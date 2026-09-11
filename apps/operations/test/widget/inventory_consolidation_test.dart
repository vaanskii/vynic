import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_summary_card.dart';
import 'package:vynic/apps/windows_pos/screens/admin_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_inventory_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart' as pos;
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/edge/inventory_projection_sync_service.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'manager_catalog_cost_test.dart' as qa;

final summary = <String, dynamic>{
  'procurement': {
    'today': '2026-09-06',
    'businessDate': '2026-09-05',
    'month': '2026-09',
    'calendarDay': {'total': '500.00', 'count': 1},
    'businessDay': {'total': '500.00', 'count': 1},
    'calendarMonth': {'total': '900.00', 'count': 2},
  },
  'lowStock': 1,
  'negativeStock': 1,
  'unmappedCount': 1,
  'unmapped': [
    {'itemName': 'ხაჭაპური'},
  ],
};
final low = StockItem.fromJson({
  'id': 'low',
  'name': 'საქონლის ხორცი გრძელი დასახელებით',
  'baseUnit': 'kg',
  'currentStock': '2.000',
  'stockStatus': 'LOW',
  'minimumStock': 5,
  'supplierIds': ['s'],
  'lastPurchaseUnitCost': '12.500000',
});
final negative = StockItem.fromJson({
  'id': 'negative',
  'name': 'ჩამოსასხმელი ლუდი',
  'classification': 'BEVERAGE',
  'baseUnit': 'L',
  'currentStock': '-1.000',
  'stockStatus': 'NEGATIVE',
});
void main() {
  late Directory temp;
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
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vynic46-widget-');
    Hive.init(temp.path);
    DatabaseCore.inventoryBox = await Hive.openBox('inventory');
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.inventoryBox = null;
    await temp.delete(recursive: true);
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('Manager Inventory sections and form stay usable at $width', (
      tester,
    ) async {
      qa.narrow(tester, width: width, height: 900);
      await tester.pumpWidget(
        qa.app(
          InventoryAdminTab(
            loadStockItems: () async => [low, negative],
            loadSuppliers: () async => [qa.supplier],
            loadReceivings: () async => const ReceivingPage(receivings: []),
            loadRecipes: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await qa.screenshot(tester, 'inventory-$width');
      for (final label in [
        'მომწოდებლები',
        'დღიური მიღება',
        'მენიუს შემადგენლობა',
        'ნაშთები',
      ]) {
        await tester.ensureVisible(find.text(label).first);
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final add = find.byKey(const Key('inventory-add'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('როგორ ვითვლით საწყობში?'), findsOneWidget);
      expect(find.text('როგორ მოდის მომწოდებლისგან?'), findsOneWidget);
      expect(find.text('საბაზო ერთეული'), findsNothing);
      expect(find.text('SKU'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('stock-name'))).width,
        greaterThanOrEqualTo(width < 500 ? 260 : 400),
      );
      expect(tester.takeException(), isNull);
      await qa.screenshot(tester, 'stock-form-$width');
    });
  }
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('Receiving form and supplier priority at $width', (
      tester,
    ) async {
      qa.narrow(tester, width: width, height: 900);
      await tester.pumpWidget(
        qa.app(
          ReceivingEditorDialog(
            suppliers: [qa.supplier],
            stockItems: qa.stocks,
            businessDate: '2026-09-05',
            save: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final product = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('receiving-line-item'),
        ),
      );
      expect(product.initialValue, 'borjomi');
      final cost = find.byKey(const Key('receiving-line-cost-0'));
      await tester.ensureVisible(cost);
      await tester.pumpAndSettle();
      expect(tester.getSize(cost).width, greaterThan(220));
      expect(
        tester.getSize(find.byKey(const Key('receiving-save'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await qa.screenshot(tester, 'receiving-$width');
    });
  }
  testWidgets('POS Admin remains read-only after failed pull and Hive reopen', (
    tester,
  ) async {
    qa.narrow(tester, width: 1024, height: 768);
    expect(AdminScreen.managerSections, contains('inventory'));
    await tester.runAsync(() async {
      await InventoryRepository.replaceCatalog({
        'version': 5,
        'generatedAt': '2026-09-06T10:00:00Z',
        'stockItems': [low.toJson(), negative.toJson()],
        'suppliers': [],
        'recipes': [
          {
            'recipeId': 'r',
            'menuItemId': 'menu',
            'menuItemName': 'ხინკალი',
            'components': [
              {
                'stockItemId': 'low',
                'stockItemName': low.name,
                'baseQuantityPerUnit': '0.035000',
                'baseUnit': 'kg',
              },
            ],
          },
        ],
        'inspection': {
          ...summary,
          'receivings': [
            {'supplierNameSnapshot': 'Borjomi', 'documentTotal': '500.00'},
          ],
          'menuItems': [],
          'movementsByItem': {
            'low': [
              {
                'id': 'm',
                'stockItemId': 'low',
                'movementType': 'RECEIVING',
                'quantityDeltaBase': '2.000',
                'baseUnit': 'kg',
                'businessDate': '2026-09-05',
              },
            ],
          },
        },
      });
      await Hive.close();
      DatabaseCore.inventoryBox = await Hive.openBox('inventory');
      final client = InventoryProjectionClient(
        credential: () => 'test',
        baseUrl: () => 'https://example.invalid',
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      );
      final sync = InventoryProjectionSyncService(client: client);
      expect(await sync.syncOnce(), EdgeTransportOutcome.unreachable);
      client.close();
    });
    await tester.pumpWidget(
      qa.app(
        Builder(
          builder: (context) => Theme(
            data: pos.AdminTheme.of(context),
            child: const AdminInventorySection(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(low.name), findsOneWidget);
    expect(find.textContaining('ბოლო განახლება:'), findsOneWidget);
    expect(find.text('შენახვა'), findsNothing);
    expect(find.text('რედაქტირება'), findsNothing);
    await qa.screenshot(tester, 'pos-inventory-offline');
    await tester.tap(find.byKey(const ValueKey('pos-stock-low')));
    await tester.pumpAndSettle();
    expect(find.text('2.000 კგ · მიღება'), findsOneWidget);
    expect(find.text('ხინკალი'), findsOneWidget);
    expect(find.text('აქტიური რეცეპტი / მიბმა'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await qa.screenshot(tester, 'pos-inventory-detail');
    final exported = InventoryRepository.exportCatalog();
    await tester.runAsync(() async {
      await DatabaseCore.inventoryBox!.clear();
      await InventoryRepository.restoreCatalog(exported);
    });
    expect(InventoryRepository.exportCatalog()['inspection'], isNotNull);
  });
  testWidgets(
    'Dashboard summary routes all four destinations and marks failed refresh',
    (tester) async {
      qa.narrow(tester, width: 390);
      final opened = <String>[];
      bool fail = false;
      await tester.pumpWidget(
        qa.app(
          InventorySummaryCard(
            load: () async {
              if (fail) throw const SocketException('offline');
              return summary;
            },
            onOpen: (destination, date) {
              opened.add(destination);
              if (destination == 'receiving') expect(date, '2026-09-06');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final destination in ['receiving', 'low', 'negative', 'unmapped']) {
        await tester.tap(
          find.byKey(ValueKey('inventory-summary-$destination')),
        );
      }
      expect(opened, ['receiving', 'low', 'negative', 'unmapped']);
      await qa.screenshot(tester, 'dashboard-inventory');
      fail = true;
      await tester.tap(find.byTooltip('განახლება'));
      await tester.pumpAndSettle();
      expect(find.textContaining('განახლება ვერ მოხერხდა'), findsOneWidget);
      expect(find.text('500.00 ₾'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final destination in ['receiving', 'low', 'negative', 'unmapped']) {
    testWidgets('Dashboard opens the actual $destination destination', (
      tester,
    ) async {
      qa.narrow(tester, width: 390);
      await tester.pumpWidget(
        qa.app(InventorySummaryCard(load: () async => summary)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('inventory-summary-$destination')));
      await tester.pumpAndSettle();
      if (destination == 'unmapped') {
        expect(
          tester
              .widget<ConsumptionHistoryScreen>(
                find.byType(ConsumptionHistoryScreen),
              )
              .initialUnmapped,
          isTrue,
        );
      } else {
        final screen = tester.widget<InventoryScreen>(
          find.byType(InventoryScreen),
        );
        expect(screen.section, destination == 'receiving' ? 2 : 0);
        expect(
          screen.stockStatus,
          destination == 'low'
              ? 'LOW'
              : destination == 'negative'
              ? 'NEGATIVE'
              : null,
        );
        if (destination == 'receiving')
          expect(screen.businessDate, '2026-09-06');
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Financials separates purchases, expenses and salary and links Receiving',
    (tester) async {
      qa.narrow(tester, width: 390, height: 900);
      await tester.pumpWidget(
        qa.app(
          FinancialsScreen(
            user: User(username: 'manager', pinCode: '0000', role: 'manager'),
            loadData: () async => {
              'revenue': 1000.0,
              'expenses': 100.0,
              'otherExpenses': '25.00',
              'salaryPayments': '75.00',
              'totalOutflows': '600.00',
              'procurement': summary['procurement'],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('კატეგორია (მაგ: ბაზარი)'), findsNothing);
      expect(find.text('კატეგორია (მაგ: ტრანსპორტი)'), findsOneWidget);
      expect(find.text('სხვა ხარჯები: 25.00 ₾'), findsOneWidget);
      expect(find.text('ხელფასები: 75.00 ₾'), findsOneWidget);
      expect(find.text('სულ გასავლები: 600.00 ₾'), findsOneWidget);
      final link = find.byKey(const Key('financials-receiving'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await qa.screenshot(tester, 'financials-procurement');
      await tester.tap(link);
      await tester.pumpAndSettle();
      final screen = tester.widget<InventoryScreen>(
        find.byType(InventoryScreen),
      );
      expect(screen.section, 2);
      expect(screen.businessDate, '2026-09-05');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('local legacy Market creation is refused before persistence', () async {
    await expectLater(
      SalesRepository.saveExpenseRecord(
        description: 'Goods',
        amount: 500,
        category: 'ბაზარი',
      ),
      throwsArgumentError,
    );
  });
}
