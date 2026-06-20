/**
 * Suppresses POS → cloud → mobile notification echoes after a mobile manager mutation.
 * Mobile edits push to Windows; Windows syncs back — those round-trips should not
 * re-notify the device that originated the change.
 */

const DEFAULT_TTL_MS = 60_000;

const orderSuppressUntil = new Map<number, number>();
const tableSuppressUntil = new Map<string, number>();
const reservationSuppressUntil = new Map<string, number>();
let auditBroadcastSuppressUntil = 0;

function tableKey(tableNumber: string, floor: string): string {
  return `${tableNumber.trim()}_${floor.trim()}`;
}

function pruneExpired<K>(map: Map<K, number>, now: number): void {
  for (const [key, until] of map.entries()) {
    if (until <= now) map.delete(key);
  }
}

export function suppressPosEchoForOrder(
  posOrderId: number,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  if (!Number.isFinite(posOrderId)) return;
  orderSuppressUntil.set(posOrderId, Date.now() + ttlMs);
}

export function suppressPosEchoForTable(
  tableNumber: string,
  floor: string,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  const key = tableKey(tableNumber, floor);
  if (!key.replace('_', '').length) return;
  tableSuppressUntil.set(key, Date.now() + ttlMs);
}

export function suppressPosEchoForReservation(
  reservationId: string,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  const id = reservationId.trim();
  if (!id) return;
  reservationSuppressUntil.set(id, Date.now() + ttlMs);
}

export function isReservationEchoSuppressed(reservationId: string): boolean {
  const id = reservationId.trim();
  if (!id) return false;
  const now = Date.now();
  pruneExpired(reservationSuppressUntil, now);
  const until = reservationSuppressUntil.get(id);
  if (until === undefined) return false;
  if (until <= now) {
    reservationSuppressUntil.delete(id);
    return false;
  }
  return true;
}

/** After mobile save — POS audit bulk sync should not spam WS/audit tab. */
export function suppressPosAuditBroadcast(ttlMs: number = 15_000): void {
  auditBroadcastSuppressUntil = Date.now() + ttlMs;
}

export function isPosEchoSuppressed(posOrderId: number): boolean {
  const now = Date.now();
  pruneExpired(orderSuppressUntil, now);
  const until = orderSuppressUntil.get(posOrderId);
  if (until === undefined) return false;
  if (until <= now) {
    orderSuppressUntil.delete(posOrderId);
    return false;
  }
  return true;
}

export function isTableEchoSuppressed(
  tableNumber: string,
  floor: string,
): boolean {
  const now = Date.now();
  pruneExpired(tableSuppressUntil, now);
  const until = tableSuppressUntil.get(tableKey(tableNumber, floor));
  if (until === undefined) return false;
  if (until <= now) {
    tableSuppressUntil.delete(tableKey(tableNumber, floor));
    return false;
  }
  return true;
}

export function isPosAuditBroadcastSuppressed(): boolean {
  if (Date.now() > auditBroadcastSuppressUntil) {
    auditBroadcastSuppressUntil = 0;
    return false;
  }
  return true;
}

export function filterSuppressedOrderIds(ids: number[]): number[] {
  return ids.filter((id) => !isPosEchoSuppressed(id));
}
