import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';

/// The Manager Receiving surface.
///
/// The rules being checked here are the ones a restaurant manager would notice
/// going wrong: a posted document offering an edit button, a packaged line not
/// saying how many bottles actually arrived, or a cancellation quietly hiding
/// the receipt it reversed.

final _beef = StockItem.fromJson({
  'id': 'stock-beef',
  'name': 'Beef',
  'baseUnit': 'kg',
  'isActive': true,
  'minimumStock': '10',
  'currentStock': '62.500',
  'stockStatus': 'OK',
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
});

final _lemonade = StockItem.fromJson({
  'id': 'stock-lemonade',
  'name': 'Lemonade 0.5L',
  'baseUnit': 'bottle',
  'isActive': true,
  'currentStock': '240.000',
  'stockStatus': 'NO_MINIMUM',
  'purchaseUnits': [
    {'id': 'pu-1', 'unit': 'box', 'baseUnitMultiplier': '24'},
  ],
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
});

final _lowStockItem = StockItem.fromJson({
  'id': 'stock-salt',
  'name': 'Salt',
  'baseUnit': 'kg',
  'isActive': true,
  'minimumStock': '10',
  'currentStock': '2.000',
  'stockStatus': 'LOW',
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
});

final _supplier = Supplier.fromJson({
  'id': 'supplier-1',
  'name': 'Meat Supplier',
  'isActive': true,
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
});

Map<String, dynamic> _receivingJson({
  String id = 'r-1',
  String status = 'POSTED',
  String waybill = '12345',
  String total = '750.00',
  bool withReversal = false,
}) => <String, dynamic>{
  'id': id,
  'supplierId': 'supplier-1',
  'supplierName': 'Meat Supplier',
  'waybillNumber': waybill,
  'documentDate': '2026-09-05',
  'receivedAt': '2026-09-05T09:00:00Z',
  'status': status,
  'documentTotal': total,
  'lineCount': 1,
  'createdByName': 'Nino',
  'createdAt': '2026-09-05T09:00:00Z',
  if (withReversal) 'cancelledByName': 'Gio',
  if (withReversal) 'cancellationReason': 'returned',
  'lines': [
    {
      'id': 'line-1',
      'lineSequence': 0,
      'stockItemId': 'stock-beef',
      'stockItemName': 'Beef',
      'enteredQuantity': '50.000',
      'enteredUnit': 'kg',
      'baseQuantity': '50.000',
      'baseUnit': 'kg',
      'unitPurchaseCost': '15.0000',
      'lineTotal': '750.00',
      'effectiveBaseUnitCost': '15.000000',
    },
  ],
  'movements': [
    if (status != 'DRAFT')
      {
        'id': 'm-1',
        'stockItemId': 'stock-beef',
        'movementType': 'RECEIVING',
        'quantityDeltaBase': '50.000',
        'baseUnit': 'kg',
        'businessDate': '2026-09-05',
        'actorName': 'Nino',
        'createdAt': '2026-09-05T09:00:00Z',
      },
    if (withReversal)
      {
        'id': 'm-2',
        'stockItemId': 'stock-beef',
        'movementType': 'RECEIVING_REVERSAL',
        'quantityDeltaBase': '-50.000',
        'baseUnit': 'kg',
        'businessDate': '2026-09-06',
        'actorName': 'Gio',
        'createdAt': '2026-09-06T09:00:00Z',
        'reversalOfMovementId': 'm-1',
      },
  ],
};

Widget _tab({
  List<StockItem>? stockItems,
  List<Receiving>? receivings,
  int section = 2,
}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(
    body: InventoryAdminTab(
      initialSection: section,
      loadStockItems: () async => stockItems ?? [_beef, _lemonade],
      loadSuppliers: () async => [_supplier],
      loadReceivings: () async => ReceivingPage(
        receivings:
            receivings ??
            [
              Receiving.fromJson(_receivingJson()),
              Receiving.fromJson(
                _receivingJson(id: 'r-2', status: 'DRAFT', waybill: '999'),
              ),
            ],
      ),
      loadRecipes: () async => const <RecipeMenuItem>[],
    ),
  ),
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('the Receiving list', () {
    testWidgets('shows date, supplier, waybill, status and total', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receiving-list')), findsOneWidget);
      expect(find.text('05 სექ'), findsNWidgets(2));
      expect(find.text('Meat Supplier'), findsNWidgets(2));
      expect(find.text('ზედნადები 12345'), findsOneWidget);
      expect(find.text('750.00 ₾'), findsNWidgets(2));
      // Once as the status filter chip, once as this document's badge.
      expect(find.byKey(const Key('receiving-status-POSTED')), findsOneWidget);
      expect(find.byKey(const Key('receiving-status-DRAFT')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters by status', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receiving-filter-posted')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receiving-card-r-1')), findsOneWidget);
      expect(find.byKey(const Key('receiving-card-r-2')), findsNothing);

      await tester.tap(find.byKey(const Key('receiving-filter-draft')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receiving-card-r-1')), findsNothing);
      expect(find.byKey(const Key('receiving-card-r-2')), findsOneWidget);
    });

    testWidgets('searches by waybill', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('inventory-search')), '999');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receiving-card-r-2')), findsOneWidget);
      expect(find.byKey(const Key('receiving-card-r-1')), findsNothing);
    });

    testWidgets('lays out on a narrow phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receiving-list')), findsOneWidget);
      expect(find.text('Meat Supplier'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers an empty state rather than a blank page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab(receivings: const []));
      await tester.pumpAndSettle();

      expect(find.text('მიღებები ჯერ არ არის'), findsOneWidget);
    });
  });

  group('the Receiving detail', () {
    testWidgets('a posted document is read-only and shows its stock impact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          ReceivingDetailDialog(
            receivingId: 'r-1',
            onEditDraft: (_) async {},
            load: () async => Receiving.fromJson(_receivingJson()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receiving-detail')), findsOneWidget);
      expect(find.text('750.00 ₾'), findsNWidgets(2));
      expect(
        find.byKey(const Key('receiving-original-impact')),
        findsOneWidget,
      );
      expect(find.text('+50 კგ · Beef'), findsOneWidget);
      // A posted document is inventory history: no edit, no delete, no post.
      expect(find.byKey(const Key('receiving-edit')), findsNothing);
      expect(find.byKey(const Key('receiving-delete')), findsNothing);
      expect(find.byKey(const Key('receiving-post')), findsNothing);
      expect(find.byKey(const Key('receiving-cancel')), findsOneWidget);
    });

    testWidgets('a cancelled document still shows the original receipt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          ReceivingDetailDialog(
            receivingId: 'r-1',
            onEditDraft: (_) async {},
            load: () async => Receiving.fromJson(
              _receivingJson(status: 'CANCELLED', withReversal: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('საწყისი გავლენა მარაგზე'), findsOneWidget);
      expect(find.text('+50 კგ · Beef'), findsOneWidget);
      expect(
        find.byKey(const Key('receiving-reversal-impact')),
        findsOneWidget,
      );
      expect(find.text('-50 კგ · Beef'), findsOneWidget);
      expect(find.byKey(const Key('receiving-cancel')), findsNothing);
    });

    testWidgets('posting asks for confirmation before it moves stock', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          ReceivingDetailDialog(
            receivingId: 'r-2',
            onEditDraft: (_) async {},
            load: () async =>
                Receiving.fromJson(_receivingJson(status: 'DRAFT')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receiving-post')), findsOneWidget);
      expect(find.byKey(const Key('receiving-edit')), findsOneWidget);
      expect(find.byKey(const Key('receiving-delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('receiving-post')));
      await tester.pumpAndSettle();
      expect(find.text('გატარდეს მიღება?'), findsOneWidget);
      expect(find.byKey(const Key('receiving-post-confirm')), findsOneWidget);

      // Backing out must leave the document alone.
      await tester.tap(find.text('დახურვა').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receiving-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling explains that reversals are added, not deletions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          ReceivingDetailDialog(
            receivingId: 'r-1',
            onEditDraft: (_) async {},
            load: () async => Receiving.fromJson(_receivingJson()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receiving-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('გაუქმდეს მიღება?'), findsOneWidget);
      expect(find.textContaining('საწყისი მოძრაობები რჩება'), findsOneWidget);
      expect(find.byKey(const Key('receiving-cancel-confirm')), findsOneWidget);
    });
  });

  group('the Receiving form', () {
    testWidgets('converts a packaged line and shows the base quantity', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _host(
          ReceivingEditorDialog(
            businessDate: '2026-09-05',
            suppliers: [_supplier],
            stockItems: [_lemonade, _beef],
            save: (payload) async => saved = payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('receiving-waybill')),
        '123456',
      );
      await tester.enterText(
        find.byKey(const Key('receiving-line-quantity-0')),
        '10',
      );
      await tester.enterText(
        find.byKey(const Key('receiving-line-cost-0')),
        '28.80',
      );
      await tester.pumpAndSettle();

      // The unit dropdown offers the item's own box beside its base unit,
      // named the way restaurant staff read it.
      await tester.tap(find.byKey(const Key('receiving-line-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ყუთი').last);
      await tester.pumpAndSettle();

      // 10 boxes of 24 is 240 bottles, said before anything is posted.
      expect(find.byKey(const Key('receiving-line-base-0')), findsOneWidget);
      expect(find.text('მიღებული: 240 ბოთლი'), findsOneWidget);
      expect(find.text('288.00 ₾'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('receiving-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['waybillNumber'], '123456');
      expect(saved!['lines'], [
        {
          'stockItemId': 'stock-lemonade',
          'enteredQuantity': '10',
          'enteredUnit': 'box',
          'unitPurchaseCost': '28.80',
        },
      ]);
    });

    testWidgets('refuses a zero quantity before it reaches Cloud', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var called = false;
      await tester.pumpWidget(
        _host(
          ReceivingEditorDialog(
            businessDate: '2026-09-05',
            suppliers: [_supplier],
            stockItems: [_beef],
            save: (_) async => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('receiving-line-cost-0')),
        '15',
      );
      await tester.tap(find.byKey(const Key('receiving-save')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('რაოდენობა უნდა იყოს დადებითი'),
        findsOneWidget,
      );
      expect(called, isFalse);
    });

    testWidgets('re-opens an existing draft with its lines', (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          ReceivingEditorDialog(
            businessDate: '2026-09-05',
            receiving: Receiving.fromJson(_receivingJson(status: 'DRAFT')),
            suppliers: [_supplier],
            stockItems: [_beef],
            save: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('მიღების რედაქტირება'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12345'), findsOneWidget);
      expect(find.widgetWithText(TextField, '50'), findsOneWidget);
      expect(find.text('750.00 ₾'), findsNWidgets(2));
    });
  });

  group('Stock Items with real quantities', () {
    testWidgets('show the derived balance and packaging', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tab(section: 0));
      await tester.pumpAndSettle();

      expect(find.text('ნაშთი: 62.5 კგ'), findsOneWidget);
      expect(find.text('ნაშთი: 240 ბოთლი'), findsOneWidget);
      expect(find.text('1 ყუთი = 24 ბოთლი'), findsOneWidget);
      // The Step 1 placeholder is gone for good.
      expect(find.text('მოძრაობები ჯერ არ არის'), findsNothing);
      expect(find.byKey(const Key('low-stock-badge')), findsNothing);
    });

    testWidgets('flag low stock only when Cloud says so', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _tab(section: 0, stockItems: [_beef, _lowStockItem]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('low-stock-badge')), findsOneWidget);
      expect(find.text('ნაშთი: 2 კგ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open a detail with the balance and recent movements', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          StockItemDetailDialog(
            stockItemId: 'stock-beef',
            load: () async => StockItemDetail.fromJson({
              ..._beefDetailJson(),
              'recentMovements': [
                {
                  'id': 'm-1',
                  'stockItemId': 'stock-beef',
                  'movementType': 'RECEIVING',
                  'quantityDeltaBase': '50.000',
                  'baseUnit': 'kg',
                  'businessDate': '2026-09-05',
                  'actorName': 'Nino',
                  'createdAt': '2026-09-05T09:00:00Z',
                  'receiving': {
                    'id': 'r-1',
                    'waybillNumber': '123',
                    'documentDate': '2026-09-05',
                    'supplierName': 'Meat Supplier',
                    'status': 'POSTED',
                  },
                },
                {
                  'id': 'm-2',
                  'stockItemId': 'stock-beef',
                  'movementType': 'RECEIVING_REVERSAL',
                  'quantityDeltaBase': '-7.500',
                  'baseUnit': 'kg',
                  'businessDate': '2026-09-06',
                  'actorName': 'Gio',
                  'createdAt': '2026-09-06T09:00:00Z',
                },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock-detail-current')), findsOneWidget);
      expect(find.text('62.5 კგ'), findsOneWidget);
      expect(find.text('მიღება #123'), findsOneWidget);
      expect(find.text('+50 კგ'), findsOneWidget);
      expect(find.text('მიღების რევერსი'), findsOneWidget);
      expect(find.text('-7.5 კგ'), findsOneWidget);
    });

    testWidgets('say plainly when an item has no movements yet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          StockItemDetailDialog(
            stockItemId: 'stock-beef',
            load: () async => StockItemDetail.fromJson({
              ..._beefDetailJson(),
              'currentStock': '0.000',
              'stockStatus': 'LOW',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 კგ'), findsOneWidget);
      expect(
        find.byKey(const Key('stock-detail-no-movements')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('low-stock-badge')), findsOneWidget);
    });
  });
}

Map<String, dynamic> _beefDetailJson() => <String, dynamic>{
  'id': 'stock-beef',
  'name': 'Beef',
  'baseUnit': 'kg',
  'isActive': true,
  'minimumStock': '10',
  'currentStock': '62.500',
  'stockStatus': 'OK',
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
};
