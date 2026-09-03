import 'reservation.dart';

/// What a row in the reservation box actually is.
///
/// The box has never held only bookings. Every order-creation path writes one:
/// `OrderRepository.createOrder` defaults `createReservationRecord` to true and
/// writes a `Walk-in` row noted `Order #N`, takeaway writes an `isTakeAway`
/// row, and `createOrderForPackage` inherits the walk-in default. Only
/// [ActivateReservationTransaction] opts out, because there a real booking
/// already exists. So the box is roughly one row per order ever placed, plus
/// the actual bookings.
///
/// The POS still needs those rows — the home takeaway panel renders and totals
/// from them — so they stay. What they are not is *bookings*, and this names
/// the difference in one place instead of the three near-copies of the same
/// string check that grew up around it.
enum ReservationRecordKind {
  /// A genuine advance booking, activated or not.
  advanceBooking,

  /// Written alongside a takeaway order so the home panel can show it.
  takeawayBookkeeping,

  /// Written alongside a walk-in or package order. Nothing reads it.
  orderBookkeeping,

  /// Carries a generated row's marks but not conclusively.
  ///
  /// Treated as a booking everywhere it matters. Excluding a real booking hides
  /// it from the manager and frees its table on the public site; including a
  /// stray bookkeeping row costs one mirrored row that every consumer already
  /// filters. Only one of those two mistakes is worth avoiding.
  ambiguousLegacy;

  /// Whether Cloud should hold this row as a reservation.
  bool get belongsInCloudProjection =>
      this == advanceBooking || this == ambiguousLegacy;
}

/// The one place that decides whether a reservation row is a real booking.
///
/// ## What identifies a generated row
///
/// Two marks, both written at creation and never rewritten afterwards:
/// `isTakeAway`, and a `notes` value that *begins* `Order #`. Activation is
/// explicit that "notes stay user-owned", and close-day only moves status, so
/// neither mark is disturbed by the lifecycle.
///
/// ## What deliberately does not identify one
///
/// `linkedOrderId` must not be part of this. A booking whose guest has arrived
/// is linked to the order serving it — that is the point of activation — and
/// rejecting it would drop exactly the reservations a restaurant most needs to
/// see. It is also useless for history: close-day nulls it on every past row.
/// The existing three-clause predicates that do use it
/// (`ReservationTableAvailability.isRealTableBooking`, `isRealPosTableBooking`)
/// answer a narrower question — "is this an un-activated table booking" — and
/// are left alone.
class ReservationClassification {
  ReservationClassification._();

  /// The note a generated walk-in or package row is created with.
  static const String generatedOrderNotePrefix = 'Order #';

  /// The customer name a generated walk-in or package row is created with.
  static const String generatedWalkInCustomerName = 'walk-in';

  static ReservationRecordKind kindOf(Reservation reservation) => kindOfFields(
    isTakeAway: reservation.isTakeAway,
    notes: reservation.notes,
    customerName: reservation.customerName,
  );

  /// [kindOf] for a row that has been serialized — a backup entry, or a record
  /// read back off the wire — so the same rule can answer for both shapes.
  static ReservationRecordKind kindOfFields({
    required bool isTakeAway,
    required String? notes,
    required String? customerName,
  }) {
    if (isTakeAway) return ReservationRecordKind.takeawayBookkeeping;
    if ((notes ?? '').trimLeft().startsWith(generatedOrderNotePrefix)) {
      return ReservationRecordKind.orderBookkeeping;
    }
    // Named like a generated row but without the note that would prove it —
    // an edited or truncated legacy shape. Not classified as bookkeeping.
    if ((customerName ?? '').trim().toLowerCase() ==
        generatedWalkInCustomerName) {
      return ReservationRecordKind.ambiguousLegacy;
    }
    return ReservationRecordKind.advanceBooking;
  }

  /// Whether [reservation] is a real advance booking for Cloud and for any
  /// consumer that means "booking" rather than "row in the reservation box".
  ///
  /// True for an activated booking. True for an unclassifiable legacy shape.
  static bool isRealAdvanceBooking(Reservation reservation) =>
      kindOf(reservation).belongsInCloudProjection;

  /// The bookings a full snapshot should carry, and what it left behind.
  ///
  /// This is the whole projection rule in one place, so the property that
  /// matters — a mixed box projects to bookings only, activated ones included —
  /// is something a test can state directly rather than infer from a payload.
  static ReservationProjection projectForCloud(
    Iterable<Reservation> reservations,
  ) {
    final bookings = <Reservation>[];
    var takeawayCount = 0;
    var generatedOrderCount = 0;
    var ambiguousCount = 0;
    var localCount = 0;
    for (final reservation in reservations) {
      localCount++;
      switch (kindOf(reservation)) {
        case ReservationRecordKind.takeawayBookkeeping:
          takeawayCount++;
        case ReservationRecordKind.orderBookkeeping:
          generatedOrderCount++;
        case ReservationRecordKind.ambiguousLegacy:
          ambiguousCount++;
          bookings.add(reservation);
        case ReservationRecordKind.advanceBooking:
          bookings.add(reservation);
      }
    }
    return ReservationProjection(
      bookings: bookings,
      localCount: localCount,
      takeawayCount: takeawayCount,
      generatedOrderCount: generatedOrderCount,
      ambiguousCount: ambiguousCount,
    );
  }
}

/// What one snapshot's reservation section carries, and what it did not.
class ReservationProjection {
  const ReservationProjection({
    required this.bookings,
    required this.localCount,
    required this.takeawayCount,
    required this.generatedOrderCount,
    required this.ambiguousCount,
  });

  /// The rows to send, in box order.
  final List<Reservation> bookings;

  /// How many rows the box holds.
  final int localCount;

  final int takeawayCount;
  final int generatedOrderCount;

  /// Rows that could not be classified and are sent as bookings.
  final int ambiguousCount;

  int get sentCount => bookings.length;

  int get bookkeepingCount => takeawayCount + generatedOrderCount;

  /// Counts only. A reservation carries a customer's name, phone and notes,
  /// and none of that belongs in a log line.
  String get summaryLine =>
      '[ReservationProjection] local=$localCount sent=$sentCount '
      'bookkeeping=$bookkeepingCount '
      '(takeaway=$takeawayCount generatedOrder=$generatedOrderCount) '
      'ambiguous=$ambiguousCount';
}
