import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/database/repositories/table_repository.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/contracts/table_identity.dart' as contract;
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/user.dart';

/// What a terminal starts with, on a machine that has never run it.
///
/// A POS out of the box used to come up as *this* restaurant: nine tables,
/// four VIP booths, a full menu, and a manager account called „vaanskii" — the
/// developer's own username, printed on the venue's checks as the waiter who
/// opened the table. Every venue had to delete all of it first.
///
/// The dangerous half of the change is the other direction, and that is what
/// most of this file is about: a terminal being *updated* must keep every
/// table, every dish and every open bill it already has. Getting that wrong
/// does not annoy anyone — it loses their data.

late Directory _tempDir;

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(UserAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(TableModelAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(OrderItemAdapter());
  }
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(OrderAdapter());
  }
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(MenuCategoryDBAdapter());
  }
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
  }
  if (!Hive.isAdapterRegistered(7)) {
    Hive.registerAdapter(MenuItemDBAdapter());
  }
  if (!Hive.isAdapterRegistered(8)) {
    Hive.registerAdapter(MenuVariantDBAdapter());
  }
  if (!Hive.isAdapterRegistered(9)) {
    Hive.registerAdapter(ReservationAdapter());
  }
}

/// The decision `DatabaseService.init()` makes, in isolation.
///
/// `init()` itself opens real boxes, starts sync and touches printers, so the
/// branch is reproduced here rather than driven through it — the point is the
/// condition, not the plumbing around it.
bool isFreshInstall() {
  return !SettingsRepository.isSetupComplete() &&
      DatabaseCore.userBox!.isEmpty &&
      DatabaseCore.tableBox!.isEmpty &&
      DatabaseCore.menuBox!.isEmpty;
}

Future<void> _openBoxes() async {
  DatabaseCore.settingsBox = await Hive.openBox('fi_settings');
  DatabaseCore.userBox = await Hive.openBox<User>('fi_users');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('fi_tables');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('fi_menu');
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_fresh_install');
    Hive.init(_tempDir.path);
    _registerAdapters();
  });

  setUp(() async {
    for (final name in const [
      'fi_settings',
      'fi_users',
      'fi_tables',
      'fi_menu',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    await _openBoxes();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.menuBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('a machine that has never run the POS', () {
    test('is recognised as fresh', () {
      expect(isFreshInstall(), isTrue);
    });

    test(
      'gets one account, at PIN 000000, not named after the developer',
      () async {
        await UserRepository.createDefaultAdmin();

        final user = DatabaseCore.userBox!.values.single;
        expect(user.pinCode, '000000');
        expect(user.role, 'manager');
        expect(user.username, isNot('vaanskii'));
        expect(user.username, UserRepository.defaultManagerUsername);
      },
    );

    test('the empty plan has rooms but no tables in them', () {
      // A layout with no zones gives the floor editor no canvas to draw onto,
      // so the venue would have nowhere to start.
      const plan = RestaurantTableLayouts.emptyVenue;
      expect(plan.tables, isEmpty);
      expect(plan.objects, isEmpty);
      expect(plan.zones, isNotEmpty);
    });

    test(
      'saving the empty plan is what stops the built-in tables appearing',
      () async {
        // `getRestaurantTableLayout()` falls back to the built-in thirteen-table
        // layout whenever nothing is stored. Leaving the setting unset would draw
        // a floor plan full of tables this venue does not have.
        await SettingsRepository.saveActiveTableLayout(
          RestaurantTableLayouts.emptyVenue,
        );

        expect(TableRepository.getRestaurantTableLayout().tables, isEmpty);
      },
    );

    test('and no table rows are created for them', () async {
      await SettingsRepository.saveActiveTableLayout(
        RestaurantTableLayouts.emptyVenue,
      );
      await TableRepository.initializeTables();

      expect(DatabaseCore.tableBox!.isEmpty, isTrue);
    });
  });

  group('a terminal being updated, not installed', () {
    setUp(() async {
      // Everything a working venue has: staff, tables, a menu.
      await DatabaseCore.userBox!.add(
        User(username: 'გიორგი', pinCode: '1234', role: 'waiter'),
      );
      await DatabaseCore.tableBox!.add(
        TableModel(tableNumber: '7', floor: 'first'),
      );
      await DatabaseCore.menuBox!.add(
        MenuCategoryDB(
          slug: 'hot',
          translationsEn: const {'name': 'Hot'},
          translationsKa: const {'name': 'ცხელი'},
        ),
      );
    });

    test('is never mistaken for a fresh one', () {
      expect(isFreshInstall(), isFalse);
    });

    test('is not sent through setup on update', () async {
      // It has a floor, a menu and staff already. A „name your restaurant"
      // wizard on update would be a locked door in front of a working POS.
      await SettingsRepository.markSetupComplete();
      expect(SettingsRepository.isSetupComplete(), isTrue);
    });

    test('keeps its tables — the empty plan is never written over them', () {
      expect(DatabaseCore.tableBox!.values.single.tableNumber, '7');
      expect(TableRepository.getRestaurantTableLayout().tables, isNotEmpty);
    });

    test(
      'backfills table UUIDs once and persists them across restart reads',
      () async {
        await TableRepository.ensureCanonicalTableIdentity();
        final firstRead = TableRepository.getRestaurantTableLayout();
        final firstIds = firstRead.tables.map((table) => table.id).toList();

        expect(firstIds, isNotEmpty);
        expect(firstIds.every(contract.isCanonicalTableId), isTrue);
        expect(
          firstRead.tables.map((table) => table.legacyTableNumber),
          RestaurantTableLayouts.current.tables.map(
            (table) => table.legacyTableNumber,
          ),
        );

        await TableRepository.ensureCanonicalTableIdentity();
        final secondIds = TableRepository.getRestaurantTableLayout().tables
            .map((table) => table.id)
            .toList();
        expect(secondIds, firstIds);
      },
    );

    test(
      'a venue that customised its plan keeps that, not the empty one',
      () async {
        const custom = RestaurantTableLayout(
          id: 'custom',
          name: 'Ours',
          zones: [
            RestaurantZone(
              id: 'z',
              name: 'ტერასა',
              legacyFloor: 'first',
              displayOrder: 1,
              renderMode: TableLayoutRenderMode.floorPlan,
            ),
          ],
          tables: [
            RestaurantTableDefinition(
              id: 'z-1',
              zoneId: 'z',
              legacyFloor: 'first',
              legacyTableNumber: '1',
              label: 'ფანჯარასთან',
              capacity: 4,
              sortOrder: 1,
            ),
          ],
        );
        await SettingsRepository.saveActiveTableLayout(custom);

        final loaded = TableRepository.getRestaurantTableLayout();
        expect(loaded.tables.single.label, 'ფანჯარასთან');
      },
    );

    test('one empty box does not make an install look fresh', () async {
      // A venue that deleted every category to re-enter its menu still has
      // staff and tables. Treating that as a first run would blank its floor.
      await DatabaseCore.menuBox!.clear();
      expect(isFreshInstall(), isFalse);
    });
  });

  test('the empty plan survives being written and read back', () async {
    // It goes through the settings box as JSON like any other layout.
    await SettingsRepository.saveActiveTableLayout(
      RestaurantTableLayouts.emptyVenue,
    );
    final raw =
        DatabaseCore.settingsBox!.get('activeTableLayoutJson') as String;

    final decoded = RestaurantTableLayout.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(decoded.tables, isEmpty);
    expect(decoded.zones.single.legacyFloor, 'first');
  });
}
