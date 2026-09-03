import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_action_helpers.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_actions_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_content_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_header_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_side_panels.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';

/// The order detail page, assembled the way the screen assembles it, against a
/// real (temp-dir) Hive.
///
/// The page is dense — a header, four metric cards, a reservation strip, a long
/// bill and a rail of buttons — so it is exactly the kind of layout that
/// overflows on the smallest supported POS. Every resolution is covered in the
/// busiest state: ten lines, a service fee and an advance already taken.
///
/// These pump the sections rather than `OrderDetailScreen` itself: pumping the
/// whole screen never returns under `flutter_test`, for something in its
/// initialisation that predates this work. The sections below are the entire
/// visual surface, wired exactly as the screen wires them.

late Directory _tempDir;

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

const _dishes = <(String, double, int)>[
  ('ხინკალი (კალმახი)', 2.50, 10),
  ('მწვადი ღორის', 18.00, 4),
  ('შემერული', 24.00, 2),
  ('აჯაფსანდალი', 12.50, 2),
  ('სალათი', 14.00, 3),
  ('შოთის პური', 1.50, 4),
  ('საფერავი 0.75', 42.00, 2),
  ('ჭაჭა 0.5', 30.00, 1),
  ('ბორჯომი 0.5', 3.00, 4),
  ('ჩიზქეიქი', 14.00, 4),
];

late Order _order;

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('od_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('od_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('od_res');
  DatabaseCore.settingsBox = await Hive.openBox('od_settings');

  // The venue's business day is deliberately NOT today — a normal state after
  // a day is left open, and the one that used to make the duration card read
  // 1368:08:05. Every test in this file therefore runs against a business
  // clock that disagrees with the wall clock.
  await DatabaseCore.settingsBox!.put(
    'currentDate',
    DateTime.now().subtract(const Duration(days: 57)).toIso8601String(),
  );
  final now = DatabaseService.getCurrentDateTime();

  _order = Order(
    orderId: 1,
    tableNumbers: ['1'],
    floor: 'first',
    items: [
      for (final (name, price, quantity) in _dishes)
        OrderItem(
          itemKey: name,
          itemName: name,
          unitPrice: price,
          quantity: quantity,
          total: price * quantity,
        ),
    ],
    totalAmount: 340,
    createdBy: 'გიორგი',
    createdAt: now.subtract(const Duration(hours: 1, minutes: 33)),
  )..status = 'served';
  // An advance already taken, so the totals card carries its extra line.
  // It lives in `advanceAmount` since Phase 1B: an advance reduces what is
  // left to collect, a discount reduces what the meal was worth, and they
  // used to share one field.
  _order.advanceAmount = 100;
  _order.includeServiceFee = true;
  _order.recalculateTotal();
  await DatabaseCore.orderBox!.put(1, _order);

  final table = TableModel(tableNumber: '1', floor: 'first');
  table.reserve('გიორგი', 1);
  await DatabaseCore.tableBox!.add(table);
}

OrderActionsBundle _bundle() {
  return OrderDetailActionHelpers.buildActions(
    status: _order.status,
    order: _order,
    user: _user,
    canPrintKitchenCheck: true,
    canPrintReceipt: true,
    canModify: true,
    isTakeAwayOrder: false,
    canCloseTable: true,
    canNonFiscalClose: true,
    serviceFeeAvailable: true,
    serviceFeePercentageLabel: '10',
    onConfirmOrder: () {},
    onPrintKitchenCheck: () {},
    onPrintReceipt: () {},
    onToggleServiceFee: () {},
    onOpenServiceFeeConfig: () {},
    onStartNonFiscalClosureFlow: () {},
    onShowDiscountDialog: () {},
    onShowManualAdjustmentDialog: () {},
    onShowChangeTableDialog: () {},
    onShowMoveItemsDialog: () {},
    onConfirmCancelOrder: () {},
    onStartTableClosureFlow: () {},
  );
}

/// The page as the screen builds it: header, then a two-column body.
Widget _harness(Size size, {bool hasReservation = false}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(
            children: [
              OrderDetailHeaderSection(
                order: _order,
                isTakeAwayOrder: false,
                guestCount: 3,
                onBack: () {},
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OrderDetailMetricsRow(
                              order: _order,
                              isTakeAwayOrder: false,
                              guestCount: 3,
                              onGuestsChanged: (_) {},
                            ),
                            const SizedBox(height: 12),
                            OrderDetailReservationPanel(
                              isTakeAwayOrder: false,
                              hasReservation: hasReservation,
                              customerName: hasReservation ? 'ნინო' : null,
                              customerPhone: hasReservation
                                  ? '555 12 34 56'
                                  : null,
                              onEditReservation: () {},
                              onAddReservation: () {},
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: OrderDetailContentSection(
                                order: _order,
                                canModify: true,
                                isAdmin: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 300,
                        child: OrderDetailActionRail(
                          order: _order,
                          actionsBundle: _bundle(),
                          serviceFeePercentageLabel: '10',
                          onEditOrder: () {},
                          canEditOrder: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const _resolutions = <(String, Size)>[
  ('1024x768', Size(1024, 768)),
  ('1280x720', Size(1280, 720)),
  ('1366x768', Size(1366, 768)),
  ('1440x900', Size(1440, 900)),
  ('1920x1080', Size(1920, 1080)),
];

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool booked = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(size, hasReservation: booked));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_order_detail');
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _seed();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.tableBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.reservationBox = null;
    DatabaseCore.settingsBox = null;
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
  });

  for (final (name, size) in _resolutions) {
    testWidgets('lays out without overflow at $name', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out without overflow at $name with a booking', (
      tester,
    ) async {
      await _pump(tester, size, booked: true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the header answers where, what and how much', (tester) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.text('მაგიდები'), findsOneWidget);
    // An open table reads as occupied, not as the internal order status.
    expect(find.text('დაკავებული'), findsOneWidget);
    // The amount owed is stated once, on the totals card — not twice.
    expect(find.text('გადასახდელი'), findsOneWidget);
    expect(find.text('340.00 ₾'), findsOneWidget);
  });

  testWidgets('duration is measured on the business clock', (tester) async {
    // A table opened moments ago on a business day that is not today. Reading
    // the wall clock here reported the gap between the two calendars instead
    // of how long the guests had been sitting.
    final justOpened = Order(
      orderId: 2,
      tableNumbers: ['1'],
      floor: 'first',
      items: const [],
      totalAmount: 0,
      createdBy: 'გიორგი',
      createdAt: DatabaseService.getCurrentDateTime(),
    )..status = 'confirmed';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDetailMetricsRow(
            order: justOpened,
            isTakeAwayOrder: false,
            guestCount: 2,
          ),
        ),
      ),
    );

    expect(find.textContaining(RegExp(r'^0:00:\d\d$')), findsOneWidget);
  });

  testWidgets('a long-running table still reads its real elapsed time', (
    tester,
  ) async {
    // The seeded order was opened 1h33m ago on the business clock.
    await _pump(tester, const Size(1440, 900));
    expect(find.textContaining(RegExp(r'^1:3\d:\d\d$')), findsOneWidget);
  });

  testWidgets('the metric cards carry the four figures', (tester) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.text('ოფიციანტი'), findsOneWidget);
    expect(find.text('გახსნა'), findsOneWidget);
    expect(find.text('ხანგრძლივობა'), findsOneWidget);
    expect(find.text('სტუმარი'), findsOneWidget);
  });

  testWidgets('the bill lists every dish once', (tester) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.text('ORDER'), findsOneWidget);
    for (final (name, _, _) in _dishes) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('an advance reads as a deduction, not another charge', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.text('ავანსი'), findsWidgets);
    expect(find.text('− 100.00 ₾'), findsOneWidget);
  });

  testWidgets('a table with no booking says so and offers to add one', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.text('ამ მაგიდაზე რეზერვაცია არ არის'), findsOneWidget);
    expect(find.text('რეზერვაციის დამატება'), findsOneWidget);
    expect(find.text('დეტალების შეცვლა'), findsNothing);
  });

  testWidgets('a booked table shows the guest instead', (tester) async {
    await _pump(tester, const Size(1440, 900), booked: true);

    expect(find.text('ამ მაგიდაზე რეზერვაცია არ არის'), findsNothing);
    expect(find.textContaining('ნინო'), findsOneWidget);
    expect(find.text('დეტალების შეცვლა'), findsOneWidget);
  });

  testWidgets('the rail keeps every action the footer used to carry', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));

    for (final label in const [
      'შეკვეთა',
      'ბეჭდვა',
      'მაგიდა',
      'მენიუს რედაქტირება',
      'ავანსი',
      'ფასის კორექცია',
      'სერვისი (10%)',
      'სამზარეულოს ჩეკი',
      'ჩეკის დაბეჭდვა',
      'მაგიდის შეცვლა',
      'პროდუქტების გადატანა',
      'არაფისკალური დახურვა',
      'შეკვეთის გაუქმება',
      'მაგიდის დახურვა',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('the receipt service-fee row is an admin setting, not a rail '
      'button', (tester) async {
    // „ჩეკზე ასახვა" governs every receipt the venue prints, not this one
    // order. Having it on the order rail put a house-wide setting one tap from
    // a waiter mid-service, and made it look like a per-table choice. It lives
    // in Settings only.
    await _pump(tester, const Size(1440, 900));
    expect(find.text('ჩეკზე ასახვა'), findsNothing);
  });

  testWidgets('press-and-hold on the service fee still opens its config', (
    tester,
  ) async {
    // The custom service rates are only reachable through this long-press, so
    // it has to survive the move to the grouped rail.
    var configOpened = false;
    final bundle = OrderDetailActionHelpers.buildActions(
      status: _order.status,
      order: _order,
      user: _user,
      canPrintKitchenCheck: false,
      canPrintReceipt: false,
      canModify: true,
      isTakeAwayOrder: false,
      canCloseTable: false,
      canNonFiscalClose: false,
      serviceFeeAvailable: true,
      serviceFeePercentageLabel: '10',
      onConfirmOrder: () {},
      onPrintKitchenCheck: () {},
      onPrintReceipt: () {},
      onToggleServiceFee: () {},
      onOpenServiceFeeConfig: () => configOpened = true,
      onStartNonFiscalClosureFlow: () {},
      onShowDiscountDialog: () {},
      onShowManualAdjustmentDialog: () {},
      onShowChangeTableDialog: () {},
      onShowMoveItemsDialog: () {},
      onConfirmCancelOrder: () {},
      onStartTableClosureFlow: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 700,
            child: OrderDetailActionRail(
              order: _order,
              actionsBundle: bundle,
              serviceFeePercentageLabel: '10',
              onEditOrder: () {},
              canEditOrder: true,
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('სერვისი (10%)'));
    await tester.pump();

    expect(configOpened, isTrue);
  });
}
