import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';

/// Where a restored audit row lands.
///
/// The audit box is read by key: a report lives under
/// `audit_report_order_<orderId>` and a legacy action log under
/// `legacy_event_<micros>`. Restore used to append every row instead, which
/// filed reports where nothing looks for them — so the next write created a
/// second copy under the canonical key and the report reached Cloud as two
/// conflicting versions of itself — and hid legacy logs from the audit screen
/// altogether.
void main() {
  late Directory directory;

  Map<String, dynamic> report(int orderId, {String updatedAt = '18:02'}) {
    return <String, dynamic>{
      'reportId': AuditRepository.buildAuditReportKey(orderId),
      'orderId': orderId,
      'tableNumbers': <String>['5'],
      'floor': 'first',
      'openedById': 'staff-1',
      'openedByName': 'Nino',
      'openedAt': '2026-09-01T18:00:00.000',
      'status': 'CLOSED',
      'events': const <Map<String, dynamic>>[],
      'updatedAt': '2026-09-01T$updatedAt:00.000',
      'locked': true,
    };
  }

  Map<String, dynamic> legacyLog(String item, {String? timestamp}) {
    return <String, dynamic>{
      'actionType': 'add_item',
      'performedBy': 'Nino',
      'comment': '',
      'details': <String, dynamic>{
        'orderId': 90,
        'itemName': item,
        'previousQty': 0,
        'newQty': 1,
        'tableNumbers': <String>['7'],
        'floor': 'first',
      },
      if (timestamp != null) 'timestamp': timestamp,
    };
  }

  /// A backup payload in the current shape, keys included.
  String backupWithKeys(Map<Object, Map<String, dynamic>> rows) {
    return json.encode(<String, dynamic>{
      'auditLog': rows.values.toList(),
      'auditLogKeys': rows.keys.toList(),
    });
  }

  /// A backup payload in the old shape: values only, no keys at all.
  String legacyBackup(List<Map<String, dynamic>> rows) {
    return json.encode(<String, dynamic>{'auditLog': rows});
  }

  Future<void> restore(String payload) {
    return BackupRepository.restoreDataBackupFromJson(
      payload,
      clearExisting: false,
      backupBeforeRestore: false,
    );
  }

  /// The rows the restore put back, without the one it writes about itself.
  ///
  /// A restore is auditable, so it appends one `BACKUP_RESTORED` row of its
  /// own — deliberately after the payload, since `clearExisting` would
  /// otherwise erase it. That row is not a restored row, and counting it here
  /// would make these assertions about the audit feature rather than about
  /// where restored rows land.
  Iterable<Object> restoredKeys() {
    final box = DatabaseCore.auditLogBox!;
    return box.keys.cast<Object>().where((key) {
      final row = box.get(key);
      return !(row is Map && row['action'] == 'BACKUP_RESTORED');
    });
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-audit-keys-');
    Hive.init(directory.path);
    DatabaseCore.auditLogBox = await Hive.openBox('auditLog');
    DatabaseCore.settingsBox = await Hive.openBox('settings');
    DatabaseCore.metaBox = await Hive.openBox('meta');
    await AuditSyncState.open();
  });

  tearDown(() async {
    DatabaseCore.auditLogBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.metaBox = null;
    await AuditSyncState.close();
    await Hive.deleteFromDisk();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('a restored report occupies exactly one row, at its own key', () async {
    await restore(
      backupWithKeys({AuditRepository.buildAuditReportKey(1): report(1)}),
    );

    expect(restoredKeys(), hasLength(1));
    expect(restoredKeys().single, AuditRepository.buildAuditReportKey(1));
    // And so the normal read path finds it, rather than creating a second one.
    expect(AuditRepository.getAuditReport(1), isNotNull);
  });

  test('restoring the same backup twice leaves one logical report', () async {
    final payload = backupWithKeys({
      AuditRepository.buildAuditReportKey(1): report(1),
      AuditRepository.buildAuditReportKey(2): report(2),
      'legacy_event_1756000000111000': legacyLog(
        'Lobio',
        timestamp: '2026-08-01T10:00:00.000',
      ),
    });

    await restore(payload);
    final afterFirst = restoredKeys().length;
    await restore(payload);

    expect(restoredKeys(), hasLength(afterFirst));
    expect(
      AuditRepository.getAuditReports().map((r) => r.reportId),
      containsAll(<String>[
        AuditRepository.buildAuditReportKey(1),
        AuditRepository.buildAuditReportKey(2),
        'legacy_report_order_90',
      ]),
    );
    expect(AuditRepository.getAuditReports(), hasLength(3));
  });

  test('an existing canonical row is updated, not duplicated', () async {
    await DatabaseCore.auditLogBox!.put(
      AuditRepository.buildAuditReportKey(1),
      report(1, updatedAt: '18:02'),
    );

    await restore(
      backupWithKeys({
        AuditRepository.buildAuditReportKey(1): report(1, updatedAt: '19:30'),
      }),
    );

    expect(restoredKeys(), hasLength(1));
    expect(
      AuditRepository.getAuditReport(1)!.updatedAt,
      DateTime.parse('2026-09-01T19:30:00.000'),
    );
  });

  test(
    'a report a damaged store filed under an integer key is repaired',
    () async {
      // What the old append restore left behind: the row is in the box, but not
      // where anything reads it from.
      await DatabaseCore.auditLogBox!.add(report(1));
      expect(AuditRepository.getAuditReport(1), isNull);

      // A backup taken from that store records the integer key. The report's own
      // reportId wins over it, so the restore repairs the shape.
      await restore(backupWithKeys({0: report(1)}));

      expect(AuditRepository.getAuditReport(1), isNotNull);
      expect(AuditRepository.getAuditReports(), hasLength(1));
    },
  );

  test('a keyless older backup still restores, and stays idempotent', () async {
    final payload = legacyBackup([
      report(1),
      legacyLog('Lobio', timestamp: '2026-08-01T10:00:00.000'),
      legacyLog('Mtsvadi', timestamp: '2026-08-01T10:00:00.000'),
      legacyLog('Undated'),
      <String, dynamic>{
        'id': 'e7f1c0de-0000-4000-8000-000000000001',
        'action': 'LOGIN',
        'userId': 'staff-1',
        'data': '{}',
        'deviceType': 'windows',
        'createdAt': '2026-08-01T09:00:00.000',
        'synced': 0,
      },
    ]);

    await restore(payload);

    final box = DatabaseCore.auditLogBox!;
    expect(restoredKeys(), hasLength(5));
    // Reports and event logs land on their own identity.
    expect(box.containsKey(AuditRepository.buildAuditReportKey(1)), isTrue);
    expect(box.containsKey('e7f1c0de-0000-4000-8000-000000000001'), isTrue);
    // Legacy logs keep the prefix the audit screen and derived reports match on.
    final legacyKeys = box.keys
        .whereType<String>()
        .where((key) => key.startsWith('legacy_event_'))
        .toList();
    expect(legacyKeys, hasLength(3));
    // All three legacy logs survive — including the two that share a
    // microsecond and the undated one — and derive one report between them.
    final derived = AuditRepository.getAuditReports().firstWhere(
      (report) => report.reportId == 'legacy_report_order_90',
    );
    expect(derived.events, hasLength(3));
    // The listing still renders with an undated row in the box.
    expect(AuditRepository.getAuditLogs(), isNotEmpty);

    // Restoring the same keyless backup again changes nothing.
    await restore(payload);
    expect(restoredKeys(), hasLength(5));
    expect(
      AuditRepository.getAuditReports()
          .firstWhere((report) => report.reportId == 'legacy_report_order_90')
          .events,
      hasLength(3),
    );
  });
}
