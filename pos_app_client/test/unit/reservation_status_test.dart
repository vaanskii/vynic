// Tests for [ReservationStatus] parsing/mapping — the Phase 4 status-enum
// foundation. Locks in exact-match canonicalization, including both
// misspellings/variants seen in production data ('canceled', 'inprogress'
// without a hyphen). Does NOT test the fuzzy startsWith('confirmed') /
// startsWith('cancelled') tolerance still used in
// core/utils/home_reservations_helper.dart and two admin/reservation
// widgets — that tolerance was intentionally left unmigrated; see the
// Phase 4 report for why.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';

void main() {
  group('ReservationStatus.fromStorage', () {
    test('parses every canonical value', () {
      expect(
        ReservationStatus.fromStorage('pending'),
        ReservationStatus.pending,
      );
      expect(
        ReservationStatus.fromStorage('preparing'),
        ReservationStatus.preparing,
      );
      expect(
        ReservationStatus.fromStorage('confirmed'),
        ReservationStatus.confirmed,
      );
      expect(
        ReservationStatus.fromStorage('in-progress'),
        ReservationStatus.inProgress,
      );
      expect(
        ReservationStatus.fromStorage('completed'),
        ReservationStatus.completed,
      );
      expect(
        ReservationStatus.fromStorage('cancelled'),
        ReservationStatus.cancelled,
      );
      expect(
        ReservationStatus.fromStorage('no-show'),
        ReservationStatus.noShow,
      );
    });

    test('treats legacy "canceled" (single L) as cancelled', () {
      expect(
        ReservationStatus.fromStorage('canceled'),
        ReservationStatus.cancelled,
      );
    });

    test('accepts "inprogress" without a hyphen', () {
      expect(
        ReservationStatus.fromStorage('inprogress'),
        ReservationStatus.inProgress,
      );
    });

    test('accepts "noshow" without a hyphen', () {
      expect(ReservationStatus.fromStorage('noshow'), ReservationStatus.noShow);
    });

    test('normalizes underscores, whitespace, and case', () {
      expect(
        ReservationStatus.fromStorage('In_Progress'),
        ReservationStatus.inProgress,
      );
      expect(
        ReservationStatus.fromStorage('  CONFIRMED  '),
        ReservationStatus.confirmed,
      );
    });

    test('maps null and unrecognized values to unknown, not pending', () {
      expect(ReservationStatus.fromStorage(null), ReservationStatus.unknown);
      expect(ReservationStatus.fromStorage(''), ReservationStatus.unknown);
      expect(
        ReservationStatus.fromStorage('garbage'),
        ReservationStatus.unknown,
      );
    });
  });

  group('ReservationStatus.storageValue', () {
    test('round-trips every canonical value', () {
      for (final status in ReservationStatus.values) {
        if (status == ReservationStatus.unknown) continue;
        expect(ReservationStatus.fromStorage(status.storageValue), status);
      }
    });

    test('unknown has no storage representation', () {
      expect(() => ReservationStatus.unknown.storageValue, throwsStateError);
    });
  });

  group('ReservationStatus.isFinal', () {
    test('completed, cancelled, and no-show are final', () {
      expect(ReservationStatus.completed.isFinal, isTrue);
      expect(ReservationStatus.cancelled.isFinal, isTrue);
      expect(ReservationStatus.noShow.isFinal, isTrue);
    });

    test('legacy "canceled" spelling is final (via cancelled)', () {
      expect(ReservationStatus.fromStorage('canceled').isFinal, isTrue);
    });

    test('pending, preparing, confirmed, in-progress are not final', () {
      expect(ReservationStatus.pending.isFinal, isFalse);
      expect(ReservationStatus.preparing.isFinal, isFalse);
      expect(ReservationStatus.confirmed.isFinal, isFalse);
      expect(ReservationStatus.inProgress.isFinal, isFalse);
    });

    test('unknown is not final', () {
      expect(ReservationStatus.unknown.isFinal, isFalse);
    });
  });

  group('Reservation.statusEnum', () {
    Reservation buildReservation({String status = 'pending'}) => Reservation(
      id: 'r1',
      customerName: 'Test',
      customerPhone: '000',
      tableNumbers: const [1],
      reservationDate: DateTime(2026, 1, 1),
      reservationTime: '19:00',
      numberOfGuests: 2,
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'tester',
      status: status,
    );

    test('reads the raw string field through the enum', () {
      expect(
        buildReservation(status: 'in-progress').statusEnum,
        ReservationStatus.inProgress,
      );
    });

    test('writing the enum updates the raw string field', () {
      final reservation = buildReservation();
      reservation.statusEnum = ReservationStatus.completed;
      expect(reservation.status, 'completed');
    });
  });
}
