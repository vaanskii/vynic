import 'inventory_test_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';

/// The Manager Recipes surface.
///
/// The rules a restaurant manager would notice going wrong: an unconfigured
/// product hidden instead of flagged, a draft beer offered in boxes, a
/// converted quantity only revealed after saving, or a variant recipe landing
/// on the wrong size.

final _beef = StockItem.fromJson({
  'id': 'stock-beef',
  'name': 'Beef',
  'baseUnit': 'kg',
  'isActive': true,
  'currentStock': '62.500',
  'recipeUnits': ['g', 'kg'],
  'createdAt': '2026-09-10T10:00:00Z',
  'updatedAt': '2026-09-10T10:00:00Z',
});

final _flour = StockItem.fromJson({
  'id': 'stock-flour',
  'name': 'Flour',
  'baseUnit': 'kg',
  'isActive': true,
  'currentStock': '20.000',
  'recipeUnits': ['g', 'kg'],
  'createdAt': '2026-09-10T10:00:00Z',
  'updatedAt': '2026-09-10T10:00:00Z',
});

/// Held by volume and bought by the keg. The keg is procurement packaging; the
/// litre is consumption truth.
final _draftBeer = StockItem.fromJson({
  'id': 'stock-beer',
  'name': 'Draft Beer',
  'baseUnit': 'L',
  'isActive': true,
  'currentStock': '30.000',
  'recipeUnits': ['ml', 'L'],
  'purchaseUnits': [
    {'id': 'pu-keg', 'unit': 'box', 'baseUnitMultiplier': '30'},
  ],
  'createdAt': '2026-09-10T10:00:00Z',
  'updatedAt': '2026-09-10T10:00:00Z',
});

final _cola = StockItem.fromJson({
  'id': 'stock-cola',
  'name': 'Coca-Cola 0.5L',
  'baseUnit': 'bottle',
  'isActive': true,
  'currentStock': '48.000',
  'recipeUnits': ['bottle'],
  'createdAt': '2026-09-10T10:00:00Z',
  'updatedAt': '2026-09-10T10:00:00Z',
});

Map<String, dynamic> _menuItem({
  required String id,
  required String name,
  double price = 10,
  Map<String, dynamic>? recipe,
  List<Map<String, dynamic>> variants = const [],
}) => <String, dynamic>{
  'menuItemId': id,
  'posMenuItemId': 'pos-$id',
  'nameKa': name,
  'nameEn': name,
  'price': price,
  'categoryName': 'მთავარი',
  'recipe': recipe,
  'variants': variants,
};

Map<String, dynamic> _summary({int components = 1, bool active = true}) =>
    <String, dynamic>{
      'id': 'recipe-1',
      'isActive': active,
      'revision': 1,
      'componentCount': components,
    };

final _menu = <RecipeMenuItem>[
  RecipeMenuItem.fromJson(
    _menuItem(
      id: 'menu-khinkali',
      name: 'ხინკალი',
      price: 1.2,
      recipe: _summary(components: 4),
    ),
  ),
  RecipeMenuItem.fromJson(
    _menuItem(id: 'menu-burger', name: 'Burger', price: 18),
  ),
  RecipeMenuItem.fromJson(
    _menuItem(
      id: 'menu-pizza',
      name: 'Pizza',
      price: 20,
      variants: [
        {
          'variantId': 'variant-small',
          'posMenuVariantId': 'pos-variant-small',
          'size': 30,
          'price': 20,
          'recipe': {
            'id': 'recipe-small',
            'isActive': true,
            'componentCount': 2,
          },
        },
        {
          'variantId': 'variant-large',
          'posMenuVariantId': 'pos-variant-large',
          'size': 45,
          'price': 28,
          'recipe': null,
        },
      ],
    ),
  ),
];

Widget _tab({List<RecipeMenuItem>? menu, List<StockItem>? stockItems}) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: InventoryAdminTab(
          initialSection: 3,
          loadStockItems: () async =>
              stockItems ?? [_beef, _flour, _draftBeer, _cola],
          loadSuppliers: () async => const <Supplier>[],
          loadReceivings: () async => const ReceivingPage(receivings: []),
          loadRecipes: () async => menu ?? _menu,
        ),
      ),
    );

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: Center(child: child)),
);

MenuRecipeDetail _detail({
  String menuItemId = 'menu-khinkali',
  String name = 'ხინკალი',
  double price = 1.2,
  String? variantId,
  String? variantLabel,
  Map<String, dynamic>? recipe,
}) => MenuRecipeDetail.fromJson(<String, dynamic>{
  'menuItemId': menuItemId,
  'posMenuItemId': 'pos-$menuItemId',
  'menuItemName': name,
  'price': price,
  'variantId': variantId,
  'variantLabel': variantLabel,
  'recipe': recipe,
});

Map<String, dynamic> _recipe({
  String id = 'recipe-1',
  String yieldQuantity = '1.000',
  required List<Map<String, dynamic>> components,
}) => <String, dynamic>{
  'id': id,
  'menuItemId': 'menu-khinkali',
  'menuItemName': 'ხინკალი',
  'isActive': true,
  'revision': 1,
  'yieldQuantity': yieldQuantity,
  'components': components,
};

Map<String, dynamic> _component({
  required String stockItemId,
  required String name,
  required String quantity,
  required String unit,
  required String baseQuantity,
  required String baseUnit,
}) => <String, dynamic>{
  'stockItemId': stockItemId,
  'stockItemName': name,
  'quantity': quantity,
  'unit': unit,
  'baseQuantity': baseQuantity,
  'baseUnit': baseUnit,
  'baseQuantityPerUnit': baseQuantity,
};

void main() {
  group('the Recipes list', () {
    testWidgets('is Menu-oriented and flags what is not configured', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventory-menu-results')), findsOneWidget);
      expect(find.text('ხინკალი'), findsOneWidget);
      // The product with no definition is a first-class row, not an absence.
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('4 ინგრედიენტი'), findsOneWidget);
      expect(find.text('შემადგენლობა შესავსებია'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters to the products still missing a definition', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      // Status filters are visible above the selected category.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-filter-unlinked')));
      await tester.pumpAndSettle();
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('ხინკალი'), findsNothing);

      await tester.tap(find.byKey(const Key('recipe-filter-linked')));
      await tester.pumpAndSettle();
      expect(find.text('ხინკალი'), findsOneWidget);
      expect(find.text('Burger'), findsNothing);
    });

    testWidgets('searches Menu Items by name', (tester) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('inventory-menu-search')),
        'burg',
      );
      await tester.pumpAndSettle();
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('ხინკალი'), findsNothing);
    });

    testWidgets('offers one entry per variant, each with its own status', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recipe-variant-variant-small')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('recipe-variant-variant-large')),
        findsOneWidget,
      );
      expect(find.text('30.0 · 2 ინგრედიენტი'), findsOneWidget);
      expect(find.text('45.0 · შემადგენლობა შესავსებია'), findsOneWidget);
    });

    testWidgets('lays out on a narrow phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventory-menu-results')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the direct product link', () {
    testWidgets('opens in the simple mode and saves one component', (
      tester,
    ) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-cola',
            menuItemName: 'Coca-Cola 0.5L',
            stockItems: [_cola, _beef],
            load: () async => _detail(
              menuItemId: 'menu-cola',
              name: 'Coca-Cola 0.5L',
              price: 4,
            ),
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recipe-editor')), findsOneWidget);
      // The selling price is context, and read-only.
      expect(find.text('გასაყიდი ფასი: 4.00 ₾'), findsOneWidget);
      expect(find.text('1 გაყიდვა = მარაგიდან'), findsOneWidget);
      // A direct link has no ingredient list to grow.
      expect(find.byKey(const Key('recipe-add-component')), findsNothing);
      expect(find.byKey(const Key('recipe-yield')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['menuItemId'], 'menu-cola');
      expect(saved!['variantId'], isNull);
      expect(saved!['yieldQuantity'], '1');
      expect(saved!['components'], [
        {'stockItemId': 'stock-cola', 'quantity': '1', 'unit': 'bottle'},
      ]);
    });

    testWidgets('reads an existing one-component card as a link', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-cola',
            menuItemName: 'Coca-Cola 0.5L',
            stockItems: [_cola],
            load: () async => _detail(
              menuItemId: 'menu-cola',
              name: 'Coca-Cola 0.5L',
              recipe: _recipe(
                components: [
                  _component(
                    stockItemId: 'stock-cola',
                    name: 'Coca-Cola 0.5L',
                    quantity: '1.000',
                    unit: 'bottle',
                    baseQuantity: '1.000',
                    baseUnit: 'bottle',
                  ),
                ],
              ),
            ),
            save: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recipe-yield')), findsNothing);
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);
      // A configured card offers a way to stop applying it.
      expect(find.byKey(const Key('recipe-disable')), findsOneWidget);
    });
  });

  group('the draft beverage', () {
    testWidgets('shows the normalized litres before anything is saved', (
      tester,
    ) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-beer',
            menuItemName: 'Draft Beer 0.5L',
            stockItems: [_draftBeer],
            load: () async =>
                _detail(menuItemId: 'menu-beer', name: 'Draft Beer 0.5L'),
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-component-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('მლ').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '500',
      );
      await tester.pumpAndSettle();

      // 500 ml of a tank held in litres, said while it is still editable.
      expect(find.byKey(const Key('recipe-component-base-0')), findsOneWidget);
      expect(find.text('500 მლ = 0.5 ლ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();
      expect(saved!['components'], [
        {'stockItemId': 'stock-beer', 'quantity': '500', 'unit': 'ml'},
      ]);
    });

    testWidgets('never offers the keg as a consumption unit', (tester) async {
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-beer',
            menuItemName: 'Draft Beer 0.5L',
            stockItems: [_draftBeer],
            load: () async =>
                _detail(menuItemId: 'menu-beer', name: 'Draft Beer 0.5L'),
            save: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-component-unit-0')));
      await tester.pumpAndSettle();
      // The item is bought in 30 L kegs; that is procurement, not a pour.
      expect(find.text('ყუთი'), findsNothing);
      expect(find.text('მლ'), findsWidgets);
      expect(find.text('ლ'), findsWidgets);
    });
  });

  group('the multi-ingredient recipe', () {
    testWidgets('adds ingredients and saves them all', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-khinkali',
            menuItemName: 'ხინკალი',
            stockItems: [_beef, _flour],
            load: () async => _detail(),
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('რამდენიმე ინგრედიენტის დამატება'));
      await tester.pumpAndSettle();
      expect(find.text('რამდენიმე პორციაზე მომზადება'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recipe-component-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('გ').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '35',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-add-component')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flour').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-1')),
        '25',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      // A kitchen weighs in grams, so that is what the editor offers first.
      expect(saved!['components'], [
        {'stockItemId': 'stock-beef', 'quantity': '35', 'unit': 'g'},
        {'stockItemId': 'stock-flour', 'quantity': '25', 'unit': 'g'},
      ]);
    });

    testWidgets('carries a batch yield through to the payload', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-khinkali',
            menuItemName: 'ხინკალი',
            stockItems: [_beef],
            load: () async => _detail(),
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('რამდენიმე ინგრედიენტის დამატება'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-component-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('კგ').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '3.5',
      );
      await tester.ensureVisible(find.text('რამდენიმე პორციაზე მომზადება'));
      await tester.tap(find.text('რამდენიმე პორციაზე მომზადება'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('recipe-yield')), '100');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      // Cloud divides; the editor only says how many portions this describes.
      expect(saved!['yieldQuantity'], '100');
      expect(saved!['components'], [
        {'stockItemId': 'stock-beef', 'quantity': '3.5', 'unit': 'kg'},
      ]);
    });

    testWidgets('refuses the same Stock Item twice', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var saves = 0;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-khinkali',
            menuItemName: 'ხინკალი',
            stockItems: [_beef, _flour],
            load: () async => _detail(),
            save: (_) async => saves++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('რამდენიმე ინგრედიენტის დამატება'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '1',
      );
      await tester.tap(find.byKey(const Key('recipe-add-component')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beef').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-1')),
        '2',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      expect(saves, 0);
      expect(find.textContaining('ორჯერ'), findsOneWidget);
    });
  });

  group('variants', () {
    testWidgets('save against the variant that was opened', (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-pizza',
            menuItemName: 'Pizza',
            variantId: 'variant-large',
            variantLabel: '45.0',
            stockItems: [_flour],
            load: () async => _detail(
              menuItemId: 'menu-pizza',
              name: 'Pizza',
              price: 28,
              variantId: 'variant-large',
              variantLabel: '45.0',
            ),
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pizza · 45.0'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '0.32',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      // Stable variant identity, never inferred from the size label.
      expect(saved!['variantId'], 'variant-large');
      expect(saved!['menuItemId'], 'menu-pizza');
    });
  });

  group('the Stock Item creation assist', () {
    testWidgets('pre-fills only the name and keeps identities separate', (
      tester,
    ) async {
      String? prefilled;
      final created = StockItem.fromJson({
        'id': 'stock-new',
        'name': 'Orange Juice 0.5L',
        'baseUnit': 'bottle',
        'isActive': true,
        'currentStock': '0.000',
        'recipeUnits': ['bottle'],
        'createdAt': '2026-09-10T10:00:00Z',
        'updatedAt': '2026-09-10T10:00:00Z',
      });

      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-juice',
            menuItemName: 'Orange Juice 0.5L',
            stockItems: const <StockItem>[],
            load: () async =>
                _detail(menuItemId: 'menu-juice', name: 'Orange Juice 0.5L'),
            save: (payload) async => saved = payload,
            onCreateStockItem: (name) async {
              prefilled = name;
              return created;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('recipe-create-stock-item')),
      );
      await tester.tap(find.byKey(const Key('recipe-create-stock-item')));
      await tester.pumpAndSettle();

      expect(prefilled, 'Orange Juice 0.5L');
      // A Menu Item and a Stock Item are never the same identity.
      expect(created.id, isNot('menu-juice'));

      await tester.enterText(
        find.byKey(const Key('recipe-component-quantity-0')),
        '1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-save')));
      await tester.pumpAndSettle();

      expect(saved!['components'], [
        {'stockItemId': 'stock-new', 'quantity': '1', 'unit': 'bottle'},
      ]);
    });
  });

  group('disabling', () {
    testWidgets('stops applying a card without deleting it', (tester) async {
      String? disabled;
      await tester.pumpWidget(
        _host(
          RecipeEditorDialog(
            menuItemId: 'menu-khinkali',
            menuItemName: 'ხინკალი',
            stockItems: [_beef],
            load: () async => _detail(
              recipe: _recipe(
                components: [
                  _component(
                    stockItemId: 'stock-beef',
                    name: 'Beef',
                    quantity: '35.000',
                    unit: 'g',
                    baseQuantity: '0.035',
                    baseUnit: 'kg',
                  ),
                ],
              ),
            ),
            save: (_) async {},
            disable: (id) async => disabled = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipe-disable')));
      await tester.pumpAndSettle();
      expect(disabled, 'recipe-1');
    });
  });
  group('the Stock Item detail', () {
    testWidgets('answers which products consume this item', (tester) async {
      await tester.pumpWidget(
        _host(
          StockItemDetailDialog(
            stockItemId: 'stock-beef',
            load: () async => StockItemDetail.fromJson(<String, dynamic>{
              'id': 'stock-beef',
              'name': 'Beef',
              'baseUnit': 'kg',
              'isActive': true,
              'minimumStock': '10.000',
              'currentStock': '62.500',
              'stockStatus': 'OK',
              'createdAt': '2026-09-10T10:00:00Z',
              'updatedAt': '2026-09-10T10:00:00Z',
              'usedBy': [
                {
                  'recipeId': 'recipe-1',
                  'menuItemId': 'menu-khinkali',
                  'menuItemName': 'ხინკალი',
                  'quantityPerUnit': '0.035000',
                  'baseUnit': 'kg',
                },
                {
                  'recipeId': 'recipe-2',
                  'menuItemId': 'menu-burger',
                  'menuItemName': 'Burger',
                  'quantityPerUnit': '0.150000',
                  'baseUnit': 'kg',
                },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('გამოიყენება პროდუქტებში'), findsOneWidget);
      expect(
        find.byKey(const Key('stock-detail-usage-recipe-1')),
        findsOneWidget,
      );
      expect(find.text('ხინკალი'), findsOneWidget);
      expect(find.text('35 გ'), findsOneWidget);
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('150 გ'), findsOneWidget);
    });

    testWidgets('says plainly what a minimum stock threshold means', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          StockItemDetailDialog(
            stockItemId: 'stock-beef',
            load: () async => StockItemDetail.fromJson(<String, dynamic>{
              'id': 'stock-beef',
              'name': 'Beef',
              'baseUnit': 'kg',
              'isActive': true,
              'minimumStock': '10.000',
              'currentStock': '62.500',
              'stockStatus': 'OK',
              'createdAt': '2026-09-10T10:00:00Z',
              'updatedAt': '2026-09-10T10:00:00Z',
              'purchaseUnits': [
                {'id': 'pu-1', 'unit': 'box', 'baseUnitMultiplier': '24'},
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A threshold, not a balance — and both read in Georgian.
      expect(find.text('მინიმალური მარაგი'), findsOneWidget);
      expect(find.text('10 კგ'), findsOneWidget);
      expect(
        find.byKey(const Key('stock-detail-minimum-help')),
        findsOneWidget,
      );
      expect(find.text('კილოგრამი (კგ)'), findsOneWidget);
      expect(find.text('როგორ მოდის მომწოდებლისგან?'), findsOneWidget);
      expect(find.text('1 ყუთი = 24 კგ'), findsOneWidget);
      // Nothing consumes it yet, so the section is absent rather than empty.
      expect(find.text('გამოიყენება პროდუქტებში'), findsNothing);
    });

    testWidgets('explains the minimum-stock field in the editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-show-all')));
      await tester.pumpAndSettle();

      await openInventorySection(tester, 'stockItems');
      await tester.pumpAndSettle();
      await tester.tap(find.text('რედაქტირება').first);
      await tester.pumpAndSettle();

      expect(find.text('მინიმალური მარაგი'), findsOneWidget);
      expect(find.byKey(const Key('minimum-stock-help')), findsOneWidget);
      expect(find.text('როგორ მოდის მომწოდებლისგან?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
