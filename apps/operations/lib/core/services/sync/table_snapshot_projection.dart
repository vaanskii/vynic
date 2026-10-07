import 'package:vynic/core/contracts/table_identity.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';

/// Ephemeral Cloud projection; the saved POS layout and Hive remain authority.
class TableSnapshotProjection {
  final List<Map<String, dynamic>> tables;
  final Map<String, dynamic>? layout;
  const TableSnapshotProjection(this.tables, this.layout);

  static String? normalizeAlias(
    String raw,
    String floor,
    RestaurantTableLayout? layout,
  ) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (layout?.tableForLegacy(floor: floor, tableNumber: trimmed) != null)
      return trimmed;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('table ')) return trimmed.substring(6).trim();
    if (lower.startsWith('vip zone ')) return trimmed.substring(9).trim();
    final number = int.tryParse(trimmed);
    return number != null && floor == 'second' && number > 10
        ? '${number - 10}'
        : trimmed;
  }

  static TableSnapshotProjection build({
    required Iterable<TableModel> sourceTables,
    required List<Order> orders,
    required DateTime businessDate,
    required RestaurantTableLayout? savedLayout,
  }) {
    final byAlias = <String, Map<String, dynamic>>{};
    String key(String floor, String number) => '$floor\u0000$number';
    if (savedLayout != null) _validate(savedLayout);
    for (final table in sourceTables) {
      final order = orders
          .where((o) => o.orderId == table.activeOrderId)
          .firstOrNull;
      final row = Map<String, dynamic>.from(table.toJson());
      for (final field in [
        'tableKind',
        'tableLabel',
        'floorLabel',
        'floorSortOrder',
        'tableSortOrder',
      ]) {
        row.remove(field);
      }
      row['currentBill'] = table.activeOrderId != null
          ? order?.totalAmount ?? 0.0
          : 0.0;
      byAlias[key(table.floor, table.tableNumber)] = row;
    }
    for (final order in orders) {
      final status = order.status.toLowerCase();
      if (['paid', 'closed', 'cancelled'].contains(status)) continue;
      final date = order.createdAt;
      if (date.year != businessDate.year ||
          date.month != businessDate.month ||
          date.day != businessDate.day)
        continue;
      final floor = order.floor.toLowerCase();
      final configured = order.tableNumbers.any(
        (n) =>
            savedLayout?.tableForLegacy(
              floor: order.floor,
              tableNumber: normalizeAlias(n, order.floor, savedLayout) ?? '',
            ) !=
            null,
      );
      if (!configured &&
          (floor.contains('takeaway') || floor.contains('take away')))
        continue;
      for (final raw in order.tableNumbers) {
        final number = normalizeAlias(raw, order.floor, savedLayout);
        if (number == null || number.isEmpty) continue;
        final row = byAlias.putIfAbsent(
          key(order.floor, number),
          () => {'tableNumber': number, 'floor': order.floor},
        );
        row.addAll({
          'isReserved': true,
          'activeOrderId': order.orderId,
          'currentBill': order.totalAmount,
        });
      }
    }
    if (savedLayout == null)
      return TableSnapshotProjection(byAlias.values.toList(), null);
    // Include configured free tables even when an older local table box has not
    // yet materialized them; completeness comes from configuration, not Hive.
    for (final definition in savedLayout.tables) {
      final zone = savedLayout.zones.singleWhere(
        (z) => z.id == definition.zoneId,
      );
      final row = byAlias.putIfAbsent(
        key(definition.legacyFloor, definition.legacyTableNumber),
        () => {
          'tableNumber': definition.legacyTableNumber,
          'floor': definition.legacyFloor,
          'isReserved': false,
          'activeOrderId': null,
          'currentBill': 0.0,
        },
      );
      row.addAll({
        'tableId': definition.id,
        'tableKind': 'PHYSICAL',
        'tableLabel': definition.label,
        'floorLabel': zone.name,
        'floorSortOrder': zone.displayOrder,
        'tableSortOrder': definition.sortOrder,
      });
    }
    for (final row in byAlias.values) {
      if (row['tableKind'] == 'PHYSICAL') continue;
      row.remove('tableId');
      row['tableKind'] = 'VIRTUAL';
      for (final field in [
        'tableLabel',
        'floorLabel',
        'floorSortOrder',
        'tableSortOrder',
      ]) {
        row.remove(field);
      }
    }
    return TableSnapshotProjection(byAlias.values.toList(), {
      'version': 1,
      'physicalTableIds': savedLayout.tables.map((t) => t.id).toList(),
    });
  }

  static void _validate(RestaurantTableLayout layout) {
    final zoneIds = <String>{},
        floors = <String>{},
        ids = <String>{},
        aliases = <String>{};
    for (final zone in layout.zones) {
      if (!zoneIds.add(zone.id) ||
          !floors.add(zone.legacyFloor) ||
          zone.name.trim().isEmpty ||
          zone.name.length > 512 ||
          zone.displayOrder.abs() > 2147483647) {
        throw const FormatException(
          'Saved layout has invalid or duplicate floors',
        );
      }
    }
    for (final table in layout.tables) {
      final zone = layout.zones.where((z) => z.id == table.zoneId).firstOrNull;
      if (!isCanonicalTableId(table.id) ||
          !ids.add(table.id) ||
          zone == null ||
          zone.legacyFloor != table.legacyFloor ||
          !aliases.add(
            '${table.legacyFloor}\u0000${table.legacyTableNumber}',
          ) ||
          table.legacyTableNumber.trim().isEmpty ||
          table.label.trim().isEmpty ||
          table.label.length > 512 ||
          table.sortOrder.abs() > 2147483647) {
        throw const FormatException(
          'Saved layout has invalid or duplicate physical tables',
        );
      }
    }
  }
}
