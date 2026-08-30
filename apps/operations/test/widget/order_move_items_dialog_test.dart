import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/order/order_move_items_dialog.dart';
import 'package:vynic/core/models/order.dart';

/// The picker for „move these items onto that order".
///
/// It is the densest dialog on the POS — two scrolling panes, a stepper per
/// line and a footer — so it is checked at every supported resolution in the
/// state that fills it most.

/// `flutter_test` otherwise substitutes a face whose every glyph is a full em
/// square, which roughly doubles the measured width of Georgian text and
/// reports tears that do not exist on the terminal.
Future<void> _loadRealFont() async {
  final data = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
}

OrderItem _line(String name, double price, int qty, {String? comment}) =>
    OrderItem(
      itemKey: name,
      itemName: name,
      unitPrice: price,
      quantity: qty,
      total: price * qty,
      comment: comment,
    );

Order _order({
  required int id,
  required List<OrderItem> items,
  String floor = 'first',
  List<String>? tables,
  bool serviceFee = false,
}) {
  final order = Order(
    orderId: id,
    tableNumbers: tables ?? ['$id'],
    floor: floor,
    items: items,
    totalAmount: 0,
    createdAt: DateTime(2026, 8, 23, 19),
    createdBy: 'გიორგი',
    includeServiceFee: serviceFee,
  )..status = 'confirmed';
  order.recalculateTotal();
  return order;
}

Order _source() => _order(
  id: 1,
  tables: ['7'],
  serviceFee: true,
  items: [
    _line('ხინკალი კალმახის ხორცით', 2.50, 10, comment: 'ცომი თხელი'),
    _line('ჩაქაფული ტარხუნით და თეთრი ღვინით', 26.00, 4),
    _line('საფერავი 0.75', 42.00, 3),
    _line('ბადრიჯანი ნიგვზით', 14.00, 2),
    _line('შოთის პური', 1.50, 6),
  ],
);

/// The picker as the order screen assembles it: open orders first, then the
/// things a move can create — a free table, and a fresh take-away.
List<OrderMoveOption> _options() {
  final open12 = _order(
    id: 2,
    tables: ['12'],
    items: [_line('ლიმონათი', 4.00, 2)],
  );
  final openTakeAway = _order(
    id: 3,
    floor: 'takeaway',
    tables: ['TA-4'],
    items: [_line('მწვადი', 18.00, 1)],
  );
  return [
    OrderMoveOption(
      target: ExistingOrderTarget(open12),
      label: 'მაგიდა 12',
      detail: 'პირველი სართული  ·  1 პოზიცია  ·  8.00 ₾',
    ),
    OrderMoveOption(
      target: ExistingOrderTarget(openTakeAway),
      label: 'გატანა — ლევანი',
      detail: '1 პოზიცია  ·  18.00 ₾',
    ),
    const OrderMoveOption(
      target: FreeTableTarget(tableNumber: '3', floor: 'first'),
      label: 'მაგიდა 3',
      detail: 'პირველი სართული  ·  თავისუფალი',
      isNew: true,
    ),
    const OrderMoveOption(
      target: NewTakeAwayTarget(),
      label: 'ახალი გატანა',
      detail: 'შეიქმნება ახალი გატანის შეკვეთა',
      isNew: true,
    ),
  ];
}

const _resolutions = <(String, Size)>[
  ('1200x720', Size(1200, 720)),
  ('1280x720', Size(1280, 720)),
  ('1366x768', Size(1366, 768)),
  ('1440x900', Size(1440, 900)),
  ('1920x1080', Size(1920, 1080)),
];

OrderMoveRequest? _captured;

Future<void> _open(WidgetTester tester, Size size, {Order? source}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _captured = null;

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  _captured = await showDialog<OrderMoveRequest>(
                    context: context,
                    builder: (_) => OrderMoveItemsDialog(
                      source: source ?? _source(),
                      sourceLabel: 'მაგიდა 7',
                      options: _options(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _loadRealFont();
    Order.serviceFeeRateResolver = () => 0.10;
  });

  tearDownAll(() => Order.serviceFeeRateResolver = null);

  for (final (name, size) in _resolutions) {
    testWidgets('lays out without overflow at $name', (tester) async {
      await _open(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.text('პროდუქტების გადატანა'), findsOneWidget);
    });

    testWidgets('still fits at $name with lines picked and a target', (
      tester,
    ) async {
      // The busiest state: a warning line under the summary, a selected
      // destination, and the footer carrying a figure.
      await _open(tester, size);
      await tester.tap(find.text('ყველა').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('გატანა — ლევანი'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a table and a take-away are both offered as targets', (
    tester,
  ) async {
    // The whole point of the feature: it runs in both directions.
    await _open(tester, const Size(1280, 720));

    expect(find.text('მაგიდა 12'), findsOneWidget);
    expect(find.text('გატანა — ლევანი'), findsOneWidget);
  });

  testWidgets('a free table and a new take-away are offered too', (
    tester,
  ) async {
    // Half the time the table the guests want is still free. Without these the
    // operator has to leave, open it on the floor screen, and come back.
    await _open(tester, const Size(1280, 720));

    expect(find.text('უკვე გახსნილი'), findsOneWidget);
    expect(find.text('ახლად გაიხსნება'), findsOneWidget);
    expect(find.text('მაგიდა 3'), findsOneWidget);
    expect(find.text('ახალი გატანა'), findsOneWidget);
  });

  testWidgets('the header says where the items are going', (tester) async {
    // The dialog used to name only the order the items were leaving. „Where am
    // I taking these" was answerable only by remembering which row was tinted.
    await _open(tester, const Size(1280, 720));
    expect(find.text('აირჩიეთ დანიშნულება'), findsOneWidget);

    await tester.tap(find.text('მაგიდა 12'));
    await tester.pumpAndSettle();

    expect(find.text('აირჩიეთ დანიშნულება'), findsNothing);
    expect(find.text('მაგიდა 7'), findsOneWidget);
    expect(find.text('მაგიდა 12'), findsWidgets);
  });

  testWidgets('choosing a free table hands back a target, not an order', (
    tester,
  ) async {
    // The dialog never opens anything. The screen does, after the operator has
    // confirmed — so backing out of the move leaves no half-opened table
    // behind.
    await _open(tester, const Size(1280, 720));

    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('მაგიდა 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('გადატანა'));
    await tester.pumpAndSettle();

    final target = _captured!.option.target;
    expect(target, isA<FreeTableTarget>());
    expect((target as FreeTableTarget).tableNumber, '3');
  });

  testWidgets('a new take-away can be chosen as the destination', (
    tester,
  ) async {
    await _open(tester, const Size(1280, 720));

    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ახალი გატანა'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('გადატანა'));
    await tester.pumpAndSettle();

    expect(_captured!.option.target, isA<NewTakeAwayTarget>());
  });

  testWidgets('nothing can be confirmed until both halves are chosen', (
    tester,
  ) async {
    await _open(tester, const Size(1280, 720));
    expect(find.text('აირჩიეთ პროდუქტები და დანიშნულება'), findsOneWidget);

    // Items but no destination: still not enough.
    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('გადატანა'));
    await tester.pumpAndSettle();
    expect(_captured, isNull, reason: 'confirmed without a destination');
  });

  testWidgets('the footer counts what is actually picked', (tester) async {
    await _open(tester, const Size(1280, 720));

    // „ყველა" on the first line: 10 x 2.50.
    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    expect(
      find.text('10 ცალი  ·  25.00 ₾  ·  აირჩიეთ დანიშნულება'),
      findsOneWidget,
    );

    // One more off the second line: +26.00.
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();
    expect(
      find.text('11 ცალი  ·  51.00 ₾  ·  აირჩიეთ დანიშნულება'),
      findsOneWidget,
    );
  });

  testWidgets('a stepper cannot go past what the line holds', (tester) async {
    await _open(tester, const Size(1280, 720));

    // The last line has 6; tapping `+` ten times must stop at 6 rather than
    // letting the operator request more than exists.
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();
    }
    expect(
      find.text('6 ცალი  ·  9.00 ₾  ·  აირჩიეთ დანიშნულება'),
      findsOneWidget,
    );
  });

  testWidgets('taking the whole bill says the table will be left empty', (
    tester,
  ) async {
    // An open table holding nothing looks like a bug unless it was asked for.
    await _open(
      tester,
      const Size(1280, 720),
      source: _order(id: 1, tables: ['7'], items: [_line('ხინკალი', 2.50, 4)]),
    );

    await tester.tap(find.text('ყველა'));
    await tester.pumpAndSettle();

    expect(find.textContaining('გათავისუფლდება'), findsOneWidget);
  });

  testWidgets('a service-fee mismatch is called out before it is applied', (
    tester,
  ) async {
    // The source charges service and table 12 does not, so the totals will not
    // simply swap over. Legitimate, but not something to discover afterwards.
    await _open(tester, const Size(1280, 720));

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('მაგიდა 12'));
    await tester.pumpAndSettle();

    expect(find.textContaining('განსხვავებული სერვისი'), findsOneWidget);
  });

  testWidgets('confirming hands back the destination and the quantities', (
    tester,
  ) async {
    await _open(tester, const Size(1280, 720));

    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('მაგიდა 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('გადატანა'));
    await tester.pumpAndSettle();

    expect(_captured, isNotNull);
    final target = _captured!.option.target as ExistingOrderTarget;
    expect(target.order.orderId, 2);
    expect(_captured!.moves, [(index: 0, quantity: 10)]);
  });

  testWidgets('backing out returns nothing at all', (tester) async {
    await _open(tester, const Size(1280, 720));

    await tester.tap(find.text('ყველა').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('გაუქმება'));
    await tester.pumpAndSettle();

    expect(_captured, isNull);
  });
}
