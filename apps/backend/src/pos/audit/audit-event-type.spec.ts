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
  ])(
    'normalizes %s without conflating closure and cancellation',
    (raw, expected) => {
      expect(normalizeAuditEventType(raw)).toBe(expected);
    },
  );
});
