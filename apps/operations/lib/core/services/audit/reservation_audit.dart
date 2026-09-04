import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

/// The action names of the Reservation timeline in the append-only log.
///
/// A Reservation is not an Order, so it has no per-Order report; its history
/// lives in `AuditEventLog` keyed by `reservationId` in `data`. The names are
/// constants so a typo cannot open a second, invisible category, and so a
/// reader can enumerate them.
abstract final class ReservationAuditAction {
  static const String create = 'CREATE_RESERVATION';
  static const String update = 'UPDATE_RESERVATION';
  static const String confirm = 'CONFIRM_RESERVATION';
  static const String cancel = 'CANCEL_RESERVATION';
  static const String noShow = 'NO_SHOW_RESERVATION';
  static const String complete = 'COMPLETE_RESERVATION';
  static const String delete = 'DELETE_RESERVATION';

  /// What the Admin panel wrote before this registry existed. Kept readable;
  /// never written again.
  static const String legacyCancelled = 'reservation_cancelled';

  static const List<String> all = [
    create,
    update,
    confirm,
    cancel,
    noShow,
    complete,
    delete,
  ];

  /// The canonical name for a stored action, or null when it is not a
  /// Reservation action at all.
  static String? normalize(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == legacyCancelled) return cancel;
    final upper = trimmed.toUpperCase();
    for (final action in all) {
      if (action == upper) return action;
    }
    return null;
  }

  /// The action a status transition means. Status and action are separate
  /// concepts: a booking that moves to `confirmed` was confirmed, whatever
  /// the caller called the operation.
  static String forTransition(
    ReservationStatus previous,
    ReservationStatus next,
  ) {
    if (previous == next) return update;
    switch (next) {
      case ReservationStatus.confirmed:
        return confirm;
      case ReservationStatus.cancelled:
        return cancel;
      case ReservationStatus.noShow:
        return noShow;
      case ReservationStatus.completed:
        return complete;
      case ReservationStatus.pending:
      case ReservationStatus.preparing:
      case ReservationStatus.inProgress:
      case ReservationStatus.unknown:
        return update;
    }
  }
}

/// Writes the Reservation timeline.
///
/// One entry point so every path that touches a booking — POS screens, the
/// Admin panel, Manager and website commands relayed through Cloud, Close Day
/// — describes what happened with the same fields.
abstract final class ReservationAudit {
  static Future<void> log({
    required String action,
    required Reservation reservation,
    required String actorId,
    String? actorName,
    required AuditSource source,
    String? previousStatus,
    String? newStatus,
    String? reason,
    Map<String, dynamic> extra = const {},
  }) async {
    final actor = actorId.trim().isEmpty ? 'unknown' : actorId.trim();
    final name = (actorName == null || actorName.trim().isEmpty)
        ? actor
        : actorName.trim();
    await AuditEventService.logEvent(
      action: action,
      userId: actor,
      data: <String, dynamic>{
        ...snapshot(reservation),
        if (previousStatus != null) 'previousStatus': previousStatus,
        if (newStatus != null) 'newStatus': newStatus,
        AuditSource.detailsKey: source.wireValue,
        'actorId': actor,
        'actorName': name,
        'businessDate': BusinessDayRepository.getCurrentDate()
            .toIso8601String()
            .split('T')[0],
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        ...extra,
      },
    );
  }

  /// The fields the Reservation model already stores, and nothing more.
  static Map<String, dynamic> snapshot(Reservation reservation) {
    return <String, dynamic>{
      'reservationId': reservation.id,
      'customerName': reservation.customerName,
      'customerPhone': reservation.customerPhone,
      'date': reservation.reservationDate.toIso8601String().split('T')[0],
      'time': reservation.reservationTime,
      'guestCount': reservation.numberOfGuests,
      'tableRefs': ReservationTableAvailability.tableRefsOf(
        reservation,
      ).map((ref) => ref.encode()).toList(growable: false),
      'status': reservation.status,
      'isTakeAway': reservation.isTakeAway,
      if (reservation.linkedOrderId != null)
        'linkedOrderId': reservation.linkedOrderId,
      'preOrderItemCount': reservation.preOrderItems?.length ?? 0,
    };
  }
}
