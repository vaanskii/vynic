/// Moving ordered items from one open order to another.
///
/// The case this exists for: a party orders take-away and then decides to sit
/// down, or half a table moves to another one. Until now the only way through
/// that was to cancel the order and key it in again, which loses the audit
/// trail, the open time, and — when a reservation is attached — the booking.
///
/// The arithmetic lives here rather than in the dialog because it is the part
/// that has to be right: two orders' money changes at once, and getting it
/// wrong is not a visual bug.
library;

import 'dart:developer' as developer;
import '../edge/orders_tables/shadow.dart';
import '../edge/orders_tables/pos_shadow_projection.dart';

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/order_audit_details.dart';
import 'package:vynic/core/services/database_service.dart';

/// Which line to take from, and how many of it.
///
/// The line is named by its index in [Order.items] rather than by `itemKey`,
/// because an order merged from the mobile app can carry the same key twice
/// with different comments and those are genuinely different lines.
typedef OrderItemMove = ({int index, int quantity});

/// Why a transfer was refused.
///
/// A typed reason rather than a thrown string or a silent `false`: the dialog
/// has to tell the operator which of these happened, and a caller that ignores
/// the result should not be able to do so by accident.
enum OrderTransferError {
  /// Source and destination are the same order.
  sameOrder,

  /// The source is paid, closed or cancelled — its items are history.
  sourceFinalized,

  /// The destination is paid, closed or cancelled; items moved onto it would
  /// never be billed.
  destinationFinalized,

  /// No line had a quantity above zero.
  nothingSelected,

  /// A move named a line that is not there, or asked for more of it than the
  /// order holds.
  quantityOutOfRange,
}

/// One line as it was actually moved.
class OrderTransferLine {
  const OrderTransferLine({
    required this.itemName,
    required this.quantity,
    required this.amount,
    this.comment,
    this.menuItemId,
    this.variantId,
  });

  final String itemName;
  final int quantity;

  /// The money that moved with it, in GEL.
  final double amount;
  final String? comment;
  final String? menuItemId;
  final String? variantId;
}

/// What a transfer did, or why it did nothing.
class OrderTransferResult {
  const OrderTransferResult._({
    this.error,
    this.moved = const [],
    this.sourceLeftEmpty = false,
  });

  const OrderTransferResult.failed(OrderTransferError reason)
    : this._(error: reason);

  const OrderTransferResult.applied({
    required List<OrderTransferLine> moved,
    required bool sourceLeftEmpty,
  }) : this._(moved: moved, sourceLeftEmpty: sourceLeftEmpty);

  final OrderTransferError? error;
  final List<OrderTransferLine> moved;

  /// The source has no items left. Not an error — a whole party moving is the
  /// ordinary case — but the caller is expected to say so out loud, because an
  /// open table with an empty bill on it looks like a mistake.
  final bool sourceLeftEmpty;

  bool get ok => error == null;

  int get totalQuantity => moved.fold(0, (sum, line) => sum + line.quantity);

  double get totalAmount => double.parse(
    moved.fold(0.0, (sum, line) => sum + line.amount).toStringAsFixed(2),
  );
}

abstract final class OrderItemTransfer {
  /// Moves [moves] from [source] to [destination], in memory.
  ///
  /// Both orders are mutated and their totals recomputed; nothing is written to
  /// disk. [apply] is the version that persists and audits — this one is split
  /// out so the arithmetic can be checked without a database.
  static OrderTransferResult move({
    required Order source,
    required Order destination,
    required List<OrderItemMove> moves,
  }) {
    if (identical(source, destination) ||
        source.orderId == destination.orderId) {
      return const OrderTransferResult.failed(OrderTransferError.sameOrder);
    }
    if (_isFinalized(source.status)) {
      return const OrderTransferResult.failed(
        OrderTransferError.sourceFinalized,
      );
    }
    if (_isFinalized(destination.status)) {
      return const OrderTransferResult.failed(
        OrderTransferError.destinationFinalized,
      );
    }

    final wanted = moves.where((m) => m.quantity > 0).toList();
    if (wanted.isEmpty) {
      return const OrderTransferResult.failed(
        OrderTransferError.nothingSelected,
      );
    }

    // Validate everything before mutating anything. A half-applied move would
    // leave two orders disagreeing about how many khinkali exist.
    final byIndex = <int, int>{};
    for (final move in wanted) {
      if (move.index < 0 || move.index >= source.items.length) {
        return const OrderTransferResult.failed(
          OrderTransferError.quantityOutOfRange,
        );
      }
      final running = (byIndex[move.index] ?? 0) + move.quantity;
      if (running > source.items[move.index].quantity) {
        return const OrderTransferResult.failed(
          OrderTransferError.quantityOutOfRange,
        );
      }
      byIndex[move.index] = running;
    }

    final moved = <OrderTransferLine>[];

    // Descending, so removing an emptied line cannot shift an index we have
    // not reached yet.
    final indexes = byIndex.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final index in indexes) {
      final line = source.items[index];
      final quantity = byIndex[index]!;

      // Split the line's existing total rather than recomputing it from
      // `unitPrice * quantity`. They are usually the same, but where they are
      // not — a price keyed in by hand, a rounding from an older build — the
      // money is what is on the bill, and the two halves must still add up to
      // it exactly.
      final movedAmount = double.parse(
        (line.total * quantity / line.quantity).toStringAsFixed(2),
      );
      final remainingAmount = double.parse(
        (line.total - movedAmount).toStringAsFixed(2),
      );

      _merge(
        destination: destination,
        line: line,
        quantity: quantity,
        amount: movedAmount,
      );

      moved.add(
        OrderTransferLine(
          itemName: line.itemName,
          quantity: quantity,
          amount: movedAmount,
          comment: line.comment,
          menuItemId: line.menuItemId,
          variantId: line.variantId,
        ),
      );

      if (quantity == line.quantity) {
        source.items.removeAt(index);
      } else {
        line.quantity -= quantity;
        line.total = remainingAmount;
      }
    }

    source.recalculateTotal();
    destination.recalculateTotal();

    return OrderTransferResult.applied(
      // Rebuilt in the order the operator picked them, not the reverse order
      // the loop needed.
      moved: moved.reversed.toList(),
      sourceLeftEmpty: source.items.isEmpty && source.packageItems.isEmpty,
    );
  }

  /// Moves the items and writes both orders, with an audit event on each side.
  ///
  /// The destination is saved first. If the second write were to fail, the
  /// items would exist twice — which an operator can see and fix — rather than
  /// nowhere at all, which they cannot.
  static Future<OrderTransferResult> apply({
    required Order source,
    required Order destination,
    required List<OrderItemMove> moves,
    required User user,
    required String sourceLabel,
    required String destinationLabel,
    AuditSource auditSource = AuditSource.pos,
  }) async {
    // Work on copies so a refusal — or a failed write — cannot leave the
    // in-memory orders half-moved behind the operator's back.
    final sourceDraft = source.clone();
    final destinationDraft = destination.clone();

    final result = move(
      source: sourceDraft,
      destination: destinationDraft,
      moves: moves,
    );
    if (!result.ok) return result;

    await OrderTableShadow.observe(
      proposed: () =>
          PosShadowProjection.orders([sourceDraft, destinationDraft]),
      actual: () => PosShadowProjection.orders([source, destination]),
      operation: () async {
        source.items = sourceDraft.items;
        destination.items = destinationDraft.items;
        await DatabaseService.updateOrder(destination);
        await DatabaseService.updateOrder(source);
      },
    );

    final now = DatabaseService.getCurrentDateTime();
    final movedAmount = result.totalAmount;
    Map<String, dynamic> moveDetails({
      required Order own,
      required String direction,
      required OrderTransferLine line,
    }) => <String, dynamic>{
      ...OrderAuditDetails.base(
        order: own,
        orderKind: _kindOf(own),
        source: auditSource,
        actorId: user.username,
      ),
      'direction': direction,
      'fromOrderId': source.orderId,
      'toOrderId': destination.orderId,
      'fromTableRefs': OrderAuditDetails.tableRefs(source),
      'toTableRefs': OrderAuditDetails.tableRefs(destination),
      'quantity': line.quantity,
      'amount': line.amount,
      'transferAmount': movedAmount,
      if (line.comment != null && line.comment!.trim().isNotEmpty)
        'comment': line.comment!.trim(),
      if (line.menuItemId != null) 'menuItemId': line.menuItemId,
      if (line.variantId != null) 'variantId': line.variantId,
    };

    // One typed MOVE_ITEMS per line on each side. The quantities still say
    // which way the line went, so a build that predates the type reads the
    // same rows as an add on one bill and a removal on the other.
    await DatabaseService.appendOrderAuditEvents(
      orderId: destination.orderId,
      events: [
        for (final line in result.moved)
          AuditEvent(
            type: AuditEventType.moveItems,
            itemName: line.itemName,
            previousQty: 0,
            newQty: line.quantity,
            waiterId: user.username,
            waiterName: user.username,
            timestamp: now,
            note: 'გადმოტანილია — $sourceLabel',
            details: moveDetails(own: destination, direction: 'IN', line: line),
          ),
      ],
    );
    await DatabaseService.appendOrderAuditEvents(
      orderId: source.orderId,
      events: [
        for (final line in result.moved)
          AuditEvent(
            type: AuditEventType.moveItems,
            itemName: line.itemName,
            previousQty: line.quantity,
            newQty: 0,
            waiterId: user.username,
            waiterName: user.username,
            timestamp: now,
            note: 'გადატანილია — $destinationLabel',
            details: moveDetails(own: source, direction: 'OUT', line: line),
          ),
      ],
    );

    return result;
  }

  /// Closes an order that a transfer left with nothing on it, and frees its
  /// tables.
  ///
  /// An open table holding an empty bill is not a state anyone can act on: it
  /// reads as occupied on the floor, blocks the table for the next party, and
  /// holds a reservation open against the day close.
  ///
  /// What it deliberately does **not** do is write a sale record. Cancelling an
  /// order writes one flagged `isCancelled`, and the sales report counts those
  /// — `cancelledCount = rawSales.length - activeSales.length`. Nothing was
  /// cancelled here: the food was ordered, it was served, and it is on another
  /// table's bill. Recording a cancellation would inflate the venue's void rate
  /// for a move between two tables.
  ///
  /// The report is closed with a typed `TRANSFER_CLOSE` and locked, so the
  /// trail ends the way the Order did instead of staying open forever.
  /// [destination] is the Order the last items went to, when known.
  static Future<void> releaseEmptiedOrder(
    Order order, {
    required User user,
    Order? destination,
    AuditSource auditSource = AuditSource.pos,
  }) async {
    if (order.items.isNotEmpty || order.packageItems.isNotEmpty) return;
    // Already closed or cancelled: nothing to release, and no second event.
    if (_isFinalized(order.status)) return;

    for (final tableNumber in order.tableNumbers) {
      await DatabaseService.freeTable(
        tableNumber: tableNumber,
        floor: order.floor,
      );
    }

    // `closed`, not `cancelled`. Both stop the order being active, but only one
    // of them is a lie about what happened.
    order.status = OrderStatus.closed.storageValue;
    order.closedAt = DatabaseService.getCurrentDateTime();
    order.updatedAt = order.closedAt;
    order.recalculateTotal();
    await DatabaseService.updateOrder(order);

    // A booking whose party moved is finished, not cancelled — and a booking
    // left `confirmed` against a closed order is what stops the day closing.
    await DatabaseService.completeReservationForOrder(
      order.orderId,
      actorId: user.username,
      source: auditSource,
      reason: 'Order emptied by transfer',
    );

    await _appendTransferClose(
      order: order,
      destination: destination,
      user: user,
      auditSource: auditSource,
    );
  }

  static Future<void> _appendTransferClose({
    required Order order,
    required Order? destination,
    required User user,
    required AuditSource auditSource,
  }) async {
    final existing = DatabaseService.getAuditReport(order.orderId);
    if (existing != null &&
        existing.events.any((e) => e.type == AuditEventType.transferClose)) {
      return;
    }
    final event = AuditEvent(
      type: AuditEventType.transferClose,
      itemName: OrderAuditDetails.orderItemName,
      previousQty: 0,
      newQty: 0,
      waiterId: user.username,
      waiterName: user.username,
      timestamp: order.closedAt ?? DatabaseService.getCurrentDateTime(),
      note: destination != null
          ? 'ყველა პოზიცია გადატანილია — შეკვეთა #${destination.orderId}'
          : 'ყველა პოზიცია გადატანილია',
      details: <String, dynamic>{
        ...OrderAuditDetails.base(
          order: order,
          orderKind: _kindOf(order),
          source: auditSource,
          actorId: user.username,
        ),
        'closeReason': 'EMPTIED_BY_TRANSFER',
        'isFiscal': false,
        'grossAmount': 0.0,
        'collectedNow': 0.0,
        if (destination != null) 'transferredToOrderId': destination.orderId,
        if (destination != null)
          'transferredToTableRefs': OrderAuditDetails.tableRefs(destination),
      },
    );
    try {
      await DatabaseService.appendOrderAuditEvents(
        orderId: order.orderId,
        events: [event],
        statusOverride: AuditReportStatus.closed,
        lockReport: true,
        closedById: user.username,
        closedByName: user.username,
      );
    } on StateError catch (e) {
      if (!e.toString().toLowerCase().contains('locked')) rethrow;
      developer.log(
        'Audit report for order ${order.orderId} is locked; transfer close '
        'not recorded',
        name: 'order_item_transfer',
      );
    }
  }

  static String _kindOf(Order order) {
    if (order.packageId?.trim().isNotEmpty == true) {
      return OrderAuditDetails.package;
    }
    if (isTakeawayOrder(order)) return OrderAuditDetails.takeaway;
    return OrderAuditDetails.walkIn;
  }

  /// Adds [quantity] of [line] to [destination], stacking onto a line that is
  /// already the same thing.
  ///
  /// „The same thing" means the same item *and* the same comment. Merging on
  /// the key alone would silently drop one order's „ხახვის გარეშე".
  static void _merge({
    required Order destination,
    required OrderItem line,
    required int quantity,
    required double amount,
  }) {
    final comment = _normalizeComment(line.comment);
    for (final existing in destination.items) {
      if (existing.itemKey == line.itemKey &&
          existing.menuItemId == line.menuItemId &&
          existing.variantId == line.variantId &&
          _normalizeComment(existing.comment) == comment) {
        existing.quantity += quantity;
        existing.total = double.parse(
          (existing.total + amount).toStringAsFixed(2),
        );
        return;
      }
    }
    destination.items.add(
      OrderItem(
        // A full unmerged move keeps line identity; a split creates a new line.
        lineUuid: quantity == line.quantity ? line.lineUuid : null,
        itemKey: line.itemKey,
        itemName: line.itemName,
        unitPrice: line.unitPrice,
        quantity: quantity,
        total: amount,
        comment: line.comment,
        menuItemId: line.menuItemId,
        variantId: line.variantId,
      ),
    );
  }

  static String? _normalizeComment(String? comment) {
    final trimmed = comment?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static bool _isFinalized(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'paid' ||
        normalized == 'closed' ||
        normalized == 'cancelled';
  }
}
