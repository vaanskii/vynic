import {
  actionsForEntityType,
  deriveAuditLogEntity,
  isAuditLogEntityType,
} from './audit-log-entity';

/**
 * Classifying a venue-wide audit row from its action name.
 *
 * This is the path taken for a row written before `entityType` existed and for
 * an older POS build that does not send one. It has to be derivation rather
 * than guessing: an unknown action is honestly unclassified, not filed under
 * whatever looks close.
 */
describe('deriveAuditLogEntity', () => {
  it('classifies each domain by its action and its own identity key', () => {
    expect(
      deriveAuditLogEntity('STAFF_ROLE_CHANGED', { staffName: 'Nika' }),
    ).toEqual({ entityType: 'STAFF', entityId: 'Nika' });
    expect(
      deriveAuditLogEntity('MENU_ITEM_UPDATED', {
        itemId: 'hot/Khinkali',
        itemName: 'ხინკალი',
      }),
    ).toEqual({ entityType: 'MENU_ITEM', entityId: 'hot/Khinkali' });
    expect(
      deriveAuditLogEntity('PACKAGE_UPDATED', { packageId: 'pkg-1' }),
    ).toEqual({ entityType: 'PACKAGE', entityId: 'pkg-1' });
    expect(
      deriveAuditLogEntity('STOCK_ITEM_UPDATED', { stockItemId: 'stock-1' }),
    ).toEqual({ entityType: 'STOCK_ITEM', entityId: 'stock-1' });
    expect(
      deriveAuditLogEntity('SUPPLIER_DISABLED', { supplierId: 'supplier-1' }),
    ).toEqual({ entityType: 'SUPPLIER', entityId: 'supplier-1' });
    expect(
      deriveAuditLogEntity('RECEIVING_POSTED', {
        receivingId: 'r-1',
        waybillNumber: '12345',
      }),
    ).toEqual({ entityType: 'RECEIVING', entityId: 'r-1' });
    expect(
      deriveAuditLogEntity('RECIPE_UPDATED', {
        recipeId: 'rec-1',
        menuItemId: 'menu-1',
      }),
    ).toEqual({ entityType: 'RECIPE', entityId: 'rec-1' });
    expect(
      deriveAuditLogEntity('EXPENSE_CREATED', { expenseId: 'exp-9' }),
    ).toEqual({ entityType: 'EXPENSE', entityId: 'exp-9' });
    expect(
      deriveAuditLogEntity('CLOSE_DAY_COMPLETED', {
        businessDateClosed: '2026-09-05',
      }),
    ).toEqual({ entityType: 'CLOSE_DAY', entityId: '2026-09-05' });
    expect(
      deriveAuditLogEntity('BACKUP_RESTORED', {
        backupCreatedAt: '2026-09-01T10:00:00.000Z',
      }),
    ).toEqual({ entityType: 'BACKUP', entityId: '2026-09-01T10:00:00.000Z' });
  });

  it('reads an Order id that was stored as a number', () => {
    expect(deriveAuditLogEntity('ORDER_CREATED', { orderId: 42 })).toEqual({
      entityType: 'ORDER',
      entityId: '42',
    });
  });

  it('prefers the sale identity over the closure and the order', () => {
    expect(
      deriveAuditLogEntity('SALE_CANCELLED', {
        saleId: 'sale-1',
        closureId: 'clo-1',
        orderId: 7,
      }),
    ).toEqual({ entityType: 'SALE', entityId: 'sale-1' });
    // And falls through when the earlier keys are absent, rather than giving up.
    expect(deriveAuditLogEntity('SALE_CANCELLED', { orderId: 7 })).toEqual({
      entityType: 'SALE',
      entityId: '7',
    });
  });

  it('classifies the legacy lowercase reservation action', () => {
    expect(
      deriveAuditLogEntity('reservation_cancelled', { reservationId: 'r-1' }),
    ).toEqual({ entityType: 'RESERVATION', entityId: 'r-1' });
  });

  it('classifies namespaced developer actions without inventing a subject', () => {
    expect(deriveAuditLogEntity('developer.recovery.pinReset', {})).toEqual({
      entityType: 'DEVELOPER',
      entityId: null,
    });
  });

  it('gives a settings policy change a fixed subject', () => {
    expect(
      deriveAuditLogEntity('RECEIPT_SERVICE_FEE_POLICY_CHANGED', {}),
    ).toEqual({ entityType: 'SETTINGS', entityId: 'receiptServiceFeePolicy' });
  });

  it('keeps the type when the details carry no identity', () => {
    expect(deriveAuditLogEntity('STAFF_CREATED', {})).toEqual({
      entityType: 'STAFF',
      entityId: null,
    });
  });

  it('refuses to classify an action it does not know', () => {
    expect(deriveAuditLogEntity('SOMETHING_ELSE', { orderId: 1 })).toEqual({
      entityType: null,
      entityId: null,
    });
    expect(deriveAuditLogEntity('', {})).toEqual({
      entityType: null,
      entityId: null,
    });
    expect(deriveAuditLogEntity(null, null)).toEqual({
      entityType: null,
      entityId: null,
    });
  });

  it('tolerates details that are not an object', () => {
    expect(deriveAuditLogEntity('ORDER_CREATED', 'not-json')).toEqual({
      entityType: 'ORDER',
      entityId: null,
    });
  });
});

describe('actionsForEntityType', () => {
  it('lists every action that means an entity, so history is still findable', () => {
    expect(actionsForEntityType('STAFF').sort()).toEqual([
      'STAFF_COMPENSATION_CHANGED',
      'STAFF_CREATED',
      'STAFF_DELETED',
      'STAFF_PIN_CHANGED',
      'STAFF_ROLE_CHANGED',
      'STAFF_UPDATED',
    ]);
    // Including the one name history stored in lower case.
    expect(actionsForEntityType('RESERVATION')).toContain(
      'reservation_cancelled',
    );
  });

  it('round-trips: every listed action derives back to its entity type', () => {
    for (const entityType of [
      'ORDER',
      'SALE',
      'MENU_ITEM',
      'PACKAGE',
      'STOCK_ITEM',
      'SUPPLIER',
      'RECEIVING',
      'RECIPE',
    ] as const) {
      for (const action of actionsForEntityType(entityType)) {
        expect(deriveAuditLogEntity(action, {}).entityType).toBe(entityType);
      }
    }
  });
});

describe('isAuditLogEntityType', () => {
  it('accepts a canonical name in any case and rejects anything else', () => {
    expect(isAuditLogEntityType('STAFF')).toBe(true);
    expect(isAuditLogEntityType('staff')).toBe(true);
    expect(isAuditLogEntityType('TABLE')).toBe(false);
    expect(isAuditLogEntityType(null)).toBe(false);
    expect(isAuditLogEntityType(7)).toBe(false);
  });
});
