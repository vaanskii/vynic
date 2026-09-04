import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:vynic/core/models/menu_item_db.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import '../database_core.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

/// Menu storage: categories/subcategories/items CRUD, the seed import from
/// `data/menu.json`, and the kitchen-routing keyword rules.
class MenuRepository {
  MenuRepository._();

  static const int _kitchenRoutingDefaultsVersion = 2;

  static const List<String> _kitchenExcludedCategoryKeywords = [
    'drink',
    'drinks',
    'soft drink',
    'soft drinks',
    'alcohol',
    'alcoholic',
    'bar',
    'vodka',
    'house vodka',
    'chacha',
    'house chacha',
    'wine',
    'house wine',
    'dry wine',
    'red wine',
    'white wine',
    'sparkling wine',
    'sparkling',
    'champagne',
    'prosecco',
    'cava',
    'cognac',
    'brandy',
    'whiskey',
    'whisky',
    'bourbon',
    'scotch',
    'beer',
    'draft beer',
    'bottled beer',
    'craft beer',
    'lager',
    'ale',
    'cider',
    'gin',
    'rum',
    'tequila',
    'martini',
    'cocktail',
    'cocktails',
    'spritz',
    'aperol',
    'sangria',
    'shots',
    'shot',
    'liqueur',
    'liquor',
    'digestif',
    'aperitif',
    'energy drink',
    'energy drinks',
    'juice',
    'juices',
    'lemonade',
    'soda',
    'tonic',
    'water',
    'sparkling water',
    'still water',
    'mineral water',
    'coffee',
    'coffee and tea',
    'espresso',
    'americano',
    'cappuccino',
    'latte',
    'macchiato',
    'flat white',
    'iced coffee',
    'tea',
    'iced tea',
    'herbal tea',
    'milkshake',
    'milkshakes',
    'smoothie',
    'smoothies',
    'mocktail',
    'mocktails',
    'non-alcoholic',
    'bar menu',
  ];

  static List<String> get kitchenExcludedCategoryKeywords =>
      List.unmodifiable(_kitchenExcludedCategoryKeywords);

  /// One-time upgrade: force bar/drink categories to not route to kitchen.
  /// Versioned via `kitchenRoutingDefaultsVersion` in settings.
  static Future<void> ensureKitchenRoutingDefaults() async {
    final appliedVersion =
        (DatabaseCore.settingsBox!.get('kitchenRoutingDefaultsVersion')
            as int?) ??
        0;
    if (appliedVersion < _kitchenRoutingDefaultsVersion) {
      await _applyKitchenRoutingDefaults();
      await DatabaseCore.settingsBox!.put(
        'kitchenRoutingDefaultsVersion',
        _kitchenRoutingDefaultsVersion,
      );
    }
  }

  static bool shouldCategorySendToKitchenByDefault(
    String? slug, {
    String? nameEn,
    String? nameKa,
  }) {
    return _shouldCategorySendToKitchen(slug, nameEn: nameEn, nameKa: nameKa);
  }

  static bool _shouldCategorySendToKitchen(
    String? slug, {
    String? nameEn,
    String? nameKa,
  }) {
    if (_matchesKitchenExclusion(slug)) {
      return false;
    }
    if (_matchesKitchenExclusion(nameEn)) {
      return false;
    }
    if (_matchesKitchenExclusion(nameKa)) {
      return false;
    }
    return true;
  }

  static bool _matchesKitchenExclusion(String? value) {
    final normalized =
        value?.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ').trim() ??
        '';
    if (normalized.isEmpty) {
      return false;
    }
    for (final keyword in _kitchenExcludedCategoryKeywords) {
      final keywordNormalized = keyword
          .toLowerCase()
          .replaceAll('-', ' ')
          .trim();
      if (keywordNormalized.isNotEmpty &&
          normalized.contains(keywordNormalized)) {
        return true;
      }
    }
    return false;
  }

  // ==================== MENU METHODS ====================

  // Initialize menu from JSON file
  static Future<void> initializeMenuFromJson() async {
    try {
      final String jsonString = await rootBundle.loadString('data/menu.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      for (final categoryJson in jsonList) {
        final category = _convertJsonToMenuCategory(categoryJson);
        await DatabaseCore.menuBox!.add(category);
      }
    } catch (e) {
      developer.log(e.toString(), name: 'DatabaseService', error: e);
    }
  }

  // Convert JSON to MenuCategoryDB
  static MenuCategoryDB _convertJsonToMenuCategory(Map<String, dynamic> json) {
    final nameEn = json['translations']['en']['name'] as String;
    final nameKa = json['translations']['ka']['name'] as String;
    return MenuCategoryDB(
      slug: json['slug'] as String,
      translationsEn: {'name': nameEn},
      translationsKa: {'name': nameKa},
      sendToKitchen:
          json['sendToKitchen'] as bool? ??
          _shouldCategorySendToKitchen(
            json['slug'] as String?,
            nameEn: nameEn,
            nameKa: nameKa,
          ),
      items: json['items'] != null
          ? (json['items'] as List)
                .map((item) => _convertJsonToMenuItem(item))
                .toList()
          : null,
      subcategories: json['subcategories'] != null
          ? (json['subcategories'] as List)
                .map((sub) => _convertJsonToMenuSubcategory(sub))
                .toList()
          : null,
    );
  }

  // Convert JSON to MenuSubcategoryDB
  static MenuSubcategoryDB _convertJsonToMenuSubcategory(
    Map<String, dynamic> json,
  ) {
    return MenuSubcategoryDB(
      slug: json['slug'] as String,
      translationsEn: {'name': json['translations']['en']['name'] as String},
      translationsKa: {'name': json['translations']['ka']['name'] as String},
      items: (json['items'] as List)
          .map((item) => _convertJsonToMenuItem(item))
          .toList(),
    );
  }

  // Convert JSON to MenuItemDB
  static MenuItemDB _convertJsonToMenuItem(Map<String, dynamic> json) {
    return MenuItemDB(
      translationsEn: {'name': json['translations']['en']['name'] as String},
      translationsKa: {'name': json['translations']['ka']['name'] as String},
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
      variants: json['variants'] != null
          ? (json['variants'] as List)
                .map((variant) => _convertJsonToMenuVariant(variant))
                .toList()
          : null,
    );
  }

  // Convert JSON to MenuVariantDB
  static MenuVariantDB _convertJsonToMenuVariant(Map<String, dynamic> json) {
    return MenuVariantDB(
      size: (json['size'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
    );
  }

  // Get all menu categories from database
  static List<MenuCategoryDB> getAllMenuCategories() {
    return DatabaseCore.menuBox!.values.toList();
  }

  // Clear menu cache (if needed for refresh)
  static Future<void> clearMenuCache() async {
    // This is handled by Hive automatically
    // No need for explicit cache clearing
  }

  static Future<void> _applyKitchenRoutingDefaults() async {
    if (DatabaseCore.menuBox == null || DatabaseCore.menuBox!.isEmpty) {
      return;
    }

    bool updated = false;
    for (final category in DatabaseCore.menuBox!.values) {
      final shouldSend = _shouldCategorySendToKitchen(
        category.slug,
        nameEn: category.translationsEn['name'],
        nameKa: category.translationsKa['name'],
      );
      if (!shouldSend && category.sendToKitchen) {
        category.sendToKitchen = false;
        await category.save();
        updated = true;
      }
    }

    if (updated) {
      developer.log(
        'Updated kitchen routing defaults for bar/drink categories',
        name: 'DatabaseService',
      );
    }
  }


  // ==================== MENU AUDIT ====================

  /// Attribution for a menu change whose caller did not say who made it.
  static const String _unknownActor = 'unknown';

  /// The durable identity of a menu item.
  ///
  /// Items are positions in a category's list, not rows with keys, so the only
  /// identity that survives an edit elsewhere in the list is where the item
  /// sits in the menu tree. Indexes are not usable: inserting one item above
  /// renumbers everything below it.
  static String _itemPath(String categorySlug, String? subSlug, String nameEn) =>
      subSlug == null || subSlug.isEmpty
      ? '$categorySlug/$nameEn'
      : '$categorySlug/$subSlug/$nameEn';

  static String _displayName(String nameKa, String nameEn) =>
      nameKa.trim().isNotEmpty ? nameKa.trim() : nameEn.trim();

  /// The fields of a menu item that actually moved.
  ///
  /// Only the differences, never a snapshot of the whole item: a menu edit is
  /// frequent and a snapshot per edit would bury the price change nobody can
  /// otherwise find.
  static List<Map<String, dynamic>> _itemChanges({
    required String previousNameEn,
    required String previousNameKa,
    required double? previousPrice,
    required bool previousSendToKitchen,
    required int previousVariantCount,
    required String nameEn,
    required String nameKa,
    required double? price,
    required bool sendToKitchen,
    required int variantCount,
  }) {
    final changes = <Map<String, dynamic>>[];
    if (previousNameEn != nameEn) {
      changes.add(
        GlobalAudit.change(
          field: 'nameEn',
          previousValue: previousNameEn,
          newValue: nameEn,
        ),
      );
    }
    if (previousNameKa != nameKa) {
      changes.add(
        GlobalAudit.change(
          field: 'nameKa',
          previousValue: previousNameKa,
          newValue: nameKa,
        ),
      );
    }
    if (previousPrice != price) {
      changes.add(
        GlobalAudit.change(
          field: 'price',
          previousValue: previousPrice,
          newValue: price,
        ),
      );
    }
    if (previousSendToKitchen != sendToKitchen) {
      changes.add(
        GlobalAudit.change(
          field: 'sendToKitchen',
          previousValue: previousSendToKitchen,
          newValue: sendToKitchen,
        ),
      );
    }
    if (previousVariantCount != variantCount) {
      changes.add(
        GlobalAudit.change(
          field: 'variantCount',
          previousValue: previousVariantCount,
          newValue: variantCount,
        ),
      );
    }
    return changes;
  }

  // ==================== MENU CRUD METHODS ====================

  // Add new category
  static Future<bool> addCategory({
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = MenuCategoryDB(
        slug: slug,
        translationsEn: {'name': nameEn},
        translationsKa: {'name': nameKa},
        items: [],
        subcategories: null,
        sendToKitchen:
            sendToKitchen ??
            _shouldCategorySendToKitchen(slug, nameEn: nameEn, nameKa: nameKa),
      );
      await DatabaseCore.menuBox!.add(category);
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.menu,
          action: 'created',
          payload: {'slug': slug},
        ),
      );
      await GlobalAudit.menuCategory(
        action: GlobalAuditAction.menuCategoryCreated,
        categoryName: slug,
        actorId: actorId,
        actorName: actorName,
        source: source,
        extra: <String, dynamic>{
          'nameEn': nameEn,
          'nameKa': nameKa,
          'sendToKitchen': category.sendToKitchen,
        },
      );
      return true;
    } catch (e) {
      developer.log(
        'Error adding category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update category
  static Future<bool> updateCategory({
    required int index,
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(index);
      if (category != null) {
        final previousSlug = category.slug;
        final previousNameEn = (category.translationsEn['name'] ?? '')
            .toString();
        final previousNameKa = (category.translationsKa['name'] ?? '')
            .toString();
        final previousSendToKitchen = category.sendToKitchen;
        category.slug = slug;
        category.translationsEn = {'name': nameEn};
        category.translationsKa = {'name': nameKa};
        category.sendToKitchen = sendToKitchen ?? category.sendToKitchen;
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'updated',
            payload: {'slug': slug},
          ),
        );
        final changes = <Map<String, dynamic>>[
          if (previousSlug != slug)
            GlobalAudit.change(
              field: 'slug',
              previousValue: previousSlug,
              newValue: slug,
            ),
          if (previousNameEn != nameEn)
            GlobalAudit.change(
              field: 'nameEn',
              previousValue: previousNameEn,
              newValue: nameEn,
            ),
          if (previousNameKa != nameKa)
            GlobalAudit.change(
              field: 'nameKa',
              previousValue: previousNameKa,
              newValue: nameKa,
            ),
          if (previousSendToKitchen != category.sendToKitchen)
            GlobalAudit.change(
              field: 'sendToKitchen',
              previousValue: previousSendToKitchen,
              newValue: category.sendToKitchen,
            ),
        ];
        // A save that saved the same values is not a change.
        if (changes.isNotEmpty) {
          await GlobalAudit.menuCategory(
            action: GlobalAuditAction.menuCategoryUpdated,
            categoryName: slug,
            changes: changes,
            actorId: actorId,
            actorName: actorName,
            source: source,
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete category
  static Future<bool> deleteCategory(
    int index, {
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(index);
      final slug = category?.slug ?? 'index:$index';
      final itemCount = category?.items?.length ?? 0;
      final subcategoryCount = category?.subcategories?.length ?? 0;
      await DatabaseCore.menuBox!.deleteAt(index);
      SyncHub.notify(SyncEvent(type: SyncEventType.menu, action: 'deleted'));
      await GlobalAudit.menuCategory(
        action: GlobalAuditAction.menuCategoryDeleted,
        categoryName: slug,
        actorId: actorId,
        actorName: actorName,
        source: source,
        extra: <String, dynamic>{
          'itemCount': itemCount,
          'subcategoryCount': subcategoryCount,
        },
      );
      return true;
    } catch (e) {
      developer.log(
        'Error deleting category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add item to category
  static Future<bool> addItemToCategory({
    required int categoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      if (category != null) {
        final item = MenuItemDB(
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          price: price,
          variants: variants,
          sendToKitchen: sendToKitchen ?? true,
        );
        category.items ??= [];
        category.items!.add(item);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_created',
            payload: {'slug': category.slug},
          ),
        );
        await GlobalAudit.menuItem(
          action: GlobalAuditAction.menuItemCreated,
          itemId: _itemPath(category.slug, null, nameEn),
          itemName: _displayName(nameKa, nameEn),
          categoryName: category.slug,
          actorId: actorId,
          actorName: actorName,
          source: source,
          extra: <String, dynamic>{
            'price': price,
            'sendToKitchen': item.sendToKitchen,
            'variantCount': variants?.length ?? 0,
          },
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding item to category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update item in category
  static Future<bool> updateItemInCategory({
    required int categoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      if (category != null &&
          category.items != null &&
          itemIndex < category.items!.length) {
        final before = category.items![itemIndex];
        final previousNameEn = (before.translationsEn['name'] ?? '').toString();
        final previousNameKa = (before.translationsKa['name'] ?? '').toString();
        final previousPrice = before.price;
        final previousSendToKitchen = before.sendToKitchen;
        final previousVariantCount = before.variants?.length ?? 0;
        category.items![itemIndex].translationsEn = {'name': nameEn};
        category.items![itemIndex].translationsKa = {'name': nameKa};
        category.items![itemIndex].price = price;
        category.items![itemIndex].variants = variants;
        if (sendToKitchen != null) {
          category.items![itemIndex].sendToKitchen = sendToKitchen;
        }
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_updated',
            payload: {'slug': category.slug},
          ),
        );
        final changes = _itemChanges(
          previousNameEn: previousNameEn,
          previousNameKa: previousNameKa,
          previousPrice: previousPrice,
          previousSendToKitchen: previousSendToKitchen,
          previousVariantCount: previousVariantCount,
          nameEn: nameEn,
          nameKa: nameKa,
          price: price,
          sendToKitchen: category.items![itemIndex].sendToKitchen,
          variantCount: variants?.length ?? 0,
        );
        if (changes.isNotEmpty) {
          await GlobalAudit.menuItem(
            action: GlobalAuditAction.menuItemUpdated,
            // The item's identity after the edit — a rename moves it.
            itemId: _itemPath(category.slug, null, nameEn),
            itemName: _displayName(nameKa, nameEn),
            categoryName: category.slug,
            changes: changes,
            actorId: actorId,
            actorName: actorName,
            source: source,
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating item in category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete item from category
  static Future<bool> deleteItemFromCategory({
    required int categoryIndex,
    required int itemIndex,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      if (category != null &&
          category.items != null &&
          itemIndex < category.items!.length) {
        final removed = category.items![itemIndex];
        final removedNameEn = (removed.translationsEn['name'] ?? '').toString();
        final removedNameKa = (removed.translationsKa['name'] ?? '').toString();
        final removedPrice = removed.price;
        category.items!.removeAt(itemIndex);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_deleted',
            payload: {'slug': category.slug},
          ),
        );
        await GlobalAudit.menuItem(
          action: GlobalAuditAction.menuItemDeleted,
          itemId: _itemPath(category.slug, null, removedNameEn),
          itemName: _displayName(removedNameKa, removedNameEn),
          categoryName: category.slug,
          actorId: actorId,
          actorName: actorName,
          source: source,
          extra: <String, dynamic>{'price': removedPrice},
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error deleting item from category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add subcategory
  static Future<bool> addSubcategory({
    required int categoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      if (category != null) {
        final subcategory = MenuSubcategoryDB(
          slug: slug,
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          items: <MenuItemDB>[],
        );
        category.subcategories ??= <MenuSubcategoryDB>[];
        category.subcategories!.add(subcategory);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_created',
            payload: {'slug': category.slug},
          ),
        );
        await GlobalAudit.menuCategory(
          action: GlobalAuditAction.menuCategoryCreated,
          categoryName: slug,
          nodeKind: 'SUBCATEGORY',
          parentCategoryName: category.slug,
          actorId: actorId,
          actorName: actorName,
          source: source,
          extra: <String, dynamic>{'nameEn': nameEn, 'nameKa': nameKa},
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update subcategory
  static Future<bool> updateSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final subcategory = subcategories[subcategoryIndex];
        final previousSlug = subcategory.slug;
        final previousNameEn = (subcategory.translationsEn['name'] ?? '')
            .toString();
        final previousNameKa = (subcategory.translationsKa['name'] ?? '')
            .toString();
        subcategory.slug = slug;
        subcategory.translationsEn = {'name': nameEn};
        subcategory.translationsKa = {'name': nameKa};
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_updated',
            payload: {'slug': category.slug},
          ),
        );
        final changes = <Map<String, dynamic>>[
          if (previousSlug != slug)
            GlobalAudit.change(
              field: 'slug',
              previousValue: previousSlug,
              newValue: slug,
            ),
          if (previousNameEn != nameEn)
            GlobalAudit.change(
              field: 'nameEn',
              previousValue: previousNameEn,
              newValue: nameEn,
            ),
          if (previousNameKa != nameKa)
            GlobalAudit.change(
              field: 'nameKa',
              previousValue: previousNameKa,
              newValue: nameKa,
            ),
        ];
        if (changes.isNotEmpty) {
          await GlobalAudit.menuCategory(
            action: GlobalAuditAction.menuCategoryUpdated,
            categoryName: slug,
            nodeKind: 'SUBCATEGORY',
            parentCategoryName: category.slug,
            changes: changes,
            actorId: actorId,
            actorName: actorName,
            source: source,
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete subcategory
  static Future<bool> deleteSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final removed = subcategories[subcategoryIndex];
        final removedSlug = removed.slug;
        final removedItemCount = removed.items.length;
        subcategories.removeAt(subcategoryIndex);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_deleted',
            payload: {'slug': category.slug},
          ),
        );
        await GlobalAudit.menuCategory(
          action: GlobalAuditAction.menuCategoryDeleted,
          categoryName: removedSlug,
          nodeKind: 'SUBCATEGORY',
          parentCategoryName: category.slug,
          actorId: actorId,
          actorName: actorName,
          source: source,
          extra: <String, dynamic>{'itemCount': removedItemCount},
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error deleting subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add item to subcategory
  static Future<bool> addItemToSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final item = MenuItemDB(
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          price: price,
          variants: variants,
          sendToKitchen: sendToKitchen ?? true,
        );
        subcategories[subcategoryIndex].items.add(item);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_item_created',
            payload: {'slug': category.slug},
          ),
        );
        await GlobalAudit.menuItem(
          action: GlobalAuditAction.menuItemCreated,
          itemId: _itemPath(
            category.slug,
            subcategories[subcategoryIndex].slug,
            nameEn,
          ),
          itemName: _displayName(nameKa, nameEn),
          categoryName: subcategories[subcategoryIndex].slug,
          actorId: actorId,
          actorName: actorName,
          source: source,
          extra: <String, dynamic>{
            'parentCategoryName': category.slug,
            'price': price,
            'sendToKitchen': item.sendToKitchen,
            'variantCount': variants?.length ?? 0,
          },
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding item to subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update item in subcategory
  static Future<bool> updateItemInSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final items = subcategories[subcategoryIndex].items;
        if (itemIndex < items.length) {
          final item = items[itemIndex];
          final previousNameEn = (item.translationsEn['name'] ?? '').toString();
          final previousNameKa = (item.translationsKa['name'] ?? '').toString();
          final previousPrice = item.price;
          final previousSendToKitchen = item.sendToKitchen;
          final previousVariantCount = item.variants?.length ?? 0;
          item.translationsEn = {'name': nameEn};
          item.translationsKa = {'name': nameKa};
          item.price = price;
          item.variants = variants;
          if (sendToKitchen != null) {
            item.sendToKitchen = sendToKitchen;
          }
          await category.save();
          SyncHub.notify(
            SyncEvent(
              type: SyncEventType.menu,
              action: 'subcategory_item_updated',
              payload: {'slug': category.slug},
            ),
          );
          final changes = _itemChanges(
            previousNameEn: previousNameEn,
            previousNameKa: previousNameKa,
            previousPrice: previousPrice,
            previousSendToKitchen: previousSendToKitchen,
            previousVariantCount: previousVariantCount,
            nameEn: nameEn,
            nameKa: nameKa,
            price: price,
            sendToKitchen: item.sendToKitchen,
            variantCount: variants?.length ?? 0,
          );
          if (changes.isNotEmpty) {
            await GlobalAudit.menuItem(
              action: GlobalAuditAction.menuItemUpdated,
              itemId: _itemPath(
                category.slug,
                subcategories[subcategoryIndex].slug,
                nameEn,
              ),
              itemName: _displayName(nameKa, nameEn),
              categoryName: subcategories[subcategoryIndex].slug,
              changes: changes,
              actorId: actorId,
              actorName: actorName,
              source: source,
              extra: <String, dynamic>{'parentCategoryName': category.slug},
            );
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error updating subcategory item: $e');
      return false;
    }
  }

  // Delete item from subcategory
  static Future<bool> deleteItemFromSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      final category = DatabaseCore.menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final items = subcategories[subcategoryIndex].items;
        if (itemIndex < items.length) {
          final removed = items[itemIndex];
          final removedNameEn = (removed.translationsEn['name'] ?? '')
              .toString();
          final removedNameKa = (removed.translationsKa['name'] ?? '')
              .toString();
          final removedPrice = removed.price;
          items.removeAt(itemIndex);
          await category.save();
          SyncHub.notify(
            SyncEvent(
              type: SyncEventType.menu,
              action: 'subcategory_item_deleted',
              payload: {'slug': category.slug},
            ),
          );
          await GlobalAudit.menuItem(
            action: GlobalAuditAction.menuItemDeleted,
            itemId: _itemPath(
              category.slug,
              subcategories[subcategoryIndex].slug,
              removedNameEn,
            ),
            itemName: _displayName(removedNameKa, removedNameEn),
            categoryName: subcategories[subcategoryIndex].slug,
            actorId: actorId,
            actorName: actorName,
            source: source,
            extra: <String, dynamic>{
              'parentCategoryName': category.slug,
              'price': removedPrice,
            },
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error deleting subcategory item: $e');
      return false;
    }
  }
}
