import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/apps/mobile_app/data/services/takeaway_remote_service.dart';

class TakeawayRepository {
  final TakeawayRemoteService _service;

  const TakeawayRepository(this._service);

  Future<List<TakeawayMenuItem>> getMenuItems() async {
    final raw = await _service.getMenuRaw();
    final items = <TakeawayMenuItem>[];
    for (final category in raw) {
      _collectItems(category as Map<String, dynamic>, items);
    }
    return items;
  }

  Future<void> createOrder(TakeawayCreatePayload payload) {
    return _service.createTakeawayOrder(payload);
  }

  void _collectItems(
    Map<String, dynamic> category,
    List<TakeawayMenuItem> out,
  ) {
    final catItems = category['items'] as List? ?? [];
    for (final item in catItems) {
      final m = item as Map<String, dynamic>;
      final name = (m['nameKa'] as String? ?? '').trim();
      final price = (m['price'] as num? ?? 0).toDouble();
      if (name.isNotEmpty) {
        out.add(TakeawayMenuItem(name: name, price: price));
      }
    }
    final subcategories = category['subcategories'] as List? ?? [];
    for (final sub in subcategories) {
      _collectItems(sub as Map<String, dynamic>, out);
    }
  }
}
