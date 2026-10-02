import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'dart:developer' as developer;

import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import '../database_core.dart';
import '../repositories/order_repository.dart';
import '../repositories/reservation_repository.dart';
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
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.mutate(
    'activate',
    () => _updateTrackedActivate(
      reservationId: reservationId,
      activatedBy: activatedBy,
      source: source,
    ),
  );

  static Future<ReservationActivationResult> _updateTrackedActivate({
    required String reservationId,
    required String activatedBy,
    AuditSource source = AuditSource.pos,
  }) async {
    final reservations = DatabaseCore.reservationBox!.values.where(
      (r) => r.id == reservationId,
    );
    if (reservations.isEmpty) {
      return ReservationActivationResult.failure(
        'Reservation $reservationId not found',
      );
    }
    if (reservations.length != 1)
      throw OrderMutationConflict(
        'repair_required',
        'Reservation identity is ambiguous',
      );
    final reservation = reservations.single;

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

    final existingOrderId = reservation.linkedOrderId;
    if (existingOrderId != null) {
      final existing = OrderRepository.getOrder(existingOrderId);
      if (existing == null ||
          existing.statusEnum.isTerminal ||
          existing.floor != floor ||
          !decodedTables.every(
            (t) => existing.tableNumbers.contains(t.tableNumber),
          ))
        throw OrderMutationConflict(
          'repair_required',
          'Existing activation link requires explicit repair',
        );
      OrderTableMutationRepository.requireFresh(existing);
      return ReservationActivationResult.success(existingOrderId);
    }
    if (!ReservationClassification.isRealAdvanceBooking(reservation) ||
        ![
          ReservationStatus.pending,
          ReservationStatus.preparing,
          ReservationStatus.confirmed,
        ].contains(reservation.statusEnum))
      return ReservationActivationResult.failure(
        'Reservation is not eligible for seating',
      );

    // The report opens with ACTIVATE_RESERVATION, not CREATE_WALKIN: this
    // Order exists because a booking was seated, and the trail says which.
    final order = await OrderRepository.createOrder(
      tableNumbers: decodedTables.map((table) => table.tableNumber).toList(),
      floor: floor,
      createdBy: activatedBy,
      items: reservation.preOrderItems ?? const <OrderItem>[],
      source: source,
      activatesReservationId: reservation.id,
      reservationCustomerName: reservation.customerName,
      requestId: 'activation:${reservation.id}',
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'activated',
        payload: {'reservationId': reservationId, 'orderId': order.orderId},
      ),
    );

    return ReservationActivationResult.success(order.orderId);
  }

  static Future<void> activateTodaysReservations() =>
      UpdateReadiness.mutate('activateTodaysReservations', () async {
        final today = BusinessDayRepository.dateKey(
          BusinessDayRepository.getCurrentDate(),
        );
        final ids = DatabaseCore.reservationBox!.values
            .where(
              (r) =>
                  ReservationClassification.isRealAdvanceBooking(r) &&
                  BusinessDayRepository.dateKey(r.reservationDate) == today &&
                  r.statusEnum == ReservationStatus.confirmed &&
                  r.linkedOrderId == null,
            )
            .map((r) => r.id)
            .toList();
        for (final id in ids) {
          try {
            await activate(
              reservationId: id,
              activatedBy: 'System (Reservation)',
              source: AuditSource.system,
            );
          } catch (error, stack) {
            developer.log(
              'Reservation activation failed for $id',
              error: error,
              stackTrace: stack,
              name: 'activate_reservation',
            );
            if (OrderTableMutationRepository.records().any((r) => r.pending))
              rethrow;
          }
        }
      });
}
