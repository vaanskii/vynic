// GENERATED FILE — DO NOT EDIT.
//
// Rendered from packages/contracts/schema/table-identity.contract.json
// by packages/contracts/scripts/generate.mjs.
//
// Change the schema and regenerate; edits here are overwritten and
// CI fails on a stale or hand-edited output.

/**
 * Table identity: the canonical `encodeTableRef` form and the transitional
 * integer `encodeTableCode` encoding shared with pos_app_client.
 */

export const TABLE_IDENTITY_CONTRACT_VERSION = 1;

/** Separator between the floor key and the table number in a table ref. */
export const TABLE_REF_SEPARATOR = '/';

interface Floor {
  key: string;
  offset: number;
  maxTableNumber: number | null;
}

const FLOORS: readonly Floor[] = [
  { key: 'first', offset: 0, maxTableNumber: 10 },
  { key: 'second', offset: 10, maxTableNumber: null },
];

const MIN_TABLE_NUMBER = 1;

function floorByKey(key: string): Floor | undefined {
  return FLOORS.find((floor) => floor.key === key);
}

/**
 * The parsed table number, or null when `raw` is not a whole number at or
 * above the minimum. Matches Dart's int.tryParse: an optional sign followed
 * by digits and nothing else, so "5abc" is rejected rather than read as 5.
 */
function parseTableNumber(raw: string): number | null {
  const trimmed = raw.trim();
  if (!/^[+-]?\d+$/.test(trimmed)) return null;
  const parsed = Number.parseInt(trimmed, 10);
  if (!Number.isFinite(parsed) || parsed < MIN_TABLE_NUMBER) return null;
  return parsed;
}

/**
 * Whether `floor` and `tableNumber` can be represented as a legacy code.
 *
 * Pickers must hide tables that fail this check rather than offering them,
 * because `encodeTableCode` throws for exactly the same inputs.
 */
export function canEncodeTableCode(
  floor: string,
  tableNumber: string,
): boolean {
  const parsed = parseTableNumber(tableNumber);
  if (parsed === null) return false;
  const target = floorByKey(floor);
  if (!target) return false;
  return target.maxTableNumber === null || parsed <= target.maxTableNumber;
}

/**
 * Encodes `floor` and `tableNumber` into the legacy integer code.
 *
 * Throws rather than returning a code that would decode as a different table.
 */
export function encodeTableCode(floor: string, tableNumber: string): number {
  const parsed = parseTableNumber(tableNumber);
  if (parsed === null) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }
  const target = floorByKey(floor);
  if (!target) {
    throw new Error(
      `Floor "${floor}" cannot be encoded as a reservation table code; ` +
        `only ${FLOORS.map((f) => f.key).join('/')} are supported`,
    );
  }
  if (target.maxTableNumber !== null && parsed > target.maxTableNumber) {
    throw new Error(
      `Table ${parsed} on the ${floor} floor cannot be encoded as a ` +
        `reservation table code (would decode as another floor's table)`,
    );
  }
  return parsed + target.offset;
}

/**
 * Decodes a legacy integer code back into a floor and table number.
 *
 * Total by design: it validates nothing, so every code — including ones
 * `encodeTableCode` would never produce — maps somewhere, exactly as the
 * hand-written implementations did.
 */
export function decodeTableCode(code: number): {
  floor: string;
  tableNumber: string;
} {
  if (code > 10) {
    return { floor: 'second', tableNumber: String(code - 10) };
  }
  return { floor: 'first', tableNumber: String(code - 0) };
}

/** The canonical, lossless reference: `floor${TABLE_REF_SEPARATOR}tableNumber`. */
export function encodeTableRef(floor: string, tableNumber: string): string {
  return `${floor}${TABLE_REF_SEPARATOR}${tableNumber}`;
}

/**
 * Parses `raw` back into a floor and table number, or null when malformed.
 *
 * Splits on the FIRST separator only: floor keys never contain it, so any
 * later occurrence belongs to the table number.
 */
export function tryDecodeTableRef(
  raw: string,
): { floor: string; tableNumber: string } | null {
  const separator = raw.indexOf(TABLE_REF_SEPARATOR);
  if (separator <= 0 || separator >= raw.length - 1) {
    return null;
  }
  const floor = raw.slice(0, separator).trim();
  const tableNumber = raw.slice(separator + 1).trim();
  if (floor.length === 0 || tableNumber.length === 0) {
    return null;
  }
  return { floor, tableNumber };
}
