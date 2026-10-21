import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table_ref.dart';

import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  final date = DateTime(2026, 10, 18);
  const ref = TableRef(floor: 'first', tableNumber: '1');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reservation_admission_');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-15T00:00:00.000',
    );
  });
  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    await dir.delete(recursive: true);
  });

  Future<String> create(
    String id, {
    String status = 'confirmed',
    DateTime? on,
    List<TableRef> refs = const [ref],
    double advance = 0,
  }) => ReservationRepository.createReservation(
    id: id,
    customerName: 'Synthetic guest',
    customerPhone: '',
    tableRefs: refs,
    reservationDate: on ?? date,
    reservationTime: '18:00',
    numberOfGuests: 2,
    createdBy: 'synthetic',
    status: status,
    advanceAmount: advance,
    requireDurability: true,
  );

  Future<String> remote(String id, {String time = '18:00'}) =>
      BackupRepository.createReservationFromJson({
        'id': id,
        'customerName': 'Manager guest',
        'customerPhone': '',
        'tableNumbers': [1],
        'reservationDate': '2026-10-18',
        'reservationTime': time,
        'numberOfGuests': 2,
        'createdBy': 'synthetic-manager',
        'status': 'confirmed',
      }, requireDurability: true);

  test('distinct queued Manager requests cannot both book a table, even at different times', () async {
    await remote('manager-request-one');
    final auditBefore = DatabaseCore.auditLogBox!.toMap();
    await expectLater(remote('manager-request-two', time: '22:00'), throwsStateError);

    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    expect(DatabaseCore.reservationBox!.values.single.id, 'manager-request-one');
    expect(DatabaseCore.auditLogBox!.toMap(), auditBefore);
    expect(DatabaseCore.salesBox!.values, isEmpty);
  });

  test('concurrent distinct requests serialize the check with the first durable write', () async {
    Future<Object> result(String id) => remote(id).then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
    final results = await Future.wait([result('concurrent-one'), result('concurrent-two')]);
    expect(results.whereType<String>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    expect(DatabaseCore.reservationBox!.values, hasLength(1));

    await fixture.close();
    await fixture.open(dir.path);
    expect(DatabaseCore.reservationBox!.values.single.id, results.whereType<String>().single);
    await expectLater(remote('after-reopen'), throwsStateError);
  });

  for (final status in ['pending', 'preparing', 'confirmed', 'hold']) {
    test('$status booking blocks a second confirmed booking before receipt or audit writes', () async {
      await create('existing', status: status);
      final auditBefore = DatabaseCore.auditLogBox!.toMap();
      await expectLater(create('new-with-advance', advance: 5), throwsStateError);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      expect(DatabaseCore.salesBox!.values, isEmpty);
      expect(DatabaseCore.auditLogBox!.toMap(), auditBefore);
    });
  }

  test('same identity retry remains idempotent with its original receipt', () async {
    await create('same-request', advance: 5);
    final auditBefore = DatabaseCore.auditLogBox!.toMap();
    await create('same-request', advance: 5);
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    expect(DatabaseCore.salesBox!.values, hasLength(1));
    expect(DatabaseCore.auditLogBox!.toMap(), auditBefore);
  });

  for (final exclusion in ['cancelled', 'completed', 'takeaway', 'technical', 'activated']) {
    test('$exclusion historical row does not block a genuine unactivated booking', () async {
      final row = Reservation(
        id: 'historical',
        customerName: 'Synthetic',
        customerPhone: '',
        tableNumbers: [1],
        tableRefs: [ref.encode()],
        reservationDate: date,
        reservationTime: '18:00',
        numberOfGuests: 2,
        createdAt: DateTime(2026, 10, 15),
        createdBy: 'synthetic',
        status: ['cancelled', 'completed'].contains(exclusion) ? exclusion : 'confirmed',
        isTakeAway: exclusion == 'takeaway',
        notes: exclusion == 'technical' ? '  Order #123' : null,
        linkedOrderId: exclusion == 'activated' ? 123 : null,
      );
      await DatabaseCore.reservationBox!.put('historical', row);
      expect(await create('new-booking'), 'new-booking');
      expect(DatabaseCore.reservationBox!.values, hasLength(2));
    });
  }

  test('different dates, floors and unassigned tables remain independent', () async {
    await create('first');
    await create('another-day', on: DateTime(2026, 10, 19));
    await create('another-floor', refs: const [TableRef(floor: 'second', tableNumber: '1')]);
    await create('unassigned', refs: const []);
    expect(DatabaseCore.reservationBox!.values, hasLength(4));
  });

  test('date and table edits cannot collide with an existing confirmed booking', () async {
    await create('occupied');
    await create('other-day', on: DateTime(2026, 10, 19));
    await expectLater(
      ReservationRepository.updateReservationDetails('other-day', reservationDate: date),
      throwsStateError,
    );
    await create('other-table', refs: const [TableRef(floor: 'first', tableNumber: '2')]);
    await expectLater(
      ReservationRepository.updateReservationTables('other-table', [1]),
      throwsStateError,
    );
    expect(ReservationRepository.getReservation('other-day')!.reservationDate, DateTime(2026, 10, 19));
    expect(ReservationRepository.getReservation('other-table')!.tableNumbers, [2]);
  });

  test('reconfirming a cancelled booking cannot steal a reassigned table', () async {
    await create('cancelled', status: 'cancelled');
    await create('new-owner');
    await expectLater(
      ReservationRepository.updateReservationStatus('cancelled', 'confirmed'),
      throwsStateError,
    );
    expect(ReservationRepository.getReservation('cancelled')!.status, 'cancelled');
  });
}
