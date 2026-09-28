import 'dart:convert';

import 'package:hive/hive.dart';

/// Durable POS Menu mutation journal (docs/CANONICAL_MENU_SYNC.md).
///
/// Every local Menu edit is committed to the operational menu FIRST and then
/// recorded here, in order, before any network attempt. The journal lives in
/// Hive, so it survives app restart, Windows restart and days of backend
/// outage. Cloud acceptance only decides global convergence; it never decides
/// whether this POS may keep operating with its local change.
enum MenuMutationStatus {
  /// Recorded locally, not yet accepted by Cloud.
  pending,

  /// Accepted by Cloud (kept briefly for diagnostics).
  synced,

  /// Cloud holds a newer revision of the same node; the operator decides.
  conflict,

  /// Cloud refused the change itself (e.g. its parent was deleted elsewhere).
  rejected,

  /// A transient failure (offline, 5xx); retried in order.
  failedRetryable,
}

class MenuMutationEntry {
  MenuMutationEntry({
    required this.seq,
    required this.mutationId,
    required this.venueId,
    required this.entityType,
    required this.operation,
    required this.entityId,
    required this.expectedRevision,
    required this.patch,
    required this.status,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.conflict,
    this.resolution,
  });

  final int seq;
  final String mutationId;
  final String venueId;
  final String entityType;
  final String operation;
  final String entityId;
  int expectedRevision;
  final Map<String, Object?> patch;
  MenuMutationStatus status;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  /// Server conflict detail: current node/revision, deleted flag.
  Map<String, dynamic>? conflict;

  /// `REAPPLY` when this entry re-applies a change after a conflict.
  final String? resolution;

  /// Still part of the local projection and not yet converged.
  bool get unresolved => status != MenuMutationStatus.synced;

  bool get sendable =>
      status == MenuMutationStatus.pending ||
      status == MenuMutationStatus.failedRetryable;

  Map<String, Object?> toWire() => {
    'mutationId': mutationId,
    'entityType': entityType,
    'operation': operation,
    'entityId': entityId,
    'expectedRevision': expectedRevision,
    if (operation != 'DELETE') 'patch': patch,
    if (resolution != null) 'resolution': resolution,
  };

  Map<String, Object?> toJson() => {
    ...toWire(),
    'seq': seq,
    'venueId': venueId,
    'patch': patch,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
    'lastError': lastError,
    'conflict': conflict,
  };

  static MenuMutationEntry fromJson(Map<String, dynamic> json) =>
      MenuMutationEntry(
        seq: (json['seq'] as num).toInt(),
        mutationId: json['mutationId'] as String,
        venueId: json['venueId'] as String,
        entityType: json['entityType'] as String,
        operation: json['operation'] as String,
        entityId: json['entityId'] as String,
        expectedRevision: (json['expectedRevision'] as num).toInt(),
        patch: Map<String, Object?>.from(json['patch'] as Map? ?? const {}),
        status: MenuMutationStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
        conflict: json['conflict'] == null
            ? null
            : Map<String, dynamic>.from(json['conflict'] as Map),
        resolution: json['resolution'] as String?,
      );
}

class MenuMutationJournal {
  MenuMutationJournal(this.box);

  final Box<String> box;

  static String _key(int seq) => seq.toString().padLeft(12, '0');

  /// All entries in local order.
  List<MenuMutationEntry> all() {
    final keys = box.keys.cast<String>().toList()..sort();
    return [
      for (final key in keys)
        MenuMutationEntry.fromJson(
          jsonDecode(box.get(key)!) as Map<String, dynamic>,
        ),
    ];
  }

  List<MenuMutationEntry> unresolved() =>
      all().where((entry) => entry.unresolved).toList();

  int _nextSeq() {
    final keys = box.keys.cast<String>().toList()..sort();
    return keys.isEmpty ? 1 : int.parse(keys.last) + 1;
  }

  Future<MenuMutationEntry> append({
    required String mutationId,
    required String venueId,
    required String entityType,
    required String operation,
    required String entityId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    String? resolution,
  }) async {
    final entry = MenuMutationEntry(
      seq: _nextSeq(),
      mutationId: mutationId,
      venueId: venueId,
      entityType: entityType,
      operation: operation,
      entityId: entityId,
      expectedRevision: expectedRevision,
      patch: patch,
      status: MenuMutationStatus.pending,
      createdAt: DateTime.now().toUtc(),
      resolution: resolution,
    );
    await save(entry);
    return entry;
  }

  Future<void> save(MenuMutationEntry entry) async {
    await box.put(_key(entry.seq), jsonEncode(entry.toJson()));
    await box.flush();
  }

  Future<void> remove(MenuMutationEntry entry) async {
    await box.delete(_key(entry.seq));
    await box.flush();
  }

  /// Keeps only the most recent synced entries for diagnostics.
  Future<void> compact({int keepSynced = 50}) async {
    final synced = all()
        .where((e) => e.status == MenuMutationStatus.synced)
        .toList();
    if (synced.length <= keepSynced) return;
    for (final entry in synced.take(synced.length - keepSynced)) {
      await box.delete(_key(entry.seq));
    }
    await box.flush();
  }
}
