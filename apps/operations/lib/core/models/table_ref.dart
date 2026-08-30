import 'package:vynic/core/contracts/table_identity.dart' as contract;

/// Lossless reservation compatibility reference: floor key + table number,
/// e.g. `first/3`.
///
/// Reservations currently use this form, and it can represent any floor/table
/// the layout editor can create. It is not the immutable physical-table UUID;
/// that is `RestaurantTableDefinition.id`. The legacy int encoding remains for
/// storage backfill and the server reservation wire format.
class TableRef {
  const TableRef({required this.floor, required this.tableNumber});

  final String floor;
  final String tableNumber;

  /// `floor/tableNumber`. Floor keys ('first', 'second', 'floor-3', …) never
  /// contain '/', so the first slash is an unambiguous separator.
  ///
  /// The wire form is defined by the shared contract in `packages/contracts`,
  /// which apps/backend renders from the same schema.
  String encode() =>
      contract.encodeTableRef(floor: floor, tableNumber: tableNumber);

  static TableRef? tryDecode(String raw) {
    final decoded = contract.tryDecodeTableRef(raw);
    if (decoded == null) {
      return null;
    }
    return TableRef(
      floor: decoded.floor,
      tableNumber: decoded.tableNumber,
    );
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
