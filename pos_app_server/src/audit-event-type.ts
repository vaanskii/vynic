/** Canonical audit event types stored in DB and sent to clients. */
export type CanonicalAuditEventType =
  | 'ADD_ITEM'
  | 'REDUCE_QTY'
  | 'DELETE_ITEM'
  | 'CANCEL_TABLE'
  | 'CUSTOM';

export function normalizeAuditEventType(
  raw: unknown,
  previousQty?: number,
  newQty?: number,
): CanonicalAuditEventType {
  const s = String(raw ?? '').trim();
  const u = s.toUpperCase().replace(/\s+/g, '_');
  const l = s.toLowerCase();

  if (u === 'ADD_ITEM' || u === 'ADD' || l === 'add_item') return 'ADD_ITEM';
  if (
    u === 'REDUCE_QTY' ||
    u === 'REDUCE_QUANTITY' ||
    l === 'reduce_quantity' ||
    l === 'reduce_qty'
  ) {
    return 'REDUCE_QTY';
  }
  if (
    u === 'DELETE_ITEM' ||
    u === 'REMOVE_ITEM' ||
    l === 'delete_item' ||
    l === 'remove_item'
  ) {
    return 'DELETE_ITEM';
  }
  if (u === 'CANCEL_TABLE' || l === 'cancel_table') return 'CANCEL_TABLE';

  const prev = Number(previousQty ?? 0);
  const next = Number(newQty ?? 0);
  if (next <= 0 && prev > 0) return 'DELETE_ITEM';
  if (next > 0 && next < prev) return 'REDUCE_QTY';
  if (next > prev) return 'ADD_ITEM';

  return 'CUSTOM';
}
