/// Takeaway, read from the orders that are takeaway.
///
/// The home takeaway panel used to be driven by the reservation box: every
/// takeaway order also wrote a `Reservation` row, and the panel listed, counted
/// and totalled *those*. That is why `Reservation.preOrderItems` exists at all —
/// it is a copy of `Order.items` kept so a screen could render. The order was
/// always the real record; the booking beside it was scaffolding.
///
/// So the queue is built from orders here. A takeaway order with no reservation
/// row anywhere renders exactly the same, which is the property this file is
/// for.
///
/// Customer name, phone and pickup time now come from `Order`. An optional
/// [TakeawayContact] remains only as a compatibility fallback for orders
/// written by old builds, whose additive Hive fields read as empty.
library;

import 'order.dart';
import 'order_status.dart';

/// Whether [order] is a takeaway order.
///
/// The one definition. Takeaway has no field of its own yet — it is the floor
/// label, with the spellings that have been written over the years, plus the
/// `TA-` synthetic table a takeaway order is given instead of a real one. New
/// call sites should use this rather than adding a sixteenth substring test.
bool isTakeawayOrder(Order order) {
  if (order.packageId?.trim().isNotEmpty == true) return false;
  final floor = order.floor.trim().toLowerCase();
  if (floor == 'takeaway' ||
      floor == 'take-away' ||
      floor.contains('take away')) {
    return true;
  }
  if (floor.contains('takeaway')) return true;
  for (final table in order.tableNumbers) {
    final normalized = table.trim().toLowerCase();
    if (normalized.startsWith('ta-') || normalized.contains('take away')) {
      return true;
    }
  }
  return false;
}

/// The guest details a takeaway order was taken with.
///
/// Display-only compatibility data from a legacy bookkeeping reservation.
class TakeawayContact {
  const TakeawayContact({
    this.customerName,
    this.customerPhone,
    this.pickupTime,
    this.notes,
  });

  final String? customerName;
  final String? customerPhone;

  /// `HH:mm`, when the guest said they would collect.
  final String? pickupTime;

  final String? notes;
}

/// One takeaway order as the home panel shows it.
class TakeawayTicket {
  const TakeawayTicket({required this.order, this.contact});

  final Order order;
  final TakeawayContact? contact;

  int get orderId => order.orderId;

  /// Stable across a rebuild, and unique per order.
  String get key => 'takeaway-${order.orderId}';

  /// `#TA-0042`. Unchanged: the old panel derived it from the linked order id
  /// and fell back to the reservation's own id only when there was no order.
  String get orderNumber => '#TA-${order.orderId.toString().padLeft(4, '0')}';

  /// Package lines first, then ordinary lines — the same list the receipt and
  /// the close flow sell.
  List<OrderItem> get items => <OrderItem>[
    ...order.packageItems,
    ...order.items,
  ];

  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  /// The order's own total. There is one money rule and this is not a second
  /// one: no re-summing of lines, no service fee (takeaway never charges it),
  /// no discount or adjustment arithmetic repeated here.
  double get total => order.totalAmount;

  String get status => order.status.trim().toLowerCase();

  OrderStatus get statusEnum => order.statusEnum;

  DateTime get createdAt => order.createdAt;

  bool get isCancelled => statusEnum == OrderStatus.cancelled;

  /// Settled: paid, closed, or the legacy `paid` spelling `OrderStatus` folds
  /// into `closed`.
  bool get isCompleted => statusEnum == OrderStatus.closed;

  /// Nothing more will happen to it. The same set the old panel derived from
  /// the linked order when it had one.
  bool get isFinalized => isCompleted || isCancelled;

  /// Still in the queue. A cancelled order is not active — the old panel's
  /// metric counted one as active because it only tested for `completed`,
  /// while the sidebar badge beside it already excluded both.
  bool get isActive => !isFinalized;

  String? get pickupTime {
    final owned = order.pickupTime.trim();
    if (owned.isNotEmpty) return owned;
    return _nonEmpty(contact?.pickupTime);
  }

  String? get customerPhone {
    final owned = order.customerPhone.trim();
    final value = owned.isNotEmpty ? owned : _nonEmpty(contact?.customerPhone);
    return (value == null || value.isEmpty || value == '-') ? null : value;
  }

  String? get notes {
    final value = contact?.notes?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// What to call the guest, falling back the way the panel always has.
  String customerName(String fallback) {
    final owned = order.customerName.trim();
    if (owned.isNotEmpty) return owned;
    final name = contact?.customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final note = contact?.notes?.trim();
    if (note != null && note.isNotEmpty) return note;
    return fallback;
  }

  static String? _nonEmpty(String? raw) {
    final value = raw?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Past its pickup time and still in the queue.
  ///
  /// A ticket with no known pickup time is never late: the panel would
  /// otherwise have to invent a deadline, and a made-up one shown in red is
  /// worse than none.
  bool isDelayedAt(DateTime now) {
    if (isFinalized) return false;
    final pickup = _pickupAt();
    if (pickup == null) return false;
    return pickup.isBefore(now);
  }

  DateTime? _pickupAt() {
    final raw = pickupTime;
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(
      order.createdAt.year,
      order.createdAt.month,
      order.createdAt.day,
      hour,
      minute,
    );
  }
}

/// Builds the home panel's queue.
class TakeawayTickets {
  TakeawayTickets._();

  /// The takeaway orders of [businessDate], newest first.
  ///
  /// Keyed by order, so a takeaway that also has a legacy reservation row
  /// appears once. The row may supply missing guest details for old orders,
  /// but it never controls membership, money or status.
  ///
  /// [contactFor] is optional. New orders remain complete without it; an old
  /// order whose additive fields are empty loses only the legacy display text.
  static List<TakeawayTicket> forBusinessDate({
    required Iterable<Order> orders,
    required DateTime businessDate,
    TakeawayContact? Function(int orderId)? contactFor,
  }) {
    final dateKey = _dateKey(businessDate);
    final tickets = <TakeawayTicket>[];
    final seen = <int>{};
    for (final order in orders) {
      if (!isTakeawayOrder(order)) continue;
      if (_dateKey(order.createdAt) != dateKey) continue;
      if (!seen.add(order.orderId)) continue;
      tickets.add(
        TakeawayTicket(order: order, contact: contactFor?.call(order.orderId)),
      );
    }
    tickets.sort((a, b) {
      final byId = b.orderId.compareTo(a.orderId);
      if (byId != 0) return byId;
      return b.createdAt.compareTo(a.createdAt);
    });
    return tickets;
  }

  /// How many takeaway orders of [businessDate] are still in the queue.
  static int activeCount({
    required Iterable<Order> orders,
    required DateTime businessDate,
  }) => forBusinessDate(
    orders: orders,
    businessDate: businessDate,
  ).where((ticket) => ticket.isActive).length;

  /// The authoritative open-takeaway source used by Close Day.
  static List<TakeawayTicket> activeForBusinessDate({
    required Iterable<Order> orders,
    required DateTime businessDate,
  }) => forBusinessDate(
    orders: orders,
    businessDate: businessDate,
  ).where((ticket) => ticket.isActive).toList();

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
