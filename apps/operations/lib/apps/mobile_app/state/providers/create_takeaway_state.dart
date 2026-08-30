import 'package:vynic/apps/mobile_app/data/models/takeaway_models.dart';

class CreateTakeawayState {
  final bool loading;
  final bool submitting;
  final bool waitInPlace;
  final List<TakeawayMenuItem> menuItems;
  final Map<String, TakeawayCartEntry> cart;
  final String customerName;
  final String pickupTime;
  final String? errorMessage;

  const CreateTakeawayState({
    this.loading = true,
    this.submitting = false,
    this.waitInPlace = false,
    this.menuItems = const [],
    this.cart = const {},
    this.customerName = '',
    this.pickupTime = '',
    this.errorMessage,
  });

  double get total =>
      cart.values.fold(0.0, (sum, entry) => sum + entry.price * entry.quantity);

  CreateTakeawayState copyWith({
    bool? loading,
    bool? submitting,
    bool? waitInPlace,
    List<TakeawayMenuItem>? menuItems,
    Map<String, TakeawayCartEntry>? cart,
    String? customerName,
    String? pickupTime,
    String? errorMessage,
  }) {
    return CreateTakeawayState(
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      waitInPlace: waitInPlace ?? this.waitInPlace,
      menuItems: menuItems ?? this.menuItems,
      cart: cart ?? this.cart,
      customerName: customerName ?? this.customerName,
      pickupTime: pickupTime ?? this.pickupTime,
      errorMessage: errorMessage,
    );
  }
}
