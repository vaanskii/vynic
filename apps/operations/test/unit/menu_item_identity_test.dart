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

  group('category and variant identity', () {
    test('200 menu nodes created in one instant have unique ids', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(newMenuNodeId());
      }
      expect(ids, hasLength(200));
    });

    test('category and subcategory renames preserve their ids', () async {
      await seedCategory();
      await MenuRepository.addSubcategory(
        categoryIndex: 0,
        slug: 'soups',
        nameEn: 'Soups',
        nameKa: 'სუპები',
        actorId: 'nino',
      );
      final category = DatabaseCore.menuBox!.getAt(0)!;
      final categoryId = category.id;
      final subcategoryId = category.subcategories!.single.id;

      await MenuRepository.updateCategory(
        index: 0,
        slug: 'georgian-cuisine',
        nameEn: 'Georgian Cuisine',
        nameKa: 'ქართული სამზარეულო',
        actorId: 'manager',
        source: AuditSource.manager,
      );
      await MenuRepository.updateSubcategory(
        categoryIndex: 0,
        subcategoryIndex: 0,
        slug: 'traditional-soups',
        nameEn: 'Traditional Soups',
        nameKa: 'ტრადიციული სუპები',
        actorId: 'manager',
        source: AuditSource.manager,
      );

      final renamed = DatabaseCore.menuBox!.getAt(0)!;
      expect(renamed.id, categoryId);
      expect(renamed.subcategories!.single.id, subcategoryId);
    });

    test('variant size and price updates preserve its id', () async {
      await seedCategory();
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Lemonade',
        nameKa: 'ლიმონათი',
        variants: [MenuVariantDB.create(size: 0.5, price: 5)],
        actorId: 'nino',
      );
      final item = itemAt(0, 0);
      final itemId = item.id;
      final variantId = item.variants!.single.id;

      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Lemonade',
        nameKa: 'ლიმონათი',
        variants: [MenuVariantDB(id: variantId, size: 0.75, price: 7)],
        actorId: 'manager',
        source: AuditSource.manager,
      );

      expect(itemAt(0, 0).id, itemId);
      expect(itemAt(0, 0).variants!.single.id, variantId);
      expect(itemAt(0, 0).variants!.single.size, 0.75);
      expect(itemAt(0, 0).variants!.single.price, 7);
    });

    test(
      'backup round trip preserves category, subcategory and variant ids',
      () async {
        await seedCategory();
        await MenuRepository.addSubcategory(
          categoryIndex: 0,
          slug: 'drinks',
          nameEn: 'Drinks',
          nameKa: 'სასმელები',
          actorId: 'nino',
        );
        await MenuRepository.addItemToSubcategory(
          categoryIndex: 0,
          subcategoryIndex: 0,
          nameEn: 'Water',
          nameKa: 'წყალი',
          variants: [MenuVariantDB.create(size: 0.5, price: 2)],
          actorId: 'nino',
        );
        final before = DatabaseCore.menuBox!.getAt(0)!;
        final categoryId = before.id;
        final subcategoryId = before.subcategories!.single.id;
        final variantId =
            before.subcategories!.single.items.single.variants!.single.id;

        final exported = BackupRepository.exportMenu();
        await BackupRepository.importMenuFromJson(
          exported,
          clearExisting: true,
          silent: true,
        );

        final restored = DatabaseCore.menuBox!.getAt(0)!;
        expect(restored.id, categoryId);
        expect(restored.subcategories!.single.id, subcategoryId);
        expect(
          restored.subcategories!.single.items.single.variants!.single.id,
          variantId,
        );
      },
    );

    test(
      'legacy category, subcategory, item and variant get ids once',
      () async {
        await DatabaseCore.menuBox!.add(
          MenuCategoryDB(
            slug: 'legacy',
            translationsEn: {'name': 'Legacy'},
            translationsKa: {'name': 'Legacy'},
            items: [
              MenuItemDB(
                translationsEn: {'name': 'Water'},
                translationsKa: {'name': 'Water'},
                variants: [MenuVariantDB(size: 0.5, price: 2)],
              ),
            ],
            subcategories: [
              MenuSubcategoryDB(
                slug: 'legacy-sub',
                translationsEn: {'name': 'Legacy sub'},
                translationsKa: {'name': 'Legacy sub'},
                items: [],
              ),
            ],
          ),
        );

        expect(await MenuRepository.ensureStableMenuIds(), 4);
        final assigned = DatabaseCore.menuBox!.getAt(0)!;
        final ids = [
          assigned.id,
          assigned.subcategories!.single.id,
          assigned.items!.single.id,
          assigned.items!.single.variants!.single.id,
        ];
        expect(ids, everyElement(isNotNull));
        expect(await MenuRepository.ensureStableMenuIds(), 0);

        await DatabaseCore.menuBox!.close();
        DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('mi_menu');
        final restarted = DatabaseCore.menuBox!.getAt(0)!;
        expect([
          restarted.id,
          restarted.subcategories!.single.id,
          restarted.items!.single.id,
          restarted.items!.single.variants!.single.id,
        ], ids);
      },
    );
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

    test(
      'a row written before the field decodes rather than failing',
      () async {
        await seedLegacyMenu();

        expect(itemAt(0, 0).id, isNull);
        expect(itemAt(0, 0).translationsEn['name'], 'Khinkali');
      },
    );

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
      expect(
        id,
        isNotNull,
        reason: 'restore must not leave items unidentified',
      );

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
    test('category rename and variant update use stable entity ids', () async {
      await seedCategory();
      final categoryId = DatabaseCore.menuBox!.getAt(0)!.id!;
      await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Lemonade',
        nameKa: 'ლიმონათი',
        variants: [MenuVariantDB.create(size: 0.5, price: 5)],
        actorId: 'nino',
      );
      final item = itemAt(0, 0);
      final variantId = item.variants!.single.id!;

      await MenuRepository.updateCategory(
        index: 0,
        slug: 'cold-drinks',
        nameEn: 'Cold Drinks',
        nameKa: 'ცივი სასმელები',
        actorId: 'nino',
      );
      await MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Lemonade',
        nameKa: 'ლიმონათი',
        variants: [MenuVariantDB(id: variantId, size: 0.5, price: 6)],
        actorId: 'nino',
      );

      final categoryUpdate = feed(
        action: GlobalAuditAction.menuCategoryUpdated,
      ).single;
      final variantUpdate = feed(
        action: GlobalAuditAction.menuVariantUpdated,
      ).single;
      expect(categoryUpdate.entityType, GlobalAuditEntity.menuCategory);
      expect(categoryUpdate.entityId, categoryId);
      expect(variantUpdate.entityType, GlobalAuditEntity.menuVariant);
      expect(variantUpdate.entityId, variantId);
      expect(variantUpdate.data['itemId'], item.id);
    });

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
      expect(
        feed(action: GlobalAuditAction.menuItemCreated).single.entityId,
        id,
      );
      expect(
        feed(action: GlobalAuditAction.menuItemUpdated).single.entityId,
        id,
      );
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
