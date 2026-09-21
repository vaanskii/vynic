/// Operational status of an [Order].
///
/// Backed by the existing `Order.status` `String` field — this enum does not
/// change Hive storage. Use [OrderStatus.fromStorage] to read and
/// [storageValue] to write, so every call site agrees on the same set of
/// canonical strings instead of re-typing literals.
/// The four statuses this system actually writes are [pending], [confirmed],
/// [closed] and [cancelled]. [preparing] and [served] are read-only: no code
/// path in this repository writes either, and they exist so historical rows
/// still parse and display rather than becoming [unknown]. Do not introduce a
/// new writer for them without deciding what they mean operationally first.
///
/// Being parseable is not the same as being assignable, and neither is the
/// same as being assignable *by a remote caller*. Three different sets:
///
/// - **Valid in storage** — [pending], [confirmed], [preparing], [served],
///   [closed], [cancelled]. Everything a Hive row or a backup may legitimately
///   contain. [OrderStatus.fromStorage] is the reader.
/// - **Valid for a local domain transition** — [pending], [confirmed],
///   [closed], [cancelled], and only through the path that owns each:
///   creation writes the first two, `CloseTableTransaction` writes [closed],
///   `CancelOrderTransaction` writes [cancelled].
/// - **Valid for `ORDER_STATUS_UPDATE`** — [confirmed] and [cancelled] only.
///   See [RemoteOrderStatusRule].
enum OrderStatus {
  pending,
  confirmed,

  /// Legacy/read-only. Parsed and displayed, never written by this codebase.
  preparing,

  /// Legacy/read-only. Parsed and displayed, never written by this codebase.
  served,

  closed,
  cancelled,

  /// Storage held a value this enum doesn't recognize (corrupt data, a
  /// future value written by a newer app version, etc.). Callers should
  /// treat this the same as an unknown/non-terminal state rather than
  /// guessing — never silently reinterpret it as [pending].
  unknown;

  /// Parses the raw Hive/JSON string into a canonical status.
  ///
  /// Handles the known legacy quirks seen in production data:
  /// - `'paid'` — never written by current client or server code (grep-
  ///   verified), only checked for on read. Treated as an alias for
  ///   [closed].
  /// - `'preparing'` / `'served'` — likewise unwritten here, kept parseable
  ///   because a historical row may still carry one. Dropping them would turn
  ///   such a row into [unknown], which every caller is told to treat as
  ///   non-terminal — an open table nobody can close.
  /// - case/whitespace variance — normalized before matching.
  ///
  /// Reading a legacy value is deliberately more permissive than writing one:
  /// [RemoteOrderStatusRule] refuses to let a remote caller assign any of
  /// them.
  static OrderStatus fromStorage(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'pending':
        return OrderStatus.pending;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'preparing':
        return OrderStatus.preparing;
      case 'served':
        return OrderStatus.served;
      case 'closed':
      case 'paid': // legacy alias — see doc comment above.
        return OrderStatus.closed;
      case 'cancelled':
      case 'canceled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.unknown;
    }
  }

  /// Canonical string to persist. [unknown] has no canonical form and must
  /// never be written back — callers should not construct new records with
  /// an unknown status.
  String get storageValue {
    switch (this) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.served:
        return 'served';
      case OrderStatus.closed:
        return 'closed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.unknown:
        throw StateError('OrderStatus.unknown has no storage representation');
    }
  }

  /// True once the order is settled and its table should be freed — mirrors
  /// the `status == 'closed' || status == 'cancelled'` (plus legacy `'paid'`)
  /// checks duplicated across the codebase today.
  bool get isTerminal =>
      this == OrderStatus.closed || this == OrderStatus.cancelled;
}

/// What a remote `ORDER_STATUS_UPDATE` should do with the status it asked for.
///
/// One verdict per request, resolved before anything is written, so the
/// decision cannot differ between the Edge handler and the legacy LAN adapter.
enum RemoteOrderStatusDecision {
  /// Assign the parsed status to the Order.
  assign,

  /// The Order is already in the requested state. Report success and write
  /// nothing, so a redelivered command leaves no second trace.
  alreadyInState,

  /// A cancellation is not a status assignment: it has to leave the same
  /// durable history a POS cancellation leaves. Route it through
  /// `CancelOrderTransaction`.
  cancelThroughTransaction,

  /// A real status, but one no remote caller may assign — `closed`/`paid`
  /// (closing is a fiscal transaction, not a string), and the legacy
  /// `preparing`/`served` (readable, not writable).
  notRemotelyAssignable,

  /// Not a status this system recognizes at all. Never persisted, never
  /// silently mapped onto a business state.
  unknownStatus,

  /// The Order is already closed or cancelled. A status string does not reopen
  /// it; a closed Order is restored through the restore path first.
  orderIsTerminal,
}

/// The one authoritative rule for a Cloud/Manager-originated status change.
///
/// `ORDER_STATUS_UPDATE` used to take a status string and hand it straight to
/// the repository, so any caller that could reach the command could persist
/// any string at all — including a value no reader understands, which every
/// caller then treats as non-terminal: an open table nobody can close.
///
/// The remotely assignable set is deliberately much smaller than the set
/// storage can hold. `closed` is missing on purpose: a fiscal close is
/// `CloseTableTransaction` (Sale, closure id, journal, typed audit event), and
/// letting a remote string set `status=closed` would produce a closed Order
/// with no Sale behind it. `cancelled` is accepted but is not an assignment —
/// it is delegated to `CancelOrderTransaction`, which is the only writer of a
/// genuine cancellation.
abstract final class RemoteOrderStatusRule {
  /// The only statuses `ORDER_STATUS_UPDATE` may ask for.
  static const Set<OrderStatus> assignable = <OrderStatus>{
    OrderStatus.confirmed,
    OrderStatus.cancelled,
  };

  /// Decides what to do, without touching storage.
  ///
  /// [current] is the Order's status as stored today; pass
  /// [OrderStatus.unknown] for a row whose status this build cannot read —
  /// it is treated as non-terminal, so a repair to `confirmed` still works.
  static RemoteOrderStatusDecision decide({
    required String? requested,
    required OrderStatus current,
  }) {
    final target = OrderStatus.fromStorage(requested);
    if (target == OrderStatus.unknown) {
      return RemoteOrderStatusDecision.unknownStatus;
    }
    // Cancellation is routed whatever the current state is: the transaction is
    // itself convergent and owns the "already cancelled" and "closed, so not
    // cancellable" answers.
    if (target == OrderStatus.cancelled) {
      return RemoteOrderStatusDecision.cancelThroughTransaction;
    }
    if (!assignable.contains(target)) {
      return RemoteOrderStatusDecision.notRemotelyAssignable;
    }
    if (current == target) {
      return RemoteOrderStatusDecision.alreadyInState;
    }
    if (current.isTerminal) {
      return RemoteOrderStatusDecision.orderIsTerminal;
    }
    return RemoteOrderStatusDecision.assign;
  }
}
