import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/utils/table_naming.dart';

/// Shared table-group colors and labels (matches Windows POS floor map).
class TableGroupStyle {
  TableGroupStyle._();

  static String? groupKey(TableModel table) {
    final reservationId = table.reservationId?.trim();
    if (reservationId != null && reservationId.isNotEmpty) {
      return 'reservation-$reservationId';
    }
    if (table.activeOrderId != null) {
      return 'order-${table.activeOrderId}';
    }
    if (table.isReserved) {
      return 'table-${table.floor}-${table.tableNumber}-'
          '${table.reservedAt?.millisecondsSinceEpoch ?? 0}';
    }
    return null;
  }

  static Color colorFromGroupKey(String groupKey) {
    final normalizedHash = groupKey.hashCode & 0x7fffffff;
    final hue = (normalizedHash % 360).toDouble();
    final saturation = 0.55 + ((normalizedHash >> 3) % 35) / 100;
    final lightness = 0.45 + ((normalizedHash >> 5) % 20) / 100;
    return HSLColor.fromAHSL(
      0.92,
      hue,
      saturation.clamp(0.0, 1.0),
      lightness.clamp(0.0, 1.0),
    ).toColor();
  }

  static Map<String, Color> buildColorMap(Iterable<TableModel> tables) {
    final map = <String, Color>{};
    for (final table in tables) {
      final key = groupKey(table);
      if (key != null) {
        map.putIfAbsent(key, () => colorFromGroupKey(key));
      }
    }
    return map;
  }

  /// Sorted table numbers per active order (e.g. 5 & 6 on one check).
  static Map<int, List<String>> buildOrderTableNumbers(
    Iterable<TableModel> tables,
  ) {
    final map = <int, List<String>>{};
    for (final table in tables) {
      final orderId = table.activeOrderId;
      if (orderId == null) continue;
      map.putIfAbsent(orderId, () => []).add(table.tableNumber.trim());
    }
    for (final numbers in map.values) {
      numbers.sort(
        (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
      );
    }
    return map;
  }

  static String normalizeTableToken(String raw) {
    return raw
        .replaceAll(RegExp(r'^Table\s*', caseSensitive: false), '')
        .trim();
  }

  static String formatOrderTablesLabel(Order order) {
    if (order.tableNumbers.isEmpty) return '—';
    final floor = order.floor.trim().toLowerCase();
    final nums = order.tableNumbers
        .map(normalizeTableToken)
        .where((s) => s.isNotEmpty)
        .toList();
    if (nums.isEmpty) return '—';
    nums.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    if (floor == 'takeaway') {
      return nums.map((n) => 'Take Away $n').join(', ');
    }
    // One bill, joined with a plus. The floor no longer decides the word: the
    // layout does, so a renamed table reads the same here as on the POS.
    return nums
        .map((n) => TableNaming.table(tableNumber: n, floor: order.floor))
        .join(TableNaming.joiner);
  }

  static String formatTableNumbersList(Iterable<String> numbers, String floor) {
    final nums =
        numbers.map((n) => n.trim()).where((s) => s.isNotEmpty).toList()..sort(
          (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
        );
    if (nums.isEmpty) return '';
    return nums
        .map((n) => TableNaming.table(tableNumber: n, floor: floor))
        .join(TableNaming.joiner);
  }
}
