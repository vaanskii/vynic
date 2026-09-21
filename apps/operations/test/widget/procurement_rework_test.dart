import 'inventory_test_actions.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/inventory_decimal.dart';

Widget app(Widget child) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, fontFamily: 'NotoSansGeorgian'),
    home: Scaffold(body: child),
  ),
);
void size(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> shot(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  final image = await t.runAsync(() => boundary.toImage());
  final data = await t.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  await t.runAsync(
    () => File(
      '/tmp/procurement-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List()),
  );
  image!.dispose();
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
  test('decimal previews preserve cents and derive exact kg price', () {
    expect(
      (InventoryDecimal.parse('0.1') + InventoryDecimal.parse('0.2'))
          .toStringAsFixed(2),
      '0.30',
    );
    expect(
      (InventoryDecimal.parse('800') / InventoryDecimal.parse('20'))
          .toStringAsFixed(6),
      '40.000000',
    );
    expect(
      (InventoryDecimal.parse('10') *
              InventoryDecimal.parse('10') *
              InventoryDecimal.parse('1.2'))
          .toStringAsFixed(2),
      '120.00',
    );
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('supplier direct Menu creation at $width', (t) async {
      size(t, width);
      Map<String, dynamic>? sent;
      await t.pumpWidget(
        app(
          SuppliedItemDialog(
            supplierId: 'supplier',
            stockItems: const [],
            menuItems: const [
              RecipeMenuItem(
                menuItemId: 'borjomi',
                name: 'ბორჯომი 0.5L',
                price: 5,
              ),
            ],
            save: (p) async {
              sent = p;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('supplied-mode-menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('supplied-menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('menu-show-all')));
      await t.pumpAndSettle();
      await t.tap(find.text('ბორჯომი 0.5L').last);
      await t.pumpAndSettle();
      expect(find.text('როგორ ვითვლით? ცალი'), findsOneWidget);
      await shot(t, 'supplier-${width.toInt()}');
      await t.tap(find.byKey(const Key('supplied-save')));
      await t.pumpAndSettle();
      expect(sent?['menuItemId'], 'borjomi');
      expect(
        (sent?['purchaseUnits'] as List).first['baseUnitMultiplier'],
        '10',
      );
      expect(t.takeException(), isNull);
    });
    testWidgets('receiving full value and posting intent at $width', (t) async {
      size(t, width);
      Map<String, dynamic>? sent;
      final supplier = Supplier.fromJson({
        'id': 'meat',
        'name': 'ხორცი (ბაზარი)',
        'stockItemIds': ['beef'],
      });
      final beef = StockItem.fromJson({
        'id': 'beef',
        'name': 'საქონლის ხორცი',
        'baseUnit': 'kg',
      });
      await t.pumpWidget(
        app(
          ReceivingEditorDialog(
            suppliers: [supplier],
            stockItems: [beef],
            businessDate: '2026-09-05',
            save: (p) async {
              sent = p;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await chooseReceivingProduct(t);
      await t.ensureVisible(find.byKey(const Key('receiving-price-mode-0')));
      await t.tap(find.text('მთლიანი თანხა').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('receiving-line-quantity-0')),
        '20',
      );
      await t.enterText(find.byKey(const Key('receiving-line-cost-0')), '800');
      await t.pumpAndSettle();
      await shot(t, 'receiving-${width.toInt()}');
      await reviewReceiving(t);
      await t.tap(find.byKey(const Key('receiving-save')));
      await t.pumpAndSettle();
      expect(sent?['post'], true);
      expect((sent?['lines'] as List).first['lineTotal'], '800');
      expect(
        (sent?['lines'] as List).first.containsKey('unitPurchaseCost'),
        false,
      );
      expect(t.takeException(), isNull);
    });
    testWidgets('payment retry retains identity and mobile layout at $width', (
      t,
    ) async {
      size(t, width);
      final sent = <Map<String, dynamic>>[];
      await t.pumpWidget(
        app(
          SupplierPaymentDialog(
            receiving: const {'id': 'receipt', 'remaining': '70.00'},
            save: (p) async {
              sent.add(p);
              if (sent.length == 1) throw Exception('Retry connection');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('supplier-payment-amount')), '50');
      await t.tap(find.byKey(const Key('supplier-payment-save')));
      await t.pumpAndSettle();
      expect(find.textContaining('Retry connection'), findsOneWidget);
      await shot(t, 'payment-${width.toInt()}');
      await t.tap(find.byKey(const Key('supplier-payment-save')));
      await t.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent[0]['requestId'], sent[1]['requestId']);
      expect(sent[1]['amount'], '50');
      expect(t.takeException(), isNull);
    });
  }
}

// Receipt creation now starts with an explicit selection, even for one product.
Future<void> chooseReceivingProduct(WidgetTester tester) async {
  final blank = find.byKey(const ValueKey('receiving-line-item-0-null'));
  if (blank.evaluate().isEmpty) return;
  await tester.ensureVisible(blank);
  await tester.pumpAndSettle();
  await tester.tap(blank);
  await tester.pumpAndSettle();
  final options = find.descendant(
    of: find.byType(InventoryIngredientPicker),
    matching: find.byType(ListTile),
  );
  if (options.evaluate().isEmpty) return;
  await tester.tap(options.first);
  await tester.pumpAndSettle();
}
