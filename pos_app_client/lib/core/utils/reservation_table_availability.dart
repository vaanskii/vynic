import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';

/// Shared reservation table encoding and availability checks.
///
/// Table blocking is based only on existing **reservation records** for the
/// chosen calendar day (not live walk-in / order occupancy on tables).
///
/// [TableRef] is the canonical table identity; the legacy int encoding
/// (`encodeTableCode` / `decodeTableCode`) survives only for stored
/// `Reservation.tableNumbers` backfill and the server wire format.
class ReservationTableAvailability {
  ReservationTableAvailability._();

  static const int slotDurationMinutes = 120;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static bool isSameCalendarDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Canonical tables of a reservation: stored [Reservation.tableRefs] when
  /// present, otherwise decoded from the legacy int codes.
  static List<TableRef> tableRefsOf(Reservation reservation) {
    final stored = reservation.tableRefs;
    if (stored != null && stored.isNotEmpty) {
      return [
        for (final raw in stored)
          if (TableRef.tryDecode(raw) case final ref?) ref,
      ];
    }
    return [
      for (final code in reservation.tableNumbers) refFromLegacyCode(code),
    ];
  }

  static TableRef refFromLegacyCode(int code) {
    final decoded = decodeTableCode(code);
    return TableRef(floor: decoded.floor, tableNumber: decoded.tableNumber);
  }

  /// Legacy int code for [ref], or null when the encoding cannot represent
  /// it (3rd+ floors, first-floor tables above 10).
  static int? legacyCodeOf(TableRef ref) {
    if (!canEncodeTableCode(floor: ref.floor, tableNumber: ref.tableNumber)) {
      return null;
    }
    return encodeTableCode(floor: ref.floor, tableNumber: ref.tableNumber);
  }

  /// Best-effort legacy projection of [refs] for backups and the server
  /// wire format: unrepresentable tables are simply omitted.
  static List<int> legacyCodesOf(Iterable<TableRef> refs) {
    return [
      for (final ref in refs)
        if (legacyCodeOf(ref) case final code?) code,
    ]..sort();
  }

  /// Whether [encodeTableCode] can represent this table. Pickers must hide
  /// tables that fail this check instead of offering them for reservation.
  static bool canEncodeTableCode({
    required String floor,
    required String tableNumber,
  }) {
    final parsed = int.tryParse(tableNumber.trim());
    if (parsed == null || parsed < 1) {
      return false;
    }
    if (floor == 'second') {
      return true;
    }
    return floor == 'first' && parsed <= 10;
  }

  /// Encodes floor + table number into reservation `tableNumbers` format.
  ///
  /// The legacy int encoding can only represent two floors ('first' ≤ 10,
  /// 'second' = number + 10). Anything else must throw rather than encode a
  /// code that silently decodes to a different table.
  static int encodeTableCode({
    required String floor,
    required String tableNumber,
  }) {
    final parsed = int.tryParse(tableNumber.trim());
    if (parsed == null || parsed < 1) {
      throw ArgumentError('Invalid table number: $tableNumber');
    }
    if (floor == 'second') {
      return parsed + 10;
    }
    if (floor != 'first') {
      throw ArgumentError(
        'Floor "$floor" cannot be encoded as a reservation table code; '
        'only first/second are supported',
      );
    }
    if (parsed > 10) {
      throw ArgumentError(
        'Table $parsed on the first floor cannot be encoded as a '
        'reservation table code (would decode as a second-floor table)',
      );
    }
    return parsed;
  }

  static ({String floor, String tableNumber}) decodeTableCode(int code) {
    if (code > 10) {
      return (floor: 'second', tableNumber: '${code - 10}');
    }
    return (floor: 'first', tableNumber: '$code');
  }

  /// Bare table number for display. POS reservations encode 2nd-floor
  /// tables as 10+N; API payloads carry the plain number plus a floor, so
  /// an explicit non-'second' floor hint means the value is not encoded.
  static String displayTableNumber(int value, {String? floorHint}) {
    final floor = (floorHint ?? '').trim().toLowerCase();
    if (floor == 'second' || floor.isEmpty) {
      return decodeTableCode(value).tableNumber;
    }
    return '$value';
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

  static String floorLabel(String floor) {
    if (floor == 'second') return 'მე-2 სართული';
    if (floor == 'first') return '1-ლი სართული';
    // Custom floors carry their layout key; callers with layout access can
    // pass a nicer name via [formatTableRefs]'s floorNameOf.
    return floor;
  }

  static String displayLabel({
    required String floor,
    required String tableNumber,
  }) => '${floorLabel(floor)} • $tableNumber';

  static String displayLabelForRef(
    TableRef ref, {
    String Function(String floor)? floorNameOf,
  }) {
    final floorName = floorNameOf?.call(ref.floor) ?? floorLabel(ref.floor);
    return '$floorName • ${ref.tableNumber}';
  }

  static String formatTableRefs(
    List<TableRef> refs, {
    String Function(String floor)? floorNameOf,
  }) {
    return refs
        .map((ref) => displayLabelForRef(ref, floorNameOf: floorNameOf))
        .join(', ');
  }

  static String formatTableCodes(List<int> codes) {
    return formatTableRefs(codes.map(refFromLegacyCode).toList());
  }

  /// Comma-joined table numbers of a reservation for compact labels
  /// (reservations are single-floor, so bare numbers are unambiguous).
  static String tableNumbersLabel(
    Reservation reservation, {
    String placeholder = '-',
  }) {
    final refs = tableRefsOf(reservation);
    if (refs.isEmpty) {
      return placeholder;
    }
    return refs.map((ref) => ref.tableNumber).join(', ');
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
    final normalized = (status ?? '').trim().toLowerCase().replaceAll('_', '-');
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
    return {
      for (final ref in unavailableTableRefsFromReservations(
        reservations: reservations,
        excludeReservationId: excludeReservationId,
      ))
        if (legacyCodeOf(ref) case final code?) code,
    };
  }

  static Set<TableRef> unavailableTableRefsFromReservations({
    required Iterable<Reservation> reservations,
    String? excludeReservationId,
  }) {
    final unavailable = <TableRef>{};
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
      unavailable.addAll(tableRefsOf(existing));
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
    return isTableCodeAvailable(
      tableCode: code,
      unavailableCodes: unavailableCodes,
    );
  }

  static bool areTableCodesAvailable({
    required List<int> tableCodes,
    required Iterable<Reservation> reservations,
    String? excludeReservationId,
  }) {
    return areTableRefsAvailable(
      tableRefs: tableCodes.map(refFromLegacyCode).toList(),
      reservations: reservations,
      excludeReservationId: excludeReservationId,
    );
  }

  static bool areTableRefsAvailable({
    required List<TableRef> tableRefs,
    required Iterable<Reservation> reservations,
    String? excludeReservationId,
  }) {
    if (tableRefs.isEmpty) {
      return true;
    }
    final unavailable = unavailableTableRefsFromReservations(
      reservations: reservations,
      excludeReservationId: excludeReservationId,
    );
    return tableRefs.every((ref) => !unavailable.contains(ref));
  }

  /// Tables blocked by LIVE floor state (walk-in orders, activated
  /// reservations, stale locks) — the reservation-record checks above cannot
  /// see these because activated bookings are excluded from
  /// [isRealTableBooking].
  ///
  /// Tables held by the reservation being (re)assigned itself are NOT
  /// blocked: pass its [excludeReservationId] and/or [excludeOrderId].
  /// Tables with non-numeric numbers are skipped (they cannot be encoded
  /// into reservation table codes).
  static Set<int> unavailableTableCodesFromLiveTables({
    required Iterable<TableModel> tables,
    String? excludeReservationId,
    int? excludeOrderId,
  }) {
    return {
      for (final ref in unavailableTableRefsFromLiveTables(
        tables: tables,
        excludeReservationId: excludeReservationId,
        excludeOrderId: excludeOrderId,
      ))
        if (legacyCodeOf(ref) case final code?) code,
    };
  }

  static Set<TableRef> unavailableTableRefsFromLiveTables({
    required Iterable<TableModel> tables,
    String? excludeReservationId,
    int? excludeOrderId,
  }) {
    final unavailable = <TableRef>{};
    for (final table in tables) {
      if (!table.isReserved && table.activeOrderId == null) {
        continue;
      }
      if (excludeReservationId != null &&
          table.reservationId == excludeReservationId) {
        continue;
      }
      if (excludeOrderId != null && table.activeOrderId == excludeOrderId) {
        continue;
      }
      unavailable.add(refOfTableModel(table));
    }
    return unavailable;
  }

  static TableRef refOfTableModel(TableModel table) {
    return TableRef(floor: table.floor, tableNumber: table.tableNumber);
  }

  static List<TableModel> sortTables(List<TableModel> tables) {
    return tables.toList()..sort((a, b) {
      final floorCmp = a.floor.compareTo(b.floor);
      if (floorCmp != 0) return floorCmp;
      return (int.tryParse(a.tableNumber) ?? 0).compareTo(
        int.tryParse(b.tableNumber) ?? 0,
      );
    });
  }
}
