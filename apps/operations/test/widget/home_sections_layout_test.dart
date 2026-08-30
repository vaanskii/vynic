import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_take_away_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// The four home sections — დათვლა, გატანები, რეზერვაცია and X — against a
/// real (temp-dir) Hive, at every supported POS resolution.
///
/// They were redesigned onto the shared POS surface, which changed the
/// heading, the metric row and every button on all four. That is exactly the
/// kind of change that overflows on the smallest window, so each one is
/// pumped in a populated state rather than empty.

late Directory _tempDir;

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

List<OrderItem> _items() => [
  OrderItem(
    itemKey: 'ხინკალი (კალმახი)',
    itemName: 'ხინკალი (კალმახი)',
    unitPrice: 2.5,
    quantity: 10,
    total: 25,
  ),
  OrderItem(
    itemKey: 'საფერავი 0.75',
    itemName: 'საფერავი 0.75',
    unitPrice: 42,
    quantity: 2,
    total: 84,
  ),
];

late List<Reservation> _reservations;
late List<Reservation> _takeaways;
late List<QuickOrderDraft> _drafts;

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('hs_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('hs_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('hs_res');
  DatabaseCore.settingsBox = await Hive.openBox('hs_settings');

  final now = DateTime.now();
  await DatabaseCore.settingsBox!.put('currentDate', now.toIso8601String());

  _reservations = [
    for (var i = 0; i < 3; i++)
      Reservation(
        id: 'r$i',
        customerName: 'ნინო ბერიძე',
        customerPhone: '555 12 34 5$i',
        tableNumbers: [i + 1],
        reservationDate: now,
        reservationTime: '19:3$i',
        numberOfGuests: 4 + i,
        notes: 'ფანჯარასთან, ტორტი დაბადების დღეზე',
        createdAt: now,
        createdBy: 'giorgi',
        status: i == 0 ? 'confirmed' : 'pending',
        preOrderItems: _items(),
      ),
  ];

  _takeaways = [
    for (var i = 0; i < 3; i++)
      Reservation(
        id: 't$i',
        customerName: 'გიორგი მაისურაძე',
        customerPhone: '577 00 11 2$i',
        tableNumbers: const [],
        reservationDate: now,
        reservationTime: '20:1$i',
        numberOfGuests: 1,
        createdAt: now,
        createdBy: 'giorgi',
        status: i == 2 ? 'completed' : 'pending',
        isTakeAway: true,
        linkedOrderId: 100 + i,
        preOrderItems: _items(),
      ),
  ];
  for (var i = 0; i < _takeaways.length; i++) {
    await DatabaseCore.orderBox!.put(
      100 + i,
      Order(
        orderId: 100 + i,
        tableNumbers: const ['TA-1'],
        floor: 'takeaway',
        items: _items(),
        totalAmount: 109,
        createdBy: 'giorgi',
        createdAt: now,
      )..status = 'served',
    );
  }

  _drafts = [
    for (var i = 0; i < 3; i++)
      QuickOrderDraft(
        id: 'd$i',
        items: _items(),
        subtotal: 109,
        serviceFeeAmount: 10.9,
        total: 119.9,
        includeServiceFee: i.isEven,
        serviceFeeRate: 0.1,
        createdAt: now,
        createdBy: 'giorgi',
        displayName: 'დათვლა #${i + 1}',
      ),
  ];
}

const _resolutions = <(String, Size)>[
  ('1024x768', Size(1024, 768)),
  ('1280x720', Size(1280, 720)),
  ('1366x768', Size(1366, 768)),
  ('1920x1080', Size(1920, 1080)),
];

Widget _wrap(Size size, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

Widget _calculator() => HomeCalculatorSection(
  quickOrderDrafts: _drafts,
  onStartQuickOrder: () {},
  onToggleServiceFee: (_) {},
  onOpenServiceFeeConfig: (_) {},
  onContinueDraft: (_) {},
  onPrintDraft: (_) {},
  onItemQuantityChanged: (_, _, _) {},
  serviceFeeAvailable: true,
  canManageDrafts: true,
  onOpenDraftManage: (_) {},
  onClearAllDrafts: () {},
  primaryColor: const Color(0xFF1E3A8A),
  secondaryColor: const Color(0xFF2563EB),
  textPrimary: const Color(0xFF1F2937),
  mutedText: const Color(0xFF64748B),
);

Widget _takeAway() => HomeTakeAwaySection(
  user: _user,
  takeAwayReservations: _takeaways,
  onRefreshRequested: () async {},
  primaryColor: const Color(0xFF1E3A8A),
  secondaryColor: const Color(0xFF2563EB),
  textPrimary: const Color(0xFF1F2937),
  mutedText: const Color(0xFF64748B),
);

Widget _reservationsSection() => HomeReservationsSection(
  user: _user,
  reservations: _reservations,
  onRefreshRequested: () async {},
  primaryColor: const Color(0xFF1E3A8A),
  secondaryColor: const Color(0xFF2563EB),
  textPrimary: const Color(0xFF1F2937),
  mutedText: const Color(0xFF64748B),
  canAssignTable: true,
  onEditReservation: (_) async {},
  onViewPreOrder: (_) async {},
  onManagePreOrder: (_) async {},
  onSendKitchenCheck: (_) async {},
  onAssignTable: (_) async {},
);

/// Two closed tables and one cancelled one — enough for the report to have to
/// render times, a duration, a payment label and a struck-through row.
List<Map<String, dynamic>> _sales() {
  final day = DateTime(2026, 8, 18);
  return [
    {
      'orderId': 1,
      'tableNumbers': ['1'],
      'floor': 'first',
      'items': [
        {
          'itemName': 'ხინკალი (კალმახი)',
          'quantity': 10,
          'unitPrice': 2.5,
          'total': 25.0,
        },
        {
          'itemName': 'საფერავი 0.75',
          'quantity': 2,
          'unitPrice': 42.0,
          'total': 84.0,
        },
      ],
      'total': 109.0,
      'totalAmount': 109.0,
      'paymentMethod': 'cash',
      'paymentBreakdown': {'cash': 109.0},
      'createdBy': 'გიორგი',
      'createdAt': day
          .add(const Duration(hours: 18, minutes: 5))
          .toIso8601String(),
      'closedAt': day
          .add(const Duration(hours: 19, minutes: 40))
          .toIso8601String(),
      'isCancelled': false,
      'isFiscal': true,
    },
    {
      'orderId': 2,
      'tableNumbers': ['2'],
      'floor': 'first',
      'items': [
        {
          'itemName': 'ხინკალი (კალმახი)',
          'quantity': 5,
          'unitPrice': 2.5,
          'total': 12.5,
        },
      ],
      'total': 12.5,
      'totalAmount': 12.5,
      'paymentMethod': 'card-tbc',
      'paymentBreakdown': {'card-tbc': 12.5},
      'createdBy': 'ნინო',
      'createdAt': day
          .add(const Duration(hours: 20, minutes: 0))
          .toIso8601String(),
      'closedAt': day
          .add(const Duration(hours: 20, minutes: 25))
          .toIso8601String(),
      'isCancelled': false,
      'isFiscal': true,
    },
    {
      'orderId': 3,
      'tableNumbers': ['3'],
      'floor': 'first',
      'items': [
        {
          'itemName': 'ჩიზქეიქი',
          'quantity': 4,
          'unitPrice': 14.0,
          'total': 56.0,
        },
      ],
      'total': 56.0,
      'totalAmount': 56.0,
      'paymentMethod': 'cash',
      'createdBy': 'ლევანი',
      'createdAt': day
          .add(const Duration(hours: 21, minutes: 0))
          .toIso8601String(),
      'closedAt': day
          .add(const Duration(hours: 21, minutes: 10))
          .toIso8601String(),
      'isCancelled': true,
      'isFiscal': true,
    },
  ];
}

Widget _xReport() => HomeXReportSection(
  closedTables: HomeXReportHelper.buildClosedTables(_sales()),
  soldItems: HomeXReportHelper.buildSoldItems(_sales()),
  dailySalesTotal: 4812.40,
  openedTablesAmount: 1260.00,
  takeAwayCount: 12,
  activeWaitersCount: 5,
  waiterSummaries: const [
    {'username': 'გიორგი', 'orderCount': 14, 'total': 2210.50},
    {'username': 'ნინო', 'orderCount': 9, 'total': 1401.90},
    {'username': 'ლევანი', 'orderCount': 6, 'total': 1200.00},
  ],
  onPrintReport: () {},
  primaryColor: const Color(0xFF1E3A8A),
  secondaryColor: const Color(0xFF2563EB),
  textPrimary: const Color(0xFF1F2937),
  mutedText: const Color(0xFF64748B),
);

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_home_sections');
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

  final sections = <(String, Widget Function())>[
    ('დათვლა', _calculator),
    ('გატანები', _takeAway),
    ('რეზერვაცია', _reservationsSection),
    ('X', _xReport),
  ];

  // Overflow coverage lives in the scale matrix at the bottom of this file:
  // it pumps each section through PosScaledSurface, which is the only way the
  // app ever renders them. Pumping a section bare at 1024 logical pixels
  // tests a size the POS no longer produces — below the design floor the
  // surface hands the layout 1280 and paints it smaller.

  testWidgets('every section leads with the shared page heading', (
    tester,
  ) async {
    // The view has to be sized explicitly: flutter_test defaults to 800x600,
    // which is below every supported POS resolution, and these sections lay
    // out their compact branch differently there.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The four screens used to open with four different headings — a tinted
    // icon tile here, a bare bold line there. They share one now.
    for (final (name, build) in sections) {
      await tester.pumpWidget(_wrap(const Size(1440, 900), build()));
      await tester.pump();
      expect(find.byType(PosPageHeading), findsOneWidget, reason: name);
    }
  });

  testWidgets('figures are shown on the shared metric card', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final (name, build) in <(String, Widget Function())>[
      ('დათვლა', _calculator),
      ('გატანები', _takeAway),
      ('რეზერვაცია', _reservationsSection),
      ('X', _xReport),
    ]) {
      await tester.pumpWidget(_wrap(const Size(1440, 900), build()));
      await tester.pump();
      expect(find.byType(PosMetricCard), findsWidgets, reason: name);
    }
  });

  testWidgets('the X report ranks waiters by their takings', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const Size(1440, 900), _xReport()));
    await tester.pump();

    expect(find.text('X ანგარიში'), findsOneWidget);
    expect(find.text('გიორგი'), findsOneWidget);
    expect(find.text('2210.50 ₾'), findsOneWidget);
    expect(find.text('14 შეკვეთა'), findsOneWidget);
    // Money still on the floor is the one figure that carries a colour.
    expect(find.text('1260.00 ₾'), findsOneWidget);
  });

  testWidgets('the X report shows each closed table with its times', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const Size(1440, 900), _xReport()));
    await tester.pump();

    expect(find.text('დახურული მაგიდები'), findsOneWidget);
    // Opened 18:05, paid 19:40 — an hour and thirty-five minutes on the table.
    expect(find.text('18:05'), findsOneWidget);
    expect(find.text('19:40'), findsOneWidget);
    expect(find.text('1:35'), findsOneWidget);
    // Under an hour reads in minutes rather than as 0:25.
    expect(find.text('25 წთ'), findsOneWidget);
  });

  testWidgets('the X report rolls dishes up across every sale', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const Size(1440, 900), _xReport()));
    await tester.pump();

    expect(find.text('გაყიდული პროდუქტები'), findsOneWidget);
    // Ten khinkali on table 1 and five on table 2 are one line of fifteen.
    expect(find.text('ხინკალი (კალმახი)'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    // The cancelled table's dessert was reversed, so it never left the
    // kitchen and must not be counted as sold.
    expect(find.text('ჩიზქეიქი'), findsNothing);
  });

  testWidgets('reservation actions are grouped in a rail, not a footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const Size(1440, 900), _reservationsSection()),
    );
    await tester.pump();

    for (final group in const ['რეზერვაცია', 'მენიუ', 'ბეჭდვა']) {
      expect(find.text(group.toUpperCase()), findsOneWidget, reason: group);
    }
    // Every action from the old footer Wrap survived the move.
    for (final label in const [
      'რეზერვაციის შეცვლა',
      'სუფრაზე გადაყვანა',
      'მენიუს შეცვლა',
      'მენიუს ნახვა',
      'სამზარეულოში გაგზავნა',
      'ჩეკის ბეჭდვა',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('take-away actions sit in a rail, sorted by what they do', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const Size(1440, 900), _takeAway()));
    await tester.pump();

    expect(find.text('სრული დეტალები'), findsOneWidget);

    // Closing takes money, cancelling voids — they used to share a red.
    final close = tester.widget<PosActionButton>(
      find
          .ancestor(
            of: find.text('შეკვეთის დახურვა'),
            matching: find.byType(PosActionButton),
          )
          .first,
    );
    final cancel = tester.widget<PosActionButton>(
      find
          .ancestor(
            of: find.text('გაუქმება'),
            matching: find.byType(PosActionButton),
          )
          .first,
    );
    expect(close.tone, PosActionTone.money);
    expect(cancel.tone, PosActionTone.danger);
  });

  testWidgets('the action rail stays on the right, never a scrolling strip', (
    tester,
  ) async {
    // Below the design floor the whole layout is painted smaller rather than
    // folding the rail away, so a small window still shows list, detail and
    // rail side by side — just smaller.
    for (final (name, build) in <(String, Widget Function())>[
      ('გატანები', _takeAway),
      ('რეზერვაცია', _reservationsSection),
    ]) {
      const window = Size(1024, 700);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: window),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: window.width,
                height: window.height,
                child: PosScaledSurface(scale: 1.0, child: build()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PosPaneSwitch), findsNothing, reason: name);
      // Nothing on this screen scrolls sideways.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ScrollView && widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
        reason: name,
      );
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  // Every section, at every supported resolution, at every UI scale the
  // settings offer. Scaling is meant to make the POS fit better, so a scale
  // that overflows is the setting failing at its one job.
  for (final scale in const [0.9, 1.0, 1.1]) {
    for (final (name, build) in <(String, Widget Function())>[
      ('დათვლა', _calculator),
      ('გატანები', _takeAway),
      ('რეზერვაცია', _reservationsSection),
      ('X', _xReport),
    ]) {
      for (final (label, size) in _resolutions) {
        testWidgets('$name at ${(scale * 100).round()}% fits $label', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(size: size),
              child: MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: PosScaledSurface(scale: scale, child: build()),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
