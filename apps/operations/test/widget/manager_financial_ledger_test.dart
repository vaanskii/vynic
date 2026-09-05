import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/core/models/user.dart';

final _manager = User(username: 'manager', pinCode: '0000', role: 'manager');

Map<String, dynamic> fixture({String? warning, List<Object?>? sales}) => {
  'revenue': 100.0,
  'expenses': 10.0,
  'cashRevenue': 40.0,
  'cardRevenue': 60.0,
  'expenseBreakdown': const <Object?>[],
  'expenseEntries': const <Object?>[],
  'ledgerSummary': {
    'revenue': '100.00',
    'tbcCollected': '60.00',
    'bogCollected': '0.00',
    'advanceApplied': '20.00',
    'voidedCount': 1,
    'restoredCount': 1,
    'internalCount': 1,
    if (warning != null) 'warning': warning,
  },
  'sales': sales ?? const <Object?>[],
  'products': const [
    {'name': 'Khinkali', 'quantity': 10, 'revenue': '25.00'},
  ],
  'saleStaff': const [
    {'staffName': 'Nino', 'saleCount': 2, 'revenue': '100.00'},
  ],
};

Map<String, dynamic> saleSummary() => {
  'id': 'cloud-sale-1',
  'posSaleId': 'pos-sale-1',
  'posOrderId': 523,
  'closedAt': '2026-09-04T14:22:00.000Z',
  'gross': '100.00',
  'paymentMethod': 'card-tbc',
  'isFiscal': true,
  'isCancelled': false,
  'restoredToOrder': false,
};

Map<String, dynamic> saleDetail() => {
  ...saleSummary(),
  'businessDate': '2026-09-04',
  'floor': 'first',
  'tableNumbers': ['1'],
  'closureId': 'closure-523',
  'advanceApplied': '20.00',
  'amountDueNow': '80.00',
  'collectedNow': '80.00',
  'closedById': 'manager',
  'lines': const [
    {
      'itemName': 'Khinkali',
      'quantity': 10,
      'unitPrice': '2.50',
      'lineTotal': '25.00',
      'menuItemId': 'menu-1',
      'variantId': 'variant-1',
    },
  ],
  'payments': const [
    {'method': 'card-tbc', 'amount': '80.00'},
    {'method': 'advance', 'amount': '20.00'},
  ],
  'auditLink': const {'reportId': 'audit-523'},
};

Widget app({
  required Future<Map<String, dynamic>> Function() load,
  Future<Map<String, dynamic>> Function(String)? detail,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: FinancialsScreen(user: _manager, loadData: load, loadSale: detail),
);

void main() {
  testWidgets('renders loading, complete ledger sections, list and detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      app(load: () => completer.future, detail: (_) async => saleDetail()),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(fixture(sales: [saleSummary()]));
    await tester.pumpAndSettle();
    expect(find.text('გაყიდვების ისტორია'), findsOneWidget);
    expect(find.text('ტოპ პროდუქტები'), findsOneWidget);
    expect(find.text('თანამშრომლების შედეგები'), findsOneWidget);
    final saleRow = find.byKey(const ValueKey('sale-cloud-sale-1'));
    await tester.scrollUntilVisible(
      saleRow,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saleRow);
    await tester.pumpAndSettle();
    expect(find.text('Closure ID'), findsOneWidget);
    expect(find.text('audit-523'), findsOneWidget);
    expect(find.textContaining('Khinkali'), findsWidgets);
  });

  testWidgets('renders empty ledger and legacy fallback warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const warning =
        'Detailed sale history is unavailable for part of this period. Summary values include legacy daily records.';
    await tester.pumpWidget(app(load: () async => fixture(warning: warning)));
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
    await tester.fling(
      find.byType(CustomScrollView).first,
      const Offset(0, -900),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('ამ პერიოდში დეტალური გაყიდვები არ არის'), findsOneWidget);
  });

  testWidgets('renders partial-history warning without claiming completeness', (
    tester,
  ) async {
    const warning =
        'Detailed sale history is incomplete for part of this period. Totals shown are ledger-only and may be partial.';
    await tester.pumpWidget(app(load: () async => fixture(warning: warning)));
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
  });

  testWidgets('renders a load error with retry', (tester) async {
    await tester.pumpWidget(app(load: () async => throw Exception('offline')));
    await tester.pumpAndSettle();
    expect(find.text('სერვერთან კავშირი ვერ დამყარდა'), findsOneWidget);
    expect(find.text('თავიდან ცდა'), findsOneWidget);
  });
}
