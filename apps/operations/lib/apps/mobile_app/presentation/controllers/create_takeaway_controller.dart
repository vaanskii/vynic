import 'package:flutter/foundation.dart';
import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';
import 'package:vynic/apps/mobile_app/data/repositories/takeaway_repository.dart';
import 'package:vynic/apps/mobile_app/state/providers/create_takeaway_state.dart';
import 'package:vynic/core/models/user.dart';

class CreateTakeawayController extends ChangeNotifier {
  final TakeawayRepository _repository;
  CreateTakeawayState _state = const CreateTakeawayState();

  final String? expectedScope;
  bool _disposed = false;
  bool newRequest = true;
  CreateTakeawayController(this._repository, {this.expectedScope});
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  CreateTakeawayState get state => _state;

  Future<void> initialize() async {
    final defaultPickup = _defaultPickupTime();
    _state = _state.copyWith(pickupTime: defaultPickup, loading: true);
    _emit();
    try {
      final menuItems = await _repository.getMenuItems();
      _state = _state.copyWith(menuItems: menuItems, loading: false);
      _emit();
    } catch (_) {
      _state = _state.copyWith(
        loading: false,
        errorMessage: 'მენიუს ჩატვირთვა ვერ მოხერხდა',
      );
      _emit();
    }
  }

  void setWaitInPlace(bool value) {
    _state = _state.copyWith(waitInPlace: value);
    _emit();
  }

  void setCustomerName(String value) {
    _state = _state.copyWith(customerName: value);
    _emit();
  }

  void setPickupTime(String value) {
    _state = _state.copyWith(pickupTime: value);
    _emit();
  }

  void incrementItem(TakeawayMenuItem item) {
    final cart = Map<String, TakeawayCartEntry>.from(_state.cart);
    cart
        .putIfAbsent(item.name, () => TakeawayCartEntry(price: item.price))
        .quantity++;
    _state = _state.copyWith(cart: cart);
    _emit();
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
    _emit();
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
    _emit();
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
    _emit();
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
      final fresh = newRequest;
      newRequest = false;
      final result = await _repository.createOrder(
        TakeawayCreatePayload(
          customerName: customerName,
          pickupTime: _state.pickupTime.trim(),
          waiterName: user.username,
          items: items,
        ),
        expectedScope: expectedScope,
        newRequest: fresh,
      );
      _state = _state.copyWith(submitting: false);
      _emit();
      return SubmitResult(
        result.isDone,
        result.message,
        isError: result.delivery.name == 'failed',
      );
    } catch (e) {
      _state = _state.copyWith(submitting: false);
      _emit();
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

  final bool isError;
  const SubmitResult(this.success, this.message, {this.isError = true});
}
