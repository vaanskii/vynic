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
/// ## What still comes from elsewhere
///
/// Customer name, phone and pickup time are not on `Order` — the POS model has
/// no field for them, and the takeaway creation paths put them only on the
/// reservation. They are display text, so this takes them as an optional
/// [TakeawayContact] supplied by the caller and falls back cleanly when there
/// is none: nothing in the list, the money, the status or the actions depends
/// on it. Moving those three onto `Order` (Cloud's `Order` already carries
/// them) is what finally retires the row, and is a later phase.
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
  final floor = order.floor.trim().toLowerCase();
  if (floor == 'takeaway' || floor == 'take-away' || floor.contains('take away')) {
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
/// Display only. Held apart from [TakeawayTicket] so the ticket can be built
/// without any of it, and so the legacy row it currently comes from is named at
/// exactly one call site instead of throughout a screen.
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

  int get itemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

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
    final value = contact?.pickupTime?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get customerPhone {
    final value = contact?.customerPhone?.trim();
    return (value == null || value.isEmpty || value == '-') ? null : value;
  }

  String? get notes {
    final value = contact?.notes?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// What to call the guest, falling back the way the panel always has.
  String customerName(String fallback) {
    final name = contact?.customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final note = contact?.notes?.trim();
    if (note != null && note.isNotEmpty) return note;
    return fallback;
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
  /// appears once — the row is looked up for its guest details, never listed.
  ///
  /// [contactFor] is optional. Without it every ticket still lists, totals and
  /// closes correctly; it only loses the guest's name, phone and pickup time.
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

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
