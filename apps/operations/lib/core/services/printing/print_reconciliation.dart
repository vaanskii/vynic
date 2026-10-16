import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'print_job.dart';
import 'print_queue.dart';

enum PrintReconciliationPolicy { unconfigured, administrators, printingStaff }

/// The owner must choose the operator policy. Until then the journal is
/// readable, but no action can manufacture a paper confirmation/reprint.
class PrintReconciliation {
  PrintReconciliation._();
  static PrintReconciliationPolicy policy =
      PrintReconciliationPolicy.unconfigured;

  static bool get allowed {
    final user = PosSession.user;
    if (user == null || policy == PrintReconciliationPolicy.unconfigured)
      return false;
    return policy == PrintReconciliationPolicy.printingStaff || user.isManager;
  }

  static User _actor({PrintReconciliationPolicy? actionPolicy}) {
    final session = PosSession.user;
    if (session == null)
      throw StateError('Sign in before reconciling print jobs');
    final users = DatabaseService.getAllUsers().where(
      (u) => u.username == session.username,
    );
    if (users.length != 1)
      throw StateError('Current staff identity is unavailable');
    final user = users.single;
    final effectivePolicy = actionPolicy ?? policy;
    if (effectivePolicy == PrintReconciliationPolicy.unconfigured ||
        effectivePolicy == PrintReconciliationPolicy.administrators &&
            !user.isManager)
      throw StateError('This staff member cannot reconcile print jobs');
    return user;
  }

  static void _reason(String reason) {
    if (reason.trim().length < 3 || reason.length > 500)
      throw ArgumentError('Record a reason between 3 and 500 characters');
  }

  static User authorizeCopy(String reason) {
    _reason(reason);
    return _actor();
  }

  // User-approved kitchen copies need no free-text reason. Other actions retain
  // the owner's policy, including receipt copies and paper confirmation.
  static const kitchenCopyReason = 'Operator requested kitchen reprint';
  static String productionCopyReason(PrintQueueTarget target) =>
      switch (target) {
        PrintQueueTarget.kitchen => kitchenCopyReason,
        PrintQueueTarget.bar => 'Operator requested bar reprint',
        PrintQueueTarget.additional =>
          'Operator requested additional station reprint',
        PrintQueueTarget.receipt => throw StateError(
          'Receipt copies require the owner policy',
        ),
      };

  static bool get kitchenCopyAllowed => PosSession.user != null;

  static User authorizeKitchenCopy() =>
      _actor(actionPolicy: PrintReconciliationPolicy.printingStaff);

  static PrintJob _job(String id) {
    final job = PrintJobRepository.read(id);
    if (job == null) throw StateError('Print job not found');
    if (job.venueId != EdgeDeviceCredentialStore.venueId)
      throw StateError(
        'Enroll this terminal in the backup Venue before reconciling its print jobs',
      );
    return job;
  }

  static Future<void> confirm(
    PrintJob expected,
    String reason,
    String requestId,
  ) => LocalDataAdmission.mutate(() async {
    final actor = _actor();
    _reason(reason);
    final job = _job(expected.id);
    if (_already(job, requestId, actor.username, reason, 'confirmed')) return;
    if (job.attemptId != expected.attemptId ||
        job.state != expected.state ||
        !(job.state == PrintJobState.sent ||
            job.state == PrintJobState.uncertain))
      throw StateError(
        'This attempt is not awaiting paper reconciliation; refresh the list',
      );
    await PrintJobRepository.transition(
      job.id,
      job.attemptId,
      job.state,
      PrintJobState.confirmed,
      actorId: actor.username,
      reason: reason.trim(),
      actionId: requestId,
      detail: 'Paper output checked by an operator',
    );
  });

  static Future<void> reprint(
    PrintJob expected,
    String reason,
    String requestId,
  ) => LocalDataAdmission.mutate(() async {
    final job = _job(expected.id);
    final kitchen = job.target != PrintQueueTarget.receipt;
    final actor = kitchen ? authorizeKitchenCopy() : _actor();
    _reason(reason);
    if (!_already(job, requestId, actor.username, reason, 'reprint')) {
      if (job.state != expected.state)
        throw StateError('Print status changed; refresh the list');
      await PrintJobRepository.reprint(
        job.id,
        expected.attemptId,
        requestId,
        actor.username,
        reason.trim(),
      );
    }
    PrintQueue.wake();
  });

  static Future<void> retryNotSent(
    PrintJob expected,
    String reason,
    String requestId,
  ) => LocalDataAdmission.mutate(() async {
    final actor = _actor();
    _reason(reason);
    final job = _job(expected.id);
    final next = job.attempts.length == 1
        ? PrintJobState.queued
        : PrintJobState.reprint;
    if (!_already(job, requestId, actor.username, reason, next.name)) {
      if (job.attemptId != expected.attemptId ||
          job.state != PrintJobState.failed)
        throw StateError('Only an attempt that wrote no bytes can be retried');
      await PrintJobRepository.transition(
        job.id,
        job.attemptId,
        PrintJobState.failed,
        next,
        actorId: actor.username,
        reason: reason.trim(),
        actionId: requestId,
        detail: 'Operator requested retry after no-byte connection failure',
      );
    }
    PrintQueue.wake();
  });

  static bool _already(
    PrintJob job,
    String id,
    String actor,
    String reason,
    String action,
  ) {
    final events = job.audit.where(
      (e) =>
          e['actionId'] == id ||
          e['action'] == 'reprint' &&
              e['attemptId'] == id &&
              e['actionId'] == null,
    );
    if (events.isEmpty) return false;
    final event = events.single;
    if (event['actorId'] != actor ||
        event['reason'] != reason.trim() ||
        event['action'] != action)
      throw StateError('Print action identity reused with different content');
    return true;
  }
}
