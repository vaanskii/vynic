import 'dart:developer' as developer;

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'package:vynic/core/utils/payment_utils.dart';

import '../database_core.dart';
import '../repositories/audit_repository.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/closure_journal_repository.dart';
import '../repositories/reservation_repository.dart';
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
  /// [money] must reconcile: gross equals advance plus balance due, and a
  /// fiscal tender settles the balance. An internal close preserves gross and
  /// advance but normalizes current collection to zero. A fiscal closure that
  /// does not reconcile writes nothing at all — the guest was charged one
  /// number and a different one would have been booked.
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

    // Internal closure preserves the order's operational value while making
    // no claim that money changed hands. Normalize at this authoritative
    // boundary so an older caller that still supplies an automatic cash
    // selection cannot persist false collection metadata.
    final effectiveMoney = isFiscal
        ? money
        : ClosureMoney(
            gross: money.gross,
            advanceApplied: money.advanceApplied,
            collectedNow: 0,
          );
    final effectivePaymentMethod = isFiscal
        ? paymentMethod
        : PaymentUtils.methodNonFiscal;
    final effectiveTenderBreakdown = isFiscal
        ? tenderBreakdown
        : const <String, double>{};
    final effectiveFinalTransaction = isFiscal
        ? finalTransaction
        : <String, dynamic>{
            ...?finalTransaction,
            'isFiscal': false,
            'paymentMethod': PaymentUtils.methodNonFiscal,
            'paymentBreakdown': const <String, double>{},
            'cashAmount': 0.0,
            'cardAmount': 0.0,
            'collectedNow': 0.0,
          };

    final mismatch = effectiveMoney.describeMismatch(
      requireCurrentCollection: isFiscal,
    );
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
        finalTransaction: effectiveFinalTransaction,
      );
      return ClosureResult(
        outcome: resumed ? ClosureOutcome.resumed : ClosureOutcome.failed,
        closureId: existing.closureId,
        money: effectiveMoney,
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
      grossSaleAmount: effectiveMoney.gross,
      advanceApplied: effectiveMoney.advanceApplied,
      collectedNow: effectiveMoney.collectedNow,
      paymentMethod: effectivePaymentMethod,
      paymentBreakdown: effectiveMoney.breakdownWithAdvance(
        effectiveTenderBreakdown,
      ),
      actorId: closedById,
      actorName: closedByName,
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
      finalTransaction: effectiveFinalTransaction,
    );

    return ClosureResult(
      outcome: done ? ClosureOutcome.closed : ClosureOutcome.failed,
      closureId: closureId,
      money: effectiveMoney,
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

      return completeExistingSale(
        entry: current,
        order: order,
        saleRecordKey: current.saleRecordKey,
        closedByName: closedByName,
        customPaymentLabel: customPaymentLabel,
      );
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

  /// Completes a closure whose Sale already exists without writing the Sale.
  ///
  /// Normal close and startup recovery share this exact routine. The journal
  /// advances to [ClosurePhase.postSaleEffectsCompleted] only after the
  /// advance receipt, Order, physical Table, genuine linked Reservation, and
  /// typed audit report are all durable. A retry before that marker safely
  /// replays the same effects; a retry after it skips them.
  ///
  /// [source] says which mechanism is finishing the closure. A normal close is
  /// [AuditSource.pos]; startup recovery passes [AuditSource.systemRecovery]
  /// with [recoveryAction] so the typed close event records that the operator
  /// started it and the system completed it. The event type is unchanged
  /// either way, and a closure already finalized is never re-stamped.
  static Future<bool> completeExistingSale({
    required ClosureJournalEntry entry,
    required Order order,
    Object? saleRecordKey,
    String? closedByName,
    String? customPaymentLabel,
    AuditSource source = AuditSource.pos,
    String? recoveryAction,
  }) async {
    try {
      var current = ClosureJournalRepository.find(entry.closureId) ?? entry;
      final existingSaleKey =
          saleRecordKey ??
          current.saleRecordKey ??
          SalesRepository.findSaleKeyByClosureId(current.closureId);
      if (existingSaleKey == null) {
        developer.log(
          'Closure ${current.closureId}: existing Sale disappeared before '
          'post-Sale completion',
          name: 'close_table',
        );
        return false;
      }

      if (!current.phase.isAtLeast(ClosurePhase.saleWritten) ||
          current.saleRecordKey == null) {
        current = await ClosureJournalRepository.advance(
          current,
          phase: ClosurePhase.saleWritten,
          saleRecordKey: existingSaleKey,
        );
      }

      if (!current.phase.isAtLeast(ClosurePhase.postSaleEffectsCompleted)) {
        await _applyPostSaleEffects(
          current: current,
          order: order,
          saleRecordKey: existingSaleKey,
          closedByName: closedByName,
          customPaymentLabel: customPaymentLabel,
          source: source,
          recoveryAction: recoveryAction,
        );
        current = await ClosureJournalRepository.advance(
          current,
          phase: ClosurePhase.postSaleEffectsCompleted,
        );
      }

      if (!current.phase.isAtLeast(ClosurePhase.completed)) {
        await BusinessDayRepository.refreshDailySalesTotalForDate(
          BusinessDayRepository.getCurrentDate(),
        );
        await ClosureJournalRepository.advance(
          current,
          phase: ClosurePhase.completed,
          completedAt: DateTime.now(),
        );
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.orders,
            action: 'closed',
            payload: {'orderId': order.orderId, 'status': 'closed'},
          ),
        );
      }
      return true;
    } catch (e, stack) {
      developer.log(
        'Closure ${entry.closureId} post-Sale completion failed: $e',
        error: e,
        stackTrace: stack,
        name: 'close_table',
      );
      return false;
    }
  }

  static Future<void> _applyPostSaleEffects({
    required ClosureJournalEntry current,
    required Order order,
    required Object saleRecordKey,
    String? closedByName,
    String? customPaymentLabel,
    required AuditSource source,
    String? recoveryAction,
  }) async {
    final rawSale = DatabaseCore.salesBox?.get(saleRecordKey);
    final sale = rawSale is Map ? rawSale : null;
    final saleClosedAt = DateTime.tryParse(sale?['closedAt']?.toString() ?? '');
    final closureTimestamp =
        order.closedAt ?? saleClosedAt ?? current.startedAt;
    final effectiveActorId = current.actorId.trim().isEmpty
        ? 'system'
        : current.actorId;
    final journalActorName = current.actorName?.trim();
    final effectiveActorName = closedByName?.trim().isNotEmpty == true
        ? closedByName!.trim()
        : journalActorName?.isNotEmpty == true
        ? journalActorName!
        : effectiveActorId;
    final saleCustomLabel = sale?['customPaymentLabel']?.toString().trim();
    final effectiveCustomPaymentLabel =
        customPaymentLabel?.trim().isNotEmpty == true
        ? customPaymentLabel!.trim()
        : saleCustomLabel?.isNotEmpty == true
        ? saleCustomLabel
        : null;

    // The advance receipt is now spent. Reapplying the same closure id is a
    // no-op and does not alter the already-written Sale.
    final receiptId = current.advanceReceiptId;
    if (receiptId != null && current.advanceApplied > 0) {
      await SalesRepository.markAdvanceReceiptApplied(
        receiptId: receiptId,
        closureId: current.closureId,
      );
    }

    order.statusEnum = OrderStatus.closed;
    order.paymentMethod = current.isFiscal
        ? current.paymentMethod
        : PaymentUtils.methodNonFiscal;
    order.closedAt ??= closureTimestamp;
    order.updatedAt = closureTimestamp;
    order.closureId = current.closureId;
    await order.save();

    // Takeaway uses a synthetic `TA-` table identity and must not mutate the
    // physical floor. Package and Walk-In table orders follow the normal path.
    if (!isTakeawayOrder(order)) {
      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
        );
      }
    }

    await ReservationRepository.completeReservationByOrderId(
      order.orderId,
      failOnError: true,
    );

    final closingEvent = AuditEvent(
      type: current.isFiscal
          ? AuditEventType.close
          : AuditEventType.internalClose,
      itemName: 'ORDER',
      previousQty: 0,
      newQty: 0,
      waiterId: effectiveActorId,
      waiterName: effectiveActorName,
      timestamp: closureTimestamp,
      note: _closureNote(
        isFiscal: current.isFiscal,
        paymentMethod: current.paymentMethod,
        customPaymentLabel: effectiveCustomPaymentLabel,
        money: current,
      ),
      details: _closureDetails(
        order: order,
        money: current,
        actorId: effectiveActorId,
        actorName: effectiveActorName,
        customPaymentLabel: effectiveCustomPaymentLabel,
        source: source,
        recoveryAction: recoveryAction,
      ),
    );
    await AuditRepository.finalizeOrderClosureAudit(
      orderId: order.orderId,
      closingEvent: closingEvent,
      closedById: effectiveActorId,
      closedByName: effectiveActorName,
    );
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

  static Map<String, dynamic> _closureDetails({
    required Order order,
    required ClosureJournalEntry money,
    required String actorId,
    required String actorName,
    String? customPaymentLabel,
    required AuditSource source,
    String? recoveryAction,
  }) {
    final cashAmount = money.isFiscal
        ? (money.paymentBreakdown[PaymentUtils.methodCash] ?? 0.0)
        : 0.0;
    final cardAmount = money.isFiscal
        ? money.paymentBreakdown.entries
              .where((entry) => entry.key.startsWith('card'))
              .fold<double>(0, (sum, entry) => sum + entry.value)
        : 0.0;

    return <String, dynamic>{
      'orderId': order.orderId,
      'tableNumbers': List<String>.from(order.tableNumbers),
      'tableRefs': order.tableNumbers
          .map((tableNumber) => '${order.floor}/$tableNumber')
          .toList(growable: false),
      'floor': order.floor,
      'actorId': actorId,
      'actorName': actorName,
      // The actor is who initiated the closure; the source is what completed
      // it. They differ only when startup recovery finished the job.
      AuditSource.detailsKey: source.wireValue,
      if (recoveryAction != null && recoveryAction.isNotEmpty)
        'recoveryAction': recoveryAction,
      'businessDate': money.businessDate,
      'closureId': money.closureId,
      'isFiscal': money.isFiscal,
      'grossAmount': money.grossSaleAmount,
      'paymentMethod': money.isFiscal
          ? money.paymentMethod
          : PaymentUtils.methodNonFiscal,
      'paymentBreakdown': Map<String, double>.from(money.paymentBreakdown),
      'cashAmount': cashAmount,
      'cardAmount': cardAmount,
      'advanceApplied': money.advanceApplied,
      'collectedNow': money.collectedNow,
      'serviceFee': order.getServiceFee(),
      'discountAmount': order.discountAmount,
      'manualAdjustmentAmount': order.manualAdjustmentAmount,
      if (customPaymentLabel != null && customPaymentLabel.isNotEmpty)
        'customPaymentLabel': customPaymentLabel,
    };
  }
}
