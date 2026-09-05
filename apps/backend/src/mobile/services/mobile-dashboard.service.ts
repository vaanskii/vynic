import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import {
  PosCommandDispatcher,
  type PosDelivery,
} from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import { MobileMutationSupport } from './mobile-mutation-support.service';
import {
  businessDateWhere,
  nextDay,
  normalizePaymentType,
  parseBusinessDateStart,
  pctChange,
  previousDay,
  todayStart,
} from '../util/mobile-date.util';
import { settingIdentity } from '../../tenancy/tenant-identity';
import type { TenantContext } from '../../tenancy/tenant-context';
import { MobileSaleLedgerService } from './mobile-sale-ledger.service';

const MANAGER_TABLE_LAYOUT: Record<string, Set<string>> = {
  first: new Set(['1', '2', '3', '4', '5', '6', '7', '8', '9']),
  second: new Set(['1', '2', '3', '4']),
};

export interface DashboardResponse {
  todayRevenue: number;
  shiftTotalRevenue: number;
  closedTablesRevenue: number;
  nonFiscalClosedRevenue: number;
  todayOrderCount: number;
  activeTablesCount: number;
  openTablesAmount: number;
  openTablesPayable: number;
  occupancyPercentage: number;
  yesterdayRevenue: number;
  avgOrderValue: number;
  revenueChange: number;
  businessDate: string;
  businessDayId: string;
  businessDayStatus: 'OPEN' | 'CLOSED';
  businessDayOpenedAt: string | null;
  businessDayDurationMinutes: number | null;
  cashRevenue: number;
  cardRevenue: number;
  refunds: number;
  totalTables: number;
  occupiedTables: number;
  reservedTables: number;
  freeTables: number;
  snapshotAt: string;
  financialProvenance?: string;
  financialWarning?: string | null;
  tbcRevenue?: number;
  bogRevenue?: number;
  advanceApplied?: number;
}

export interface StaffRankEntry {
  rank: number;
  waiterName: string;
  totalSales: number;
  orderCount: number;
  avgOrderValue: number;
}

export interface FinancialsResponse {
  revenue: number;
  expenses: number;
  profit: number;
  cashRevenue: number;
  cardRevenue: number;
  orderCount: number;
  avgOrderValue: number;
  expenseBreakdown: { category: string; amount: number }[];
  expenseEntries: {
    id: string;
    description: string;
    category: string;
    amount: number;
    paymentType: string;
    createdAt: string;
  }[];
  financialProvenance?: string;
  financialWarning?: string | null;
  tbcRevenue?: number;
  bogRevenue?: number;
  advanceApplied?: number;
  voidedCount?: number;
  restoredCount?: number;
  internalCount?: number;
}

/**
 * Dashboard / tables / staff-performance / financials / expenses endpoints for
 * the mobile manager app (`/mobile/dashboard`, `/mobile/tables`,
 * `/mobile/tables/:tableNumber/free`, `/mobile/staff-performance`,
 * `/mobile/financials`, `/mobile/expenses`).
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators and passes through query/body/socket params.
 */
@Injectable()
export class MobileDashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly posCommands: PosCommandDispatcher,
    private readonly mutationSupport: MobileMutationSupport,
    private readonly saleLedger?: MobileSaleLedgerService,
  ) {}

  private normalizeManagerTableNumber(raw: unknown, floor: string): string {
    const trimmed = String(raw ?? '').trim();
    if (!trimmed) return '';
    const withoutLabel = trimmed
      .replace(/^table\s*/i, '')
      .replace(/^vip zone\s*/i, '')
      .trim();
    const parsed = Number.parseInt(withoutLabel, 10);
    if (Number.isFinite(parsed) && floor === 'second' && parsed > 10) {
      return String(parsed - 10);
    }
    return withoutLabel;
  }

  private isManagerPhysicalTable(table: any): boolean {
    const floor = String(table.floor ?? '')
      .trim()
      .toLowerCase();
    const allowed = MANAGER_TABLE_LAYOUT[floor];
    if (!allowed) return false;
    return allowed.has(
      this.normalizeManagerTableNumber(table.tableNumber, floor),
    );
  }

  private managerTableSort(a: any, b: any): number {
    const floorRank = (floor: unknown) =>
      String(floor ?? '')
        .trim()
        .toLowerCase() === 'second'
        ? 1
        : 0;
    const floorDiff = floorRank(a.floor) - floorRank(b.floor);
    if (floorDiff !== 0) return floorDiff;

    const aFloor = String(a.floor ?? '')
      .trim()
      .toLowerCase();
    const bFloor = String(b.floor ?? '')
      .trim()
      .toLowerCase();
    const aNum = Number.parseInt(
      this.normalizeManagerTableNumber(a.tableNumber, aFloor),
      10,
    );
    const bNum = Number.parseInt(
      this.normalizeManagerTableNumber(b.tableNumber, bFloor),
      10,
    );
    if (Number.isFinite(aNum) && Number.isFinite(bNum)) {
      return aNum - bNum;
    }
    return String(a.tableNumber ?? '').localeCompare(
      String(b.tableNumber ?? ''),
    );
  }

  async getDashboard(tenant: TenantContext): Promise<DashboardResponse> {
    // Use the business date set by the POS (stored in Setting).
    // Falls back to calendar today if not yet set (first-run / no POS connected).
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });

    let todayDateKey: string;
    let todayStartDate: Date;

    if (businessDateSetting?.value) {
      todayDateKey = businessDateSetting.value;
      todayStartDate = parseBusinessDateStart(todayDateKey);
    } else {
      todayStartDate = todayStart();
      todayDateKey = todayStartDate.toISOString().split('T')[0];
    }
    const previousBusinessDay = previousDay(todayStartDate);
    const yesterdayDateKey = [
      previousBusinessDay.getFullYear().toString().padStart(4, '0'),
      (previousBusinessDay.getMonth() + 1).toString().padStart(2, '0'),
      previousBusinessDay.getDate().toString().padStart(2, '0'),
    ].join('-');

    const openedAtKey = `businessDayOpenedAt:${todayDateKey}`;
    const [
      allTables,
      openTableOrders,
      todaySummarySetting,
      yesterdaySummarySetting,
      dailySalesTotalSetting,
      businessDayOpenedAtSetting,
    ] = await Promise.all([
      (this.prisma as any).table.findMany({
        where: { venueId: tenant.venueId },
        select: {
          id: true,
          tableNumber: true,
          floor: true,
          currentBill: true,
          isReserved: true,
          activeOrderId: true,
        },
      }),
      this.prisma.order.findMany({
        where: {
          venueId: tenant.venueId,
          ...businessDateWhere(todayDateKey),
          status: { notIn: ['closed', 'cancelled', 'paid'] },
          NOT: {
            OR: [
              { floor: { contains: 'takeaway', mode: 'insensitive' } },
              { floor: { contains: 'take away', mode: 'insensitive' } },
            ],
          },
        },
        select: { posOrderId: true, totalAmount: true, businessDate: true },
      }),
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, `salesSummary:${todayDateKey}`),
      }),
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, `salesSummary:${yesterdayDateKey}`),
      }),
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, `dailySalesTotal:${todayDateKey}`),
      }),
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, openedAtKey),
      }),
    ]);

    const physicalTables = allTables.filter((t: any) =>
      this.isManagerPhysicalTable(t),
    );
    const totalTablesCount = physicalTables.length;

    // Open money = only orders physically linked to occupied tables right now.
    // Ignores ghost "open" orders in DB and stale openTablesPayable settings.
    const openOrderByPosId = new Map<
      number,
      { totalAmount: number; businessDate: string }
    >();
    for (const order of openTableOrders) {
      openOrderByPosId.set(Number(order.posOrderId), {
        totalAmount: Number(order.totalAmount ?? 0),
        businessDate: String(order.businessDate ?? '').trim(),
      });
    }

    const openPosOrderIds = new Set<number>();
    const openPayableByPosOrderId = new Map<number, number>();
    for (const table of physicalTables) {
      if (table.activeOrderId == null) continue;
      const posId = Number(table.activeOrderId);
      const linked = openOrderByPosId.get(posId);
      if (!linked) continue;
      const bd = linked.businessDate;
      if (bd !== '' && bd !== todayDateKey) continue;
      const bill = Number(table.currentBill ?? 0);
      const payable = bill > 0 ? bill : linked.totalAmount;
      const previous = openPayableByPosOrderId.get(posId) ?? 0;
      openPayableByPosOrderId.set(posId, Math.max(previous, payable));
      openPosOrderIds.add(posId);
    }
    const openTablesPayable = Array.from(
      openPayableByPosOrderId.values(),
    ).reduce((sum, amount) => sum + amount, 0);

    const occupiedTables = physicalTables.filter(
      (t: any) =>
        t.activeOrderId != null && openPosOrderIds.has(Number(t.activeOrderId)),
    ).length;
    const reservedTables = physicalTables.filter(
      (t: any) => t.isReserved && t.activeOrderId == null,
    ).length;
    const freeTables = Math.max(
      0,
      totalTablesCount - occupiedTables - reservedTables,
    );
    const activeTables = occupiedTables + reservedTables;

    const r = (n: number) => Math.round(n * 100) / 100;
    // Closed revenue comes only from Sale-derived POS settings. The Cloud
    // Order mirror cannot prove fiscality, closure completeness, reversal, or
    // gross value, so absence of a summary fails closed to zero.
    let todayRev = 0;
    let closedTablesRevenue = 0;
    let nonFiscalClosedRevenue = 0;
    if (dailySalesTotalSetting?.value !== undefined) {
      const exactDaily = Number(dailySalesTotalSetting.value ?? 0);
      closedTablesRevenue = exactDaily;
      todayRev = exactDaily;
    }
    let todayOrderCount = 0;
    let cashRevenue = 0;
    let cardRevenue = 0;
    let refunds = 0;
    if (todaySummarySetting?.value) {
      try {
        const summary = JSON.parse(todaySummarySetting.value) as {
          totalRevenue?: number;
          orderCount?: number;
          cashRevenue?: number;
          cardRevenue?: number;
          paymentBreakdown?: Record<string, number>;
        };
        nonFiscalClosedRevenue = Number(
          summary.paymentBreakdown?.['non-fiscal'] ?? 0,
        );
        closedTablesRevenue = Number(summary.totalRevenue ?? 0);
        todayRev = closedTablesRevenue;
        todayOrderCount = Number(summary.orderCount ?? 0);
        cashRevenue = Number(
          summary.cashRevenue ?? summary.paymentBreakdown?.cash ?? 0,
        );
        cardRevenue = Number(
          summary.cardRevenue ?? summary.paymentBreakdown?.card ?? 0,
        );
        const pb = summary.paymentBreakdown ?? {};
        refunds = Number(pb.refund ?? pb.refunds ?? pb['refund'] ?? 0);
      } catch (error) {
        console.warn(
          `[MobileDashboard] Invalid Sale-derived summary for ${todayDateKey}; using only the validated daily Sale total when available.`,
          error,
        );
      }
    }

    const businessDayOpenedAt = businessDayOpenedAtSetting?.value ?? null;
    let businessDayDurationMinutes: number | null = null;
    if (businessDayOpenedAt) {
      const openedMs = Date.parse(businessDayOpenedAt);
      if (!Number.isNaN(openedMs)) {
        businessDayDurationMinutes = Math.max(
          0,
          Math.floor((Date.now() - openedMs) / 60000),
        );
      }
    }
    const computedOpenTablesPayable = openTablesPayable;
    const shiftTotalRevenue = closedTablesRevenue;
    let yestRev = 0;
    if (yesterdaySummarySetting?.value) {
      try {
        const summary = JSON.parse(yesterdaySummarySetting.value) as {
          totalRevenue?: number;
        };
        yestRev = Number(summary.totalRevenue ?? 0);
      } catch (error) {
        console.warn(
          `[MobileDashboard] Invalid Sale-derived summary for ${yesterdayDateKey}; revenue unavailable.`,
          error,
        );
      }
    }

    console.log(
      '[MobileDashboard][MoneyDebug] businessDate=%s todayRevenue=%s closedTablesRevenue=%s openTablesPayable=%s sourceDaily=%s computedOpen=%s occupiedTables=%s openOrderCandidates=%s',
      todayDateKey,
      r(todayRev),
      r(closedTablesRevenue),
      r(openTablesPayable),
      dailySalesTotalSetting?.value ?? 'unavailable',
      r(computedOpenTablesPayable),
      occupiedTables,
      openTableOrders.length,
    );

    const ledger = this.saleLedger
      ? await this.saleLedger.getSummary(tenant, {
          from: todayDateKey,
          to: todayDateKey,
        })
      : null;
    if (ledger?.provenance === 'LEDGER_COMPLETE') {
      todayRev = Number(ledger.revenue);
      closedTablesRevenue = todayRev;
      todayOrderCount = ledger.revenueSaleCount;
      cashRevenue = Number(ledger.cashCollected);
      cardRevenue =
        Number(ledger.tbcCollected) +
        Number(ledger.bogCollected) +
        Number(ledger.legacyCardCollected);
    }

    return {
      todayRevenue: r(todayRev),
      shiftTotalRevenue: r(shiftTotalRevenue),
      closedTablesRevenue: r(closedTablesRevenue),
      nonFiscalClosedRevenue: r(nonFiscalClosedRevenue),
      todayOrderCount,
      activeTablesCount: activeTables,
      openTablesAmount: r(openTablesPayable),
      openTablesPayable: r(openTablesPayable),
      occupancyPercentage:
        totalTablesCount > 0
          ? Math.round((activeTables / totalTablesCount) * 1000) / 10
          : 0,
      yesterdayRevenue: r(yestRev),
      avgOrderValue: todayOrderCount > 0 ? r(todayRev / todayOrderCount) : 0,
      revenueChange: pctChange(todayRev, yestRev),
      businessDate: todayDateKey,
      businessDayId: todayDateKey,
      businessDayStatus: 'OPEN',
      businessDayOpenedAt,
      businessDayDurationMinutes,
      cashRevenue: r(cashRevenue),
      cardRevenue: r(cardRevenue),
      refunds: r(refunds),
      totalTables: totalTablesCount,
      occupiedTables,
      reservedTables,
      freeTables,
      snapshotAt: new Date().toISOString(),
      ...(ledger
        ? {
            financialProvenance: ledger.provenance,
            financialWarning: ledger.warning,
            tbcRevenue: Number(ledger.tbcCollected),
            bogRevenue: Number(ledger.bogCollected),
            advanceApplied: Number(ledger.advanceApplied),
          }
        : {}),
    };
  }

  async getTables(tenant: TenantContext) {
    const tables = await (this.prisma as any).table.findMany({
      where: { venueId: tenant.venueId },
      orderBy: [{ floor: 'asc' }, { tableNumber: 'asc' }],
    });
    return tables
      .filter((t: any) => this.isManagerPhysicalTable(t))
      .sort((a: any, b: any) => this.managerTableSort(a, b))
      .map((t: any) => {
        const occupied = !!(t.isReserved || t.activeOrderId);
        return {
          id: t.id,
          tableNumber: this.normalizeManagerTableNumber(t.tableNumber, t.floor),
          floor: t.floor,
          isReserved: occupied,
          isOccupied: occupied,
          currentBill: occupied ? (t.currentBill ?? 0) : 0,
          activeOrderId: occupied ? (t.activeOrderId ?? null) : null,
          updatedAt: t.updatedAt,
        };
      });
  }

  async freeTable(
    tenant: TenantContext,
    tableNumber: string,
    floor: string,
    monitoringSocketId?: string,
  ) {
    const updated = await (this.prisma as any).table.updateMany({
      where: {
        venueId: tenant.venueId,
        tableNumber,
        floor,
      },
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });
    if (updated.count === 0)
      return { success: false, error: 'table_not_found' };
    this.mutationSupport.registerMobileMutationEchoGuard(undefined, {
      tableNumber,
      floor,
    });
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'tables',
        action: 'freed',
        tableNumber,
        floor,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  async getStaffPerformance(tenant: TenantContext): Promise<StaffRankEntry[]> {
    void tenant;
    // Per-waiter Sale attribution is not present in the authoritative summary
    // mirror yet. Raw Orders include open/internal/restored states and net
    // payable values, so an empty unavailable result is the only honest value.
    return [];
  }

  async getFinancials(tenant: TenantContext): Promise<FinancialsResponse> {
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const r = (n: number) => Math.round(n * 100) / 100;

    const start = parseBusinessDateStart(currentBusinessDate);
    const end = nextDay(start);
    const [summarySetting, expenses] = await Promise.all([
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, `salesSummary:${currentBusinessDate}`),
      }),
      this.prisma.expense.findMany({
        where: {
          venueId: tenant.venueId,
          createdAt: { gte: start, lt: end },
        },
        select: {
          id: true,
          description: true,
          amount: true,
          category: true,
          paymentType: true,
          createdAt: true,
        },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    let revenue = 0;
    let cashRev = 0;
    let cardRev = 0;
    let orderCount = 0;
    if (summarySetting?.value) {
      try {
        const summary = JSON.parse(summarySetting.value) as {
          totalRevenue?: number;
          cashRevenue?: number;
          cardRevenue?: number;
          orderCount?: number;
        };
        revenue = Number(summary.totalRevenue ?? 0);
        cashRev = Number(summary.cashRevenue ?? 0);
        cardRev = Number(summary.cardRevenue ?? 0);
        orderCount = Number(summary.orderCount ?? 0);
      } catch (error) {
        console.warn(
          `[MobileDashboard] Invalid Sale-derived financial summary for ${currentBusinessDate}; revenue unavailable.`,
          error,
        );
      }
    }
    const totalExp = expenses.reduce(
      (s: number, e: any) => s + Number(e.amount),
      0,
    );

    const expMap = new Map<string, number>();
    for (const e of expenses) {
      expMap.set(e.category, (expMap.get(e.category) ?? 0) + Number(e.amount));
    }

    const ledger = this.saleLedger
      ? await this.saleLedger.getSummary(tenant, {
          from: currentBusinessDate,
          to: currentBusinessDate,
        })
      : null;
    if (ledger?.provenance === 'LEDGER_COMPLETE') {
      revenue = Number(ledger.revenue);
      cashRev = Number(ledger.cashCollected);
      cardRev =
        Number(ledger.tbcCollected) +
        Number(ledger.bogCollected) +
        Number(ledger.legacyCardCollected);
      orderCount = ledger.revenueSaleCount;
    }

    return {
      revenue: r(revenue),
      expenses: r(totalExp),
      profit: r(revenue - totalExp),
      cashRevenue: r(cashRev),
      cardRevenue: r(cardRev),
      orderCount,
      avgOrderValue: orderCount > 0 ? r(revenue / orderCount) : 0,
      expenseBreakdown: Array.from(expMap.entries()).map(
        ([category, amount]) => ({
          category,
          amount: r(amount),
        }),
      ),
      expenseEntries: expenses.map((e) => ({
        id: e.id,
        description: e.description,
        category: e.category,
        amount: r(Number(e.amount)),
        paymentType: e.paymentType,
        createdAt: e.createdAt.toISOString(),
      })),
      ...(ledger
        ? {
            financialProvenance: ledger.provenance,
            financialWarning: ledger.warning,
            tbcRevenue: Number(ledger.tbcCollected),
            bogRevenue: Number(ledger.bogCollected),
            advanceApplied: Number(ledger.advanceApplied),
            voidedCount: ledger.voidedCount,
            restoredCount: ledger.restoredCount,
            internalCount: ledger.internalCount,
          }
        : {}),
    };
  }

  async createExpense(
    tenant: TenantContext,
    payload: {
      description?: string;
      amount?: number;
      category?: string;
      paymentType?: string;
    },
  ): Promise<{
    id: string;
    description: string;
    category: string;
    amount: number;
    paymentType: string;
    createdAt: string;
    posDelivery: PosDelivery;
  }> {
    const description = (payload.description ?? '').trim();
    const category = (payload.category ?? 'სხვა').trim() || 'სხვა';
    const paymentType = normalizePaymentType(payload.paymentType ?? 'cash');
    const amount = Number(payload.amount ?? 0);
    if (!description) {
      throw new BadRequestException('description is required');
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('amount must be greater than zero');
    }
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const businessDayStart = parseBusinessDateStart(currentBusinessDate);
    const now = new Date();
    // Persist expense on current POS business day (not device calendar day).
    const createdAt = new Date(businessDayStart);
    createdAt.setHours(
      now.getHours(),
      now.getMinutes(),
      now.getSeconds(),
      now.getMilliseconds(),
    );
    const created = await this.prisma.expense.create({
      data: {
        venueId: tenant.venueId,
        description,
        amount,
        category,
        paymentType,
        createdAt,
      },
      select: {
        id: true,
        description: true,
        category: true,
        amount: true,
        paymentType: true,
        createdAt: true,
      },
    });
    // Cloud allocates the expense id, and the POS upserts on it — so a
    // redelivered command updates the one record instead of adding a second
    // expense to a restaurant's day.
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.EXPENSE_CREATE,
      payload: {
        id: created.id,
        description: created.description,
        category: created.category,
        amount: Number(created.amount),
        paymentType: created.paymentType,
        createdAt: created.createdAt.toISOString(),
        businessDate: currentBusinessDate,
      },
    });
    return {
      posDelivery,
      id: created.id,
      description: created.description,
      category: created.category,
      amount: Math.round(Number(created.amount) * 100) / 100,
      paymentType: created.paymentType,
      createdAt: created.createdAt.toISOString(),
    };
  }

  async deleteExpense(
    tenant: TenantContext,
    id: string,
  ): Promise<{ success: true }> {
    const deleted = await this.prisma.expense.deleteMany({
      where: { id, venueId: tenant.venueId },
    });
    if (deleted.count === 0) {
      throw new NotFoundException('Expense not found');
    }
    return { success: true };
  }
}
