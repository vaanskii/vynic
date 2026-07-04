import 'package:vynic/core/models/menu_models.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import '../database_service.dart';

class MenuService {
  static List<MenuCategory>? _cachedCategories;

  static Future<List<MenuCategory>> loadMenu() async {
    if (_cachedCategories != null) {
      return _cachedCategories!;
    }

    try {
      // Load from database
      final menuCategoriesDB = DatabaseService.getAllMenuCategories();

      // Convert database models to menu models
      _cachedCategories = menuCategoriesDB
          .map((categoryDB) => _convertToMenuCategory(categoryDB))
          .toList();

      return _cachedCategories!;
    } catch (e) {
      return [];
    }
  }

  // Convert MenuCategoryDB to MenuCategory
  static MenuCategory _convertToMenuCategory(MenuCategoryDB categoryDB) {
    return MenuCategory(
      slug: categoryDB.slug,
      translations: {
        'en': Translation(name: categoryDB.translationsEn['name'] ?? ''),
        'ka': Translation(name: categoryDB.translationsKa['name'] ?? ''),
      },
      sendToKitchen: categoryDB.sendToKitchen,
      items: categoryDB.items
          ?.map((itemDB) => _convertToMenuItem(itemDB))
          .toList(),
      subcategories: categoryDB.subcategories
          ?.map((subDB) => _convertToMenuSubcategory(subDB))
          .toList(),
    );
  }

  // Convert MenuSubcategoryDB to MenuSubcategory
  static MenuSubcategory _convertToMenuSubcategory(MenuSubcategoryDB subDB) {
    return MenuSubcategory(
      slug: subDB.slug,
      translations: {
        'en': Translation(name: subDB.translationsEn['name'] ?? ''),
        'ka': Translation(name: subDB.translationsKa['name'] ?? ''),
      },
      items: subDB.items.map((itemDB) => _convertToMenuItem(itemDB)).toList(),
    );
  }

  // Convert MenuItemDB to MenuItem
  static MenuItem _convertToMenuItem(MenuItemDB itemDB) {
    return MenuItem(
      translations: {
        'en': Translation(name: itemDB.translationsEn['name'] ?? ''),
        'ka': Translation(name: itemDB.translationsKa['name'] ?? ''),
      },
      price: itemDB.price,
      sendToKitchen: itemDB.sendToKitchen,
      variants: itemDB.variants
          ?.map((variantDB) => _convertToMenuVariant(variantDB))
          .toList(),
    );
  }

  // Convert MenuVariantDB to MenuVariant
  static MenuVariant _convertToMenuVariant(MenuVariantDB variantDB) {
    return MenuVariant(size: variantDB.size, price: variantDB.price);
  }

  static void clearCache() {
    _cachedCategories = null;
  }
}
