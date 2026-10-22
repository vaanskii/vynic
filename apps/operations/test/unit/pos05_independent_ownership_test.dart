import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import '../support/menu01_fixture.dart';

// Root-owned property: the baseline and candidate execute the same public
// entrypoints against real, throwaway Hive storage. No scheduling mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides? previous;

  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    UpdateReadiness.enabled = false;
    root = await Directory.systemTemp.createTemp('vynic-pos05-independent-');
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
    AuditRepository.registerAuditChangedCallback(() {});
    await closeMenu01();
    HttpOverrides.global = previous;
    await root.delete(recursive: true);
  });

  OrderItem line(String origin) => OrderItem(
    itemKey: origin,
    itemName: origin,
    unitPrice: 12.51,
    quantity: 1,
    total: 12.51,
  );

  Future<Object?> outcome(Future<Order?> operation) async {
    try {
      return await operation;
    } catch (error) {
      return error;
    }
  }

  test(
    'stale independent edit cannot overwrite a committed Order image',
    () async {
      final created = await OrderRepository.createOrder(
        tableNumbers: ['7'],
        floor: 'first',
        createdBy: 'local-synthetic',
        items: [line('editable')],
        includeServiceFee: false,
      );
      final first = OrderRepository.getOrder(created.orderId)!;
      final second = OrderRepository.getOrder(created.orderId)!;
      first.items.single.quantity = 2;
      first.items.single.total = 25.02;
      await OrderRepository.updateOrder(first);
      second.items.single.quantity = 3;
      second.items.single.total = 37.53;
      var refused = false;
      try {
        await OrderRepository.updateOrder(second);
      } catch (_) {
        refused = true;
      }
      await closeMenu01();
      await openMenu01(root.path);
      final persisted = OrderRepository.getOrder(created.orderId)!;
      final observation = {
        'secondRefused': refused,
        'persistedQuantity': persisted.items.single.quantity,
        'persistedValueCents': (persisted.items.single.total * 100).round(),
      };
      // ignore: avoid_print
      print('POS05_STALE_EDIT_OBSERVATION ${jsonEncode(observation)}');
      expect(refused, true, reason: jsonEncode(observation));
      expect(persisted.items.single.quantity, 2);
      expect((persisted.items.single.total * 100).round(), 2502);
      expect(
        DatabaseCore.tableBox!.get('first-7')!.activeOrderId,
        created.orderId,
      );
    },
  );

  test(
    'simultaneous cancel and payment persist exactly one settlement',
    () async {
      final order = await OrderRepository.createOrder(
        tableNumbers: ['7'],
        floor: 'first',
        createdBy: 'local-synthetic',
        items: [line('settlement')],
        includeServiceFee: false,
      );
      final money = ClosureMoney.fromOrder(order, collectedNow: 12.51);
      final results = await Future.wait<Object>([
        CancelOrderTransaction.run(
          orderId: order.orderId,
          actorId: 'cancel-synthetic',
          source: AuditSource.pos,
          reason: 'Synthetic cancellation race',
        ),
        CloseTableTransaction.run(
          orderId: order.orderId,
          money: money,
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 12.51},
          closedById: 'payment-synthetic',
          isFiscal: true,
        ),
      ]);
      await closeMenu01();
      await openMenu01(root.path);
      final sales = DatabaseCore.salesBox!.values
          .whereType<Map>()
          .where((sale) => sale['orderId'] == order.orderId)
          .toList();
      final persisted = OrderRepository.getOrder(order.orderId)!;
      final successes = results
          .where(
            (v) =>
                v == CancelOrderOutcome.cancelled ||
                (v is ClosureResult && v.isSuccess),
          )
          .length;
      final observation = {
        'outcomes': results
            .map((v) => v is ClosureResult ? v.outcome.name : '$v')
            .toList(),
        'settlementCount': sales.length,
        'paymentMethods': sales.map((v) => v['paymentMethod']).toList(),
        'orderStatus': persisted.status,
      };
      // ignore: avoid_print
      print('POS05_SETTLEMENT_OBSERVATION ${jsonEncode(observation)}');
      expect(successes, 1, reason: jsonEncode(observation));
      expect(sales, hasLength(1));
      expect(DatabaseCore.tableBox!.get('first-7')!.activeOrderId, isNull);
      if (persisted.status == 'cancelled') {
        expect(sales.single['paymentMethod'], 'cancelled');
      } else {
        expect(persisted.status, 'closed');
        expect(sales.single['paymentMethod'], 'cash');
      }
    },
  );

  test(
    'simultaneous local creates persist exactly one physical owner',
    () async {
      final results = await Future.wait([
        for (final actor in ['local-a-synthetic', 'local-b-synthetic'])
          outcome(
            OrderRepository.createOrder(
              tableNumbers: ['7'],
              floor: 'first',
              createdBy: actor,
              items: [line(actor)],
              includeServiceFee: false,
            ),
          ),
      ]);
      await closeMenu01();
      await openMenu01(root.path);
      final owners = DatabaseCore.orderBox!.values.toList();
      final reports = AuditRepository.getAuditReports();
      final observation = {
        'acceptedIds': results
            .whereType<Order>()
            .map((order) => order.orderId)
            .toList(),
        'persistedIds': owners.map((order) => order.orderId).toList(),
        'tableOwnerId': DatabaseCore.tableBox!.get('first-7')!.activeOrderId,
        'auditOrderIds': reports.map((report) => report.orderId).toList(),
      };
      // ignore: avoid_print
      print('POS05_LOCAL_RACE_OBSERVATION ${jsonEncode(observation)}');
      expect(
        results.whereType<Order>(),
        hasLength(1),
        reason: jsonEncode(observation),
      );
      expect(owners, hasLength(1));
      expect(reports, hasLength(1));
      expect(
        DatabaseCore.tableBox!.get('first-7')!.activeOrderId,
        owners.single.orderId,
      );
    },
  );

  test('free projection cannot admit a second persisted owner', () async {
    await DatabaseCore.orderBox!.add(
      Order(
        orderId: 70,
        tableNumbers: ['7'],
        floor: 'first',
        items: [line('existing')],
        totalAmount: 12.51,
        createdAt: DateTime(2026, 10, 2, 10),
        createdBy: 'existing-synthetic',
        status: 'confirmed',
        includeServiceFee: false,
      ),
    );
    final beforeOrders = jsonEncode(
      DatabaseCore.orderBox!.values.map((o) => o.toJson()).toList(),
    );
    final result = await outcome(
      OrderRepository.createOrder(
        tableNumbers: ['7'],
        floor: 'first',
        createdBy: 'new-synthetic',
        items: [line('new')],
        includeServiceFee: false,
      ),
    );
    final afterOrders = jsonEncode(
      DatabaseCore.orderBox!.values.map((o) => o.toJson()).toList(),
    );
    expect(
      result,
      isNot(isA<Order>()),
      reason:
          'Order claims are authoritative even when the table flag is stale',
    );
    expect(
      afterOrders,
      beforeOrders,
      reason: 'Refusal must preserve original records',
    );
    expect(AuditRepository.getAuditReports(), isEmpty);
  });

  test(
    'simultaneous local and remote create persist exactly one physical owner',
    () async {
      final results = await Future.wait([
        outcome(
          OrderRepository.createOrder(
            tableNumbers: ['7'],
            floor: 'first',
            createdBy: 'local-synthetic',
            items: [line('local')],
            includeServiceFee: false,
          ),
        ),
        outcome(
          OrderRepository.upsertMobileDineInOrder(
            posOrderId: 99,
            tableNumbers: ['7'],
            floor: 'first',
            waiterName: 'remote-synthetic',
            items: [line('remote')],
          ),
        ),
      ]);
      // A real close/reopen proves persisted state, not just eager Hive objects.
      await closeMenu01();
      await openMenu01(root.path);
      final owners = DatabaseCore.orderBox!.values
          .where(
            (order) =>
                order.floor == 'first' && order.tableNumbers.contains('7'),
          )
          .toList();
      final table = DatabaseCore.tableBox!.get('first-7')!;
      final reports = AuditRepository.getAuditReports();
      final observation = {
        'results': results
            .map(
              (v) => v is Order
                  ? {'acceptedOrderId': v.orderId}
                  : {'refused': '$v'},
            )
            .toList(),
        'persistedOwnerIds': owners.map((order) => order.orderId).toList(),
        'tableOwnerId': table.activeOrderId,
        'auditOrderIds': reports.map((r) => r.orderId).toList(),
      };
      // ignore: avoid_print
      print('POS05_INDEPENDENT_OBSERVATION ${jsonEncode(observation)}');
      expect(
        results.whereType<Order>().length,
        1,
        reason: jsonEncode(observation),
      );
      expect(owners, hasLength(1));
      expect(table.activeOrderId, owners.single.orderId);
      expect(table.isReserved, true);
      expect(reports, hasLength(1));
      expect(reports.single.orderId, owners.single.orderId);
      expect(
        DatabaseCore.orderBox!.length,
        1,
        reason: 'Rejected request must leave no orphan Order',
      );
    },
  );
}
