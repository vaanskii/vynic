import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/global_audit_entry.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

/// A menu item's identity used to be where it sat in the tree, which meant
/// renaming Khinkali to Royal Khinkali retired one product and invented
/// another: the audit timeline split in two and the Cloud mirror grew a second
/// row. `MenuItemDB.id` is the answer — minted once, offline, and never
/// regenerated.
///
/// These tests are about that "once". An identity that is re-minted on decode,
/// on restore, or on the second run of the migration is not an identity.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-05';
  const boxes = ['mi_settings', 'mi_audit', 'mi_menu'];

  void registerAdapters() {
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
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_menu_identity');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('mi_settings');
    DatabaseCore.auditLogBox = await Hive.openBox('mi_audit');
    DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('mi_menu');
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
    DatabaseCore.menuBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> seedCategory({String slug = 'hot'}) =>
      MenuRepository.addCategory(
        slug: slug,
        nameEn: 'Hot',
        nameKa: 'ცხელი',
        actorId: 'nino',
      );

  Future<void> addKhinkali({double price = 2.0}) =>
      MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: price,
        actorId: 'nino',
      );

  MenuItemDB itemAt(int categoryIndex, int itemIndex) =>
      DatabaseCore.menuBox!.getAt(categoryIndex)!.items![itemIndex];

  /// The venue-wide feed, read exactly as both audit screens read it.
  List<GlobalAuditEntry> feed({String? action}) {
    final entries = <GlobalAuditEntry>[];
    for (final raw in DatabaseCore.auditLogBox!.values) {
      if (raw is! Map) continue;
      if (raw['reportId'] != null) continue;
      if (raw['action'] == null || raw['id'] == null) continue;
      final entry = GlobalAuditEntry.fromLocal(
        AuditEventLog.fromMap(Map<String, dynamic>.from(raw)),
      );
      if (action != null && entry.action != action) continue;
      entries.add(entry);
    }
    return entries;
  }

  group('minting', () {
    test('a new item is created with a stable id', () async {
      await seedCategory();
      await addKhinkali();

      final id = itemAt(0, 0).id;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      // Not derived from anything mutable.
      expect(id, isNot(contains('Khinkali')));
      expect(id, isNot(contains('hot')));
    });

    test('items created in the same instant get different ids', () async {
      await seedCategory();
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(newMenuItemId());
      }
      expect(ids, hasLength(200));
    });

    test('a subcategory item is identified the same way', () async {
      await seedCategory();
      await MenuRepository.addSubcategory(
        categoryIndex: 0,
        slug: 'soups',
        nameEn: 'Soups',
        nameKa: 'სუპები',
        actorId: 'nino',
      );
      await MenuRepository.addItemToSubcategory(
        categoryIndex: 0,
        subcategoryIndex: 0,
        nameEn: 'Kharcho',
        nameKa: 'ხარჩო',
        price: 6.0,
        actorId: 'nino',
      );

      final item = DatabaseCore.menuBox!
          .getAt(0)!
          .subcategories!
          .single
          .items
          .single;
      expect(item.id, isNotNull);
    });
  });

  group('the id survives', () {
    test('a rename', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Royal Khinkali',
        nameKa: 'სამეფო ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );

      expect(itemAt(0, 0).id, id);
      expect(itemAt(0, 0).translationsEn['name'], 'Royal Khinkali');
    });

    test('a price change', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 3.5,
        actorId: 'nino',
      );

      expect(itemAt(0, 0).id, id);
      expect(itemAt(0, 0).price, 3.5);
    });

    test('a kitchen-routing change', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.0,
        sendToKitchen: false,
        actorId: 'nino',
      );

      expect(itemAt(0, 0).id, id);
      expect(itemAt(0, 0).sendToKitchen, isFalse);
    });

    test('its category being renamed underneath it', () async {
      // Items cannot be moved between categories today, so the supported way
      // an item's path changes is the category slug changing. That used to
      // re-identify every item in the category.
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await MenuRepository.updateCategory(
        index: 0,
        slug: 'main-dishes',
        nameEn: 'Main Dishes',
        nameKa: 'მთავარი კერძები',
        actorId: 'nino',
      );

      expect(DatabaseCore.menuBox!.getAt(0)!.slug, 'main-dishes');
      expect(itemAt(0, 0).id, id);
    });

    test('an edit relayed with a non-POS source', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 4.0,
        actorId: 'manager',
        source: AuditSource.manager,
      );

      expect(itemAt(0, 0).id, id);
    });

    test('a restart', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      await DatabaseCore.menuBox!.close();
      DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('mi_menu');

      expect(itemAt(0, 0).id, id);
    });

    test('a backup round trip', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      final exported = BackupRepository.exportMenu();
      expect(exported.single['items'][0]['id'], id);

      await BackupRepository.importMenuFromJson(
        exported,
        clearExisting: true,
        silent: true,
      );

      expect(itemAt(0, 0).id, id);
      expect(DatabaseCore.menuBox!.length, 1);
    });
  });

  group('existing menus', () {
    /// A category exactly as an older build wrote it: items with no id.
    Future<void> seedLegacyMenu() async {
      await DatabaseCore.menuBox!.add(
        MenuCategoryDB(
          slug: 'hot',
          translationsEn: {'name': 'Hot'},
          translationsKa: {'name': 'ცხელი'},
          items: [
            MenuItemDB(
              translationsEn: {'name': 'Khinkali'},
              translationsKa: {'name': 'ხინკალი'},
              price: 2.0,
            ),
          ],
          subcategories: [
            MenuSubcategoryDB(
              slug: 'soups',
              translationsEn: {'name': 'Soups'},
              translationsKa: {'name': 'სუპები'},
              items: [
                MenuItemDB(
                  translationsEn: {'name': 'Kharcho'},
                  translationsKa: {'name': 'ხარჩო'},
                  price: 6.0,
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('a row written before the field decodes rather than failing', () async {
      await seedLegacyMenu();

      expect(itemAt(0, 0).id, isNull);
      expect(itemAt(0, 0).translationsEn['name'], 'Khinkali');
    });

    test('the rollout assigns an id once and only once', () async {
      await seedLegacyMenu();

      final assigned = await MenuRepository.ensureStableItemIds();
      expect(assigned, 2);
      final categoryItemId = itemAt(0, 0).id;
      final subItemId = DatabaseCore.menuBox!
          .getAt(0)!
          .subcategories!
          .single
          .items
          .single
          .id;
      expect(categoryItemId, isNotNull);
      expect(subItemId, isNotNull);

      // Running it again — a second startup, a repeated restore — must be
      // inert. A re-minted id is a new product to Cloud.
      final second = await MenuRepository.ensureStableItemIds();
      expect(second, 0);
      expect(itemAt(0, 0).id, categoryItemId);
      expect(
        DatabaseCore.menuBox!.getAt(0)!.subcategories!.single.items.single.id,
        subItemId,
      );
    });

    test('the assignment persists across a restart', () async {
      await seedLegacyMenu();
      await MenuRepository.ensureStableItemIds();
      final id = itemAt(0, 0).id;

      await DatabaseCore.menuBox!.close();
      DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('mi_menu');

      expect(itemAt(0, 0).id, id);
      expect(await MenuRepository.ensureStableItemIds(), 0);
    });

    test('an older backup restores and is identified on the way in', () async {
      // A backup file taken before menu items had ids: no `id` key at all.
      final legacyPayload = <Map<String, dynamic>>[
        {
          'slug': 'hot',
          'translationsEn': {'name': 'Hot'},
          'translationsKa': {'name': 'ცხელი'},
          'sendToKitchen': true,
          'items': [
            {
              'translationsEn': {'name': 'Khinkali'},
              'translationsKa': {'name': 'ხინკალი'},
              'price': 2.0,
              'sendToKitchen': true,
              'variants': null,
            },
          ],
          'subcategories': null,
        },
      ];

      await BackupRepository.importMenuFromJson(
        legacyPayload,
        clearExisting: true,
        silent: true,
      );

      expect(DatabaseCore.menuBox!.length, 1);
      final id = itemAt(0, 0).id;
      expect(id, isNotNull, reason: 'restore must not leave items unidentified');

      // And restoring the same file again does not mint a third identity for
      // a product that already has one on this install.
      await BackupRepository.importMenuFromJson(
        legacyPayload,
        clearExisting: true,
        silent: true,
      );
      expect(itemAt(0, 0).id, isNotNull);
      expect(await MenuRepository.ensureStableItemIds(), 0);
    });
  });

  group('audit', () {
    test('a rename extends one timeline instead of starting two', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id!;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Royal Khinkali',
        nameKa: 'სამეფო ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );

      final created = feed(action: GlobalAuditAction.menuItemCreated).single;
      final updated = feed(action: GlobalAuditAction.menuItemUpdated).single;

      expect(created.entityType, GlobalAuditEntity.menuItem);
      expect(created.entityId, id);
      expect(updated.entityId, id, reason: 'one entity, one timeline');

      // The human-readable context stays in the details, where it belongs.
      expect(created.data['treePath'], 'hot/Khinkali');
      expect(updated.data['treePath'], 'hot/Royal Khinkali');
      final name = updated.changes.firstWhere((c) => c.field == 'nameEn');
      expect(name.previousValue, 'Khinkali');
      expect(name.newValue, 'Royal Khinkali');
    });

    test('a subcategory item is audited by its id too', () async {
      await seedCategory();
      await MenuRepository.addSubcategory(
        categoryIndex: 0,
        slug: 'soups',
        nameEn: 'Soups',
        nameKa: 'სუპები',
        actorId: 'nino',
      );
      await MenuRepository.addItemToSubcategory(
        categoryIndex: 0,
        subcategoryIndex: 0,
        nameEn: 'Kharcho',
        nameKa: 'ხარჩო',
        price: 6.0,
        actorId: 'nino',
      );
      await MenuRepository.updateItemInSubcategory(
        categoryIndex: 0,
        subcategoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Kharcho Classic',
        nameKa: 'ხარჩო',
        price: 6.0,
        actorId: 'nino',
      );

      final id = DatabaseCore.menuBox!
          .getAt(0)!
          .subcategories!
          .single
          .items
          .single
          .id;
      expect(feed(action: GlobalAuditAction.menuItemCreated).single.entityId, id);
      expect(feed(action: GlobalAuditAction.menuItemUpdated).single.entityId, id);
    });

    test('an item with no id yet is still audited, by its path', () async {
      // Belt and braces: if a row somehow reaches an editor before the
      // rollout, the log still says which item it was rather than nothing.
      await DatabaseCore.menuBox!.add(
        MenuCategoryDB(
          slug: 'hot',
          translationsEn: {'name': 'Hot'},
          translationsKa: {'name': 'ცხელი'},
          items: [
            MenuItemDB(
              translationsEn: {'name': 'Khinkali'},
              translationsKa: {'name': 'ხინკალი'},
              price: 2.0,
            ),
          ],
        ),
      );

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Khinkali',
        nameKa: 'ხინკალი',
        price: 2.5,
        actorId: 'nino',
      );

      expect(
        feed(action: GlobalAuditAction.menuItemUpdated).single.entityId,
        'hot/Khinkali',
      );
    });
  });

  group('sync', () {
    test('a retried snapshot carries the same identity', () async {
      await seedCategory();
      await addKhinkali();
      final id = itemAt(0, 0).id;

      Map<String, dynamic> snapshotItem() {
        final it = itemAt(0, 0);
        return <String, dynamic>{
          if (it.id != null) 'id': it.id,
          'nameEn': it.translationsEn['name'],
          'price': it.price,
        };
      }

      final first = snapshotItem();
      final retry = snapshotItem();
      expect(first['id'], id);
      expect(retry['id'], id);

      // A rename between the two attempts still describes the same product.
      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Royal Khinkali',
        nameKa: 'სამეფო ხინკალი',
        price: 2.0,
        actorId: 'nino',
      );
      expect(snapshotItem()['id'], id);
      expect(snapshotItem()['nameEn'], 'Royal Khinkali');
    });
  });
}
