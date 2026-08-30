import 'package:vynic/core/models/table_layout.dart';

/// Name a table is shown under, as typed into the floor editor's
/// „მაგიდის სახელი" field.
///
/// The layout is the single source of truth for what a table is *called* and
/// its definition UUID is the canonical physical identity. The
/// `(floor, tableNumber)` pair remains the operational compatibility lookup.
/// Keeping those apart lets a table be renamed without orders, reservations,
/// or live table rows losing track of it.
///
/// Returns null when the runtime row has no layout entry — a legacy table that
/// was deleted from the plan but still carries an order. Callers supply their
/// own wording for that case rather than having Georgian text live in here.
String? floorPlanTableName(
  RestaurantTableLayout layout, {
  required String floor,
  required String tableNumber,
}) {
  final label = layout
      .tableForLegacy(floor: floor, tableNumber: tableNumber)
      ?.label
      .trim();
  return label == null || label.isEmpty ? null : label;
}

/// [floorPlanTableName] with the usual fallback: the bare table number, which
/// is what the POS showed before names were editable.
String floorPlanTableNameOrNumber(
  RestaurantTableLayout layout, {
  required String floor,
  required String tableNumber,
}) {
  return floorPlanTableName(layout, floor: floor, tableNumber: tableNumber) ??
      tableNumber;
}
