import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// Phase 1 of the audit-integrity work: every genuine cancellation converges
/// on one routine that leaves the Order, a typed `CANCEL_TABLE` event, a
/// locked report and a non-revenue cancelled Sale record — and repeating the
/// same intent changes nothing.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-04';

  void registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MenuCategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(MenuVariantDBAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(ReservationAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(SaleRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
  }

  Future<Order> seedOrder({
    required int orderId,
    double gross = 100,
    String floor = 'first',
    bool package = false,
    String status = 'confirmed',
  }) async {
    final table = floor == 'takeaway' ? 'TA-$orderId' : '$orderId';
    final order = Order(
      orderId: orderId,
      tableNumbers: [table],
      floor: floor,
      items: package
          ? const []
          : [
              OrderItem(
                itemKey: 'item-$orderId',
                itemName: 'Item $orderId',
                unitPrice: gross / 2,
                quantity: 2,
                total: gross,
              ),
            ],
      totalAmount: gross,
      createdAt: DateTime.parse('${businessDate}T12:00:00'),
      createdBy: 'waiter',
      status: status,
    );
    if (package) {
      order.packageId = 'package-$orderId';
      order.packageName = 'Package $orderId';
      order.packageGuestCount = 10;
      order.packageUnitPrice = gross / 10;
      order.packagePrice = gross;
      order.packageItems = [
        OrderItem(
          itemKey: 'package-item-$orderId',
          itemName: 'Package item $orderId',
          unitPrice: 5,
          quantity: 2,
          total: 10,
        ),
      ];
    }
    order.recalculateTotal(serviceFeeRate: 0);
    await DatabaseCore.orderBox!.put(orderId, order);
    if (floor != 'takeaway') {
      final tableModel = TableModel(tableNumber: table, floor: floor)
        ..reserve('waiter', orderId);
      await DatabaseCore.tableBox!.put('$floor-$table', tableModel);
    }
    await AuditRepository.ensureAuditReport(
      orderId: orderId,
      orderSnapshot: order,
    );
    return order;
  }

  Future<Reservation> seedLinkedBooking(Order order) async {
    final reservation = Reservation(
      id: 'reservation-${order.orderId}',
      customerName: 'Guest',
      customerPhone: '+995555000000',
      tableNumbers: [order.orderId],
      tableRefs: ['first/${order.orderId}'],
      reservationDate: DateTime.parse('${businessDate}T00:00:00'),
      reservationTime: '12:00',
      numberOfGuests: 2,
      createdAt: DateTime.parse('${businessDate}T10:00:00'),
      createdBy: 'manager',
      status: ReservationStatus.inProgress.storageValue,
      linkedOrderId: order.orderId,
    );
    await DatabaseCore.reservationBox!.add(reservation);
    final table = DatabaseCore.tableBox!.values.single;
    table.reservationId = reservation.id;
    await table.save();
    return reservation;
  }

  List<Map<dynamic, dynamic>> salesFor(int orderId) => DatabaseCore
      .salesBox!
      .values
      .whereType<Map>()
      .where((sale) => sale['orderId'] == orderId)
      .toList();

  double revenueForDay() =>
      SalesRepository.getSalesForDate(businessDate)
          .where(SalesRepository.countsAsRevenue)
          .fold<double>(0, (sum, sale) => sum + SalesRepository.grossOf(sale));

  /// The full durable cancellation contract, asserted the same way for every
  /// path so the paths cannot drift apart again.
  void expectCancelled(
    int orderId, {
    required String source,
    required bool physicalTable,
    String? approvedBy,
  }) {
    final order = DatabaseCore.orderBox!.get(orderId)!;
    expect(order.statusEnum, OrderStatus.cancelled);

    if (physicalTable) {
      final table = DatabaseCore.tableBox!.values.single;
      expect(table.activeOrderId, isNull);
      expect(table.isReserved, isFalse);
    }

    final report = AuditRepository.getAuditReport(orderId)!;
    expect(report.status, AuditReportStatus.cancelled);
    expect(report.locked, isTrue);
    final cancels = report.events
        .where((event) => event.type == AuditEventType.cancelTable)
        .toList();
    expect(cancels, hasLength(1));
    expect(
      report.events.where((event) => event.type == AuditEventType.close),
      isEmpty,
    );
    final details = cancels.single.details!;
    expect(details['orderId'], orderId);
    expect(details[AuditSource.detailsKey], source);
    expect(details['actorId'], isNotEmpty);
    expect(details['businessDate'], businessDate);
    expect(details['floor'], order.floor);
    expect(details['tableRefs'], order.tableNumbers.map((t) => '${order.floor}/$t'));
    if (approvedBy != null) expect(details['approvedBy'], approvedBy);
    expect(details.containsKey('pin'), isFalse);
    expect(details.containsKey('pinCode'), isFalse);

    final sales = salesFor(orderId);
    expect(sales, hasLength(1));
    final sale = sales.single;
    expect(sale['isFiscal'], isFalse);
    expect(sale['isCancelled'], isTrue);
    expect(sale['paymentMethod'], 'cancelled');
    expect((sale['finalTransaction'] as Map)['type'], 'cancelled_order');
    expect(sale['collectedNow'], 0.0);
    expect(SalesRepository.countsAsRevenue(sale), isFalse);
    expect(revenueForDay(), 0.0);
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_cancel_order');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('co_settings');
    DatabaseCore.salesBox = await Hive.openBox('co_sales');
    DatabaseCore.auditLogBox = await Hive.openBox('co_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('co_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('co_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('co_res');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '${businessDate}T00:00:00.000',
    );
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 0.0);
    Order.serviceFeeRateResolver = () => 0.0;
  });

  tearDown(() async {
    Order.serviceFeeRateResolver = null;
    for (final name in const [
      'co_settings',
      'co_sales',
      'co_audit',
      'co_orders',
      'co_tables',
      'co_res',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('POS Walk-In cancel leaves the full durable trail', () async {
    await seedOrder(orderId: 101);

    final outcome = await CancelOrderTransaction.run(
      orderId: 101,
      actorId: 'waiter',
      actorName: 'waiter',
      source: AuditSource.pos,
      reason: 'Guest left',
      approvedBy: 'admin',
    );

    expect(outcome, CancelOrderOutcome.cancelled);
    expectCancelled(101, source: 'POS', physicalTable: true, approvedBy: 'admin');
    final report = AuditRepository.getAuditReport(101)!;
    expect(report.closedById, 'admin');
    final event = report.events.single;
    expect(event.waiterId, 'waiter');
    expect(event.previousQty, 2);
    expect(event.newQty, 0);
    expect(event.note, contains('Guest left'));
    expect(event.note, contains('Approved by admin'));
    expect(event.details!['orderKind'], 'WALK_IN');
    expect(event.details!['reason'], 'Guest left');
  });

  test('Takeaway cancel has the same trail and no table dependency', () async {
    await seedOrder(orderId: 102, floor: 'takeaway');
    expect(DatabaseCore.tableBox!.values, isEmpty);

    final outcome = await CancelOrderTransaction.run(
      orderId: 102,
      actorId: 'manager',
      source: AuditSource.pos,
      reason: 'Takeaway cancelled from the home panel',
      approvedBy: 'manager',
    );

    expect(outcome, CancelOrderOutcome.cancelled);
    expectCancelled(102, source: 'POS', physicalTable: false);
    expect(DatabaseCore.tableBox!.values, isEmpty);
    expect(
      AuditRepository.getAuditReport(102)!.events.single.details!['orderKind'],
      'TAKEAWAY',
    );
  });

  test('Manager ORDER_STATUS_UPDATE cancelled uses the shared routine', () async {
    await seedOrder(orderId: 103);

    final result = await PosCommandApplier.updateOrderStatus(<String, dynamic>{
      'posOrderId': 103,
      'status': 'cancelled',
      'updatedBy': 'Nino',
    });

    expect(result.ok, isTrue);
    expectCancelled(103, source: 'MANAGER', physicalTable: true);
    expect(AuditRepository.getAuditReport(103)!.events.single.waiterId, 'Nino');
  });

  test('Manager ORDER_CANCEL cancels instead of erasing', () async {
    await seedOrder(orderId: 104);
    await AuditRepository.appendOrderAuditEvents(
      orderId: 104,
      events: [
        AuditEvent(
          type: AuditEventType.addItem,
          itemName: 'Item 104',
          previousQty: 0,
          newQty: 2,
          waiterId: 'waiter',
          waiterName: 'waiter',
          timestamp: DateTime.parse('${businessDate}T12:05:00'),
        ),
      ],
    );

    final result = await PosCommandApplier.cancelOrder(<String, dynamic>{
      'posOrderId': 104,
    }, treatMissingAsDone: true);

    expect(result.ok, isTrue);
    expect(DatabaseCore.orderBox!.get(104), isNotNull);
    expectCancelled(104, source: 'MANAGER', physicalTable: true);
    final report = AuditRepository.getAuditReport(104)!;
    // The earlier history is still there, ahead of the cancellation.
    expect(report.events.first.type, AuditEventType.addItem);
    expect(report.events.last.type, AuditEventType.cancelTable);
  });

  test('Package cancellation keeps package data intact', () async {
    await seedOrder(orderId: 105, package: true);

    final outcome = await CancelOrderTransaction.run(
      orderId: 105,
      actorId: 'waiter',
      source: AuditSource.pos,
    );

    expect(outcome, CancelOrderOutcome.cancelled);
    expectCancelled(105, source: 'POS', physicalTable: true);
    final order = DatabaseCore.orderBox!.get(105)!;
    expect(order.packageId, 'package-105');
    expect(order.packageName, 'Package 105');
    expect(order.packageGuestCount, 10);
    expect(order.packageItems, hasLength(1));
    final sale = salesFor(105).single;
    expect((sale['items'] as List).single['itemName'], 'Package item 105');
    expect(
      AuditRepository.getAuditReport(105)!.events.single.details!['orderKind'],
      'PACKAGE',
    );
  });

  test('Reservation-linked cancellation keeps the genuine booking coherent', () async {
    final order = await seedOrder(orderId: 106);
    final booking = await seedLinkedBooking(order);

    final outcome = await CancelOrderTransaction.run(
      orderId: 106,
      actorId: 'waiter',
      source: AuditSource.pos,
    );

    expect(outcome, CancelOrderOutcome.cancelled);
    expectCancelled(106, source: 'POS', physicalTable: true);
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    final stored = DatabaseCore.reservationBox!.values.single;
    expect(stored.id, booking.id);
    expect(stored.statusEnum, ReservationStatus.cancelled);
    expect(stored.linkedOrderId, 106);
    expect(
      AuditRepository.getAuditReport(106)!.events.single.details!['orderKind'],
      'RESERVATION',
    );
    expect(
      AuditRepository.getAuditReport(106)!.events.single.details!['reservationId'],
      booking.id,
    );
  });

  test('legacy bookkeeping rows are not treated as bookings', () async {
    final order = await seedOrder(orderId: 107);
    await DatabaseCore.reservationBox!.add(
      Reservation(
        id: 'bookkeeping-107',
        customerName: 'Walk-in',
        customerPhone: '',
        tableNumbers: [107],
        tableRefs: ['first/107'],
        reservationDate: DateTime.parse('${businessDate}T00:00:00'),
        reservationTime: '12:00',
        numberOfGuests: 2,
        createdAt: order.createdAt,
        createdBy: 'waiter',
        status: ReservationStatus.inProgress.storageValue,
        linkedOrderId: 107,
        notes: 'Order #107',
      ),
    );

    await CancelOrderTransaction.run(
      orderId: 107,
      actorId: 'waiter',
      source: AuditSource.pos,
    );

    final row = DatabaseCore.reservationBox!.values.single;
    expect(row.statusEnum, ReservationStatus.inProgress);
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    expect(
      AuditRepository.getAuditReport(107)!.events.single.details!['orderKind'],
      'WALK_IN',
    );
  });

  test('the same cancellation delivered twice is one cancellation', () async {
    final order = await seedOrder(orderId: 108);
    await seedLinkedBooking(order);

    final first = await PosCommandApplier.updateOrderStatus(<String, dynamic>{
      'posOrderId': 108,
      'status': 'cancelled',
    });
    final snapshotOrder = DatabaseCore.orderBox!.get(108)!.updatedAt;
    final snapshotReport = AuditRepository.getAuditReport(108)!.toMap();
    final snapshotSale = Map<dynamic, dynamic>.from(salesFor(108).single);

    final second = await PosCommandApplier.updateOrderStatus(<String, dynamic>{
      'posOrderId': 108,
      'status': 'cancelled',
    });
    final third = await PosCommandApplier.cancelOrder(<String, dynamic>{
      'posOrderId': 108,
    }, treatMissingAsDone: true);
    final direct = await CancelOrderTransaction.run(
      orderId: 108,
      actorId: 'someone-else',
      source: AuditSource.pos,
    );

    expect(first.ok, isTrue);
    expect(second.ok, isTrue);
    expect(second.code, 'already_cancelled');
    expect(third.ok, isTrue);
    expect(third.code, 'already_cancelled');
    expect(direct, CancelOrderOutcome.alreadyCancelled);
    expectCancelled(108, source: 'MANAGER', physicalTable: true);
    expect(DatabaseCore.orderBox!.get(108)!.updatedAt, snapshotOrder);
    expect(AuditRepository.getAuditReport(108)!.toMap(), equals(snapshotReport));
    expect(salesFor(108).single, equals(snapshotSale));
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    expect(
      DatabaseCore.reservationBox!.values.single.statusEnum,
      ReservationStatus.cancelled,
    );
  });

  test('a retry after a partial write converges without duplicates', () async {
    await seedOrder(orderId: 109);
    // Simulate a crash after the audit event and the Sale were written but
    // before the Order status was: the report and record exist, the Order is
    // still live.
    await CancelOrderTransaction.run(
      orderId: 109,
      actorId: 'waiter',
      source: AuditSource.pos,
    );
    final order = DatabaseCore.orderBox!.get(109)!;
    order.status = OrderStatus.confirmed.storageValue;
    await order.save();
    final table = DatabaseCore.tableBox!.values.single..reserve('waiter', 109);
    await table.save();

    final retry = await CancelOrderTransaction.run(
      orderId: 109,
      actorId: 'waiter',
      source: AuditSource.pos,
    );

    expect(retry, CancelOrderOutcome.cancelled);
    expectCancelled(109, source: 'POS', physicalTable: true);
  });

  test('a closed order is not cancellable without a restore', () async {
    await seedOrder(orderId: 110, status: 'closed');

    final outcome = await CancelOrderTransaction.run(
      orderId: 110,
      actorId: 'waiter',
      source: AuditSource.pos,
    );
    final viaCommand = await PosCommandApplier.cancelOrder(<String, dynamic>{
      'posOrderId': 110,
    }, treatMissingAsDone: true);

    expect(outcome, CancelOrderOutcome.notCancellable);
    expect(viaCommand.ok, isFalse);
    expect(viaCommand.conflict, isTrue);
    expect(DatabaseCore.orderBox!.get(110)!.statusEnum, OrderStatus.closed);
    expect(salesFor(110), isEmpty);
    expect(AuditRepository.getAuditReport(110)!.events, isEmpty);
  });

  test('a missing order is reported, and never invented', () async {
    expect(
      await CancelOrderTransaction.run(
        orderId: 999,
        actorId: 'waiter',
        source: AuditSource.pos,
      ),
      CancelOrderOutcome.notFound,
    );
    expect(DatabaseCore.salesBox!.values, isEmpty);
    expect(AuditRepository.getAuditReport(999), isNull);
  });
}
