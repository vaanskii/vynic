import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'dart:developer' as developer;

import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import '../database_core.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/table_repository.dart';

/// Closes the business day.
///
/// Multi-step flow (all-or-nothing from the operator's point of view):
/// guards (no active orders or live table locks) →
/// finalize reservations → remember the operated date → advance the business
/// date → reset the daily sales total → purge closed orders → free tables.
class CloseDayTransaction {
  CloseDayTransaction._();

  /// Moves every genuine booking dated on or before [currentDateString] to
  /// its terminal state: `completed` when it was seated, `no-show` otherwise.
  ///
  /// Each transition is written to the Reservation timeline as the system's
  /// own action — nobody pressed a button on a specific booking, Close Day
  /// did — so the actor is `system` and the source `SYSTEM`. Bookings already
  /// final only lose a dangling Order link and write nothing.
  static Future<({int completed, int noShow})> finalizeReservationsForDay(
    String currentDateString,
  ) => UpdateReadiness.track(
    'finalizeReservationsForDay',
    () => _updateTrackedFinalizeReservationsForDay(currentDateString),
  );

  static Future<({int completed, int noShow})>
  _updateTrackedFinalizeReservationsForDay(String currentDateString) async {
    var completedReservations = 0;
    var noShowReservations = 0;
    for (final reservation in DatabaseCore.reservationBox!.values) {
      if (!ReservationClassification.isRealAdvanceBooking(reservation)) {
        continue;
      }
      final resDateString = reservation.reservationDate.toIso8601String().split(
        'T',
      )[0];
      if (resDateString.compareTo(currentDateString) > 0) {
        continue; // future booking — leave untouched
      }
      if (reservation.statusEnum.isFinal) {
        if (reservation.linkedOrderId != null) {
          // Its order is deleted below — do not keep a dangling id.
          reservation.linkedOrderId = null;
          await reservation.save();
        }
        continue;
      }
      final wasActivated =
          reservation.linkedOrderId != null ||
          reservation.statusEnum == ReservationStatus.inProgress;
      final previousStatus = reservation.status;
      final linkedOrderId = reservation.linkedOrderId;
      reservation.statusEnum = wasActivated
          ? ReservationStatus.completed
          : ReservationStatus.noShow;
      reservation.linkedOrderId = null;
      await reservation.save();
      await ReservationAudit.log(
        action: wasActivated
            ? ReservationAuditAction.complete
            : ReservationAuditAction.noShow,
        reservation: reservation,
        actorId: 'system',
        source: AuditSource.system,
        previousStatus: previousStatus,
        newStatus: reservation.status,
        reason: 'Close Day',
        extra: {if (linkedOrderId != null) 'orderId': linkedOrderId},
      );
      if (wasActivated) {
        completedReservations++;
      } else {
        noShowReservations++;
      }
    }
    return (completed: completedReservations, noShow: noShowReservations);
  }

  /// [actorId] is the operator who pressed Close Day. The transaction itself
  /// is an automatic process — it finalizes bookings nobody touched — so the
  /// reservation transitions inside it stay `system`/`SYSTEM`, while the day
  /// closing is attributed to the person who asked for it.
  static Future<bool> run({
    String actorId = 'unknown',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.track(
    'closeDay',
    () => _updateTrackedRun(
      actorId: actorId,
      actorName: actorName,
      source: source,
    ),
  );

  static Future<bool> _updateTrackedRun({
    String actorId = 'unknown',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    try {
      developer.log('========================================');
      developer.log('CLOSE DAY - Starting checks');
      final currentDate = BusinessDayRepository.getCurrentDate();
      final currentDateString = currentDate.toIso8601String().split('T')[0];
      developer.log(
        'Current business date: ${BusinessDayRepository.getGeorgianFormattedDate(currentDate)}',
      );
      developer.log('========================================');

      // Check if any tables have active (non-closed) orders
      final activeOrders = DatabaseCore.orderBox!.values.where((order) {
        if (order.status == 'closed' || order.status == 'cancelled') {
          return false;
        }
        final orderDateString = order.createdAt.toIso8601String().split('T')[0];
        return orderDateString == currentDateString;
      }).toList();

      developer.log('Total active orders: ${activeOrders.length}');

      if (activeOrders.isNotEmpty) {
        developer.log('❌ CANNOT CLOSE DAY - Active orders found:');
        for (var order in activeOrders) {
          developer.log('  - Order #${order.orderId}:');
          developer.log('    Tables: ${order.tableNumbers.join(", ")}');
          developer.log('    Floor: ${order.floor}');
          developer.log('    Status: ${order.status}');
          developer.log('    Created by: ${order.createdBy}');
          developer.log('    Created at: ${order.createdAt}');
        }

        // Also check which tables are still reserved
        developer.log('\nReserved tables in database:');
        for (final table in DatabaseCore.tableBox!.values) {
          if (table.isReserved) {
            developer.log('  - Table ${table.tableNumber} (${table.floor}):');
            developer.log('    Reserved by: ${table.reservedBy}');
            developer.log('    Order ID: ${table.activeOrderId}');
            developer.log('    Reserved at: ${table.reservedAt}');
          }
        }

        // Check reservations
        developer.log('\nAll reservations in database:');
        for (var reservation in DatabaseCore.reservationBox!.values) {
          final resDate = reservation.reservationDate.toIso8601String().split(
            'T',
          )[0];
          developer.log(
            '  - ${reservation.customerName} (${reservation.status}):',
          );
          developer.log(
            '    Date: $resDate (${BusinessDayRepository.getGeorgianFormattedDate(reservation.reservationDate)})',
          );
          developer.log(
            '    Tables: ${ReservationTableAvailability.tableRefsOf(reservation).map((ref) => ref.encode()).join(", ")}',
          );
          developer.log('    Time: ${reservation.reservationTime}');
          developer.log('    Notes: ${reservation.notes ?? "none"}');
        }

        await GlobalAudit.closeDayBlocked(
          businessDate: currentDateString,
          blockedBy: 'ACTIVE_ORDERS',
          blockers: [
            for (final order in activeOrders)
              <String, dynamic>{
                'orderId': order.orderId,
                'tableNumbers': order.tableNumbers,
                'floor': order.floor,
                'status': order.status,
                'createdBy': order.createdBy,
              },
          ],
          actorId: actorId,
          actorName: actorName,
          source: source,
        );
        return false;
      }

      final cleanupResults = await TableRepository.releaseStaleReservedTables();
      if (cleanupResults.isNotEmpty) {
        developer.log(
          '🧹 Cleaned ${cleanupResults.length} stale reserved tables before final check:',
        );
        for (final entry in cleanupResults) {
          final reason = entry['reason'] as String? ?? 'unknown reason';
          developer.log(
            '  - Table ${entry['tableNumber']} (${entry['floor']}) • $reason',
          );
        }
      }

      final reservedTables = DatabaseCore.tableBox!.values
          .where((table) => table.isReserved)
          .toList();
      if (reservedTables.isNotEmpty) {
        developer.log('❌ CANNOT CLOSE DAY - Reserved tables still active:');
        for (final table in reservedTables) {
          developer.log('  - Table ${table.tableNumber} (${table.floor})');
          if (table.reservedBy != null) {
            developer.log('    Reserved by: ${table.reservedBy}');
          }
          if (table.activeOrderId != null) {
            developer.log('    Active order: #${table.activeOrderId}');
          }
          if (table.reservationId != null) {
            developer.log('    Reservation ID: ${table.reservationId}');
          }
        }
        await GlobalAudit.closeDayBlocked(
          businessDate: currentDateString,
          blockedBy: 'RESERVED_TABLES',
          blockers: [
            for (final table in reservedTables)
              <String, dynamic>{
                'tableNumber': table.tableNumber,
                'floor': table.floor,
                if (table.reservedBy != null) 'reservedBy': table.reservedBy,
                if (table.activeOrderId != null)
                  'activeOrderId': table.activeOrderId,
                if (table.reservationId != null)
                  'reservationId': table.reservationId,
              },
          ],
          actorId: actorId,
          actorName: actorName,
          source: source,
        );
        return false;
      }

      developer.log('✅ No active orders found - proceeding with day closure');

      // Finalize genuine reservations for the closed day (and any earlier
      // stragglers) so nothing stays 'in-progress' with a linkedOrderId
      // pointing at an order deleted below. Historical bookkeeping rows are
      // local history, not bookings, and remain untouched.
      // See docs/VYNIC_PROJECT_PLAN.md §2 (root cause 3).
      final finalized = await finalizeReservationsForDay(currentDateString);
      developer.log(
        'Finalized reservations: ${finalized.completed} completed, '
        '${finalized.noShow} no-show',
      );

      // Persist the day being closed so empty days (without sales) are still
      // part of operated business history.
      await BusinessDayRepository.rememberOperatedBusinessDate(currentDate);

      final nextDate = currentDate.add(const Duration(days: 1));
      developer.log(
        'Moving from ${BusinessDayRepository.getGeorgianFormattedDate(currentDate)} to ${BusinessDayRepository.getGeorgianFormattedDate(nextDate)}',
      );

      await DatabaseCore.settingsBox!.put(
        'currentDate',
        nextDate.toIso8601String(),
      );

      // Reset daily sales total for new day
      await SalesRepository.resetDailySalesTotal();

      // Clear all closed orders from active orders. Their Sale is the durable
      // record; the Order row is operational state for the day that just ended.
      var archivedOrders = 0;
      final orderKeys = DatabaseCore.orderBox!.keys.toList();
      for (final key in orderKeys) {
        final order = DatabaseCore.orderBox!.get(key);
        if (order?.status == 'closed') {
          await DatabaseCore.orderBox!.delete(key);
          archivedOrders++;
        }
      }

      // Free all reserved tables for new day
      int freedTables = 0;
      for (final table in DatabaseCore.tableBox!.values) {
        if (table.isReserved || table.reservationId != null) {
          table.isReserved = false;
          table.activeOrderId = null;
          table.reservedAt = null;
          table.reservedBy = null;
          table.reservationId = null;
          await table.save();
          freedTables++;
        }
      }

      developer.log('Freed $freedTables tables');

      await GlobalAudit.closeDayCompleted(
        businessDateClosed: currentDateString,
        nextBusinessDate: nextDate.toIso8601String().split('T')[0],
        reservationsCompleted: finalized.completed,
        reservationsNoShow: finalized.noShow,
        ordersArchived: archivedOrders,
        tablesFreed: freedTables,
        actorId: actorId,
        actorName: actorName,
        source: source,
      );

      developer.log('✅ Day closed successfully');
      developer.log('========================================');

      return true;
    } catch (e) {
      if (UpdateReadiness.enabled) UpdateReadiness.failure = e.toString();
      developer.log('❌ Error closing day: $e');
      return false;
    }
  }
}
