import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';

/// Which audit reports the POS sends, and when.
///
/// The behaviour this replaces re-uploaded a restaurant's entire audit history
/// every time one order changed — `Syncing 1091 / 1091 audit reports` after a
/// single edit. The property that had to hold instead is stated directly below:
/// an acknowledged history plus one change sends one report.
void main() {
  late Directory directory;

  AuditReport report(
    int orderId, {
    String openedBy = 'Nino',
    List<AuditEvent> events = const [],
    DateTime? updatedAt,
  }) {
    final at = updatedAt ?? DateTime.utc(2026, 9, 1, 18);
    return AuditReport(
      reportId: 'audit_report_order_$orderId',
      orderId: orderId,
      tableNumbers: const ['5'],
      floor: 'first',
      openedById: 'staff-1',
      openedByName: openedBy,
      openedAt: at,
      status: AuditReportStatus.open,
      events: events,
      updatedAt: at,
    );
  }

  AuditEvent event(String itemName, {int newQty = 1}) => AuditEvent(
    type: AuditEventType.addItem,
    itemName: itemName,
    previousQty: 0,
    newQty: newQty,
    waiterId: 'staff-1',
    waiterName: 'Nino',
    timestamp: DateTime.utc(2026, 9, 1, 18, 1),
  );

  /// Marks everything currently dirty as acknowledged, the way a completed
  /// backfill leaves the POS.
  Future<void> acknowledgeAll(List<AuditReport> reports) async {
    for (final entry in AuditSyncState.selectDirty(reports).dirty) {
      await AuditSyncState.markAcknowledged(entry.reportId, entry.revision);
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('audit-sync-state-');
    Hive.init(directory.path);
    await AuditSyncState.open();
  });

  tearDown(() async {
    await AuditSyncState.close();
    await Hive.deleteFromDisk();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('a fresh install has everything to send', () async {
    final reports = [report(1), report(2), report(3)];
    final selection = AuditSyncState.selectDirty(reports);

    expect(selection.dirty, hasLength(3));
    expect(selection.knownReportIds, hasLength(3));
  });

  test(
    '1091 previously acknowledged reports plus one change sends exactly one',
    () async {
      // The upgrade backfill: a real Vankisi-sized history, uploaded once.
      final history = List.generate(1091, (i) => report(i));
      expect(AuditSyncState.selectDirty(history).dirty, hasLength(1091));
      await acknowledgeAll(history);

      // Steady state. Nothing changed, so nothing is sent.
      expect(AuditSyncState.selectDirty(history).dirty, isEmpty);

      // One ordinary operation adds a line to one report.
      final changed = List<AuditReport>.from(history);
      changed[400] = report(400, events: [event('Khachapuri')]);

      final selection = AuditSyncState.selectDirty(changed);
      expect(selection.dirty, hasLength(1));
      expect(selection.dirty.single.reportId, 'audit_report_order_400');
      expect(selection.knownReportIds, hasLength(1091));
    },
  );

  test('a brand new report is sent, and the rest are not', () async {
    final history = List.generate(50, (i) => report(i));
    await acknowledgeAll(history);

    final withNewOrder = [...history, report(999)];
    final selection = AuditSyncState.selectDirty(withNewOrder);

    expect(selection.dirty, hasLength(1));
    expect(selection.dirty.single.reportId, 'audit_report_order_999');
  });

  test('an acknowledgment for revision N does not clean revision N+1', () async {
    final atRevisionN = report(7);
    final revisionN = AuditSyncState.selectDirty([atRevisionN]).dirty.single;

    // The report is edited while revision N is still in flight.
    final atRevisionNPlus1 = report(7, events: [event('Wine')]);
    expect(
      AuditSyncState.revisionOf(atRevisionNPlus1),
      isNot(revisionN.revision),
    );

    // The backend acknowledges what it was actually sent: revision N.
    await AuditSyncState.markAcknowledged(
      revisionN.reportId,
      revisionN.revision,
    );

    // The newer content is still dirty. Marking it clean here is the one bug
    // this mechanism exists to prevent — it would lose an audit edit silently.
    final selection = AuditSyncState.selectDirty([atRevisionNPlus1]);
    expect(selection.dirty, hasLength(1));
    expect(
      selection.dirty.single.revision,
      AuditSyncState.revisionOf(atRevisionNPlus1),
    );
  });

  test('an unacknowledged report stays dirty across a restart', () async {
    final reports = [report(1), report(2)];
    final first = AuditSyncState.selectDirty(reports).dirty;
    // Only the first report's acknowledgment came back before the crash.
    await AuditSyncState.markAcknowledged(first[0].reportId, first[0].revision);

    await AuditSyncState.close();
    await AuditSyncState.open();

    final resumed = AuditSyncState.selectDirty(reports);
    expect(resumed.dirty, hasLength(1));
    expect(resumed.dirty.single.reportId, 'audit_report_order_2');
  });

  test('a backfill interrupted halfway resumes where it stopped', () async {
    final history = List.generate(250, (i) => report(i));

    // Two batches of 100 acknowledged, then the backend went away.
    final dirty = AuditSyncState.selectDirty(history).dirty;
    for (final entry in dirty.take(200)) {
      await AuditSyncState.markAcknowledged(entry.reportId, entry.revision);
    }

    await AuditSyncState.close();
    await AuditSyncState.open();

    expect(AuditSyncState.selectDirty(history).dirty, hasLength(50));
  });

  test('the revision does not depend on map iteration order', () async {
    final a = report(1, events: [event('A'), event('B')]);
    final b = report(1, events: [event('A'), event('B')]);
    expect(AuditSyncState.revisionOf(a), AuditSyncState.revisionOf(b));
  });

  test('every field the report carries changes its revision', () async {
    final base = report(1);
    expect(
      AuditSyncState.revisionOf(report(1, openedBy: 'Giorgi')),
      isNot(AuditSyncState.revisionOf(base)),
    );
    expect(
      AuditSyncState.revisionOf(report(1, events: [event('Wine')])),
      isNot(AuditSyncState.revisionOf(base)),
    );
    expect(
      AuditSyncState.revisionOf(
        report(1, updatedAt: DateTime.utc(2026, 9, 1, 19)),
      ),
      isNot(AuditSyncState.revisionOf(base)),
    );
  });

  test('a report the POS no longer has stops being tracked', () async {
    final reports = [report(1), report(2)];
    await acknowledgeAll(reports);

    await AuditSyncState.pruneUnknown({'audit_report_order_1'});

    expect(
      AuditSyncState.acknowledgedRevision('audit_report_order_1'),
      isNotNull,
    );
    expect(AuditSyncState.acknowledgedRevision('audit_report_order_2'), isNull);
  });

  test(
    'the send payload carries the revision the backend must acknowledge',
    () async {
      final entry = AuditSyncState.selectDirty([report(1)]).dirty.single;
      final payload = entry.toPayload();

      expect(payload['reportId'], 'audit_report_order_1');
      expect(payload['revision'], entry.revision);
      // Still the whole report: incremental means fewer reports, not partial ones.
      expect(payload['orderId'], 1);
      expect(payload['openedByName'], 'Nino');
    },
  );
}
