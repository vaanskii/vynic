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
  items?: any[];
  includeServiceFee?: boolean;
  discountAmount?: number;
  serviceFeePercent?: number;
  customServiceFeePercentage?: number;
  /** ISO timestamp of the order's last local edit on the POS (LWW conflict resolution). */
  updatedAt?: string;
}

export interface ExpenseSync {
  description: string;
  amount: number;
  category: string;
  paymentType?: string;
  createdAt?: string;
}

export interface StaffSync {
  username: string;
  /** Optional — routine POS sync must not send PINs; only explicit provisioning. */
  pin?: string;
  role: 'ADMIN' | 'MANAGER' | 'SUPERVISOR' | 'WAITER';
}

export interface AuditEventLogSync {
  id: string;
  action: string;
  userId: string;
  data: any;
  deviceType: string;
  createdAt: string;
}

export interface SyncPayload {
  tables?: TableSync[];
  orders?: OrderSync[];
  expenses?: ExpenseSync[];
  menu?: any[];
  staff?: StaffSync[];
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
