import 'dart:developer' as developer;

import 'package:vynic/core/utils/reservation_table_availability.dart';

import '../database_core.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/table_repository.dart';

/// Closes the business day.
///
/// Multi-step flow (all-or-nothing from the operator's point of view):
/// guards (no active orders, no pending takeaways, no live table locks) →
/// finalize reservations → remember the operated date → advance the business
/// date → reset the daily sales total → purge closed orders → free tables.
class CloseDayTransaction {
  CloseDayTransaction._();

  static Future<bool> run() async {
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

        return false;
      }

      final pendingTakeAwayReservations = DatabaseCore.reservationBox!.values
          .where((reservation) {
            if (!reservation.isTakeAway) {
              return false;
            }
            final reservationDateString = reservation.reservationDate
                .toIso8601String()
                .split('T')[0];
            if (reservationDateString != currentDateString) {
              return false;
            }
            final status = reservation.status.toLowerCase();
            return status != 'completed' && status != 'cancelled';
          })
          .toList();

      if (pendingTakeAwayReservations.isNotEmpty) {
        developer.log(
          '❌ CANNOT CLOSE DAY - Pending takeaway reservations found:',
        );
        for (final reservation in pendingTakeAwayReservations) {
          developer.log(
            '  - ${reservation.customerName} (${reservation.status})',
          );
          developer.log('    Time: ${reservation.reservationTime}');
          developer.log('    Created by: ${reservation.createdBy}');
        }
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
        return false;
      }

      developer.log('✅ No active orders found - proceeding with day closure');

      // Finalize dine-in reservations for the closed day (and any earlier
      // stragglers) so nothing stays 'in-progress' with a linkedOrderId
      // pointing at an order deleted below. Activated bookings become
      // 'completed'; never-activated past bookings become 'no-show'.
      // See docs/VYNIC_PROJECT_PLAN.md §2 (root cause 3).
      var completedReservations = 0;
      var noShowReservations = 0;
      for (final reservation in DatabaseCore.reservationBox!.values) {
        if (reservation.isTakeAway) {
          continue; // today's pending takeaways already blocked closing above
        }
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (resDateString.compareTo(currentDateString) > 0) {
          continue; // future booking — leave untouched
        }
        final status = reservation.status.toLowerCase();
        final isFinal =
            status == 'completed' ||
            status == 'cancelled' ||
            status == 'canceled' ||
            status == 'no-show';
        if (isFinal) {
          if (reservation.linkedOrderId != null) {
            // Its order is deleted below — do not keep a dangling id.
            reservation.linkedOrderId = null;
            await reservation.save();
          }
          continue;
        }
        final wasActivated =
            reservation.linkedOrderId != null || status == 'in-progress';
        reservation.status = wasActivated ? 'completed' : 'no-show';
        reservation.linkedOrderId = null;
        await reservation.save();
        if (wasActivated) {
          completedReservations++;
        } else {
          noShowReservations++;
        }
      }
      developer.log(
        'Finalized reservations: $completedReservations completed, '
        '$noShowReservations no-show',
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

      // Clear all closed orders from active orders
      final orderKeys = DatabaseCore.orderBox!.keys.toList();
      for (final key in orderKeys) {
        final order = DatabaseCore.orderBox!.get(key);
        if (order?.status == 'closed') {
          await DatabaseCore.orderBox!.delete(key);
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

      developer.log('✅ Day closed successfully');
      developer.log('========================================');

      return true;
    } catch (e) {
      developer.log('❌ Error closing day: $e');
      return false;
    }
  }
}
