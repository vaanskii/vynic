import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';

/// The POS side of Inventory Step 3.
///
/// Recipes stay Cloud-authoritative and Manager-written. What the POS gains is
/// a read-only projection of the active definitions, so a later step can
/// consume stock offline without asking Cloud anything — and without the
/// terminal ever recomputing a consumption quantity of its own.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vynic_inventory_step3');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('inventory_step3_test');
    DatabaseCore.inventoryBox = await Hive.openBox('inventory_step3_test');
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.inventoryBox = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the projected definition', () {
    test('keeps Cloud’s per-unit quantity exactly', () {
      final recipe = InventoryRecipe.fromJson(
        _recipe(components: [_component(perUnit: '0.035000')]),
      );

      expect(recipe.components.single.baseQuantityPerUnit, '0.035000');
      expect(recipe.components.single.baseUnit, InventoryUnit.kg);
      // A cache round trip must not re-round what Cloud computed.
      expect(
        InventoryRecipe.fromJson(
          recipe.toJson(),
        ).components.single.baseQuantityPerUnit,
        '0.035000',
      );
    });

    test('carries both identities, so an offline terminal can match a sale', () {
      final recipe = InventoryRecipe.fromJson(
        _recipe(
          posMenuItemId: 'pos-item-1',
          variantId: 'variant-1',
          posMenuVariantId: 'pos-variant-1',
        ),
      );

      expect(recipe.menuItemId, 'menu-1');
      expect(recipe.posMenuItemId, 'pos-item-1');
      expect(recipe.variantId, 'variant-1');
      expect(recipe.posMenuVariantId, 'pos-variant-1');
    });

    test('carries the revision a later step will snapshot', () {
      expect(InventoryRecipe.fromJson(_recipe(revision: 7)).revision, 7);
    });
  });

  group('the catalog', () {
    test('survives a refresh with its recipes intact', () async {
      await InventoryRepository.replaceCatalog(
        _catalog(recipes: [_recipe(), _recipe(recipeId: 'r-2')]),
      );

      final recipes = InventoryRepository.getRecipes();
      expect(recipes, hasLength(2));
      expect(recipes.first.components.single.stockItemId, 'stock-1');
      expect(InventoryRepository.getStockItems(), hasLength(1));
    });

    test('a failed refresh leaves the last known recipes in place', () async {
      await InventoryRepository.replaceCatalog(_catalog(recipes: [_recipe()]));

      // A refresh that fails never reaches replaceCatalog at all, so the
      // previous projection is simply still there. Restaurant service never
      // waits on Cloud.
      expect(InventoryRepository.getRecipes(), hasLength(1));
      expect(InventoryRepository.getRecipes().single.recipeId, 'recipe-1');
    });

    test('a v2 catalog with no recipes decodes as an empty list', () async {
      await InventoryRepository.replaceCatalog(<String, dynamic>{
        'version': 2,
        'generatedAt': '2026-09-10T10:00:00.000Z',
        'stockItems': [_stock()],
        'suppliers': const [],
      });

      expect(InventoryRepository.getRecipes(), isEmpty);
      expect(InventoryRepository.getStockItems(), hasLength(1));
    });

    test('a legacy backup without recipes restores safely', () async {
      await InventoryRepository.restoreCatalog(<String, dynamic>{
        'version': 1,
        'stockItems': [_stock()],
        'suppliers': const [],
      });

      expect(InventoryRepository.getRecipes(), isEmpty);
      expect(InventoryRepository.getStockItems().single.currentStock, '0.000');

      // And the next Device pull fills in what the backup could not carry.
      await InventoryRepository.replaceCatalog(_catalog(recipes: [_recipe()]));
      expect(InventoryRepository.getRecipes(), hasLength(1));
    });

    test('an export carries the recipes back into a backup', () async {
      await InventoryRepository.replaceCatalog(_catalog(recipes: [_recipe()]));

      final exported = InventoryRepository.exportCatalog();
      await InventoryRepository.replaceCatalog(_catalog(recipes: const []));
      expect(InventoryRepository.getRecipes(), isEmpty);

      await InventoryRepository.restoreCatalog(exported);
      expect(InventoryRepository.getRecipes(), hasLength(1));
    });
  });

  group('consumption units', () {
    test('offer the natural scales Cloud declares', () {
      final beef = StockItem.fromJson(
        _stock(baseUnit: 'kg', recipeUnits: const ['g', 'kg']),
      );
      expect(beef.consumptionUnits, [InventoryUnit.g, InventoryUnit.kg]);
    });

    test('fall back to the base unit on an older catalog', () {
      // Absent rather than wrong: an older backend simply says nothing, and
      // the base unit is always a legitimate consumption unit.
      final beef = StockItem.fromJson(_stock(baseUnit: 'kg'));
      expect(beef.recipeUnits, isEmpty);
      expect(beef.consumptionUnits, [InventoryUnit.kg]);
    });

    test('drop a unit code this build has never heard of', () {
      final item = StockItem.fromJson(
        _stock(baseUnit: 'kg', recipeUnits: const ['g', 'furlong']),
      );
      // One unreadable code must not cost the venue its whole catalog.
      expect(item.consumptionUnits, [InventoryUnit.g]);
    });
  });

  group('the Manager read models', () {
    test('read a direct product link as a link, not as a recipe', () {
      final recipe = MenuRecipe.fromJson(<String, dynamic>{
        'id': 'recipe-1',
        'menuItemId': 'menu-1',
        'menuItemName': 'Coca-Cola 0.5L',
        'isActive': true,
        'revision': 1,
        'yieldQuantity': '1.000',
        'components': [
          {
            'stockItemId': 'stock-1',
            'stockItemName': 'Coca-Cola 0.5L',
            'quantity': '1.000',
            'unit': 'bottle',
            'baseQuantity': '1.000',
            'baseUnit': 'bottle',
            'baseQuantityPerUnit': '1.000000',
          },
        ],
      });

      expect(recipe.isDirectLink, isTrue);
      expect(recipe.yieldValue, 1);
      expect(recipe.components.single.isConverted, isFalse);
    });

    test('mark a converted component as converted', () {
      final component = MenuRecipeComponent.fromJson(<String, dynamic>{
        'stockItemId': 'stock-1',
        'stockItemName': 'Draft Beer',
        'quantity': '500.000',
        'unit': 'ml',
        'baseQuantity': '0.500',
        'baseUnit': 'L',
        'baseQuantityPerUnit': '0.500000',
      });

      expect(component.isConverted, isTrue);
      expect(component.baseQuantity, '0.500');
    });

    test('count a Menu Item as configured through any active variant', () {
      final pizza = RecipeMenuItem.fromJson(<String, dynamic>{
        'menuItemId': 'menu-1',
        'nameKa': 'Pizza',
        'price': 20,
        'recipe': null,
        'variants': [
          {
            'variantId': 'variant-1',
            'size': 30,
            'price': 20,
            'recipe': {'id': 'r-1', 'isActive': true, 'componentCount': 2},
          },
          {'variantId': 'variant-2', 'size': 45, 'price': 28, 'recipe': null},
        ],
      });

      expect(pizza.isConfigured, isTrue);
      expect(pizza.componentCount, 2);
      expect(pizza.hasVariants, isTrue);

      final burger = RecipeMenuItem.fromJson(<String, dynamic>{
        'menuItemId': 'menu-2',
        'nameKa': 'Burger',
        'price': 15,
      });
      expect(burger.isConfigured, isFalse);
      expect(burger.componentCount, 0);
    });

    test('treat a disabled definition as unconfigured', () {
      final item = RecipeMenuItem.fromJson(<String, dynamic>{
        'menuItemId': 'menu-1',
        'nameKa': 'Khinkali',
        'price': 1,
        'recipe': {'id': 'r-1', 'isActive': false, 'componentCount': 4},
      });

      expect(item.isConfigured, isFalse);
      expect(item.componentCount, 0);
    });
  });
}

Map<String, dynamic> _stock({
  String id = 'stock-1',
  String baseUnit = 'kg',
  List<String>? recipeUnits,
}) => <String, dynamic>{
  'id': id,
  'name': 'Beef',
  'baseUnit': baseUnit,
  'isActive': true,
  'createdAt': '2026-09-10T10:00:00.000Z',
  'updatedAt': '2026-09-10T10:00:00.000Z',
  if (recipeUnits != null) 'recipeUnits': recipeUnits,
};

Map<String, dynamic> _component({
  String stockItemId = 'stock-1',
  String perUnit = '0.035000',
  String baseUnit = 'kg',
}) => <String, dynamic>{
  'stockItemId': stockItemId,
  'stockItemName': 'Beef',
  'baseQuantityPerUnit': perUnit,
  'baseUnit': baseUnit,
};

Map<String, dynamic> _recipe({
  String recipeId = 'recipe-1',
  int revision = 1,
  String? posMenuItemId,
  String? variantId,
  String? posMenuVariantId,
  List<Map<String, dynamic>>? components,
}) => <String, dynamic>{
  'recipeId': recipeId,
  'revision': revision,
  'menuItemId': 'menu-1',
  'posMenuItemId': posMenuItemId,
  'variantId': variantId,
  'posMenuVariantId': posMenuVariantId,
  'menuItemName': 'ხინკალი',
  'yieldQuantity': '1.000',
  'components': components ?? [_component()],
};

Map<String, dynamic> _catalog({required List<Map<String, dynamic>> recipes}) =>
    <String, dynamic>{
      'version': 3,
      'generatedAt': '2026-09-10T10:00:00.000Z',
      'stockItems': [_stock()],
      'suppliers': const [],
      'recipes': recipes,
    };
