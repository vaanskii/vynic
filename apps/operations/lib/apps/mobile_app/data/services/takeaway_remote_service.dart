import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';

class TakeawayRemoteService {
  const TakeawayRemoteService();

  Future<List<dynamic>> getMenuRaw() => MobileApiService.getMenu();

  Future<void> createTakeawayOrder(TakeawayCreatePayload payload) {
    return MobileApiService.createTakeawayOrder(
      customerName: payload.customerName,
      pickupTime: payload.pickupTime,
      waiterName: payload.waiterName,
      items: payload.items,
    );
  }
}
