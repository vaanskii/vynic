import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';

class MobileOrderDetailRemoteService {
  const MobileOrderDetailRemoteService();

  Future<Order> getOrder(int orderId) => MobileApiService.getOrder(orderId);
}
