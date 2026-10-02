import 'package:vynic/core/database/local_data_admission.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'dart:developer' as developer;
import '../../services/edge/orders_tables/shadow.dart';
import '../../services/edge/orders_tables/pos_shadow_projection.dart';

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

import '../database_core.dart';
import '../repositories/audit_repository.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/order_table_mutation_repository.dart';

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
    Order? expectedOrder,
    String? requestId,
  }) {
    final captured = expectedOrder == null
        ? OrderRepository.getOrder(orderId)
        : OrderTableMutationRepository.capture(expectedOrder);
    return UpdateReadiness.mutate(
      'cancelOrder',
      () => _updateTrackedRun(
        orderId: orderId,
        actorId: actorId,
        actorName: actorName,
        source: source,
        reason: reason,
        approvedBy: approvedBy,
        expectedOrder: captured,
        explicitExpectedOrder: expectedOrder != null,
        requestId: requestId,
      ),
    );
  }

  static Future<CancelOrderOutcome> _updateTrackedRun({
    required int orderId,
    required String actorId,
    String? actorName,
    required AuditSource source,
    String? reason,
    String? approvedBy,
    Order? expectedOrder,
    required bool explicitExpectedOrder,
    String? requestId,
  }) async {
    final effectiveActorId = actorId.trim().isEmpty
        ? 'unknown'
        : actorId.trim();
    final effectiveActorName = actorName?.trim().isNotEmpty == true
        ? actorName!.trim()
        : effectiveActorId;
    final previous = requestId == null
        ? null
        : OrderTableMutationRepository.read(requestId);
    if (previous != null) {
      if (previous.kind != 'cancel' ||
          previous.request['order']['orderId'] != orderId) {
        throw OrderMutationConflict(
          'request_conflict',
          'Request ID belongs to another lifecycle',
        );
      }
      OrderTableMutationRepository.retry(requestId!, {
        'order': explicitExpectedOrder && expectedOrder != null
            ? OrderTableMutationRepository.image(expectedOrder)
            : previous.request['order'],
        'actor': effectiveActorId,
        'actorName': effectiveActorName,
        'source': source.wireValue,
        'reason': reason?.trim(),
        'approvedBy': approvedBy?.trim(),
      });
      return CancelOrderOutcome.alreadyCancelled;
    }
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

    final report = AuditRepository.getAuditReport(order.orderId);
    final existingSaleKey = findCancelledSaleKey(order.orderId);
    final legacyPrefix =
        existingSaleKey != null &&
        report?.locked == true &&
        report?.status == AuditReportStatus.cancelled &&
        report!.events.any((e) => e.type == AuditEventType.cancelTable);
    if (!legacyPrefix) {
      if (expectedOrder != null)
        OrderTableMutationRepository.requireFresh(expectedOrder);
      OrderTableMutationRepository.requireFresh(order);
    }
    final id = requestId ?? const Uuid().v4();
    final now = OrderTableMutationRepository.now();
    final event = _cancellationEvent(
      order: order,
      actorId: effectiveActorId,
      actorName: effectiveActorName,
      source: source,
      reason: reason?.trim(),
      approvedBy: approvedBy?.trim(),
      timestamp: now,
      requestId: id,
    );
    if (report?.locked == true && !legacyPrefix)
      throw OrderMutationConflict(
        'repair_required',
        'Cancellation audit is locked by another lifecycle',
      );
    final baseReport =
        report ??
        AuditReport(
          reportId: AuditRepository.buildAuditReportKey(orderId),
          orderId: orderId,
          tableNumbers: order.tableNumbers,
          floor: order.floor,
          openedById: order.createdBy,
          openedByName: order.createdBy,
          openedAt: order.createdAt,
          status: AuditReportStatus.open,
          locked: false,
          updatedAt: order.createdAt,
          events: const [],
        );
    final sequence = baseReport.events.fold<int>(
      0,
      (n, e) => (e.sequence ?? -1) >= n ? e.sequence! + 1 : n,
    );
    final cancelledReport = legacyPrefix
        ? baseReport
        : baseReport.copyWith(
            events: [
              ...baseReport.events,
              event.copyWith(sequence: sequence),
            ],
            status: AuditReportStatus.cancelled,
            locked: true,
            closedAt: now,
            closedById: approvedBy?.trim().isNotEmpty == true
                ? approvedBy!.trim()
                : effectiveActorId,
            closedByName: approvedBy?.trim().isNotEmpty == true
                ? approvedBy!.trim()
                : effectiveActorName,
            updatedAt: now,
          );
    final effects = <Map<String, dynamic>>[
      OrderTableMutationRepository.effect(
        'auditReport',
        AuditRepository.buildAuditReportKey(orderId),
        cancelledReport.toMap(),
      ),
      OrderTableMutationRepository.effect(
        'sales',
        existingSaleKey ?? '$id:cancelled-sale',
        existingSaleKey == null
            ? OrderTableMutationRepository.cancellationSaleImage(
                order,
                now,
                reason?.trim(),
                posSaleId: const Uuid().v4(),
                businessDate: OrderTableMutationRepository.dateKey,
              )
            : DatabaseCore.salesBox!.get(existingSaleKey),
      ),
    ];
    final bookings =
        DatabaseCore.reservationBox
            ?.toMap()
            .entries
            .where(
              (e) =>
                  e.value.linkedOrderId == orderId &&
                  ReservationClassification.isRealAdvanceBooking(e.value),
            )
            .toList() ??
        [];
    if (bookings.length > 1)
      throw OrderMutationConflict(
        'repair_required',
        'Cancellation Reservation link is ambiguous',
      );
    if (bookings.isNotEmpty && bookings.single.value.status != 'cancelled') {
      final entry = bookings.single;
      final booking = entry.value;
      effects.add(
        OrderTableMutationRepository.effect(
          'reservation',
          entry.key,
          OrderTableMutationRepository.reservationImage(booking)
            ..['status'] = 'cancelled',
        ),
      );
      final audit = AuditEventLog(
        id: '$id:reservation',
        action: ReservationAuditAction.cancel,
        userId: effectiveActorId,
        entityType: GlobalAuditEntity.reservation,
        entityId: booking.id,
        createdAt: DateTime.now(),
        deviceType: 'pos',
        data: {
          ...ReservationAudit.snapshot(booking),
          'requestId': id,
          'orderId': orderId,
          'previousStatus': booking.status,
          'newStatus': 'cancelled',
          'status': 'cancelled',
          'actorId': effectiveActorId,
          'actorName': effectiveActorName,
          'source': source.wireValue,
          'businessDate': OrderTableMutationRepository.dateKey,
          'reason': reason?.trim() ?? 'Order cancelled',
        },
      );
      effects.add(
        OrderTableMutationRepository.effect(
          'auditEvent',
          audit.id,
          audit.toMap(),
        ),
      );
    }
    if (!isTakeawayOrder(order)) {
      for (final number in order.tableNumbers) {
        final rows = DatabaseCore.tableBox!
            .toMap()
            .entries
            .where(
              (e) =>
                  e.value.floor == order.floor && e.value.tableNumber == number,
            )
            .toList();
        if (rows.length != 1 ||
            rows.single.value.activeOrderId != null &&
                rows.single.value.activeOrderId != orderId)
          throw OrderMutationConflict(
            'repair_required',
            'Cancellation table ownership is ambiguous',
          );
        final after = TableModel.fromJson(
          OrderTableMutationRepository.tableImage(rows.single.value),
        )..free();
        effects.add(
          OrderTableMutationRepository.effect(
            'tables',
            rows.single.key,
            OrderTableMutationRepository.tableImage(after),
          ),
        );
      }
    }
    final after = OrderTableMutationRepository.capture(order)
      ..status = 'cancelled'
      ..updatedAt = now;
    final row = OrderTableMutationRepository.persisted(
      orderId,
      uuid: order.orderUuid,
    )!;
    effects.add(
      OrderTableMutationRepository.effect(
        'orders',
        row.$1,
        OrderTableMutationRepository.image(after),
      ),
    );
    try {
      await OrderTableShadow.observe(
        proposed: () => PosShadowProjection.cancelled(after, proposed: true),
        actual: () => PosShadowProjection.cancelled(after, proposed: false),
        operation: () async {
          await OrderTableMutationRepository.commit(
            id: id,
            kind: 'cancel',
            request: {
              'order': OrderTableMutationRepository.image(order),
              'actor': effectiveActorId,
              'actorName': effectiveActorName,
              'source': source.wireValue,
              'reason': reason?.trim(),
              'approvedBy': approvedBy?.trim(),
            },
            order: after,
            effects: effects,
          );
        },
      );
      return CancelOrderOutcome.cancelled;
    } catch (error, stack) {
      if (LocalDataAdmission.failure == null) rethrow;
      developer.log(
        'Cancellation of order $orderId requires recovery',
        error: error,
        stackTrace: stack,
        name: 'cancel_order',
      );
      return CancelOrderOutcome.failed;
    }
  }

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

  static AuditEvent _cancellationEvent({
    required Order order,
    required String actorId,
    required String actorName,
    required AuditSource source,
    String? reason,
    String? approvedBy,
    required DateTime timestamp,
    required String requestId,
  }) {
    final totalQuantity = order.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final noteParts = <String>[
      if (reason != null && reason.isNotEmpty) reason,
      if (approvedBy != null && approvedBy.isNotEmpty)
        'Approved by $approvedBy',
    ];
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
        'orderUuid': order.orderUuid,
        'requestId': requestId,
        'orderKind': orderKindOf(order),
        'tableNumbers': List<String>.from(order.tableNumbers),
        'tableRefs': order.tableNumbers
            .map((tableNumber) => '${order.floor}/$tableNumber')
            .toList(growable: false),
        'floor': order.floor,
        AuditSource.detailsKey: source.wireValue,
        'actorId': actorId,
        'actorName': actorName,
        if (approvedBy != null && approvedBy.isNotEmpty) ...{
          'approvedBy': approvedBy,
          'approvedById': approvedBy,
          'approvedByName': approvedBy,
        },
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'businessDate': BusinessDayRepository.getCurrentDate()
            .toIso8601String()
            .split('T')[0],
        'grossAmount': order.grossAmount,
        if (_linkedBookingId(order) != null)
          'reservationId': _linkedBookingId(order),
      },
    );

    return event;
  }

  /// The record the sales box holds for a cancelled Order, if one exists.
  static Object? findCancelledSaleKey(int orderId) {
    final box = DatabaseCore.salesBox;
    if (box == null) return null;
    final matches = <Object>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['orderId'] != orderId) continue;
      if (raw['isCancelled'] != true) continue;
      final finalTransaction = raw['finalTransaction'];
      final type = finalTransaction is Map ? finalTransaction['type'] : null;
      if (type == cancelledTransactionType ||
          raw['paymentMethod'] == cancelledPaymentMethod) {
        matches.add(key as Object);
      }
    }
    if (matches.length > 1)
      throw OrderMutationConflict(
        'repair_required',
        'Multiple cancellation Sales need explicit repair',
      );
    return matches.isEmpty ? null : matches.single;
  }
}
