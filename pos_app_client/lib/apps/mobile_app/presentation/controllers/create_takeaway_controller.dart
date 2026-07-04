import 'package:flutter/foundation.dart';
import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/apps/mobile_app/data/repositories/takeaway_repository.dart';
import 'package:vynic/apps/mobile_app/state/providers/create_takeaway_state.dart';
import 'package:vynic/core/models/user.dart';

class CreateTakeawayController extends ChangeNotifier {
  final TakeawayRepository _repository;
  CreateTakeawayState _state = const CreateTakeawayState();

  CreateTakeawayController(this._repository);

  CreateTakeawayState get state => _state;

  Future<void> initialize() async {
    final defaultPickup = _defaultPickupTime();
    _state = _state.copyWith(pickupTime: defaultPickup, loading: true);
    notifyListeners();
    try {
      final menuItems = await _repository.getMenuItems();
      _state = _state.copyWith(menuItems: menuItems, loading: false);
      notifyListeners();
    } catch (_) {
      _state = _state.copyWith(
        loading: false,
        errorMessage: 'მენიუს ჩატვირთვა ვერ მოხერხდა',
      );
      notifyListeners();
    }
  }

  void setWaitInPlace(bool value) {
    _state = _state.copyWith(waitInPlace: value);
    notifyListeners();
  }

  void setCustomerName(String value) {
    _state = _state.copyWith(customerName: value);
    notifyListeners();
  }

  void setPickupTime(String value) {
    _state = _state.copyWith(pickupTime: value);
    notifyListeners();
  }

  void incrementItem(TakeawayMenuItem item) {
    final cart = Map<String, TakeawayCartEntry>.from(_state.cart);
    cart
        .putIfAbsent(item.name, () => TakeawayCartEntry(price: item.price))
        .quantity++;
    _state = _state.copyWith(cart: cart);
    notifyListeners();
  }

  void decrementItem(String itemName) {
    final cart = Map<String, TakeawayCartEntry>.from(_state.cart);
    final entry = cart[itemName];
    if (entry == null) return;
    entry.quantity--;
    if (entry.quantity <= 0) {
      cart.remove(itemName);
    }
    _state = _state.copyWith(cart: cart);
    notifyListeners();
  }

  void replaceCartFromSelection(List<Map<String, dynamic>> lines) {
    final next = <String, TakeawayCartEntry>{};
    for (final line in lines) {
      final name = (line['itemName'] ?? '').toString();
      final qty = (line['qty'] as num?)?.toInt() ?? 0;
      final price = (line['unitPrice'] as num?)?.toDouble() ?? 0.0;
      if (name.isEmpty || qty <= 0) continue;
      next[name] = TakeawayCartEntry(price: price)..quantity = qty;
    }
    _state = _state.copyWith(cart: next);
    notifyListeners();
  }

  Future<SubmitResult> submit(User user) async {
    final customerName = _state.waitInPlace
        ? 'აქ დაელოდება'
        : _state.customerName.trim();
    if (customerName.isEmpty) {
      return const SubmitResult(false, 'შეიყვანეთ მომხმარებლის ნომერი');
    }
    if (_state.cart.isEmpty) {
      return const SubmitResult(false, 'დაამატეთ მინიმუმ ერთი პროდუქტი');
    }
    _state = _state.copyWith(submitting: true);
    notifyListeners();
    try {
      final items = _state.cart.entries
          .map(
            (e) => {
              'itemName': e.key,
              'unitPrice': e.value.price,
              'quantity': e.value.quantity,
            },
          )
          .toList();
      await _repository.createOrder(
        TakeawayCreatePayload(
          customerName: customerName,
          pickupTime: _state.pickupTime.trim(),
          waiterName: user.username,
          items: items,
        ),
      );
      _state = _state.copyWith(submitting: false);
      notifyListeners();
      return const SubmitResult(true, null);
    } catch (e) {
      _state = _state.copyWith(submitting: false);
      notifyListeners();
      return SubmitResult(false, 'შეცდომა: $e');
    }
  }

  String _defaultPickupTime() {
    final now = DateTime.now().add(const Duration(minutes: 15));
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class SubmitResult {
  final bool success;
  final String? message;

  const SubmitResult(this.success, this.message);
}
