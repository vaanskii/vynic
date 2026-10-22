import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_actions_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/print_jobs.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/escpos_kitchen_renderer.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/sync/pos_live_refresh.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import '../support/pos02_fixture.dart';

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  setUpAll(() async {
    final font = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.view(font.buffer)))).load();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_kitchen_entry_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
  });
  tearDown(() async {
    SessionLock.disarm();
    await fixture.close();
    await root.delete(recursive: true);
  });
  Future<void> advance(WidgetTester tester) async {
    for (var n = 0; n < 12; n++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Future<void> drainToast(WidgetTester tester) async {
    for (var n = 0; n < 40; n++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
  }

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'order reprint keeps one snapshot through live refresh and repeated clicks',
    (tester) async {
      wide(tester);
      final original = DatabaseService.getOrder(41)!.clone();
      final expected = await tester.runAsync(
        () => EscposKitchenRenderer.generateBytes(
          items: ['2x Item'],
          tableNumber: OrderDetailCommonHelpers.kitchenTableLabel(original),
          orderNumber: '41',
          waiterName: original.createdBy,
          createdAt: original.createdAt,
          resolveOperatorDisplayName: (name, {required isEnglish}) =>
              name == 'manager' ? (isEnglish ? 'System' : 'სისტემა') : name,
        ),
      );
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: OrderDetailScreen(user: PosSession.user!, orderId: 41),
          ),
        ),
      );
      await advance(tester);
      final callback = tester
          .widget<OrderDetailActionRail>(find.byType(OrderDetailActionRail))
          .actionsBundle[OrderActionId.printKitchenCheck]!
          .onTap!;
      await tester.runAsync(() async {
        callback();
        callback();
      });
      await tester.pumpAndSettle();
      expect(find.text('გაშვება'), findsOneWidget);
      expect(find.byType(PosOnScreenTextField), findsNothing);
      await tester.runAsync(() async {
        final changed = DatabaseService.getOrder(41)!;
        changed.tableNumbers = ['99'];
        changed.items.single.quantity = 5;
        changed.items.single.itemName = 'Changed food';
        changed.createdBy = 'changed-staff';
        final key = DatabaseCore.orderBox!.keys.firstWhere(
          (key) => DatabaseCore.orderBox!.get(key)!.orderId == 41,
        );
        await DatabaseCore.orderBox!.put(key, changed);
        PosLiveRefresh.generation.value++;
      });
      await advance(tester);
      expect(
        tester
            .widget<OrderDetailActionRail>(find.byType(OrderDetailActionRail))
            .order
            .tableNumbers,
        ['99'],
      );
      await tester.runAsync(() => tester.tap(find.text('გაშვება')));
      await advance(tester);
      await tester.runAsync(() => fixture.dispatch());
      PrintQueue.stop();
      final copy = PrintJobRepository.all().single;
      expect(copy.copyOf, 'order/41');
      expect(base64Decode(copy.toMap()['payload'] as String), expected);
      expect(copy.audit.first['reason'], PrintReconciliation.kitchenCopyReason);
      expect(fixture.transmitted, hasLength(1));
      expect(
        ascii.decode(
          fixture.transmitted.single.take(60).toList(),
          allowInvalid: true,
        ),
        contains('REPRINT COPY'),
      );
      await drainToast(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'Home reservation kitchen reprint uses Run/Cancel under unset receipt policy',
    (tester) async {
      wide(tester);
      final order = DatabaseService.getOrder(42)!;
      final booking = Reservation(
        id: 'synthetic-kitchen-booking',
        customerName: 'Synthetic booking',
        customerPhone: '000',
        tableNumbers: [],
        reservationDate: DatabaseService.getCurrentDate(),
        reservationTime: '18:00',
        numberOfGuests: 2,
        createdAt: order.createdAt,
        createdBy: 'synthetic-operator',
        status: 'confirmed',
        isTakeAway: true,
        preOrderItems: order.items.map((v) => v.clone()).toList(),
      );
      await tester.runAsync(
        () => DatabaseCore.reservationBox!.put(booking.id, booking),
      );
      PrinterService.renderBytesOverride = () async =>
          ascii.encode('SYNTHETIC ONLY');
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(home: HomeScreen(user: PosSession.user!)),
        ),
      );
      await advance(tester);
      expect(find.byType(PrintJobsNotice), findsNothing);
      await tester.tap(find.text('რეზერვაცია').first);
      await advance(tester);
      final action = tester
          .widget<HomeReservationsSection>(find.byType(HomeReservationsSection))
          .onSendKitchenCheck!;
      await tester.runAsync(() async {
        unawaited(action(booking));
        unawaited(action(booking));
      });
      await tester.pumpAndSettle();
      expect(find.text('გაშვება'), findsOneWidget);
      expect(find.text('გაუქმება'), findsOneWidget);
      expect(find.byType(PosOnScreenTextField), findsNothing);
      await tester.tap(find.text('გაუქმება'));
      await advance(tester);
      expect(PrintJobRepository.all(), isEmpty);
      expect(fixture.transmitted, isEmpty);
      await tester.runAsync(() async {
        unawaited(action(booking));
        unawaited(action(booking));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('გაშვება')));
      await advance(tester);
      await tester.runAsync(() => fixture.dispatch());
      PrintQueue.stop();
      final copy = PrintJobRepository.all().single;
      expect(copy.copyOf, 'reservation/${booking.id}');
      expect(copy.audit.first['actorId'], 'synthetic-operator');
      expect(copy.audit.first['reason'], PrintReconciliation.kitchenCopyReason);
      expect(fixture.transmitted, hasLength(1));
      await drainToast(tester);
      expect(tester.takeException(), isNull);
      SessionLock.disarm();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
