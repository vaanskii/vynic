import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'dart:convert';
import 'package:vynic/core/models/table_layout.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_tables_dashboard_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_home_ui_');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'defaultLanguage': 'ka',
    });
    PosInputSettings.active = true;
    PosInputSettings.enabled.value = false;
  });
  tearDown(() async {
    SessionLock.disarm();
    PosSession.clear();
    await fixture.close();
    await dir.delete(recursive: true);
    PosInputSettings.active = false;
  });
  Future<void> seed() async {
    final order = Order(
      orderId: 1,
      tableNumbers: ['1'],
      floor: 'first',
      items: const [],
      totalAmount: 48,
      createdAt: DateTime(2026, 10, 15, 12),
      createdBy: 'საცდელი ოფიციანტი',
      status: 'confirmed',
    );
    await DatabaseCore.orderBox!.put(1, order);
    final layout = RestaurantTableLayouts.current;
    await DatabaseCore.settingsBox!.put(
      'activeTableLayoutJson',
      jsonEncode(layout.toJson()),
    );
    for (final definition in layout.tables) {
      final table = TableModel(
        tableNumber: definition.legacyTableNumber,
        floor: definition.legacyFloor,
      );
      if (definition.legacyFloor == 'first' &&
          definition.legacyTableNumber == '1')
        table.reserve('საცდელი ოფიციანტი', 1);
      await DatabaseCore.tableBox!.put(definition.id, table);
    }
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (_, child) => PosLocaleHost(
          child: RepaintBoundary(
            key: const Key('home-ui-capture'),
            child: PosScaledSurface(scale: 1, child: child!),
          ),
        ),
        home: HomeScreen(
          user: User(
            username: 'საცდელი მენეჯერი',
            pinCode: '0000',
            role: 'manager',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final destination = Platform.environment['POS_UI_PROOF_DIR'];
    if (destination == null) return;
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/logo/vynic-logo.png'),
        tester.element(find.byType(HomeScreen)),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('home-ui-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(destination).create(recursive: true);
      await File(
        '$destination/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('connected workflows retain actual Home navigation at 1024', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed();
      final items = [
        OrderItem(
          itemKey: 'sample',
          itemName: 'იმერული ხაჭაპური',
          quantity: 2,
          unitPrice: 16,
          total: 32,
        ),
        OrderItem(
          itemKey: 'sample-2',
          itemName: 'ჩაქაფული ტარხუნით და თეთრი ღვინით',
          quantity: 1,
          unitPrice: 26,
          total: 26,
        ),
      ];
      await DatabaseCore.quickOrderBox!.put(
        'sample',
        QuickOrderDraft(
          id: 'sample',
          items: items,
          subtotal: 58,
          serviceFeeAmount: 0,
          total: 58,
          includeServiceFee: false,
          serviceFeeRate: 0,
          createdAt: DateTime(2026, 10, 15, 18),
          createdBy: 'საცდელი',
          customerName: 'ნინო საცდელი',
          customerPhone: '555000000',
        ),
      );
      await DatabaseCore.orderBox!.put(
        7,
        Order(
          orderId: 7,
          tableNumbers: const [],
          floor: 'takeaway',
          items: items,
          totalAmount: 58,
          createdAt: DateTime(2026, 10, 15, 18),
          createdBy: 'საცდელი',
          status: 'confirmed',
          customerName: 'ნინო საცდელი',
          customerPhone: '555000000',
          pickupTime: '18:30',
        ),
      );
      await DatabaseCore.reservationBox!.put(
        'sample',
        Reservation(
          id: 'sample',
          customerName: 'ნინო საცდელი',
          customerPhone: '555000000',
          tableNumbers: const [],
          reservationDate: DateTime(2026, 10, 15),
          reservationTime: '20:30',
          numberOfGuests: 6,
          createdAt: DateTime(2026, 10, 15, 18),
          createdBy: 'საცდელი',
          status: 'confirmed',
          preOrderItems: items,
        ),
      );
    });
    await pump(tester, const Size(1024, 768));
    for (final entry in [
      ('დათვლა', 'count'),
      ('გატანები', 'takeaway'),
      ('რეზერვაცია', 'reservations'),
      ('X', 'report'),
    ]) {
      await tester.tap(find.text(entry.$1).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'home-${entry.$2}-1024x768');
    }
    await tester.tap(find.text('მაგიდები').last);
    await tester.pumpAndSettle();
    expect(find.byType(HomeTablesDashboardSection), findsOneWidget);
    SessionLock.disarm();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final size in [const Size(1024, 768), const Size(1440, 900)]) {
    testWidgets(
      'restrained full-width table view ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await tester.runAsync(seed);
        await pump(tester, size);
        final section = tester.widget<HomeTablesDashboardSection>(
          find.byType(HomeTablesDashboardSection),
        );
        expect(find.text('SERVICE RIGHT NOW'), findsNothing);
        expect(find.text('ჯავშნები'), findsNothing);
        expect(find.text('სწრაფი გაყიდვა').hitTestable(), findsNothing);
        expect(find.text('გაერთიანება').hitTestable(), findsNothing);
        final panel = tester.getSize(find.byKey(planPanelKey));
        final viewport = tester.getSize(
          find.byKey(const Key('home-floor-plan-viewport')),
        );
        expect(viewport.width, greaterThan(panel.width - 24));
        expect(section.tableSelectionKey.currentState!.tableIds.length, 9);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'home-collapsed-${size.width.toInt()}x${size.height.toInt()}',
        );
        final closedWidth = panel.width;
        await tester.tap(find.byKey(const Key('home-table-actions-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('სწრაფი გაყიდვა').hitTestable(), findsOneWidget);
        final openedPanel = tester.getRect(find.byKey(planPanelKey));
        final drawer = tester.getRect(
          find.byKey(const Key('home-table-actions-column')),
        );
        expect(openedPanel.right, lessThan(drawer.left));
        expect(openedPanel.width, lessThan(closedWidth));
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'home-expanded-${size.width.toInt()}x${size.height.toInt()}',
        );
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(const Key('home-table-actions-toggle')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(tester.getRect(find.byKey(planPanelKey)), openedPanel);
        await tester.tap(find.byKey(const Key('home-table-actions-toggle')));
        await tester.tap(find.byKey(const Key('home-table-actions-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(planPanelKey)), openedPanel);
        expect(section.tableSelectionKey.currentState!.tableIds.length, 9);
        await tester.tap(find.byKey(const Key('home-table-multi-select')));
        await tester.pump();
        expect(
          section.tableSelectionKey.currentState!.multiSelectionMode,
          isTrue,
        );
        SessionLock.disarm();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'empty stored floor is explicit, never fabricated tables or a narrow blank grid',
    (tester) async {
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put(
          'activeTableLayoutJson',
          jsonEncode(RestaurantTableLayouts.emptyVenue.toJson()),
        ),
      );
      await pump(tester, const Size(1024, 768));
      expect(find.text('ამ სართულზე მაგიდები არ არის'), findsOneWidget);
      expect(DatabaseCore.tableBox!.values, isEmpty);
      expect(tester.takeException(), isNull);
      await capture(tester, 'home-empty-1024x768');
      SessionLock.disarm();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
