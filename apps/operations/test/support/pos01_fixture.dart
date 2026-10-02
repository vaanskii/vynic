import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'menu01_fixture.dart' show openMenu01, closeMenu01, Menu01NoHttp;
export 'menu01_fixture.dart' show Menu01NoHttp;

class Pos01Box<T> extends UpdateTrackedBox<T> {
  Pos01Box(super.inner, this.nameInProof, this.boundary);
  final String nameInProof;
  final Future<void> Function(String) boundary;
  String _key(Object? key, Object? value) =>
      nameInProof == 'meta' && value is Map && value['phase'] != null
      ? '$key:${value['phase']}'
      : nameInProof == 'audit'
      ? 'event'
      : '$key';
  Future<R> _io<R>(String point, Future<R> Function() action) async {
    await boundary('$nameInProof.$point:before');
    final result = await action();
    await boundary('$nameInProof.$point:after');
    return result;
  }

  @override
  Future<void> put(dynamic key, T value) =>
      _io('put:${_key(key, value)}', () => super.put(key, value));
  @override
  Future<void> delete(dynamic key) =>
      _io('delete:$key', () => super.delete(key));
  @override
  Future<void> flush() => _io('flush', super.flush);
}

class Pos01Fixture {
  final List<String> trace = [];
  Future<void> Function(String, int)? fault;
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
    if (instrument) wrap();
  }

  void wrap() {
    DatabaseCore.metaBox = Pos01Box(DatabaseCore.metaBox!, 'meta', boundary);
    DatabaseCore.settingsBox = Pos01Box(
      DatabaseCore.settingsBox!,
      'settings',
      boundary,
    );
    DatabaseCore.orderBox = Pos01Box(
      DatabaseCore.orderBox!,
      'orders',
      boundary,
    );
    DatabaseCore.tableBox = Pos01Box(
      DatabaseCore.tableBox!,
      'tables',
      boundary,
    );
    DatabaseCore.reservationBox = Pos01Box(
      DatabaseCore.reservationBox!,
      'reservations',
      boundary,
    );
    DatabaseCore.auditLogBox = Pos01Box(
      DatabaseCore.auditLogBox!,
      'audit',
      boundary,
    );
  }

  Future<void> seed() async {
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-01T00:00:00.000',
      'dailySalesTotal': 70.0,
      'lastOrderId': 7,
      'serviceFeePercent': 0.0,
      'serviceFeeEnabled': false,
    });
    Order order(int id, String status, String date) => Order(
      orderId: id,
      tableNumbers: ['$id'],
      floor: 'first',
      items: [
        OrderItem(
          itemKey: 'captured',
          itemName: 'Captured',
          unitPrice: 7,
          quantity: 2,
          total: 14,
        ),
      ],
      totalAmount: 14,
      createdAt: DateTime.parse(date),
      createdBy: 'synthetic',
      status: status,
      includeServiceFee: false,
    );
    await DatabaseCore.orderBox!.put(
      'closed',
      order(1, 'closed', '2026-10-01'),
    );
    await DatabaseCore.orderBox!.put(
      'cancelled',
      order(2, 'cancelled', '2026-10-01'),
    );
    // Preserve an old operational Order row, matching existing archive semantics.
    await DatabaseCore.orderBox!.put(
      'older-active',
      order(3, 'confirmed', '2026-09-30'),
    );
    await DatabaseCore.tableBox!.put(
      'stale',
      TableModel(
        tableNumber: '1',
        floor: 'first',
        isReserved: true,
        activeOrderId: 1,
        reservedBy: 'synthetic',
        reservedAt: DateTime.parse('2026-10-01'),
      ),
    );
    await DatabaseCore.tableBox!.put(
      'free',
      TableModel(tableNumber: '4', floor: 'first'),
    );
    Reservation reservation(String id, String status, String date, int? link) =>
        Reservation(
          id: id,
          customerName: 'Synthetic $id',
          customerPhone: 'synthetic',
          tableNumbers: [1],
          reservationDate: DateTime.parse(date),
          reservationTime: '18:00',
          numberOfGuests: 2,
          createdAt: DateTime.parse('2026-09-30'),
          createdBy: 'synthetic',
          status: status,
          linkedOrderId: link,
        );
    await DatabaseCore.reservationBox!.put(
      'seated',
      reservation('seated', 'in-progress', '2026-10-01', 1),
    );
    await DatabaseCore.reservationBox!.put(
      'missed',
      reservation('missed', 'confirmed', '2026-10-01', null),
    );
    await DatabaseCore.reservationBox!.put(
      'final',
      reservation('final', 'completed', '2026-10-01', 1),
    );
    await DatabaseCore.reservationBox!.put(
      'future',
      reservation('future', 'confirmed', '2026-10-03', null),
    );
    await DatabaseCore.salesBox!.put('history', {
      'orderId': 1,
      'posSaleId': 'synthetic-historical-sale',
      'recordType': 'sale',
      'date': '2026-10-01',
      'createdAt': '2026-10-01T10:00:00.000',
      'closedAt': '2026-10-01T11:00:00.000',
      'totalAmount': 70.0,
      'grossSaleAmount': 70.0,
      'collectedNow': 70.0,
      'isFiscal': true,
      'items': [],
    });
    for (final box in [
      DatabaseCore.metaBox!,
      DatabaseCore.settingsBox!,
      DatabaseCore.orderBox!,
      DatabaseCore.tableBox!,
      DatabaseCore.reservationBox!,
      DatabaseCore.salesBox!,
    ])
      await box.flush();
    trace.clear();
  }

  Future<void> close() async {
    fault = null;
    await closeMenu01();
    LocalDataAdmission.failure = null;
    UpdateReadiness.failure = null;
    Order.timestampResolver = null;
    Order.serviceFeeRateResolver = null;
  }

  List<AuditEventLog> get audits => DatabaseCore.auditLogBox!.values
      .whereType<Map>()
      .where((row) => row['action'] != null)
      .map((row) => AuditEventLog.fromMap(Map<String, dynamic>.from(row)))
      .toList();
  Map<String, Object?> verify({String? transitionId}) {
    expect(
      BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
      '2026-10-02',
    );
    expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 0.0);
    expect(DatabaseCore.orderBox!.get('closed'), isNull);
    expect(DatabaseCore.orderBox!.get('cancelled')!.status, 'cancelled');
    expect(DatabaseCore.orderBox!.get('older-active')!.status, 'confirmed');
    expect(DatabaseCore.tableBox!.get('stale')!.activeOrderId, isNull);
    expect(DatabaseCore.tableBox!.get('stale')!.isReserved, false);
    expect(DatabaseCore.reservationBox!.get('seated')!.status, 'completed');
    expect(DatabaseCore.reservationBox!.get('missed')!.status, 'no-show');
    expect(DatabaseCore.reservationBox!.get('final')!.linkedOrderId, isNull);
    expect(DatabaseCore.reservationBox!.get('future')!.status, 'confirmed');
    expect(DatabaseCore.salesBox!.get('history')['totalAmount'], 70.0);
    expect(
      BusinessDayRepository.getOperatedBusinessDateKeys().where(
        (d) => d == '2026-10-01',
      ),
      hasLength(1),
    );
    final intent = CloseDayJournalRepository.read()!;
    expect(intent.phase, CloseDayPhase.completed);
    if (transitionId != null) expect(intent.id, transitionId);
    final completed = audits
        .where((e) => e.action == GlobalAuditAction.closeDayCompleted)
        .single;
    expect(completed.entityId, '2026-10-01');
    expect(completed.data['ordersArchived'], 1);
    expect(
      completed.data['tablesFreed'],
      0,
    ); // Existing stale cleanup is separate.
    expect(completed.data['reservationsCompleted'], 1);
    expect(completed.data['reservationsNoShow'], 1);
    expect(
      audits.where((e) => e.action == ReservationAuditAction.complete),
      hasLength(1),
    );
    expect(
      audits.where((e) => e.action == ReservationAuditAction.noShow),
      hasLength(1),
    );
    expect(audits.map((e) => e.id).toSet(), hasLength(audits.length));
    expect(LocalDataAdmission.failure, isNull);
    return {
      'status': 'PASS',
      'pid': pid,
      'transitionId': intent.id,
      'businessDate': '2026-10-02',
      'dateAdvanceCount': 1,
      'auditCount': audits.length,
      'activeAndCancelledOrdersPreserved': true,
      'historicalSalePreserved': true,
      'reservationPreStatusPreserved': audits
          .firstWhere((e) => e.action == ReservationAuditAction.complete)
          .data['previousStatus'],
      'allRealHttpBlocked': true,
      'journalPhase': intent.phase.name,
    };
  }
}
