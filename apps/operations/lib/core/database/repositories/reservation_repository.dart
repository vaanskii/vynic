import 'dart:developer' as developer;

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';

/// Reservations: CRUD, table-blocking queries, activation (creating the real
/// order when guests are seated), and day-open auto-activation.
class ReservationRepository {
  ReservationRepository._();

  /// Fetch a reservation by its business id (used by UI overlays and the
  /// table stale-lock analysis).
  static Reservation? findReservationById(String reservationId) {
    if (DatabaseCore.reservationBox == null) {
      return null;
    }
    try {
      return DatabaseCore.reservationBox!.values.firstWhere(
        (reservation) => reservation.id == reservationId,
      );
    } catch (_) {
      return null;
    }
  }

  // Create a new reservation
  static Future<String> createReservation({
    required String customerName,
    required String customerPhone,
    List<int> tableNumbers = const [],
    List<TableRef>? tableRefs,
    required DateTime reservationDate,
    required String reservationTime,
    required int numberOfGuests,
    String? notes,
    required String createdBy,
    List<OrderItem>? preOrderItems,
    bool isTakeAway = false,
    int? linkedOrderId,
    String status = 'pending',
    String? id,
  }) async {
    // Cloud supplies the id for a reservation it originated, because a POS that
    // invents one turns an at-least-once redelivery into a second booking. A
    // reservation taken on this terminal still gets a local one.
    final reservationId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : DateTime.now().millisecondsSinceEpoch.toString();

    // Refs are canonical; the legacy int codes are kept in sync for backups
    // and the server wire format (unrepresentable tables are omitted there).
    final refs =
        tableRefs ??
        tableNumbers
            .map(ReservationTableAvailability.refFromLegacyCode)
            .toList();
    final legacyCodes = tableRefs != null
        ? ReservationTableAvailability.legacyCodesOf(tableRefs)
        : tableNumbers;

    // All new reservations start as pending (will be confirmed manually when date arrives)
    final reservation = Reservation(
      id: reservationId,
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: legacyCodes,
      tableRefs: [for (final ref in refs) ref.encode()],
      reservationDate: reservationDate,
      reservationTime: reservationTime,
      numberOfGuests: numberOfGuests,
      notes: notes,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: createdBy,
      status: status,
      preOrderItems: preOrderItems,
      isTakeAway: isTakeAway,
      linkedOrderId: linkedOrderId,
    );

    await DatabaseCore.reservationBox!.add(reservation);
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'created',
        payload: {'reservationId': reservationId},
      ),
    );
    return reservationId;
  }

  // Get all reservations
  static List<Reservation> getAllReservations() {
    return DatabaseCore.reservationBox!.values.toList();
  }

  // Get a reservation by its key (ID)
  static Reservation? getReservation(String reservationId) {
    try {
      final key = int.parse(reservationId);
      return DatabaseCore.reservationBox!.get(key);
    } catch (e) {
      return null;
    }
  }

  // Get reservations for a specific date
  static List<Reservation> getReservationsForDate(DateTime date) {
    return DatabaseCore.reservationBox!.values
        .where(
          (r) => ReservationTableAvailability.isSameCalendarDate(
            r.reservationDate,
            date,
          ),
        )
        .toList();
  }

  /// Real bookings on [date] that already hold table numbers (excludes walk-ins).
  static List<Reservation> getTableBlockingReservationsForDate(DateTime date) {
    return getReservationsForDate(date).where((reservation) {
      if (!ReservationTableAvailability.isRealTableBooking(reservation)) {
        return false;
      }
      if (!ReservationTableAvailability.isReservationBlocking(
        reservation.status,
      )) {
        return false;
      }
      return ReservationTableAvailability.tableRefsOf(reservation).isNotEmpty;
    }).toList();
  }

  /// Marks the booking linked to [orderId] as finished.
  ///
  /// The sibling of [cancelReservationByOrderId], for the case where the party
  /// was served and the order is being closed for a reason that is not a
  /// cancellation — items moved to another table, for instance. Leaving the
  /// booking `confirmed` against a closed order is what blocks the day close.
  static Future<bool> completeReservationByOrderId(int orderId) async {
    try {
      for (final reservation in DatabaseCore.reservationBox!.values) {
        final matchesLinked = reservation.linkedOrderId == orderId;
        final matchesNote =
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId');
        if (matchesLinked || matchesNote) {
          reservation.statusEnum = ReservationStatus.completed;
          await reservation.save();
          return true;
        }
      }
      return false;
    } catch (error, stackTrace) {
      developer.log(
        'Error completing reservation by order id',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static Future<bool> cancelReservationByOrderId(int orderId) async {
    try {
      for (final reservation in DatabaseCore.reservationBox!.values) {
        final matchesLinked = reservation.linkedOrderId == orderId;
        final matchesNote =
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId');
        if (matchesLinked || matchesNote) {
          reservation.statusEnum = ReservationStatus.cancelled;
          await reservation.save();
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error cancelling reservation by order id: $e');
      return false;
    }
  }

  static Reservation? findReservationForOrder(Order order) {
    try {
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      bool matchesOrderDate(Reservation reservation) {
        final reservationDateKey = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        return reservationDateKey == orderDateKey;
      }

      if (DatabaseCore.tableBox != null) {
        for (final table in DatabaseCore.tableBox!.values) {
          if (table.activeOrderId == order.orderId &&
              table.reservationId != null) {
            final linked = findReservationById(table.reservationId!);
            if (linked != null && matchesOrderDate(linked)) {
              return linked;
            }
          }
        }
      }

      final isTakeAway = _isOrderTakeAway(order);

      for (final reservation in DatabaseCore.reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          final name = reservation.customerName.trim().toLowerCase();
          if (name.isNotEmpty && name != 'walk-in') {
            return reservation;
          }
        }
      }

      for (final reservation in DatabaseCore.reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      for (final reservation in DatabaseCore.reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      final targetNote = 'Order #${order.orderId}';
      for (final reservation in DatabaseCore.reservationBox!.values) {
        final note = reservation.notes;
        if (note != null &&
            note.contains(targetNote) &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      for (final reservation in DatabaseCore.reservationBox!.values) {
        final note = reservation.notes;
        if (note != null &&
            note.contains(targetNote) &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }
    } catch (e) {
      developer.log('Error finding reservation for order ${order.orderId}: $e');
    }
    return null;
  }

  static bool _isOrderTakeAway(Order order) {
    final floorLabel = order.floor.toLowerCase();
    if (floorLabel == 'takeaway' ||
        floorLabel == 'take-away' ||
        floorLabel.contains('take away')) {
      return true;
    }

    for (final table in order.tableNumbers) {
      final normalized = table.toLowerCase();
      if (normalized.startsWith('ta-') || normalized.contains('take away')) {
        return true;
      }
    }

    return false;
  }

  static List<Reservation> getTakeAwayReservationsForDate(DateTime date) {
    final dateString = date.toIso8601String().split('T')[0];
    final reservationsForDate = DatabaseCore.reservationBox!.values.where((r) {
      if (!r.isTakeAway) return false;
      final reservationDateString = r.reservationDate.toIso8601String().split(
        'T',
      )[0];
      return reservationDateString == dateString;
    }).toList();

    reservationsForDate.sort((a, b) {
      final orderIdComparison = (b.linkedOrderId ?? 0).compareTo(
        a.linkedOrderId ?? 0,
      );
      if (orderIdComparison != 0) {
        return orderIdComparison;
      }

      final createdAtComparison = b.createdAt.compareTo(a.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return b.id.compareTo(a.id);
    });

    return reservationsForDate;
  }

  // Get reservations by status
  static List<Reservation> getReservationsByStatus(String status) {
    return DatabaseCore.reservationBox!.values
        .where((r) => r.status == status)
        .toList();
  }

  /// Returns only dates that were real operated business days (have sales records)
  /// plus the current business date. Excludes reservation-only future dates.
  // Update reservation status
  static Future<void> updateReservationStatus(
    String reservationId,
    String newStatus,
  ) async {
    final reservation = DatabaseCore.reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );
    reservation.status = newStatus;
    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  static Future<void> updateReservationPreOrderItems(
    String reservationId,
    List<OrderItem> updatedItems,
  ) async {
    final reservation = DatabaseCore.reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );

    final clonedItems = updatedItems
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: item.unitPrice * item.quantity,
            comment: item.comment,
          ),
        )
        .toList();

    if (clonedItems.isEmpty) {
      reservation.preOrderItems = null;
      if (reservation.statusEnum == ReservationStatus.preparing) {
        reservation.statusEnum = ReservationStatus.pending;
      }
    } else {
      reservation.preOrderItems = clonedItems;
      if (reservation.statusEnum == ReservationStatus.pending) {
        reservation.statusEnum = ReservationStatus.preparing;
      }
    }

    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  static Future<void> updateReservationTables(
    String reservationId,
    List<int> tableNumbers, {
    List<TableRef>? tableRefs,
  }) async {
    final reservations = DatabaseCore.reservationBox!.values.where(
      (r) => r.id == reservationId,
    );
    if (reservations.isEmpty) {
      developer.log(
        'Warning: Tried to update tables for missing reservation $reservationId',
      );
      return;
    }
    final reservation = reservations.first;

    final refs =
        tableRefs ??
        tableNumbers
            .map(ReservationTableAvailability.refFromLegacyCode)
            .toList();
    reservation.tableNumbers = tableRefs != null
        ? ReservationTableAvailability.legacyCodesOf(tableRefs)
        : List<int>.from(tableNumbers);
    reservation.tableRefs = [for (final ref in refs) ref.encode()];
    if (reservation.statusEnum == ReservationStatus.pending) {
      reservation.statusEnum = ReservationStatus.confirmed;
    }
    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  // Delete reservation
  static Future<void> deleteReservation(String reservationId) async {
    try {
      final reservation = DatabaseCore.reservationBox!.values.firstWhere(
        (r) => r.id == reservationId,
      );
      await reservation.delete();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.reservations,
          action: 'deleted',
          payload: {'reservationId': reservationId},
        ),
      );
    } catch (e) {
      developer.log('Error deleting reservation: $e');
    }
  }

  // Check if tables are available for a specific date
  static bool areTablesAvailableForReservation({
    required List<int> tableNumbers,
    required DateTime reservationDate,
    required String reservationTime,
    String? excludeReservationId,
  }) {
    if (tableNumbers.isEmpty) {
      return true;
    }
    return ReservationTableAvailability.areTableCodesAvailable(
      tableCodes: tableNumbers,
      reservations: getTableBlockingReservationsForDate(reservationDate),
      excludeReservationId: excludeReservationId,
    );
  }

  static bool areTableRefsAvailableForReservation({
    required List<TableRef> tableRefs,
    required DateTime reservationDate,
    String? excludeReservationId,
  }) {
    if (tableRefs.isEmpty) {
      return true;
    }
    return ReservationTableAvailability.areTableRefsAvailable(
      tableRefs: tableRefs,
      reservations: getTableBlockingReservationsForDate(reservationDate),
      excludeReservationId: excludeReservationId,
    );
  }
}

/// Outcome of [ReservationRepository.activateReservation].
///
/// Success always carries the linked order id; failure carries the real
/// reason instead of a silent `null` (see docs/VYNIC_PROJECT_PLAN.md §2).
class ReservationActivationResult {
  final int? orderId;
  final String? failureReason;

  const ReservationActivationResult.success(int this.orderId)
    : failureReason = null;

  const ReservationActivationResult.failure(String this.failureReason)
    : orderId = null;

  bool get isSuccess => orderId != null;
}
