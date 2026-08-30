import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// Task 1 (docs/VYNIC_ROADMAP.md): v4 migration + adapter round trips against
/// a real (temp-dir) Hive instance. Seeds legacy fixtures per the workflow in
/// apps/operations/docs/HIVE_MIGRATIONS.md.
void main() {
  late Directory tempDir;
  late HiveMigrationContext context;

  // Register each adapter with its concrete generic type — passing them
  // through a helper typed `TypeAdapter` would erase the generics and break
  // Hive's runtime type → adapter resolution.
  void registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MenuCategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(MenuVariantDBAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(ReservationAdapter());
    }
    if (!Hive.isAdapterRegistered(15))
      Hive.registerAdapter(SaleRecordAdapter());
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_hive_v4_test');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    context = HiveMigrationContext(
      metaBox: await Hive.openBox('meta_test'),
      userBox: await Hive.openBox<User>('users_test'),
      tableBox: await Hive.openBox<TableModel>('tables_test'),
      orderBox: await Hive.openBox<Order>('orders_test'),
      menuBox: await Hive.openBox<MenuCategoryDB>('menu_test'),
      settingsBox: await Hive.openBox('settings_test'),
      salesBox: await Hive.openBox('sales_test'),
      auditLogBox: await Hive.openBox('audit_test'),
      reservationBox: await Hive.openBox<Reservation>('reservations_test'),
    );
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('meta_test');
    await Hive.deleteBoxFromDisk('users_test');
    await Hive.deleteBoxFromDisk('tables_test');
    await Hive.deleteBoxFromDisk('orders_test');
    await Hive.deleteBoxFromDisk('menu_test');
    await Hive.deleteBoxFromDisk('settings_test');
    await Hive.deleteBoxFromDisk('sales_test');
    await Hive.deleteBoxFromDisk('audit_test');
    await Hive.deleteBoxFromDisk('reservations_test');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> legacySale({bool withFlags = false}) => {
    'orderId': 5,
    'tableNumbers': ['Table 2'],
    'floor': 'first',
    'items': [
      {'itemName': 'ოჯახური', 'quantity': 1, 'unitPrice': 18.0, 'total': 18.0},
    ],
    'totalAmount': 18.0,
    'total': 18.0,
    'paymentMethod': 'cash',
    'createdBy': 'waiter1',
    'createdAt': '2026-07-19T12:00:00.000',
    'closedAt': '2026-07-19T13:00:00.000',
    'includeServiceFee': false,
    'date': '2026-07-19',
    if (withFlags) 'isCancelled': true,
    if (withFlags) 'isFiscal': false,
    if (withFlags) 'restoredToOrder': true,
  };

  group('migrateV3toV4', () {
    test(
      'materializes missing sales flag keys with read-path defaults',
      () async {
        await context.salesBox.add(legacySale());
        await HiveMigrationService.migrateV3toV4(context);

        final migrated = Map<String, dynamic>.from(
          context.salesBox.getAt(0) as Map,
        );
        expect(migrated['isCancelled'], isFalse);
        expect(migrated['restoredToOrder'], isFalse);
        expect(migrated['isFiscal'], isTrue);
        // Every original key/value is untouched.
        for (final entry in legacySale().entries) {
          expect(migrated[entry.key], equals(entry.value), reason: entry.key);
        }
      },
    );

    test('leaves records that already carry the flags untouched', () async {
      await context.salesBox.add(legacySale(withFlags: true));
      await HiveMigrationService.migrateV3toV4(context);

      final migrated = Map<String, dynamic>.from(
        context.salesBox.getAt(0) as Map,
      );
      expect(migrated['isCancelled'], isTrue);
      expect(migrated['isFiscal'], isFalse);
      expect(migrated['restoredToOrder'], isTrue);
    });

    test('is idempotent', () async {
      await context.salesBox.add(legacySale());
      await HiveMigrationService.migrateV3toV4(context);
      final first = Map<String, dynamic>.from(context.salesBox.getAt(0) as Map);
      await HiveMigrationService.migrateV3toV4(context);
      final second = Map<String, dynamic>.from(
        context.salesBox.getAt(0) as Map,
      );
      expect(second, equals(first));
    });

    test('runPendingMigrations advances 3 → 4 exactly once', () async {
      await context.metaBox.put(HiveMigrationService.dbVersionKey, 3);
      await context.salesBox.add(legacySale());

      final version = await HiveMigrationService.runPendingMigrations(context);
      expect(version, HiveMigrationService.targetVersion);
      expect(context.metaBox.get(HiveMigrationService.dbVersionKey), 4);

      // Second run is a no-op at the current version.
      final again = await HiveMigrationService.runPendingMigrations(context);
      expect(again, 4);
    });
  });

  group('adapter round trips (behavior unchanged)', () {
    test('Order persists with null closureId by default', () async {
      final order = Order(
        orderId: 42,
        tableNumbers: ['Table 3'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'ლუდი',
            itemName: 'ლუდი',
            unitPrice: 6.0,
            quantity: 1,
            total: 6.0,
          ),
        ],
        totalAmount: 6.0,
        createdAt: DateTime(2026, 7, 20, 12),
        createdBy: 'waiter1',
      );
      await context.orderBox.add(order);

      // Force a re-read from disk through the adapter.
      await context.orderBox.flush();
      final revived = context.orderBox.getAt(0)!;
      expect(revived.closureId, isNull);
      expect(revived.orderId, 42);
      expect(revived.totalAmount, 6.0);
      expect(revived.items.single.itemName, 'ლუდი');
    });

    test('Order round-trips a set closureId', () async {
      final order = Order(
        orderId: 43,
        tableNumbers: ['Table 3'],
        floor: 'first',
        items: [],
        totalAmount: 0,
        createdAt: DateTime(2026, 7, 20, 12),
        createdBy: 'waiter1',
        closureId: 'closure-xyz',
      );
      await context.orderBox.add(order);
      await context.orderBox.flush();
      expect(context.orderBox.getAt(0)!.closureId, 'closure-xyz');
    });

    test('SaleRecord round-trips through its Hive adapter', () async {
      final salesTyped = await Hive.openBox<SaleRecord>('sales_typed_test');
      addTearDown(() => Hive.deleteBoxFromDisk('sales_typed_test'));

      final record = SaleRecord(
        closureId: 'closure-1',
        orderId: 9,
        tableNumbers: ['Table 1'],
        floor: 'first',
        items: [
          SaleRecordItem(
            itemName: 'ხინკალი',
            quantity: 5,
            unitPrice: 1.5,
            total: 7.5,
          ),
        ],
        totalAmount: 7.5,
        paymentMethod: 'cash',
        paymentBreakdown: {'cash': 7.5},
        createdBy: 'waiter1',
        createdAt: DateTime(2026, 7, 20, 12),
        closedAt: DateTime(2026, 7, 20, 13),
        includeServiceFee: false,
        subtotalAmount: 7.5,
        businessDate: '2026-07-20',
      );
      await salesTyped.add(record);
      await salesTyped.flush();

      final revived = salesTyped.getAt(0)!;
      expect(revived.closureId, 'closure-1');
      expect(revived.paymentBreakdown, {'cash': 7.5});
      expect(revived.items.single.total, 7.5);
      expect(revived.toMap(), equals(record.toMap()));
    });
  });
}
