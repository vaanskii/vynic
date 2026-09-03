import 'dart:developer' as developer;

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation_status.dart';

import '../database_core.dart';
import '../repositories/audit_repository.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/closure_journal_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/table_repository.dart';

/// Why a closure did not happen, or that it already had.
enum ClosureOutcome {
  /// The closure completed on this call.
  closed,

  /// A completed closure for this order already existed. Nothing was written
  /// and no second sale exists — this is what a double-click looks like.
  alreadyClosed,

  /// An interrupted closure was found and finished on this call.
  resumed,

  /// The order is not in the box.
  orderNotFound,

  /// The tender does not settle the balance due, or gross does not equal
  /// advance plus balance. Nothing was written.
  moneyMismatch,

  failed,
}

/// The result of asking for a closure.
class ClosureResult {
  const ClosureResult({
    required this.outcome,
    this.closureId,
    this.money,
    this.detail,
  });

  final ClosureOutcome outcome;
  final String? closureId;
  final ClosureMoney? money;

  /// Why it was refused, when it was.
  final String? detail;

  bool get isSuccess =>
      outcome == ClosureOutcome.closed ||
      outcome == ClosureOutcome.alreadyClosed ||
      outcome == ClosureOutcome.resumed;
}

/// Closes a table's order once, and only once.
///
/// Hive has no cross-box transaction. A closure writes to the sales box, the
/// order box, the table box, the reservation box, the audit boxes and
/// settings, and a process killed between any two of those used to leave the
/// floor and the sales history disagreeing, with nothing recording that a
/// closure had even been attempted. Retrying wrote a second sale; so did a
/// second tap on the button.
///
/// Two things fix that, and neither pretends the boxes are atomic:
///
/// - **Closure identity.** Every attempt carries a `closureId`, stamped onto
///   the order and onto the sale it writes. A closure whose sale already
///   exists never writes another, whether the duplicate came from a retry, a
///   double-click, or a restart.
/// - **A durable journal.** The intent — order, kind, and the full money
///   split — is recorded before the first write and the phase after each one.
///   An interrupted closure is therefore a known state that
///   `ClosureRecoveryService` can finish, rather than wreckage.
///
/// The order of writes matters and is deliberate: the sale is written *first*,
/// because a recorded sale with an order still marked open is recoverable
/// (the recovery finishes the bookkeeping) while a freed table with no sale is
/// money that silently vanished.
class CloseTableTransaction {
  CloseTableTransaction._();

  /// Closes [orderId], or reports that it is already closed.
  ///
  /// [money] must reconcile: gross equals advance plus balance due, and the
  /// tender settles the balance. A closure that does not reconcile writes
  /// nothing at all — the guest was charged one number and a different one
  /// would have been booked.
  static Future<ClosureResult> run({
    required int orderId,
    required ClosureMoney money,
    required String paymentMethod,
    required Map<String, double> tenderBreakdown,
    required String closedById,
    required bool isFiscal,
    String? closedByName,
    String? customPaymentLabel,
    List<OrderItem>? saleItems,
    double? subtotalAmount,
    Map<String, dynamic>? finalTransaction,
  }) async {
    Order? order;
    try {
      order = DatabaseCore.orderBox!.values.firstWhere(
        (o) => o.orderId == orderId,
      );
    } catch (_) {
      order = null;
    }

    // An order already settled is the double-click case. Answer from the
    // journal rather than from the order's status, because the status is set
    // partway through and a crash can leave it either way.
    final existing = ClosureJournalRepository.findByOrderId(orderId);
    if (existing != null && existing.isComplete) {
      return ClosureResult(
        outcome: ClosureOutcome.alreadyClosed,
        closureId: existing.closureId,
        money: ClosureMoney(
          gross: existing.grossSaleAmount,
          advanceApplied: existing.advanceApplied,
          collectedNow: existing.collectedNow,
        ),
      );
    }

    if (order == null) {
      return const ClosureResult(outcome: ClosureOutcome.orderNotFound);
    }

    final mismatch = money.describeMismatch();
    if (mismatch != null) {
      developer.log(
        'Closure refused for order #$orderId: $mismatch',
        name: 'close_table',
      );
      return ClosureResult(
        outcome: ClosureOutcome.moneyMismatch,
        detail: mismatch,
      );
    }

    // Resume an interrupted attempt rather than starting a second one.
    if (existing != null) {
      final resumed = await _finish(
        entry: existing,
        order: order,
        closedById: closedById,
        closedByName: closedByName,
        customPaymentLabel: customPaymentLabel,
        saleItems: saleItems ?? _defaultSaleItems(order),
        subtotalAmount: subtotalAmount,
        finalTransaction: finalTransaction,
      );
      return ClosureResult(
        outcome: resumed ? ClosureOutcome.resumed : ClosureOutcome.failed,
        closureId: existing.closureId,
        money: money,
      );
    }

    final closureId =
        order.closureId ?? ClosureJournalRepository.newClosureId();
    final businessDate = BusinessDayRepository.dateKey(
      BusinessDayRepository.getCurrentDate(),
    );

    // The closure id lands on the order before anything financial happens, so
    // a crash immediately after leaves a traceable attempt rather than an
    // anonymous half-close.
    order.closureId = closureId;
    await order.save();

    final entry = ClosureJournalEntry(
      closureId: closureId,
      orderId: orderId,
      phase: ClosurePhase.started,
      businessDate: businessDate,
      isFiscal: isFiscal,
      grossSaleAmount: money.gross,
      advanceApplied: money.advanceApplied,
      collectedNow: money.collectedNow,
      paymentMethod: paymentMethod,
      paymentBreakdown: money.breakdownWithAdvance(tenderBreakdown),
      actorId: closedById,
      startedAt: DateTime.now(),
      advanceReceiptId: order.advanceReceiptId,
    );
    await ClosureJournalRepository.write(entry);

    final done = await _finish(
      entry: entry,
      order: order,
      closedById: closedById,
      closedByName: closedByName,
      customPaymentLabel: customPaymentLabel,
      saleItems: saleItems ?? _defaultSaleItems(order),
      subtotalAmount: subtotalAmount,
      finalTransaction: finalTransaction,
    );

    return ClosureResult(
      outcome: done ? ClosureOutcome.closed : ClosureOutcome.failed,
      closureId: closureId,
      money: money,
    );
  }

  static List<OrderItem> _defaultSaleItems(Order order) => <OrderItem>[
    ...order.packageItems,
    ...order.items,
  ];

  /// Carries [entry] from wherever it is to [ClosurePhase.completed].
  ///
  /// Every step is safe to repeat, which is what lets recovery call this on an
  /// entry it did not start.
  static Future<bool> _finish({
    required ClosureJournalEntry entry,
    required Order order,
    required String closedById,
    String? closedByName,
    String? customPaymentLabel,
    required List<OrderItem> saleItems,
    double? subtotalAmount,
    Map<String, dynamic>? finalTransaction,
  }) async {
    try {
      var current = entry;

      // ── 1. The sale. Written first: a sale with an order still open is
      // recoverable, a freed table with no sale is money that vanished.
      if (!current.phase.isAtLeast(ClosurePhase.saleWritten)) {
        final closedAt = BusinessDayRepository.getCurrentDateTime();
        final key = await SalesRepository.saveSaleRecord(
          orderId: order.orderId,
          tableNumbers: order.tableNumbers,
          floor: order.floor,
          items: saleItems,
          // The sale is worth what the guest consumed. An advance moves which
          // day the money was collected on, never what the sale was worth.
          totalAmount: current.grossSaleAmount,
          paymentMethod: current.paymentMethod,
          paymentBreakdown: current.paymentBreakdown,
          customPaymentLabel: customPaymentLabel,
          createdBy: order.createdBy,
          createdAt: order.createdAt,
          closedAt: closedAt,
          includeServiceFee: order.includeServiceFee,
          discountAmount: order.discountAmount,
          advanceAmount: current.advanceApplied,
          subtotalAmount: subtotalAmount,
          manualAdjustmentAmount: order.manualAdjustmentAmount,
          finalTransaction: finalTransaction,
          isFiscal: current.isFiscal,
          closureId: current.closureId,
          closedById: closedById,
          grossSaleAmount: current.grossSaleAmount,
          advanceApplied: current.advanceApplied,
          collectedNow: current.collectedNow,
          businessDate: current.businessDate,
          advanceReceiptId: current.advanceReceiptId,
        );
        if (key == null) {
          developer.log(
            'Closure ${current.closureId}: sale write failed',
            name: 'close_table',
          );
          return false;
        }
        current = await ClosureJournalRepository.advance(
          current,
          phase: ClosurePhase.saleWritten,
          saleRecordKey: key,
        );
      }

      // ── 2. The advance receipt is now spent. Idempotent.
      final receiptId = current.advanceReceiptId;
      if (receiptId != null && current.advanceApplied > 0) {
        await SalesRepository.markAdvanceReceiptApplied(
          receiptId: receiptId,
          closureId: current.closureId,
        );
      }

      // ── 3. The order. Repeating this is a no-op.
      order.statusEnum = OrderStatus.closed;
      order.paymentMethod = current.isFiscal
          ? current.paymentMethod
          : 'non-fiscal';
      final closureTimestamp = BusinessDayRepository.getCurrentDateTime();
      order.closedAt ??= closureTimestamp;
      order.updatedAt = closureTimestamp;
      await order.save();

      // ── 4. The floor. Freeing a free table is a no-op.
      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
        );
      }

      // ── 5. The reservation.
      await _completeLinkedReservation(order.orderId);

      // ── 6. The audit trail. Appending to a locked report throws; that is
      // the second attempt finding the first one's work, not a failure.
      final closingEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: closedById,
        waiterName: closedByName ?? closedById,
        timestamp: order.closedAt ?? closureTimestamp,
        note: _closureNote(
          isFiscal: current.isFiscal,
          paymentMethod: current.paymentMethod,
          customPaymentLabel: customPaymentLabel,
          money: current,
        ),
      );
      try {
        await AuditRepository.appendOrderAuditEvents(
          orderId: order.orderId,
          events: [closingEvent],
          statusOverride: AuditReportStatus.closed,
          lockReport: true,
          closedById: closedById,
          closedByName: closedByName ?? closedById,
        );
      } catch (e) {
        developer.log(
          'Audit report append failed for closure ${current.closureId}: $e',
        );
      }

      // ── 7. The derived daily figure, recomputed from the records.
      await BusinessDayRepository.refreshDailySalesTotalForDate(
        BusinessDayRepository.getCurrentDate(),
      );

      await ClosureJournalRepository.advance(
        current,
        phase: ClosurePhase.completed,
        completedAt: DateTime.now(),
      );
      return true;
    } catch (e, stack) {
      developer.log(
        'Closure ${entry.closureId} failed: $e',
        error: e,
        stackTrace: stack,
        name: 'close_table',
      );
      return false;
    }
  }

  static String _closureNote({
    required bool isFiscal,
    required String paymentMethod,
    String? customPaymentLabel,
    required ClosureJournalEntry money,
  }) {
    final base = !isFiscal
        ? 'Order closed (non-fiscal)'
        : (customPaymentLabel != null && customPaymentLabel.isNotEmpty
              ? 'Order closed with $customPaymentLabel'
              : 'Order closed with $paymentMethod');
    if (money.advanceApplied <= 0) return base;
    return '$base • gross ${money.grossSaleAmount.toStringAsFixed(2)}, '
        'advance ${money.advanceApplied.toStringAsFixed(2)}, '
        'collected ${money.collectedNow.toStringAsFixed(2)}';
  }

  static Future<void> _completeLinkedReservation(int orderId) async {
    final dateString = BusinessDayRepository.dateKey(
      BusinessDayRepository.getCurrentDate(),
    );
    for (final reservation in DatabaseCore.reservationBox!.values) {
      final resDateString = BusinessDayRepository.dateKey(
        reservation.reservationDate,
      );
      final matchesLinked = reservation.linkedOrderId == orderId;
      final matchesLegacyNote =
          reservation.notes != null &&
          reservation.notes!.contains('Order #$orderId');
      if (resDateString == dateString && (matchesLinked || matchesLegacyNote)) {
        if (reservation.statusEnum != ReservationStatus.completed) {
          reservation.statusEnum = ReservationStatus.completed;
          await reservation.save();
        }
        return;
      }
    }
  }
}
