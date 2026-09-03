import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/widgets/home/home_tables_dashboard_section.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';

/// Pumps the real home-screen tables tab against a real (temp-dir) Hive so
/// overflow shows up here instead of on a terminal. Every supported POS
/// resolution is covered, in the worst-case state: tables occupied, an order
/// awaiting payment, and reservations queued — that is when the service rail
/// carries the most content.

late Directory _tempDir;

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

Future<void> _seed() async {
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('t_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('t_orders');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('t_res');
  DatabaseCore.settingsBox = await Hive.openBox('t_settings');

  final now = DateTime.now();
  await DatabaseCore.settingsBox!.put('currentDate', now.toIso8601String());

  // A served order: this is what populates the rail's "needs attention"
  // card, whose long money+waiter line is the tightest thing in the rail.
  final order = Order(
    orderId: 1,
    tableNumbers: ['1'],
    floor: 'first',
    items: [],
    totalAmount: 1234.56,
    createdBy: 'ოპერატორი გიორგი',
    createdAt: now.subtract(const Duration(hours: 2)),
  )..status = 'served';
  await DatabaseCore.orderBox!.put(1, order);

  for (var i = 1; i <= 13; i++) {
    final table = TableModel(tableNumber: '$i', floor: 'first');
    if (i == 1) {
      table.reserve('ოპერატორი გიორგი', 1);
    } else if (i == 2) {
      table.reserveForReservation('ოპერატორი გიორგი', 'res-1');
    }
    await DatabaseCore.tableBox!.add(table);
  }
  for (var i = 1; i <= 9; i++) {
    await DatabaseCore.tableBox!.add(
      TableModel(tableNumber: '$i', floor: 'second'),
    );
  }
}

Widget _harness(Size size, double sidebarWidth, PosDisplaySettings settings) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: size.width - sidebarWidth,
        height: size.height,
        child: _dashboard(settings),
      ),
    ),
  );
}

Widget _dashboard(PosDisplaySettings settings) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTablesDashboardSection(
        textPrimary: const Color(0xFF1C1A18),
        mutedText: const Color(0xFF5C574F),
        tableSelectionKey: GlobalKey<TableSelectionWidgetState>(),
        onSelectionChanged: () {},
        onTableTap: (_) {},
        onContinueToMenu: () {},
        currentFloor: 1,
        onSwitchFloor: (_) {},
        onOpenReservations: () {},
        displaySettings: settings,
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

/// The tables tab sits to the right of the operational sidebar, so it never
/// receives the full window width. Both states matter: collapsed is the xs
/// default, expanded is what an operator gets after pinning the rail.
const _collapsedSidebar = 54.0;
const _expandedSidebar = 164.0;

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_home_layout');
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
    for (final (sidebarName, sidebarWidth) in <(String, double)>[
      ('collapsed sidebar', _collapsedSidebar),
      ('expanded sidebar', _expandedSidebar),
    ]) {
      testWidgets('tables tab lays out without overflow at $name, '
          '$sidebarName', (tester) async {
        tester.view
          ..devicePixelRatio = 1.0
          ..physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _harness(size, sidebarWidth, PosDisplaySettings.defaults),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the grid toggle is not on the operational screen', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    // The preference is set on the Floors & areas page; the tables tab only
    // renders the result, so no toggle should appear here.
    for (final grid in [true, false]) {
      await tester.pumpWidget(
        _harness(
          size,
          _collapsedSidebar,
          PosDisplaySettings.defaults.copyWith(floorPlanGrid: grid),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('ბადის დამალვა (გამჭვირვალე ფონი)'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the operations bar carries no search or booking buttons', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(size, _collapsedSidebar, PosDisplaySettings.defaults),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('New takeaway'), findsNothing);
    expect(find.text('New reservation'), findsNothing);
    expect(find.text('Takeaway'), findsNothing);
    expect(find.text('Reserve'), findsNothing);
  });

  testWidgets('the service rail is docked on the right at 1024x768', (
    tester,
  ) async {
    const size = Size(1024, 768);
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(size, _collapsedSidebar, PosDisplaySettings.defaults),
    );
    await tester.pumpAndSettle();

    // The rail's headings only exist in the docked layout; the compact
    // fallback shows a horizontal chip strip instead.
    expect(find.text('SERVICE RIGHT NOW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the floor tabs sit evenly between the header and the plan', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(size, _collapsedSidebar, PosDisplaySettings.defaults),
    );
    await tester.pumpAndSettle();

    final section = tester.getRect(find.byType(HomeTablesDashboardSection));
    final tabs = tester.getRect(find.byKey(floorSwitchKey));
    final panel = tester.getRect(find.byKey(planPanelKey));

    final gapAbove = tabs.top - section.top;
    final gapBelow = panel.top - tabs.bottom;

    expect(gapAbove, greaterThan(0));
    expect(gapBelow, greaterThan(0));
    // The mock puts 14 above and 12 below; anything beyond a couple of pixels
    // of difference reads as the tabs riding high.
    expect(
      (gapAbove - gapBelow).abs(),
      lessThanOrEqualTo(3),
      reason:
          'tabs are not optically centred: $gapAbove above, $gapBelow below',
    );
  });

  testWidgets('the floor tab label is centred inside its own box', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(size, _collapsedSidebar, PosDisplaySettings.defaults),
    );
    await tester.pumpAndSettle();

    final tabs = tester.getRect(find.byKey(floorSwitchKey));
    final label = tester.getRect(
      find
          .descendant(
            of: find.byKey(floorSwitchKey),
            matching: find.byType(Text),
          )
          .first,
    );

    expect(
      (label.center.dy - tabs.center.dy).abs(),
      lessThanOrEqualTo(1.5),
      reason: 'label centre ${label.center.dy} vs tab centre ${tabs.center.dy}',
    );
  });
}
