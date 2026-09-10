/**
 * What a venue-wide audit row is about.
 *
 * `AuditEventLog` is the generic half of the audit system: an Order has its own
 * report with an ordered timeline, and everything else a restaurant does to
 * itself lands here. `entityType`/`entityId` say which thing a row concerns, so
 * "who changed this menu price" is answerable without parsing `data`.
 *
 * The POS writes those columns itself. This module exists for the two cases
 * where it did not: a row written before the columns existed, and an older POS
 * build that does not send them. In both, the entity is *derived* from the
 * action name — derivation, not guessing: an action this table does not know
 * resolves to no entity rather than to a plausible one.
 *
 * Kept in step with `apps/operations/lib/core/services/audit/global_audit.dart`
 * and its registry; the action names are the shared contract.
 */

export const AUDIT_LOG_ENTITY_TYPES = [
  'STAFF',
  'PAYROLL_PAYMENT',
  'PAYROLL_PERIOD',
  'FINANCIAL_OBLIGATION',
  'OBLIGATION_CYCLE',
  'MENU_ITEM',
  'MENU_CATEGORY',
  'MENU_VARIANT',
  'STOCK_ITEM',
  'SUPPLIER',
  'RECEIVING',
  'RECIPE',
  'PACKAGE',
  'EXPENSE',
  'CLOSE_DAY',
  'BACKUP',
  'RESERVATION',
  'ORDER',
  'SALE',
  'BUSINESS_DATE',
  'SETTINGS',
  'DEVELOPER',
] as const;

export type AuditLogEntityType = (typeof AUDIT_LOG_ENTITY_TYPES)[number];

export function isAuditLogEntityType(raw: unknown): raw is AuditLogEntityType {
  return (
    typeof raw === 'string' &&
    (AUDIT_LOG_ENTITY_TYPES as readonly string[]).includes(raw.toUpperCase())
  );
}

/**
 * Which keys of `data` carry the subject's identity, in preference order.
 * The first one present and non-empty wins.
 */
type EntityRule = {
  entityType: AuditLogEntityType;
  idKeys: readonly string[];
  /** A fixed id for an action whose subject is the setting itself. */
  fixedId?: string;
};

const RESERVATION_RULE: EntityRule = {
  entityType: 'RESERVATION',
  idKeys: ['reservationId'],
};

const ACTION_RULES: Readonly<Record<string, EntityRule>> = {
  // Reservations. The lowercase legacy name is normalized before lookup.
  CREATE_RESERVATION: RESERVATION_RULE,
  UPDATE_RESERVATION: RESERVATION_RULE,
  CONFIRM_RESERVATION: RESERVATION_RULE,
  CANCEL_RESERVATION: RESERVATION_RULE,
  NO_SHOW_RESERVATION: RESERVATION_RULE,
  COMPLETE_RESERVATION: RESERVATION_RULE,
  DELETE_RESERVATION: RESERVATION_RULE,

  // Orders.
  ORDER_CREATED: { entityType: 'ORDER', idKeys: ['orderId'] },
  TAKEAWAY_ORDER_CREATED: { entityType: 'ORDER', idKeys: ['orderId'] },
  ORDER_HARD_DELETED: { entityType: 'ORDER', idKeys: ['orderId'] },
  ORDER_DISCOUNT_CHANGED: { entityType: 'ORDER', idKeys: ['orderId'] },
  ORDER_MANUAL_ADJUSTMENT_CHANGED: {
    entityType: 'ORDER',
    idKeys: ['orderId'],
  },
  ORDER_SERVICE_FEE_CHANGED: { entityType: 'ORDER', idKeys: ['orderId'] },
  ADVANCE_RECORDED: { entityType: 'ORDER', idKeys: ['orderId'] },
  SALE_RESTORED_TO_ORDER: { entityType: 'ORDER', idKeys: ['orderId'] },

  // Sales and closures.
  SALE_CANCELLED: {
    entityType: 'SALE',
    idKeys: ['saleId', 'closureId', 'orderId'],
  },
  CLOSURE_RECOVERED: { entityType: 'SALE', idKeys: ['closureId'] },

  // Settings and the business date.
  BUSINESS_DATE_CHANGED: { entityType: 'BUSINESS_DATE', idKeys: ['newDate'] },
  RECEIPT_SERVICE_FEE_POLICY_CHANGED: {
    entityType: 'SETTINGS',
    idKeys: [],
    fixedId: 'receiptServiceFeePolicy',
  },
  REPORT_COST_ASSUMPTION_CHANGED: { entityType: 'SETTINGS', idKeys: ['field'] },

  STAFF_COMPENSATION_CHANGED: { entityType: 'STAFF', idKeys: ['staffId'] },
  PAYROLL_PAYMENT_RECORDED: {
    entityType: 'PAYROLL_PAYMENT',
    idKeys: ['paymentId'],
  },
  PAYROLL_DAY_REVERSED: { entityType: 'PAYROLL_PERIOD', idKeys: ['periodId'] },
  PAYROLL_ACCRUAL_RECORDED: {
    entityType: 'PAYROLL_PERIOD',
    idKeys: ['periodId'],
  },
  FINANCIAL_OBLIGATION_CREATED: {
    entityType: 'FINANCIAL_OBLIGATION',
    idKeys: ['obligationId'],
  },
  FINANCIAL_OBLIGATION_UPDATED: {
    entityType: 'FINANCIAL_OBLIGATION',
    idKeys: ['obligationId'],
  },
  FINANCIAL_OBLIGATION_DISABLED: {
    entityType: 'FINANCIAL_OBLIGATION',
    idKeys: ['obligationId'],
  },
  OBLIGATION_RESERVE_RECORDED: {
    entityType: 'OBLIGATION_CYCLE',
    idKeys: ['cycleId'],
  },
  OBLIGATION_PAYMENT_RECORDED: {
    entityType: 'OBLIGATION_CYCLE',
    idKeys: ['cycleId'],
  },
  // Staff.
  STAFF_CREATED: { entityType: 'STAFF', idKeys: ['staffName'] },
  STAFF_UPDATED: { entityType: 'STAFF', idKeys: ['staffName'] },
  STAFF_ROLE_CHANGED: { entityType: 'STAFF', idKeys: ['staffName'] },
  STAFF_PIN_CHANGED: { entityType: 'STAFF', idKeys: ['staffName'] },
  STAFF_DELETED: { entityType: 'STAFF', idKeys: ['staffName'] },

  // Menu.
  MENU_ITEM_CREATED: {
    entityType: 'MENU_ITEM',
    idKeys: ['itemId', 'itemName'],
  },
  MENU_ITEM_UPDATED: {
    entityType: 'MENU_ITEM',
    idKeys: ['itemId', 'itemName'],
  },
  MENU_ITEM_DELETED: {
    entityType: 'MENU_ITEM',
    idKeys: ['itemId', 'itemName'],
  },
  MENU_CATEGORY_CREATED: {
    entityType: 'MENU_CATEGORY',
    idKeys: ['categoryName'],
  },
  MENU_CATEGORY_UPDATED: {
    entityType: 'MENU_CATEGORY',
    idKeys: ['categoryName'],
  },
  MENU_CATEGORY_DELETED: {
    entityType: 'MENU_CATEGORY',
    idKeys: ['categoryName'],
  },
  MENU_VARIANT_CREATED: {
    entityType: 'MENU_VARIANT',
    idKeys: ['variantId'],
  },
  MENU_VARIANT_UPDATED: {
    entityType: 'MENU_VARIANT',
    idKeys: ['variantId'],
  },
  MENU_VARIANT_DELETED: {
    entityType: 'MENU_VARIANT',
    idKeys: ['variantId'],
  },

  STOCK_ITEM_CREATED: {
    entityType: 'STOCK_ITEM',
    idKeys: ['stockItemId'],
  },
  STOCK_ITEM_UPDATED: {
    entityType: 'STOCK_ITEM',
    idKeys: ['stockItemId'],
  },
  STOCK_ITEM_DISABLED: {
    entityType: 'STOCK_ITEM',
    idKeys: ['stockItemId'],
  },

  STOCK_ITEM_SUPPLIERS_UPDATED: {
    entityType: 'STOCK_ITEM',
    idKeys: ['stockItemId'],
  },
  SUPPLIER_PRODUCT_LINKED: { entityType: 'SUPPLIER', idKeys: ['supplierId'] },
  SUPPLIER_PRODUCT_UNLINKED: { entityType: 'SUPPLIER', idKeys: ['supplierId'] },
  SUPPLIER_CREATED: { entityType: 'SUPPLIER', idKeys: ['supplierId'] },
  SUPPLIER_UPDATED: { entityType: 'SUPPLIER', idKeys: ['supplierId'] },
  SUPPLIER_DISABLED: { entityType: 'SUPPLIER', idKeys: ['supplierId'] },

  // Receiving documents. The movements they produce are already durable
  // ledger history and are summarised here rather than mirrored row by row.
  RECEIVING_CREATED: { entityType: 'RECEIVING', idKeys: ['receivingId'] },
  RECEIVING_UPDATED: { entityType: 'RECEIVING', idKeys: ['receivingId'] },
  RECEIVING_POSTED: { entityType: 'RECEIVING', idKeys: ['receivingId'] },
  RECEIVING_CANCELLED: { entityType: 'RECEIVING', idKeys: ['receivingId'] },

  // Menu consumption definitions. The row summarises the card rather than
  // carrying it: the components are readable at the recipe itself.
  RECIPE_CREATED: { entityType: 'RECIPE', idKeys: ['recipeId'] },
  RECIPE_UPDATED: { entityType: 'RECIPE', idKeys: ['recipeId'] },
  RECIPE_DISABLED: { entityType: 'RECIPE', idKeys: ['recipeId'] },

  // Package definitions. Applying a package to an Order is `APPLY_PACKAGE` on
  // that Order's report and is deliberately not mirrored here.
  PACKAGE_CREATED: { entityType: 'PACKAGE', idKeys: ['packageId'] },
  PACKAGE_UPDATED: { entityType: 'PACKAGE', idKeys: ['packageId'] },
  PACKAGE_DELETED: { entityType: 'PACKAGE', idKeys: ['packageId'] },

  EXPENSE_CREATED: { entityType: 'EXPENSE', idKeys: ['expenseId'] },

  CLOSE_DAY_COMPLETED: {
    entityType: 'CLOSE_DAY',
    idKeys: ['businessDateClosed', 'businessDate'],
  },
  CLOSE_DAY_BLOCKED: {
    entityType: 'CLOSE_DAY',
    idKeys: ['businessDateClosed', 'businessDate'],
  },

  BACKUP_RESTORED: { entityType: 'BACKUP', idKeys: ['backupCreatedAt'] },
};

/** What the Admin panel wrote before the Reservation registry existed. */
const LEGACY_RESERVATION_CANCELLED = 'reservation_cancelled';

function normalizeAction(action: string): string {
  const trimmed = action.trim();
  if (trimmed.toLowerCase() === LEGACY_RESERVATION_CANCELLED) {
    return 'CANCEL_RESERVATION';
  }
  return trimmed.toUpperCase();
}

function cleanId(raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  const text = String(raw).trim();
  return text.length === 0 ? null : text;
}

export type DerivedAuditLogEntity = {
  entityType: AuditLogEntityType | null;
  entityId: string | null;
};

/**
 * The entity a log row is about, derived from its action and its own details.
 *
 * Returns nulls for an action outside the registry. That is the honest answer:
 * an unclassified row is still stored, still returned by the reader, and still
 * readable — it just is not claimed to be about something it may not be.
 */
export function deriveAuditLogEntity(
  action: string | null | undefined,
  data: unknown,
): DerivedAuditLogEntity {
  const raw = (action ?? '').trim();
  if (raw.length === 0) return { entityType: null, entityId: null };

  // Developer service actions are namespaced rather than enumerated.
  if (raw.startsWith('developer.')) {
    return { entityType: 'DEVELOPER', entityId: null };
  }

  const rule = ACTION_RULES[normalizeAction(raw)];
  if (!rule) return { entityType: null, entityId: null };

  if (rule.fixedId) {
    return { entityType: rule.entityType, entityId: rule.fixedId };
  }
  const details =
    data !== null && typeof data === 'object' && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {};
  for (const key of rule.idKeys) {
    const id = cleanId(details[key]);
    if (id !== null) return { entityType: rule.entityType, entityId: id };
  }
  return { entityType: rule.entityType, entityId: null };
}

/**
 * Every action name that means this entity type.
 *
 * The reader needs this because historical rows carry no `entityType`. Asking
 * for "everything about staff" has to find both the rows that say so and the
 * older rows whose action says so, without rewriting either.
 */
export function actionsForEntityType(entityType: AuditLogEntityType): string[] {
  const actions = Object.entries(ACTION_RULES)
    .filter(([, rule]) => rule.entityType === entityType)
    .map(([action]) => action);
  if (entityType === 'RESERVATION') {
    // The one action name that is not upper-case in storage.
    actions.push(LEGACY_RESERVATION_CANCELLED);
  }
  return actions;
}
