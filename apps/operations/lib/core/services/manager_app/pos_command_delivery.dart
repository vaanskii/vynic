/// How far a Cloud-originated operation has actually got on the POS.
///
/// The Manager used to treat any 2xx as "the POS did it", which was true while
/// the backend reached the POS synchronously over the LAN: the response could
/// not come back before the terminal had answered. It is not true of a queue.
/// A command Cloud has recorded has not run yet, and telling a manager standing
/// at a printer that a check printed — when it is waiting for a POS that may be
/// switched off — is the kind of lie somebody acts on.
enum PosCommandDelivery {
  /// Cloud recorded it. The POS has not claimed it yet.
  queued,

  /// A POS holds it and has not reported back.
  claimed,

  /// The POS ran it and said so. Only this one means "done".
  succeeded,

  /// The POS ran it and reported a failure.
  failed,

  /// Handed to the POS over the LAN and accepted. Transitional.
  deliveredLegacy,

  /// Nothing could be recorded — no enrolled terminal and no LAN address.
  unavailable,

  /// The response predates this field, or carried something unreadable.
  unknown;

  /// Whether the restaurant has actually performed the operation.
  bool get isDone =>
      this == PosCommandDelivery.succeeded ||
      this == PosCommandDelivery.deliveredLegacy;

  /// Whether it is recorded and still on its way.
  bool get isPending =>
      this == PosCommandDelivery.queued || this == PosCommandDelivery.claimed;

  /// Reads the `posDelivery` block a migrated endpoint returns.
  ///
  /// An older backend sends nothing, and that is [unknown] rather than a
  /// failure: the request succeeded, and the caller decides how to describe an
  /// outcome nobody reported.
  static PosCommandDelivery fromResponse(Object? body) {
    if (body is! Map) return PosCommandDelivery.unknown;
    final delivery = body['posDelivery'];
    if (delivery is! Map) return PosCommandDelivery.unknown;
    switch (delivery['status']?.toString()) {
      case 'QUEUED':
        return PosCommandDelivery.queued;
      case 'CLAIMED':
        return PosCommandDelivery.claimed;
      case 'SUCCEEDED':
        return PosCommandDelivery.succeeded;
      case 'FAILED':
        return PosCommandDelivery.failed;
      case 'DELIVERED_LEGACY':
        return PosCommandDelivery.deliveredLegacy;
      case 'UNAVAILABLE':
        return PosCommandDelivery.unavailable;
      default:
        return PosCommandDelivery.unknown;
    }
  }
}
