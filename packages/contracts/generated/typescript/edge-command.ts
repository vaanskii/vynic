// GENERATED FILE — DO NOT EDIT.
//
// Rendered from packages/contracts/schema/edge-command.contract.json
// by packages/contracts/scripts/generate.mjs.
//
// Change the schema and regenerate; edits here are overwritten and
// CI fails on a stale or hand-edited output.

/**
 * The Cloud → Edge work contract.
 *
 * Cloud cannot reach a restaurant's LAN, so the Edge opens the connection with
 * its Device credential, claims work, executes it locally, and reports the
 * outcome. Delivery is at-least-once: a claim is a lease, and a lease that
 * expires unacknowledged is offered again. Every command type must therefore be
 * safe to execute twice, which is what `EDGE_IDEMPOTENT_COMMAND_TYPES` records.
 *
 * The version travels on every envelope so an Edge running an older build can
 * decline work it does not understand rather than guessing at it.
 */
export const EDGE_COMMAND_CONTRACT_VERSION = 2;

/** Batch size the Edge gets when it asks for none, and the ceiling it cannot exceed. */
export const EDGE_COMMAND_DEFAULT_BATCH_SIZE = 20;
export const EDGE_COMMAND_MAX_BATCH_SIZE = 50;

/** How long a claimed command stays leased before it becomes available again. */
export const EDGE_COMMAND_CLAIM_LEASE_SECONDS = 120;

/** Redeliveries before a command is given up on and recorded as failed. */
export const EDGE_COMMAND_MAX_ATTEMPTS = 10;

/**
 * Every envelope version an up-to-date Edge understands, newest first.
 *
 * A fleet does not upgrade all at once, so Cloud has to be able to serve the
 * version before this one while builds catch up. An Edge sends this list on
 * every claim and Cloud withholds anything outside it.
 */
export const EDGE_COMMAND_COMPATIBLE_VERSIONS: readonly number[] = [2, 1];

export const EdgeCommandTypes = {
  /**
   * Does nothing on the Edge. Exists so the transport can be exercised end to end without performing restaurant work.
   *
   * Idempotency: Nothing happens, so nothing can happen twice.
   *
   * Payload: none.
   */
  NOOP: 'NOOP',

  /**
   * Replace an existing order's lines, total and service-fee flag.
   *
   * Idempotency: Assignment, not adjustment: the payload is the order's new content, so a second delivery writes the same values. The audit diff is computed against what is stored, so a replay produces no events, and MoneyAudit already skips a service-fee entry when the flag did not move.
   *
   * Payload:
   * - `posOrderId`: int, the order's POS identity
   * - `updatedBy`: string?, who the Manager identified itself as
   * - `items`: array of {itemName, quantity, unitPrice, itemKey?, comment?}
   * - `totalAmount`: number?
   * - `includeServiceFee`: bool?
   *
   * Failure: order_not_found when no such order exists locally.
   */
  ORDER_UPDATE: 'ORDER_UPDATE',

  /**
   * Remove an order from the POS and release the tables it held.
   *
   * Idempotency: The goal state is 'this order is gone'. An order already absent satisfies it, so a redelivery succeeds rather than reporting a missing order.
   *
   * Payload:
   * - `posOrderId`: int
   */
  ORDER_CANCEL: 'ORDER_CANCEL',

  /**
   * Set an order's status.
   *
   * Idempotency: Assignment. The same status written twice is the same status.
   *
   * Payload:
   * - `posOrderId`: int
   * - `status`: string
   */
  ORDER_STATUS_UPDATE: 'ORDER_STATUS_UPDATE',

  /**
   * Create or update a takeaway order the Manager originated.
   *
   * Idempotency: Keyed on the Cloud-allocated posOrderId and written as an upsert, so a redelivery updates the one order. The kitchen check is sent only when the order did not already exist, so a replay does not reprint it.
   *
   * Payload:
   * - `posOrderId`: int, allocated by Cloud
   * - `customerName`: string
   * - `pickupTime`: string
   * - `waiterName`: string
   * - `businessDate`: string?, YYYY-MM-DD
   * - `items`: array of {itemName, quantity, unitPrice, comment?}
   * - `totalAmount`: number
   */
  TAKEAWAY_ORDER_UPSERT: 'TAKEAWAY_ORDER_UPSERT',

  /**
   * Create or update a walk-in dine-in order on one or more tables.
   *
   * Idempotency: Same as TAKEAWAY_ORDER_UPSERT: upsert on the Cloud-allocated posOrderId, kitchen check only on first arrival.
   *
   * Payload:
   * - `posOrderId`: int, allocated by Cloud
   * - `tableNumbers`: string[]
   * - `floor`: string
   * - `waiterName`: string
   * - `guestCount`: int
   * - `businessDate`: string?, YYYY-MM-DD
   * - `items`: array of {itemName, quantity, unitPrice, comment?}
   * - `totalAmount`: number
   */
  DINE_IN_ORDER_UPSERT: 'DINE_IN_ORDER_UPSERT',

  /**
   * Print an order's customer pre-bill on the POS receipt printer.
   *
   * Idempotency: Not naturally idempotent — paper is a side effect the world keeps. Safety comes from the local execution journal: a command already recorded as succeeded is acknowledged again without printing. A command interrupted mid-execution is NOT reprinted automatically, because the honest answer to 'did the paper come out' is unknown and a silent second check is worse than a reported failure.
   *
   * Payload:
   * - `posOrderId`: int
   *
   * Failure: order_not_found; printer failures surface from the local print service.
   *
   * Not repeated after an interrupted execution: the outcome is unknown and
   * repeating it would be worse than reporting it.
   */
  ORDER_CHECK_PRINT: 'ORDER_CHECK_PRINT',

  /**
   * Create a reservation the Manager or the public website originated.
   *
   * Idempotency: Cloud allocates reservationId, so the POS creates it only if that id is absent and returns the existing one otherwise. This is why the id moved to Cloud: a POS-generated id made a redelivery a second booking.
   *
   * Payload:
   * - `reservationId`: string, allocated by Cloud
   * - `customerName`: string
   * - `customerPhone`: string
   * - `tableNumbers`: int[], legacy reservation table codes
   * - `reservationDate`: string, ISO date
   * - `reservationTime`: string, HH:mm
   * - `numberOfGuests`: int
   * - `notes`: string?
   * - `createdBy`: string
   * - `status`: string
   * - `isTakeAway`: bool
   * - `preOrderItems`: array of order items
   */
  RESERVATION_CREATE: 'RESERVATION_CREATE',

  /**
   * Set a reservation's status.
   *
   * Idempotency: Assignment.
   *
   * Payload:
   * - `reservationId`: string
   * - `status`: string
   */
  RESERVATION_STATUS_UPDATE: 'RESERVATION_STATUS_UPDATE',

  /**
   * Remove a reservation from the POS.
   *
   * Idempotency: The goal state is 'this reservation is gone'; already absent satisfies it.
   *
   * Payload:
   * - `reservationId`: string
   */
  RESERVATION_DELETE: 'RESERVATION_DELETE',

  /**
   * Print a reservation's kitchen check on the POS kitchen printer.
   *
   * Idempotency: Journal-guarded, exactly as ORDER_CHECK_PRINT. An interrupted print is not repeated automatically.
   *
   * Payload:
   * - `reservationId`: string
   * - `requestedBy`: string?
   *
   * Failure: reservation_not_found.
   *
   * Not repeated after an interrupted execution: the outcome is unknown and
   * repeating it would be worse than reporting it.
   */
  RESERVATION_CHECK_PRINT: 'RESERVATION_CHECK_PRINT',

  /**
   * Print a counted-menu draft on the POS receipt printer from the payload itself.
   *
   * Idempotency: Journal-guarded, exactly as ORDER_CHECK_PRINT. The draft lives in Cloud rather than POS Hive, which is why the whole thing travels in the payload.
   *
   * Payload:
   * - `displayName`: string?
   * - `items`: array of {itemName, quantity, unitPrice, total?, comment?}
   * - `subtotal`: number
   * - `serviceFeeAmount`: number
   * - `total`: number
   * - `includeServiceFee`: bool
   * - `language`: string?, ka|en
   *
   * Not repeated after an interrupted execution: the outcome is unknown and
   * repeating it would be worse than reporting it.
   */
  COUNTED_MENU_PRINT: 'COUNTED_MENU_PRINT',

  /**
   * Record an expense the Manager entered.
   *
   * Idempotency: Cloud allocates the expense id and the POS upserts on it, so a redelivery updates the one record instead of adding a second.
   *
   * Payload:
   * - `id`: string, allocated by Cloud
   * - `description`: string
   * - `amount`: number
   * - `category`: string
   * - `paymentType`: string
   * - `createdAt`: string?, ISO
   * - `businessDate`: string?, YYYY-MM-DD
   */
  EXPENSE_CREATE: 'EXPENSE_CREATE',

  /**
   * Add a staff user to the POS.
   *
   * Idempotency: The goal state is 'this username exists with this role and PIN'. Cloud has already refused a duplicate username before enqueueing, so a username that exists locally means the command has landed before; the handler reconciles the role and PIN and succeeds.
   *
   * Payload:
   * - `username`: string
   * - `pinCode`: string
   * - `role`: string
   */
  STAFF_CREATE: 'STAFF_CREATE',

  /**
   * Set a staff user's PIN.
   *
   * Idempotency: Assignment. The same PIN written twice is the same PIN.
   *
   * Payload:
   * - `username`: string
   * - `pinCode`: string
   */
  STAFF_PIN_UPDATE: 'STAFF_PIN_UPDATE',

  /**
   * Set a staff user's role.
   *
   * Idempotency: Assignment.
   *
   * Payload:
   * - `username`: string
   * - `role`: string
   */
  STAFF_ROLE_UPDATE: 'STAFF_ROLE_UPDATE',

  /**
   * Rename a staff user.
   *
   * Idempotency: The goal state is 'newUsername exists and oldUsername does not'. A redelivery finds exactly that and succeeds without touching anything.
   *
   * Payload:
   * - `oldUsername`: string
   * - `newUsername`: string
   */
  STAFF_RENAME: 'STAFF_RENAME',

  /**
   * Remove a staff user from the POS.
   *
   * Idempotency: The goal state is 'this username is gone'; already absent satisfies it.
   *
   * Payload:
   * - `username`: string
   */
  STAFF_DELETE: 'STAFF_DELETE',
} as const;

export type EdgeCommandType =
  | 'NOOP'
  | 'ORDER_UPDATE'
  | 'ORDER_CANCEL'
  | 'ORDER_STATUS_UPDATE'
  | 'TAKEAWAY_ORDER_UPSERT'
  | 'DINE_IN_ORDER_UPSERT'
  | 'ORDER_CHECK_PRINT'
  | 'RESERVATION_CREATE'
  | 'RESERVATION_STATUS_UPDATE'
  | 'RESERVATION_DELETE'
  | 'RESERVATION_CHECK_PRINT'
  | 'COUNTED_MENU_PRINT'
  | 'EXPENSE_CREATE'
  | 'STAFF_CREATE'
  | 'STAFF_PIN_UPDATE'
  | 'STAFF_ROLE_UPDATE'
  | 'STAFF_RENAME'
  | 'STAFF_DELETE';

/**
 * Command types that may be executed more than once without extra effect.
 *
 * A type absent from this set must not be enqueued until its Edge handler
 * carries its own idempotency, because at-least-once delivery will eventually
 * hand it over twice.
 */
export const EDGE_IDEMPOTENT_COMMAND_TYPES: ReadonlySet<string> = new Set([
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
]);

/**
 * Types whose Edge handler must NOT re-run after an interrupted execution.
 *
 * These are the ones whose side effect leaves the machine — paper, mostly. A
 * command the POS started and never finished has an unknown outcome, and
 * quietly doing it again is worse than reporting that nobody knows.
 */
export const EDGE_NO_REPEAT_AFTER_INTERRUPTION: ReadonlySet<string> = new Set([
  'ORDER_CHECK_PRINT',
  'RESERVATION_CHECK_PRINT',
  'COUNTED_MENU_PRINT',
]);

export type EdgeCommandResultStatus = 'SUCCEEDED' | 'FAILED';

/** One unit of work, as the Edge receives it. */
export interface EdgeCommandEnvelope {
  contractVersion: number;
  commandId: string;
  type: string;
  payload: unknown;
  /** Stable per Venue: the same intent enqueued twice is the same command. */
  idempotencyKey: string;
  /** How many times this command has been handed out, this delivery included. */
  attempt: number;
  issuedAt: string;
  /** After this instant the command may be offered to an Edge again. */
  leaseExpiresAt: string;
}

/** What the Edge reports back once it has executed — or failed to execute — a command. */
export interface EdgeCommandResult {
  contractVersion: number;
  commandId: string;
  status: EdgeCommandResultStatus;
  /** Short machine-readable outcome, e.g. `printer_offline`. */
  code?: string | null;
  detail?: string | null;
}
