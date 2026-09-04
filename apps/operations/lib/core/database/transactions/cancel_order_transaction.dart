import 'dart:developer' as developer;

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/services/sync/sync_events.dart';

import '../database_core.dart';
import '../repositories/audit_repository.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/reservation_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/table_repository.dart';

/// What [CancelOrderTransaction.run] found and did.
enum CancelOrderOutcome {
  /// The Order was live and is now cancelled with its full history.
  cancelled,

  /// The Order was already cancelled. Nothing was written.
  alreadyCancelled,

  /// No Order with that id exists here.
  notFound,

  /// The Order is closed. A closed Order has a Sale; it must be restored
  /// before it can be cancelled, otherwise revenue would disagree with status.
  notCancellable,

  /// A write failed. State may be partially applied; a retry converges.
  failed,
}

/// The one way a live Order is cancelled.
///
/// The POS detail screen, the Takeaway home panel, the Admin close-day repair
/// list, and the Manager app (through `ORDER_CANCEL` and
/// `ORDER_STATUS_UPDATE status=cancelled`) all arrive here. Before this
/// routine existed the detail screen was the only path that left durable
/// evidence — a typed `CANCEL_TABLE` event, a locked report and a non-revenue
/// cancelled Sale record — while the others merely flipped the status, and the
/// Manager cancel hard-deleted the Order together with its audit report.
///
/// Every step checks for its own prior effect, and the Order status is written
/// last, so a retry after a crash (or a command delivered twice) converges on
/// exactly one cancellation: one audit event, one cancelled Sale, one
/// Reservation transition, and no complaint that the table is already free.
class CancelOrderTransaction {
  CancelOrderTransaction._();

  /// The `paymentMethod` the POS has always written on a cancelled Order's
  /// record. It is a sentinel, not a tender.
  static const String cancelledPaymentMethod = 'cancelled';

  /// `finalTransaction.type` of a cancelled Order's record.
  static const String cancelledTransactionType = 'cancelled_order';

  static Future<CancelOrderOutcome> run({
    required int orderId,
    required String actorId,
    String? actorName,
    required AuditSource source,
    String? reason,
    String? approvedBy,
  }) async {
    final order = OrderRepository.getOrder(orderId);
    if (order == null) return CancelOrderOutcome.notFound;

    switch (order.statusEnum) {
      case OrderStatus.cancelled:
        return CancelOrderOutcome.alreadyCancelled;
      case OrderStatus.closed:
        return CancelOrderOutcome.notCancellable;
      case OrderStatus.pending:
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.served:
      case OrderStatus.unknown:
        break;
    }

    final effectiveActorId = actorId.trim().isEmpty ? 'unknown' : actorId.trim();
    final effectiveActorName = actorName?.trim().isNotEmpty == true
        ? actorName!.trim()
        : effectiveActorId;
    final trimmedApprover = approvedBy?.trim();
    final trimmedReason = reason?.trim();
    final now = BusinessDayRepository.getCurrentDateTime();

    try {
      await _appendCancellationAudit(
        order: order,
        actorId: effectiveActorId,
        actorName: effectiveActorName,
        source: source,
        reason: trimmedReason,
        approvedBy: trimmedApprover,
        timestamp: now,
      );

      await _writeCancelledSaleRecord(
        order: order,
        reason: trimmedReason,
        cancelledAt: now,
      );

      // A genuine advance booking whose party was seated and then cancelled
      // keeps its identity and its Order link; only its status moves.
      await ReservationRepository.cancelReservationByOrderId(order.orderId);

      order.statusEnum = OrderStatus.cancelled;
      order.updatedAt = now;
      await order.save();

      // Takeaway lives on a synthetic `TA-` table and must not touch the floor.
      if (!isTakeawayOrder(order)) {
        for (final tableNumber in order.tableNumbers) {
          await TableRepository.freeTable(
            tableNumber: tableNumber,
            floor: order.floor,
          );
        }
      }

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.orders,
          action: 'status_changed',
          payload: {
            'orderId': order.orderId,
            'status': OrderStatus.cancelled.storageValue,
          },
        ),
      );
      return CancelOrderOutcome.cancelled;
    } catch (e, stack) {
      developer.log(
        'Cancellation of order $orderId failed: $e',
        error: e,
        stackTrace: stack,
        name: 'cancel_order',
      );
      return CancelOrderOutcome.failed;
    }
  }

  /// `WALK_IN`, `TAKEAWAY`, `PACKAGE` or `RESERVATION` — what kind of Order
  /// this was, for the audit trail. Not a stored field.
  static String orderKindOf(Order order) {
    if (isTakeawayOrder(order)) return 'TAKEAWAY';
    if (order.packageId != null && order.packageId!.isNotEmpty) {
      return 'PACKAGE';
    }
    if (_linkedBookingId(order) != null) return 'RESERVATION';
    return 'WALK_IN';
  }

  static String? _linkedBookingId(Order order) {
    final box = DatabaseCore.reservationBox;
    if (box == null) return null;
    for (final reservation in box.values) {
      if (reservation.linkedOrderId == order.orderId &&
          ReservationClassification.isRealAdvanceBooking(reservation)) {
        return reservation.id;
      }
    }
    return null;
  }

  static Future<void> _appendCancellationAudit({
    required Order order,
    required String actorId,
    required String actorName,
    required AuditSource source,
    String? reason,
    String? approvedBy,
    required DateTime timestamp,
  }) async {
    final report = AuditRepository.getAuditReport(order.orderId);
    final alreadyRecorded =
        report != null &&
        report.status == AuditReportStatus.cancelled &&
        report.events.any((event) => event.type == AuditEventType.cancelTable);
    if (alreadyRecorded) return;

    final totalQuantity = order.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final noteParts = <String>[
      if (reason != null && reason.isNotEmpty) reason,
      if (approvedBy != null && approvedBy.isNotEmpty) 'Approved by $approvedBy',
    ];
    final closerId = approvedBy != null && approvedBy.isNotEmpty
        ? approvedBy
        : actorId;
    final closerName = approvedBy != null && approvedBy.isNotEmpty
        ? approvedBy
        : actorName;

    final event = AuditEvent(
      type: AuditEventType.cancelTable,
      itemName: 'ORDER',
      previousQty: totalQuantity,
      newQty: 0,
      waiterId: actorId,
      waiterName: actorName,
      timestamp: timestamp,
      note: noteParts.isEmpty ? null : noteParts.join(' • '),
      details: <String, dynamic>{
        'orderId': order.orderId,
        'orderKind': orderKindOf(order),
        'tableNumbers': List<String>.from(order.tableNumbers),
        'tableRefs': order.tableNumbers
            .map((tableNumber) => '${order.floor}/$tableNumber')
            .toList(growable: false),
        'floor': order.floor,
        AuditSource.detailsKey: source.wireValue,
        'actorId': actorId,
        'actorName': actorName,
        if (approvedBy != null && approvedBy.isNotEmpty)
          'approvedBy': approvedBy,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'businessDate': BusinessDayRepository.getCurrentDate()
            .toIso8601String()
            .split('T')[0],
        'grossAmount': order.grossAmount,
        if (_linkedBookingId(order) != null)
          'reservationId': _linkedBookingId(order),
      },
    );

    try {
      await AuditRepository.appendOrderAuditEvents(
        orderId: order.orderId,
        events: [event],
        statusOverride: AuditReportStatus.cancelled,
        lockReport: true,
        closedById: closerId,
        closedByName: closerName,
      );
    } on StateError catch (e) {
      // A report locked by an earlier lifecycle cannot take the event. The
      // cancellation itself still proceeds, as the detail screen always did.
      if (!e.toString().toLowerCase().contains('locked')) rethrow;
      developer.log(
        'Audit report for order ${order.orderId} is locked; cancellation '
        'continues without a new event',
        name: 'cancel_order',
      );
    }
  }

  /// The record the sales box holds for a cancelled Order, if one exists.
  static Object? findCancelledSaleKey(int orderId) {
    final box = DatabaseCore.salesBox;
    if (box == null) return null;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['orderId'] != orderId) continue;
      if (raw['isCancelled'] != true) continue;
      final finalTransaction = raw['finalTransaction'];
      final type = finalTransaction is Map ? finalTransaction['type'] : null;
      if (type == cancelledTransactionType ||
          raw['paymentMethod'] == cancelledPaymentMethod) {
        return key;
      }
    }
    return null;
  }

  /// The non-revenue record the POS has always written for a cancelled Order:
  /// `isFiscal=false`, `isCancelled=true`, nothing collected. Every revenue
  /// figure excludes it through `SalesRepository.countsAsRevenue`.
  static Future<void> _writeCancelledSaleRecord({
    required Order order,
    String? reason,
    required DateTime cancelledAt,
  }) async {
    if (findCancelledSaleKey(order.orderId) != null) return;

    final subtotal = double.parse(
      (order.getPackageSubtotal() + order.getAdditionalItemsSubtotal())
          .toStringAsFixed(2),
    );
    final serviceFee = order.getServiceFee();
    final key = await SalesRepository.saveSaleRecord(
      orderId: order.orderId,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      items: [...order.packageItems, ...order.items],
      totalAmount: order.totalAmount,
      paymentMethod: cancelledPaymentMethod,
      paymentBreakdown: null,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      closedAt: cancelledAt,
      includeServiceFee: order.includeServiceFee,
      discountAmount: order.discountAmount,
      advanceApplied: order.effectiveAdvanceAmount,
      grossSaleAmount: order.grossAmount,
      collectedNow: 0.0,
      advanceAmount: 0.0,
      subtotalAmount: subtotal,
      manualAdjustmentAmount: order.manualAdjustmentAmount,
      finalTransaction: {
        'type': cancelledTransactionType,
        'orderId': order.orderId,
        'subtotal': subtotal,
        'serviceFee': double.parse(serviceFee.toStringAsFixed(2)),
        'total': double.parse(order.totalAmount.toStringAsFixed(2)),
        'comment': reason ?? '',
        'isFiscal': false,
      },
      isFiscal: false,
      isCancelled: true,
      cancelledAt: cancelledAt,
    );
    if (key == null) {
      throw StateError('Cancelled Sale record for order ${order.orderId} was not written');
    }
  }
}
