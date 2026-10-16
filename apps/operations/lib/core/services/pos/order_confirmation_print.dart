import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';

/// Admit the frozen initial ticket before committing confirmation. The worker
/// starts outside this owner and additionally checks the saved Order status.
/// A crash at either write leaves a pending Order or a durable held ticket.
abstract final class OrderConfirmationPrint {
  static Future<bool> confirm({
    required Order order,
    required List<String> lines,
    required String tableLabel,
    void Function(bool)? onComplete,
  }) {
    final frozen = List<String>.of(lines);
    return LocalDataAdmission.mutate(() async {
      OrderTableMutationRepository.requireFresh(order);
      if (frozen.isNotEmpty) {
        final accepted = await PrinterService.printKitchenCheckInBackground(
          initialOrderUuid: order.orderUuid,
          requiresConfirmedOrderUuid: order.orderUuid,
          items: frozen,
          tableNumber: tableLabel,
          orderNumber: order.orderId.toString(),
          waiterName: order.createdBy,
          createdAt: order.createdAt,
          onComplete: onComplete,
        );
        if (!accepted) return false;
      }
      await DatabaseService.updateOrderStatus(
        orderId: order.orderId,
        status: 'confirmed',
      );
      return true;
    });
  }
}
