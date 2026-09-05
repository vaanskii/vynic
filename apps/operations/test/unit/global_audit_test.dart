import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/database/repositories/package_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/global_audit_entry.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

/// Phase 4: the restaurant-wide accountability log.
///
/// An Order has its own report. Everything else a restaurant does to itself —
/// hiring, pricing, packages, expenses, closing the day, restoring a backup —
/// had no record at all, or had one nobody could read. These are the writers.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-05';

  const boxes = [
    'ga_settings',
    'ga_audit',
    'ga_users',
    'ga_menu',
    'ga_packages',
    'ga_expenses',
    'ga_sales',
    'ga_orders',
    'ga_tables',
    'ga_reservations',
    'ga_quick',
    'ga_errors',
    'ga_meta',
  ];

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
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(PackageAdapter());
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PackageItemAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(SaleRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(QuickOrderDraftAdapter());
    }
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_global_audit');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('ga_settings');
    DatabaseCore.auditLogBox = await Hive.openBox('ga_audit');
    DatabaseCore.userBox = await Hive.openBox<User>('ga_users');
    DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('ga_menu');
    DatabaseCore.packageBox = await Hive.openBox<Package>('ga_packages');
    DatabaseCore.expenseBox = await Hive.openBox('ga_expenses');
    DatabaseCore.salesBox = await Hive.openBox('ga_sales');
    DatabaseCore.orderBox = await Hive.openBox<Order>('ga_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('ga_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'ga_reservations',
    );
    DatabaseCore.quickOrderBox = await Hive.openBox<QuickOrderDraft>('ga_quick');
    DatabaseCore.errorLogBox = await Hive.openBox('ga_errors');
    DatabaseCore.metaBox = await Hive.openBox('ga_meta');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '${businessDate}T00:00:00.000',
    );
  });

  tearDown(() async {
    for (final name in boxes) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.menuBox = null;
    DatabaseCore.packageBox = null;
    DatabaseCore.expenseBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.reservationBox = null;
    DatabaseCore.quickOrderBox = null;
    DatabaseCore.errorLogBox = null;
    DatabaseCore.metaBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  /// The venue-wide feed, exactly as both audit screens read it.
  List<GlobalAuditEntry> feed({String? action, String? entityType}) {
    final entries = <GlobalAuditEntry>[];
    for (final raw in DatabaseCore.auditLogBox!.values) {
      if (raw is! Map) continue;
      if (raw['reportId'] != null) continue;
      if (raw['action'] == null || raw['id'] == null) continue;
      final entry = GlobalAuditEntry.fromLocal(
        AuditEventLog.fromMap(Map<String, dynamic>.from(raw)),
      );
      if (action != null && entry.action != action) continue;
      if (entityType != null && entry.entityType != entityType) continue;
      entries.add(entry);
    }
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }

  GlobalAuditEntry one({required String action}) {
    final matches = feed(action: action);
    expect(matches, hasLength(1), reason: 'expected exactly one $action');
    return matches.single;
  }

  group('staff', () {
    test('a hire, a rename, a role change and a removal are all recorded', () async {
      await UserRepository.addUser(
        username: 'nika',
        pinCode: '111111',
        role: 'waiter',
        actorId: 'avtandil',
      );
      await UserRepository.renameUserByUsername(
        oldUsername: 'nika',
        newUsername: 'nika_k',
        actorId: 'avtandil',
      );
      await UserRepository.updateUserRoleByUsername(
        username: 'nika_k',
        role: 'supervisor',
        actorId: 'avtandil',
      );
      await UserRepository.deleteUserByUsername(
        'nika_k',
        actorId: 'avtandil',
      );

      final created = one(action: GlobalAuditAction.staffCreated);
      expect(created.entityType, GlobalAuditEntity.staff);
      expect(created.entityId, 'nika');
      expect(created.actorName, 'avtandil');
      expect(created.source, 'POS');
      expect(created.businessDate, businessDate);

      final renamed = one(action: GlobalAuditAction.staffUpdated);
      expect(renamed.entityId, 'nika_k');
      expect(renamed.changes.single.field, 'username');
      expect(renamed.changes.single.previousValue, 'nika');
      expect(renamed.changes.single.newValue, 'nika_k');

      final roleChanged = one(action: GlobalAuditAction.staffRoleChanged);
      expect(roleChanged.entityId, 'nika_k');
      expect(roleChanged.changes.single.previousValue, 'waiter');
      expect(roleChanged.changes.single.newValue, 'supervisor');
      // Which is what the reader renders as `Role: waiter → supervisor`.
      expect(
        GlobalAuditPresentation.changeLine(roleChanged.changes.single),
        'Role: waiter → supervisor',
      );

      final deleted = one(action: GlobalAuditAction.staffDeleted);
      expect(deleted.entityId, 'nika_k');
      expect(deleted.data['role'], 'supervisor');
    });

    test('a PIN change records that it happened and never the PIN', () async {
      await UserRepository.addUser(
        username: 'nika',
        pinCode: '111111',
        role: 'waiter',
        actorId: 'avtandil',
      );
      await UserRepository.updateUserPinByUsername(
        username: 'nika',
        pinCode: '999999',
        actorId: 'avtandil',
      );

      final changed = one(action: GlobalAuditAction.staffPinChanged);
      expect(changed.entityId, 'nika');
      expect(changed.data['changed'], isTrue);

      // The whole audit box, encoded: neither PIN appears anywhere in it. The
      // log syncs to Cloud and is read by managers; a credential in it would be
      // a leak wearing an accountability costume.
      final everything = jsonEncode(
        DatabaseCore.auditLogBox!.values.toList(),
      );
      expect(everything.contains('111111'), isFalse);
      expect(everything.contains('999999'), isFalse);
    });

    test('re-saving the same role or PIN records nothing', () async {
      await UserRepository.addUser(
        username: 'nika',
        pinCode: '111111',
        role: 'waiter',
        actorId: 'avtandil',
      );
      await UserRepository.updateUserRoleByUsername(
        username: 'nika',
        role: 'waiter',
        actorId: 'avtandil',
      );
      await UserRepository.updateUserPinByUsername(
        username: 'nika',
        pinCode: '111111',
        actorId: 'avtandil',
      );
      await UserRepository.renameUserByUsername(
        oldUsername: 'nika',
        newUsername: 'nika',
        actorId: 'avtandil',
      );

      expect(feed(action: GlobalAuditAction.staffRoleChanged), isEmpty);
      expect(feed(action: GlobalAuditAction.staffPinChanged), isEmpty);
      expect(feed(action: GlobalAuditAction.staffUpdated), isEmpty);
    });

    test('a Manager-relayed change records the channel it arrived through', () async {
      await UserRepository.addUser(
        username: 'nika',
        pinCode: '111111',
        role: 'waiter',
        actorId: 'mobile_manager',
        source: AuditSource.manager,
      );
      expect(one(action: GlobalAuditAction.staffCreated).source, 'MANAGER');
    });
  });

  group('menu', () {
    Future<void> seedCategory() => MenuRepository.addCategory(
      slug: 'hot',
      nameEn: 'Hot',
      nameKa: 'ცხელი',
      actorId: 'nino',
    );

    test('a category and an item are recorded on creation', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );

      final category = one(action: GlobalAuditAction.menuCategoryCreated);
      expect(category.entityType, GlobalAuditEntity.menuCategory);
      expect(category.entityId, DatabaseCore.menuBox!.getAt(0)!.id);
      expect(category.data['categoryName'], 'hot');

      final item = one(action: GlobalAuditAction.menuItemCreated);
      expect(item.entityType, GlobalAuditEntity.menuItem);
      // Identity is the item's own stable id; the tree path is context.
      expect(item.entityId, DatabaseCore.menuBox!.getAt(0)!.items!.single.id);
      expect(item.data['treePath'], 'hot/Khinkali');
      expect(item.entityLabel, 'ხინკალი');
      expect(item.data['price'], 2.0);
    });

    test('a price change is queryable as a previous/new pair', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );
      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.5,
        actorId: 'nino',
      );

      final updated = one(action: GlobalAuditAction.menuItemUpdated);
      expect(
        updated.entityId,
        DatabaseCore.menuBox!.getAt(0)!.items!.single.id,
      );
      expect(updated.changes.single.field, 'price');
      expect(
        GlobalAuditPresentation.changeLine(updated.changes.single),
        'Price: 2.00 → 2.50',
      );
    });

    test('a kitchen-routing change is recorded as its own field', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Coke',
        nameKa: 'კოკა',
        price: 3.0,
        sendToKitchen: true,
        actorId: 'nino',
      );
      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Coke',
        nameKa: 'კოკა',
        price: 3.0,
        sendToKitchen: false,
        actorId: 'nino',
      );

      final updated = one(action: GlobalAuditAction.menuItemUpdated);
      expect(updated.changes.map((c) => c.field), ['sendToKitchen']);
      expect(updated.changes.single.newValue, isFalse);
    });

    test('an edit that changed nothing records nothing', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );
      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );

      expect(feed(action: GlobalAuditAction.menuItemUpdated), isEmpty);
    });

    test('a deletion names what was removed', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );
      await MenuRepository.deleteItemFromCategory(
        categoryIndex: 0,
        itemIndex: 0,
        actorId: 'nino',
      );

      final deleted = one(action: GlobalAuditAction.menuItemDeleted);
      expect(deleted.data['treePath'], 'hot/Khinkali');
      expect(deleted.entityId, isNot('hot/Khinkali'));
      expect(deleted.data['price'], 2.0);
    });

    test('a subcategory is a category node, told apart by nodeKind', () async {
      await seedCategory();
      await MenuRepository.addSubcategory(
        categoryIndex: 0,
        slug: 'soups',
        nameEn: 'Soups',
        nameKa: 'სუპები',
        actorId: 'nino',
      );

      // The parent category's own creation row is the first; the subcategory
      // is the second, told apart by `nodeKind` rather than by its own action.
      final created = feed(action: GlobalAuditAction.menuCategoryCreated).last;
      expect(created.data['nodeKind'], 'SUBCATEGORY');
      expect(created.data['parentCategoryName'], 'hot');
      expect(
        created.entityId,
        DatabaseCore.menuBox!.getAt(0)!.subcategories!.single.id,
      );
    });
  });

  group('packages', () {
    Future<Package> createPackage() => PackageRepository.createPackage(
      name: 'Banquet',
      items: [
        PackageItem(
          itemKey: 'k1',
          itemName: 'Khinkali',
          quantity: 5,
          unitPrice: 2,
        ),
      ],
      pricePerPerson: 45,
      servingSize: 10,
      createdBy: 'nino',
    );

    test('a definition is recorded when created, changed and deleted', () async {
      final package = await createPackage();
      await PackageRepository.updatePackage(
        packageId: package.packageId,
        name: 'Banquet',
        items: package.items,
        pricePerPerson: 50,
        servingSize: 10,
        actorId: 'nino',
      );
      await PackageRepository.setPackageActive(
        packageId: package.packageId,
        isActive: false,
        actorId: 'nino',
      );
      await PackageRepository.deletePackage(
        package.packageId,
        actorId: 'nino',
      );

      final created = one(action: GlobalAuditAction.packageCreated);
      expect(created.entityType, GlobalAuditEntity.package);
      expect(created.entityId, package.packageId);
      expect(created.entityLabel, 'Banquet');

      final updates = feed(action: GlobalAuditAction.packageUpdated);
      expect(updates, hasLength(2));
      expect(updates.first.changes.single.field, 'pricePerPerson');
      expect(updates.first.changes.single.newValue, 50);
      // Disabling is the same configuration change, named by the field that
      // moved rather than by a second action.
      expect(updates.last.changes.single.field, 'isActive');
      expect(updates.last.changes.single.newValue, isFalse);

      final deleted = one(action: GlobalAuditAction.packageDeleted);
      expect(deleted.entityId, package.packageId);
    });

    test('a save that changed nothing records nothing', () async {
      final package = await createPackage();
      await PackageRepository.updatePackage(
        packageId: package.packageId,
        name: 'Banquet',
        items: package.items,
        pricePerPerson: 45,
        servingSize: 10,
        actorId: 'nino',
      );
      expect(feed(action: GlobalAuditAction.packageUpdated), isEmpty);
    });
  });

  group('expenses', () {
    test('a new expense is recorded with its figure and category', () async {
      await SalesRepository.saveExpenseRecord(
        description: 'Napkins',
        amount: 120,
        category: 'Supplies',
        actorId: 'nino',
      );

      final created = one(action: GlobalAuditAction.expenseCreated);
      expect(created.entityType, GlobalAuditEntity.expense);
      expect(created.data['amount'], 120.0);
      expect(created.data['category'], 'Supplies');
      expect(created.data['expenseBusinessDate'], businessDate);
    });

    test('a redelivered expense is one expense, and one audit row', () async {
      const id = 'expense-from-cloud-1';
      await SalesRepository.saveExpenseRecord(
        description: 'Napkins',
        amount: 120,
        category: 'Supplies',
        sourceId: id,
        actorId: 'mobile_manager',
        source: AuditSource.manager,
      );
      await SalesRepository.saveExpenseRecord(
        description: 'Napkins',
        amount: 120,
        category: 'Supplies',
        sourceId: id,
        actorId: 'mobile_manager',
        source: AuditSource.manager,
      );

      expect(DatabaseCore.expenseBox!.length, 1);
      expect(feed(action: GlobalAuditAction.expenseCreated), hasLength(1));
    });
  });

  group('close day', () {
    test('a completed close records the day it closed and the next one', () async {
      final closed = await CloseDayTransaction.run(actorId: 'nino');
      expect(closed, isTrue);

      final completed = one(action: GlobalAuditAction.closeDayCompleted);
      expect(completed.entityType, GlobalAuditEntity.closeDay);
      expect(completed.entityId, businessDate);
      expect(completed.data['nextBusinessDate'], '2026-09-06');
      expect(completed.actorName, 'nino');
      expect(feed(action: GlobalAuditAction.closeDayBlocked), isEmpty);
    });

    test('a refused close records what stopped it', () async {
      final order = Order(
        orderId: 1,
        tableNumbers: const ['5'],
        floor: 'first',
        items: const [],
        totalAmount: 0,
        createdAt: DateTime.parse('${businessDate}T18:00:00.000'),
        createdBy: 'nino',
        status: 'confirmed',
      );
      await DatabaseCore.orderBox!.add(order);

      final closed = await CloseDayTransaction.run(actorId: 'nino');
      expect(closed, isFalse);

      final blocked = one(action: GlobalAuditAction.closeDayBlocked);
      expect(blocked.entityId, businessDate);
      expect(blocked.data['blockedBy'], 'ACTIVE_ORDERS');
      expect(blocked.data['blockerCount'], 1);
      expect(feed(action: GlobalAuditAction.closeDayCompleted), isEmpty);
      // And the day did not move.
      expect(
        DatabaseCore.settingsBox!.get('currentDate'),
        '${businessDate}T00:00:00.000',
      );
    });
  });

  group('backup', () {
    test('an Admin restore leaves a record of itself', () async {
      final payload = jsonEncode(<String, dynamic>{
        'generatedAt': '2026-09-01T10:00:00.000',
        'meta': <String, dynamic>{'db_version': 6},
        'users': <dynamic>[],
        'auditLog': <dynamic>[],
      });

      await BackupRepository.restoreDataBackupFromJson(
        payload,
        clearExisting: true,
        backupBeforeRestore: false,
        actorId: 'avtandil',
      );

      final restored = one(action: GlobalAuditAction.backupRestored);
      expect(restored.entityType, GlobalAuditEntity.backup);
      expect(restored.entityId, '2026-09-01T10:00:00.000');
      expect(restored.data['backupVersion'], '6');
      expect(restored.actorName, 'avtandil');
      // Never the backup's contents — that is the whole restaurant, and it
      // belongs in the file rather than in a log row.
      expect(restored.data.containsKey('auditLog'), isFalse);
      expect(restored.data.containsKey('users'), isFalse);
    });

    test('the record survives a restore that clears the audit box', () async {
      // The row is written after the payload precisely because `clearExisting`
      // empties the box the row lives in.
      await DatabaseCore.auditLogBox!.put('leftover', <String, dynamic>{
        'id': 'leftover',
        'action': 'ORDER_CREATED',
        'userId': 'nino',
        'data': '{}',
        'deviceType': 'windows',
        'createdAt': '2026-09-01T09:00:00.000',
        'synced': 0,
      });

      await BackupRepository.restoreDataBackupFromJson(
        jsonEncode(<String, dynamic>{'auditLog': <dynamic>[]}),
        clearExisting: true,
        backupBeforeRestore: false,
        actorId: 'avtandil',
      );

      expect(DatabaseCore.auditLogBox!.containsKey('leftover'), isFalse);
      expect(feed(action: GlobalAuditAction.backupRestored), hasLength(1));
    });
  });

  group('historical compatibility', () {
    test('a row written before entity identity still reads as what it is', () {
      // Exactly the shape history holds: no entityType, no entityId.
      DatabaseCore.auditLogBox!.put('legacy-1', <String, dynamic>{
        'id': 'legacy-1',
        'action': 'reservation_cancelled',
        'userId': 'nino',
        'data': jsonEncode(<String, dynamic>{
          'reservationId': 'res-9',
          'customerName': 'Tamar',
        }),
        'deviceType': 'windows',
        'createdAt': '2026-08-01T10:00:00.000',
        'synced': 0,
      });

      final entry = feed().single;
      expect(entry.entityType, GlobalAuditEntity.reservation);
      expect(entry.entityId, 'res-9');
      expect(entry.entityLabel, 'Tamar');
      expect(
        GlobalAuditPresentation.actionLabel(entry.action),
        'Reservation cancelled',
      );

      // Derived on read. The stored row is not rewritten.
      final stored = DatabaseCore.auditLogBox!.get('legacy-1') as Map;
      expect(stored.containsKey('entityType'), isFalse);
    });

    test('an action this build has never heard of is shown, not hidden', () {
      DatabaseCore.auditLogBox!.put('unknown-1', <String, dynamic>{
        'id': 'unknown-1',
        'action': 'SOME_FUTURE_ACTION',
        'userId': 'nino',
        'data': '{}',
        'deviceType': 'windows',
        'createdAt': '2026-08-01T10:00:00.000',
        'synced': 0,
      });

      final entry = feed().single;
      expect(entry.entityType, isNull);
      expect(GlobalAuditPresentation.actionLabel(entry.action),
          'SOME_FUTURE_ACTION');
    });
  });
}
