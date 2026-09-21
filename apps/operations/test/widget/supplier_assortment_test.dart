import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';
import 'procurement_rework_test.dart' as qa;
import 'inventory_final_journeys_test.dart' show tap, enter;

class SupplierApi {
  final stocks = <String, Map<String, dynamic>>{
    'beef': {
      'id': 'beef',
      'name': 'საქონლის ხორცი',
      'baseUnit': 'kg',
      'isActive': true,
      'currentStock': '0.000',
    },
    'water': {
      'id': 'water',
      'name': 'წყალი',
      'baseUnit': 'piece',
      'isActive': true,
      'currentStock': '0.000',
    },
  };
  final suppliers = <String, Map<String, dynamic>>{};
  final links = <String, Set<String>>{};
  final writes = <(String, String, Map<String, dynamic>)>[];
  bool failNextLink = false;
  Map<String, dynamic> supplier(String id) => {
    ...suppliers[id]!,
    'stockItemIds': links[id]?.toList() ?? [],
  };
  late final client = MockClient((request) async {
    final path = request.url.path.replaceFirst('/mobile/inventory/', '');
    final method = request.method;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (method != 'GET') writes.add((method, path, body));
    Object result;
    if (path == 'suppliers' && method == 'POST') {
      suppliers['new-supplier'] = {...body, 'id': 'new-supplier'};
      result = supplier('new-supplier');
    } else if (path == 'suppliers') {
      result = suppliers.keys.map(supplier).toList();
    } else if (path.contains('/products/')) {
      final parts = path.split('/');
      final products = links.putIfAbsent(parts[1], () => <String>{});
      if (method == 'POST')
        products.add(parts[3]);
      else
        products.remove(parts[3]);
      if (failNextLink) {
        failNextLink = false;
        return http.Response(jsonEncode({'message': 'კავშირი შეწყდა'}), 500);
      }
      result = {'linked': method == 'POST'};
    } else if (path.startsWith('suppliers/')) {
      final id = path.split('/').last;
      result = {
        ...supplier(id),
        'products': [for (final item in links[id] ?? <String>{}) stocks[item]!],
        'recentReceivings': [],
        'settlement': {'outstanding': '0.00', 'unverified': '0.00'},
      };
    } else if (path == 'stock-items' && method == 'POST') {
      stocks['created'] = {...body, 'id': 'created', 'currentStock': '0.000'};
      result = stocks['created']!;
    } else if (path == 'stock-items') {
      result = stocks.values.toList();
    } else if (path == 'receivings') {
      result = {'receivings': [], 'currentBusinessDate': '2026-09-13'};
    } else if (path == 'recipes') {
      result = [];
    } else {
      throw StateError('Unexpected request $method $path');
    }
    return http.Response(
      jsonEncode(result),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
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
    testWidgets(
      'create supplier opens assortment; existing goods link and unlink without receiving $width',
      (t) async {
        qa.size(t, width);
        final api = SupplierApi();
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(const InventoryAdminTab(initialSection: 1)),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('inventory-add')));
          await enter(t, 'supplier-name', 'ხორცის მომწოდებელი');
          await tap(t, find.byKey(const Key('supplier-save')));
          expect(find.byKey(const Key('supplier-detail')), findsOneWidget);
          expect(find.text('ხორცის მომწოდებელი'), findsWidgets);
          await tap(t, find.byKey(const Key('supplier-add-product')));
          await enter(t, 'ingredient-search', 'ხორცი');
          await tap(t, find.widgetWithText(ListTile, 'საქონლის ხორცი'));
          expect(api.links['new-supplier'], {'beef'});
          expect(
            find.byKey(const Key('supplier-product-beef')),
            findsOneWidget,
          );
          await qa.shot(t, 'supplier-assortment-${width.toInt()}');
          await tap(t, find.byKey(const Key('supplier-add-product')));
          expect(
            find.descendant(
              of: find.byType(InventoryIngredientPicker),
              matching: find.widgetWithText(ListTile, 'საქონლის ხორცი'),
            ),
            findsNothing,
          );
          await tap(t, find.widgetWithText(TextButton, 'დახურვა').last);
          await tap(t, find.byKey(const Key('supplier-remove-product-beef')));
          await tap(t, find.widgetWithText(TextButton, 'გაუქმება'));
          expect(api.links['new-supplier'], {'beef'});
          await tap(t, find.byKey(const Key('supplier-remove-product-beef')));
          await tap(t, find.widgetWithText(FilledButton, 'ამოღება'));
          expect(api.links['new-supplier'], isEmpty);
          expect(api.stocks['beef']!['currentStock'], '0.000');
          expect(api.writes.map((w) => w.$2), [
            'suppliers',
            'suppliers/new-supplier/products/beef',
            'suppliers/new-supplier/products/beef',
          ]);
          expect(t.takeException(), isNull);
        }, () => api.client);
      },
    );

    testWidgets(
      'new supplier product retries the same identity and is ready for receiving $width',
      (t) async {
        qa.size(t, width);
        final api = SupplierApi()
          ..suppliers['farm'] = {
            'id': 'farm',
            'name': 'ფერმა',
            'isActive': true,
          };
        await http.runWithClient(() async {
          await t.pumpWidget(
            qa.app(
              SupplierDetailDialog(
                supplier: Supplier.fromJson(api.supplier('farm')),
                stockItems: api.stocks.values.map(StockItem.fromJson).toList(),
              ),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('supplier-add-product')));
          await enter(t, 'ingredient-search', 'რძე');
          await tap(t, find.byKey(const Key('receiving-create-product')));
          expect(
            t
                .widget<TextField>(find.byKey(const Key('new-product-name')))
                .controller!
                .text,
            'რძე',
          );
          await tap(t, find.byKey(const Key('new-product-unit-L')));
          api.failNextLink = true;
          await tap(t, find.widgetWithText(FilledButton, 'დამატება'));
          expect(
            find.byKey(const Key('supplier-product-error')),
            findsOneWidget,
          );
          expect(api.writes.where((w) => w.$2 == 'stock-items').length, 1);
          await tap(t, find.byKey(const Key('supplier-product-retry')));
          expect(api.links['farm'], {'created'});
          expect(api.writes.where((w) => w.$2 == 'stock-items').length, 1);
          expect(
            api.writes
                .where((w) => w.$2 == 'suppliers/farm/products/created')
                .length,
            2,
          );
          expect(
            find.byKey(const Key('supplier-product-created')),
            findsOneWidget,
          );
          await tap(t, find.byKey(const Key('supplier-new-receiving')));
          await tap(t, find.byKey(const Key('receiving-line-item-0-null')));
          final choices = find.descendant(
            of: find.byType(InventoryIngredientPicker),
            matching: find.byType(ListTile),
          );
          expect(
            t.widget<ListTile>(choices.first).title,
            isA<Text>().having((text) => text.data, 'name', 'რძე'),
          );
          await tap(t, choices.first);
          expect(
            find.byKey(const Key('receiving-line-item-0-created')),
            findsOneWidget,
          );
          expect(
            api.writes.any(
              (w) => w.$2.startsWith('receivings') || w.$2 == 'recipes',
            ),
            isFalse,
          );
          expect(t.takeException(), isNull);
        }, () => api.client);
      },
    );
  }
  testWidgets('long assortment is searchable and uses dark themed selection', (
    t,
  ) async {
    qa.size(t, 360);
    final old = ManagerAppPreferences.dashboardAppearance.value;
    ManagerAppPreferences.dashboardAppearance.value =
        ManagerDashboardAppearance.dark;
    addTearDown(() => ManagerAppPreferences.dashboardAppearance.value = old);
    final api = SupplierApi()
      ..suppliers['farm'] = {'id': 'farm', 'name': 'ფერმა', 'isActive': true};
    for (var i = 0; i < 30; i++) {
      api.stocks['item-$i'] = {
        'id': 'item-$i',
        'name': 'პროდუქტი $i',
        'baseUnit': 'kg',
        'isActive': true,
      };
    }
    api.links['farm'] = {for (var i = 0; i < 30; i++) 'item-$i'};
    await http.runWithClient(() async {
      await t.pumpWidget(
        qa.app(
          SupplierDetailDialog(
            supplier: Supplier.fromJson(api.supplier('farm')),
            stockItems: api.stocks.values.map(StockItem.fromJson).toList(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await enter(t, 'supplier-product-search', '29');
      expect(find.byKey(const Key('supplier-product-item-29')), findsOneWidget);
      expect(find.byKey(const Key('supplier-product-item-0')), findsNothing);
      await qa.shot(t, 'supplier-assortment-dark-360');
      await tap(t, find.byKey(const Key('supplier-add-product')));
      expect(
        Theme.of(
          t.element(find.byKey(const Key('ingredient-search'))),
        ).colorScheme.surface,
        AdminTheme.surface,
      );
      expect(t.takeException(), isNull);
    }, () => api.client);
  });
}
