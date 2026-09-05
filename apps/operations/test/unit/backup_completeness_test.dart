import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
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
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(MenuCategoryDBAdapter());
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
    Hive.registerAdapter(MenuItemDBAdapter());
    Hive.registerAdapter(MenuVariantDBAdapter());
  }
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(PackageAdapter());
    Hive.registerAdapter(PackageItemAdapter());
  }
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
  DatabaseCore.inventoryBox = await Hive.openBox('bk_inventory');
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

  test('the backup records the key each audit row was stored under', () async {
    // Restore has to put an audit row back where the code reads it from: a
    // report under `audit_report_order_<id>`, a legacy action log under
    // `legacy_event_<micros>`. The old payload carried values only, so a
    // restore had nowhere to put them and appended instead — filing a report
    // where nothing looks for it and hiding legacy logs from the audit screen.
    await DatabaseCore.auditLogBox!.clear();
    await DatabaseCore.auditLogBox!.put('audit_report_order_7', {
      'reportId': 'audit_report_order_7',
      'orderId': 7,
      'status': 'CLOSED',
      'events': const <Map<String, dynamic>>[],
    });
    await DatabaseCore.auditLogBox!.put('legacy_event_1756000000111000', {
      'actionType': 'add_item',
      'performedBy': 'Nino',
      'timestamp': '2026-08-01T10:00:00.000',
      'details': const {'orderId': 7},
    });

    final payload = await _backupPayload();
    final rows = payload['auditLog'] as List;
    final keys = payload['auditLogKeys'] as List;

    expect(keys, hasLength(rows.length));
    expect(keys, contains('audit_report_order_7'));
    expect(keys, contains('legacy_event_1756000000111000'));
    // Index-aligned, so row i belongs at key i.
    final index = keys.indexOf('audit_report_order_7');
    expect((rows[index] as Map)['reportId'], 'audit_report_order_7');

    await DatabaseCore.auditLogBox!.clear();
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
      'inventoryCatalog',
      'sales',
      'expenses',
      'auditLog',
      'errorLog',
      'currentDate',
    ]) {
      expect(payload.containsKey(section), isTrue, reason: section);
    }
  });

  test('Inventory projection keeps stable identities through backup restore', () async {
    await InventoryRepository.replaceCatalog({
      'generatedAt': '2026-09-05T10:00:00Z',
      'stockItems': [
        {
          'id': 'stock-stable-1',
          'name': 'Flour',
          'baseUnit': 'kg',
          'createdAt': '2026-09-05T10:00:00Z',
          'updatedAt': '2026-09-05T10:00:00Z',
        },
      ],
      'suppliers': [
        {
          'id': 'supplier-stable-1',
          'name': 'Mill',
          'createdAt': '2026-09-05T10:00:00Z',
          'updatedAt': '2026-09-05T10:00:00Z',
        },
      ],
    });
    final payload = await _backupPayload();
    await DatabaseCore.inventoryBox!.clear();

    await BackupRepository.restoreDataBackupFromJson(jsonEncode(payload));

    expect(InventoryRepository.getStockItems().single.id, 'stock-stable-1');
    expect(InventoryRepository.getSuppliers().single.id, 'supplier-stable-1');
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

  test(
    'order and package line menu identities survive backup restore',
    () async {
      await DatabaseCore.orderBox!.clear();
      await DatabaseCore.packageBox!.clear();
      final order = Order(
        orderId: 17,
        tableNumbers: const ['4'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'lemonade|0.5',
            itemName: 'Lemonade 0.5L',
            unitPrice: 5,
            quantity: 2,
            total: 10,
            menuItemId: 'menu-lemonade',
            variantId: 'variant-half-litre',
          ),
        ],
        totalAmount: 10,
        createdAt: DateTime(2026, 8, 22, 12),
        createdBy: 'Nino',
        packageId: 'package-banquet',
        packageItems: [
          OrderItem(
            itemKey: 'water|1',
            itemName: 'Water 1L',
            unitPrice: 3,
            quantity: 1,
            total: 3,
            menuItemId: 'menu-water',
            variantId: 'variant-one-litre',
          ),
        ],
      );
      final package = Package(
        packageId: 'package-banquet',
        name: 'Banquet',
        items: [
          PackageItem(
            itemKey: 'water|1',
            itemName: 'Water 1L',
            quantity: 1,
            unitPrice: 3,
            menuItemId: 'menu-water',
            variantId: 'variant-one-litre',
          ),
        ],
        pricePerPerson: 40,
        createdAt: DateTime(2026, 8, 22),
        createdBy: 'Nino',
        servingSize: 10,
      );
      await DatabaseCore.orderBox!.put(order.orderId, order);
      await DatabaseCore.packageBox!.put(package.packageId, package);

      final payload = await _backupPayload();
      final orderJson = (payload['orders'] as List).single as Map;
      final packageJson = (payload['packages'] as List).single as Map;
      expect(
        (orderJson['items'] as List).single['menuItemId'],
        'menu-lemonade',
      );
      expect(
        (orderJson['packageItems'] as List).single['variantId'],
        'variant-one-litre',
      );
      expect((packageJson['items'] as List).single['menuItemId'], 'menu-water');

      await DatabaseCore.orderBox!.clear();
      await DatabaseCore.packageBox!.clear();
      await BackupRepository.restoreDataBackupFromJson(
        jsonEncode(payload),
        backupBeforeRestore: false,
      );

      final restoredOrder = DatabaseCore.orderBox!.values.single;
      final restoredPackage = DatabaseCore.packageBox!.values.single;
      expect(restoredOrder.items.single.menuItemId, 'menu-lemonade');
      expect(restoredOrder.items.single.variantId, 'variant-half-litre');
      expect(restoredOrder.packageItems.single.menuItemId, 'menu-water');
      expect(restoredOrder.packageItems.single.variantId, 'variant-one-litre');
      expect(restoredPackage.items.single.menuItemId, 'menu-water');
      expect(restoredPackage.items.single.variantId, 'variant-one-litre');
    },
  );

  test('the payload is plain JSON all the way down', () async {
    // Written with JsonEncoder, so anything unencodable would throw at backup
    // time rather than at restore time. Re-encoding proves the round trip.
    final payload = await _backupPayload();
    expect(() => jsonEncode(payload), returnsNormally);
  });
}
