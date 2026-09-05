import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/receiving.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansGeorgian')
      ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  final row = <String, dynamic>{
    'id': 'consumption-1',
    'posSaleId': 'sale-1',
    'closureId': 'close-1',
    'orderId': 523,
    'businessDate': '2026-09-05',
    'policy': 'FISCAL_CLOSE',
    'reversedAt': null,
    'lines': [
      {
        'itemName': 'ხინკალი',
        'soldQuantity': 10,
        'status': 'MAPPED',
        'recipeId': 'recipe-1',
        'recipeRevision': 2,
        'components': [
          {
            'stockItemNameSnapshot': 'საქონლის ხორცი',
            'baseQuantityPerUnit': '0.035000',
            'totalBaseQuantity': '0.350000',
            'baseUnit': 'kg',
          },
        ],
      },
      {
        'itemName': 'ხელით დამატებული კერძი',
        'soldQuantity': 1,
        'status': 'UNMAPPED',
      },
    ],
  };
  testWidgets(
    'narrow history shows unmapped warnings, filter, Sale and frozen components',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var filtered = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            textTheme: ThemeData.light().textTheme.apply(
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          home: ConsumptionHistoryScreen(
            load: (unmapped, from, to) async {
              filtered = unmapped;
              return [row];
            },
            loadDetail: (_) async => row,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('შეკვეთა #523'), findsOneWidget);
      expect(
        find.text('დაუკავშირებელია — მარაგი არ ჩამოწერილა'),
        findsOneWidget,
      );
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      expect(filtered, true);
      await tester.tap(find.text('დეტალები'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ვერსია 2'), findsOneWidget);
      expect(find.textContaining('0.350000'), findsOneWidget);
      expect(find.text('Sale: sale-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'negative quantity and explicit negative badge remain visible on narrow Stock list',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              textTheme: ThemeData.light().textTheme.apply(
                fontFamily: 'NotoSansGeorgian',
              ),
            ),
            home: Scaffold(
              body: InventoryAdminTab(
                loadStockItems: () async => [
                  StockItem(
                    id: 'beef',
                    name: 'საქონლის ხორცი',
                    baseUnit: InventoryUnit.kg,
                    isActive: true,
                    createdAt: DateTime(2026),
                    updatedAt: DateTime(2026),
                    currentStock: '-0.300',
                    stockStatus: 'NEGATIVE',
                  ),
                ],
                loadSuppliers: () async => [],
                loadReceivings: () async => const ReceivingPage(receivings: []),
                loadRecipes: () async => [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('უარყოფითი ნაშთი'), findsOneWidget);
      expect(find.text('ნაშთი: -0.3 კგ'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory-consumption-history')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final screenshot = Platform.environment['INVENTORY_QA_SCREENSHOT'];
      if (screenshot != null) {
        await tester.runAsync(() async {
          final rendered =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    },
  );
  testWidgets(
    'stock movement detail identifies Sale consumption and its restore on a narrow layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StockItemDetailDialog(
            stockItemId: 'beef',
            load: () async => StockItemDetail.fromJson({
              'id': 'beef',
              'name': 'ხორცი',
              'baseUnit': 'kg',
              'currentStock': '-0.350',
              'stockStatus': 'NEGATIVE',
              'isActive': true,
              'createdAt': '2026-09-05T10:00:00Z',
              'updatedAt': '2026-09-05T10:00:00Z',
              'recentMovements': [
                for (final reversed in [false, true])
                  {
                    'id': 'movement-$reversed',
                    'stockItemId': 'beef',
                    'movementType': reversed
                        ? 'CONSUMPTION_REVERSAL'
                        : 'CONSUMPTION',
                    'quantityDeltaBase': reversed ? '0.350000' : '-0.350000',
                    'baseUnit': 'kg',
                    'businessDate': '2026-09-05',
                    'createdAt': '2026-09-05T10:00:00Z',
                    'actorName': 'POS',
                    'details': {
                      'consumptionId': 'consumption-1',
                      'orderId': 523,
                    },
                  },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ჩამოწერა · შეკვეთა #523'), findsOneWidget);
      expect(find.text('აღდგენა · შეკვეთა #523'), findsOneWidget);
      expect(find.text('-0.35 კგ'), findsNWidgets(2));
      expect(find.text('+0.35 კგ'), findsOneWidget);
      expect(find.text('დეტალები'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history request failure is visible and retry recovers', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ConsumptionHistoryScreen(
          load: (_, from, to) async {
            if (++attempts == 1) throw const SocketException('offline');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ისტორია ვერ ჩაიტვირთა'), findsOneWidget);
    await tester.tap(find.text('ხელახლა ცდა'));
    await tester.pumpAndSettle();
    expect(find.text('ჩამოწერები ვერ მოიძებნა'), findsOneWidget);
  });
}
