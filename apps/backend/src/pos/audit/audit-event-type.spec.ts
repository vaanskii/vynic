import { normalizeAuditEventType } from './audit-event-type';

describe('normalizeAuditEventType', () => {
  it.each([
    ['CLOSE', 'CLOSE'],
    ['closed', 'CLOSE'],
    ['INTERNAL_CLOSE', 'INTERNAL_CLOSE'],
    ['non fiscal close', 'INTERNAL_CLOSE'],
    ['NONFISCAL_CLOSE', 'INTERNAL_CLOSE'],
    ['RESTORE', 'RESTORE'],
    ['reopened', 'RESTORE'],
    ['SALE_RESTORED_TO_ORDER', 'RESTORE'],
    ['CANCEL_TABLE', 'CANCEL_TABLE'],
    ['CREATE_WALKIN', 'CREATE_WALKIN'],
    ['create_walk_in', 'CREATE_WALKIN'],
    ['CREATE_TAKEAWAY', 'CREATE_TAKEAWAY'],
    ['APPLY_PACKAGE', 'APPLY_PACKAGE'],
    ['ACTIVATE_RESERVATION', 'ACTIVATE_RESERVATION'],
    ['MOVE_ITEMS', 'MOVE_ITEMS'],
    ['TRANSFER_CLOSE', 'TRANSFER_CLOSE'],
  ])(
    'normalizes %s without conflating closure and cancellation',
    (raw, expected) => {
      expect(normalizeAuditEventType(raw)).toBe(expected);
    },
  );

  it('keeps a typed move as a move, not an add or delete by quantity', () => {
    // MOVE_ITEMS carries quantities on both sides; only an unknown type may
    // fall through to the quantity inference.
    expect(normalizeAuditEventType('MOVE_ITEMS', 0, 3)).toBe('MOVE_ITEMS');
    expect(normalizeAuditEventType('MOVE_ITEMS', 3, 0)).toBe('MOVE_ITEMS');
    expect(normalizeAuditEventType('SOMETHING_NEW', 0, 3)).toBe('ADD_ITEM');
  });

  it('stores a creation event as itself rather than CUSTOM', () => {
    expect(normalizeAuditEventType('CREATE_WALKIN', 0, 0)).toBe(
      'CREATE_WALKIN',
    );
    expect(normalizeAuditEventType('CREATE_TAKEAWAY', 0, 0)).toBe(
      'CREATE_TAKEAWAY',
    );
  });
});
