import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/contracts/edge_command.dart';

/// What this POS has already done with a Cloud command.
enum EdgeExecutionStatus {
  /// Started in this process and not finished yet.
  running,

  /// Started in an earlier process that did not finish it.
  interrupted,
  succeeded,
  failed,
}

/// One journal row.
class EdgeExecutionEntry {
  const EdgeExecutionEntry({
    required this.commandId,
    required this.idempotencyKey,
    required this.type,
    required this.status,
    required this.firstSeenAt,
    this.completedAt,
    this.code,
  });

  final String commandId;
  final String idempotencyKey;
  final String type;
  final EdgeExecutionStatus status;
  final DateTime firstSeenAt;
  final DateTime? completedAt;
  final String? code;

  bool get isTerminal =>
      status == EdgeExecutionStatus.succeeded ||
      status == EdgeExecutionStatus.failed;
}

/// The durable record of which Cloud commands this POS has executed.
///
/// Cloud acknowledgment alone cannot protect against the sequence that actually
/// happens in a restaurant: the POS receives a command, executes it, the
/// Internet dies before the acknowledgment lands, the lease expires, and Cloud
/// offers the same command again. Without a local record the side effect
/// happens twice.
///
/// So the journal is the Edge's own answer to at-least-once delivery: a command
/// that already succeeded here is acknowledged again without being re-executed.
///
/// Stores no payloads. A command id, its idempotency key, its type and its
/// outcome are enough to decide whether to run it, and keeping the payload
/// would mean keeping whatever a future command type carries.
class EdgeCommandJournal {
  EdgeCommandJournal._();

  static const String boxName = 'edge_command_journal';

  /// Terminal entries older than this are pruned. Comfortably longer than any
  /// lease or redelivery window, short enough that the box stays small.
  static const Duration retention = Duration(days: 7);

  /// A hard ceiling in case a future command type is enqueued in bulk.
  static const int maxEntries = 5000;

  static const Uuid _uuid = Uuid();

  static Box<Map>? _box;

  /// Identifies this process run, so an entry left behind by a crash is
  /// recognisable as one rather than looking like work in progress.
  static String _runId = _uuid.v4();

  /// Opens the journal and settles anything a previous run left mid-flight.
  static Future<void> open() async {
    if (_box != null) return;
    _box = await Hive.openBox<Map>(boxName);
    _runId = _uuid.v4();
    await _settleInterrupted();
    await prune();
  }

  static bool get isOpen => _box != null;

  static Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  static EdgeExecutionEntry? entryFor(String commandId) {
    final raw = _box?.get(commandId);
    if (raw == null) return null;
    return _fromMap(Map<String, dynamic>.from(raw));
  }

  /// Records that execution is starting. Returns the entry already stored when
  /// this command has been seen before, so the caller can decide not to re-run.
  static Future<EdgeExecutionEntry?> beginExecution(
    EdgeCommandEnvelope command,
  ) async {
    final box = _box;
    if (box == null) return null;

    final existing = entryFor(command.commandId);
    if (existing != null && existing.isTerminal) return existing;

    await box.put(command.commandId, <String, dynamic>{
      'commandId': command.commandId,
      'idempotencyKey': command.idempotencyKey,
      'type': command.type,
      'status': EdgeExecutionStatus.running.name,
      'firstSeenAt':
          existing?.firstSeenAt.toIso8601String() ??
          DateTime.now().toUtc().toIso8601String(),
      'runId': _runId,
    });
    return existing;
  }

  static Future<void> completeExecution(
    String commandId, {
    required bool succeeded,
    String? code,
  }) async {
    final box = _box;
    if (box == null) return;
    final raw = box.get(commandId);
    if (raw == null) return;

    final updated = Map<String, dynamic>.from(raw)
      ..['status'] = succeeded
          ? EdgeExecutionStatus.succeeded.name
          : EdgeExecutionStatus.failed.name
      ..['completedAt'] = DateTime.now().toUtc().toIso8601String()
      ..['code'] = code;
    await box.put(commandId, updated);
  }

  /// Drops terminal entries past retention, then trims the oldest if the box
  /// somehow still exceeds its ceiling. Non-terminal entries are never pruned:
  /// they are exactly the ones a redelivery still needs to be judged against.
  static Future<void> prune() async {
    final box = _box;
    if (box == null) return;

    final cutoff = DateTime.now().toUtc().subtract(retention);
    final expired = <dynamic>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = _fromMap(Map<String, dynamic>.from(raw));
      if (!entry.isTerminal) continue;
      final finished = entry.completedAt ?? entry.firstSeenAt;
      if (finished.isBefore(cutoff)) expired.add(key);
    }
    if (expired.isNotEmpty) await box.deleteAll(expired);

    if (box.length <= maxEntries) return;
    final byAge = box.keys.toList()
      ..sort((a, b) {
        final left = _fromMap(Map<String, dynamic>.from(box.get(a)!));
        final right = _fromMap(Map<String, dynamic>.from(box.get(b)!));
        return left.firstSeenAt.compareTo(right.firstSeenAt);
      });
    await box.deleteAll(byAge.take(box.length - maxEntries));
  }

  @visibleForTesting
  static Future<void> clearForTest() async {
    await _box?.clear();
  }

  /// A `running` entry from another process run means the POS stopped between
  /// starting a command and recording its outcome. It is marked `interrupted`
  /// rather than assumed either way: the outcome genuinely is unknown, and a
  /// redelivered idempotent command may safely be executed again.
  static Future<void> _settleInterrupted() async {
    final box = _box;
    if (box == null) return;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['status'] != EdgeExecutionStatus.running.name) continue;
      if (map['runId'] == _runId) continue;
      await box.put(key, map..['status'] = EdgeExecutionStatus.interrupted.name);
    }
  }

  static EdgeExecutionEntry _fromMap(Map<String, dynamic> map) {
    return EdgeExecutionEntry(
      commandId: (map['commandId'] as String?) ?? '',
      idempotencyKey: (map['idempotencyKey'] as String?) ?? '',
      type: (map['type'] as String?) ?? '',
      status: EdgeExecutionStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => EdgeExecutionStatus.interrupted,
      ),
      firstSeenAt:
          DateTime.tryParse((map['firstSeenAt'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      completedAt: DateTime.tryParse(
        (map['completedAt'] as String?) ?? '',
      )?.toUtc(),
      code: map['code'] as String?,
    );
  }
}
