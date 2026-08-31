import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { PosCallbackClient } from '../../pos/pos-callback.client';
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
    private readonly posCallback: PosCallbackClient,
    private readonly mutationSupport: MobileMutationSupport,
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
    let yesterdayDateKey: string;
    let todayStartDate: Date;

    if (businessDateSetting?.value) {
      todayDateKey = businessDateSetting.value;
      todayStartDate = parseBusinessDateStart(todayDateKey);
    } else {
      todayStartDate = todayStart();
      todayDateKey = todayStartDate.toISOString().split('T')[0];
    }
    yesterdayDateKey = previousDay(todayStartDate).toISOString().split('T')[0];

    const openedAtKey = `businessDayOpenedAt:${todayDateKey}`;
    const [
      todayOrders,
      yesterdayOrders,
      allTables,
      openTableOrders,
      todaySummarySetting,
      openTablesPayableSetting,
      dailySalesTotalSetting,
      businessDayOpenedAtSetting,
    ] = await Promise.all([
      this.prisma.order.findMany({
        where: {
          venueId: tenant.venueId,
          ...businessDateWhere(todayDateKey),
        },
        select: { totalAmount: true },
      }),
      this.prisma.order.findMany({
        where: {
          venueId: tenant.venueId,
          ...businessDateWhere(yesterdayDateKey),
        },
        select: { totalAmount: true },
      }),
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
        where: settingIdentity(tenant, `openTablesPayable:${todayDateKey}`),
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
    const computedTodayRev = todayOrders.reduce(
      (s: number, o: any) => s + Number(o.totalAmount),
      0,
    );
    let todayRev = computedTodayRev;
    let closedTablesRevenue = computedTodayRev;
    let nonFiscalClosedRevenue = 0;
    if (dailySalesTotalSetting?.value !== undefined) {
      const exactDaily = Number(
        dailySalesTotalSetting.value ?? computedTodayRev,
      );
      closedTablesRevenue = exactDaily;
      todayRev = exactDaily;
    }
    let todayOrderCount = todayOrders.length;
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
        closedTablesRevenue = Number(summary.totalRevenue ?? computedTodayRev);
        // `summary.totalRevenue` already includes non-fiscal closed tables,
        // so do not add non-fiscal again (avoids double counting).
        todayRev = closedTablesRevenue;
        todayOrderCount = Number(summary.orderCount ?? todayOrders.length);
        cashRevenue = Number(
          summary.cashRevenue ?? summary.paymentBreakdown?.cash ?? 0,
        );
        cardRevenue = Number(
          summary.cardRevenue ?? summary.paymentBreakdown?.card ?? 0,
        );
        const pb = summary.paymentBreakdown ?? {};
        refunds = Number(pb.refund ?? pb.refunds ?? pb['refund'] ?? 0);
      } catch {
        // Keep computed fallback values.
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
    const shiftTotalRevenue = closedTablesRevenue + openTablesPayable;
    const yestRev = yesterdayOrders.reduce(
      (s: number, o: any) => s + Number(o.totalAmount),
      0,
    );

    console.log(
      '[MobileDashboard][MoneyDebug] businessDate=%s todayRevenue=%s closedTablesRevenue=%s openTablesPayable=%s sourceDaily=%s computedOpen=%s occupiedTables=%s openOrderCandidates=%s',
      todayDateKey,
      r(todayRev),
      r(closedTablesRevenue),
      r(openTablesPayable),
      dailySalesTotalSetting?.value ?? 'fallback',
      r(computedOpenTablesPayable),
      occupiedTables,
      openTableOrders.length,
    );

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
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];

    const orders = await this.prisma.order.findMany({
      where: {
        venueId: tenant.venueId,
        ...businessDateWhere(currentBusinessDate),
      },
      select: { waiterName: true, totalAmount: true },
    });

    const map = new Map<string, { totalSales: number; orderCount: number }>();
    for (const o of orders) {
      const name = o.waiterName || 'Unknown';
      const cur = map.get(name) ?? { totalSales: 0, orderCount: 0 };
      map.set(name, {
        totalSales: cur.totalSales + Number(o.totalAmount),
        orderCount: cur.orderCount + 1,
      });
    }

    return Array.from(map.entries())
      .sort((a, b) => b[1].totalSales - a[1].totalSales)
      .map(([name, stats], i) => ({
        rank: i + 1,
        waiterName: name,
        totalSales: Math.round(stats.totalSales * 100) / 100,
        orderCount: stats.orderCount,
        avgOrderValue:
          stats.orderCount > 0
            ? Math.round((stats.totalSales / stats.orderCount) * 100) / 100
            : 0,
      }));
  }

  async getFinancials(tenant: TenantContext): Promise<FinancialsResponse> {
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const range = {
      venueId: tenant.venueId,
      ...businessDateWhere(currentBusinessDate),
    };
    const r = (n: number) => Math.round(n * 100) / 100;

    const start = parseBusinessDateStart(currentBusinessDate);
    const end = nextDay(start);
    const [orders, expenses] = await Promise.all([
      (this.prisma.order.findMany as any)({
        where: range,
        select: { totalAmount: true, paymentType: true },
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

    const revenue = orders.reduce(
      (s: number, o: any) => s + Number(o.totalAmount),
      0,
    );
    const cashRev = orders.reduce((s: number, o: any) => {
      const method = normalizePaymentType(o.paymentType);
      return method === 'cash' ? s + Number(o.totalAmount) : s;
    }, 0);
    const totalExp = expenses.reduce(
      (s: number, e: any) => s + Number(e.amount),
      0,
    );

    const expMap = new Map<string, number>();
    for (const e of expenses) {
      expMap.set(e.category, (expMap.get(e.category) ?? 0) + Number(e.amount));
    }

    return {
      revenue: r(revenue),
      expenses: r(totalExp),
      profit: r(revenue - totalExp),
      cashRevenue: r(cashRev),
      cardRevenue: r(revenue - cashRev),
      orderCount: orders.length,
      avgOrderValue: orders.length > 0 ? r(revenue / orders.length) : 0,
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
    try {
      await this.posCallback.createPosExpense({
        id: created.id,
        description: created.description,
        category: created.category,
        amount: Number(created.amount),
        paymentType: created.paymentType,
        createdAt: created.createdAt.toISOString(),
        businessDate: currentBusinessDate,
      });
    } catch (e) {
      console.warn(
        '[Mobile][Expenses] POS expense callback failed:',
        (e as Error).message,
      );
    }
    return {
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
