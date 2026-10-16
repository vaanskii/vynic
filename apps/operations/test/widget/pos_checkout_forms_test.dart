import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/estimate_customer_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/staff_lock_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_take_away_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_reservations_section.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_checkout_forms_');
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
    PosInputSettings.active = false;
    await fixture.close();
    await dir.delete(recursive: true);
  });
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
        builder: (_, child) => PosLocaleHost(child: child!),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.labelText == label || w.decoration?.hintText == label),
  );
  const future = '2026-10-17';
  ReservationCreationSheet sheet() => ReservationCreationSheet(
    requestId: 'synthetic-form',
    initialName: 'ნინო საცდელი',
    initialPhone: '555000000',
    initialDate: DateTime.parse(future),
    initialTime: const TimeOfDay(hour: 18, minute: 0),
    initialGuests: 2,
  );
  Future<void> openSheet(
    WidgetTester tester,
    void Function(Map<String, dynamic>?) onResult,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => onResult(
            await showDialog<Map<String, dynamic>>(
              context: context,
              barrierDismissible: false,
              builder: (_) => sheet(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact reservation submits guest controls, future hold and cent advance once',
    (tester) async {
      Map<String, dynamic>? result;
      var returns = 0;
      await openSheet(tester, (value) {
        result = value;
        returns++;
      });
      final size = tester.getSize(
        find.byKey(const Key('reservation-compact-form')),
      );
      expect(size.width, lessThanOrEqualTo(560));
      expect(size.height, lessThanOrEqualTo(660));
      await tester.ensureVisible(
        find.byKey(const Key('reservation-guests-plus')),
      );
      await tester.tap(find.byKey(const Key('reservation-guests-plus')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reservation-guests-minus')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reservation-guests-plus')));
      await tester.pump();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(field('მიღებული ავანსი (₾)'));
      await tester.enterText(field('მიღებული ავანსი (₾)'), '6.25');
      await tester.pump();
      await tester.tap(find.text('რეზერვაციის შექმნა'));
      // Invoke the retained callback again before the route has disposed.
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'რეზერვაციის შექმნა'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(returns, 1);
      expect(result, containsPair('id', 'synthetic-form'));
      expect(result, containsPair('status', 'hold'));
      expect(result, containsPair('advanceAmount', 6.25));
      expect(result, containsPair('guests', 3));
      expect(
        DatabaseCore.reservationBox!.values,
        isEmpty,
      ); // Form has no money side effect.
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing only advance or hold requires explicit discard and keeps the input on continue',
    (tester) async {
      await openSheet(tester, (_) {});
      await tester.ensureVisible(field('მიღებული ავანსი (₾)'));
      await tester.enterText(field('მიღებული ავანსი (₾)'), '6.25');
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(find.text('დახურვის დადასტურება'), findsOneWidget);
      await tester.tap(find.text('გაგრძელება'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('მიღებული ავანსი (₾)')).controller!.text,
        '6.25',
      );
      await tester.enterText(field('მიღებული ავანსი (₾)'), '0');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(find.text('დახურვის დადასტურება'), findsOneWidget);
      await tester.tap(find.text('დახურვა'));
      await tester.pumpAndSettle();
      expect(DatabaseCore.salesBox!.values, isEmpty);
    },
  );
  testWidgets(
    'estimate optional contacts return trimmed values; cancel has no persistence',
    (tester) async {
      EstimateCustomerDetails? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await EstimateCustomerDialog.show(context);
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(
              find.byWidgetPredicate(
                (w) => w is ConstrainedBox && w.constraints.maxWidth == 460,
              ),
            )
            .width,
        lessThanOrEqualTo(460),
      );
      await tester.enterText(field('სახელი და გვარი'), '  ნინო საცდელი  ');
      await tester.enterText(field('ტელეფონი'), '555000000');
      await tester.tap(find.text('შენახვა'));
      await tester.pumpAndSettle();
      expect(result!.name, 'ნინო საცდელი');
      expect(result!.phone, '555000000');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(field('სახელი და გვარი'), 'გაუქმებული');
      await tester.tap(find.text('უკან'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(DatabaseCore.quickOrderBox!.values, isEmpty);
    },
  );
  QuickOrderDraft draft(String id, String name, String phone, double amount) =>
      QuickOrderDraft(
        id: id,
        items: [
          OrderItem(
            itemKey: 'sample',
            itemName: 'კერძი',
            unitPrice: amount,
            quantity: 1,
            total: amount,
          ),
        ],
        subtotal: amount,
        serviceFeeAmount: 0,
        total: amount,
        includeServiceFee: false,
        serviceFeeRate: 0,
        createdAt: DateTime(2026, 10, 15),
        createdBy: 'synthetic',
        customerName: name,
        customerPhone: phone,
      );
  Widget estimates(List<QuickOrderDraft> drafts, {bool manager = false}) =>
      HomeCalculatorSection(
        quickOrderDrafts: drafts,
        onStartQuickOrder: () {},
        onToggleServiceFee: (_) {},
        onOpenServiceFeeConfig: (_) {},
        onContinueDraft: (_) {},
        onPrintDraft: (_) {},
        onItemQuantityChanged: (_, __, ___) {},
        serviceFeeAvailable: false,
        canManageDrafts: true,
        canDeleteDrafts: manager,
        onConfirmDraft: (_) {},
        onRenameDraft: (_) {},
        onPreviewDraft: (_) {},
        onDeleteDraft: (_) {},
        onClearAllDrafts: () {},
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        textPrimary: Colors.black,
        mutedText: Colors.grey,
      );
  testWidgets(
    'estimate browser filters actual surname phone amount and hides manager deletion',
    (tester) async {
      final rows = [
        draft('one', 'ნინო საცდელი', '555000001', 21.5),
        draft('two', 'გიორგი მაგალითი', '555000002', 33),
      ];
      await pump(tester, estimates(rows));
      expect(find.byTooltip('ყველას წაშლა'), findsNothing);
      for (final query in ['საცდელი', '555 000 001', '21,50']) {
        await tester.enterText(field('ძებნა'), query);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field('ძებნა')).controller!.text,
          query,
        );
        expect(find.text('ნინო საცდელი').hitTestable(), findsWidgets);
        expect(
          find.text('გიორგი მაგალითი').hitTestable(),
          findsNothing,
          reason: query,
        );
      }
      await tester.enterText(field('ძებნა'), 'არ არის 555');
      await tester.pump();
      expect(find.text('ძებნის შედეგი ვერ მოიძებნა'), findsOneWidget);
      await pump(tester, estimates(rows, manager: true));
      expect(find.byTooltip('ყველას წაშლა'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'takeaway browser shows saved full names and filters actual contacts and amounts',
    (tester) async {
      final tickets = [
        for (final row in [
          draft('one', 'ნინო საცდელი', '555000001', 21.5),
          draft('two', 'გიორგი მაგალითი', '555000002', 33),
        ])
          TakeawayTicket(
            order: Order(
              orderId: row.id == 'one' ? 1 : 2,
              tableNumbers: const [],
              floor: 'takeaway',
              items: row.items,
              totalAmount: row.total,
              createdAt: row.createdAt,
              createdBy: 'synthetic',
              status: 'confirmed',
              customerName: row.customerName!,
              customerPhone: row.customerPhone!,
            ),
          ),
      ];
      await pump(
        tester,
        PosScaledSurface(
          scale: 1,
          child: HomeTakeAwaySection(
            user: pos03User,
            tickets: tickets,
            onRefreshRequested: () async {},
            primaryColor: Colors.black,
            secondaryColor: Colors.grey,
            textPrimary: Colors.black,
            mutedText: Colors.grey,
          ),
        ),
      );
      for (final query in ['საცდელი', '555 000 001', '21,50']) {
        await tester.enterText(field('ძებნა'), query);
        await tester.pump();
        expect(find.text('ნინო საცდელი'), findsWidgets);
        expect(find.text('გიორგი მაგალითი'), findsNothing);
      }
      expect(DatabaseCore.reservationBox!.values, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'holds are separately visible in Management Center and cannot seat or send kitchen work from Home',
    (tester) async {
      final hold = Reservation(
        id: 'synthetic-hold',
        customerName: 'ნინო საცდელი',
        customerPhone: '555000000',
        tableNumbers: const [1],
        reservationDate: DateTime(2026, 10, 17),
        reservationTime: '18:00',
        numberOfGuests: 2,
        createdAt: DateTime(2026, 10, 15),
        createdBy: 'synthetic',
        status: 'hold',
        preOrderItems: [
          OrderItem(
            itemKey: 'sample',
            itemName: 'კერძი',
            unitPrice: 10,
            quantity: 1,
            total: 10,
          ),
        ],
        advanceAmount: 6,
        advanceCollectedOn: '2026-10-15',
        advanceReceiptId: 'synthetic-receipt',
      );
      await tester.runAsync(() => DatabaseCore.reservationBox!.add(hold));
      await pump(
        tester,
        PosScaledSurface(
          scale: 1,
          child: AdminReservationsSection(user: pos03User),
        ),
      );
      await tester.tap(find.text('ფილტრი'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'hold',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ნინო საცდელი'), findsWidgets);
      expect(find.text('დროებითი დაკავება'), findsWidgets);
      await tester.tap(find.byTooltip('მოქმედებები'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'delete',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ავანსიანი ჯავშანი ინახება'), findsOneWidget);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      var confirms = 0;
      var seats = 0;
      var kitchen = 0;
      await pump(
        tester,
        PosScaledSurface(
          scale: 1,
          child: HomeReservationsSection(
            user: pos03User,
            reservations: [hold],
            onRefreshRequested: () async {},
            primaryColor: Colors.black,
            secondaryColor: Colors.grey,
            textPrimary: Colors.black,
            mutedText: Colors.grey,
            canAssignTable: true,
            onAssignTable: (_) async {
              seats++;
            },
            onConfirmHold: (_) async {
              confirms++;
            },
            onSendKitchenCheck: (_) async {
              kitchen++;
            },
          ),
        ),
      );
      expect(find.text('სუფრაზე გადაყვანა').hitTestable(), findsNothing);
      expect(find.text('სამზარეულოში გაგზავნა').hitTestable(), findsNothing);
      expect(find.text('მიღებული ავანსი: 6.00 ₾'), findsOneWidget);
      await tester.tap(find.text('ჯავშნის დადასტურება'));
      await tester.pump();
      expect(confirms, 1);
      expect(seats, 0);
      expect(kitchen, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'PIN pad stays compact and system back cannot bypass authentication',
    (tester) async {
      await tester.runAsync(
        () => DatabaseCore.userBox!.put('synthetic', pos03User),
      );
      final nav = GlobalKey<NavigatorState>();
      User? unlocked;
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                unlocked = await Navigator.of(context).push(staffLockRoute());
              },
              child: const Text('lock'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('lock'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('staff-compact-pin-pad'))).width,
        320,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('staff-compact-pin-pad')), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('1'));
        await tester.pump();
      }
      expect(find.text('არასწორი PIN კოდი'), findsOneWidget);
      expect(unlocked, isNull);
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('0'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(unlocked!.username, 'synthetic');
      expect(find.byKey(const Key('staff-compact-pin-pad')), findsNothing);
      SessionLock.disarm();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'fully prepaid payment requires confirmation; cancel retains it and excess is refused',
    (tester) async {
      TablePaymentSelection? selection;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selection = await TablePaymentService(
                context: context,
                total: 0,
                grossTotal: 10,
                advanceApplied: 10,
              ).collect();
            },
            child: const Text('pay'),
          ),
        ),
      );
      await tester.tap(find.text('pay'));
      await tester.pumpAndSettle();
      expect(find.text('ანგარიში სრულად დაფარულია'), findsOneWidget);
      await tester.tap(find.text('უკან'));
      await tester.pumpAndSettle();
      expect(selection, isNull);
      await tester.tap(find.text('pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ანგარიშის დახურვა'));
      await tester.pumpAndSettle();
      expect(selection!.total, 0);
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selection = await TablePaymentService(
                context: context,
                total: 0,
                grossTotal: 10,
                advanceApplied: 12,
              ).collect();
            },
            child: const Text('excess'),
          ),
        ),
      );
      await tester.tap(find.text('excess'));
      await tester.pumpAndSettle();
      expect(find.text('ანგარიში სრულად დაფარულია'), findsNothing);
      expect(DatabaseCore.salesBox!.values, isEmpty);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}
