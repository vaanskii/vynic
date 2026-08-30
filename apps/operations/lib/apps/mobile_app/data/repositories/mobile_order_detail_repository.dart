import 'package:vynic/apps/mobile_app/data/services/mobile_order_detail_remote_service.dart';
import 'package:vynic/core/models/order.dart';

class MobileOrderDetailRepository {
  final MobileOrderDetailRemoteService _remote;

  const MobileOrderDetailRepository(this._remote);

  Future<Order> getOrder(int orderId) => _remote.getOrder(orderId);
}
