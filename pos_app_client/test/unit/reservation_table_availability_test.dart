// Characterization tests for [ReservationTableAvailability].
//
// Locks the CURRENT reservation/table-relation logic before any refactor:
// table-code encoding, time-slot overlap, which reservations block a table,
// and which bookings count as "real" table bookings vs. order/takeaway-linked.
// These are pure functions over the Reservation/TableModel models — no Hive,
// no I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

Reservation _reservation({
  String id = 'r1',
  List<int> tableNumbers = const [1],
  String status = 'confirmed',
  String? notes,
  bool isTakeAway = false,
  int? linkedOrderId,
}) {
  return Reservation(
    id: id,
    customerName: 'Test',
    customerPhone: '000',
    tableNumbers: tableNumbers,
    reservationDate: DateTime(2026, 6, 24),
    reservationTime: '19:00',
    numberOfGuests: 2,
    notes: notes,
    createdAt: DateTime(2026, 6, 24),
    createdBy: 'tester',
    status: status,
    isTakeAway: isTakeAway,
    linkedOrderId: linkedOrderId,
  );
}

void main() {
  group('table code encoding', () {
    test('first floor keeps the raw number; second floor offsets by 10', () {
      expect(
        ReservationTableAvailability.encodeTableCode(
          floor: 'first',
          tableNumber: '3',
        ),
        3,
      );
      expect(
        ReservationTableAvailability.encodeTableCode(
          floor: 'second',
          tableNumber: '3',
        ),
        13,
      );
    });

    test('decode is the inverse of encode', () {
      final firstFloor = ReservationTableAvailability.decodeTableCode(3);
      expect(firstFloor.floor, 'first');
      expect(firstFloor.tableNumber, '3');

      final secondFloor = ReservationTableAvailability.decodeTableCode(13);
      expect(secondFloor.floor, 'second');
      expect(secondFloor.tableNumber, '3');
    });

    test('encodeFloorSelection returns sorted codes', () {
      expect(
        ReservationTableAvailability.encodeFloorSelection(
          floor: 'first',
          tableNumbers: ['5', '1', '3'],
        ),
        [1, 3, 5],
      );
    });

    test('encodeTableCode throws on non-numeric table', () {
      expect(
        () => ReservationTableAvailability.encodeTableCode(
          floor: 'first',
          tableNumber: 'abc',
        ),
        throwsArgumentError,
      );
    });

    test('encodeTableCode throws instead of encoding a colliding code', () {
      // first/12 would encode to 12, which decodes as second/2.
      expect(
        () => ReservationTableAvailability.encodeTableCode(
          floor: 'first',
          tableNumber: '12',
        ),
        throwsArgumentError,
      );
      // Unknown floors have no representation in the int encoding.
      expect(
        () => ReservationTableAvailability.encodeTableCode(
          floor: 'floor-3',
          tableNumber: '1',
        ),
        throwsArgumentError,
      );
      // Second floor round-trips at any number.
      expect(
        ReservationTableAvailability.encodeTableCode(
          floor: 'second',
          tableNumber: '12',
        ),
        22,
      );
    });

    test('canEncodeTableCode mirrors what encodeTableCode accepts', () {
      bool can(String floor, String number) =>
          ReservationTableAvailability.canEncodeTableCode(
            floor: floor,
            tableNumber: number,
          );
      expect(can('first', '10'), isTrue);
      expect(can('first', '11'), isFalse);
      expect(can('second', '11'), isTrue);
      expect(can('floor-3', '1'), isFalse);
      expect(can('first', 'abc'), isFalse);
    });

    test('displayTableNumber strips the offset only for encoded values', () {
      expect(
        ReservationTableAvailability.displayTableNumber(13, floorHint: null),
        '3',
      );
      expect(
        ReservationTableAvailability.displayTableNumber(
          13,
          floorHint: 'second',
        ),
        '3',
      );
      // An explicit non-'second' floor means the value is an API-plain
      // number, not an encoded code.
      expect(
        ReservationTableAvailability.displayTableNumber(12, floorHint: 'first'),
        '12',
      );
    });
  });

  group('reservationTimesOverlap (120-minute slots)', () {
    test('times within 2 hours overlap', () {
      expect(
        ReservationTableAvailability.reservationTimesOverlap('19:00', '20:30'),
        isTrue,
      );
    });

    test('times exactly 2 hours apart do not overlap', () {
      expect(
        ReservationTableAvailability.reservationTimesOverlap('19:00', '21:00'),
        isFalse,
      );
    });

    test('malformed time returns false', () {
      expect(
        ReservationTableAvailability.reservationTimesOverlap('19', '20:00'),
        isFalse,
      );
    });
  });

  group('isReservationBlocking', () {
    test('active statuses block', () {
      expect(
        ReservationTableAvailability.isReservationBlocking('confirmed'),
        isTrue,
      );
      expect(
        ReservationTableAvailability.isReservationBlocking('pending'),
        isTrue,
      );
      expect(ReservationTableAvailability.isReservationBlocking(null), isTrue);
    });

    test('cancelled/completed variants do not block', () {
      for (final s in [
        'cancelled',
        'canceled',
        'completed',
        'CANCELLED',
        'cancelled_by_user',
        'completed-late',
      ]) {
        expect(
          ReservationTableAvailability.isReservationBlocking(s),
          isFalse,
          reason: 'status "$s" should not block',
        );
      }
    });
  });

  group('isRealTableBooking', () {
    test('plain dine-in booking is real', () {
      expect(
        ReservationTableAvailability.isRealTableBooking(_reservation()),
        isTrue,
      );
    });

    test('takeaway, order-linked, and "Order #" notes are not real', () {
      expect(
        ReservationTableAvailability.isRealTableBooking(
          _reservation(isTakeAway: true),
        ),
        isFalse,
      );
      expect(
        ReservationTableAvailability.isRealTableBooking(
          _reservation(linkedOrderId: 7),
        ),
        isFalse,
      );
      expect(
        ReservationTableAvailability.isRealTableBooking(
          _reservation(notes: 'Order #42 walk-in'),
        ),
        isFalse,
      );
    });

    test('API-shaped equivalent matches model behavior', () {
      expect(
        ReservationTableAvailability.isRealTableBookingFromApi({
          'isTakeAway': false,
          'linkedOrderId': null,
          'notes': 'birthday',
        }),
        isTrue,
      );
      expect(
        ReservationTableAvailability.isRealTableBookingFromApi({
          'notes': 'Order #5',
        }),
        isFalse,
      );
    });
  });

  group('unavailableTableCodesFromReservations', () {
    test('collects codes from blocking real bookings only', () {
      final result =
          ReservationTableAvailability.unavailableTableCodesFromReservations(
            reservations: [
              _reservation(id: 'a', tableNumbers: [1, 2]),
              _reservation(id: 'b', tableNumbers: [3], status: 'cancelled'),
              _reservation(id: 'c', tableNumbers: [4], isTakeAway: true),
              _reservation(id: 'd', tableNumbers: [5], linkedOrderId: 9),
            ],
          );
      expect(result, {1, 2});
    });

    test('excludes the reservation being edited', () {
      final result =
          ReservationTableAvailability.unavailableTableCodesFromReservations(
            reservations: [
              _reservation(id: 'a', tableNumbers: [1]),
              _reservation(id: 'edit-me', tableNumbers: [2]),
            ],
            excludeReservationId: 'edit-me',
          );
      expect(result, {1});
    });
  });

  group('areTableCodesAvailable', () {
    final reservations = [
      _reservation(id: 'a', tableNumbers: [1, 2]),
    ];

    test('empty selection is always available', () {
      expect(
        ReservationTableAvailability.areTableCodesAvailable(
          tableCodes: [],
          reservations: reservations,
        ),
        isTrue,
      );
    });

    test('free table is available; booked table is not', () {
      expect(
        ReservationTableAvailability.areTableCodesAvailable(
          tableCodes: [3],
          reservations: reservations,
        ),
        isTrue,
      );
      expect(
        ReservationTableAvailability.areTableCodesAvailable(
          tableCodes: [1],
          reservations: reservations,
        ),
        isFalse,
      );
    });
  });

  group('table model helpers', () {
    test('isTableModelAvailable encodes floor before checking', () {
      final secondFloorTable = TableModel(tableNumber: '1', floor: 'second');
      // code 11 is free, code 1 is taken
      expect(
        ReservationTableAvailability.isTableModelAvailable(
          table: secondFloorTable,
          unavailableCodes: {1},
        ),
        isTrue,
      );
      expect(
        ReservationTableAvailability.isTableModelAvailable(
          table: secondFloorTable,
          unavailableCodes: {11},
        ),
        isFalse,
      );
    });

    test('unavailableTableCodesFromLiveTables blocks reserved/ordered '
        'tables', () {
      final tables = [
        // Free table — not blocked.
        TableModel(tableNumber: '1', floor: 'first'),
        // Walk-in order lock — blocked.
        TableModel(
          tableNumber: '3',
          floor: 'first',
          isReserved: true,
          activeOrderId: 101,
        ),
        // Stale reservation lock (no order) — blocked.
        TableModel(
          tableNumber: '4',
          floor: 'first',
          isReserved: true,
          reservationId: 'res-other',
        ),
        // Second-floor lock — blocked with encoded code (+10).
        TableModel(tableNumber: '2', floor: 'second', isReserved: true),
      ];

      expect(
        ReservationTableAvailability.unavailableTableCodesFromLiveTables(
          tables: tables,
        ),
        {3, 4, 12},
      );
    });

    test(
      "unavailableTableCodesFromLiveTables skips the reservation's own tables",
      () {
        final tables = [
          TableModel(
            tableNumber: '3',
            floor: 'first',
            isReserved: true,
            reservationId: 'res-self',
          ),
          TableModel(
            tableNumber: '4',
            floor: 'first',
            isReserved: true,
            activeOrderId: 55,
          ),
          TableModel(
            tableNumber: '5',
            floor: 'first',
            isReserved: true,
            reservationId: 'res-other',
          ),
        ];

        expect(
          ReservationTableAvailability.unavailableTableCodesFromLiveTables(
            tables: tables,
            excludeReservationId: 'res-self',
            excludeOrderId: 55,
          ),
          {5},
        );
      },
    );

    test('unavailableTableCodesFromLiveTables skips non-numeric table '
        'numbers', () {
      expect(
        ReservationTableAvailability.unavailableTableCodesFromLiveTables(
          tables: [
            TableModel(tableNumber: 'bar', floor: 'first', isReserved: true),
          ],
        ),
        isEmpty,
      );
    });

    test('sortTables orders by floor then numeric table number', () {
      final sorted = ReservationTableAvailability.sortTables([
        TableModel(tableNumber: '10', floor: 'first'),
        TableModel(tableNumber: '2', floor: 'first'),
        TableModel(tableNumber: '1', floor: 'second'),
      ]);
      expect(sorted.map((t) => '${t.floor}-${t.tableNumber}').toList(), [
        'first-2',
        'first-10',
        'second-1',
      ]);
    });
  });
}
