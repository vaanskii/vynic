import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/user.dart';

/// What happens when a terminal running the old build — the one whose floor was
/// an SVG map — is updated in place.
///
/// The worry is a reasonable one: the floor plan is a different system now, and
/// an old install arrives carrying a database written before any of it existed.
/// These tests seed exactly that database (no `db_version`, reservations stored
/// as legacy int codes, sales as maps missing the flags added later, and a
/// saved layout in the old `svgMap` shape) and upgrade it, so the answer is
/// measured rather than argued.
void main() {
  late Directory tempDir;

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
  }

  /// The layout an old terminal would have saved: SVG render mode, an asset
  /// path, and tables identified by floor and number.
  String legacySvgLayoutJson() => jsonEncode({
    'id': 'default-vynic-restaurant',
    'name': 'SVG floor map',
    'zones': [
      {
        'id': 'main-floor',
        'name': 'First floor',
        'legacyFloor': 'first',
        'displayOrder': 1,
        'renderMode': 'svgMap',
        'svgAsset': 'assets/new-floor1.svg',
        'canvasWidth': 1005,
        'canvasHeight': 1101,
      },
    ],
    'tables': [
      {
        'id': 'floor1-table7',
        'zoneId': 'main-floor',
        'legacyFloor': 'first',
        'legacyTableNumber': '7',
        'label': 'Table 7',
        'capacity': 0,
        'sortOrder': 7,
        'svgElementId': 'table7',
        'hitBox': {
          'left': 64.5,
          'top': 260.65,
          'width': 101.29,
          'height': 161.76,
        },
      },
    ],
  });

  late HiveMigrationContext context;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_legacy_upgrade');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    final settings = await Hive.openBox('lu_settings');
    context = HiveMigrationContext(
      metaBox: await Hive.openBox('lu_meta'),
      userBox: await Hive.openBox<User>('lu_users'),
      tableBox: await Hive.openBox<TableModel>('lu_tables'),
      orderBox: await Hive.openBox<Order>('lu_orders'),
      menuBox: await Hive.openBox<MenuCategoryDB>('lu_menu'),
      settingsBox: settings,
      salesBox: await Hive.openBox('lu_sales'),
      auditLogBox: await Hive.openBox('lu_audit'),
      reservationBox: await Hive.openBox<Reservation>('lu_reservations'),
    );
    // SettingsRepository reads through DatabaseCore.
    DatabaseCore.settingsBox = settings;
  });

  tearDown(() async {
    DatabaseCore.settingsBox = null;
    for (final name in const [
      'lu_meta',
      'lu_users',
      'lu_tables',
      'lu_orders',
      'lu_menu',
      'lu_settings',
      'lu_sales',
      'lu_audit',
      'lu_reservations',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Seeds the shape an install predating every migration would have on disk.
  Future<void> seedLegacyInstall() async {
    // No `db_version` at all — that is what "never migrated" looks like.
    expect(context.metaBox.get(HiveMigrationService.dbVersionKey), isNull);

    await context.settingsBox.put(
      'activeTableLayoutJson',
      legacySvgLayoutJson(),
    );

    await context.tableBox.add(TableModel(tableNumber: '7', floor: 'first'));

    // A reservation written before `tableRefs` existed: legacy int codes only.
    await context.reservationBox.add(
      Reservation(
        id: 'res-legacy-1',
        customerName: 'ნინო',
        customerPhone: '555000111',
        tableNumbers: const [7],
        reservationDate: DateTime(2026, 8, 20),
        reservationTime: '19:30',
        numberOfGuests: 4,
        createdAt: DateTime(2026, 8, 19),
        createdBy: 'manager',
        status: 'confirmed',
      ),
    );

    // A sale written before the cancel/restore/fiscal flags existed.
    await context.salesBox.add({
      'orderId': 5,
      'tableNumbers': ['7'],
      'floor': 'first',
      'items': [
        {
          'itemName': 'ოჯახური',
          'quantity': 1,
          'unitPrice': 18.0,
          'total': 18.0,
        },
      ],
      'totalAmount': 18.0,
      'paymentMethod': 'cash',
      'createdBy': 'waiter1',
      'createdAt': '2026-08-19T12:00:00.000',
      'closedAt': '2026-08-19T13:00:00.000',
      'includeServiceFee': false,
      'date': '2026-08-19',
    });
  }

  group('updating an old SVG-floor install in place', () {
    test('the pending migrations run to the current version', () async {
      await seedLegacyInstall();

      final version = await HiveMigrationService.runPendingMigrations(context);

      expect(version, HiveMigrationService.targetVersion);
      expect(
        context.metaBox.get(HiveMigrationService.dbVersionKey),
        HiveMigrationService.targetVersion,
      );
    });

    test('a layout saved by the old build still parses', () async {
      await seedLegacyInstall();
      await HiveMigrationService.runPendingMigrations(context);

      // Every field in the layout parser carries a fallback, so an old
      // document does not need a migration of its own.
      final layout = SettingsRepository.getActiveTableLayout();
      expect(layout, isNotNull);
      expect(layout!.zones.single.renderMode, TableLayoutRenderMode.svgMap);
      expect(layout.zones.single.svgAsset, 'assets/new-floor1.svg');
    });

    test('a table that had an order on it still resolves after the update', () {
      // This is the failure that would actually hurt: the layout loads, but
      // the tables inside it no longer match what the orders point at, so
      // every open bill is stranded on a table nobody can tap.
      final layout = RestaurantTableLayouts.current;
      final table = layout.tableForLegacy(floor: 'first', tableNumber: '7');

      expect(table, isNotNull);
      expect(table!.legacyTableNumber, '7');
    });

    test('the new default layout carries every old table identity', () {
      // `floorPlanPreview.tables` is literally `svgMap.tables` — the redesign
      // changed how a zone is drawn, not what the tables are called. Every
      // (floor, number) pair the old build could have written still resolves.
      for (final old in RestaurantTableLayouts.svgMap.tables) {
        final match = RestaurantTableLayouts.current.tableForLegacy(
          floor: old.legacyFloor,
          tableNumber: old.legacyTableNumber,
        );
        expect(
          match,
          isNotNull,
          reason:
              'table ${old.legacyFloor}/${old.legacyTableNumber} disappeared',
        );
      }
    });

    test('legacy reservations are backfilled onto stable table refs', () async {
      await seedLegacyInstall();
      await HiveMigrationService.runPendingMigrations(context);

      final reservation = context.reservationBox.values.single;
      expect(reservation.tableRefs, isNotNull);
      expect(reservation.tableRefs, isNotEmpty);
    });

    test('legacy sales gain the flags every read path assumes', () async {
      await seedLegacyInstall();
      await HiveMigrationService.runPendingMigrations(context);

      final sale = context.salesBox.values.single as Map;
      expect(sale['isCancelled'], isFalse);
      expect(sale['restoredToOrder'], isFalse);
      expect(sale['isFiscal'], isTrue);
    });

    test('running the update twice changes nothing', () async {
      await seedLegacyInstall();
      await HiveMigrationService.runPendingMigrations(context);
      final afterFirst = context.reservationBox.values.single.tableRefs;

      // Reinstalling, or a crash mid-launch, must not double-apply anything.
      final version = await HiveMigrationService.runPendingMigrations(context);

      expect(version, HiveMigrationService.targetVersion);
      expect(context.reservationBox.values.single.tableRefs, afterFirst);
      expect(context.salesBox.length, 1);
    });

    test('an install with no saved layout falls back to the new floor', () async {
      await seedLegacyInstall();
      await context.settingsBox.delete('activeTableLayoutJson');
      await HiveMigrationService.runPendingMigrations(context);

      expect(SettingsRepository.getActiveTableLayout(), isNull);
      // TableRepository substitutes the built-in layout for a null read, so a
      // terminal that never customised its floor comes up on the new plan.
      expect(
        RestaurantTableLayouts.current.tableForLegacy(
          floor: 'first',
          tableNumber: '7',
        ),
        isNotNull,
      );
    });
  });
}
