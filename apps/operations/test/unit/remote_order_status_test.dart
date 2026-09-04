import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// `ORDER_STATUS_UPDATE` used to take whatever status string it was handed and
/// write it to the Order. Anything that could reach the command — the Manager,
/// the Edge queue, the legacy LAN callback — could therefore persist a value no
/// reader understands, and an unreadable status is treated as non-terminal
/// everywhere: an open table nobody can close.
///
/// These tests state the rule the command now obeys. Being readable, being
/// writable, and being writable *remotely* are three different things, and the
/// last is the smallest of the three.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-05';

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
    String status = 'pending',
  }) async {
    final order = Order(
      orderId: orderId,
      tableNumbers: ['$orderId'],
      floor: 'first',
      items: [
        OrderItem(
          itemKey: 'item-$orderId',
          itemName: 'Item $orderId',
          unitPrice: 10,
          quantity: 2,
          total: 20,
        ),
      ],
      totalAmount: 20,
      createdAt: DateTime.parse('${businessDate}T12:00:00'),
      createdBy: 'waiter',
      status: status,
    );
    order.recalculateTotal(serviceFeeRate: 0);
    await DatabaseCore.orderBox!.put(orderId, order);
    final table = TableModel(tableNumber: '$orderId', floor: 'first')
      ..reserve('waiter', orderId);
    await DatabaseCore.tableBox!.put('first-$orderId', table);
    await AuditRepository.ensureAuditReport(
      orderId: orderId,
      orderSnapshot: order,
    );
    return order;
  }

  String storedStatus(int orderId) =>
      DatabaseCore.orderBox!.get(orderId)!.status;

  Future<dynamic> remote(int orderId, String status) =>
      PosCommandApplier.updateOrderStatus(<String, dynamic>{
        'posOrderId': orderId,
        'status': status,
        'updatedBy': 'Nino',
      });

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_remote_status');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('rs_settings');
    DatabaseCore.salesBox = await Hive.openBox('rs_sales');
    DatabaseCore.auditLogBox = await Hive.openBox('rs_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('rs_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('rs_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('rs_res');
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
      'rs_settings',
      'rs_sales',
      'rs_audit',
      'rs_orders',
      'rs_tables',
      'rs_res',
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

  group('the rule itself', () {
    test('confirming an open Order is the one plain assignment', () {
      expect(
        RemoteOrderStatusRule.decide(
          requested: 'confirmed',
          current: OrderStatus.pending,
        ),
        RemoteOrderStatusDecision.assign,
      );
    });

    test('a cancellation is delegated, never assigned', () {
      for (final current in OrderStatus.values) {
        expect(
          RemoteOrderStatusRule.decide(
            requested: 'cancelled',
            current: current,
          ),
          RemoteOrderStatusDecision.cancelThroughTransaction,
          reason: 'cancelling a $current Order still belongs to the transaction',
        );
      }
    });

    test('closing, and its legacy spelling, are not remotely assignable', () {
      for (final requested in const ['closed', 'paid', 'PAID']) {
        expect(
          RemoteOrderStatusRule.decide(
            requested: requested,
            current: OrderStatus.confirmed,
          ),
          RemoteOrderStatusDecision.notRemotelyAssignable,
          reason: '$requested must go through the closure transaction',
        );
      }
    });

    test('the legacy kitchen states are readable but not writable', () {
      for (final requested in const ['preparing', 'served']) {
        expect(
          RemoteOrderStatusRule.decide(
            requested: requested,
            current: OrderStatus.confirmed,
          ),
          RemoteOrderStatusDecision.notRemotelyAssignable,
        );
        // Still parseable — the point is that reading stays permissive.
        expect(OrderStatus.fromStorage(requested), isNot(OrderStatus.unknown));
      }
    });

    test('anything else is refused rather than mapped onto a real state', () {
      for (final requested in const ['', 'random-string', 'OPEN', 'void']) {
        expect(
          RemoteOrderStatusRule.decide(
            requested: requested,
            current: OrderStatus.pending,
          ),
          RemoteOrderStatusDecision.unknownStatus,
        );
      }
    });

    test('a settled Order is not reopened by a status string', () {
      for (final current in const [OrderStatus.closed, OrderStatus.cancelled]) {
        expect(
          RemoteOrderStatusRule.decide(
            requested: 'confirmed',
            current: current,
          ),
          RemoteOrderStatusDecision.orderIsTerminal,
        );
      }
    });

    test('a request the Order already satisfies writes nothing', () {
      expect(
        RemoteOrderStatusRule.decide(
          requested: 'confirmed',
          current: OrderStatus.confirmed,
        ),
        RemoteOrderStatusDecision.alreadyInState,
      );
    });
  });

  group('the command', () {
    test('a Manager confirmation is applied', () async {
      await seedOrder(orderId: 201);

      final result = await remote(201, 'confirmed');

      expect(result.ok, isTrue);
      expect(
        DatabaseCore.orderBox!.get(201)!.statusEnum,
        OrderStatus.confirmed,
      );
    });

    test('repeating it is a clean no-op, not a second write', () async {
      await seedOrder(orderId: 202);
      await remote(202, 'confirmed');
      final firstTouch = DatabaseCore.orderBox!.get(202)!.updatedAt;

      final second = await remote(202, 'confirmed');

      expect(second.ok, isTrue);
      expect(second.code, 'already_in_state');
      expect(DatabaseCore.orderBox!.get(202)!.updatedAt, firstTouch);
    });

    test('a cancellation runs the cancellation lifecycle', () async {
      await seedOrder(orderId: 203, status: 'confirmed');

      final result = await remote(203, 'cancelled');

      expect(result.ok, isTrue);
      final report = AuditRepository.getAuditReport(203)!;
      expect(report.status, AuditReportStatus.cancelled);
      expect(report.locked, isTrue);
      expect(
        report.events.where((e) => e.type == AuditEventType.cancelTable),
        hasLength(1),
      );
      // The durable non-revenue record the transaction owns, not a bare
      // status write.
      expect(
        DatabaseCore.salesBox!.values.whereType<Map>().where(
          (sale) => sale['orderId'] == 203,
        ),
        hasLength(1),
      );
    });

    test('a repeated cancellation adds no second trail', () async {
      await seedOrder(orderId: 204, status: 'confirmed');
      await remote(204, 'cancelled');

      final second = await remote(204, 'cancelled');

      expect(second.ok, isTrue);
      expect(second.code, 'already_cancelled');
      expect(
        AuditRepository.getAuditReport(
          204,
        )!.events.where((e) => e.type == AuditEventType.cancelTable),
        hasLength(1),
      );
    });

    test('"paid" cannot bypass the closure transaction', () async {
      await seedOrder(orderId: 205, status: 'confirmed');

      final result = await remote(205, 'paid');

      expect(result.ok, isFalse);
      expect(result.badRequest, isTrue);
      expect(result.code, 'status_not_remotely_assignable');
      expect(storedStatus(205), 'confirmed');
      // No Sale, no closure — the Order is exactly as it was.
      expect(DatabaseCore.salesBox!.values, isEmpty);
    });

    test('"closed" is refused for the same reason', () async {
      await seedOrder(orderId: 206, status: 'confirmed');

      final result = await remote(206, 'closed');

      expect(result.ok, isFalse);
      expect(storedStatus(206), 'confirmed');
      expect(DatabaseCore.salesBox!.values, isEmpty);
    });

    test('"preparing" and "served" are refused', () async {
      await seedOrder(orderId: 207, status: 'confirmed');

      for (final status in const ['preparing', 'served']) {
        final result = await remote(207, status);
        expect(result.ok, isFalse, reason: status);
        expect(result.code, 'status_not_remotely_assignable');
        expect(storedStatus(207), 'confirmed');
      }
    });

    test('an arbitrary string is refused and never persisted', () async {
      await seedOrder(orderId: 208, status: 'confirmed');

      final result = await remote(208, 'totally-made-up');

      expect(result.ok, isFalse);
      expect(result.badRequest, isTrue);
      expect(result.code, 'unsupported_status');
      expect(storedStatus(208), 'confirmed');
    });

    test('a closed Order is not reopened by a status string', () async {
      await seedOrder(orderId: 209, status: 'closed');

      final confirm = await remote(209, 'confirmed');
      expect(confirm.ok, isFalse);
      expect(confirm.conflict, isTrue);
      expect(confirm.code, 'order_terminal');

      // And cancelling one is the transaction's own refusal, which says the
      // same thing in the language of the cancellation path.
      final cancel = await remote(209, 'cancelled');
      expect(cancel.ok, isFalse);
      expect(cancel.code, 'order_closed');
      expect(storedStatus(209), 'closed');
    });

    test('a missing Order is reported, not silently accepted', () async {
      final result = await remote(999, 'confirmed');

      expect(result.ok, isFalse);
      expect(result.notFound, isTrue);
      expect(result.code, 'order_not_found');
    });

    test('no unsupported status survives a run of refused commands', () async {
      await seedOrder(orderId: 210, status: 'confirmed');
      for (final status in const [
        'paid',
        'preparing',
        'served',
        'garbage',
        'closed',
        '',
      ]) {
        await remote(210, status);
      }

      for (final order in DatabaseCore.orderBox!.values) {
        expect(
          order.statusEnum,
          isNot(OrderStatus.unknown),
          reason: '"${order.status}" reached storage',
        );
      }
    });
  });

  group('storage', () {
    test('the repository refuses a status it cannot read back', () async {
      await seedOrder(orderId: 211);

      expect(
        () => OrderRepository.updateOrderStatus(
          orderId: 211,
          status: 'not-a-status',
        ),
        throwsArgumentError,
      );
      expect(storedStatus(211), 'pending');
    });

    test('a legacy spelling is stored in its canonical form', () async {
      await seedOrder(orderId: 212);

      await OrderRepository.updateOrderStatus(orderId: 212, status: 'paid');

      expect(storedStatus(212), 'closed');
      expect(DatabaseCore.orderBox!.get(212)!.statusEnum, OrderStatus.closed);
    });

    test('a historical row keeps its legacy status readable', () async {
      await seedOrder(orderId: 213, status: 'served');

      expect(DatabaseCore.orderBox!.get(213)!.statusEnum, OrderStatus.served);
      expect(storedStatus(213), 'served');
    });
  });
}
