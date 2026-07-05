/// Operational status of an [Order].
///
/// Backed by the existing `Order.status` `String` field — this enum does not
/// change Hive storage. Use [OrderStatus.fromStorage] to read and
/// [storageValue] to write, so every call site agrees on the same set of
/// canonical strings instead of re-typing literals.
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  served,
  closed,
  cancelled,

  /// Storage held a value this enum doesn't recognize (corrupt data, a
  /// future value written by a newer app version, etc.). Callers should
  /// treat this the same as an unknown/non-terminal state rather than
  /// guessing — never silently reinterpret it as [pending].
  unknown;

  /// Parses the raw Hive/JSON string into a canonical status.
  ///
  /// Handles the two known legacy quirks seen in production data:
  /// - `'paid'` — never written by current client or server code (grep-
  ///   verified), only checked for on read. Treated as an alias for
  ///   [closed].
  /// - case/whitespace variance — normalized before matching.
  static OrderStatus fromStorage(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'pending':
        return OrderStatus.pending;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'preparing':
        return OrderStatus.preparing;
      case 'served':
        return OrderStatus.served;
      case 'closed':
      case 'paid': // legacy alias — see doc comment above.
        return OrderStatus.closed;
      case 'cancelled':
      case 'canceled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.unknown;
    }
  }

  /// Canonical string to persist. [unknown] has no canonical form and must
  /// never be written back — callers should not construct new records with
  /// an unknown status.
  String get storageValue {
    switch (this) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.served:
        return 'served';
      case OrderStatus.closed:
        return 'closed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.unknown:
        throw StateError('OrderStatus.unknown has no storage representation');
    }
  }

  /// True once the order is settled and its table should be freed — mirrors
  /// the `status == 'closed' || status == 'cancelled'` (plus legacy `'paid'`)
  /// checks duplicated across the codebase today.
  bool get isTerminal =>
      this == OrderStatus.closed || this == OrderStatus.cancelled;
}
