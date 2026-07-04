import 'dart:developer' as developer;

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import '../database_core.dart';
import '../repositories/error_log_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/reservation_repository.dart';
import '../repositories/table_repository.dart';
import 'package:vynic/core/services/sync/sync_events.dart';

import '../repositories/business_day_repository.dart';

/// Activates reservations: creates (or re-links) the real order and reserves
/// the tables — manually when guests are seated ([activate]) or in bulk at
/// day-open ([activateTodaysReservations]).
///
/// Known business failures come back as
/// [ReservationActivationResult.failure]; unexpected errors propagate.
class ActivateReservationTransaction {
  ActivateReservationTransaction._();

  /// Activates a reservation by creating (or re-linking) its order and
  /// reserving its tables.
  ///
  /// Known business failures are returned as
  /// [ReservationActivationResult.failure] with the real reason. Unexpected
  /// errors (e.g. `StateError('Table X is busy')` from [createOrder]) are NOT
  /// caught here — they propagate so callers can log and surface them.
  static Future<ReservationActivationResult> activate({
    required String reservationId,
    required String activatedBy,
  }) async {
    final reservations = DatabaseCore.reservationBox!.values.where(
      (r) => r.id == reservationId,
    );
    if (reservations.isEmpty) {
      return ReservationActivationResult.failure(
        'Reservation $reservationId not found',
      );
    }
    final reservation = reservations.first;

    if (reservation.isTakeAway) {
      final linkedOrderId = reservation.linkedOrderId;
      if (linkedOrderId != null) {
        return ReservationActivationResult.success(linkedOrderId);
      }
      return ReservationActivationResult.failure(
        'Take-away reservation $reservationId has no linked order',
      );
    }

    final decodedTables = ReservationTableAvailability.tableRefsOf(reservation);
    if (decodedTables.isEmpty) {
      return ReservationActivationResult.failure(
        'Reservation $reservationId has no tables assigned',
      );
    }

    final floors = decodedTables.map((table) => table.floor).toSet();

    if (floors.length > 1) {
      return ReservationActivationResult.failure(
        'Reservation $reservationId mixes tables from both floors, '
        'which is not supported',
      );
    }

    final floor = floors.first;

    Future<void> ensureTablesReserved(int orderId) async {
      for (final table in decodedTables) {
        await TableRepository.reserveTable(
          tableNumber: table.tableNumber,
          floor: table.floor,
          username: activatedBy,
          orderId: orderId,
          reservationId: reservation.id,
        );
      }
    }

    final existingOrderId = reservation.linkedOrderId;
    if (existingOrderId != null) {
      final existingOrder = OrderRepository.getOrder(existingOrderId);
      if (existingOrder != null) {
        await ensureTablesReserved(existingOrderId);
        if (existingOrder.status.toLowerCase() != 'confirmed') {
          existingOrder.status = 'confirmed';
          await existingOrder.save();
        }
        reservation.status = 'in-progress';
        await reservation.save();
        return ReservationActivationResult.success(existingOrderId);
      }
      reservation.linkedOrderId = null;
    }

    final order = await OrderRepository.createOrder(
      tableNumbers: decodedTables.map((table) => table.tableNumber).toList(),
      floor: floor,
      createdBy: activatedBy,
      items: reservation.preOrderItems ?? const <OrderItem>[],
      createReservationRecord: false,
    );

    // Set openedByUserId to track who activated this reservation
    order.openedByUserId = activatedBy;

    // Restore reservation link on tables (createOrder clears reservationId)
    await ensureTablesReserved(order.orderId);

    order.status = 'confirmed';
    await order.save();

    // linkedOrderId is the activation marker; notes stay user-owned.
    reservation.status = 'in-progress';
    reservation.linkedOrderId = order.orderId;
    await reservation.save();

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'activated',
        payload: {'reservationId': reservationId, 'orderId': order.orderId},
      ),
    );

    return ReservationActivationResult.success(order.orderId);
  }

  // Activate today's confirmed reservations (called when app starts or day opens)
  static Future<void> activateTodaysReservations() async {
    developer.log('========================================');
    developer.log('ACTIVATE TODAY\'S RESERVATIONS - CALLED');

    final currentDate = BusinessDayRepository.getCurrentDate();
    final currentDateString = currentDate.toIso8601String().split('T')[0];

    developer.log(
      'Current business date: ${BusinessDayRepository.getGeorgianFormattedDate(currentDate)} ($currentDateString)',
    );
    developer.log('\nALL RESERVATIONS IN DATABASE:');

    for (var r in DatabaseCore.reservationBox!.values) {
      final resDateString = r.reservationDate.toIso8601String().split('T')[0];
      developer.log('  - ${r.customerName}:');
      developer.log(
        '    Date: $resDateString (${BusinessDayRepository.getGeorgianFormattedDate(r.reservationDate)})',
      );
      developer.log('    Status: ${r.status}');
      developer.log(
        '    Tables: ${ReservationTableAvailability.tableRefsOf(r).map((ref) => ref.encode()).join(", ")}',
      );
      developer.log('    Notes: ${r.notes ?? "null"}');
    }

    developer.log('\nFILTERING FOR TODAY\'S CONFIRMED RESERVATIONS:');

    // Get all confirmed reservations for today that haven't been activated yet
    final todaysReservations = DatabaseCore.reservationBox!.values.where((r) {
      if (r.isTakeAway) {
        return false;
      }
      final resDateString = r.reservationDate.toIso8601String().split('T')[0];
      final isToday = resDateString == currentDateString;
      final isConfirmed = r.status == 'confirmed';
      // Activation is tracked by linkedOrderId — NOT by the user-editable
      // notes field (editing notes used to allow double activation).
      final notActivated = r.linkedOrderId == null;

      developer.log(
        '  ${r.customerName}: IsToday=$isToday, IsConfirmed=$isConfirmed, NotActivated=$notActivated',
      );

      return isToday && isConfirmed && notActivated;
    }).toList();

    developer.log(
      '\n✅ Found ${todaysReservations.length} reservations to activate',
    );

    // Show current reserved tables BEFORE activation
    developer.log('\nCURRENT RESERVED TABLES (before activation):');
    final reservedTablesBefore = DatabaseCore.tableBox!.values
        .where((t) => t.isReserved)
        .toList();
    if (reservedTablesBefore.isEmpty) {
      developer.log('  None');
    } else {
      for (var table in reservedTablesBefore) {
        developer.log(
          '  - Table ${table.tableNumber} (${table.floor}): Reserved by ${table.reservedBy}',
        );
      }
    }

    if (todaysReservations.isEmpty) {
      developer.log(
        '\n❌ No reservations to activate - exiting without changes',
      );
      developer.log('========================================');
      return;
    }

    // Reserve tables for each confirmed reservation. Each reservation is
    // isolated in its own try/catch so one bad record (e.g. empty tables)
    // cannot abort activation of the remaining ones.
    for (var reservation in todaysReservations) {
      try {
        developer.log(
          '\n🔄 Activating reservation for ${reservation.customerName}:',
        );
        final tableRefs = ReservationTableAvailability.tableRefsOf(reservation);
        developer.log(
          '  Tables: ${tableRefs.map((ref) => ref.encode()).join(", ")}',
        );
        developer.log('  Time: ${reservation.reservationTime}');

        if (tableRefs.isEmpty) {
          throw StateError(
            'Reservation ${reservation.id} has no tables assigned',
          );
        }
        final floors = tableRefs.map((ref) => ref.floor).toSet();
        if (floors.length > 1) {
          throw StateError(
            'Reservation ${reservation.id} mixes tables from multiple floors',
          );
        }
        final floor = floors.first;

        developer.log(
          '  Reserving tables: '
          '${ReservationTableAvailability.formatTableRefs(tableRefs)} '
          'on $floor floor',
        );
        developer.log(
          '  Pre-order items: ${reservation.preOrderItems?.length ?? 0}',
        );

        // Create order with pre-order items (or empty if no pre-order)
        final order = await OrderRepository.createOrder(
          tableNumbers: tableRefs.map((ref) => ref.tableNumber).toList(),
          floor: floor,
          createdBy: 'System (Reservation)',
          items:
              reservation.preOrderItems ??
              [], // Use pre-order items or empty list
          createReservationRecord: false,
        );

        // If there are pre-order items, mark order as confirmed (already sent to kitchen)
        if (reservation.preOrderItems != null &&
            reservation.preOrderItems!.isNotEmpty) {
          order.status = 'confirmed';
          await order.save();
          developer.log(
            '  ✅ Order #${order.orderId} status set to "confirmed" (pre-ordered items)',
          );
        }

        developer.log(
          '  ✅ Order #${order.orderId} created with ${reservation.preOrderItems?.length ?? 0} items',
        );

        // Update reservation status to 'in-progress' and link to order.
        // linkedOrderId is the activation marker; notes stay user-owned.
        reservation.status = 'in-progress';
        reservation.linkedOrderId = order.orderId;
        await reservation.save();

        developer.log(
          '  ✅ Activated successfully - Reservation ID: ${reservation.key}, Order ID: ${order.orderId}',
        );
      } catch (error, stackTrace) {
        // Logged (not swallowed): the failed reservation stays 'confirmed'
        // and unlinked so staff can activate it manually; the loop moves on.
        await ErrorLogRepository.logError(
          title: 'Reservation auto-activation failed',
          error: error,
          stackTrace: stackTrace,
          context: 'activate_todays_reservations',
          metadata: {
            'reservationId': reservation.id,
            'customerName': reservation.customerName,
            'tables': ReservationTableAvailability.tableRefsOf(
              reservation,
            ).map((ref) => ref.encode()).toList(),
          },
        );
      }
    }

    // Show reserved tables AFTER activation
    developer.log('\nCURRENT RESERVED TABLES (after activation):');
    final reservedTablesAfter = DatabaseCore.tableBox!.values
        .where((t) => t.isReserved)
        .toList();
    if (reservedTablesAfter.isEmpty) {
      developer.log('  None');
    } else {
      for (var table in reservedTablesAfter) {
        developer.log(
          '  - Table ${table.tableNumber} (${table.floor}): Reserved=${table.isReserved}, ReservationId=${table.reservationId}, OrderId=${table.activeOrderId}',
        );
      }
    }

    developer.log('\n✅ All today\'s reservations activated');
    developer.log('========================================');
  }
}
