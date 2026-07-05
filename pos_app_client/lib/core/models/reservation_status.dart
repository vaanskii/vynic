/// Operational status of a [Reservation].
///
/// Backed by the existing `Reservation.status` `String` field — this enum
/// does not change Hive storage. Use [ReservationStatus.fromStorage] to read
/// and [storageValue] to write.
///
/// Note: this enum covers **exact-match** normalization only (case/whitespace/
/// underscore variance). Several call sites (`home_reservations_helper.dart`,
/// `admin_reservations_section.dart`, `reservations_management_section.dart`)
/// use `startsWith('confirmed')`/`startsWith('cancelled')` fuzzy-prefix
/// matching instead of exact equality. That tolerance is intentionally left
/// alone here — there is no way to confirm from source alone whether any
/// live restaurant data actually relies on a composite value that tolerance
/// was written to catch, and narrowing it silently would risk changing
/// behavior. See `docs/VYNIC_PROJECT_PLAN.md` Phase 4 report for the
/// call-sites-not-migrated list.
enum ReservationStatus {
  pending,
  preparing,
  confirmed,
  inProgress,
  completed,
  cancelled,
  noShow,

  /// Storage held a value this enum doesn't recognize. Treat as non-final,
  /// non-actionable — never silently reinterpret as [pending].
  unknown;

  static ReservationStatus fromStorage(String? raw) {
    final normalized = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(RegExp(r'\s+'), '-');
    switch (normalized) {
      case 'pending':
        return ReservationStatus.pending;
      case 'preparing':
        return ReservationStatus.preparing;
      case 'confirmed':
        return ReservationStatus.confirmed;
      case 'in-progress':
      case 'inprogress': // seen without the hyphen in existing tolerance code.
        return ReservationStatus.inProgress;
      case 'completed':
        return ReservationStatus.completed;
      case 'cancelled':
      case 'canceled':
        return ReservationStatus.cancelled;
      case 'no-show':
      case 'noshow':
        return ReservationStatus.noShow;
      default:
        return ReservationStatus.unknown;
    }
  }

  /// Canonical string to persist. [unknown] has no canonical form.
  String get storageValue {
    switch (this) {
      case ReservationStatus.pending:
        return 'pending';
      case ReservationStatus.preparing:
        return 'preparing';
      case ReservationStatus.confirmed:
        return 'confirmed';
      case ReservationStatus.inProgress:
        return 'in-progress';
      case ReservationStatus.completed:
        return 'completed';
      case ReservationStatus.cancelled:
        return 'cancelled';
      case ReservationStatus.noShow:
        return 'no-show';
      case ReservationStatus.unknown:
        throw StateError(
          'ReservationStatus.unknown has no storage representation',
        );
    }
  }

  /// True for a reservation that has reached a terminal outcome (completed,
  /// cancelled, or no-show) — mirrors the
  /// `status == 'completed' || status == 'cancelled' || status == 'canceled'
  /// || status == 'no-show'` check duplicated in close-day finalization.
  bool get isFinal =>
      this == ReservationStatus.completed ||
      this == ReservationStatus.cancelled ||
      this == ReservationStatus.noShow;
}
