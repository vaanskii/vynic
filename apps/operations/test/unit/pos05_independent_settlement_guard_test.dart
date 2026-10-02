import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import '../support/menu01_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides? previous;
  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    root = await Directory.systemTemp.createTemp('vynic-pos05-settlement-');
    await openMenu01(root.path);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-02T00:00:00.000',
    );
    await DatabaseCore.tableBox!.put(
      'first-7',
      TableModel(tableNumber: '7', floor: 'first'),
    );
    Order.serviceFeeRateResolver = () => 0.0;
    AuditRepository.registerAuditChangedCallback(() {});
  });
  tearDown(() async {
    await closeMenu01();
    HttpOverrides.global = previous;
    await root.delete(recursive: true);
  });
  test(
    'cancelled Order payment refuses before allocating any new recovery work',
    () async {
      final order = await OrderRepository.createOrder(
        tableNumbers: ['7'],
        floor: 'first',
        createdBy: 'synthetic',
        includeServiceFee: false,
        items: [
          OrderItem(
            itemKey: 'item',
            itemName: 'Synthetic',
            unitPrice: 12.51,
            quantity: 1,
            total: 12.51,
          ),
        ],
      );
      expect(
        await CancelOrderTransaction.run(
          orderId: order.orderId,
          actorId: 'synthetic',
          source: AuditSource.pos,
        ),
        CancelOrderOutcome.cancelled,
      );
      final beforeAudit = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      final beforeClosure = jsonEncode(DatabaseCore.closureJournalBox!.toMap());
      final beforeOrder = jsonEncode(
        OrderRepository.getOrder(order.orderId)!.toJson(),
      );
      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 12.51),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 12.51},
        closedById: 'synthetic',
        isFiscal: true,
      );
      final observation = {
        'outcome': result.outcome.name,
        'pendingClosures': ClosureJournalRepository.pending().length,
        'closureId': OrderRepository.getOrder(order.orderId)!.closureId,
        'sales': DatabaseCore.salesBox!.length,
      };
      // ignore: avoid_print
      print('POS05_REFUSED_PAYMENT_OBSERVATION ${jsonEncode(observation)}');
      expect(result.isSuccess, false);
      expect(
        jsonEncode(DatabaseCore.closureJournalBox!.toMap()),
        beforeClosure,
        reason: 'Refused payment cannot allocate a closure intent',
      );
      expect(
        jsonEncode(OrderRepository.getOrder(order.orderId)!.toJson()),
        beforeOrder,
        reason: 'Refused payment cannot allocate a closure identity',
      );
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudit);
      expect(DatabaseCore.salesBox!.length, 1);
    },
  );
  test(
    'a payment amount captured before a committed edit cannot settle the new Order',
    () async {
      final order = await OrderRepository.createOrder(
        tableNumbers: ['7'],
        floor: 'first',
        createdBy: 'synthetic',
        includeServiceFee: false,
        items: [
          OrderItem(
            itemKey: 'item',
            itemName: 'Synthetic',
            unitPrice: 12.51,
            quantity: 1,
            total: 12.51,
          ),
        ],
      );
      final staleMoney = ClosureMoney.fromOrder(order, collectedNow: 12.51);
      final edited = OrderRepository.getOrder(order.orderId)!;
      edited.items.single.quantity = 2;
      edited.items.single.total = 25.02;
      await OrderRepository.updateOrder(edited);
      final beforeAudit = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      final beforeClosure = jsonEncode(DatabaseCore.closureJournalBox!.toMap());
      final beforeOrder = jsonEncode(
        OrderRepository.getOrder(order.orderId)!.toJson(),
      );
      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: staleMoney,
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 12.51},
        closedById: 'synthetic',
        isFiscal: true,
      );
      final observation = {
        'outcome': result.outcome.name,
        'currentOrderValueCents':
            (OrderRepository.getOrder(order.orderId)!.totalAmount * 100)
                .round(),
        'sales': DatabaseCore.salesBox!.length,
        'closureRecords': DatabaseCore.closureJournalBox!.length,
      };
      // ignore: avoid_print
      print('POS05_STALE_PAYMENT_OBSERVATION ${jsonEncode(observation)}');
      expect(result.isSuccess, false, reason: jsonEncode(observation));
      expect(
        jsonEncode(DatabaseCore.closureJournalBox!.toMap()),
        beforeClosure,
      );
      expect(
        jsonEncode(OrderRepository.getOrder(order.orderId)!.toJson()),
        beforeOrder,
      );
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudit);
      expect(DatabaseCore.salesBox!.length, 0);
      expect(
        DatabaseCore.tableBox!.get('first-7')!.activeOrderId,
        order.orderId,
      );
    },
  );
}
