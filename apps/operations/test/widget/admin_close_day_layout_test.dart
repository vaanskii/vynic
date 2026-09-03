import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/admin_close_day_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// The close-day tab used to be four short cards on a tall page, so the bottom
/// third of a POS screen was empty. It now carries a day summary and a
/// pre-close readiness list, and its last row stretches into whatever height
/// is left. Both of those can fail at runtime rather than at compile time —
/// an [Expanded] under a scroll view throws, and a taller page can overflow —
/// so they are pinned here.

late Directory _tempDir;

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
}

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('cd_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('cd_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('cd_res');
  DatabaseCore.settingsBox = await Hive.openBox('cd_settings');
  DatabaseCore.userBox = await Hive.openBox<User>('cd_users');
  DatabaseCore.salesBox = await Hive.openBox('cd_sales');

  final now = DateTime.now();
  final dateKey = now.toIso8601String().split('T')[0];
  await DatabaseCore.settingsBox!.put('currentDate', now.toIso8601String());
  await DatabaseCore.settingsBox!.put('dailySalesTotal', 260.0);

  // Three fiscal sales — one cash, one TBC card, one split — plus a cancelled
  // record and a non-fiscal one, which the summary reports separately.
  Map<String, dynamic> sale({
    required int orderId,
    required double total,
    required Map<String, double> breakdown,
    bool isFiscal = true,
    bool isCancelled = false,
    double discount = 0,
  }) => {
    'orderId': orderId,
    'tableNumbers': ['$orderId'],
    'floor': 'first',
    'items': const [],
    'totalAmount': total,
    'total': total,
    'paymentMethod': breakdown.keys.first,
    'paymentBreakdown': breakdown,
    'createdBy': 'giorgi',
    'createdAt': now.toIso8601String(),
    'closedAt': now.toIso8601String(),
    'includeServiceFee': true,
    'discountAmount': discount,
    'advanceAmount': 0.0,
    'subtotalAmount': total,
    'manualAdjustmentAmount': 0.0,
    'date': dateKey,
    'isCancelled': isCancelled,
    'isFiscal': isFiscal,
    'restoredToOrder': false,
  };

  await DatabaseCore.salesBox!.add(
    sale(orderId: 1, total: 100, breakdown: {'cash': 100}),
  );
  await DatabaseCore.salesBox!.add(
    sale(orderId: 2, total: 60, breakdown: {'card-tbc': 60}, discount: 5),
  );
  await DatabaseCore.salesBox!.add(
    sale(orderId: 3, total: 100, breakdown: {'cash': 40, 'card-bog': 60}),
  );
  await DatabaseCore.salesBox!.add(
    sale(orderId: 4, total: 25, breakdown: {'cash': 25}, isCancelled: true),
  );
  await DatabaseCore.salesBox!.add(
    sale(orderId: 5, total: 30, breakdown: {'cash': 30}, isFiscal: false),
  );

  // One table still open, so the readiness list has something to block on.
  final open = Order(
    orderId: 9,
    tableNumbers: ['7'],
    floor: 'first',
    items: [],
    totalAmount: 42,
    createdBy: 'giorgi',
    createdAt: now,
  )..status = 'served';
  await DatabaseCore.orderBox!.put(9, open);

  for (var i = 1; i <= 6; i++) {
    final table = TableModel(tableNumber: '$i', floor: 'first');
    if (i == 3) table.reserveForReservation('giorgi', 'res-1');
    await DatabaseCore.tableBox!.add(table);
  }
}

/// The management centre's shell: fixed sidebar, stretched content column.
Widget _shell(Size size, Widget section) {
  const sidebar = 236.0;
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: sidebar),
              Expanded(
                child: ClipRect(
                  child: KeyedSubtree(
                    key: const ValueKey('section'),
                    child: section,
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

Widget _section() => AdminCloseDaySection(
  user: _user,
  onShowBusinessDateSelector: () async {},
  formatDateTimeDisplay: (date) => date.toIso8601String(),
);

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_shell(size, _section()));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_close_day');
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
    DatabaseCore.userBox = null;
    DatabaseCore.salesBox = null;
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
  });

  group('layout', () {
    for (final size in const [
      Size(1024, 768),
      Size(1280, 800),
      Size(1440, 900),
      Size(1920, 1080),
      // Narrow enough to drop to the stacked single-column path.
      Size(820, 1180),
    ]) {
      testWidgets('renders without overflow at ${size.width}x${size.height}', (
        tester,
      ) async {
        await _pumpAt(tester, size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the last row stretches to the bottom of a tall screen', (
      tester,
    ) async {
      const size = Size(1920, 1080);
      await _pumpAt(tester, size);
      expect(tester.takeException(), isNull);

      // The operations card is in the final row, which is Expanded on wide
      // screens. Before, it stopped around two thirds down and left a band of
      // empty page underneath.
      final actions = tester.getRect(
        find
            .ancestor(of: find.text('ოპერაციები'), matching: find.byType(Card))
            .first,
      );
      expect(actions.bottom, greaterThan(size.height - 60));
    });
  });

  group('day summary', () {
    testWidgets('shows the payment split beside the total', (tester) async {
      await _pumpAt(tester, const Size(1440, 900));

      expect(find.text('დღის შეჯამება'), findsOneWidget);
      // Gross sales derived from the records, not the sum of every record in
      // the box. Twice: once as the headline, once as the day's takings —
      // with no deposits in this fixture the two are the same number.
      expect(find.text('₾260.00'), findsNWidgets(2));
      expect(find.text('დღეს ინკასირებული'), findsOneWidget);
      expect(find.text('OK · ₾260.00'), findsOneWidget);
      expect(find.text('ნაღდი'), findsOneWidget);
      expect(find.text('ბარათი TBC'), findsOneWidget);
      expect(find.text('ბარათი BOG'), findsOneWidget);

      // cash 100 + 40, TBC 60, BOG 60 — the split adds up to the total.
      expect(find.text('₾140.00'), findsOneWidget);
      expect(find.text('₾60.00'), findsNWidgets(2));
    });

    testWidgets('reports what the total leaves out', (tester) async {
      await _pumpAt(tester, const Size(1440, 900));

      // One non-fiscal sale (₾30) and one cancelled record, both excluded
      // from the total rather than quietly folded into it.
      expect(find.text('არაფისკალური (ჯამში არ შედის)'), findsOneWidget);
      expect(find.text('1 · ₾30.00'), findsOneWidget);
      expect(find.text('გაუქმებული / დაბრუნებული'), findsOneWidget);
      expect(find.text('1 ჩანაწერი'), findsOneWidget);
    });
  });

  group('readiness', () {
    testWidgets('blocks on the open table and the reserved one', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1440, 900));

      expect(find.text('დახურვის მზადყოფნა'), findsOneWidget);
      expect(find.text('ღია მაგიდები'), findsWidgets);
      expect(find.text('დარეზერვებული მაგიდები'), findsOneWidget);
      expect(find.text('2 შემოწმება ხელს უშლის დახურვას.'), findsOneWidget);

      // The checks that pass say so rather than disappearing.
      expect(find.text('გატანის ღია შეკვეთა არ არის'), findsOneWidget);
      expect(find.text('ყველა რეზერვაცია დასრულებულია'), findsOneWidget);
    });

    testWidgets('reading readiness does not release reserved tables', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1440, 900));
      await tester.pump();

      // The close flow releases stale tables before counting; a rebuild must
      // not, or the floor would change every time the tab repaints.
      final reserved = DatabaseCore.tableBox!.values
          .where((t) => t.isReserved)
          .length;
      expect(reserved, 1);
    });
  });
}
