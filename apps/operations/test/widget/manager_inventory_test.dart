import 'inventory_test_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';

final _stock = StockItem(
  id: 'stock-1',
  name: 'Beef',
  sku: 'BEEF-01',
  baseUnit: InventoryUnit.kg,
  minimumStock: 2.5,
  isActive: true,
  notes: 'Shoulder',
  createdAt: DateTime.utc(2026, 9, 5),
  updatedAt: DateTime.utc(2026, 9, 5),
);

final _supplier = Supplier(
  id: 'supplier-1',
  name: 'Farm Georgia',
  taxId: '123456789',
  phone: '555 12 34 56',
  email: 'orders@farm.ge',
  address: 'Tbilisi',
  isActive: true,
  createdAt: DateTime.utc(2026, 9, 5),
  updatedAt: DateTime.utc(2026, 9, 5),
);

Widget _app() => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(
    body: InventoryAdminTab(
      initialSection: 0,
      loadStockItems: () async => [_stock],
      loadSuppliers: () async => [_supplier],
      loadReceivings: () async => const ReceivingPage(receivings: []),
      loadRecipes: () async => const <RecipeMenuItem>[],
    ),
  ),
);

void main() {
  test('Management no longer duplicates the main Inventory destination', () {
    expect(
      MobileAdminScreen.adminTabs.map((tab) => tab.label),
      isNot(contains('მარაგები')),
    );
  });

  testWidgets('shows Stock Items, derived stock, search, and both editors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory-search')), findsOneWidget);
    expect(find.byKey(const Key('stock-item-list')), findsOneWidget);
    expect(find.text('Beef'), findsOneWidget);
    // Step 3 reads units in Georgian; storage keeps the English codes.
    expect(
      find.text('ერთეული: კგ'),
      findsNothing,
    ); // Unit is beside the quantity.
    // Step 2 replaced the placeholder with the ledger's own answer.
    expect(find.text('მარაგშია: 0 კგ'), findsOneWidget);
    expect(find.text('მინიმალური მარაგი: 2.5 კგ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('inventory-add')), findsNothing);

    await tester.ensureVisible(find.text('რედაქტირება').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('inventory-admin-list')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('რედაქტირება').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Beef'), findsOneWidget);
    await tester.tap(find.text('გაუქმება'));
    await tester.pumpAndSettle();

    await openInventorySection(tester, 'home');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('მომწოდებლები'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('მომწოდებლები'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supplier-list')), findsOneWidget);
    expect(find.text('Farm Georgia'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supplier-editor')), findsOneWidget);
    expect(find.byKey(const Key('supplier-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a wider search/action row without stretching content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byKey(const Key('inventory-admin-list')));
    final search = tester.getRect(find.byKey(const Key('inventory-search')));
    expect(find.byKey(const Key('inventory-add')), findsNothing);
    expect(search.width, lessThanOrEqualTo(list.width - 32));
    expect(list.width, 1100);
    expect(tester.takeException(), isNull);
  });
}
