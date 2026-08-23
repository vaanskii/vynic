/** Mirrors pos_app_client reservation_table_availability.dart encoding. */

export function encodeTableCode(floor: string, tableNumber: string): number {
  const parsed = Number.parseInt(tableNumber.trim(), 10);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }
  if (floor === 'second') {
    return parsed + 10;
  }
  return parsed;
}

export function decodeTableCode(code: number): {
  floor: string;
  tableNumber: string;
} {
  if (code > 10) {
    return { floor: 'second', tableNumber: String(code - 10) };
  }
  return { floor: 'first', tableNumber: String(code) };
}

export function dateKeyFromString(date: string): string {
  const trimmed = date.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return trimmed;
  }
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid date: ${date}`);
  }
  const y = parsed.getFullYear();
  const m = String(parsed.getMonth() + 1).padStart(2, '0');
  const d = String(parsed.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function dayBounds(date: string): {
  start: Date;
  end: Date;
  dateKey: string;
} {
  const dateKey = dateKeyFromString(date);
  const [y, m, d] = dateKey.split('-').map(Number);
  return {
    dateKey,
    start: new Date(y, m - 1, d, 0, 0, 0, 0),
    end: new Date(y, m - 1, d, 23, 59, 59, 999),
  };
}

export function isReservationBlocking(
  status: string | null | undefined,
): boolean {
  const normalized = (status ?? '').trim().toLowerCase().replaceAll('_', '-');
  return (
    normalized !== 'cancelled' &&
    normalized !== 'canceled' &&
    normalized !== 'failed' &&
    normalized !== 'completed' &&
    !normalized.startsWith('cancelled') &&
    !normalized.startsWith('canceled') &&
    !normalized.startsWith('completed')
  );
}

export function isRealPosTableBooking(
  reservation: Record<string, unknown>,
): boolean {
  if (reservation.isTakeAway === true) return false;
  if (reservation.linkedOrderId != null) return false;
  const notes = String(reservation.notes ?? '').trim();
  if (notes.startsWith('Order #')) return false;
  return true;
}

export function reservationDateKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function unavailableCodesFromPosReservations(
  reservations: Array<Record<string, unknown>>,
  dateKey: string,
  excludeReservationId?: string,
): Set<number> {
  const unavailable = new Set<number>();
  for (const existing of reservations) {
    const id = String(existing.id ?? '').trim();
    if (excludeReservationId && id === excludeReservationId) continue;

    const reservationDate = String(existing.reservationDate ?? '');
    const normalizedDate =
      reservationDate.length >= 10
        ? reservationDate.slice(0, 10)
        : dateKeyFromString(reservationDate);
    if (normalizedDate !== dateKey) continue;

    if (!isReservationBlocking(String(existing.status ?? ''))) continue;
    if (!isRealPosTableBooking(existing)) continue;

    const tables = (existing.tableNumbers as unknown[]) ?? [];
    for (const raw of tables) {
      const code =
        typeof raw === 'number' ? raw : Number.parseInt(String(raw), 10);
      if (Number.isFinite(code) && code > 0) {
        unavailable.add(code);
      }
    }
  }
  return unavailable;
}
