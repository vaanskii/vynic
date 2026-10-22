import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos05_unit_');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await fixture.seed();
    await DatabaseCore.orderBox!.clear();
    await DatabaseCore.auditLogBox!.clear();
    await DatabaseCore.reservationBox!.clear();
    await DatabaseCore.settingsBox!.put('lastOrderId', 0);
    for (final e in DatabaseCore.tableBox!.toMap().entries) {
      await DatabaseCore.tableBox!.put(
        e.key,
        TableModel(tableNumber: e.value.tableNumber, floor: e.value.floor),
      );
    }
    fixture.trace.clear();
  });
  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    await dir.delete(recursive: true);
  });
  OrderItem line() => OrderItem(
    itemKey: 'test',
    itemName: 'Synthetic',
    unitPrice: 2.5,
    quantity: 4,
    total: 10.01,
    menuItemId: 'menu',
    variantId: 'variant',
  );
  Future<Order> create({String? requestId}) => OrderRepository.createOrder(
    tableNumbers: ['7'],
    floor: 'first',
    createdBy: 'synthetic',
    items: [line()],
    requestId: requestId,
  );
  Future<Object> outcome(Future<Order?> action) async {
    try {
      return (await action)!;
    } catch (e) {
      return e;
    }
  }

  test(
    'local double create owns one Order/table/report, rejected attempt leaves no orphan',
    () async {
      final results = await Future.wait([outcome(create()), outcome(create())]);
      expect(results.whereType<Order>(), hasLength(1));
      expect(results.whereType<OrderMutationConflict>(), hasLength(1));
      expect(DatabaseCore.orderBox!.length, 1);
      final order = DatabaseCore.orderBox!.values.single;
      expect(
        DatabaseCore.tableBox!.values
            .singleWhere((t) => t.tableNumber == '7')
            .activeOrderId,
        order.orderId,
      );
      expect(AuditRepository.getAuditReports(), hasLength(1));
      expect(OrderTableMutationRepository.records(), hasLength(1));
      expect(OrderTableMutationRepository.integrityReport(), isEmpty);
    },
  );
  test(
    'local/remote double create rejects before extra Order/audit and reopens coherently',
    () async {
      final results = await Future.wait([
        outcome(create()),
        outcome(
          OrderRepository.upsertMobileDineInOrder(
            posOrderId: 99,
            tableNumbers: ['7'],
            floor: 'first',
            waiterName: 'manager',
            items: [line()],
          ),
        ),
      ]);
      expect(results.whereType<Order>(), hasLength(1));
      expect(results.whereType<OrderMutationConflict>(), hasLength(1));
      expect(DatabaseCore.orderBox!.length, 1);
      expect(AuditRepository.getAuditReports(), hasLength(1));
      await fixture.close();
      await fixture.open(dir.path);
      expect(OrderTableMutationRepository.integrityReport(), isEmpty);
      expect(DatabaseCore.orderBox!.length, 1);
    },
  );
  test(
    'stale independent draft conflicts and preserves first committed value',
    () async {
      final order = await create();
      final first = OrderRepository.getOrder(order.orderId)!;
      final stale = OrderRepository.getOrder(order.orderId)!;
      first.items.single.quantity = 2;
      first.items.single.total = 5.01;
      await OrderRepository.updateOrder(first);
      stale.items.single.quantity = 3;
      stale.items.single.total = 7.53;
      await expectLater(
        OrderRepository.updateOrder(stale),
        throwsA(isA<OrderMutationConflict>()),
      );
      expect(OrderRepository.getOrder(order.orderId)!.items.single.quantity, 2);
      expect(
        (OrderRepository.getOrder(order.orderId)!.totalAmount * 100).round(),
        501,
      );
      expect(LocalDataAdmission.failure, isNull);
    },
  );

  test(
    'stable cancellation retry retains original request after archive and rejects changed payload',
    () async {
      final order = await create(requestId: 'create-original');
      expect(
        await CancelOrderTransaction.run(
          orderId: order.orderId,
          actorId: 'synthetic',
          source: AuditSource.pos,
          reason: 'original reason',
          requestId: 'cancel-original',
        ),
        CancelOrderOutcome.cancelled,
      );
      final receipt = OrderTableMutationRepository.read(
        'cancel-original',
      )!.toMap();
      final sale = Map.of(DatabaseCore.salesBox!.toMap());
      final reports = AuditRepository.getAuditReports()
          .map((r) => r.toMap())
          .toList();
      await DatabaseCore.orderBox!.delete(
        OrderTableMutationRepository.persisted(order.orderId)!.$1,
      );
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-02T00:00:00.000',
      );
      expect(
        await CancelOrderTransaction.run(
          orderId: order.orderId,
          actorId: 'synthetic',
          source: AuditSource.pos,
          reason: 'original reason',
          requestId: 'cancel-original',
        ),
        CancelOrderOutcome.alreadyCancelled,
      );
      await expectLater(
        CancelOrderTransaction.run(
          orderId: order.orderId,
          actorId: 'other actor',
          source: AuditSource.pos,
          reason: 'original reason',
          requestId: 'cancel-original',
        ),
        throwsA(
          isA<OrderMutationConflict>().having(
            (e) => e.code,
            'code',
            'request_conflict',
          ),
        ),
      );
      expect(
        OrderTableMutationRepository.read('cancel-original')!.toMap(),
        receipt,
      );
      expect(DatabaseCore.salesBox!.toMap(), sale);
      expect(
        AuditRepository.getAuditReports().map((r) => r.toMap()).toList(),
        reports,
      );
      expect(DatabaseCore.orderBox!.length, 0);
      expect(LocalDataAdmission.failure, isNull);
    },
  );
}
