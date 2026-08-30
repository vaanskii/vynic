import 'dart:developer' as developer;

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation_status.dart';

import '../database_core.dart';
import '../repositories/audit_repository.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/table_repository.dart';

/// Closes a table's order (fiscal payment or non-fiscal).
///
/// Multi-step flow: mark the order closed → free its tables → complete the
/// linked reservation → append the locking audit event.
class CloseTableTransaction {
  CloseTableTransaction._();

  // Close order with payment method
  static Future<bool> withPayment({
    required int orderId,
    required String paymentMethod,
    required String closedById,
    String? closedByName,
    Map<String, double>? paymentBreakdown,
    String? customPaymentLabel,
  }) async {
    try {
      final order = DatabaseCore.orderBox!.values.firstWhere(
        (o) => o.orderId == orderId,
      );
      order.statusEnum = OrderStatus.closed;
      order.paymentMethod = paymentMethod;
      final closureTimestamp = BusinessDayRepository.getCurrentDateTime();
      order.closedAt = closureTimestamp;
      order.updatedAt = closureTimestamp;
      await order.save();

      // Free all tables associated with this order
      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
        );
      }

      // Mark associated reservation as completed
      final currentDate = BusinessDayRepository.getCurrentDate();
      final dateString = currentDate.toIso8601String().split('T')[0];

      // Find the reservation for this order: linkedOrderId is the marker;
      // the notes match only covers legacy records written before it existed.
      for (var reservation in DatabaseCore.reservationBox!.values) {
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        final matchesLinked = reservation.linkedOrderId == orderId;
        final matchesLegacyNote =
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId');
        if (resDateString == dateString &&
            (matchesLinked || matchesLegacyNote)) {
          reservation.statusEnum = ReservationStatus.completed;
          await reservation.save();
          break;
        }
      }

      final closingEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: closedById,
        waiterName: closedByName ?? closedById,
        timestamp: order.closedAt!,
        note: customPaymentLabel != null && customPaymentLabel.isNotEmpty
            ? 'Order closed with $customPaymentLabel'
            : 'Order closed with $paymentMethod',
      );

      try {
        await AuditRepository.appendOrderAuditEvents(
          orderId: orderId,
          events: [closingEvent],
          statusOverride: AuditReportStatus.closed,
          lockReport: true,
          closedById: closedById,
          closedByName: closedByName ?? closedById,
        );
      } catch (e) {
        developer.log('Audit report append failed for order $orderId: $e');
      }

      return true;
    } catch (e) {
      developer.log('Error closing order with payment: $e');
      return false;
    }
  }

  static Future<bool> nonFiscal({
    required int orderId,
    required String closedById,
    String? closedByName,
  }) async {
    try {
      final order = DatabaseCore.orderBox!.values.firstWhere(
        (o) => o.orderId == orderId,
      );
      order.statusEnum = OrderStatus.closed;
      order.paymentMethod = 'non-fiscal';
      final closureTimestamp = BusinessDayRepository.getCurrentDateTime();
      order.closedAt = closureTimestamp;
      order.updatedAt = closureTimestamp;
      await order.save();

      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
        );
      }

      final currentDate = BusinessDayRepository.getCurrentDate();
      final dateString = currentDate.toIso8601String().split('T')[0];

      for (var reservation in DatabaseCore.reservationBox!.values) {
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (resDateString == dateString &&
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId')) {
          reservation.statusEnum = ReservationStatus.completed;
          await reservation.save();
          break;
        }
      }

      final closingEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: closedById,
        waiterName: closedByName ?? closedById,
        timestamp: order.closedAt!,
        note: 'Order closed (non-fiscal)',
      );

      try {
        await AuditRepository.appendOrderAuditEvents(
          orderId: orderId,
          events: [closingEvent],
          statusOverride: AuditReportStatus.closed,
          lockReport: true,
          closedById: closedById,
          closedByName: closedByName ?? closedById,
        );
      } catch (e) {
        developer.log(
          'Audit report append failed for non-fiscal closure $orderId: $e',
        );
      }

      return true;
    } catch (e) {
      developer.log('Error closing order non-fiscally: $e');
      return false;
    }
  }
}
