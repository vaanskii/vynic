// GENERATED FILE — DO NOT EDIT.
//
// Rendered from packages/contracts/schema/edge-command.contract.json
// by packages/contracts/scripts/generate.mjs.
//
// Change the schema and regenerate; edits here are overwritten and
// CI fails on a stale or hand-edited output.

/// The Cloud → Edge work contract, as the POS sees it.
///
/// Cloud cannot reach a restaurant's LAN, so the Edge opens the connection with
/// its Device credential, claims work, executes it locally, and reports the
/// outcome. Delivery is at-least-once: a claim is a lease, and a lease that
/// expires unacknowledged is offered again, so every command type must be safe
/// to execute twice.
library;

/// The envelope version this build speaks. Sent on every claim so Cloud
/// withholds work this POS would not understand.
const int edgeCommandContractVersion = 2;

/// Batch size requested when none is given, and the ceiling Cloud enforces.
const int edgeCommandDefaultBatchSize = 20;
const int edgeCommandMaxBatchSize = 50;

/// How long a claimed command stays leased before Cloud offers it again.
const int edgeCommandClaimLeaseSeconds = 120;

/// Redeliveries before Cloud gives up on a command.
const int edgeCommandMaxAttempts = 10;

/// Every envelope version this build understands, newest first.
///
/// A fleet does not upgrade all at once, so an Edge has to keep accepting the
/// version before its own while Cloud still holds work enqueued under it. Sent
/// on every claim; Cloud withholds anything outside this list.
const List<int> edgeCommandCompatibleVersions = <int>[2, 1];

/// Every command type this contract version defines.
class EdgeCommandTypes {
  EdgeCommandTypes._();

  /// Does nothing on the Edge. Exists so the transport can be exercised end to end without performing restaurant work.
  ///
  /// Idempotency: Nothing happens, so nothing can happen twice.
  ///
  /// Payload: none.
  static const String noop = 'NOOP';

  /// Replace an existing order's lines, total and service-fee flag.
  ///
  /// Idempotency: Assignment, not adjustment: the payload is the order's new content, so a second delivery writes the same values. The audit diff is computed against what is stored, so a replay produces no events, and MoneyAudit already skips a service-fee entry when the flag did not move.
  ///
  /// Payload:
  /// - `posOrderId`: int, the order's POS identity
  /// - `updatedBy`: string?, who the Manager identified itself as
  /// - `items`: array of {itemName, quantity, unitPrice, itemKey?, comment?}
  /// - `totalAmount`: number?
  /// - `includeServiceFee`: bool?
  ///
  /// Failure: order_not_found when no such order exists locally.
  static const String orderUpdate = 'ORDER_UPDATE';

  /// Remove an order from the POS and release the tables it held.
  ///
  /// Idempotency: The goal state is 'this order is gone'. An order already absent satisfies it, so a redelivery succeeds rather than reporting a missing order.
  ///
  /// Payload:
  /// - `posOrderId`: int
  static const String orderCancel = 'ORDER_CANCEL';

  /// Set an order's status.
  ///
  /// Idempotency: Assignment. The same status written twice is the same status.
  ///
  /// Payload:
  /// - `posOrderId`: int
  /// - `status`: string
  static const String orderStatusUpdate = 'ORDER_STATUS_UPDATE';

  /// Create or update a takeaway order the Manager originated.
  ///
  /// Idempotency: Keyed on the Cloud-allocated posOrderId and written as an upsert, so a redelivery updates the one order. The kitchen check is sent only when the order did not already exist, so a replay does not reprint it.
  ///
  /// Payload:
  /// - `posOrderId`: int, allocated by Cloud
  /// - `customerName`: string
  /// - `pickupTime`: string
  /// - `waiterName`: string
  /// - `businessDate`: string?, YYYY-MM-DD
  /// - `items`: array of {itemName, quantity, unitPrice, comment?}
  /// - `totalAmount`: number
  static const String takeawayOrderUpsert = 'TAKEAWAY_ORDER_UPSERT';

  /// Create or update a walk-in dine-in order on one or more tables.
  ///
  /// Idempotency: Same as TAKEAWAY_ORDER_UPSERT: upsert on the Cloud-allocated posOrderId, kitchen check only on first arrival.
  ///
  /// Payload:
  /// - `posOrderId`: int, allocated by Cloud
  /// - `tableNumbers`: string[]
  /// - `floor`: string
  /// - `waiterName`: string
  /// - `guestCount`: int
  /// - `businessDate`: string?, YYYY-MM-DD
  /// - `items`: array of {itemName, quantity, unitPrice, comment?}
  /// - `totalAmount`: number
  static const String dineInOrderUpsert = 'DINE_IN_ORDER_UPSERT';

  /// Print an order's customer pre-bill on the POS receipt printer.
  ///
  /// Idempotency: Not naturally idempotent — paper is a side effect the world keeps. Safety comes from the local execution journal: a command already recorded as succeeded is acknowledged again without printing. A command interrupted mid-execution is NOT reprinted automatically, because the honest answer to 'did the paper come out' is unknown and a silent second check is worse than a reported failure.
  ///
  /// Payload:
  /// - `posOrderId`: int
  ///
  /// Failure: order_not_found; printer failures surface from the local print service.
  ///
  /// Not repeated after an interrupted execution: the outcome is unknown and
  /// repeating it would be worse than reporting it.
  static const String orderCheckPrint = 'ORDER_CHECK_PRINT';

  /// Create a reservation the Manager or the public website originated.
  ///
  /// Idempotency: Cloud allocates reservationId, so the POS creates it only if that id is absent and returns the existing one otherwise. This is why the id moved to Cloud: a POS-generated id made a redelivery a second booking.
  ///
  /// Payload:
  /// - `reservationId`: string, allocated by Cloud
  /// - `customerName`: string
  /// - `customerPhone`: string
  /// - `tableNumbers`: int[], legacy reservation table codes
  /// - `reservationDate`: string, ISO date
  /// - `reservationTime`: string, HH:mm
  /// - `numberOfGuests`: int
  /// - `notes`: string?
  /// - `createdBy`: string
  /// - `status`: string
  /// - `isTakeAway`: bool
  /// - `preOrderItems`: array of order items
  static const String reservationCreate = 'RESERVATION_CREATE';

  /// Set a reservation's status.
  ///
  /// Idempotency: Assignment.
  ///
  /// Payload:
  /// - `reservationId`: string
  /// - `status`: string
  static const String reservationStatusUpdate = 'RESERVATION_STATUS_UPDATE';

  /// Remove a reservation from the POS.
  ///
  /// Idempotency: The goal state is 'this reservation is gone'; already absent satisfies it.
  ///
  /// Payload:
  /// - `reservationId`: string
  static const String reservationDelete = 'RESERVATION_DELETE';

  /// Print a reservation's kitchen check on the POS kitchen printer.
  ///
  /// Idempotency: Journal-guarded, exactly as ORDER_CHECK_PRINT. An interrupted print is not repeated automatically.
  ///
  /// Payload:
  /// - `reservationId`: string
  /// - `requestedBy`: string?
  ///
  /// Failure: reservation_not_found.
  ///
  /// Not repeated after an interrupted execution: the outcome is unknown and
  /// repeating it would be worse than reporting it.
  static const String reservationCheckPrint = 'RESERVATION_CHECK_PRINT';

  /// Print a counted-menu draft on the POS receipt printer from the payload itself.
  ///
  /// Idempotency: Journal-guarded, exactly as ORDER_CHECK_PRINT. The draft lives in Cloud rather than POS Hive, which is why the whole thing travels in the payload.
  ///
  /// Payload:
  /// - `displayName`: string?
  /// - `items`: array of {itemName, quantity, unitPrice, total?, comment?}
  /// - `subtotal`: number
  /// - `serviceFeeAmount`: number
  /// - `total`: number
  /// - `includeServiceFee`: bool
  /// - `language`: string?, ka|en
  ///
  /// Not repeated after an interrupted execution: the outcome is unknown and
  /// repeating it would be worse than reporting it.
  static const String countedMenuPrint = 'COUNTED_MENU_PRINT';

  /// Record an expense the Manager entered.
  ///
  /// Idempotency: Cloud allocates the expense id and the POS upserts on it, so a redelivery updates the one record instead of adding a second.
  ///
  /// Payload:
  /// - `id`: string, allocated by Cloud
  /// - `description`: string
  /// - `amount`: number
  /// - `category`: string
  /// - `paymentType`: string
  /// - `createdAt`: string?, ISO
  /// - `businessDate`: string?, YYYY-MM-DD
  static const String expenseCreate = 'EXPENSE_CREATE';

  /// Add a staff user to the POS.
  ///
  /// Idempotency: The goal state is 'this username exists with this role and PIN'. Cloud has already refused a duplicate username before enqueueing, so a username that exists locally means the command has landed before; the handler reconciles the role and PIN and succeeds.
  ///
  /// Payload:
  /// - `username`: string
  /// - `pinCode`: string
  /// - `role`: string
  static const String staffCreate = 'STAFF_CREATE';

  /// Set a staff user's PIN.
  ///
  /// Idempotency: Assignment. The same PIN written twice is the same PIN.
  ///
  /// Payload:
  /// - `username`: string
  /// - `pinCode`: string
  static const String staffPinUpdate = 'STAFF_PIN_UPDATE';

  /// Set a staff user's role.
  ///
  /// Idempotency: Assignment.
  ///
  /// Payload:
  /// - `username`: string
  /// - `role`: string
  static const String staffRoleUpdate = 'STAFF_ROLE_UPDATE';

  /// Rename a staff user.
  ///
  /// Idempotency: The goal state is 'newUsername exists and oldUsername does not'. A redelivery finds exactly that and succeeds without touching anything.
  ///
  /// Payload:
  /// - `oldUsername`: string
  /// - `newUsername`: string
  static const String staffRename = 'STAFF_RENAME';

  /// Remove a staff user from the POS.
  ///
  /// Idempotency: The goal state is 'this username is gone'; already absent satisfies it.
  ///
  /// Payload:
  /// - `username`: string
  static const String staffDelete = 'STAFF_DELETE';

  static const Set<String> all = <String>{
    'NOOP',
    'ORDER_UPDATE',
    'ORDER_CANCEL',
    'ORDER_STATUS_UPDATE',
    'TAKEAWAY_ORDER_UPSERT',
    'DINE_IN_ORDER_UPSERT',
    'ORDER_CHECK_PRINT',
    'RESERVATION_CREATE',
    'RESERVATION_STATUS_UPDATE',
    'RESERVATION_DELETE',
    'RESERVATION_CHECK_PRINT',
    'COUNTED_MENU_PRINT',
    'EXPENSE_CREATE',
    'STAFF_CREATE',
    'STAFF_PIN_UPDATE',
    'STAFF_ROLE_UPDATE',
    'STAFF_RENAME',
    'STAFF_DELETE',
  };

  /// Types safe to execute more than once.
  ///
  /// A type absent from this set must not be executed on redelivery without a
  /// handler-specific idempotency boundary of its own.
  static const Set<String> idempotent = <String>{
    'NOOP',
    'ORDER_UPDATE',
    'ORDER_CANCEL',
    'ORDER_STATUS_UPDATE',
    'TAKEAWAY_ORDER_UPSERT',
    'DINE_IN_ORDER_UPSERT',
    'ORDER_CHECK_PRINT',
    'RESERVATION_CREATE',
    'RESERVATION_STATUS_UPDATE',
    'RESERVATION_DELETE',
    'RESERVATION_CHECK_PRINT',
    'COUNTED_MENU_PRINT',
    'EXPENSE_CREATE',
    'STAFF_CREATE',
    'STAFF_PIN_UPDATE',
    'STAFF_ROLE_UPDATE',
    'STAFF_RENAME',
    'STAFF_DELETE',
  };

  /// Types that must NOT be re-run after an interrupted execution.
  ///
  /// These are the ones whose side effect leaves the machine — paper, mostly.
  /// A command the POS started and never finished has an unknown outcome, and
  /// quietly doing it again is worse than reporting that nobody knows.
  static const Set<String> noRepeatAfterInterruption = <String>{
    'ORDER_CHECK_PRINT',
    'RESERVATION_CHECK_PRINT',
    'COUNTED_MENU_PRINT',
  };
}

/// What the Edge may report back about a command.
class EdgeCommandResultStatus {
  EdgeCommandResultStatus._();

  static const String succeeded = 'SUCCEEDED';
  static const String failed = 'FAILED';
}

/// One unit of work, as the Edge receives it.
class EdgeCommandEnvelope {
  const EdgeCommandEnvelope({
    required this.contractVersion,
    required this.commandId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    required this.attempt,
    required this.issuedAt,
    required this.leaseExpiresAt,
  });

  final int contractVersion;
  final String commandId;
  final String type;
  final Object? payload;

  /// Stable per Venue: the same intent enqueued twice is the same command.
  final String idempotencyKey;

  /// How many times this command has been handed out, this delivery included.
  final int attempt;
  final DateTime issuedAt;

  /// After this instant Cloud may offer the command to an Edge again.
  final DateTime leaseExpiresAt;

  /// Whether this build understands the envelope well enough to execute it.
  bool get isSupportedVersion =>
      edgeCommandCompatibleVersions.contains(contractVersion);

  /// Parses one envelope, or throws [FormatException] on a malformed one.
  ///
  /// Deliberately strict about the fields the transport depends on: a command
  /// without an id or a type cannot be acknowledged, and silently defaulting
  /// either would lose work rather than report it.
  factory EdgeCommandEnvelope.fromJson(Map<String, dynamic> json) {
    final commandId = json['commandId'];
    final type = json['type'];
    if (commandId is! String || commandId.isEmpty) {
      throw const FormatException('Edge command is missing commandId');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('Edge command is missing type');
    }
    return EdgeCommandEnvelope(
      contractVersion: _asInt(json['contractVersion'], 0),
      commandId: commandId,
      type: type,
      payload: json['payload'],
      idempotencyKey: json['idempotencyKey'] is String
          ? json['idempotencyKey'] as String
          : '',
      attempt: _asInt(json['attempt'], 1),
      issuedAt: _asTime(json['issuedAt']),
      leaseExpiresAt: _asTime(json['leaseExpiresAt']),
    );
  }
}

/// What the Edge sends back once it has executed — or failed to execute — one.
class EdgeCommandResult {
  const EdgeCommandResult({
    required this.commandId,
    required this.status,
    this.code,
    this.detail,
  });

  const EdgeCommandResult.succeeded(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.succeeded;

  const EdgeCommandResult.failed(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.failed;

  final String commandId;
  final String status;

  /// Short machine-readable outcome, e.g. `printer_offline`.
  final String? code;
  final String? detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contractVersion': edgeCommandContractVersion,
    'commandId': commandId,
    'status': status,
    if (code != null) 'code': code,
    if (detail != null) 'detail': detail,
  };
}

int _asInt(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

DateTime _asTime(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
