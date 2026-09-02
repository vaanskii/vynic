import 'package:vynic/core/services/audit/audit_event_service.dart';

/// The action names written to the append-only audit log for money mutations.
///
/// They are constants rather than string literals at the call sites because
/// the backend groups by `action` and a typo would silently create a second,
/// invisible category.
abstract final class MoneyAuditAction {
  static const orderDiscountChanged = 'ORDER_DISCOUNT_CHANGED';
  static const orderManualAdjustmentChanged = 'ORDER_MANUAL_ADJUSTMENT_CHANGED';
  static const orderServiceFeeChanged = 'ORDER_SERVICE_FEE_CHANGED';
  static const saleCancelled = 'SALE_CANCELLED';
  static const saleRestoredToOrder = 'SALE_RESTORED_TO_ORDER';
  static const businessDateChanged = 'BUSINESS_DATE_CHANGED';
  static const receiptServiceFeePolicyChanged =
      'RECEIPT_SERVICE_FEE_POLICY_CHANGED';
  static const reportCostAssumptionChanged = 'REPORT_COST_ASSUMPTION_CHANGED';
  static const advanceRecorded = 'ADVANCE_RECORDED';
  static const closureRecovered = 'CLOSURE_RECOVERED';
}

/// Every mutation that can move a number a restaurant reports.
///
/// `AuditEventService` has existed since the first release and already does
/// the hard part — an append-only local queue that batches to Cloud and
/// survives being offline. What it did not have was callers on the money
/// paths: a discount, a manual adjustment, a cancelled sale and a business-date
/// change all changed what the restaurant reported and left nothing behind
/// saying who did it or what the figure was before.
///
/// These helpers are that missing half. Each one is a no-op when nothing
/// actually changed, so re-saving a form or reopening a dialog does not fill
/// the log with events that assert a change that never happened.
class MoneyAudit {
  MoneyAudit._();

  /// Two money amounts are the same figure if they agree to the tetri.
  static bool _sameAmount(double a, double b) => (a - b).abs() < 0.005;

  static Future<void> orderDiscountChanged({
    required String actorId,
    required int orderId,
    required double previousDiscount,
    required double newDiscount,
    required double previousTotal,
    required double newTotal,
  }) async {
    if (_sameAmount(previousDiscount, newDiscount)) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.orderDiscountChanged,
      userId: actorId,
      data: {
        'orderId': orderId,
        'previousDiscount': previousDiscount,
        'newDiscount': newDiscount,
        'previousTotal': previousTotal,
        'newTotal': newTotal,
      },
    );
  }

  static Future<void> orderManualAdjustmentChanged({
    required String actorId,
    required int orderId,
    required double previousAdjustment,
    required double newAdjustment,
    required double previousTotal,
    required double newTotal,
  }) async {
    if (_sameAmount(previousAdjustment, newAdjustment)) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.orderManualAdjustmentChanged,
      userId: actorId,
      data: {
        'orderId': orderId,
        'previousAdjustment': previousAdjustment,
        'newAdjustment': newAdjustment,
        'previousTotal': previousTotal,
        'newTotal': newTotal,
      },
    );
  }

  /// Covers both halves of the per-order service fee: whether it applies at
  /// all, and the percentage override when the order does not use the venue
  /// default. They are one event because they are one decision in the UI and
  /// both land in the same recalculated total.
  static Future<void> orderServiceFeeChanged({
    required String actorId,
    required int orderId,
    required bool previousIncluded,
    required bool newIncluded,
    double? previousPercent,
    double? newPercent,
    required double previousTotal,
    required double newTotal,
  }) async {
    final includedChanged = previousIncluded != newIncluded;
    final percentChanged =
        (previousPercent == null) != (newPercent == null) ||
        (previousPercent != null &&
            newPercent != null &&
            !_sameAmount(previousPercent, newPercent));
    if (!includedChanged && !percentChanged) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.orderServiceFeeChanged,
      userId: actorId,
      data: {
        'orderId': orderId,
        'previousIncluded': previousIncluded,
        'newIncluded': newIncluded,
        'previousPercent': previousPercent,
        'newPercent': newPercent,
        'previousTotal': previousTotal,
        'newTotal': newTotal,
      },
    );
  }

  /// A sale removed from every revenue figure that reads the sales box.
  ///
  /// [businessDate] is the date the sale belongs to, not the date it was
  /// cancelled on — the distinction is the whole reason `historical` exists.
  static Future<void> saleCancelled({
    required String actorId,
    required Object? orderId,
    required String businessDate,
    required double totalAmount,
    required String reason,
    required bool historical,
  }) async {
    await AuditEventService.logEvent(
      action: MoneyAuditAction.saleCancelled,
      userId: actorId,
      data: {
        'orderId': orderId,
        'businessDate': businessDate,
        'totalAmount': totalAmount,
        'reason': reason,
        'historical': historical,
      },
    );
  }

  static Future<void> saleRestoredToOrder({
    required String actorId,
    required Object? orderId,
    required String businessDate,
    required double totalAmount,
  }) async {
    await AuditEventService.logEvent(
      action: MoneyAuditAction.saleRestoredToOrder,
      userId: actorId,
      data: {
        'orderId': orderId,
        'businessDate': businessDate,
        'totalAmount': totalAmount,
      },
    );
  }

  /// Re-dating the POS. Everything recorded afterwards is attributed to
  /// [newDate], which is why the previous date is part of the record.
  static Future<void> businessDateChanged({
    required String actorId,
    required String previousDate,
    required String newDate,
    required String reason,
    required bool backdated,
  }) async {
    if (previousDate == newDate) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.businessDateChanged,
      userId: actorId,
      data: {
        'previousDate': previousDate,
        'newDate': newDate,
        'reason': reason,
        'backdated': backdated,
      },
    );
  }

  /// Display-only, but it changes what a printed document asserts, so it is
  /// recorded like any other policy change.
  static Future<void> receiptServiceFeePolicyChanged({
    required String actorId,
    required bool previousReceiptLineVisible,
    required bool newReceiptLineVisible,
    required bool previousCloseReceiptLineVisible,
    required bool newCloseReceiptLineVisible,
  }) async {
    if (previousReceiptLineVisible == newReceiptLineVisible &&
        previousCloseReceiptLineVisible == newCloseReceiptLineVisible) {
      return;
    }
    await AuditEventService.logEvent(
      action: MoneyAuditAction.receiptServiceFeePolicyChanged,
      userId: actorId,
      data: {
        'previousReceiptLineVisible': previousReceiptLineVisible,
        'newReceiptLineVisible': newReceiptLineVisible,
        'previousCloseReceiptLineVisible': previousCloseReceiptLineVisible,
        'newCloseReceiptLineVisible': newCloseReceiptLineVisible,
      },
    );
  }

  /// Money taken against a future closure.
  ///
  /// The receipt is dated when the money was collected, which may be days
  /// before the order closes, so the event carries both that date and the
  /// order it is held against.
  static Future<void> advanceRecorded({
    required String actorId,
    required int orderId,
    required double previousAmount,
    required double newAmount,
    required String businessDate,
    String? receiptId,
  }) async {
    if (_sameAmount(previousAmount, newAmount)) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.advanceRecorded,
      userId: actorId,
      data: {
        'orderId': orderId,
        'previousAmount': previousAmount,
        'newAmount': newAmount,
        'businessDate': businessDate,
        'receiptId': receiptId,
      },
    );
  }

  /// A closure that a crash interrupted, and what startup did about it.
  ///
  /// Recorded unconditionally: an operator who saw a table stay open, or a
  /// sale appear without them closing anything, needs the log to say why.
  static Future<void> closureRecovered({
    required String actorId,
    required String closureId,
    required int orderId,
    required String businessDate,
    required double grossSaleAmount,
    required String action,
  }) async {
    await AuditEventService.logEvent(
      action: MoneyAuditAction.closureRecovered,
      userId: actorId,
      data: {
        'closureId': closureId,
        'orderId': orderId,
        'businessDate': businessDate,
        'grossSaleAmount': grossSaleAmount,
        'recoveryAction': action,
      },
    );
  }

  /// Lease, staff cost and food-margin inputs to the monthly report.
  ///
  /// These are operator assumptions, not measured cost — the report's whole
  /// expense side derives from them, so a changed assumption changes every
  /// profit figure the report has ever shown for that period.
  ///
  /// [scope] is `'default'` for the venue-wide value or `YYYY-MM` for a
  /// per-month override.
  static Future<void> reportCostAssumptionChanged({
    required String actorId,
    required String field,
    required String scope,
    required Object? previousValue,
    required Object? newValue,
  }) async {
    if (previousValue is double &&
        newValue is double &&
        _sameAmount(previousValue, newValue)) {
      return;
    }
    if (previousValue == newValue) return;
    await AuditEventService.logEvent(
      action: MoneyAuditAction.reportCostAssumptionChanged,
      userId: actorId,
      data: {
        'field': field,
        'scope': scope,
        'previousValue': previousValue,
        'newValue': newValue,
      },
    );
  }
}
