/** Canonical audit event types stored in DB and sent to clients. */
export type CanonicalAuditEventType =
  | 'ADD_ITEM'
  | 'REDUCE_QTY'
  | 'DELETE_ITEM'
  | 'CLOSE'
  | 'INTERNAL_CLOSE'
  | 'RESTORE'
  | 'CANCEL_TABLE'
  | 'CREATE_WALKIN'
  | 'CREATE_TAKEAWAY'
  | 'APPLY_PACKAGE'
  | 'ACTIVATE_RESERVATION'
  | 'MOVE_ITEMS'
  | 'TRANSFER_CLOSE'
  | 'CUSTOM';

export function normalizeAuditEventType(
  raw: unknown,
  previousQty?: number,
  newQty?: number,
): CanonicalAuditEventType {
  const s = typeof raw === 'string' ? raw.trim() : '';
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
  if (u === 'CLOSE' || u === 'CLOSED') return 'CLOSE';
  if (
    u === 'INTERNAL_CLOSE' ||
    u === 'NON_FISCAL_CLOSE' ||
    u === 'NONFISCAL_CLOSE'
  ) {
    return 'INTERNAL_CLOSE';
  }
  if (
    u === 'RESTORE' ||
    u === 'RESTORED' ||
    u === 'REOPEN' ||
    u === 'REOPENED' ||
    u === 'SALE_RESTORED_TO_ORDER'
  ) {
    return 'RESTORE';
  }
  if (u === 'CANCEL_TABLE' || l === 'cancel_table') return 'CANCEL_TABLE';

  // Creation and lifecycle types. These must be recognised before the
  // quantity inference below: an older client that does not know them still
  // degrades to add/delete by quantity, but a backend that does must not.
  if (u === 'CREATE_WALKIN' || u === 'CREATE_WALK_IN') return 'CREATE_WALKIN';
  if (u === 'CREATE_TAKEAWAY' || u === 'CREATE_TAKE_AWAY') {
    return 'CREATE_TAKEAWAY';
  }
  if (u === 'APPLY_PACKAGE') return 'APPLY_PACKAGE';
  if (u === 'ACTIVATE_RESERVATION') return 'ACTIVATE_RESERVATION';
  if (u === 'MOVE_ITEMS' || u === 'MOVE_ITEM') return 'MOVE_ITEMS';
  if (u === 'TRANSFER_CLOSE' || u === 'EMPTIED_BY_TRANSFER') {
    return 'TRANSFER_CLOSE';
  }

  const prev = Number(previousQty ?? 0);
  const next = Number(newQty ?? 0);
  if (next <= 0 && prev > 0) return 'DELETE_ITEM';
  if (next > 0 && next < prev) return 'REDUCE_QTY';
  if (next > prev) return 'ADD_ITEM';

  return 'CUSTOM';
}
