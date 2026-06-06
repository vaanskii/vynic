import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';

/// Shared reservation table encoding and availability checks.
///
/// Table blocking is based only on existing **reservation records** for the
/// chosen calendar day (not live walk-in / order occupancy on tables).
class ReservationTableAvailability {
  ReservationTableAvailability._();

  static const int slotDurationMinutes = 120;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static bool isSameCalendarDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Encodes floor + table number into reservation `tableNumbers` format.
  static int encodeTableCode({required String floor, required String tableNumber}) {
    final parsed = int.tryParse(tableNumber.trim());
    if (parsed == null) {
      throw ArgumentError('Invalid table number: $tableNumber');
    }
    if (floor == 'second') {
      return parsed + 10;
    }
    return parsed;
  }

  static ({String floor, String tableNumber}) decodeTableCode(int code) {
    if (code > 10) {
      return (floor: 'second', tableNumber: '${code - 10}');
    }
    return (floor: 'first', tableNumber: '$code');
  }

  static List<int> encodeFloorSelection({
    required String floor,
    required List<String> tableNumbers,
  }) {
    return tableNumbers
        .map((n) => encodeTableCode(floor: floor, tableNumber: n))
        .toList()
      ..sort();
  }

  static String floorLabel(String floor) =>
      floor == 'second' ? 'მე-2 სართული' : '1-ლი სართული';

  static String displayLabel({required String floor, required String tableNumber}) =>
      '${floorLabel(floor)} • $tableNumber';

  static String formatTableCodes(List<int> codes) {
    if (codes.isEmpty) return '';
    return codes.map((code) {
      final decoded = decodeTableCode(code);
      return displayLabel(floor: decoded.floor, tableNumber: decoded.tableNumber);
    }).join(', ');
  }

  static bool reservationTimesOverlap(String time1, String time2) {
    final parts1 = time1.split(':');
    final parts2 = time2.split(':');
    if (parts1.length < 2 || parts2.length < 2) {
      return false;
    }

    final minutes1 = int.parse(parts1[0]) * 60 + int.parse(parts1[1]);
    final minutes2 = int.parse(parts2[0]) * 60 + int.parse(parts2[1]);

    return (minutes1 < minutes2 + slotDurationMinutes) &&
        (minutes2 < minutes1 + slotDurationMinutes);
  }

  static bool isReservationBlocking(String? status) {
    final normalized = (status ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('_', '-');
    return normalized != 'cancelled' &&
        normalized != 'canceled' &&
        normalized != 'completed' &&
        !normalized.startsWith('cancelled') &&
        !normalized.startsWith('canceled') &&
        !normalized.startsWith('completed');
  }

  static bool isRealTableBooking(Reservation reservation) {
    if (reservation.isTakeAway) {
      return false;
    }
    if (reservation.linkedOrderId != null) {
      return false;
    }
    final notes = reservation.notes?.trim() ?? '';
    if (notes.startsWith('Order #')) {
      return false;
    }
    return true;
  }

  static bool isRealTableBookingFromApi(Map<String, dynamic> reservation) {
    if (reservation['isTakeAway'] == true) {
      return false;
    }
    if (reservation['linkedOrderId'] != null) {
      return false;
    }
    final notes = reservation['notes']?.toString().trim() ?? '';
    if (notes.startsWith('Order #')) {
      return false;
    }
    return true;
  }

  /// Tables already assigned to other bookings on the same calendar day.
  static Set<int> unavailableTableCodesFromReservations({
    required Iterable<Reservation> reservations,
    String? excludeReservationId,
  }) {
    final unavailable = <int>{};
    for (final existing in reservations) {
      if (excludeReservationId != null && existing.id == excludeReservationId) {
        continue;
      }
      if (!isReservationBlocking(existing.status)) {
        continue;
      }
      if (!isRealTableBooking(existing)) {
        continue;
      }
      if (existing.tableNumbers.isEmpty) {
        continue;
      }
      unavailable.addAll(existing.tableNumbers);
    }
    return unavailable;
  }

  static Set<int> unavailableTableCodesFromApiReservations({
    required Iterable<Map<String, dynamic>> reservations,
    String? excludeReservationId,
  }) {
    final unavailable = <int>{};
    for (final existing in reservations) {
      final id = existing['id']?.toString();
      if (excludeReservationId != null && id == excludeReservationId) {
        continue;
      }
      final status = existing['status']?.toString() ?? '';
      if (!isReservationBlocking(status)) {
        continue;
      }
      if (!isRealTableBookingFromApi(existing)) {
        continue;
      }
      final tables = (existing['tableNumbers'] as List?) ?? const [];
      if (tables.isEmpty) {
        continue;
      }
      for (final raw in tables) {
        final code = raw is int ? raw : int.tryParse(raw.toString());
        if (code != null) {
          unavailable.add(code);
        }
      }
    }
    return unavailable;
  }

  static bool isTableCodeAvailable({
    required int tableCode,
    required Set<int> unavailableCodes,
  }) {
    return !unavailableCodes.contains(tableCode);
  }

  static bool isTableModelAvailable({
    required TableModel table,
    required Set<int> unavailableCodes,
  }) {
    final code = encodeTableCode(
      floor: table.floor,
      tableNumber: table.tableNumber,
    );
    return isTableCodeAvailable(tableCode: code, unavailableCodes: unavailableCodes);
  }

  static bool areTableCodesAvailable({
    required List<int> tableCodes,
    required Iterable<Reservation> reservations,
    String? excludeReservationId,
  }) {
    if (tableCodes.isEmpty) {
      return true;
    }
    final unavailable = unavailableTableCodesFromReservations(
      reservations: reservations,
      excludeReservationId: excludeReservationId,
    );
    return tableCodes.every((code) => !unavailable.contains(code));
  }

  static List<TableModel> sortTables(List<TableModel> tables) {
    return tables.toList()
      ..sort((a, b) {
        final floorCmp = a.floor.compareTo(b.floor);
        if (floorCmp != 0) return floorCmp;
        return (int.tryParse(a.tableNumber) ?? 0)
            .compareTo(int.tryParse(b.tableNumber) ?? 0);
      });
  }
}
