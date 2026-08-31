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
export const EDGE_COMMAND_CONTRACT_VERSION = 1;

/** Batch size the Edge gets when it asks for none, and the ceiling it cannot exceed. */
export const EDGE_COMMAND_DEFAULT_BATCH_SIZE = 20;
export const EDGE_COMMAND_MAX_BATCH_SIZE = 50;

/** How long a claimed command stays leased before it becomes available again. */
export const EDGE_COMMAND_CLAIM_LEASE_SECONDS = 120;

/** Redeliveries before a command is given up on and recorded as failed. */
export const EDGE_COMMAND_MAX_ATTEMPTS = 10;

export const EdgeCommandTypes = {
  /** Does nothing on the Edge. Exists so the transport can be exercised end to end without performing restaurant work. */
  NOOP: 'NOOP',
} as const;

export type EdgeCommandType = 'NOOP';

/**
 * Command types that may be executed more than once without extra effect.
 *
 * A type absent from this set must not be enqueued until its Edge handler
 * carries its own idempotency, because at-least-once delivery will eventually
 * hand it over twice.
 */
export const EDGE_IDEMPOTENT_COMMAND_TYPES: ReadonlySet<string> = new Set([
  'NOOP',
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
