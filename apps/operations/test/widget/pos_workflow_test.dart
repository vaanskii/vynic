import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_workflow_actions.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_page.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_take_away_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Pos03Fixture fixture;
  late Order order;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic_workflow_');
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'defaultLanguage': 'ka',
    });
    final items = [
      OrderItem(
        itemKey: 'one',
        itemName: 'იმერული ხაჭაპური',
        unitPrice: 16,
        quantity: 2,
        total: 32,
      ),
      OrderItem(
        itemKey: 'two',
        itemName: 'ცეზარის სალათი',
        unitPrice: 18,
        quantity: 1,
        total: 18,
      ),
      OrderItem(
        itemKey: 'three',
        itemName: 'ლიმონათი',
        unitPrice: 5,
        quantity: 2,
        total: 10,
      ),
    ];
    order = Order(
      orderId: 7,
      tableNumbers: const [],
      floor: 'takeaway',
      items: items,
      totalAmount: 60,
      createdAt: DateTime(2026, 10, 15, 18),
      createdBy: 'synthetic',
      status: 'confirmed',
      customerName: 'ნინო საცდელი',
      customerPhone: '555000000',
      pickupTime: '18:30',
    );
    await DatabaseCore.orderBox!.put(7, order);
    await DatabaseCore.quickOrderBox!.put(
      'sample',
      QuickOrderDraft(
        id: 'sample',
        items: items,
        subtotal: 60,
        serviceFeeAmount: 0,
        total: 60,
        includeServiceFee: false,
        serviceFeeRate: 0,
        createdAt: order.createdAt,
        createdBy: 'synthetic',
        customerName: order.customerName,
        customerPhone: order.customerPhone,
      ),
    );
    PosInputSettings.active = true;
    PosInputSettings.enabled.value = false;
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() async {
    PosInputSettings.active = false;
    await fixture.close();
    await directory.delete(recursive: true);
  });
  Widget screen(String kind) => kind == 'count'
      ? HomeCalculatorPage(
          user: pos03User,
          primaryColor: VynicFloorTokens.accentStrong,
          secondaryColor: VynicFloorTokens.accentSoft,
          textPrimary: VynicFloorTokens.text,
          mutedText: VynicFloorTokens.textMuted,
        )
      : HomeTakeAwaySection(
          user: pos03User,
          tickets: [TakeawayTicket(order: order)],
          onRefreshRequested: () async {},
          primaryColor: VynicFloorTokens.accentStrong,
          secondaryColor: VynicFloorTokens.accentSoft,
          textPrimary: VynicFloorTokens.text,
          mutedText: VynicFloorTokens.textMuted,
        );
  Future<GlobalKey> pump(
    WidgetTester tester,
    String kind, {
    Size size = const Size(1024, 768),
    bool scaled = true,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    Widget page = Scaffold(
      backgroundColor: VynicFloorTokens.page,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 100, 16, 0),
        child: screen(kind),
      ),
    );
    if (scaled) page = PosScaledSurface(scale: 1, child: page);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: PosTheme.light,
          builder: (_, child) =>
              PosLocaleHost(child: PosInputScope(child: child!)),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return boundary;
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const output = String.fromEnvironment('POS_WORKFLOW_SCREENSHOTS');
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final kind in ['count', 'takeaway']) {
    testWidgets('$kind isolated 1024 workflow visual', (tester) async {
      final key = await pump(tester, kind);
      await capture(tester, key, kind);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Count reservation is one tap; repeated dismiss keeps estimate and money',
    (tester) async {
      await pump(tester, 'count');
      expect(find.text('მართვა'), findsNothing);
      for (var attempt = 0; attempt < 3; attempt++) {
        final reserve = tester
            .widget<PosWorkflowButton>(
              find.widgetWithText(PosWorkflowButton, 'რეზერვაცია'),
            )
            .onPressed!;
        reserve();
        reserve();
        await tester.pumpAndSettle();
        expect(find.byType(ReservationCreationSheet), findsOneWidget);
        await tester.tap(find.byTooltip('დახურვა'));
        await tester.pumpAndSettle();
        expect(find.byType(ReservationCreationSheet), findsNothing);
        expect(DatabaseCore.quickOrderBox!.values.length, 1);
        expect(DatabaseCore.reservationBox!.values, isEmpty);
        expect(DatabaseCore.salesBox!.values, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Count edit is direct and delete dismissal preserves the estimate',
    (tester) async {
      await pump(tester, 'count');
      await tester.tap(find.text('მენიუს შეცვლა'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsOneWidget);
      expect(
        tester
            .widget<MenuScreen>(find.byType(MenuScreen))
            .initialQuickOrderDraftId,
        'sample',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsNothing);
      await tester.tap(find.byTooltip('შეფასების წაშლა'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(DatabaseCore.quickOrderBox!.values.length, 1);
      expect(DatabaseCore.quickOrderBox!.values.single.total, 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Takeaway payment and cancel are one tap and dismissal never changes the order',
    (tester) async {
      await pump(tester, 'takeaway');
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(find.text('გადახდა'));
        await tester.pumpAndSettle();
        expect(find.text('ნაღდი ფული'), findsOneWidget);
        await tester.tap(find.text('უკან დაბრუნება'));
        await tester.pumpAndSettle();
        expect(DatabaseCore.orderBox!.get(7)!.status, 'confirmed');
        await tester.tap(find.widgetWithText(TextButton, 'შეკვეთის გაუქმება'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('უკან დაბრუნება'));
        await tester.pumpAndSettle();
        expect(DatabaseCore.orderBox!.get(7)!.status, 'confirmed');
        expect(DatabaseCore.salesBox!.values, isEmpty);
        expect(DatabaseCore.orderBox!.get(7)!.totalAmount, 60);
      }
      expect(find.text('სრული დეტალები'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Takeaway editing opens Menu directly and back restores the queue safely',
    (tester) async {
      await pump(tester, 'takeaway');
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('მენიუს შეცვლა'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuScreen), findsOneWidget);
        expect(
          tester.widget<MenuScreen>(find.byType(MenuScreen)).existingOrderId,
          7,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MenuScreen), findsNothing);
        expect(find.text('გადახდა'), findsOneWidget);
        expect(DatabaseCore.orderBox!.get(7)!.status, 'confirmed');
        expect(DatabaseCore.orderBox!.get(7)!.totalAmount, 60);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct editor retains the same owner and Admin access policy', (
    tester,
  ) async {
    await tester.runAsync(
      () => DatabaseService.setTableCloseRestrictedToOwner(true),
    );
    final other = User(username: 'other', pinCode: '111111', role: 'waiter');
    final manager = User(username: 'other', pinCode: '111111', role: 'manager');
    final admin = User(username: 'other', pinCode: '111111', role: 'admin');
    expect(OrderDetailCommonHelpers.canModifyOrder(pos03User, order), isTrue);
    expect(OrderDetailCommonHelpers.canModifyOrder(other, order), isFalse);
    expect(OrderDetailCommonHelpers.canModifyOrder(manager, order), isTrue);
    expect(OrderDetailCommonHelpers.canModifyOrder(admin, order), isTrue);
  });

  for (final kind in ['count', 'takeaway']) {
    for (final width in [640.0, 800.0, 1024.0]) {
      testWidgets(
        '$kind $width narrow workflow retains reachable actions without overflow',
        (tester) async {
          await pump(tester, kind, size: Size(width, 768), scaled: false);
          if (find.byType(PosPaneSwitch).evaluate().isNotEmpty) {
            await tester.tap(
              find.text(kind == 'count' ? 'შეფასება' : 'შეკვეთა'),
            );
            await tester.pumpAndSettle();
          }
          expect(
            find.text(kind == 'count' ? 'რეზერვაცია' : 'გადახდა').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('მენიუს შეცვლა').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('$kind 1024 painted primary control remains touch sized', (
      tester,
    ) async {
      await pump(tester, kind);
      final button = find.widgetWithText(
        PosWorkflowButton,
        kind == 'count' ? 'რეზერვაცია' : 'გადახდა',
      );
      final box = tester.renderObject<RenderBox>(button);
      final height =
          box.localToGlobal(Offset(0, box.size.height)).dy -
          box.localToGlobal(Offset.zero).dy;
      expect(height, greaterThanOrEqualTo(47.7));
      expect(tester.takeException(), isNull);
    });
  }
}
