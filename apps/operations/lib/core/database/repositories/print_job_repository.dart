import 'package:flutter/foundation.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'dart:convert';
import 'package:vynic/core/services/printing/optional_printer_beep.dart';

/// Additive v1 rows in the existing format-2 `meta` store (Hive remains v9).
/// Each job includes all attempts and their audit, so reprint admission is one
/// flushed row, rather than two independently committed parent/child rows.
class PrintJobRepository {
  PrintJobRepository._();
  static const prefix = 'print_job:v1:';
  static bool knownKey(String key) =>
      key.startsWith(prefix) || key.startsWith('print_job:v2:');
  static final changes = ValueNotifier<int>(0);
  static String? failure;
  static String? optionalSignalFailure;
  static String key(String id, {int protocol = PrintJob.protocol}) =>
      'print_job:v$protocol:$id';

  static PrintJob decode(dynamic key, dynamic value) {
    final job = PrintJob.decode(value);
    if (key != PrintJobRepository.key(job.id, protocol: job.protocolVersion))
      throw const FormatException('Print job key/identity disagrees');
    return job;
  }

  static List<PrintJob> all() {
    final box = DatabaseCore.metaBox;
    if (box == null || !box.isOpen) return const [];
    final jobs = <PrintJob>[];
    for (final k in box.keys) {
      if (k is! String || !k.startsWith('print_job:')) continue;
      if (!knownKey(k))
        throw const FormatException('Unknown print job protocol');
      jobs.add(decode(k, box.get(k)));
    }
    jobs.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    if (jobs.map((job) => job.id).toSet().length != jobs.length) {
      throw StateError('Print job has conflicting protocol identities');
    }
    return jobs;
  }

  static PrintJob? read(String id) {
    final matches = <PrintJob>[];
    for (final protocol in [PrintJob.protocol, PrintJob.routedProtocol]) {
      final k = key(id, protocol: protocol);
      final raw = DatabaseCore.metaBox?.get(k);
      if (raw != null) matches.add(decode(k, raw));
    }
    if (matches.length > 1)
      throw StateError('Print job has conflicting protocol identities');
    return matches.isEmpty ? null : matches.single;
  }

  static Future<void> _save(PrintJob job, {bool optionalSignal = false}) async {
    final box = DatabaseCore.metaBox;
    if (box == null || !box.isOpen)
      throw StateError('Print persistence is unavailable');
    try {
      await box.put(key(job.id, protocol: job.protocolVersion), job.toMap());
      await box.flush();
      changes.value++;
    } catch (error) {
      if (optionalSignal) {
        optionalSignalFailure = 'Optional printer signal audit failed: $error';
      } else {
        failure = 'Print job persistence failed: $error';
      }
      changes.value++;
      rethrow;
    }
  }

  static Future<PrintJob> enqueue(
    PrintJob job,
  ) => LocalDataAdmission.mutate(() async {
    if (failure != null) throw StateError(failure!);
    final existing = read(job.id);
    if (existing != null) {
      final a = existing.toMap(), b = job.toMap();
      for (final field in [
        'protocol',
        'target',
        'host',
        'port',
        'label',
        'venueId',
        'payloadSha256',
        'copyOf',
        'requiresConfirmedOrderUuid',
        'printerId',
        'routeRevision',
      ]) {
        if (a[field] != b[field])
          throw StateError('Print job identity reused with different content');
      }
      if (existing.destination.identity != job.destination.identity) {
        throw StateError(
          'Print job identity reused with a different destination',
        );
      }
      if (jsonEncode(existing.capabilityProfile.toMap()) !=
          jsonEncode(job.capabilityProfile.toMap())) {
        throw StateError(
          'Print job identity reused with different capabilities',
        );
      }
      final oldAdmission = existing.audit.first, newAdmission = job.audit.first;
      for (final field in ['actorId', 'reason']) {
        if (oldAdmission[field] != newAdmission[field]) {
          throw StateError(
            'Print copy identity reused with different operator evidence',
          );
        }
      }
      return existing;
    }
    await _save(job);
    return job;
  });

  static Future<PrintJob> transition(
    String id,
    String attemptId,
    PrintJobState expected,
    PrintJobState state, {
    String? detail,
    String? actorId,
    String? reason,
    String? actionId,
  }) => LocalDataAdmission.mutate(() async {
    final job = read(id);
    if (job == null || job.attemptId != attemptId || job.state != expected)
      throw StateError('Print attempt changed; refresh before acting');
    final body = job.toMap();
    final now = DateTime.now().toUtc().toIso8601String();
    (body['attempts'] as List).last['state'] = state.name;
    if (detail != null) (body['attempts'] as List).last['detail'] = detail;
    (body['audit'] as List).add({
      'action': state.name,
      'at': now,
      'attemptId': attemptId,
      if (detail != null) 'detail': detail,
      if (actorId != null) 'actorId': actorId,
      if (reason != null) 'reason': reason,
      if (actionId != null) 'actionId': actionId,
    });
    final next = PrintJob.decode(body);
    await _save(next);
    return next;
  });

  static Future<PrintJob> reprint(
    String id,
    String expectedAttemptId,
    String requestId,
    String actorId,
    String reason,
  ) => LocalDataAdmission.mutate(() async {
    final job = read(id);
    if (job == null) throw StateError('Print job not found');
    final previous = job.attempts.where((a) => a['id'] == requestId);
    if (previous.isNotEmpty) {
      final a = previous.single;
      if (a['actorId'] != actorId || a['reason'] != reason)
        throw StateError(
          'Reprint identity reused with different operator/reason',
        );
      return job;
    }
    if (job.attemptId != expectedAttemptId ||
        job.ready ||
        job.state == PrintJobState.sending ||
        job.state == PrintJobState.failed)
      throw StateError(
        'Print attempt changed or has not been sent; refresh before reprinting',
      );
    final body = job.toMap();
    final now = DateTime.now().toUtc().toIso8601String();
    (body['attempts'] as List).add({
      'id': requestId,
      'state': 'reprint',
      'queuedAt': now,
      'actorId': actorId,
      'reason': reason,
    });
    (body['audit'] as List).add({
      'action': 'reprint',
      'at': now,
      'attemptId': requestId,
      'actorId': actorId,
      'reason': reason,
    });
    final next = PrintJob.decode(body);
    await _save(next);
    return next;
  });

  /// Optional signals have an independent spent reservation. A process dying
  /// after this flush never replays sound or changes the primary paper result.
  static Future<bool> reserveBeep(String id, String attemptId) =>
      LocalDataAdmission.mutate(() async {
        final job = read(id);
        if (job == null ||
            job.attemptId != attemptId ||
            job.protocolVersion != PrintJob.routedProtocol ||
            job.state != PrintJobState.sent ||
            job.latest.containsKey('beep'))
          return false;
        final body = job.toMap();
        body['attempts'].last['beep'] = {
          'state': 'reserved',
          'reservedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _save(PrintJob.decode(body), optionalSignal: true);
        return true;
      });

  static Future<void> settleBeep(String id, PrinterBeepResult result) =>
      LocalDataAdmission.mutate(() async {
        final job = read(id);
        if (job == null)
          throw StateError('Optional print signal job disappeared');
        final body = job.toMap();
        final attempts = (body['attempts'] as List).where(
          (attempt) => attempt['id'] == result.attemptId,
        );
        if (attempts.length != 1 ||
            attempts.single['beep']?['state'] != 'reserved') {
          throw StateError('Optional print signal reservation changed');
        }
        if (result.state == PrinterBeepState.skipped) {
          throw StateError('A reserved signal cannot be silently skipped');
        }
        attempts.single['beep'].addAll({
          'state': result.state.name,
          'settledAt': DateTime.now().toUtc().toIso8601String(),
          'detail': result.detail.length <= 4000
              ? result.detail
              : result.detail.substring(0, 4000),
        });
        await _save(PrintJob.decode(body), optionalSignal: true);
      });

  /// Startup/restore never resends an attempt that crossed the send boundary.
  /// Portable queued jobs are held too: their source may still be operating.
  static Future<void> recover({
    bool restored = false,
    bool underExclusive = false,
  }) async {
    Future<void> run() async {
      failure = null;
      final jobs = all(); // Validate every row before changing anything.
      for (final job in jobs) {
        final foreign = job.venueId != EdgeDeviceCredentialStore.venueId;
        if (job.state == PrintJobState.sending ||
            (restored || foreign) && job.ready) {
          await transition(
            job.id,
            job.attemptId,
            job.state,
            PrintJobState.uncertain,
            detail: restored
                ? 'Restored from backup; check the source terminal and paper before reprinting'
                : foreign
                ? 'Venue binding is unavailable or different; automatic delivery held'
                : 'Process stopped during transmission; paper outcome is unknown',
          );
        }
      }
      changes.value++;
    }

    if (underExclusive) {
      await run();
    } else {
      await LocalDataAdmission.exclusive(
        run,
        recovery: true,
        operation: 'print recovery',
      );
    }
  }
}
