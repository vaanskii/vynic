import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/table_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';
import 'projection_codec.dart';

/// Maps existing POS identities to a scoped shadow change set. Never writes Hive.
abstract final class PosShadowProjection {
  /// Explicit initial Primary-POS shadow seed. Refuses unsupported live state
  /// instead of silently presenting an incomplete projection as a clean proof.
  static List<ProjectionEntity> currentSnapshot() {
    final live = DatabaseCore.orderBox!.values
        .where((o) => !['closed', 'paid', 'cancelled'].contains(o.status))
        .toList();
    final result = orders(live);
    final included = result
        .where((e) => e.kind == ProjectionEntity_Kind.TABLE)
        .map((e) => e.id)
        .toSet();
    for (final table in DatabaseCore.tableBox!.values) {
      final id = tableId(table);
      if (included.contains(id)) continue;
      if (table.isReserved ||
          table.activeOrderId != null ||
          table.reservationId != null) {
        throw StateError(
          'Reservation/dangling occupancy outside Phase 2A seed',
        );
      }
      result.add(OrderTableCodec.table(table, id, null));
    }
    return result;
  }

  static String tableId(TableModel table) {
    final definition = TableRepository.getRestaurantTableLayout()
        .tableForLegacy(floor: table.floor, tableNumber: table.tableNumber);
    if (definition == null)
      throw StateError('Table has no canonical layout identity');
    return definition.id;
  }

  static List<ProjectionEntity> orders(
    List<Order> orders, {
    bool opening = false,
  }) {
    final result = <ProjectionEntity>[];
    final touched = <String, ProjectionEntity>{};
    for (final order in orders) {
      final ids = <String>[];
      if (order.floor != 'takeaway') {
        for (final number in order.tableNumbers) {
          final table = TableRepository.getTable(number, order.floor);
          if (table == null) throw StateError('Order references missing Table');
          final id = tableId(table);
          ids.add(id);
          String? occupant;
          if (opening) {
            occupant = order.orderUuid;
          } else if (table.activeOrderId != null) {
            final active = DatabaseCore.orderBox!.values.where(
              (o) => o.orderId == table.activeOrderId,
            );
            if (active.isEmpty)
              throw StateError('Table references missing Order');
            occupant = active.first.orderUuid;
          }
          touched[id] = OrderTableCodec.table(table, id, occupant);
        }
      }
      result.add(OrderTableCodec.order(order, ids));
    }
    return [...result, ...touched.values];
  }

  static List<ProjectionEntity> moved(
    Order order,
    List<String> oldNumbers,
    String oldFloor, {
    required bool proposed,
  }) {
    final result = orders([order], opening: proposed);
    final ids = result
        .where((e) => e.kind == ProjectionEntity_Kind.TABLE)
        .map((e) => e.id)
        .toSet();
    for (final number in oldNumbers) {
      final table = TableRepository.getTable(number, oldFloor);
      if (table == null) throw StateError('Previous Table missing');
      final id = tableId(table);
      if (ids.contains(id)) continue;
      if (!proposed && table.activeOrderId != null)
        throw StateError('Previous Table was not released');
      result.add(OrderTableCodec.table(table, id, null));
    }
    return result;
  }

  static List<ProjectionEntity> cancelled(
    Order order, {
    required bool proposed,
  }) {
    if (!proposed && order.status != 'cancelled') return orders([order]);
    final result = [
      OrderTableCodec.tombstone(ProjectionEntity_Kind.ORDER, order.orderUuid!),
    ];
    if (order.floor != 'takeaway') {
      for (final number in order.tableNumbers) {
        final table = TableRepository.getTable(number, order.floor);
        if (table == null) throw StateError('Cancelled Table missing');
        if (!proposed && table.activeOrderId != null)
          throw StateError('Cancelled Table remains occupied');
        result.add(OrderTableCodec.table(table, tableId(table), null));
      }
    }
    return result;
  }
}
