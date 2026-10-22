import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'menu01_fixture.dart' show openMenu01, closeMenu01, Menu01NoHttp;
export 'menu01_fixture.dart' show Menu01NoHttp;

const pos03Id = '30000000-0000-4000-8000-000000000001';
const pos03SourceUuid = '30000000-0000-4000-8000-000000000002';
const pos03DestinationUuid = '30000000-0000-4000-8000-000000000003';
final pos03User = User(
  username: 'synthetic',
  pinCode: '000000',
  role: 'manager',
);

/// Instruments actual Box.put/flush, which the coordinator uses directly.
/// HiveObject.save bypasses a wrapped Box and is deliberately not the seam.
class Pos03Box<T> extends UpdateTrackedBox<T> {
  Pos03Box(super.inner, this.proofName, this.boundary);
  final String proofName;
  final Future<void> Function(String) boundary;
  Future<R> io<R>(String point, Future<R> Function() action) async {
    await boundary('$proofName.$point:before');
    final result = await action();
    await boundary('$proofName.$point:after');
    return result;
  }

  @override
  Future<void> put(dynamic key, T value) {
    final label = proofName == 'meta' && value is Map
        ? 'transfer:${value['phase']}'
        : proofName == 'audit' && '$key'.startsWith('audit_report_order_')
        ? '$key'
        : proofName == 'audit'
        ? 'reservation-event'
        : '$key';
    return io('put:$label', () => super.put(key, value));
  }

  @override
  Future<void> flush() => io('flush', super.flush);
}

class Pos03Fixture {
  final List<String> trace = [];
  Future<void> Function(String, int)? fault;
  Order? originalSource;
  Order? originalDestination;
  Future<void> boundary(String point) async {
    trace.add(point);
    await fault?.call(point, trace.length);
  }

  Future<void> open(String path, {bool instrument = true}) async {
    HttpOverrides.global = Menu01NoHttp();
    await openMenu01(path);
    Order.serviceFeeRateResolver = () => 0;
    Order.timestampResolver = BusinessDayRepository.getCurrentDateTime;
    UpdateReadiness.enabled = false;
    UpdateReadiness.failure = null;
    if (instrument) {
      DatabaseCore.metaBox = Pos03Box(DatabaseCore.metaBox!, 'meta', boundary);
      DatabaseCore.orderBox = Pos03Box(
        DatabaseCore.orderBox!,
        'orders',
        boundary,
      );
      DatabaseCore.tableBox = Pos03Box(
        DatabaseCore.tableBox!,
        'tables',
        boundary,
      );
      DatabaseCore.reservationBox = Pos03Box(
        DatabaseCore.reservationBox!,
        'reservations',
        boundary,
      );
      DatabaseCore.auditLogBox = Pos03Box(
        DatabaseCore.auditLogBox!,
        'audit',
        boundary,
      );
    }
  }

  Future<void> seed({bool rich = false, bool takeaway = false}) async {
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-01T00:00:00.000',
      'dailySalesTotal': 70.0,
      'lastOrderId': 2,
      'serviceFeePercent': 0.0,
      'serviceFeeEnabled': false,
    });
    OrderItem line(int quantity, double total, String uuid) => OrderItem(
      itemKey: 'frozen',
      itemName: 'Frozen bill',
      unitPrice: 2.5,
      quantity: quantity,
      total: total,
      comment: ' keep ',
      menuItemId: 'menu-identity',
      variantId: 'variant-identity',
      lineUuid: uuid,
    );
    final source = Order(
      orderId: 1,
      orderUuid: pos03SourceUuid,
      edgeRevision: 7,
      tableNumbers: [takeaway ? 'Takeaway' : '7'],
      floor: takeaway ? 'takeaway' : 'first',
      items: [line(4, 10.01, 'source-line')],
      totalAmount: 10.01,
      createdAt: DateTime.parse('2026-10-01T12:01:02.123456'),
      updatedAt: DateTime.parse('2026-10-01T12:01:03.123456'),
      createdBy: 'synthetic',
      openedByUserId: 'owner',
      status: 'confirmed',
      includeServiceFee: false,
      customerName: 'Synthetic guest',
      customerPhone: 'synthetic',
      pickupTime: '18:00',
      advanceAmount: rich ? 1.17 : 0,
      advanceCollectedOn: rich ? '2026-09-30' : null,
      advanceReceiptId: rich ? 'advance-receipt' : null,
      discountAmount: rich ? 0.21 : 0,
      manualAdjustmentAmount: rich ? 0.11 : 0,
      customServiceFeePercentage: rich ? 3.0 : null,
      packageId: rich ? 'package-id' : null,
      packageName: rich ? 'Package snapshot' : null,
      packagePrice: rich ? 7.11 : 0,
      packageUnitPrice: rich ? 7.11 : 0,
      packageGuestCount: rich ? 1 : 0,
      packageItems: rich
          ? [
              OrderItem(
                itemKey: 'package',
                itemName: 'Fixed package',
                unitPrice: 8,
                quantity: 1,
                total: 7.11,
                menuItemId: 'package-menu',
                variantId: 'package-variant',
                lineUuid: 'package-line',
              ),
            ]
          : [],
    );
    final destination = Order(
      orderId: 2,
      orderUuid: pos03DestinationUuid,
      edgeRevision: 11,
      tableNumbers: ['12'],
      floor: 'first',
      items: [line(1, 2.50, 'destination-line')],
      totalAmount: 2.50,
      createdAt: DateTime.parse('2026-10-01T12:02:02.987654'),
      createdBy: 'synthetic',
      status: 'confirmed',
    );
    await DatabaseCore.orderBox!.put('source', source);
    await DatabaseCore.orderBox!.put('destination', destination);
    await DatabaseCore.tableBox!.put(
      'source-table',
      TableModel(
        tableNumber: takeaway ? 'Takeaway' : '7',
        floor: source.floor,
        activeOrderId: 1,
        isReserved: true,
        reservationId: 'booking',
        reservedBy: 'synthetic',
        reservedAt: DateTime.parse('2026-10-01T12:01:02.654321'),
        edgeRevision: 8,
      ),
    );
    await DatabaseCore.tableBox!.put(
      'destination-table',
      TableModel(
        tableNumber: '12',
        floor: 'first',
        isReserved: true,
        activeOrderId: 2,
      ),
    );
    Reservation booking(String id, {bool bookkeeping = false}) => Reservation(
      id: id,
      customerName: 'Synthetic booking',
      customerPhone: 'synthetic',
      tableNumbers: [7],
      reservationDate: DateTime.parse('2026-10-01'),
      reservationTime: '18:00',
      numberOfGuests: 2,
      createdAt: DateTime.parse('2026-09-30'),
      createdBy: 'synthetic',
      status: 'in-progress',
      linkedOrderId: 1,
      notes: bookkeeping ? 'Order #1' : 'Guest notes',
    );
    await DatabaseCore.reservationBox!.put('booking', booking('booking'));
    await DatabaseCore.reservationBox!.put(
      'bookkeeping',
      booking('bookkeeping', bookkeeping: true),
    );
    await DatabaseCore.salesBox!.put('historical', {
      'orderId': 99,
      'totalAmount': 70.0,
      'items': [],
      'recordType': 'sale',
    });
    for (final box in [
      DatabaseCore.settingsBox!,
      DatabaseCore.orderBox!,
      DatabaseCore.tableBox!,
      DatabaseCore.reservationBox!,
      DatabaseCore.salesBox!,
    ]) {
      await box.flush();
    }
    originalSource = source.clone();
    originalDestination = destination.clone();
    trace.clear();
  }

  Future<OrderTransferResult> apply({
    int quantity = 4,
    String id = pos03Id,
    String? expectedBusinessDate,
  }) => OrderItemTransfer.apply(
    source: originalSource ?? DatabaseCore.orderBox!.get('source')!.clone(),
    destination:
        originalDestination ??
        DatabaseCore.orderBox!.get('destination')!.clone(),
    moves: [(index: 0, quantity: quantity)],
    user: pos03User,
    sourceLabel: 'Table 7',
    destinationLabel: 'Table 12',
    transferId: id,
    expectedBusinessDate: expectedBusinessDate,
  );
  Future<void> close() async {
    fault = null;
    await closeMenu01();
    LocalDataAdmission.failure = null;
    UpdateReadiness.failure = null;
    Order.timestampResolver = null;
    Order.serviceFeeRateResolver = null;
  }

  Map<String, Object?> verify({String id = pos03Id, bool takeaway = false}) {
    final source = DatabaseCore.orderBox!.get('source')!;
    final destination = DatabaseCore.orderBox!.get('destination')!;
    expect(source.orderUuid, pos03SourceUuid);
    expect(destination.orderUuid, pos03DestinationUuid);
    expect(source.edgeRevision, 7);
    expect(destination.edgeRevision, 11);
    expect(source.items, isEmpty);
    expect(source.status, 'closed');
    expect(
      source.createdAt.millisecondsSinceEpoch,
      DateTime.parse('2026-10-01T12:01:02.123').millisecondsSinceEpoch,
    );
    expect(source.createdBy, 'synthetic');
    expect(source.openedByUserId, 'owner');
    expect(source.customerName, 'Synthetic guest');
    expect(source.pickupTime, '18:00');
    expect(destination.items.single.quantity, 5);
    expect((destination.items.single.total * 100).round(), 1251);
    expect(destination.items.single.unitPrice, 2.5);
    expect(destination.items.single.menuItemId, 'menu-identity');
    expect(destination.items.single.variantId, 'variant-identity');
    expect(destination.items.single.lineUuid, 'destination-line');
    expect(
      DatabaseCore.tableBox!.get('source-table')!.activeOrderId,
      takeaway ? 1 : null,
    );
    expect(DatabaseCore.tableBox!.get('source-table')!.edgeRevision, 8);
    expect(DatabaseCore.tableBox!.get('destination-table')!.activeOrderId, 2);
    expect(DatabaseCore.reservationBox!.get('booking')!.status, 'completed');
    expect(DatabaseCore.reservationBox!.get('booking')!.linkedOrderId, 1);
    expect(
      DatabaseCore.reservationBox!.get('bookkeeping')!.status,
      'in-progress',
    );
    expect(DatabaseCore.salesBox!.length, 1);
    expect(DatabaseCore.salesBox!.get('historical')['totalAmount'], 70.0);
    expect(
      DatabaseCore.settingsBox!.get('currentDate'),
      '2026-10-01T00:00:00.000',
    );
    expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    final reports = [
      for (final orderId in [1, 2])
        AuditReport.fromMap(
          DatabaseCore.auditLogBox!.get('audit_report_order_$orderId') as Map,
        ),
    ];
    expect(reports[0].events.map((e) => e.type), [
      AuditEventType.moveItems,
      AuditEventType.transferClose,
    ]);
    expect(reports[0].locked, true);
    expect(reports[1].events.map((e) => e.type), [AuditEventType.moveItems]);
    for (final report in reports) {
      expect(
        report.events.map((e) => e.sequence).toSet(),
        hasLength(report.events.length),
      );
      for (final event in report.events)
        expect(event.details!['transferId'], id);
    }
    final audits = DatabaseCore.auditLogBox!.values
        .whereType<Map>()
        .where((v) => v['action'] != null)
        .map((v) => AuditEventLog.fromMap(Map<String, dynamic>.from(v)))
        .toList();
    expect(audits, hasLength(1));
    expect(audits.single.data['previousStatus'], 'in-progress');
    expect(audits.single.data['transferId'], id);
    expect(audits.single.entityId, 'booking');
    expect(OrderTransferJournalRepository.read(id)!.pending, false);
    expect(LocalDataAdmission.failure, isNull);
    return {
      'status': 'PASS',
      'pid': pid,
      'transferId': id,
      'venueQuantity': 5,
      'venueFrozenValueCents': 1251,
      'moveAuditCount': 2,
      'transferCloseCount': 1,
      'reservationAuditCount': 1,
      'noSaleCreated': true,
      'historicalSaleUnchanged': true,
      'identitiesPreserved': true,
      'allRealHttpBlocked': true,
      'journalPhase': 'completed',
    };
  }
}
