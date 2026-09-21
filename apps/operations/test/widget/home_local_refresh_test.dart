import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_tables_dashboard_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/database_service.dart';

void main() {
  late Directory tempDir;

  void registerAdapters() {
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(ReservationAdapter());
    }
  }

  Future<Order> seedOccupiedOrder() async {
    final order = Order(
      orderId: 1,
      tableNumbers: const ['1'],
      floor: 'first',
      items: [
        OrderItem(
          itemKey: 'coffee',
          itemName: 'Coffee',
          unitPrice: 10,
          quantity: 1,
          total: 10,
        ),
      ],
      totalAmount: 10,
      createdAt: DateTime(2026, 9, 4, 12),
      createdBy: 'Nino',
      status: 'served',
      includeServiceFee: false,
    );
    await DatabaseCore.orderBox!.put(order.orderId, order);

    final table = TableModel(tableNumber: '1', floor: 'first')
      ..reserve('Nino', order.orderId);
    await DatabaseCore.tableBox!.put('first-1', table);
    return order;
  }

  Future<Order> seedTakeawayOrder() async {
    final order = Order(
      orderId: 2,
      tableNumbers: const ['TA-2'],
      floor: 'takeaway',
      items: [
        OrderItem(
          itemKey: 'lobiani',
          itemName: 'Lobiani',
          unitPrice: 12,
          quantity: 1,
          total: 12,
        ),
      ],
      totalAmount: 12,
      createdAt: DateTime(2026, 9, 4, 13),
      createdBy: 'Nino',
      status: 'served',
      includeServiceFee: false,
      customerName: 'Guest',
      pickupTime: '13:30',
    );
    await DatabaseCore.orderBox!.put(order.orderId, order);
    return order;
  }

  String metricValue(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_home_local_refresh');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('hr_settings');
    DatabaseCore.salesBox = await Hive.openBox('hr_sales');
    DatabaseCore.auditLogBox = await Hive.openBox('hr_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('hr_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('hr_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('hr_res');
    DatabaseCore.closureJournalBox = await Hive.openBox('hr_journal');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-09-04T00:00:00.000',
    );
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 0.0);
    Order.serviceFeeRateResolver = () => 0;
  });

  tearDown(() async {
    SessionLock.disarm();
    Order.serviceFeeRateResolver = null;
    for (final name in const [
      'hr_settings',
      'hr_sales',
      'hr_audit',
      'hr_orders',
      'hr_tables',
      'hr_res',
      'hr_journal',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.reservationBox = null;
    DatabaseCore.closureJournalBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          user: User(username: 'Nino', pinCode: '0000', role: 'manager'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('close refreshes visible Home from the committed local event', (
    tester,
  ) async {
    final order = (await tester.runAsync(seedOccupiedOrder))!;
    await pumpHome(tester);

    expect(metricValue(tester, homeOccupiedCountKey), '1');
    expect(metricValue(tester, homeFreeCountKey), '0');

    final result = await tester.runAsync(
      () => CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 10),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 10},
        closedById: 'Nino',
        isFiscal: true,
      ),
    );
    await tester.pump();

    expect(result!.outcome, ClosureOutcome.closed);
    expect(metricValue(tester, homeOccupiedCountKey), '0');
    expect(metricValue(tester, homeFreeCountKey), '1');
    expect(DatabaseCore.tableBox!.values.single.activeOrderId, isNull);
    expect(DatabaseCore.orderBox!.values.single.status, 'closed');
    SessionLock.disarm();
  });

  testWidgets('cancel refreshes visible Home without switching tabs', (
    tester,
  ) async {
    final order = (await tester.runAsync(seedOccupiedOrder))!;
    await pumpHome(tester);

    expect(metricValue(tester, homeOccupiedCountKey), '1');

    await tester.runAsync(
      () => DatabaseService.updateOrderStatus(
        orderId: order.orderId,
        status: 'cancelled',
      ),
    );
    await tester.pump();

    expect(metricValue(tester, homeOccupiedCountKey), '0');
    expect(metricValue(tester, homeFreeCountKey), '1');
    expect(DatabaseCore.tableBox!.values.single.activeOrderId, isNull);
    expect(DatabaseCore.orderBox!.values.single.status, 'cancelled');
    SessionLock.disarm();
  });

  testWidgets('Takeaway close removes the visible Home count immediately', (
    tester,
  ) async {
    final order = (await tester.runAsync(seedTakeawayOrder))!;
    await pumpHome(tester);

    expect(find.byKey(homeTakeawayCountKey), findsOneWidget);
    expect(metricValue(tester, homeOccupiedCountKey), '0');

    final result = await tester.runAsync(
      () => CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 12),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 12},
        closedById: 'Nino',
        isFiscal: true,
      ),
    );
    await tester.pump();

    expect(result!.outcome, ClosureOutcome.closed);
    expect(find.byKey(homeTakeawayCountKey), findsNothing);
    expect(DatabaseCore.orderBox!.values.single.status, 'closed');
    expect(DatabaseCore.reservationBox!.values, isEmpty);
    SessionLock.disarm();
  });
}
