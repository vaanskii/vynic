import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/inventory_history_page.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_movement_value.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_history_view.dart';
import 'manager_catalog_cost_test.dart' as qa;

const window = {'recordsCreatedBefore': '2026-10-08T10:00:00.000Z'};
InventoryHistoryPage page(List<Map<String, dynamic>> rows, [String? next]) =>
    InventoryHistoryPage(items: rows, nextCursor: next, window: window);
void main() {
  setUpAll(() async {
    for (final family in ['NotoSansGeorgian', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('frozen movement/current recipe provenance visible at $width', (
      tester,
    ) async {
      qa.narrow(tester, width: width, height: 1100);
      await tester.pumpWidget(
        qa.app(
          SingleChildScrollView(
            child: Column(
              children: [
                InventoryMovementValue(
                  movement: StockMovement.fromJson({
                    'id': 'restore',
                    'businessDate': '2026-09-06',
                    'createdAt': '2026-10-08T10:00:00Z',
                    'valuationStatus': 'VALUED',
                    'valueOrigin': 'FROZEN_ORIGINAL_REVERSAL',
                    'inventoryValueDelta': '60.000000000000',
                  }),
                ),
                InventoryMovementValue(
                  movement: StockMovement.fromJson({
                    'id': 'unknown',
                    'businessDate': '2026-09-06',
                    'createdAt': '2026-10-08T10:00:00Z',
                    'valuationStatus': 'PROVISIONAL',
                  }),
                ),
                CurrentRecipeCostPanel(
                  cost: CurrentRecipeCost.fromJson({
                    'status': 'MISSING_COMPONENT_COST',
                    'total': null,
                    'provenance': {'includesReconstructedHistory': true},
                    'components': [
                      {
                        'stockItemName': 'უცნობი ინგრედიენტი',
                        'quantity': '1.000000',
                        'baseUnit': 'kg',
                        'status': 'PROVISIONAL',
                      },
                    ],
                  }),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('60.000000000000'), findsOneWidget);
      expect(
        find.text('აღდგენა საწყისი ჩანაწერის ღირებულებით'),
        findsOneWidget,
      );
      expect(find.textContaining('წინასწარი შეფასება —'), findsOneWidget);
      expect(find.textContaining('ისტორიიდან აღდგენილ'), findsOneWidget);
      await tester.ensureVisible(
        find.text('შენახული შემადგენლობით · მიმდინარე მარაგის ფასი'),
      );
      await tester.tap(
        find.text('შენახული შემადგენლობით · მიმდინარე მარაგის ფასი'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('წინასწარია'), findsWidgets);
      expect(find.text('შესყიდვის ისტორია არ არის'), findsNothing);
      expect(tester.takeException(), isNull);
      await qa.screenshot(tester, 'inv02-provenance-${width.toInt()}');
    });
  }
  testWidgets(
    'load-more interruption keeps rows; retry discovers record 101; full export re-reads all pages',
    (tester) async {
      qa.narrow(tester);
      var fail = true;
      final calls = <String?>[];
      String? exported;
      Future<InventoryHistoryPage> load(String? cursor) async {
        calls.add(cursor);
        if (cursor != null && fail) throw StateError('offline');
        return cursor == null
            ? page([
                for (var i = 1; i <= 100; i++)
                  {'id': '$i', 'orderId': i, 'businessDate': '2026-09-05'},
              ], 'next')
            : page([
                {'id': '101', 'orderId': 101, 'businessDate': '2026-09-05'},
              ]);
      }

      await tester.pumpWidget(
        qa.app(
          ConsumptionHistoryScreen(
            loadPage: load,
            saveCsv: (csv) async => exported = csv,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ჩატვირთულია: 100 · გაგრძელება ქვემოთ'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('მეტის ჩატვირთვა'),
        600,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('მეტის ჩატვირთვა'));
      await tester.pumpAndSettle();
      expect(find.text('ჩატვირთულია: 100 · გაგრძელება ქვემოთ'), findsOneWidget);
      expect(find.text('ხელახლა ცდა'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('ხელახლა ცდა'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('შეკვეთა #101'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('ჩატვირთულია: 101'), findsOneWidget);
      await tester.tap(find.text('სრული CSV ექსპორტი'));
      await tester.pumpAndSettle();
      expect(exported, contains('"id:101"'));
      expect(calls, [null, 'next', 'next', null, 'next']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('filter change discards delayed old response', (tester) async {
    final old = Completer<InventoryHistoryPage>();
    var calls = 0;
    await tester.pumpWidget(
      qa.app(
        ConsumptionHistoryScreen(
          loadPage: (_) => ++calls == 1
              ? old.future
              : Future.value(
                  page([
                    {'id': 'new', 'orderId': 2},
                  ]),
                ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    old.complete(
      page([
        {'id': 'old', 'orderId': 1},
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('შეკვეთა #1'), findsNothing);
    expect(find.text('შეკვეთა #2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'changed backend/session clears old rows and refuses continuation or export',
    (tester) async {
      var requests = 0, saved = false;
      final previous = ManagerAppPreferences.backendUrlOverride.value;
      addTearDown(
        () => ManagerAppPreferences.backendUrlOverride.value = previous,
      );
      await tester.pumpWidget(
        qa.app(
          InventoryHistoryView(
            filters: {},
            itemBuilder: (row) => Text('record:${row['id']}'),
            load: (_) async {
              requests++;
              return page([
                {'id': 'old'},
              ], 'next');
            },
            saveCsv: (_) async => saved = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('record:old'), findsOneWidget);
      ManagerAppPreferences.backendUrlOverride.value = 'http://127.0.0.1:59999';
      await tester.tap(find.text('მეტის ჩატვირთვა'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('record:old'), findsNothing);
      await tester.tap(find.text('სრული CSV ექსპორტი'));
      await tester.pumpAndSettle();
      expect(saved, false);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 768.0]) {
    testWidgets(
      'financial definitions separate gross, close payment, applied advance and outflows at $width',
      (tester) async {
        qa.narrow(tester, width: width, height: 1100);
        await tester.pumpWidget(
          qa.app(
            FinancialsScreen(
              user: User(
                username: 'synthetic',
                pinCode: '0000',
                role: 'manager',
              ),
              loadData: () async => {
                'revenue': 100.0,
                'cashRevenue': 999.0,
                'cardRevenue': 999.0,
                'revenueExact': '100.00',
                'differenceExact': '-200.00',
                'totalOutflows': '300.00',
                'ledgerSummary': {
                  'revenue': '100.00',
                  'cashCollected': '80.00',
                  'advanceApplied': '20.00',
                  'warning': 'ისტორია არასრულია',
                  'provenance': 'PARTIAL_LEDGER',
                },
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('₾-200.00'), findsOneWidget);
        expect(find.text('ისტორია არასრულია'), findsOneWidget);
        expect(
          find.byKey(const Key('financial-metric-definition')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('financial-advance-definition')),
        );
        expect(
          find.textContaining('გამოყენებული ავანსი: 20.00'),
          findsOneWidget,
        );
        expect(find.text('₾80.00'), findsNWidgets(2));
        expect(find.text('₾999.00'), findsNothing);
        expect(find.text('დახურვებზე მიღებული თანხა'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await qa.screenshot(tester, 'inv02-financial-${width.toInt()}');
      },
    );
  }
  testWidgets('interrupted export produces no file and reports error', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      qa.app(
        InventoryHistoryView(
          filters: {},
          itemBuilder: (r) => Text('${r['id']}'),
          load: (c) async {
            if (c != null) throw StateError('offline');
            return page([
              {'id': '1'},
            ], 'next');
          },
          saveCsv: (_) async => saved = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('სრული CSV ექსპორტი'));
    await tester.pumpAndSettle();
    expect(saved, false);
    expect(find.textContaining('ექსპორტი ვერ დასრულდა'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
