import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// A booking's identity.
///
/// New reservation ids used to be `DateTime.now().millisecondsSinceEpoch`.
/// Two bookings taken inside the same millisecond were handed the same id, and
/// from then on the system could not tell them apart — a collision that showed
/// up as an intermittent test failure and would show up in a restaurant as one
/// party losing its table.
void main() {
  late Directory tempDir;

  const boxes = [
    'rid_settings',
    'rid_audit',
    'rid_reservations',
    'rid_tables',
    'rid_orders',
    'rid_users',
  ];

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
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_reservation_id');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('rid_settings');
    DatabaseCore.auditLogBox = await Hive.openBox('rid_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('rid_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('rid_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('rid_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'rid_reservations',
    );
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-09-05T00:00:00.000',
    );
  });

  tearDown(() async {
    for (final name in boxes) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> create({String? id, String name = 'Tamar'}) {
    return ReservationRepository.createReservation(
      customerName: name,
      customerPhone: '555000111',
      tableRefs: const [],
      reservationDate: DateTime(2026, 9, 6),
      reservationTime: '19:00',
      numberOfGuests: 4,
      createdBy: 'nino',
      id: id,
    );
  }

  test('many bookings taken in the same instant all get distinct ids', () async {
    // Deliberately without any await between them: this loop runs inside one
    // clock millisecond on any machine that matters, which is exactly the
    // condition the old clock-derived id could not survive.
    final ids = <String>[];
    for (var i = 0; i < 200; i++) {
      ids.add(await create(name: 'Guest $i'));
    }

    expect(ids.toSet(), hasLength(200));
    expect(DatabaseCore.reservationBox!.length, 200);
    // Every booking is still reachable by its own id.
    for (final id in ids) {
      expect(ReservationRepository.findReservationById(id), isNotNull);
      expect(ReservationRepository.getReservation(id), isNotNull);
    }
  });

  test('an id supplied by Cloud is used exactly as given', () async {
    // Cloud owns the identity of a booking it originated: inventing a local one
    // would turn an at-least-once redelivery into a second booking.
    final id = await create(id: 'website-booking-7');
    expect(id, 'website-booking-7');
    expect(
      ReservationRepository.findReservationById('website-booking-7'),
      isNotNull,
    );
  });

  test('a historical numeric id keeps working', () async {
    // Ids are opaque; nothing parses one. A booking created before this change
    // is found by exactly the same lookups.
    final legacyId = await create(id: '1756000000111');
    expect(legacyId, '1756000000111');
    expect(ReservationRepository.getReservation('1756000000111'), isNotNull);
    expect(
      ReservationRepository.findReservationById('1756000000111'),
      isNotNull,
    );
  });

  test('ids survive a backup round trip unchanged', () async {
    final ids = [
      for (var i = 0; i < 3; i++) await create(name: 'Guest $i'),
      await create(id: '1756000000111'),
    ];

    final serialized = [
      for (final reservation in DatabaseCore.reservationBox!.values)
        BackupRepository.serializeReservationForSync(reservation),
    ];
    await DatabaseCore.reservationBox!.clear();
    await BackupRepository.replaceReservationsFromJson(serialized);

    expect(
      DatabaseCore.reservationBox!.values.map((r) => r.id).toSet(),
      ids.toSet(),
    );
  });
}
