import 'inventory_test_actions.dart';
import 'procurement_rework_test.dart' as flow;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'procurement_rework_test.dart' as qa;

// Scripted HTTP responses verify the real Manager navigation and wire requests.
// Ledger effects for these same quantities are tested by the PostgreSQL suite.
class JourneyApi {
  JourneyApi(this.kind);
  final String kind;
  final writes = <String, List<Map<String, dynamic>>>{};
  bool linked = false, posted = false, paid = false;
  String get id => kind == 'menu'
      ? 'water-stock'
      : kind == 'bulk'
      ? 'beer-stock'
      : 'beef-stock';
  String get name => kind == 'menu'
      ? 'ბორჯომი'
      : kind == 'bulk'
      ? 'ჩამოსასხმელი ლუდი'
      : 'ხორცი';
  String get unit => kind == 'menu'
      ? 'piece'
      : kind == 'bulk'
      ? 'L'
      : 'kg';
  Map<String, dynamic> get stock => {
    'id': id,
    'name': name,
    'baseUnit': unit,
    'isActive': true,
    'currentStock': posted
        ? (kind == 'menu'
              ? '100.000'
              : kind == 'bulk'
              ? '30.000'
              : '20.000')
        : '0.000',
    'recipeUnits': kind == 'ingredient' ? ['g', 'kg'] : [unit],
    'purchaseUnits': kind == 'ingredient'
        ? []
        : [
            {
              'id': 'packaging',
              'unit': kind == 'bulk' ? 'keg' : 'pack',
              'baseUnitMultiplier': kind == 'bulk' ? '30' : '10',
            },
          ],
  };
  Map<String, dynamic> get supplier => {
    'id': 'source',
    'name': kind == 'menu' ? 'Borjomi' : 'Market A',
    'stockItemIds': linked ? [id] : [],
  };
  List<Map<String, dynamic>> get menu => [
    {
      'menuItemId': 'water-menu',
      'nameKa': 'ბორჯომი',
      'price': 4,
      'menuGroup': 'BEVERAGE',
      'parentCategoryName': 'სასმელები',
      'subcategoryName': 'წყალი',
      'categoryName': 'წყალი',
    },
    {
      'menuItemId': 'khinkali',
      'nameKa': 'ხინკალი',
      'price': 2,
      'menuGroup': 'FOOD',
      'parentCategoryName': 'კერძები',
      'categoryName': 'კერძები',
    },
    {
      'menuItemId': 'beer-menu',
      'nameKa': 'ლუდი 0.5L',
      'price': 5,
      'menuGroup': 'BEVERAGE',
      'parentCategoryName': 'სასმელები',
      'categoryName': 'ლუდი',
    },
  ];
  Map<String, dynamic> get receipt => {
    'id': 'receipt',
    'supplierId': 'source',
    'supplierName': supplier['name'],
    'status': posted ? 'POSTED' : 'DRAFT',
    'documentDate': '2026-09-12',
    'businessDate': '2026-09-12',
    'documentTotal': kind == 'menu' ? '120.00' : '800.00',
    'paid': paid ? '120.00' : '0.00',
    'remaining': paid ? '0.00' : '800.00',
    'paymentStatus': paid ? 'PAID' : 'UNPAID',
  };
  late final client = MockClient((request) async {
    final path = request.url.path.replaceFirst('/mobile/inventory/', '');
    Object result;
    if (request.method != 'GET') {
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      writes.putIfAbsent(path, () => []).add(body);
      if (path.endsWith('/items')) {
        linked = true;
        result = {};
      } else if (path == 'receivings') {
        result = receipt;
      } else if (path == 'receivings/receipt/post') {
        posted = true;
        result = receipt;
      } else if (path == 'receivings/receipt/payments') {
        paid = true;
        result = {};
      } else if (path == 'recipes') {
        result = {'id': 'recipe', ...body};
      } else {
        throw StateError('Unexpected write $path');
      }
    } else if (path == 'stock-items') {
      result = [stock];
    } else if (path == 'suppliers') {
      result = [supplier];
    } else if (path == 'suppliers/source') {
      result = {
        'products': linked ? [stock] : [],
        'recentReceivings': posted ? [receipt] : [],
        'settlement': {
          'outstanding': paid ? '0.00' : '800.00',
          'unverified': '0.00',
          'businessDate': '2026-09-12',
          'receivings': posted ? [receipt] : [],
        },
      };
    } else if (path == 'payables') {
      result = {
        'businessDate': '2026-09-12',
        'receivings': [receipt],
      };
    } else if (path == 'receivings') {
      result = {
        'currentBusinessDate': '2026-09-12',
        'receivings': posted ? [receipt] : [],
      };
    } else if (path == 'recipes') {
      result = menu;
    } else if (path.startsWith('recipes/menu-item/')) {
      result = {
        'menuItemId': path.split('/').last,
        'menuItemName': 'ხინკალი',
        'price': 2,
      };
    } else {
      throw StateError('Unexpected read $path');
    }
    return http.Response(
      jsonEncode(result),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String key, String value) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.enterText(find.byKey(Key(key)), value);
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
    testWidgets('home to actual Menu category to Khinkali composition $width', (
      t,
    ) async {
      qa.size(t, width);
      final api = JourneyApi('ingredient');
      await http.runWithClient(() async {
        await t.pumpWidget(qa.app(const InventoryAdminTab()));
        await t.pumpAndSettle();
        await tap(t, find.text('მენიუს შემადგენლობა'));
        await tap(t, find.byKey(const Key('menu-category-კერძები')));
        expect(find.byKey(const Key('recipe-card-water-menu')), findsNothing);
        await qa.shot(t, 'final-menu-composition-${width.toInt()}');
        await tap(t, find.byKey(const Key('recipe-card-khinkali')));
        await enter(t, 'recipe-component-quantity-0', '35');
        await tap(t, find.byKey(const Key('recipe-save')));
        expect(api.writes['recipes']!.single['menuItemId'], 'khinkali');
        expect(
          (api.writes['recipes']!.single['components'] as List).single,
          containsPair('unit', 'g'),
        );
        expect(t.takeException(), isNull);
      }, () => api.client);
    });
    testWidgets('second supplier reuses Beef without a new identity $width', (
      t,
    ) async {
      qa.size(t, width);
      final api = JourneyApi('ingredient');
      await http.runWithClient(() async {
        for (final supplier in ['market-a', 'market-b']) {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();
          await t.pumpWidget(
            qa.app(
              SuppliedItemDialog(
                key: ValueKey(supplier),
                supplierId: supplier,
                stockItems: [StockItem.fromJson(api.stock)],
              ),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('supplied-mode-ingredient')));
          await enter(t, 'supplied-search', 'ხორცი');
          await tap(t, find.byKey(const Key('supplied-stock-beef-stock')));
          await tap(t, find.byKey(const Key('supplied-save')));
        }
        for (final requests in api.writes.values) {
          expect(requests.single['stockItemId'], 'beef-stock');
          expect(requests.single.containsKey('menuItemId'), false);
        }
        expect(
          api.writes.keys,
          containsAll(['suppliers/market-a/items', 'suppliers/market-b/items']),
        );
        expect(api.writes.containsKey('stock-items'), false);
      }, () => api.client);
    });
    testWidgets(
      'supplier detail records payment and refreshes its debt $width',
      (t) async {
        qa.size(t, width);
        final api = JourneyApi('menu')..posted = true;
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(
              SupplierDetailDialog(
                supplier: Supplier.fromJson(api.supplier),
                stockItems: [StockItem.fromJson(api.stock)],
              ),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('supplier-payments')));
          await tap(t, find.byKey(const Key('payable-pay-receipt')));
          await enter(t, 'supplier-payment-amount', '120');
          await tap(t, find.byKey(const Key('supplier-payment-save')));
          expect(
            api.writes['receivings/receipt/payments']!.single['amount'],
            '120',
          );
          expect(find.byType(SupplierPayablesView), findsOneWidget);
          expect(find.text('მიმდინარე დავალიანება: 0.00 ₾'), findsOneWidget);
          expect(t.takeException(), isNull);
        }, () => api.client);
      },
    );
    testWidgets(
      'self purchase posts and pays without creating a supplier $width',
      (t) async {
        qa.size(t, width);
        final api = JourneyApi('ingredient');
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(
              ReceivingEditorDialog(
                suppliers: const [],
                stockItems: [StockItem.fromJson(api.stock)],
                businessDate: '2026-09-12',
              ),
            ),
          );
          await t.pumpAndSettle();
          await flow.chooseReceivingProduct(t);
          await enter(t, 'receiving-source-label', 'ბაზარი');
          await enter(t, 'receiving-line-quantity-0', '20');
          await tap(t, find.byKey(const Key('receiving-price-0-total')));
          await enter(t, 'receiving-line-cost-0', '800');
          await reviewReceiving(t);
          await tap(t, find.byKey(const Key('receiving-payment-full')));
          await reviewReceiving(t);
          await tap(t, find.byKey(const Key('receiving-save')));
          expect(
            api.writes['receivings']!.single,
            containsPair('sourceType', 'SELF_PURCHASE'),
          );
          expect(api.writes['receivings']!.single['supplierId'], isNull);
          expect(api.writes['receivings']!.single['sourceLabel'], 'ბაზარი');
          expect(
            api.writes['receivings/receipt/payments']!.single['amount'],
            '800.00',
          );
          expect(api.writes.keys.any((k) => k.startsWith('suppliers')), false);
          expect(t.takeException(), isNull);
        }, () => api.client);
      },
    );
    testWidgets(
      'pack prices per piece per pack and total agree before posting $width',
      (t) async {
        qa.size(t, width);
        final api = JourneyApi('menu')..linked = true;
        await t.pumpWidget(
          qa.app(
            ReceivingEditorDialog(
              suppliers: [Supplier.fromJson(api.supplier)],
              stockItems: [StockItem.fromJson(api.stock)],
              businessDate: '2026-09-12',
              save: (_) async {},
            ),
          ),
        );
        await t.pumpAndSettle();
        await flow.chooseReceivingProduct(t);
        await enter(t, 'receiving-line-quantity-0', '10');
        for (final entry in {
          'base': '1.20',
          'entered': '12',
          'total': '120',
        }.entries) {
          await tap(t, find.byKey(Key('receiving-price-0-${entry.key}')));
          await enter(t, 'receiving-line-cost-0', entry.value);
          expect(find.text('მიღებული: 100 ცალი'), findsOneWidget);
          expect(find.text('1.200000 ₾ / ცალი'), findsOneWidget);
          expect(find.text('120.00 ₾'), findsNWidgets(2));
        }
        expect(t.takeException(), isNull);
      },
    );
    for (final kind in ['menu', 'ingredient', 'bulk']) {
      testWidgets('supplier $kind to posted receiving and composition $width', (
        t,
      ) async {
        qa.size(t, width);
        final api = JourneyApi(kind);
        await http.runWithClient(() async {
          await t.pumpWidget(qa.app(const InventoryAdminTab()));
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('inventory-add')));
          await flow.chooseReceivingProduct(t);
          await enter(
            t,
            'receiving-line-quantity-0',
            kind == 'menu'
                ? '10'
                : kind == 'bulk'
                ? '1'
                : '20',
          );
          if (kind != 'menu')
            await tap(t, find.byKey(const Key('receiving-price-0-total')));
          await enter(
            t,
            'receiving-line-cost-0',
            kind == 'menu' ? '1.20' : '800',
          );
          await reviewReceiving(t);
          if (kind == 'menu')
            await tap(t, find.byKey(const Key('receiving-payment-full')));
          await t.ensureVisible(
            find.byKey(const Key('receiving-confirmation-summary')),
          );
          await t.pumpAndSettle();
          expect(
            find.text(
              '${api.name} +${kind == 'menu'
                  ? '100.000 ცალი'
                  : kind == 'bulk'
                  ? '30.000 ლ'
                  : '20.000 კგ'}',
            ),
            findsOneWidget,
          );
          await qa.shot(t, 'final-$kind-summary-${width.toInt()}');
          await reviewReceiving(t);
          await tap(t, find.byKey(const Key('receiving-save')));
          final line =
              (api.writes['receivings']!.single['lines'] as List).single as Map;
          expect(line['stockItemId'], api.id);
          expect(
            line['enteredUnit'],
            kind == 'menu'
                ? 'pack'
                : kind == 'bulk'
                ? 'keg'
                : 'kg',
          );
          expect(api.writes['receivings/receipt/post'], hasLength(1));
          if (kind == 'menu') {
            expect(line['priceBasis'], 'base');
            expect(
              api.writes['receivings/receipt/payments']!.single['amount'],
              '120.00',
            );
            expect(find.byKey(const Key('inventory-home')), findsOneWidget);
          } else {
            expect(
              api.writes.containsKey('receivings/receipt/payments'),
              false,
            );
            await openInventorySection(t, 'recipes');
            await t.enterText(
              find.byKey(const Key('inventory-menu-search')),
              kind == 'ingredient' ? 'ხინკალი' : 'ლუდი',
            );
            await t.pumpAndSettle();
            await tap(
              t,
              find.byKey(
                Key(
                  'recipe-card-${kind == 'ingredient' ? 'khinkali' : 'beer-menu'}',
                ),
              ),
            );
            await enter(
              t,
              'recipe-component-quantity-0',
              kind == 'ingredient' ? '35' : '0.5',
            );
            await tap(t, find.byKey(const Key('recipe-save')));
            final component =
                (api.writes['recipes']!.single['components'] as List).single
                    as Map;
            expect(component['stockItemId'], api.id);
            expect(component['unit'], kind == 'ingredient' ? 'g' : 'L');
          }
          expect(t.takeException(), isNull);
        }, () => api.client);
      });
    }
  }
}
