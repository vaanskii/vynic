import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';

final beef = StockItem.fromJson({
  'id': 'beef',
  'name': 'საქონლის ხორცი',
  'baseUnit': 'kg',
  'classification': 'FOOD',
});
final borjomi = StockItem.fromJson({
  'id': 'borjomi',
  'name': 'ბორჯომი 0.5L',
  'baseUnit': 'piece',
  'classification': 'BEVERAGE',
  'supplierIds': ['supplier'],
  'purchaseUnits': [
    {'id': 'pack-unit', 'unit': 'pack', 'baseUnitMultiplier': '10'},
  ],
});
final bakuriani = StockItem.fromJson({
  'id': 'bakuriani',
  'name': 'ბაკურიანი 0.5L',
  'baseUnit': 'piece',
  'classification': 'BEVERAGE',
});
final supplier = Supplier.fromJson({
  'id': 'supplier',
  'name': 'Borjomi',
  'stockItemIds': ['borjomi', 'bakuriani'],
});
final stocks = [beef, borjomi, bakuriani];
const imageKey = Key('catalog-qa');
Widget app(Widget child) => RepaintBoundary(
  key: imageKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'NotoSansGeorgian',
    ),
    home: Scaffold(body: child),
  ),
);
void narrow(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['INVENTORY_QA_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(imageKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansGeorgian')
      ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
    await loader.load();
    await (FontLoader(
      'Ahem',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'catalog classification filters and Georgian stock form at 390px',
    (tester) async {
      narrow(tester);
      await tester.pumpWidget(
        app(
          InventoryAdminTab(
            initialSection: 0,
            loadStockItems: () async => stocks,
            loadSuppliers: () async => [supplier],
            loadReceivings: () async => const ReceivingPage(receivings: []),
            loadRecipes: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('სასმელები'));
      await tester.pumpAndSettle();
      expect(find.text(beef.name), findsNothing);
      expect(find.text(borjomi.name), findsOneWidget);
      await screenshot(tester, 'catalog-mobile');
      await tester.tap(find.text('რედაქტირება').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-classification')), findsOneWidget);
      expect(find.text('როგორ ვითვლით საწყობში?'), findsOneWidget);
      expect(find.text('SKU'), findsNothing);
      expect(find.text('FOOD'), findsNothing);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'stock-editor-mobile');
    },
  );

  testWidgets(
    'supplier products link/unlink and recent receiving history at 390px',
    (tester) async {
      narrow(tester);
      final links = <String>{'borjomi'};
      await tester.pumpWidget(
        app(
          SupplierDetailDialog(
            supplier: supplier,
            stockItems: stocks,
            load: () async => {
              'products': stocks
                  .where((s) => links.contains(s.id))
                  .map((s) => {'id': s.id, 'name': s.name})
                  .toList(),
              'recentReceivings': [
                {
                  'id': 'receipt',
                  'businessDate': '2026-09-06',
                  'supplierNameSnapshot': 'Borjomi',
                  'documentTotal': '120.00',
                  'status': 'POSTED',
                },
              ],
            },
            setLink: (id, linked) async {
              if (linked) {
                links.add(id);
              } else {
                links.remove(id);
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('რას გვაწვდის'), findsOneWidget);
      expect(find.text('ბოლო მიღებები'), findsOneWidget);
      expect(find.text('არსებული საქონლის არჩევა'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, borjomi.name),
          matching: find.byTooltip('მიბმის მოხსნა'),
        ),
      );
      await tester.pumpAndSettle();
      expect(links, isNot(contains('borjomi')));
      expect(find.text('2026-09-06 · 120.00 ₾'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'supplier-mobile');
    },
  );

  testWidgets(
    'daily market prioritizes supplier products, packaging and business date',
    (tester) async {
      narrow(tester, height: 1100);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        app(
          ReceivingEditorDialog(
            suppliers: [supplier],
            stockItems: stocks,
            businessDate: '2026-09-05',
            save: (value) async => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('თარიღი და დოკუმენტის დეტალები'));
      await tester.pumpAndSettle();
      expect(find.text('სამუშაო დღე: 2026-09-05'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('receiving-line-item-0-borjomi')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('receiving-line-unit-0')),
      );
      await tester.tap(find.byKey(const Key('receiving-line-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('შეკვრა').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('receiving-line-quantity-0')),
        '10',
      );
      await tester.enterText(
        find.byKey(const Key('receiving-line-cost-0')),
        '1.20',
      );
      await tester.pumpAndSettle();
      expect(find.text('მიღებული: 100 ცალი'), findsOneWidget);
      expect(find.text('1 შეკვრა = 10 ცალი'), findsOneWidget);
      expect(find.text('120.00 ₾'), findsWidgets);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'daily-market-mobile');
      await tester.tap(find.byKey(const Key('receiving-save')));
      await tester.pumpAndSettle();
      expect(saved?['businessDate'], '2026-09-05');
      expect((saved?['lines'] as List).single['unitPurchaseCost'], '1.20');
    },
  );

  testWidgets('menu separates dishes and beverages using the menu hierarchy', (
    tester,
  ) async {
    narrow(tester);
    await tester.pumpWidget(
      app(
        InventoryAdminTab(
          initialSection: 3,
          loadStockItems: () async => stocks,
          loadSuppliers: () async => [supplier],
          loadReceivings: () async => const ReceivingPage(receivings: []),
          loadRecipes: () async => const [
            RecipeMenuItem(
              menuItemId: 'dish',
              name: 'ხინკალი',
              price: 2.5,
              menuGroup: 'FOOD',
            ),
            RecipeMenuItem(
              menuItemId: 'drink',
              name: 'ბორჯომი',
              price: 3,
              menuGroup: 'BEVERAGE',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('კერძები'));
    await tester.pumpAndSettle();
    expect(find.text('ხინკალი'), findsOneWidget);
    expect(find.text('ბორჯომი'), findsNothing);
    await tester.tap(find.text('სასმელები'));
    await tester.pumpAndSettle();
    expect(find.text('ბორჯომი'), findsOneWidget);
    expect(find.text('ხინკალი'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current theoretical cost and exact component amounts at 390px', (
    tester,
  ) async {
    narrow(tester);
    await tester.pumpWidget(
      app(
        RecipeEditorDialog(
          menuItemId: 'khinkali',
          menuItemName: 'ხინკალი',
          menuGroup: 'FOOD',
          stockItems: stocks,
          load: () async => MenuRecipeDetail.fromJson({
            'menuItemId': 'khinkali',
            'menuItemName': 'ხინკალი',
            'price': 2.5,
            'recipe': {
              'id': 'recipe-khinkali',
              'menuItemId': 'khinkali',
              'menuItemName': 'ხინკალი',
              'isActive': true,
              'components': [
                {
                  'stockItemId': 'beef',
                  'stockItemName': beef.name,
                  'quantity': '0.035',
                  'unit': 'kg',
                  'baseQuantity': '0.035',
                  'baseUnit': 'kg',
                  'baseQuantityPerUnit': '0.035000',
                },
              ],
            },
            'currentCost': {
              'status': 'AVAILABLE',
              'total': '0.65',
              'components': [
                {
                  'stockItemName': beef.name,
                  'quantity': '0.035000',
                  'baseUnit': 'kg',
                  'weightedUnitCost': '18.500000',
                  'cost': '0.647500',
                },
              ],
            },
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('გასაყიდი ფასი: 2.50 ₾'), findsOneWidget);
    expect(find.text('მიმდინარე თვითღირებულება: 0.65 ₾'), findsOneWidget);
    await tester.ensureVisible(
      find.text('შენახული შემადგენლობით · საშუალო შესყიდვის ფასი'),
    );
    await tester.tap(
      find.text('შენახული შემადგენლობით · საშუალო შესყიდვის ფასი'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('0.6475 ₾'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'recipe-cost-mobile');
  });

  testWidgets('missing procurement cost is visible rather than a zero total', (
    tester,
  ) async {
    narrow(tester);
    await tester.pumpWidget(
      app(
        const CurrentRecipeCostPanel(
          cost: CurrentRecipeCost(status: 'MISSING_COMPONENT_COST'),
        ),
      ),
    );
    expect(
      find.text('მიმდინარე თვითღირებულება: ვერ გამოითვლება'),
      findsOneWidget,
    );
    expect(
      find.text('ზოგი ინგრედიენტის შესყიდვის ფასი ჯერ არ გვაქვს.'),
      findsOneWidget,
    );
    expect(find.textContaining('0.00'), findsNothing);
  });
}
