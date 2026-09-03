import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';

/// Whether a report's content settles.
///
/// The incremental sync only sends what changed, but "changed" is decided by
/// hashing what the producer hands over — so a producer that hands over
/// something slightly different every time keeps a report dirty forever. That
/// is what a steady `batch of 16 report(s)` after every small operation looks
/// like: sixteen reports whose content could never be acknowledged, riding
/// along with whatever actually changed.
///
/// These tests read the same untouched audit history twice through the real
/// repository and require the revisions to match.
void main() {
  late Directory directory;

  Map<String, dynamic> storedReport(
    int orderId, {
    String? openedAt = '2026-09-01T18:00:00.000',
    String? updatedAt = '2026-09-01T18:02:00.000',
    List<Map<String, dynamic>> events = const [],
  }) {
    return <String, dynamic>{
      'reportId': AuditRepository.buildAuditReportKey(orderId),
      'orderId': orderId,
      'tableNumbers': <String>['5'],
      'floor': 'first',
      'openedById': 'staff-1',
      'openedByName': 'Nino',
      if (openedAt != null) 'openedAt': openedAt,
      'status': 'CLOSED',
      'events': events,
      if (updatedAt != null) 'updatedAt': updatedAt,
      'locked': true,
    };
  }

  Map<String, dynamic> storedEvent({String? timestamp}) {
    return <String, dynamic>{
      'type': 'ADD_ITEM',
      'itemName': 'Khachapuri',
      'previousQty': 0,
      'newQty': 1,
      'waiterId': 'staff-1',
      'waiterName': 'Nino',
      if (timestamp != null) 'timestamp': timestamp,
    };
  }

  Map<String, dynamic> legacyLog(int orderId, {String? timestamp}) {
    return <String, dynamic>{
      'actionType': 'add_item',
      'performedBy': 'Nino',
      'comment': '',
      'details': <String, dynamic>{
        'orderId': orderId,
        'itemName': 'Lobio',
        'previousQty': 0,
        'newQty': 2,
        'tableNumbers': <String>['7'],
        'floor': 'first',
      },
      if (timestamp != null) 'timestamp': timestamp,
    };
  }

  /// Every report the producer currently reports, by id, with its revision.
  Map<String, String> revisions() {
    return <String, String>{
      for (final report in AuditRepository.getAuditReports())
        report.reportId: AuditSyncState.revisionOf(report),
    };
  }

  Future<void> acknowledgeEverything() async {
    for (final entry in AuditSyncState.selectDirty(
      AuditRepository.getAuditReports(),
    ).dirty) {
      await AuditSyncState.markAcknowledged(entry.reportId, entry.revision);
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('audit-revision-');
    Hive.init(directory.path);
    DatabaseCore.auditLogBox = await Hive.openBox('auditLog');
    DatabaseCore.settingsBox = await Hive.openBox('settings');
    await AuditSyncState.open();
  });

  tearDown(() async {
    DatabaseCore.auditLogBox = null;
    DatabaseCore.settingsBox = null;
    await AuditSyncState.close();
    await Hive.deleteFromDisk();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test(
    'reading an untouched history twice produces the same revisions',
    () async {
      final box = DatabaseCore.auditLogBox!;
      // A well-formed report.
      await box.put(
        AuditRepository.buildAuditReportKey(1),
        storedReport(
          1,
          events: [storedEvent(timestamp: '2026-09-01T18:01:00.000')],
        ),
      );
      // A report written before the current shape: no opened/updated time.
      await box.put(
        AuditRepository.buildAuditReportKey(2),
        storedReport(2, openedAt: null, updatedAt: null),
      );
      // A report whose event carries no time of its own.
      await box.put(
        AuditRepository.buildAuditReportKey(3),
        storedReport(3, events: [storedEvent()]),
      );
      // A report derived from legacy logs, one dated and one not.
      await box.put(
        'legacy_event_1756000000000000',
        legacyLog(4, timestamp: '2026-08-01T10:00:00.000'),
      );
      await box.put('legacy_event_1756000000111000', legacyLog(5));

      final first = revisions();
      expect(first, hasLength(5));

      // Nothing happened in between. A second read must see the same reports.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(revisions(), first);
    },
  );

  test('a report with no usable time reads as unknown, not as now', () async {
    await DatabaseCore.auditLogBox!.put(
      AuditRepository.buildAuditReportKey(1),
      storedReport(1, openedAt: null, updatedAt: null),
    );

    final report = AuditRepository.getAuditReports().single;
    expect(report.openedAt, unknownAuditTimestamp);
    expect(report.updatedAt, unknownAuditTimestamp);
  });

  test(
    'an undated legacy log is timed from its own key, not the clock',
    () async {
      // legacy_event_<microsecondsSinceEpoch>, written when the action happened.
      const micros = 1756000000111000;
      await DatabaseCore.auditLogBox!.put('legacy_event_$micros', legacyLog(5));

      final report = AuditRepository.getAuditReports().single;
      expect(
        report.events.single.timestamp,
        DateTime.fromMicrosecondsSinceEpoch(micros),
      );
    },
  );

  test(
    'one report stored under two keys is listed once, latest wins',
    () async {
      // What a backup restore leaves behind: rows re-added under fresh integer
      // keys, while later writes go to the report's own key.
      await DatabaseCore.auditLogBox!.add(
        storedReport(1, updatedAt: '2026-09-01T18:02:00.000'),
      );
      await DatabaseCore.auditLogBox!.put(
        AuditRepository.buildAuditReportKey(1),
        storedReport(1, updatedAt: '2026-09-01T19:30:00.000'),
      );

      final reports = AuditRepository.getAuditReports();
      expect(reports, hasLength(1));
      expect(
        reports.single.updatedAt,
        DateTime.parse('2026-09-01T19:30:00.000'),
      );

      // And so the same report is never offered twice in one batch, which only
      // one of the two copies could ever be acknowledged for.
      final selection = AuditSyncState.selectDirty(reports);
      expect(selection.dirty, hasLength(1));
    },
  );

  test(
    'an acknowledged history plus one changed report sends only that report',
    () async {
      final box = DatabaseCore.auditLogBox!;
      for (var orderId = 1; orderId <= 40; orderId++) {
        await box.put(
          AuditRepository.buildAuditReportKey(orderId),
          storedReport(
            orderId,
            // A representative spread of the shapes a real history holds,
            // including the ones that used to be permanently dirty.
            openedAt: orderId % 4 == 0 ? null : '2026-09-01T18:00:00.000',
            updatedAt: orderId % 5 == 0 ? null : '2026-09-01T18:02:00.000',
            events: orderId % 3 == 0
                ? [storedEvent()]
                : [storedEvent(timestamp: '2026-09-01T18:01:00.000')],
          ),
        );
      }
      for (var orderId = 41; orderId <= 45; orderId++) {
        await box.put(
          'legacy_event_17560000001${orderId}000',
          legacyLog(orderId),
        );
      }

      await acknowledgeEverything();

      // Steady state: the backfill drained and nothing is outstanding.
      expect(
        AuditSyncState.selectDirty(AuditRepository.getAuditReports()).dirty,
        isEmpty,
      );

      // One small operational change: an item added to one open order.
      final target = AuditRepository.buildAuditReportKey(17);
      await AuditRepository.saveAuditReport(
        AuditReport.fromMap(
          Map<dynamic, dynamic>.from(DatabaseCore.auditLogBox!.get(target)),
        ).copyWith(
          events: [
            AuditEvent(
              type: AuditEventType.addItem,
              itemName: 'Wine',
              previousQty: 0,
              newQty: 1,
              waiterId: 'staff-1',
              waiterName: 'Nino',
              timestamp: DateTime.parse('2026-09-01T20:15:00.000'),
            ),
          ],
          updatedAt: DateTime.parse('2026-09-01T20:15:00.000'),
        ),
      );

      final selection = AuditSyncState.selectDirty(
        AuditRepository.getAuditReports(),
      );
      expect(selection.dirty.map((entry) => entry.reportId), [target]);
      expect(selection.dirty.single.isNew, isFalse);
    },
  );

  test('acknowledged reports are still clean after a restart', () async {
    final box = DatabaseCore.auditLogBox!;
    await box.put(
      AuditRepository.buildAuditReportKey(1),
      storedReport(1, openedAt: null, updatedAt: null),
    );
    await box.put('legacy_event_1756000000111000', legacyLog(2));
    await acknowledgeEverything();

    // Close everything the way a POS shutdown does, then come back up.
    await AuditSyncState.close();
    await box.close();
    DatabaseCore.auditLogBox = await Hive.openBox('auditLog');
    await AuditSyncState.open();

    expect(
      AuditSyncState.selectDirty(AuditRepository.getAuditReports()).dirty,
      isEmpty,
    );
  });
}
