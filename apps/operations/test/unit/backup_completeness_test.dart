import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// A backup has to come back as the same restaurant.
///
/// The settings block used to name seven keys, so everything added after it
/// was written — the floor plan, the printer list, the report configuration,
/// the destructive-action password — was dropped without a word. The restore
/// looked successful and the table layout was gone.

late Directory _tempDir;

/// Settings the POS writes that the old seven-key block never captured.
const _settingsThatMustSurvive = <String, Object>{
  'activeTableLayoutJson': '{"id":"floor-plan","zones":[],"tables":[]}',
  'printersList': ['kitchen:192.168.1.50', 'bar:192.168.1.51'],
  'posUiScalePercent': 90,
  'posUiDensity': 'compact',
  'posTableTileSize': 'large',
  'posFloorPlanGrid': false,
  'posFullscreenMode': true,
  'posSidebarDefault': 'expanded',
  'posDisplayMode': 'fixed',
  'restrictTableCloseToOwner': true,
  'receiptShowServiceFeeLine': false,
  'monthlyReportLeaseCost': 2500.0,
  'monthlyReportStaffDailyCost': 180.0,
  'monthlyReportFoodProfitRatio': 0.34,
  'destructivePasswordHash': 'abc123',
  'destructivePasswordSalt': 'saltysalt',
  'backendUrlOverride': 'https://pos.example.com',
  'operatedBusinessDates': ['2026-08-01', '2026-08-02'],
  'kitchenRoutingDefaultsVersion': 3,
};

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

Future<void> _openBoxes() async {
  DatabaseCore.userBox = await Hive.openBox<User>('bk_users');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('bk_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('bk_orders');
  DatabaseCore.packageBox = await Hive.openBox<Package>('bk_packages');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('bk_menu');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('bk_res');
  DatabaseCore.quickOrderBox = await Hive.openBox<QuickOrderDraft>('bk_quick');
  DatabaseCore.settingsBox = await Hive.openBox('bk_settings');
  DatabaseCore.salesBox = await Hive.openBox('bk_sales');
  DatabaseCore.expenseBox = await Hive.openBox('bk_expenses');
  DatabaseCore.auditLogBox = await Hive.openBox('bk_audit');
  DatabaseCore.errorLogBox = await Hive.openBox('bk_errors');
  DatabaseCore.metaBox = await Hive.openBox('bk_meta');
}

Future<Map<String, dynamic>> _backupPayload() async {
  final file = File('${_tempDir.path}/backup.json');
  await BackupRepository.createDataBackup(targetFilePath: file.path);
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

void main() {
  setUpAll(() async {
    // The curated settings block reads printer defaults through dotenv.
    dotenv.loadFromString(envString: 'POS_ENV=test');
    _tempDir = await Directory.systemTemp.createTemp('vynic_backup');
    DatabaseCore.dataDirectoryPath = _tempDir.path;
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _openBoxes();
  });

  tearDownAll(() async {
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await DatabaseCore.settingsBox!.clear();
    for (final entry in _settingsThatMustSurvive.entries) {
      await DatabaseCore.settingsBox!.put(entry.key, entry.value);
    }
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      DateTime(2026, 8, 22).toIso8601String(),
    );
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 10.0);
  });

  test('every box in the database has a slot in the backup', () async {
    final payload = await _backupPayload();

    for (final section in const [
      'meta',
      'settings',
      'settingsAll',
      'users',
      'tables',
      'orders',
      'packages',
      'reservations',
      'quickOrders',
      'menu',
      'sales',
      'expenses',
      'auditLog',
      'errorLog',
      'currentDate',
    ]) {
      expect(payload.containsKey(section), isTrue, reason: section);
    }
  });

  test('default backup path uses the resolved database directory', () async {
    final backup = await BackupRepository.createDataBackup();

    expect(
      backup.path,
      startsWith('${DatabaseCore.dataDirectoryPath}${Platform.pathSeparator}'),
    );
    expect(backup.path, contains('${Platform.pathSeparator}backups'));
    expect(backup.path, isNot(contains('DatabaseCore.dataDirectoryPath')));
  });

  test(
    'every setting is captured, not just the seven that were named',
    () async {
      final payload = await _backupPayload();
      final all = payload['settingsAll'] as Map<String, dynamic>;

      for (final entry in _settingsThatMustSurvive.entries) {
        expect(
          all.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} is not in the backup',
        );
      }
      // The floor plan in particular: losing it means losing every table's
      // position, capacity and name.
      expect(
        all['activeTableLayoutJson'],
        _settingsThatMustSurvive['activeTableLayoutJson'],
      );
      expect(all['printersList'], _settingsThatMustSurvive['printersList']);
      expect(all['posUiScalePercent'], 90);
      expect(all['monthlyReportFoodProfitRatio'], 0.34);
    },
  );

  test('a restore brings every setting back', () async {
    final payload = await _backupPayload();

    // Wipe the lot, as a restore onto a fresh terminal would find it.
    await DatabaseCore.settingsBox!.clear();
    expect(DatabaseCore.settingsBox!.keys, isEmpty);

    await BackupRepository.restoreDataBackupFromJson(
      jsonEncode(payload),
      backupBeforeRestore: false,
    );

    for (final entry in _settingsThatMustSurvive.entries) {
      expect(
        DatabaseCore.settingsBox!.get(entry.key),
        entry.value,
        reason: '${entry.key} did not survive the round trip',
      );
    }
  });

  test('the payload is plain JSON all the way down', () async {
    // Written with JsonEncoder, so anything unencodable would throw at backup
    // time rather than at restore time. Re-encoding proves the round trip.
    final payload = await _backupPayload();
    expect(() => jsonEncode(payload), returnsNormally);
  });
}
