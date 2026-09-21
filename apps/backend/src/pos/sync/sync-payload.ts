/**
 * Wire shapes of the POS → server synchronization snapshot.
 *
 * Moved verbatim out of `sync.controller.ts` so the HTTP layer, the ingestion
 * use case and the focused snapshot services all describe the payload with one
 * set of types. This is the POS's contract: field names and optionality here
 * are what the Flutter client sends today, so nothing in this file may be
 * tightened without a matching POS release.
 */

export interface TableSync {
  /** Canonical physical-table UUID. Added in contract v2; absent on old POS builds. */
  tableId?: string;
  tableNumber: string;
  floor: string;
  isReserved: boolean;
  activeOrderId?: number;
  currentBill?: number;
}

export interface OrderSync {
  posOrderId: number;
  orderId?: number;
  status: string;
  totalAmount: number;
  paymentType?: string;
  guestCount?: number;
  waiterName?: string;
  createdBy?: string;
  /** Table numbers for dine-in (POS mirrors local order.tables). */
  tableNumbers?: string[];
  /** Canonical IDs aligned by index with tableNumbers when every alias resolves. */
  tableIds?: string[];
  floor?: string;
  businessDate?: string;
  customerName?: string;
  customerPhone?: string;
  pickupTime?: string;
  items?: OrderItemSync[];
  includeServiceFee?: boolean;
  discountAmount?: number;
  /**
   * Signed operator override of the bill total, applied on the POS after the
   * discount and service fee. Added after the initial contract; absent on old
   * POS builds, where it is treated as 0 — which is what those builds meant.
   */
  manualAdjustmentAmount?: number;
  serviceFeePercent?: number;
  customServiceFeePercentage?: number;
  /** ISO timestamp of the order's last local edit on the POS (LWW conflict resolution). */
  updatedAt?: string;
}

export interface OrderItemSync {
  name?: string;
  itemName?: string;
  itemKey?: string;
  quantity: number;
  price?: number;
  unitPrice?: number;
  comment?: string | null;
  menuItemId?: string | null;
  variantId?: string | null;
}

export interface MenuVariantSync {
  id?: string;
  size: number;
  price: number;
}

export interface MenuItemSync {
  id?: string;
  nameKa: string;
  nameEn: string;
  price: number;
  sendToKitchen?: boolean;
  variants?: MenuVariantSync[];
}

export interface MenuSubcategorySync {
  id?: string;
  slug: string;
  nameKa: string;
  nameEn: string;
  items?: MenuItemSync[];
}

export interface MenuCategorySync {
  id?: string;
  slug: string;
  nameKa: string;
  nameEn: string;
  sendToKitchen?: boolean;
  items?: MenuItemSync[];
  subcategories?: MenuSubcategorySync[];
}

export interface ExpenseSync {
  /**
   * The record's id on the POS, which owns expense identity. Ingestion upserts
   * on it, so the POS can resend the same record every sync without creating a
   * second row. Optional in the type only because an old POS build sending an
   * expense without one must still be accepted; those are inserted, as before.
   */
  id?: string;
  description: string;
  amount: number;
  category: string;
  paymentType?: string;
  createdAt?: string;
  /** POS business day (`YYYY-MM-DD`) the expense belongs to. */
  businessDate?: string;
}

export interface StaffSync {
  username: string;
  /** Optional — routine POS sync must not send PINs; only explicit provisioning. */
  pin?: string;
  role: 'ADMIN' | 'MANAGER' | 'SUPERVISOR' | 'WAITER';
}

/**
 * One reservation as the POS holds it.
 *
 * Added in Step 6C, when reservation reads stopped being a synchronous call
 * into the restaurant's LAN. Optional on the payload: a POS build that predates
 * it sends nothing, and ingestion treats that silence as "no information" rather
 * than "no reservations".
 */
export interface ReservationSync {
  id: string;
  customerName?: string;
  customerPhone?: string;
  /** Legacy integer table codes. */
  tableNumbers?: number[];
  /** Lossless floor/number references, where this build sends them. */
  tableRefs?: string[];
  reservationDate?: string;
  reservationTime?: string;
  numberOfGuests?: number;
  notes?: string | null;
  createdAt?: string;
  createdBy?: string | null;
  status?: string;
  isTakeAway?: boolean;
  linkedOrderId?: number | null;
}

export interface AuditEventLogSync {
  id: string;
  action: string;
  userId: string;
  /**
   * What the row is about. Absent on every POS build that predates entity
   * identity, where the backend derives it from the action instead.
   */
  entityType?: string | null;
  entityId?: string | null;
  data: any;
  deviceType: string;
  createdAt: string;
}

/** Fixed two-decimal wire value, for example `"12.30"`. */
export type LedgerMoneySync = string;

export interface SaleLineSync {
  lineSeq: number;
  menuItemId?: string | null;
  variantId?: string | null;
  itemName: string;
  variantName?: string | null;
  quantity: number;
  unitPrice: LedgerMoneySync;
  lineTotal: LedgerMoneySync;
  comment?: string | null;
}

export interface SalePaymentSync {
  method: string;
  amount: LedgerMoneySync;
}

/** One genuine retained POS Sale; never synthesized from an aggregate. */
export interface SaleLedgerSync {
  /** Ignored for tenancy. Present only to prove payload tenant hints are inert. */
  venueId?: string;
  posSaleId: string;
  posOrderId: number;
  closureId?: string | null;
  businessDate: string;
  createdAt: string;
  closedAt: string;
  gross: LedgerMoneySync;
  subtotal: LedgerMoneySync;
  serviceFee: LedgerMoneySync;
  discount: LedgerMoneySync;
  manualAdjustment: LedgerMoneySync;
  advanceApplied: LedgerMoneySync;
  amountDueNow: LedgerMoneySync;
  collectedNow: LedgerMoneySync;
  paymentMethod: string;
  customPaymentLabel?: string | null;
  isFiscal: boolean;
  isCancelled: boolean;
  cancelledAt?: string | null;
  cancelledBy?: string | null;
  cancellationReason?: string | null;
  restoredToOrder: boolean;
  restoredAt?: string | null;
  restoredBy?: string | null;
  createdBy: string;
  closedById?: string | null;
  tableNumbers: string[];
  floor: string;
  revision: number;
  sourceUpdatedAt: string;
  lines: SaleLineSync[];
  payments: SalePaymentSync[];
}

export interface SaleLedgerDaySync {
  businessDate: string;
  expectedSaleCount?: number;
  expectedRevenue?: LedgerMoneySync;
  legacyRevenue?: LedgerMoneySync;
  /** True only after every retained Sale revision for this date was ACKed. */
  uploadComplete: boolean;
  /** Aggregate-only dates are explicitly classified and never backfilled. */
  legacySummaryOnly?: boolean;
}

export interface SyncPayload {
  tables?: TableSync[];
  orders?: OrderSync[];
  expenses?: ExpenseSync[];
  menu?: MenuCategorySync[];
  /** Enables destructive reconciliation only for clients with full node ids. */
  menuIdentityVersion?: number;
  staff?: StaffSync[];
  /** Bounded asynchronous upload of genuine retained local Sale records. */
  saleLedger?: SaleLedgerSync[];
  /** Per-day completeness claims independently reconciled by Cloud. */
  saleLedgerDays?: SaleLedgerDaySync[];
  /**
   * Every reservation the POS holds. Absent on builds predating Step 6C, and
   * absent from the `realtimeOnly` fast path.
   */
  reservations?: ReservationSync[];
  syncedAt?: string;
  posCallbackUrl?: string;
  posConnectionKey?: string;
  /** Fast path: tables/orders only — skip menu, staff, sales history DB work. */
  realtimeOnly?: boolean;
  quickOrders?: any[];
  /** ISO date string (YYYY-MM-DD) for the current POS business day */
  businessDate?: string;
  /** Exact Windows X-report დღიური გაყიდვები for current business date */
  dailySalesTotal?: number;
  salesSummary?: {
    date: string;
    totalRevenue: number;
    orderCount: number;
    cashRevenue: number;
    cardRevenue: number;
    paymentBreakdown: Record<string, number>;
    totalExpenses?: number;
    profit?: number;
  };
  salesAllTimeSummary?: {
    totalRevenue: number;
    orderCount: number;
    cashRevenue: number;
    cardRevenue: number;
    paymentBreakdown: Record<string, number>;
    topItems?: Array<{ name: string; qty: number; revenue: number }>;
  };
  salesHistoryByDate?: Record<
    string,
    {
      date: string;
      totalRevenue: number;
      orderCount: number;
      totalOrders: number;
      cancelledOrders: number;
      cashRevenue: number;
      cardRevenue: number;
      paymentBreakdown: Record<string, number>;
      totalExpenses?: number;
      profit?: number;
      topItems?: Array<{ name: string; qty: number; revenue: number }>;
      closedTables?: Array<{
        orderId?: number;
        tableLabel?: string;
        tableNumbers?: string[];
        floor?: string;
        isFiscal?: boolean;
        totalAmount?: number;
        closedAt?: string;
        paymentBreakdown?: Record<string, number>;
        items?: Array<{
          name: string;
          qty: number;
          unitPrice: number;
          total: number;
        }>;
      }>;
    }
  >;
  openTablesPayable?: number;
  settings?: {
    serviceFeePercent?: number;
    serviceFeeEnabled?: boolean;
  };
  /**
   * POS sends hints when item lines were removed or quantities decreased (sync snapshot diff).
   * Each hint carries manager-notification context: business-app time and table label.
   */
  touchedOrderHints?: Array<{
    posOrderId: number;
    occurredAt?: string;
    tableLabel?: string;
    floor?: string;
    waiterName?: string;
    highlightItemKeys?: string[];
    changeSummary?: string;
  }>;
  /** Table became occupied or free since last POS snapshot (walk-in / close). */
  touchedTableHints?: Array<{
    tableId?: string;
    tableNumber: string;
    floor: string;
    changeType: 'reserved' | 'freed';
    activeOrderId?: number;
    currentBill?: number;
    occurredAt?: string;
  }>;
  /** Reservation created/updated/deleted on the POS — relays to mobile. */
  touchedReservationHints?: Array<{
    reservationId: string;
    action?: string;
    customerName?: string;
    reservationDate?: string;
    reservationTime?: string;
    tableNumbers?: number[];
    linkedOrderId?: number;
    notes?: string;
    walkIn?: boolean;
    occurredAt?: string;
  }>;
}
