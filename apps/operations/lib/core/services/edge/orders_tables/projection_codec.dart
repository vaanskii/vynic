import 'dart:convert';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';

/// Pricing and business validation stay in Flutter. This codec deliberately
/// projects ordinary open Orders, without payment/closure/reservation effects.
abstract final class OrderTableCodec {
  static ProjectionEntity order(Order order, List<String> tableIds) {
    if (!['pending', 'confirmed'].contains(order.status) ||
        order.packageId != null ||
        order.advanceAmount != 0 ||
        order.paymentMethod != null ||
        order.closureId != null ||
        order.discountAmount != 0 ||
        order.manualAdjustmentAmount != 0) {
      throw StateError('Order is outside the Phase 2A ordinary-open scope');
    }
    if (order.orderUuid == null || order.items.any((l) => l.lineUuid == null)) {
      throw StateError('Stable identity migration required');
    }
    return ProjectionEntity(
      kind: ProjectionEntity_Kind.ORDER,
      id: order.orderUuid,
      document: utf8.encode(
        jsonEncode({
          'orderUuid': order.orderUuid,
          'orderId': order.orderId,
          'floor': order.floor,
          'tableIds': tableIds,
          'items': order.items.map((l) => l.toJson()).toList(),
          'status': order.status,
          'totalAmount': order.totalAmount,
          'includeServiceFee': order.includeServiceFee,
          'createdAt': order.createdAt.toIso8601String(),
          'createdBy': order.createdBy,
        }),
      ),
    );
  }

  static ProjectionEntity table(
    TableModel table,
    String tableId,
    String? activeOrderUuid,
  ) => ProjectionEntity(
    kind: ProjectionEntity_Kind.TABLE,
    id: tableId,
    document: utf8.encode(
      jsonEncode({
        'tableId': tableId,
        'floor': table.floor,
        'tableNumber': table.tableNumber,
        'activeOrderUuid': activeOrderUuid,
      }),
    ),
  );

  static ProjectionEntity tombstone(ProjectionEntity_Kind kind, String id) =>
      ProjectionEntity(kind: kind, id: id, tombstone: true);

  static Map<String, dynamic> document(ProjectionEntity entity) =>
      jsonDecode(utf8.decode(entity.document)) as Map<String, dynamic>;
  static String key(ProjectionEntity entity) =>
      '${entity.kind.value}/${entity.id}';
}
