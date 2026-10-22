import 'package:vynic/core/models/table_ref.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/activate_reservation_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_reservation_advance_');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'lastOrderId': 0,
      'serviceFeeEnabled': false,
    });
    await DatabaseCore.tableBox!.put(
      'first-1',
      TableModel(tableNumber: '1', floor: 'first'),
    );
  });
  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    await dir.delete(recursive: true);
  });
  Future<String> booking({
    String id = 'synthetic-booking',
    String status = 'confirmed',
    double advance = 6,
  }) => ReservationRepository.createReservation(
    id: id,
    customerName: 'Synthetic guest',
    customerPhone: '555000000',
    tableRefs: const [TableRef(floor: 'first', tableNumber: '1')],
    reservationDate: DateTime(2026, 10, 17),
    reservationTime: '18:00',
    numberOfGuests: 2,
    createdBy: 'synthetic',
    status: status,
    advanceAmount: advance,
    preOrderItems: [
      OrderItem(
        itemKey: 'synthetic',
        itemName: 'Synthetic meal',
        unitPrice: 10,
        quantity: 1,
        total: 10,
      ),
    ],
  );
  test(
    'receipt dated on collection day; seating and repeated settlement apply advance once',
    () async {
      final id = await booking();
      await booking();
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      expect(DatabaseCore.salesBox!.values, hasLength(1));
      expect(BusinessDayRepository.grossSalesTotalForDate('2026-10-15'), 0);
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-17T00:00:00.000',
      );
      final first = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      final again = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      expect(first.orderId, again.orderId);
      final order = OrderRepository.getOrder(first.orderId!)!;
      expect(order.advanceAmount, 6);
      expect(order.totalAmount, 4);
      Future<dynamic> close() => CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 4),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 4},
        closedById: 'synthetic',
        isFiscal: true,
        expectedOrder: OrderTableMutationRepository.capture(order),
      );
      expect((await close()).isSuccess, isTrue);
      expect((await close()).isSuccess, isTrue);
      expect(DatabaseCore.salesBox!.values, hasLength(2));
      expect(BusinessDayRepository.grossSalesTotalForDate('2026-10-17'), 10);
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-17'), 4);
      final receipt = SalesRepository.findAdvanceReceipt(
        order.advanceReceiptId!,
      )!;
      expect(receipt['appliedToClosureId'], isNotNull);
      expect(
        ReservationRepository.getReservation(id)!.statusEnum,
        ReservationStatus.completed,
      );
    },
  );
  test(
    'crash after flushed reservation intent recovers one receipt across Hive reopen',
    () async {
      fixture.fault = (point, _) async {
        if (point == 'reservations.flush:after')
          throw StateError('synthetic interruption');
      };
      await expectLater(booking(id: 'crash'), throwsStateError);
      fixture.fault = null;
      expect(
        DatabaseCore.reservationBox!.values.single.advanceReceiptPending,
        isTrue,
      );
      await fixture.close();
      await fixture.open(dir.path);
      await ReservationRepository.recoverAdvanceReceipts();
      await ReservationRepository.recoverAdvanceReceipts();
      expect(
        DatabaseCore.reservationBox!.values.single.advanceReceiptPending,
        isFalse,
      );
      expect(DatabaseCore.salesBox!.values, hasLength(1));
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
    },
  );
  test(
    'hold remains distinct, blocks future availability and cannot auto-seat',
    () async {
      final id = await booking(status: 'hold', advance: 0);
      expect(
        ReservationTableAvailability.isReservationBlocking('hold'),
        isTrue,
      );
      final refused = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      expect(refused.isSuccess, isFalse);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-17T00:00:00.000',
      );
      await ActivateReservationTransaction.activateTodaysReservations();
      expect(DatabaseCore.orderBox!.values, isEmpty);
      await ReservationRepository.updateReservationStatus(id, 'confirmed');
      final admitted = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      expect(admitted.isSuccess, isTrue);
    },
  );
  test(
    'new advance survives reservation backup projection and restore',
    () async {
      final id = await booking();
      final data = BackupRepository.serializeReservationForSync(
        ReservationRepository.getReservation(id)!,
      );
      await BackupRepository.replaceReservationsFromJson([data]);
      final restored = ReservationRepository.getReservation(id)!;
      expect(restored.advanceAmount, 6);
      expect(restored.advanceCollectedOn, '2026-10-15');
      expect(restored.advanceReceiptId, 'reservation:$id:advance');
      await ReservationRepository.ensureAdvanceReceipt(restored);
      expect(DatabaseCore.salesBox!.values, hasLength(1));
    },
  );
  test(
    'format2 fresh restore finishes a pending advance intent before admitting writes',
    () async {
      fixture.fault = (point, _) async {
        if (point == 'reservations.flush:after')
          throw StateError('synthetic interrupted receipt');
      };
      await expectLater(booking(id: 'pending-restore'), throwsStateError);
      fixture.fault = null;
      final backup = await BackupRepository.createDataBackup(
        targetFilePath: '${dir.path}/portable.json',
      );
      final payload = await backup.readAsString();
      await fixture.close();
      final restoredDir = await Directory('${dir.path}/restored').create();
      await fixture.open(restoredDir.path);
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      expect(
        ReservationRepository.getReservation(
          'pending-restore',
        )!.advanceReceiptPending,
        isFalse,
      );
      expect(DatabaseCore.salesBox!.values, hasLength(1));
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      expect(DatabaseCore.salesBox!.values, hasLength(1));
    },
  );
  test(
    'cancel preserves collected funds; deletion and rewriting received advance are refused',
    () async {
      final id = await booking();
      await ReservationRepository.updateReservationStatus(id, 'cancelled');
      await expectLater(
        ReservationRepository.deleteReservation(id),
        throwsStateError,
      );
      await expectLater(
        SalesRepository.recordAdvanceReceipt(
          orderId: null,
          reservationId: id,
          amount: 0,
          collectedBy: 'synthetic',
          receiptId: 'reservation:$id:advance',
        ),
        throwsStateError,
      );
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
    },
  );
  for (final replacement in [12.0, 3.0, 0.0]) {
    test(
      'posted reservation advance cannot be overwritten with $replacement',
      () async {
        final id = await booking();
        await expectLater(
          SalesRepository.recordAdvanceReceipt(
            orderId: null,
            reservationId: id,
            amount: replacement,
            collectedBy: 'synthetic',
            receiptId: 'reservation:$id:advance',
          ),
          throwsStateError,
        );
        await ReservationRepository.updateReservationDetails(
          id,
          customerName: 'Edited guest',
          actorId: 'synthetic',
        );
        expect(ReservationRepository.getReservation(id)!.advanceAmount, 6);
        expect(
          SalesRepository.findAdvanceReceipt(
            'reservation:$id:advance',
          )!['totalAmount'],
          6,
        );
        expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
        await DatabaseCore.reservationBox!.flush();
        final boxName = DatabaseCore.reservationBox!.name;
        await DatabaseCore.reservationBox!.close();
        DatabaseCore.reservationBox = await Hive.openBox<Reservation>(boxName);
        expect(ReservationRepository.getReservation(id)!.advanceAmount, 6);
      },
    );
  }

  test(
    'concurrent identical booking requests persist one booking and receipt',
    () async {
      final ids = await Future.wait([
        booking(id: 'concurrent'),
        booking(id: 'concurrent'),
      ]);
      expect(ids, ['concurrent', 'concurrent']);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      expect(DatabaseCore.salesBox!.values, hasLength(1));
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 6);
    },
  );
  test(
    'fully prepaid booking closes with zero new collection and cannot reuse its receipt',
    () async {
      final id = await booking(advance: 10);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-17T00:00:00.000',
      );
      final activation = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      final order = OrderRepository.getOrder(activation.orderId!)!;
      expect(order.totalAmount, 0);
      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 0),
        paymentMethod: 'cash',
        tenderBreakdown: const {},
        closedById: 'synthetic',
        isFiscal: true,
        expectedOrder: OrderTableMutationRepository.capture(order),
      );
      expect(result.isSuccess, isTrue);
      expect(BusinessDayRepository.grossSalesTotalForDate('2026-10-17'), 10);
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-17'), 0);
      final other = Order(
        orderId: 999,
        tableNumbers: const [],
        floor: 'takeaway',
        items: order.items,
        totalAmount: 0,
        createdAt: order.createdAt,
        createdBy: 'synthetic',
        status: 'confirmed',
        advanceAmount: 10,
        advanceCollectedOn: order.advanceCollectedOn,
        advanceReceiptId: order.advanceReceiptId,
      );
      await DatabaseCore.orderBox!.put(999, other);
      final refused = await CloseTableTransaction.run(
        orderId: 999,
        money: ClosureMoney.fromOrder(other, collectedNow: 0),
        paymentMethod: 'cash',
        tenderBreakdown: const {},
        closedById: 'synthetic',
        isFiscal: true,
      );
      expect(refused.isSuccess, isFalse);
      expect(DatabaseCore.salesBox!.values, hasLength(2));
    },
  );
  test(
    'excess advance refuses settlement while retaining the original cash receipt',
    () async {
      final id = await booking(advance: 12);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-17T00:00:00.000',
      );
      final activation = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'synthetic',
      );
      final order = OrderRepository.getOrder(activation.orderId!)!;
      expect(order.totalAmount, 0); // The existing UI total clamps at zero.
      expect(ClosureMoney.fromOrder(order, collectedNow: 0).amountDueNow, -2);
      final refused = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 0),
        paymentMethod: 'cash',
        tenderBreakdown: const {},
        closedById: 'synthetic',
        isFiscal: true,
      );
      expect(refused.isSuccess, isFalse);
      expect(DatabaseCore.salesBox!.values, hasLength(1));
      expect(OrderRepository.getOrder(order.orderId)!.status, isNot('closed'));
      expect(BusinessDayRepository.collectedTotalForDate('2026-10-15'), 12);
    },
  );
  test(
    'holds refuse same-day time variants, conflicting creates and conflicting date changes',
    () async {
      await expectLater(
        ReservationRepository.createReservation(
          id: 'same-day',
          customerName: 'Synthetic',
          customerPhone: '',
          tableRefs: const [TableRef(floor: 'first', tableNumber: '1')],
          reservationDate: DateTime(2026, 10, 15, 23),
          reservationTime: '23:00',
          numberOfGuests: 2,
          createdBy: 'synthetic',
          status: 'hold',
        ),
        throwsArgumentError,
      );
      await booking(id: 'hold', status: 'hold', advance: 0);
      await expectLater(booking(id: 'conflict', advance: 0), throwsStateError);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      await ReservationRepository.createReservation(
        id: 'other-day',
        customerName: 'Synthetic',
        customerPhone: '',
        tableRefs: const [TableRef(floor: 'first', tableNumber: '1')],
        reservationDate: DateTime(2026, 10, 18),
        reservationTime: '18:00',
        numberOfGuests: 2,
        createdBy: 'synthetic',
        status: 'confirmed',
      );
      await expectLater(
        ReservationRepository.updateReservationDetails(
          'hold',
          reservationDate: DateTime(2026, 10, 18),
        ),
        throwsStateError,
      );
      expect(
        ReservationRepository.getReservation('hold')!.reservationDate,
        DateTime(2026, 10, 17),
      );
      await ReservationRepository.updateReservationStatus('hold', 'cancelled');
      await booking(id: 'released', advance: 0);
      expect(ReservationRepository.getReservation('released'), isNotNull);
    },
  );
  test(
    'overdue hold stays visible and requires a new date before confirmation',
    () async {
      await booking(id: 'overdue', status: 'hold', advance: 0);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-18T00:00:00.000',
      );
      await expectLater(
        ReservationRepository.updateReservationStatus('overdue', 'confirmed'),
        throwsStateError,
      );
      expect(ReservationRepository.getReservation('overdue')!.status, 'hold');
      await ReservationRepository.updateReservationDetails(
        'overdue',
        reservationDate: DateTime(2026, 10, 19),
      );
      await ReservationRepository.updateReservationStatus(
        'overdue',
        'confirmed',
      );
      expect(
        ReservationRepository.getReservation('overdue')!.status,
        'confirmed',
      );
    },
  );
  test(
    'legacy Hive reservation bytes reopen with safe zero advance defaults',
    () async {
      Hive.registerAdapter<Reservation>(
        _LegacyReservationAdapter(),
        override: true,
      );
      await booking(id: 'legacy', advance: 0);
      await fixture.close();
      Hive.registerAdapter<Reservation>(ReservationAdapter(), override: true);
      await fixture.open(dir.path);
      final old = ReservationRepository.getReservation('legacy')!;
      expect(old.customerName, 'Synthetic guest');
      expect(old.status, 'confirmed');
      expect(old.advanceAmount, 0);
      expect(old.advanceReceiptId, isNull);
      expect(old.advanceReceiptPending, isFalse);
    },
  );
}

class _LegacyReservationAdapter extends TypeAdapter<Reservation> {
  @override
  int get typeId => 9;
  @override
  Reservation read(BinaryReader reader) =>
      throw UnsupportedError('write legacy proof only');
  @override
  void write(BinaryWriter writer, Reservation r) {
    final fields = [
      r.id,
      r.customerName,
      r.customerPhone,
      r.tableNumbers,
      r.reservationDate,
      r.reservationTime,
      r.numberOfGuests,
      r.notes,
      r.createdAt,
      r.createdBy,
      r.status,
      r.preOrderItems,
      r.isTakeAway,
      r.linkedOrderId,
      r.tableRefs,
    ];
    writer.writeByte(fields.length);
    for (var i = 0; i < fields.length; i++) {
      writer.writeByte(i);
      writer.write(fields[i]);
    }
  }
}
