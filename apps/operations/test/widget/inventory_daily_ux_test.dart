import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';
import 'procurement_rework_test.dart' as qa;
import 'manager_catalog_cost_test.dart' as fixtures;

final beef = StockItem.fromJson({
  'id': 'beef',
  'name': 'საქონლის ხორცი',
  'baseUnit': 'kg',
  'recipeUnits': ['g', 'kg'],
});
final beer = StockItem.fromJson({
  'id': 'beer',
  'name': 'ჩამოსასხმელი ლუდი',
  'baseUnit': 'L',
  'recipeUnits': ['L', 'ml'],
  'classification': 'BEVERAGE',
});
final menu = [
  const RecipeMenuItem(
    menuItemId: 'khinkali',
    name: 'ხინკალი',
    price: 2,
    menuGroup: 'FOOD',
  ),
  const RecipeMenuItem(
    menuItemId: 'water',
    name: 'ბორჯომი',
    price: 4,
    menuGroup: 'BEVERAGE',
  ),
];
MenuRecipeDetail detail(String name, StockItem item, String qty, String unit) =>
    MenuRecipeDetail.fromJson({
      'menuItemId': name,
      'menuItemName': name,
      'price': 4,
      'recipe': {
        'id': 'recipe-$name',
        'yieldQuantity': '1',
        'isActive': true,
        'components': [
          {
            'stockItemId': item.id,
            'stockItemName': item.name,
            'quantity': qty,
            'unit': unit,
            'baseUnit': item.baseUnit.wireValue,
            'baseQuantityPerUnit': qty,
          },
        ],
      },
    });
Future<void> select(WidgetTester t, Key key, String text) async {
  await t.ensureVisible(find.byKey(key));
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final name in ['NotoSansGeorgian', 'Ahem']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('daily home with explicit draft and posted states $width', (
      t,
    ) async {
      qa.size(t, width);
      await t.pumpWidget(
        qa.app(
          InventoryAdminTab(
            loadStockItems: () async => fixtures.stocks,
            loadSuppliers: () async => [fixtures.supplier],
            loadRecipes: () async => menu,
            loadReceivings: () async => ReceivingPage(
              currentBusinessDate: '2026-09-10',
              receivings: [
                for (final status in ['DRAFT', 'POSTED'])
                  Receiving.fromJson({
                    'id': status,
                    'status': status,
                    'supplierName': 'Borjomi',
                    'documentDate': '2026-09-10',
                    'documentTotal': '120.00',
                  }),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inventory-home')), findsOneWidget);
      expect(find.byKey(const Key('inventory-section-selector')), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('მარაგში ჯერ არ დამატებულა'), findsOneWidget);
      expect(find.text('მარაგში დაემატა'), findsOneWidget);
      await qa.shot(t, 'ux-home-${width.toInt()}');
      expect(t.takeException(), isNull);
    });
    testWidgets('supplier detail with one primary action $width', (t) async {
      qa.size(t, width);
      await t.pumpWidget(
        qa.app(
          SupplierDetailDialog(
            supplier: fixtures.supplier,
            stockItems: fixtures.stocks,
            load: () async => {
              'products': [
                {'id': 'borjomi', 'name': 'ბორჯომი 0.5L'},
                {'id': 'bakuriani', 'name': 'ბაკურიანი 0.5L'},
              ],
              'settlement': {'outstanding': '120.00', 'unverified': '0.00'},
              'recentReceivings': [],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('რას გვაწვდის'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await qa.shot(t, 'ux-supplier-${width.toInt()}');
      expect(t.takeException(), isNull);
    });
    testWidgets(
      'daily receiving selects usual goods and partial payment $width',
      (t) async {
        qa.size(t, width);
        Map<String, dynamic>? sent;
        await t.pumpWidget(
          qa.app(
            ReceivingEditorDialog(
              suppliers: [fixtures.supplier],
              stockItems: fixtures.stocks,
              businessDate: '2026-09-10',
              save: (p) async => sent = p,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('receiving-line-quantity-0')),
          '10',
        );
        await t.enterText(
          find.byKey(const Key('receiving-line-cost-0')),
          '1.20',
        );
        await t.pumpAndSettle();
        expect(find.text('მიღებული: 100 ცალი'), findsOneWidget);
        await qa.shot(t, 'ux-receiving-${width.toInt()}');
        await select(
          t,
          const Key('receiving-payment-mode'),
          'ნაწილობრივ გადავიხადე',
        );
        await t.enterText(find.byKey(const Key('receiving-paid-now')), '50');
        await t.pumpAndSettle();
        expect(find.text('დარჩა: 70.00 ₾'), findsOneWidget);
        await qa.shot(t, 'ux-receiving-payment-${width.toInt()}');
        await t.tap(find.byKey(const Key('receiving-save')));
        await t.pumpAndSettle();
        expect(sent?['post'], true);
        expect((sent?['lines'] as List).length, 1);
        expect((sent?['payment'] as Map)['amount'], '50');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('menu composition searches existing menu $width', (t) async {
      qa.size(t, width);
      await t.pumpWidget(
        qa.app(
          InventoryAdminTab(
            initialSection: 3,
            loadStockItems: () async => fixtures.stocks,
            loadSuppliers: () async => [],
            loadReceivings: () async => const ReceivingPage(receivings: []),
            loadRecipes: () async => menu,
          ),
        ),
      );
      await t.pumpAndSettle();
      await qa.shot(t, 'ux-composition-${width.toInt()}');
      await t.tap(find.text('სასმელები'));
      await t.pumpAndSettle();
      expect(find.text('ბორჯომი'), findsOneWidget);
      expect(find.text('ხინკალი'), findsNothing);
      expect(t.takeException(), isNull);
    });
    for (final mode in ['dish', 'packaged', 'draft']) {
      testWidgets(
        '$mode composition rendering and preserved quantities $width',
        (t) async {
          qa.size(t, width);
          final item = mode == 'dish'
              ? beef
              : mode == 'draft'
              ? beer
              : fixtures.borjomi;
          final qty = mode == 'dish'
              ? '35'
              : mode == 'draft'
              ? '0.500'
              : '1';
          final unit = mode == 'dish' ? 'g' : item.baseUnit.wireValue;
          Map<String, dynamic>? sent;
          await t.pumpWidget(
            qa.app(
              RecipeEditorDialog(
                menuItemId: mode,
                menuItemName: mode == 'dish'
                    ? 'ხინკალი'
                    : mode == 'draft'
                    ? 'ლუდი 0.5L'
                    : 'ბორჯომი',
                menuGroup: mode == 'dish' ? 'FOOD' : 'BEVERAGE',
                stockItems: [item],
                load: () async => detail(mode, item, qty, unit),
                save: (p) async => sent = p,
                onCreateStockItem: (_) async => null,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('recipe-add-component')),
            mode == 'dish' ? findsOneWidget : findsNothing,
          );
          await qa.shot(t, 'ux-$mode-${width.toInt()}');
          await t.tap(find.byKey(const Key('recipe-save')));
          await t.pumpAndSettle();
          expect((sent?['components'] as List).first['unit'], unit);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'self purchase without suppliers freezes source and saves draft without payment',
    (t) async {
      qa.size(t, 360);
      Map<String, dynamic>? sent;
      await t.pumpWidget(
        qa.app(
          ReceivingEditorDialog(
            suppliers: const [],
            stockItems: [fixtures.beef],
            businessDate: '2026-09-10',
            save: (p) async => sent = p,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('receiving-source-label')),
        'ბათუმის ბაზარი',
      );
      await select(t, const Key('receiving-price-mode-0'), 'მთლიანი თანხა');
      await t.enterText(
        find.byKey(const Key('receiving-line-quantity-0')),
        '20',
      );
      await t.enterText(find.byKey(const Key('receiving-line-cost-0')), '800');
      await select(t, const Key('receiving-payment-mode'), 'სრულად გადავიხადე');
      await t.tap(find.byKey(const Key('receiving-save-draft')));
      await t.pumpAndSettle();
      expect(sent?['supplierId'], isNull);
      expect(sent?['sourceType'], 'SELF_PURCHASE');
      expect(sent?['sourceLabel'], 'ბათუმის ბაზარი');
      expect(sent?['post'], false);
      expect(sent?.containsKey('payment'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('ingredient search reuses existing identity', (t) async {
    qa.size(t, 360);
    await t.pumpWidget(
      qa.app(InventoryIngredientPicker(items: fixtures.stocks)),
    );
    await t.enterText(find.byKey(const Key('ingredient-search')), 'ხორცი');
    await t.pumpAndSettle();
    expect(find.text('საქონლის ხორცი'), findsOneWidget);
    expect(find.text('ბორჯომი 0.5L'), findsNothing);
  });
  testWidgets(
    'payment failure after posting retries same payment without adding stock twice',
    (t) async {
      qa.size(t, 360);
      var posts = 0, drafts = 0;
      final payments = <Map<String, dynamic>>[];
      Receiving receipt(String status) => Receiving.fromJson({
        'id': 'receipt',
        'status': status,
        'supplierId': 'supplier',
        'documentDate': '2026-09-10',
        'documentTotal': '800.00',
      });
      await t.pumpWidget(
        qa.app(
          ReceivingEditorDialog(
            suppliers: [fixtures.supplier],
            stockItems: [beef],
            businessDate: '2026-09-10',
            saveDraft: (p) async {
              drafts++;
              return receipt('DRAFT');
            },
            postReceiving: (_) async {
              posts++;
              return receipt('POSTED');
            },
            loadReceiving: (_) async => receipt('POSTED'),
            recordPayment: (_, p) async {
              payments.add(p);
              if (payments.length == 1) throw Exception('Connection lost');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await select(t, const Key('receiving-price-mode-0'), 'მთლიანი თანხა');
      await t.enterText(
        find.byKey(const Key('receiving-line-quantity-0')),
        '20',
      );
      await t.enterText(find.byKey(const Key('receiving-line-cost-0')), '800');
      await select(
        t,
        const Key('receiving-payment-mode'),
        'ნაწილობრივ გადავიხადე',
      );
      await t.enterText(find.byKey(const Key('receiving-paid-now')), '300');
      await t.tap(find.byKey(const Key('receiving-save')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('მარაგში დაემატა. გადახდის ჩაწერა'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('receiving-save')));
      await t.pumpAndSettle();
      expect(posts, 1);
      expect(drafts, 1);
      expect(payments.length, 2);
      expect(payments[0], payments[1]);
      expect(payments[0]['amount'], '300');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('dark theme uses readable surface and action colors', (t) async {
    qa.size(t, 360);
    final previous = ManagerAppPreferences.dashboardAppearance.value;
    ManagerAppPreferences.dashboardAppearance.value =
        ManagerDashboardAppearance.dark;
    addTearDown(
      () => ManagerAppPreferences.dashboardAppearance.value = previous,
    );
    await t.pumpWidget(
      qa.app(
        ReceivingEditorDialog(
          suppliers: [fixtures.supplier],
          stockItems: fixtures.stocks,
          businessDate: '2026-09-10',
          save: (_) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
    final colors = Theme.of(
      t.element(find.byKey(const Key('receiving-save'))),
    ).colorScheme;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    expect(
      contrast(colors.onSurface, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(colors.onPrimary, colors.primary),
      greaterThanOrEqualTo(4.5),
    );
    await qa.shot(t, 'ux-receiving-dark-360');
    expect(t.takeException(), isNull);
  });
  testWidgets('simplifying a batch drink preserves quantity per sale', (
    t,
  ) async {
    qa.size(t, 768);
    Map<String, dynamic>? sent;
    await t.pumpWidget(
      qa.app(
        RecipeEditorDialog(
          menuItemId: 'beer',
          menuItemName: 'ლუდი',
          menuGroup: 'BEVERAGE',
          stockItems: [beer],
          load: () async => MenuRecipeDetail.fromJson({
            'menuItemId': 'beer',
            'price': 5,
            'recipe': {
              'id': 'batch',
              'yieldQuantity': '10',
              'components': [
                {
                  'stockItemId': beer.id,
                  'quantity': '5',
                  'unit': 'L',
                  'baseUnit': 'L',
                  'baseQuantityPerUnit': '0.5',
                },
              ],
            },
          }),
          save: (p) async => sent = p,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('ერთი საქონლიდან ჩამოწერა'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('recipe-save')));
    await t.pumpAndSettle();
    expect(sent?['yieldQuantity'], '1');
    expect((sent?['components'] as List).single['quantity'], '0.500000');
    expect(t.takeException(), isNull);
  });
}
