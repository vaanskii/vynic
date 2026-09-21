import 'inventory_test_actions.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';
import 'procurement_rework_test.dart' as qa;
import 'inventory_final_journeys_test.dart' show tap, enter;

Map<String, dynamic> payable(
  String id,
  String supplier,
  String date,
  String remaining, {
  String status = 'UNPAID',
  List<Map<String, dynamic>> payments = const [],
  bool cancelled = false,
}) => {
  'id': id,
  'supplierId': supplier,
  'supplierName': supplier,
  'status': cancelled ? 'CANCELLED' : 'POSTED',
  'businessDate': date,
  'documentTotal': '100.00',
  'remaining': remaining,
  'paid': '0.00',
  'paymentStatus': status,
  'dueDate': '2026-09-01',
  'payments': payments,
};
Map<String, dynamic> payment(
  String id,
  String date,
  String amount, [
  String? reversal,
]) => {
  'id': id,
  'paymentDate': date,
  'amount': amount,
  'method': 'cash',
  'reversalOfId': reversal,
};
Map<String, dynamic> get settlement => {
  'businessDate': '2026-09-13',
  'receivings': [
    payable(
      'old',
      'Farm',
      '2026-01-01',
      '80.00',
      status: 'PARTIALLY_PAID',
      payments: [payment('recent', '2026-09-12', '20.00')],
    ),
    payable('new', 'Water', '2026-09-12', '100.00'),
    payable('unknown', 'Farm', '2026-09-12', '100.00', status: 'UNVERIFIED'),
    payable(
      'returned',
      'Water',
      '2026-09-10',
      '0.00',
      cancelled: true,
      payments: [
        payment('paid', '2026-09-10', '25.00'),
        payment('refund', '2026-09-12', '-25.00', 'paid'),
      ],
    ),
    payable(
      'historical',
      'Farm',
      '2025-01-01',
      '0.00',
      status: 'PAID',
      payments: [payment('historical', '2025-01-01', '10.00')],
    ),
  ],
};
StockItem stock(String id, {bool active = true}) => StockItem.fromJson({
  'id': id,
  'name': 'პროდუქტი $id',
  'baseUnit': 'kg',
  'isActive': active,
});
InventoryAdminTab inventory({
  int section = 0,
  List<StockItem> items = const [],
}) => InventoryAdminTab(
  initialSection: section,
  loadStockItems: () async => items,
  loadSuppliers: () async => [],
  loadRecipes: () async => [],
  loadReceivings: () async => const ReceivingPage(receivings: []),
);
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
    testWidgets(
      'payments use payment date; debts use receipt date; reversals stay visible $width',
      (t) async {
        qa.size(t, width);
        await t.pumpWidget(
          qa.app(SupplierPayablesScreen(load: () async => settlement)),
        );
        await t.pumpAndSettle();
        await tap(t, find.byKey(const Key('payables-last-30')));
        expect(find.text('მიმდინარე დავალიანება: 180.00 ₾'), findsOneWidget);
        expect(find.byKey(const Key('payable-old')), findsNothing);
        expect(find.byKey(const Key('payable-new')), findsOneWidget);
        expect(find.byKey(const Key('payable-returned')), findsNothing);
        await qa.shot(t, 'flow-debts-${width.toInt()}');
        await tap(t, find.byKey(const Key('payables-status')));
        await tap(t, find.text('შესამოწმებელი').last);
        expect(find.byKey(const Key('payable-unknown')), findsOneWidget);
        expect(find.byKey(const Key('payable-new')), findsNothing);
        await tap(t, find.byKey(const Key('payables-payments')));
        expect(find.text('პერიოდში გადახდილი: 20.00 ₾'), findsOneWidget);
        expect(find.byKey(const Key('payment-historical')), findsNothing);
        await qa.shot(t, 'flow-payments-${width.toInt()}');
        await t.drag(
          find.byKey(const Key('payables-list')),
          const Offset(0, -350),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const Key('payment-refund')), findsOneWidget);
        expect(
          find.byTooltip('გადახდის უკუქცევა'),
          findsOneWidget,
        ); // Only the unreversed payment.
        await tap(t, find.byKey(const ValueKey('payables-supplier-all')));
        await tap(t, find.text('Water').last);
        expect(find.text('პერიოდში გადახდილი: 0.00 ₾'), findsOneWidget);
        expect(find.byKey(const Key('payment-recent')), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'stock removal confirms, hides from active list, and restores same identity $width',
      (t) async {
        qa.size(t, width);
        var active = true;
        final writes = <Map<String, dynamic>>[];
        final client = MockClient((r) async {
          expect(r.method, 'PATCH');
          expect(r.url.path.endsWith('/stock-items/mistake'), true);
          final payload = jsonDecode(r.body) as Map<String, dynamic>;
          writes.add(payload);
          active = payload['isActive'] as bool;
          return http.Response(
            jsonEncode(stock('mistake', active: active).toJson()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(
              InventoryAdminTab(
                initialSection: 0,
                loadStockItems: () async => [stock('mistake', active: active)],
                loadSuppliers: () async => [],
                loadRecipes: () async => [],
                loadReceivings: () async => const ReceivingPage(receivings: []),
              ),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, find.text('ამოღება სიიდან'));
          expect(writes, isEmpty);
          await tap(t, find.text('არქივში გადატანა'));
          expect(writes, hasLength(1));
          expect(active, false);
          expect(find.text('პროდუქტი mistake'), findsNothing);
          await tap(t, find.byKey(const Key('inventory-archived')));
          expect(find.text('პროდუქტი mistake'), findsOneWidget);
          await qa.shot(t, 'flow-archive-${width.toInt()}');
          await tap(t, find.text('აღდგენა'));
          expect(writes.map((r) => r['isActive']), [false, true]);
          await tap(t, find.byKey(const Key('inventory-archived')));
          expect(find.text('პროდუქტი mistake'), findsOneWidget);
          expect(t.takeException(), isNull);
        }, () => client);
      },
    );
    testWidgets(
      'receiving creates packaged stock inline and requires an explicit product $width',
      (t) async {
        qa.size(t, width);
        final writes = <Map<String, dynamic>>[];
        Map<String, dynamic>? received;
        final client = MockClient((r) async {
          expect(r.url.path.endsWith('/stock-items'), true);
          final payload = jsonDecode(r.body) as Map<String, dynamic>;
          writes.add(payload);
          return http.Response(
            jsonEncode({
              ...payload,
              'id': 'created',
              'purchaseUnits': [
                for (final p in (payload['purchaseUnits'] as List))
                  {...p as Map, 'id': 'pack'},
              ],
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(
              ReceivingEditorDialog(
                suppliers: const [],
                stockItems: [stock('existing')],
                businessDate: '2026-09-13',
                save: (p) async => received = p,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('receiving-line-item-0-null')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('receiving-line-item-0-existing')),
            findsNothing,
          );
          await tap(t, find.byKey(const Key('receiving-line-item-0-null')));
          await enter(t, 'ingredient-search', 'ბორჯომი');
          await tap(t, find.byKey(const Key('receiving-create-product')));
          expect(
            t
                .widget<TextField>(find.byKey(const Key('new-product-name')))
                .controller!
                .text,
            'ბორჯომი',
          );
          await tap(t, find.widgetWithText(ChoiceChip, 'სასმელი'));
          await tap(t, find.byKey(const Key('new-product-unit-piece')));
          await tap(t, find.text('შეფუთვით ვიღებთ'));
          await enter(t, 'new-product-package-ratio', '10');
          await qa.shot(t, 'flow-new-product-${width.toInt()}');
          await tap(t, find.widgetWithText(FilledButton, 'დამატება'));
          expect(writes.single.containsKey('supplierIds'), false);
          expect(writes.single['classification'], 'BEVERAGE');
          expect(writes.single['requestId'], isNotEmpty);
          await enter(t, 'receiving-line-quantity-0', '10');
          await enter(t, 'receiving-line-cost-0', '1.20');
          expect(find.text('მიღებული: 100 ცალი'), findsOneWidget);
          await reviewReceiving(t);
          await tap(t, find.byKey(const Key('receiving-save')));
          expect((received!['lines'] as List).single['stockItemId'], 'created');
          expect((received!['lines'] as List).single['enteredUnit'], 'pack');
          expect(t.takeException(), isNull);
        }, () => client);
      },
    );
    testWidgets(
      'inventory destinations start at top after long stock list $width',
      (t) async {
        qa.size(t, width);
        await t.pumpWidget(
          qa.app(inventory(items: [for (var i = 0; i < 40; i++) stock('$i')])),
        );
        await t.pumpAndSettle();
        final list = find.byKey(const Key('inventory-admin-list'));
        await t.drag(list, const Offset(0, -1200));
        await t.pumpAndSettle();
        final controller = t.widget<ListView>(list).controller!;
        expect(controller.offset, greaterThan(100));
        await openInventorySection(t, 'suppliers');
        expect(controller.offset, 0);
        await openInventorySection(t, 'stockItems');
        expect(controller.offset, 0);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'category browse is shared, searchable, and preserves variant identity $width',
      (t) async {
        qa.size(t, width);
        InventoryMenuSelection? chosen;
        await t.pumpWidget(
          qa.app(
            InventoryMenuBrowser(
              items: const [
                RecipeMenuItem(
                  menuItemId: 'water',
                  name: 'ბორჯომი',
                  price: 4,
                  parentCategoryName: 'სასმელები',
                  subcategoryName: 'წყალი',
                  variants: [
                    RecipeMenuVariant(variantId: 'half', size: .5, price: 4),
                  ],
                ),
                RecipeMenuItem(
                  menuItemId: 'food',
                  name: 'ხინკალი',
                  price: 2,
                  parentCategoryName: 'კერძები',
                ),
              ],
              onSelected: (s) => chosen = s,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('ხინკალი'), findsNothing);
        await qa.shot(t, 'flow-categories-${width.toInt()}');
        await tap(t, find.byKey(const Key('menu-category-სასმელები')));
        await tap(t, find.byKey(const Key('menu-category-წყალი')));
        await tap(t, find.text('ბორჯომი · 0.5'));
        expect(chosen!.variant!.variantId, 'half');
        await enter(t, 'inventory-menu-search', 'ხინკალი');
        await tap(t, find.widgetWithText(ListTile, 'ხინკალი'));
        expect(chosen!.item.menuItemId, 'food');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('supplier without receipts stays explicitly filtered', (t) async {
    await t.pumpWidget(
      qa.app(
        SupplierPayablesScreen(
          supplierId: 'empty-supplier',
          load: () async => settlement,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('მიმდინარე დავალიანება: 0.00 ₾'), findsOneWidget);
    expect(find.text('არჩეული მომწოდებელი · მიღებები არ აქვს'), findsOneWidget);
    expect(find.byKey(const Key('payable-new')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'payment filters and inline stock creation use readable dark surfaces',
    (t) async {
      qa.size(t, 360);
      final before = ManagerAppPreferences.dashboardAppearance.value;
      ManagerAppPreferences.dashboardAppearance.value =
          ManagerDashboardAppearance.dark;
      addTearDown(
        () => ManagerAppPreferences.dashboardAppearance.value = before,
      );
      await t.pumpWidget(
        qa.app(SupplierPayablesScreen(load: () async => settlement)),
      );
      await t.pumpAndSettle();
      final colors = Theme.of(
        t.element(find.byKey(const Key('payables-list'))),
      ).colorScheme;
      final light = colors.onSurface.computeLuminance(),
          dark = colors.surface.computeLuminance();
      expect((light + .05) / (dark + .05), greaterThanOrEqualTo(4.5));
      await qa.shot(t, 'flow-payments-dark-360');
      await t.pumpWidget(
        qa.app(
          const IngredientQuickDialog(
            receivingProduct: true,
            initialName: 'საქონლის ხორცი',
          ),
        ),
      );
      await t.pumpAndSettle();
      await qa.shot(t, 'flow-new-product-dark-360');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Manager tab reactivation resets explicit vertical controllers and keeps state',
    (t) async {
      final vertical = ScrollController(), horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      var active = true;
      late StateSetter update;
      await t.pumpWidget(
        qa.app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AdminTabViewport(
                active: active,
                child: Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: ListView(
                        controller: horizontal,
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < 20; i++)
                            SizedBox(width: 100, child: Text('Tab $i')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: vertical,
                        children: [
                          for (var i = 0; i < 40; i++)
                            SizedBox(height: 100, child: Text('Row $i')),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      vertical.jumpTo(600);
      horizontal.jumpTo(200);
      await t.pumpAndSettle();
      update(() => active = false);
      await t.pumpAndSettle();
      update(() => active = true);
      await t.pumpAndSettle();
      expect(vertical.offset, 0);
      expect(horizontal.offset, 200);
      expect(t.takeException(), isNull);
    },
  );
}
