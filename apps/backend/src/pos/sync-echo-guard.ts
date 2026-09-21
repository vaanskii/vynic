import type { TenantContext } from '../tenancy/tenant-context';
/**
 * Suppresses POS → cloud → mobile notification echoes after a mobile manager mutation.
 * Mobile edits push to Windows; Windows syncs back — those round-trips should not
 * re-notify the device that originated the change.
 */

const DEFAULT_TTL_MS = 60_000;

const orderSuppressUntil = new Map<string, number>();
const tableSuppressUntil = new Map<string, number>();
const reservationSuppressUntil = new Map<string, number>();
const auditBroadcastSuppressUntil = new Map<string, number>();

function tableKey(tableNumber: string, floor: string): string {
  return `${tableNumber.trim()}_${floor.trim()}`;
}

function pruneExpired<K>(map: Map<K, number>, now: number): void {
  for (const [key, until] of map.entries()) {
    if (until <= now) map.delete(key);
  }
}

export function suppressPosEchoForOrder(
  tenant: Pick<TenantContext, 'venueId'>,
  posOrderId: number,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  if (!Number.isFinite(posOrderId)) return;
  orderSuppressUntil.set(`${tenant.venueId}:${posOrderId}`, Date.now() + ttlMs);
}

export function suppressPosEchoForTable(
  tenant: Pick<TenantContext, 'venueId'>,
  tableNumber: string,
  floor: string,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  const key = `${tenant.venueId}:${tableKey(tableNumber, floor)}`;
  if (!tableKey(tableNumber, floor).replace('_', '').length) return;
  tableSuppressUntil.set(key, Date.now() + ttlMs);
}

export function suppressPosEchoForReservation(
  tenant: Pick<TenantContext, 'venueId'>,
  reservationId: string,
  ttlMs: number = DEFAULT_TTL_MS,
): void {
  const id = `${tenant.venueId}:${reservationId.trim()}`;
  if (!reservationId.trim()) return;
  reservationSuppressUntil.set(id, Date.now() + ttlMs);
}

export function isReservationEchoSuppressed(
  tenant: Pick<TenantContext, 'venueId'>,
  reservationId: string,
): boolean {
  const id = `${tenant.venueId}:${reservationId.trim()}`;
  if (!reservationId.trim()) return false;
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
export function suppressPosAuditBroadcast(
  tenant: Pick<TenantContext, 'venueId'>,
  ttlMs: number = 15_000,
): void {
  auditBroadcastSuppressUntil.set(tenant.venueId, Date.now() + ttlMs);
}

export function isPosEchoSuppressed(
  tenant: Pick<TenantContext, 'venueId'>,
  posOrderId: number,
): boolean {
  const now = Date.now();
  pruneExpired(orderSuppressUntil, now);
  const until = orderSuppressUntil.get(`${tenant.venueId}:${posOrderId}`);
  if (until === undefined) return false;
  if (until <= now) {
    orderSuppressUntil.delete(`${tenant.venueId}:${posOrderId}`);
    return false;
  }
  return true;
}

export function isTableEchoSuppressed(
  tenant: Pick<TenantContext, 'venueId'>,
  tableNumber: string,
  floor: string,
): boolean {
  const now = Date.now();
  pruneExpired(tableSuppressUntil, now);
  const until = tableSuppressUntil.get(
    `${tenant.venueId}:${tableKey(tableNumber, floor)}`,
  );
  if (until === undefined) return false;
  if (until <= now) {
    tableSuppressUntil.delete(
      `${tenant.venueId}:${tableKey(tableNumber, floor)}`,
    );
    return false;
  }
  return true;
}

export function isPosAuditBroadcastSuppressed(
  tenant: Pick<TenantContext, 'venueId'>,
): boolean {
  pruneExpired(auditBroadcastSuppressUntil, Date.now());
  return auditBroadcastSuppressUntil.has(tenant.venueId);
}

export function filterSuppressedOrderIds(
  tenant: Pick<TenantContext, 'venueId'>,
  ids: number[],
): number[] {
  return ids.filter((id) => !isPosEchoSuppressed(tenant, id));
}
