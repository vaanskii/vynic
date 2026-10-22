import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';

class TakeawayRemoteService {
  const TakeawayRemoteService();

  Future<List<dynamic>> getMenuRaw() => MobileApiService.getMenu();

  Future<ManagerOperationResult> createTakeawayOrder(
    TakeawayCreatePayload payload, {
    String? expectedScope,
    bool newRequest = false,
  }) {
    return MobileApiService.createTakeawayOrder(
      expectedScope: expectedScope,
      newRequest: newRequest,
      customerName: payload.customerName,
      pickupTime: payload.pickupTime,
      waiterName: payload.waiterName,
      items: payload.items,
    );
  }
}
