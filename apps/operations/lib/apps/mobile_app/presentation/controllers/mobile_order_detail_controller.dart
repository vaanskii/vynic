import 'package:flutter/foundation.dart';
import 'package:vynic/apps/mobile_app/data/repositories/mobile_order_detail_repository.dart';
import 'package:vynic/apps/mobile_app/state/providers/mobile_order_detail_state.dart';

class MobileOrderDetailController extends ChangeNotifier {
  final MobileOrderDetailRepository _repository;
  MobileOrderDetailState _state = const MobileOrderDetailState();

  MobileOrderDetailController(this._repository);

  MobileOrderDetailState get state => _state;

  Future<void> loadOrder(int orderId) async {
    _state = _state.copyWith(loading: true, error: null);
    notifyListeners();
    try {
      final order = await _repository.getOrder(orderId);
      _state = _state.copyWith(order: order, loading: false, error: null);
      notifyListeners();
    } catch (_) {
      _state = _state.copyWith(
        loading: false,
        error: 'შეკვეთის ჩატვირთვა ვერ მოხერხდა',
      );
      notifyListeners();
    }
  }
}
