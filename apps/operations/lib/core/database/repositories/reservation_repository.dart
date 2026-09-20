import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';

/// Reservations: CRUD, table-blocking queries, activation (creating the real
/// order when guests are seated), and day-open auto-activation.
class ReservationRepository {
  ReservationRepository._();

  static const Uuid _uuid = Uuid();

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
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.track(
    'createReservation',
    () => _updateTrackedCreateReservation(
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: tableNumbers,
      tableRefs: tableRefs,
      reservationDate: reservationDate,
      reservationTime: reservationTime,
      numberOfGuests: numberOfGuests,
      notes: notes,
      createdBy: createdBy,
      preOrderItems: preOrderItems,
      isTakeAway: isTakeAway,
      linkedOrderId: linkedOrderId,
      status: status,
      id: id,
      source: source,
    ),
  );

  static Future<String> _updateTrackedCreateReservation({
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
    AuditSource source = AuditSource.pos,
  }) async {
    // Cloud supplies the id for a reservation it originated, because a POS that
    // invents one turns an at-least-once redelivery into a second booking. A
    // reservation taken on this terminal still gets a local one.
    //
    // A uuid, not a clock reading: two bookings taken in the same millisecond
    // used to be handed the same id, which silently made them one booking.
    // Historical numeric ids stay exactly as they are — nothing parses an id,
    // so old and new coexist.
    final reservationId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : _uuid.v4();

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
    await ReservationAudit.log(
      action: ReservationAuditAction.create,
      reservation: reservation,
      actorId: createdBy,
      source: source,
      newStatus: reservation.status,
    );
    return reservationId;
  }

  /// The genuine advance booking seated on [orderId], if any. Bookkeeping
  /// rows written by older builds are not bookings and never match.
  static Reservation? findLinkedBooking(int orderId) {
    final box = DatabaseCore.reservationBox;
    if (box == null) return null;
    for (final reservation in box.values) {
      if (reservation.linkedOrderId == orderId &&
          ReservationClassification.isRealAdvanceBooking(reservation)) {
        return reservation;
      }
    }
    return null;
  }

  // Get all reservations
  static List<Reservation> getAllReservations() {
    return DatabaseCore.reservationBox!.values.toList();
  }

  /// A reservation by its business id.
  ///
  /// The id and the Hive key are different things — rows are appended, so keys
  /// are auto-increment integers — and this resolves the id first. The numeric
  /// key lookup is kept behind it for the callers that historically passed one;
  /// a uuid id simply never matches that branch.
  static Reservation? getReservation(String reservationId) {
    final byId = findReservationById(reservationId);
    if (byId != null) return byId;
    final key = int.tryParse(reservationId);
    if (key == null) return null;
    try {
      return DatabaseCore.reservationBox!.get(key);
    } catch (_) {
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
  static Future<bool> completeReservationByOrderId(
    int orderId, {
    bool failOnError = false,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) => UpdateReadiness.track(
    'completeReservationByOrderId',
    () => _updateTrackedCompleteReservationByOrderId(
      orderId,
      failOnError: failOnError,
      actorId: actorId,
      actorName: actorName,
      source: source,
      reason: reason,
    ),
  );

  static Future<bool> _updateTrackedCompleteReservationByOrderId(
    int orderId, {
    bool failOnError = false,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) async {
    try {
      final reservationBox = DatabaseCore.reservationBox;
      if (reservationBox == null) return false;
      for (final reservation in reservationBox.values) {
        if (reservation.linkedOrderId == orderId &&
            ReservationClassification.isRealAdvanceBooking(reservation)) {
          // Already completed: a retry, and the timeline says nothing twice.
          if (reservation.statusEnum != ReservationStatus.completed) {
            final previous = reservation.status;
            reservation.statusEnum = ReservationStatus.completed;
            await reservation.save();
            await ReservationAudit.log(
              action: ReservationAuditAction.complete,
              reservation: reservation,
              actorId: actorId,
              actorName: actorName,
              source: source,
              previousStatus: previous,
              newStatus: reservation.status,
              reason: reason,
              extra: {'orderId': orderId},
            );
          }
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
      if (failOnError) rethrow;
      return false;
    }
  }

  static Future<bool> cancelReservationByOrderId(
    int orderId, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) => UpdateReadiness.track(
    'cancelReservationByOrderId',
    () => _updateTrackedCancelReservationByOrderId(
      orderId,
      actorId: actorId,
      actorName: actorName,
      source: source,
      reason: reason,
    ),
  );

  static Future<bool> _updateTrackedCancelReservationByOrderId(
    int orderId, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) async {
    try {
      final reservationBox = DatabaseCore.reservationBox;
      if (reservationBox == null) return false;
      for (final reservation in reservationBox.values) {
        if (reservation.linkedOrderId == orderId &&
            ReservationClassification.isRealAdvanceBooking(reservation)) {
          // Identity and the Order link are kept; a repeat is a no-op.
          if (reservation.statusEnum != ReservationStatus.cancelled) {
            final previous = reservation.status;
            reservation.statusEnum = ReservationStatus.cancelled;
            await reservation.save();
            await ReservationAudit.log(
              action: ReservationAuditAction.cancel,
              reservation: reservation,
              actorId: actorId,
              actorName: actorName,
              source: source,
              previousStatus: previous,
              newStatus: reservation.status,
              reason: reason,
              extra: {'orderId': orderId},
            );
          }
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
  /// Sets a booking's status.
  ///
  /// The timeline entry is named by the transition (`CONFIRM_RESERVATION`,
  /// `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`, `COMPLETE_RESERVATION`,
  /// otherwise `UPDATE_RESERVATION`). A status already in force is a
  /// redelivery and writes nothing — the entity is convergent by assignment
  /// and so is its history.
  static Future<void> updateReservationStatus(
    String reservationId,
    String newStatus, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) => UpdateReadiness.track(
    'updateReservationStatus',
    () => _updateTrackedUpdateReservationStatus(
      reservationId,
      newStatus,
      actorId: actorId,
      actorName: actorName,
      source: source,
      reason: reason,
    ),
  );

  static Future<void> _updateTrackedUpdateReservationStatus(
    String reservationId,
    String newStatus, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) async {
    final reservation = DatabaseCore.reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );
    final previous = reservation.status;
    final previousEnum = reservation.statusEnum;
    final nextEnum = ReservationStatus.fromStorage(newStatus);
    final unchanged = nextEnum != ReservationStatus.unknown
        ? previousEnum == nextEnum
        : previous.trim().toLowerCase() == newStatus.trim().toLowerCase();
    if (unchanged) return;

    reservation.status = newStatus;
    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
    await ReservationAudit.log(
      action: ReservationAuditAction.forTransition(
        previousEnum,
        reservation.statusEnum,
      ),
      reservation: reservation,
      actorId: actorId,
      actorName: actorName,
      source: source,
      previousStatus: previous,
      newStatus: reservation.status,
      reason: reason,
    );
  }

  /// Edits the guest-facing details of a booking in one write, with one
  /// `UPDATE_RESERVATION` naming the fields that changed. Fields left null
  /// are untouched. Nothing is written when nothing changed.
  static Future<bool> updateReservationDetails(
    String reservationId, {
    String? customerName,
    String? customerPhone,
    String? notes,
    bool clearNotes = false,
    DateTime? reservationDate,
    String? reservationTime,
    int? numberOfGuests,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.track(
    'updateReservationDetails',
    () => _updateTrackedUpdateReservationDetails(
      reservationId,
      customerName: customerName,
      customerPhone: customerPhone,
      notes: notes,
      clearNotes: clearNotes,
      reservationDate: reservationDate,
      reservationTime: reservationTime,
      numberOfGuests: numberOfGuests,
      actorId: actorId,
      actorName: actorName,
      source: source,
    ),
  );

  static Future<bool> _updateTrackedUpdateReservationDetails(
    String reservationId, {
    String? customerName,
    String? customerPhone,
    String? notes,
    bool clearNotes = false,
    DateTime? reservationDate,
    String? reservationTime,
    int? numberOfGuests,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final reservation = findReservationById(reservationId);
    if (reservation == null) return false;

    final changed = <String>[];
    final previous = <String, dynamic>{};
    final next = <String, dynamic>{};

    void track(String field, Object? before, Object? after) {
      if (before == after) return;
      changed.add(field);
      previous[field] = before;
      next[field] = after;
    }

    if (customerName != null) {
      final value = customerName.trim();
      track('customerName', reservation.customerName, value);
      reservation.customerName = value;
    }
    if (customerPhone != null) {
      final value = customerPhone.trim();
      track('customerPhone', reservation.customerPhone, value);
      reservation.customerPhone = value;
    }
    if (clearNotes || notes != null) {
      final value = clearNotes
          ? null
          : (notes!.trim().isEmpty ? null : notes.trim());
      track('notes', reservation.notes, value);
      reservation.notes = value;
    }
    if (reservationDate != null) {
      final before = reservation.reservationDate.toIso8601String().split(
        'T',
      )[0];
      final after = reservationDate.toIso8601String().split('T')[0];
      track('date', before, after);
      reservation.reservationDate = reservationDate;
    }
    if (reservationTime != null) {
      track('time', reservation.reservationTime, reservationTime);
      reservation.reservationTime = reservationTime;
    }
    if (numberOfGuests != null && numberOfGuests > 0) {
      track('guestCount', reservation.numberOfGuests, numberOfGuests);
      reservation.numberOfGuests = numberOfGuests;
    }

    if (changed.isEmpty) return false;

    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
    await ReservationAudit.log(
      action: ReservationAuditAction.update,
      reservation: reservation,
      actorId: actorId,
      actorName: actorName,
      source: source,
      extra: {
        'changedFields': changed,
        'previousValues': previous,
        'newValues': next,
      },
    );
    return true;
  }

  static Future<void> updateReservationPreOrderItems(
    String reservationId,
    List<OrderItem> updatedItems, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.track(
    'updateReservationPreOrderItems',
    () => _updateTrackedUpdateReservationPreOrderItems(
      reservationId,
      updatedItems,
      actorId: actorId,
      actorName: actorName,
      source: source,
    ),
  );

  static Future<void> _updateTrackedUpdateReservationPreOrderItems(
    String reservationId,
    List<OrderItem> updatedItems, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final reservation = DatabaseCore.reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );
    final previousStatus = reservation.status;
    final previousLines = _preOrderSummary(reservation.preOrderItems);

    final clonedItems = updatedItems
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: item.unitPrice * item.quantity,
            comment: item.comment,
            menuItemId: item.menuItemId,
            variantId: item.variantId,
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

    final newLines = _preOrderSummary(reservation.preOrderItems);
    if (newLines.toString() != previousLines.toString() ||
        previousStatus != reservation.status) {
      await ReservationAudit.log(
        action: ReservationAuditAction.update,
        reservation: reservation,
        actorId: actorId,
        actorName: actorName,
        source: source,
        previousStatus: previousStatus,
        newStatus: reservation.status,
        extra: {
          'changedFields': const ['preOrderItems'],
          'previousValues': {'preOrderItems': previousLines},
          'newValues': {'preOrderItems': newLines},
        },
      );
    }
  }

  static List<Map<String, dynamic>> _preOrderSummary(List<OrderItem>? items) =>
      [
        for (final item in items ?? const <OrderItem>[])
          <String, dynamic>{
            'itemName': item.itemName,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
          },
      ];

  static Future<void> updateReservationTables(
    String reservationId,
    List<int> tableNumbers, {
    List<TableRef>? tableRefs,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => UpdateReadiness.track(
    'updateReservationTables',
    () => _updateTrackedUpdateReservationTables(
      reservationId,
      tableNumbers,
      tableRefs: tableRefs,
      actorId: actorId,
      actorName: actorName,
      source: source,
    ),
  );

  static Future<void> _updateTrackedUpdateReservationTables(
    String reservationId,
    List<int> tableNumbers, {
    List<TableRef>? tableRefs,
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
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
    final previousStatus = reservation.status;
    final previousEnum = reservation.statusEnum;
    final previousRefs = ReservationTableAvailability.tableRefsOf(
      reservation,
    ).map((ref) => ref.encode()).toList();

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

    final newRefs = [for (final ref in refs) ref.encode()];
    final tablesChanged = newRefs.join(',') != previousRefs.join(',');
    final statusChanged = previousStatus != reservation.status;
    if (tablesChanged || statusChanged) {
      // Assigning tables to a pending booking is how the POS confirms it, so
      // the transition names the event and the tables ride along.
      await ReservationAudit.log(
        action: ReservationAuditAction.forTransition(
          previousEnum,
          reservation.statusEnum,
        ),
        reservation: reservation,
        actorId: actorId,
        actorName: actorName,
        source: source,
        previousStatus: previousStatus,
        newStatus: reservation.status,
        extra: {
          if (tablesChanged) 'changedFields': const ['tableRefs'],
          if (tablesChanged) 'previousValues': {'tableRefs': previousRefs},
          if (tablesChanged) 'newValues': {'tableRefs': newRefs},
        },
      );
    }
  }

  /// Removes the row. The timeline keeps the booking's last snapshot, so a
  /// deleted Reservation is still accountable for; an already-absent one is a
  /// redelivery and writes nothing.
  static Future<void> deleteReservation(
    String reservationId, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) => UpdateReadiness.track(
    'deleteReservation',
    () => _updateTrackedDeleteReservation(
      reservationId,
      actorId: actorId,
      actorName: actorName,
      source: source,
      reason: reason,
    ),
  );

  static Future<void> _updateTrackedDeleteReservation(
    String reservationId, {
    String actorId = 'system',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? reason,
  }) async {
    try {
      final reservation = findReservationById(reservationId);
      if (reservation == null) return;
      // Written before the row goes, so the history exists even if the
      // delete itself fails half-way.
      await ReservationAudit.log(
        action: ReservationAuditAction.delete,
        reservation: reservation,
        actorId: actorId,
        actorName: actorName,
        source: source,
        previousStatus: reservation.status,
        reason: reason,
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
