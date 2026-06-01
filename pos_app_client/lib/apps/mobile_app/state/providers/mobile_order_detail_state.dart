import 'package:vynic/core/models/order.dart';

class MobileOrderDetailState {
  final Order? order;
  final bool loading;
  final String? error;

  const MobileOrderDetailState({
    this.order,
    this.loading = true,
    this.error,
  });

  MobileOrderDetailState copyWith({
    Order? order,
    bool? loading,
    String? error,
  }) {
    return MobileOrderDetailState(
      order: order ?? this.order,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}
