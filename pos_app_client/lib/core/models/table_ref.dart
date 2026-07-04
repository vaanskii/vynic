/// Stable reference to a table: floor key + table number, e.g. `first/3`.
///
/// This is the canonical way reservations refer to tables. It can represent
/// any floor/table the layout editor can create, unlike the legacy int
/// encoding (see `ReservationTableAvailability.encodeTableCode`), which is
/// kept only for storage backfill and the server wire format.
class TableRef {
  const TableRef({required this.floor, required this.tableNumber});

  final String floor;
  final String tableNumber;

  /// `floor/tableNumber`. Floor keys ('first', 'second', 'floor-3', …) never
  /// contain '/', so the first slash is an unambiguous separator.
  String encode() => '$floor/$tableNumber';

  static TableRef? tryDecode(String raw) {
    final separator = raw.indexOf('/');
    if (separator <= 0 || separator >= raw.length - 1) {
      return null;
    }
    final floor = raw.substring(0, separator).trim();
    final tableNumber = raw.substring(separator + 1).trim();
    if (floor.isEmpty || tableNumber.isEmpty) {
      return null;
    }
    return TableRef(floor: floor, tableNumber: tableNumber);
  }

  @override
  bool operator ==(Object other) {
    return other is TableRef &&
        other.floor == floor &&
        other.tableNumber == tableNumber;
  }

  @override
  int get hashCode => Object.hash(floor, tableNumber);

  @override
  String toString() => 'TableRef(${encode()})';
}
