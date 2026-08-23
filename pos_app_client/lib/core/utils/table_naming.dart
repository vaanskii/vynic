import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';

/// What a table and its floor are called, from the layout the admin edits.
///
/// Every one of these used to be decided by a `floor == 'second'` branch that
/// printed „კუპე" — on the order screen, on kitchen checks, in the manager
/// app's table lists and in its notifications. Four copies of the same
/// assumption, and none of them agreed with the floor editor, where those same
/// tables have been called „VIP Zone 1..4" since names became editable.
///
/// So the layout is the only thing asked. `(floor, tableNumber)` still says
/// which table it *is*; the layout says what it is *called*.
abstract final class TableNaming {
  /// Joins several tables on one order. „მაგიდა 1 + მაგიდა 2" — a plus, not a
  /// comma, because these are one bill and a comma reads as a list of separate
  /// ones.
  static const String joiner = ' + ';

  /// The saved layout, or the built-in one when nothing has been customised.
  ///
  /// Goes through `TableRepository`, which already handles a corrupted saved
  /// layout by falling back and reporting once. A second copy of that recovery
  /// here would report twice and could disagree about what „the layout" is.
  static RestaurantTableLayout layout() {
    try {
      return DatabaseService.getRestaurantTableLayout();
    } catch (_) {
      // Only reachable before the database is open at all — a naming helper
      // that can take down a screen for that is worse than one that falls back.
      return RestaurantTableLayouts.current;
    }
  }

  /// What one table is called, e.g. „ფანჯარასთან" or „მაგიდა 7".
  static String table({
    required String tableNumber,
    required String floor,
    RestaurantTableLayout? from,
  }) {
    final label = (from ?? layout())
        .tableForLegacy(floor: floor, tableNumber: tableNumber)
        ?.label
        .trim();
    if (label != null && label.isNotEmpty) return label;
    // A table that is on an order but no longer on the plan. The number is
    // still the truth about which one it is.
    return 'მაგიდა $tableNumber';
  }

  /// What the floor is called, e.g. „Second floor". Null when the layout has no
  /// zone for it — callers decide whether to say anything at all.
  static String? zone(String floor, {RestaurantTableLayout? from}) {
    if (floor.trim().toLowerCase() == 'takeaway') return null;
    final name = (from ?? layout()).zoneForLegacyFloor(floor)?.name.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Every table on an order, in one label.
  static String orderTables(Order order, {RestaurantTableLayout? from}) {
    if (order.tableNumbers.isEmpty) return '—';
    final resolved = from ?? layout();
    return order.tableNumbers
        .map(
          (number) =>
              table(tableNumber: number, floor: order.floor, from: resolved),
        )
        .join(joiner);
  }
}
