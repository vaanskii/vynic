import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/transactions/activate_reservation_transaction.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'pos03_fixture.dart';
export 'pos03_fixture.dart' show Menu01NoHttp;

const pos05Request = 'synthetic-pos05-request';
const pos05HistoricalSale = {
  'orderId': 99,
  'totalAmount': 70.0,
  'items': <dynamic>[],
  'recordType': 'sale',
  'posSaleId': 'synthetic-historical-sale',
  'ledgerRevision': 1,
  'ledgerUpdatedAt': '2026-09-30T12:00:00.000',
};

class Pos05Box<T> extends UpdateTrackedBox<T> {
  Pos05Box(super.inner, this.proofName, this.boundary);
  final String proofName;
  final Future<void> Function(String) boundary;
  Future<R> io<R>(String label, Future<R> Function() action) async {
    await boundary('$proofName.$label:before');
    final result = await action();
    await boundary('$proofName.$label:after');
    return result;
  }

  @override
  Future<void> put(dynamic key, T value) => io(
    'put:${proofName == 'meta' && value is Map ? value['phase'] : key}',
    () => super.put(key, value),
  );
  @override
  Future<void> flush() => io('flush', super.flush);
}

class Pos05Fixture extends Pos03Fixture {
  String scenario = 'create';
  Map<String, dynamic>? original;
  @override
  Future<void> open(String path, {bool instrument = true}) async {
    await super.open(path, instrument: false);
    if (instrument) {
      DatabaseCore.metaBox = Pos05Box(DatabaseCore.metaBox!, 'meta', boundary);
      DatabaseCore.settingsBox = Pos05Box(
        DatabaseCore.settingsBox!,
        'settings',
        boundary,
      );
      DatabaseCore.orderBox = Pos05Box(
        DatabaseCore.orderBox!,
        'orders',
        boundary,
      );
      DatabaseCore.tableBox = Pos05Box(
        DatabaseCore.tableBox!,
        'tables',
        boundary,
      );
      DatabaseCore.reservationBox = Pos05Box(
        DatabaseCore.reservationBox!,
        'reservations',
        boundary,
      );
      DatabaseCore.salesBox = Pos05Box(
        DatabaseCore.salesBox!,
        'sales',
        boundary,
      );
      DatabaseCore.auditLogBox = Pos05Box(
        DatabaseCore.auditLogBox!,
        'audit',
        boundary,
      );
    }
  }

  OrderItem line() => OrderItem(
    itemKey: 'synthetic',
    itemName: 'Synthetic frozen',
    unitPrice: 2.5,
    quantity: 4,
    total: 10.01,
    menuItemId: 'menu',
    variantId: 'variant',
  );
  Future<void> prepare(String kind) async {
    scenario = kind;
    await seed(rich: kind == 'move' || kind == 'cancel');
    await DatabaseCore.auditLogBox!.clear();
    await DatabaseCore.salesBox!.put('historical', pos05HistoricalSale);
    if (kind == 'move' || kind == 'cancel') {
      final order = OrderRepository.getOrder(1)!;
      original = OrderTableMutationRepository.image(order);
      await AuditRepository.ensureAuditReport(
        orderId: order.orderId,
        orderSnapshot: order,
      );
      await DatabaseCore.tableBox!.put(
        'target',
        TableModel(tableNumber: '13', floor: 'first'),
      );
    } else {
      await DatabaseCore.orderBox!.clear();
      await DatabaseCore.reservationBox!.clear();
      await DatabaseCore.settingsBox!.put('lastOrderId', 0);
      for (final e in DatabaseCore.tableBox!.toMap().entries)
        await DatabaseCore.tableBox!.put(
          e.key,
          TableModel(tableNumber: e.value.tableNumber, floor: e.value.floor),
        );
      if (kind == 'activation') {
        await DatabaseCore.reservationBox!.put(
          'booking',
          Reservation(
            id: 'booking',
            customerName: 'Synthetic booking',
            customerPhone: 'synthetic',
            tableNumbers: [7],
            tableRefs: ['first/7'],
            reservationDate: DateTime(2026, 10, 1),
            reservationTime: '18:00',
            numberOfGuests: 2,
            createdAt: DateTime(2026, 9, 30),
            createdBy: 'synthetic',
            status: 'confirmed',
            preOrderItems: [line()],
            notes: 'guest notes',
          ),
        );
        await DatabaseCore.tableBox!.put(
          'source-table',
          TableModel(tableNumber: '7', floor: 'first')
            ..reserveForReservation('synthetic', 'booking'),
        );
      }
    }
    for (final box in [
      DatabaseCore.orderBox!,
      DatabaseCore.tableBox!,
      DatabaseCore.reservationBox!,
      DatabaseCore.auditLogBox!,
      DatabaseCore.settingsBox!,
      DatabaseCore.metaBox!,
      DatabaseCore.salesBox!,
    ])
      await box.flush();
    trace.clear();
  }

  Future<Order?> action() async => switch (scenario) {
    'create' => OrderRepository.createOrder(
      tableNumbers: ['7'],
      floor: 'first',
      createdBy: 'synthetic',
      items: [line()],
      requestId: pos05Request,
    ),
    'takeaway' => OrderRepository.createTakeAwayOrder(
      customerName: 'Synthetic',
      customerPhone: 'synthetic',
      pickupTime: '18:00',
      createdBy: 'synthetic',
      items: [line()],
      requestId: pos05Request,
    ),
    'package' => OrderRepository.createOrderForPackage(
      package: Package(
        packageId: 'package',
        name: 'Synthetic package',
        pricePerPerson: 7.11,
        servingSize: 1,
        createdBy: 'synthetic',
        createdAt: DateTime(2026, 9, 30),
        items: [
          PackageItem(
            itemKey: 'p',
            itemName: 'Frozen package',
            quantity: 1,
            unitPrice: 8,
            menuItemId: 'pmenu',
            variantId: 'pvariant',
          ),
        ],
      ),
      tableNumbers: ['7'],
      floor: 'first',
      guestCount: 2,
      createdBy: 'synthetic',
      requestId: pos05Request,
    ),
    'activation' => _activate(),
    'cancel' => _cancel(),
    'move' => OrderTableMutationRepository.move(
      expected: OrderTableMutationRepository.capture(
        OrderTransferIntent.orderImage(original!),
      ),
      tableNumbers: ['13'],
      floor: 'first',
      actor: 'synthetic',
      requestId: pos05Request,
    ),
    _ => throw StateError('Unknown synthetic scenario'),
  };
  Future<Order> _cancel() async {
    final result = await CancelOrderTransaction.run(
      orderId: 1,
      actorId: 'synthetic',
      source: AuditSource.pos,
      requestId: pos05Request,
    );
    expect(
      [CancelOrderOutcome.cancelled, CancelOrderOutcome.alreadyCancelled],
      contains(result),
      reason: LocalDataAdmission.failure,
    );
    return OrderRepository.getOrder(1)!;
  }

  Future<Order> _activate() async {
    final result = await ActivateReservationTransaction.activate(
      reservationId: 'booking',
      activatedBy: 'synthetic',
    );
    expect(result.isSuccess, true);
    return OrderRepository.getOrder(result.orderId!)!;
  }

  String get id =>
      scenario == 'activation' ? 'activation:booking' : pos05Request;
  Map<String, dynamic> check() {
    final intent = OrderTableMutationRepository.read(id)!;
    expect(intent.pending, false);
    expect(OrderTableMutationRepository.integrityReport(), isEmpty);
    final order = OrderRepository.getOrder(intent.outcome['orderId'] as int)!;
    final report = AuditRepository.getAuditReport(order.orderId)!;
    expect(report.locked, scenario == 'cancel');
    if (scenario == 'package') {
      expect((order.packagePrice * 100).round(), 1422);
      expect(order.packageGuestCount, 2);
      expect(order.packageItems.single.menuItemId, 'pmenu');
    } else if (scenario == 'cancel') {
      expect(order.status, 'cancelled');
      expect(
        report.events.where((e) => e.type.toString().endsWith('cancelTable')),
        hasLength(1),
      );
      expect(DatabaseCore.reservationBox!.get('booking')!.status, 'cancelled');
      expect(
        DatabaseCore.reservationBox!.get('bookkeeping')!.status,
        'in-progress',
      );
      final sales = DatabaseCore.salesBox!.values
          .whereType<Map>()
          .where((s) => s['orderId'] == 1)
          .toList();
      expect(sales, hasLength(1));
      expect(sales.single['collectedNow'], 0);
      expect(sales.single['isCancelled'], true);
    } else if (scenario == 'move') {
      expect(
        OrderTransferIntent.sameImage(
          OrderTableMutationRepository.image(order),
          intent.outcome['order'],
        ),
        true,
      );
      expect(
        report.events.where((e) => e.details?['requestId'] == id),
        hasLength(1),
      );
      final booking = DatabaseCore.reservationBox!.get('booking')!;
      expect(
        ReservationTableAvailability.tableRefsOf(booking).single.encode(),
        'first/13',
      );
      expect(booking.linkedOrderId, 1);
      expect(booking.notes, 'Guest notes');
      expect(DatabaseCore.reservationBox!.get('bookkeeping')!.tableNumbers, [
        7,
      ]);
    } else {
      expect(order.items.single.quantity, 4);
      expect((order.items.single.total * 100).round(), 1001);
      expect(order.items.single.menuItemId, 'menu');
      expect(order.items.single.variantId, 'variant');
      expect(report.events, hasLength(2));
      if (scenario == 'activation') {
        final booking = DatabaseCore.reservationBox!.get('booking')!;
        expect(booking.status, 'in-progress');
        expect(booking.linkedOrderId, order.orderId);
        expect(
          AuditEventLog.fromMap(
            Map<String, dynamic>.from(
              DatabaseCore.auditLogBox!.get('$id:reservation'),
            ),
          ).data['businessDate'],
          '2026-10-01',
        );
      }
    }
    expect(DatabaseCore.salesBox!.get('historical'), pos05HistoricalSale);
    return {
      'status': 'PASS',
      'scenario': scenario,
      'requestId': id,
      'orderUuid': order.orderUuid,
      'quantity': order.items.fold(0, (int n, i) => n + i.quantity),
      'totalCents': (order.totalAmount * 100).round(),
      'reports': AuditRepository.getAuditReports().length,
      'phase': intent.body['phase'],
    };
  }

  String persisted() => jsonEncode({
    'orders': DatabaseCore.orderBox!.toMap().map(
      (k, o) => MapEntry('$k', OrderTableMutationRepository.image(o)),
    ),
    'tables': DatabaseCore.tableBox!.toMap().map(
      (k, t) => MapEntry('$k', OrderTableMutationRepository.tableImage(t)),
    ),
    'reservations': DatabaseCore.reservationBox!.toMap().map(
      (k, r) =>
          MapEntry('$k', OrderTableMutationRepository.reservationImage(r)),
    ),
    'audit': DatabaseCore.auditLogBox!.toMap(),
    'sales': DatabaseCore.salesBox!.toMap(),
    'meta': DatabaseCore.metaBox!.toMap(),
  });
}
