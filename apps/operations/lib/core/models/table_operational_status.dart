/// Operational status of a [TableModel], derived from its existing fields.
///
/// This is a **pure derivation, never persisted**. `TableModel.isReserved`
/// is a single boolean currently overloaded to mean both "booked for a
/// future reservation" and "occupied with a live order" — this enum is the
/// explicit disambiguation of that conflation, computed from the same
/// underlying fields (`isReserved`, `activeOrderId`, `reservationId`), not a
/// new source of truth.
///
/// `reservedSoon`, `seatedLate`, `dirty`, and `blocked` from
/// `docs/UI_PLAN.md` §3 are intentionally not modeled here: `dirty` and
/// `blocked` have no backing data today (would need a new stored flag), and
/// `reservedSoon`/`seatedLate` require comparing a linked reservation's time
/// against the current business clock — a business-logic decision, not a
/// field-derivation one. Out of scope for this pass; noted as near-future in
/// the Phase 4 report.
enum TableOperationalStatus {
  /// No active order and not reserved.
  free,

  /// Has a live order (`activeOrderId != null`).
  occupied,

  /// Booked for a reservation but no order yet (`isReserved == true`,
  /// `activeOrderId == null`).
  reserved,
}
