import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';

/// Uses the existing virtual takeaway identity and durable creation/closure
/// journals. Retrying the same cart/request never creates a second sale.
class QuickCheckoutService {
  static Future<ClosureResult> settle({
    required String requestId,
    required String actor,
    required List<OrderItem> items,
    required TablePaymentSelection payment,
  }) async {
    final subtotal = double.parse(
      items.fold<double>(0, (sum, item) => sum + item.total).toStringAsFixed(2),
    );
    if (items.isEmpty ||
        !subtotal.isFinite ||
        subtotal <= 0 ||
        !payment.total.isFinite ||
        (payment.total - subtotal).abs() > 0.005) {
      throw ArgumentError('გადახდა შეკვეთის ჯამს უნდა ემთხვეოდეს');
    }
    final order = await OrderRepository.createTakeAwayOrder(
      customerName: 'სწრაფი გაყიდვა',
      customerPhone: '',
      pickupTime: '',
      items: items,
      createdBy: actor,
      requestId: requestId,
    );
    return CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(order, collectedNow: payment.total),
      paymentMethod: TableClosureHelper.resolvePaymentMethod(payment),
      tenderBreakdown:
          TableClosureHelper.buildSaleBreakdown(payment) ?? const {},
      closedById: actor,
      closedByName: actor,
      isFiscal: true,
      saleItems: order.items,
      subtotalAmount: subtotal,
      expectedOrder: OrderTableMutationRepository.capture(order),
    );
  }
}
