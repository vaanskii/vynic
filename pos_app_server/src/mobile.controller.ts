import {
  BadRequestException,
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  NotFoundException,
  Headers,
  Param,
  Body,
  Query,
  UseGuards,
  ParseIntPipe,
  DefaultValuePipe,
  Req,
} from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { Order } from '@prisma/client';
import { JwtAuthGuard } from './auth/jwt-auth.guard';
import { RolesGuard } from './auth/roles.guard';
import { Roles } from './auth/roles.decorator';
import { StaffRole } from './staff/staff-role';
import { MonitoringGateway } from './realtime/monitoring.gateway';
import { PosCallbackClient } from './pos/pos-callback.client';
import { MobileUsersService } from './mobile-users.service';
import { buildAuditEventsForOrderDiff } from './pos/audit/audit-order-diff';
import { normalizeAuditEventType } from './pos/audit/audit-event-type';
import {
  suppressPosAuditBroadcast,
  suppressPosEchoForOrder,
  suppressPosEchoForReservation,
  suppressPosEchoForTable,
} from './pos/sync-echo-guard';
import { PosOutboxService } from './pos/pos-outbox.service';
import { v4 as uuidv4 } from 'uuid';

// ─── Lightweight response types ───────────────────────────────────────────────

interface DashboardResponse {
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

interface StaffRankEntry {
  rank: number;
  waiterName: string;
  totalSales: number;
  orderCount: number;
  avgOrderValue: number;
}

interface FinancialsResponse {
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

interface PaginatedOrders {
  data: {
    id: string;
    posOrderId: number;
    status: string;
    totalAmount: number;
    waiterName: string;
    guestCount: number;
    createdAt: string;
    itemCount: number;
  }[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

interface ReservationResponseItem {
  id: string;
  customerName: string;
  customerPhone: string;
  tableNumbers: number[];
  reservationDate: string;
  reservationTime: string;
  numberOfGuests: number;
  notes?: string;
  status: string;
  createdBy?: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function todayStart(): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function yesterdayStart(): Date {
  const d = todayStart();
  d.setDate(d.getDate() - 1);
  return d;
}

function parseBusinessDateStart(businessDate: string): Date {
  const [y, m, d] = businessDate.split('-').map(Number);
  return new Date(y, m - 1, d, 0, 0, 0, 0);
}

function nextDay(start: Date): Date {
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return end;
}

function previousDay(start: Date): Date {
  const prev = new Date(start);
  prev.setDate(prev.getDate() - 1);
  return prev;
}

function normalizePaymentType(raw: string | null | undefined): string {
  const key = (raw ?? 'cash').trim().toLowerCase();
  if (key === '') return 'cash';
  if (key.startsWith('card-')) return key;
  if (key === 'card_tbc') return 'card-tbc';
  if (key === 'card_bog') return 'card-bog';
  return key;
}

function businessDateWhere(
  businessDate: string,
): { OR: Array<Record<string, unknown>> } {
  const start = parseBusinessDateStart(businessDate);
  const end = nextDay(start);
  return {
    OR: [
      { businessDate },
      { businessDate: '', createdAt: { gte: start, lt: end } },
    ],
  };
}

function pctChange(today: number, yesterday: number): number {
  if (yesterday === 0) return today > 0 ? 100 : 0;
  return Math.round(((today - yesterday) / yesterday) * 1000) / 10;
}

async function readRestaurantServiceFeeSettings(prisma: any) {
  const [percentRow, enabledRow] = await Promise.all([
    (prisma as any).setting.findUnique({
      where: { key: 'restaurant:serviceFeePercent' },
    }),
    (prisma as any).setting.findUnique({
      where: { key: 'restaurant:serviceFeeEnabled' },
    }),
  ]);
  const serviceFeePercent = percentRow ? Number(percentRow.value) : 10;
  const serviceFeeEnabled = enabledRow?.value === 'true';
  return {
    serviceFeePercent,
    serviceFeeEnabled,
    serviceFeeAvailable: serviceFeeEnabled && serviceFeePercent > 0,
  };
}

// ─── Controller ───────────────────────────────────────────────────────────────

@Controller('mobile')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(StaffRole.MANAGER)
export class MobileController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly posOutbox: PosOutboxService,
    private readonly posCallback: PosCallbackClient,
    private readonly users: MobileUsersService,
  ) {}

  // GET /mobile/restaurant-settings
  @Get('restaurant-settings')
  async getRestaurantSettings() {
    return readRestaurantServiceFeeSettings(this.prisma);
  }

  /** Missed manager notifications while the app was backgrounded (persisted on server). */
  @Get('notifications')
  async getNotifications(
    @Req() req: { user: { username: string } },
    @Query('since') since?: string,
  ) {
    const username = req.user.username;
    let sinceDate: Date;
    if (since && since.trim().length > 0) {
      sinceDate = new Date(since.trim());
      if (Number.isNaN(sinceDate.getTime())) {
        throw new BadRequestException('Invalid since timestamp');
      }
    } else {
      sinceDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    }

    const rows = await (this.prisma as any).managerNotificationDelivery.findMany({
      where: {
        staffUsername: username,
        notification: { createdAt: { gte: sinceDate } },
      },
      include: { notification: true },
      orderBy: { notification: { createdAt: 'asc' } },
      take: 100,
    });

    return rows.map((row: any) => {
      const n = row.notification;
      return {
        id: n.id as string,
        type: n.wsType as string,
        title: n.title as string,
        body: n.body as string,
        envelope: n.envelope,
        createdAt: (n.createdAt as Date).toISOString(),
      };
    });
  }

  @Post('push/register')
  async registerPushDevice(
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string; platform?: string },
  ) {
    const staffUsername = req.user.username;
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    await (this.prisma as any).pushDevice.upsert({
      where: { fcmToken },
      update: {
        staffUsername,
        platform: (payload.platform ?? '').trim() || null,
      },
      create: {
        staffUsername,
        fcmToken,
        platform: (payload.platform ?? '').trim() || null,
      },
    });
    return { success: true };
  }

  @Post('push/unregister')
  async unregisterPushDevice(
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string },
  ) {
    const staffUsername = req.user.username;
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    await (this.prisma as any).pushDevice.deleteMany({
      where: { staffUsername, fcmToken },
    });
    return { success: true };
  }

  // GET /mobile/dashboard
  @Get('dashboard')
  async getDashboard(): Promise<DashboardResponse> {
    // Use the business date set by the POS (stored in Setting).
    // Falls back to calendar today if not yet set (first-run / no POS connected).
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
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
    const [todayOrders, yesterdayOrders, allTables, openTableOrders, todaySummarySetting, openTablesPayableSetting, dailySalesTotalSetting, businessDayOpenedAtSetting] =
      await Promise.all([
        this.prisma.order.findMany({
          where: businessDateWhere(todayDateKey),
          select: { totalAmount: true },
        }),
        this.prisma.order.findMany({
          where: businessDateWhere(yesterdayDateKey),
          select: { totalAmount: true },
        }),
        (this.prisma as any).table.findMany({
          select: { id: true, currentBill: true, isReserved: true, activeOrderId: true },
        }),
        this.prisma.order.findMany({
          where: {
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
          where: { key: `salesSummary:${todayDateKey}` },
        }),
        (this.prisma as any).setting.findUnique({
          where: { key: `openTablesPayable:${todayDateKey}` },
        }),
        (this.prisma as any).setting.findUnique({
          where: { key: `dailySalesTotal:${todayDateKey}` },
        }),
        (this.prisma as any).setting.findUnique({
          where: { key: openedAtKey },
        }),
      ]);

    const totalTablesCount = allTables.length;

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
    let openTablesPayable = 0;
    for (const table of allTables) {
      if (table.activeOrderId == null) continue;
      const posId = Number(table.activeOrderId);
      const linked = openOrderByPosId.get(posId);
      if (!linked) continue;
      const bd = linked.businessDate;
      if (bd !== '' && bd !== todayDateKey) continue;
      const bill = Number(table.currentBill ?? 0);
      openTablesPayable += bill > 0 ? bill : linked.totalAmount;
      openPosOrderIds.add(posId);
    }

    const occupiedTables = allTables.filter(
      (t: any) =>
        t.activeOrderId != null &&
        openPosOrderIds.has(Number(t.activeOrderId)),
    ).length;
    const reservedTables = allTables.filter(
      (t: any) => t.isReserved && t.activeOrderId == null,
    ).length;
    const freeTables = Math.max(0, totalTablesCount - occupiedTables - reservedTables);
    const activeTables = occupiedTables + reservedTables;

    const r = (n: number) => Math.round(n * 100) / 100;
    const computedTodayRev = todayOrders.reduce(
      (s: number, o: any) => s + Number(o.totalAmount), 0,
    );
    let todayRev = computedTodayRev;
    let closedTablesRevenue = computedTodayRev;
    let nonFiscalClosedRevenue = 0;
    if (dailySalesTotalSetting?.value !== undefined) {
      const exactDaily = Number(dailySalesTotalSetting.value ?? computedTodayRev);
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
        cashRevenue = Number(summary.cashRevenue ?? summary.paymentBreakdown?.cash ?? 0);
        cardRevenue = Number(summary.cardRevenue ?? summary.paymentBreakdown?.card ?? 0);
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
      (s: number, o: any) => s + Number(o.totalAmount), 0,
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
      avgOrderValue:
        todayOrderCount > 0 ? r(todayRev / todayOrderCount) : 0,
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

  // GET /mobile/tables
  @Get('tables')
  async getTables() {
    const tables = await (this.prisma as any).table.findMany({
      orderBy: [{ floor: 'asc' }, { tableNumber: 'asc' }],
    });
    return tables.map((t: any) => {
      const occupied = !!(t.isReserved || t.activeOrderId);
      return {
        id: t.id,
        tableNumber: t.tableNumber,
        floor: t.floor,
        isReserved: occupied,
        isOccupied: occupied,
        currentBill: occupied ? (t.currentBill ?? 0) : 0,
        activeOrderId: occupied ? (t.activeOrderId ?? null) : null,
        updatedAt: t.updatedAt,
      };
    });
  }

  // POST /mobile/tables/:tableNumber/free?floor=first
  // Forcefully marks a table as free (emergency ghost-table fix for managers).
  @Post('tables/:tableNumber/free')
  async freeTable(
    @Param('tableNumber') tableNumber: string,
    @Query('floor') floor: string = 'first',
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    const updated = await (this.prisma as any).table.updateMany({
      where: { tableNumber, floor },
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });
    if (updated.count === 0) return { success: false, error: 'table_not_found' };
    this.registerMobileMutationEchoGuard(undefined, { tableNumber, floor });
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'tables',
        action: 'freed',
        tableNumber,
        floor,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  // GET /mobile/staff-performance
  @Get('staff-performance')
  async getStaffPerformance(): Promise<StaffRankEntry[]> {
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];

    const orders = await this.prisma.order.findMany({
      where: businessDateWhere(currentBusinessDate),
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

  // GET /mobile/financials
  @Get('financials')
  async getFinancials(): Promise<FinancialsResponse> {
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const range = businessDateWhere(currentBusinessDate);
    const r = (n: number) => Math.round(n * 100) / 100;

    const start = parseBusinessDateStart(currentBusinessDate);
    const end = nextDay(start);
    const [orders, expenses] = await Promise.all([
      (this.prisma.order.findMany as any)({
        where: range,
        select: { totalAmount: true, paymentType: true },
      }),
      this.prisma.expense.findMany({
        where: { createdAt: { gte: start, lt: end } },
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
      (s: number, o: any) => s + Number(o.totalAmount), 0,
    );
    const cashRev = orders.reduce((s: number, o: any) => {
      const method = normalizePaymentType(o.paymentType);
      return method === 'cash' ? s + Number(o.totalAmount) : s;
    }, 0);
    const totalExp = expenses.reduce(
      (s: number, e: any) => s + Number(e.amount), 0,
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
      expenseBreakdown: Array.from(expMap.entries()).map(([category, amount]) => ({
        category,
        amount: r(amount),
      })),
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

  // POST /mobile/expenses
  @Post('expenses')
  async createExpense(
    @Body()
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
      where: { key: 'currentBusinessDate' },
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
      console.warn('[Mobile][Expenses] POS expense callback failed:', (e as Error).message);
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

  // DELETE /mobile/expenses/:id
  @Delete('expenses/:id')
  async deleteExpense(@Param('id') id: string): Promise<{ success: true }> {
    try {
      await this.prisma.expense.delete({ where: { id } });
    } catch {
      throw new NotFoundException('Expense not found');
    }
    return { success: true };
  }

  // GET /mobile/orders?page=1&pageSize=20&status=open
  @Get('orders')
  async getOrders(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('pageSize', new DefaultValuePipe(20), ParseIntPipe) pageSize: number,
    @Query('status') status?: string,
  ): Promise<PaginatedOrders> {
    const take = Math.min(pageSize, 100);
    const skip = (page - 1) * take;
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const where: any = businessDateWhere(currentBusinessDate);
    if (status) where.status = status;

    const [data, total] = await Promise.all([
      this.prisma.order.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
        select: {
          id: true,
          posOrderId: true,
          status: true,
          totalAmount: true,
          waiterName: true,
          guestCount: true,
          createdAt: true,
          _count: { select: { items: true } },
        },
      }),
      this.prisma.order.count({ where }),
    ]);

    return {
      data: data.map((o: any) => ({
        id: o.id,
        posOrderId: o.posOrderId,
        status: o.status,
        totalAmount: Math.round(Number(o.totalAmount) * 100) / 100,
        waiterName: o.waiterName,
        guestCount: o.guestCount,
        createdAt: (o.createdAt as Date).toISOString(),
        itemCount: o._count.items,
      })),
      total,
      page,
      pageSize: take,
      hasMore: skip + take < total,
    };
  }

  // GET /mobile/reservations?date=YYYY-MM-DD
  @Get('reservations')
  async getReservations(
    @Query('date') date?: string,
  ): Promise<ReservationResponseItem[]> {
    let rows: any[] = [];
    try {
      rows = await this.posCallback.fetchPosReservations();
    } catch (e) {
      console.warn('[Mobile][Reservations] fetch failed:', (e as Error).message);
      // Keep mobile UI functional even before POS callback URL is synced.
      return [];
    }
    const normalized = rows
      .filter((r) => r && typeof r === 'object')
      // Exclude walk-ins and takeaways: those are order-linked records the POS
      // creates for dine-in/takeaway orders, not real bookings. Mirrors the
      // Windows POS getAdminPanelReservations() filter.
      .filter((r: any) => {
        if (r.isTakeAway === true) return false;
        if (r.linkedOrderId !== undefined && r.linkedOrderId !== null) {
          return false;
        }
        const notes = String(r.notes ?? '');
        if (notes.startsWith('Order #')) return false;
        return true;
      })
      .map((r: any) => ({
        id: String(r.id ?? ''),
        customerName: String(r.customerName ?? ''),
        customerPhone: String(r.customerPhone ?? ''),
        tableNumbers: Array.isArray(r.tableNumbers)
          ? r.tableNumbers.map((x: any) => Number(x)).filter((x: number) => Number.isFinite(x))
          : [],
        reservationDate: String(r.reservationDate ?? ''),
        reservationTime: String(r.reservationTime ?? ''),
        numberOfGuests: Number(r.numberOfGuests ?? 0),
        notes: r.notes ? String(r.notes) : undefined,
        status: String(r.status ?? 'pending'),
        createdBy: r.createdBy ? String(r.createdBy) : undefined,
      }))
      .filter((r) => r.id.length > 0);

    if (date && date.trim().length > 0) {
      return normalized.filter((r) => r.reservationDate.startsWith(date));
    }
    return normalized;
  }

  // POST /mobile/reservations
  @Post('reservations')
  async createReservation(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body()
    payload: {
      customerName?: string;
      customerPhone?: string;
      tableNumbers?: number[];
      reservationDate?: string;
      reservationTime?: string;
      numberOfGuests?: number;
      notes?: string;
      createdBy?: string;
      status?: string;
      preOrderItems?: Array<Record<string, unknown>>;
    },
  ): Promise<ReservationResponseItem> {
    const customerName = (payload.customerName ?? '').trim();
    const customerPhone = (payload.customerPhone ?? '').trim();
    const reservationDate = (payload.reservationDate ?? '').trim();
    const reservationTime = (payload.reservationTime ?? '').trim();
    const tableNumbers = Array.isArray(payload.tableNumbers)
      ? payload.tableNumbers.map((n) => Number(n)).filter((n) => Number.isFinite(n))
      : [];
    const numberOfGuests = Number(payload.numberOfGuests ?? 0);
    if (customerName.length === 0 || reservationDate.length === 0 || reservationTime.length === 0) {
      throw new BadRequestException('customerName, reservationDate, reservationTime are required');
    }
    if (!Number.isFinite(numberOfGuests) || numberOfGuests <= 0) {
      throw new BadRequestException('numberOfGuests must be greater than zero');
    }

    const preOrderItems = Array.isArray(payload.preOrderItems)
      ? payload.preOrderItems
      : [];

    const reservation = await this.posCallback.createPosReservation({
      customerName,
      customerPhone,
      tableNumbers,
      reservationDate,
      reservationTime,
      numberOfGuests,
      notes: (payload.notes ?? '').toString(),
      createdBy: (payload.createdBy ?? 'mobile_manager').toString(),
      status: (payload.status ?? 'confirmed').toString(),
      isTakeAway: false,
      preOrderItems,
    });
    // Suppress the POS round-trip echo so the device that created this
    // reservation isn't re-notified when the POS syncs it back.
    const newReservationId = String(reservation?.id ?? '').trim();
    if (newReservationId.length > 0) {
      suppressPosEchoForReservation(newReservationId);
    }
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: 'created',
        customerName,
        tableNumbers,
        reservationTime,
        reservationDate,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return {
      id: String(reservation?.id ?? ''),
      customerName: String(reservation?.customerName ?? customerName),
      customerPhone: String(reservation?.customerPhone ?? customerPhone),
      tableNumbers: Array.isArray(reservation?.tableNumbers)
        ? reservation.tableNumbers.map((x: any) => Number(x)).filter((x: number) => Number.isFinite(x))
        : tableNumbers,
      reservationDate: String(reservation?.reservationDate ?? reservationDate),
      reservationTime: String(reservation?.reservationTime ?? reservationTime),
      numberOfGuests: Number(reservation?.numberOfGuests ?? numberOfGuests),
      notes: reservation?.notes ? String(reservation.notes) : undefined,
      status: String(reservation?.status ?? 'confirmed'),
      createdBy: reservation?.createdBy ? String(reservation.createdBy) : undefined,
    };
  }

  // POST /mobile/reservations/:id/status
  @Post('reservations/:id/status')
  async updateReservationStatus(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() payload: { status?: string },
  ): Promise<{ success: true }> {
    const status = (payload.status ?? '').trim().toLowerCase();
    if (status.length === 0) {
      throw new BadRequestException('status is required');
    }
    if (status === 'completed' || status === 'in-progress' || status === 'inprogress') {
      throw new BadRequestException('Moving reservation to table is not allowed from mobile');
    }
    await this.posCallback.updatePosReservationStatus(id, status);
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: status === 'cancelled' ? 'cancelled' : 'updated',
        reservationId: id,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  // DELETE /mobile/reservations/:id
  @Delete('reservations/:id')
  async deleteReservation(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ): Promise<{ success: true }> {
    await this.posCallback.deletePosReservation(id);
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: 'cancelled',
        reservationId: id,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  // GET /mobile/order/:id
  @Get('order/:id')
  async getOrder(@Param('id') id: string) {
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId: Number(id) },
      include: { items: true },
    });
    if (!order) return { error: 'Order not found' };

    const linkedTables = await (this.prisma as any).table.findMany({
      where: { activeOrderId: Number(id) },
      orderBy: [{ floor: 'asc' }, { tableNumber: 'asc' }],
    });
    const tableNumbers = linkedTables.map((t: { tableNumber: string }) =>
      String(t.tableNumber).trim(),
    ).filter((n: string) => n.length > 0);
    const linkedFloor =
      linkedTables.length > 0
        ? String(linkedTables[0].floor ?? '').trim()
        : '';

    const itemsSubtotal = order.items.reduce(
      (sum, it) => sum + Number(it.price) * it.quantity,
      0,
    );
    const discount = Number(order.discountAmount ?? 0);
    const includeServiceFee =
      feeSettings.serviceFeeAvailable && order.includeServiceFee === true;
    const feeRate = includeServiceFee
      ? Number(order.serviceFeePercent ?? feeSettings.serviceFeePercent) / 100
      : 0;
    const serviceFee = includeServiceFee
      ? Math.round(itemsSubtotal * feeRate * 100) / 100
      : 0;
    const totalAmount =
      Math.round((itemsSubtotal + serviceFee - discount) * 100) / 100;

    return {
      ...order,
      posOrderId: order.posOrderId,
      tableNumbers,
      floor: linkedFloor || order.floor || 'first',
      totalAmount,
      includeServiceFee,
      discountAmount: discount,
      serviceFeePercent: Number(order.serviceFeePercent),
    };
  }

  // POST /mobile/order/:id
  @Post('order/:id')
  async updateOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: any,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { posOrderId: Number(id) },
    });
    if (!order) return { success: false };

    const previousItems = await this.prisma.orderItem.findMany({
      where: { orderId: order.id },
    });

    await (this.prisma as any).orderItem.deleteMany({ where: { orderId: order.id } });
    for (const item of body.items ?? []) {
      await (this.prisma as any).orderItem.create({
        data: {
          orderId: order.id,
          name: item.itemName ?? item.name ?? '',
          quantity: item.quantity ?? 1,
          price: item.unitPrice ?? item.price ?? 0,
        },
      });
    }

    // Mobile can toggle service fee; fall back to stored value if not sent
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const requestedInclude =
      typeof body.includeServiceFee === 'boolean'
        ? body.includeServiceFee
        : order.includeServiceFee;
    const includeServiceFee =
      feeSettings.serviceFeeAvailable && requestedInclude === true;

    // Recalculate total server-side
    const itemsSubtotal = (body.items ?? []).reduce(
      (sum: number, it: any) =>
        sum + (it.unitPrice ?? it.price ?? 0) * (it.quantity ?? 1),
      0,
    );
    const feeRate = includeServiceFee
      ? Number(order.serviceFeePercent ?? feeSettings.serviceFeePercent) / 100
      : 0;
    const serviceFee = includeServiceFee ? itemsSubtotal * feeRate : 0;
    const discount = Number(order.discountAmount ?? 0);
    const newTotal =
      Math.round((itemsSubtotal + serviceFee - discount) * 100) / 100;

    const prevIncludeServiceFee = order.includeServiceFee === true;
    const prevTotal = Number(order.totalAmount ?? 0);

    await this.prisma.order.update({
      where: { id: order.id },
      data: {
        totalAmount: newTotal > 0 ? newTotal : 0,
        includeServiceFee,
      },
    });

    const tableNumbers = Array.isArray(body.tableNumbers)
      ? body.tableNumbers.map((t: unknown) => String(t))
      : [];
    const floor =
      typeof body.floor === 'string' && body.floor.trim().length > 0
        ? body.floor
        : order.floor ?? 'first';
    if (tableNumbers.length > 0 && newTotal >= 0) {
      for (const rawNum of tableNumbers) {
        const tableNumber = String(rawNum)
          .replace(/^table\s*/i, '')
          .trim();
        if (!tableNumber) continue;
        await (this.prisma as any).table.updateMany({
          where: { tableNumber, floor },
          data: { currentBill: newTotal > 0 ? newTotal : 0 },
        });
      }
    }

    const performer = String(
      body.updatedBy ?? body.waiterName ?? 'მობილური მენეჯერი',
    ).trim();
    const performerName = performer.length > 0 ? performer : 'მობილური მენეჯერი';
    const posOrderId = Number(id);
    this.registerMobileMutationEchoGuard(posOrderId);

    const auditEvents = buildAuditEventsForOrderDiff({
      previousItems: previousItems.map((it) => ({
        name: it.name,
        quantity: it.quantity,
        price: it.price,
      })),
      updatedItems: body.items ?? [],
      performerId: performerName,
      performerName,
    });
    if (auditEvents.length > 0) {
      await this.appendAuditEventsForPosOrder({
        posOrderId,
        tableNumbers: Array.isArray(body.tableNumbers)
          ? body.tableNumbers.map((t: unknown) => String(t))
          : [],
        floor: typeof body.floor === 'string' ? body.floor : order.floor,
        openedByName: order.waiterName || performerName,
        events: auditEvents,
      });
      this.gateway.broadcastUpdate(
        'audit_updated',
        { count: auditEvents.length, source: 'mobile', posOrderId },
        this.wsExcludeOpts(monitoringSocketId),
      );
    }

    this.gateway.broadcastUpdate(
      'order_updated',
      { posOrderId, source: 'mobile_manager' },
      this.wsExcludeOpts(monitoringSocketId),
    );

    const feeChanged = prevIncludeServiceFee !== includeServiceFee;
    const totalChanged = Math.abs(prevTotal - newTotal) > 0.009;
    if (feeChanged || totalChanged) {
      const tableLabel = tableNumbers
        .map((t) =>
          String(t)
            .replace(/^table\s*/i, '')
            .trim(),
        )
        .filter((t) => t.length > 0)
        .join(', ');
      const changeSummary = feeChanged
        ? includeServiceFee
          ? 'სერვისის საფასური ჩართულია'
          : 'სერვისის საფასური გამორთულია'
        : 'თანხა განახლდა';
      this.gateway.broadcastUpdate(
        'orders_bulk_touch',
        {
          touches: [
            {
              posOrderId,
              tableLabel,
              floor,
              changeSummary,
              changeKind: feeChanged ? 'service_fee' : 'total',
              occurredAt: new Date().toISOString(),
            },
          ],
          posOrderIds: [posOrderId],
          source: 'mobile_manager',
        },
        this.wsExcludeOpts(monitoringSocketId),
      );
      this.gateway.broadcastUpdate(
        'table_updated',
        { source: 'mobile_manager' },
        this.wsExcludeOpts(monitoringSocketId),
      );
    }

    // Push change back to the Windows POS (durable outbox — retried until delivered)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-update',
      posOrderId,
      payload: {
        posOrderId,
        updatedBy: performerName,
        items: (body.items ?? []).map((it: any) => ({
          name: it.itemName ?? it.name ?? '',
          quantity: it.quantity ?? 1,
          unitPrice: it.unitPrice ?? it.price ?? 0,
          price: it.unitPrice ?? it.price ?? 0,
          total: (it.unitPrice ?? it.price ?? 0) * (it.quantity ?? 1),
          itemKey: it.itemKey ?? it.itemName ?? it.name ?? '',
          itemName: it.itemName ?? it.name ?? '',
        })),
        totalAmount: newTotal > 0 ? newTotal : 0,
        includeServiceFee,
      },
    });

    return { success: true };
  }

  /** Append audit line events for a POS order (mobile manager edits). */
  private async appendAuditEventsForPosOrder(params: {
    posOrderId: number;
    tableNumbers: string[];
    floor: string;
    openedByName: string;
    events: import('./pos/audit/audit-order-diff').AuditEventInput[];
  }) {
    const { posOrderId, tableNumbers, floor, openedByName, events } = params;
    if (events.length === 0) return;

    const reportId = `audit_report_order_${posOrderId}`;
    const now = new Date();
    const prisma = this.prisma as any;

    let dbReport = await prisma.auditReport.findUnique({ where: { reportId } });
    if (!dbReport) {
      dbReport = await prisma.auditReport.create({
        data: {
          reportId,
          posOrderId,
          tableNumbers,
          floor: floor || 'first',
          openedById: openedByName,
          openedByName,
          openedAt: now,
          status: 'OPEN',
          locked: false,
        },
      });
    }

    const existing = await prisma.auditEvent.findMany({
      where: { reportId: dbReport.id },
      orderBy: { seq: 'asc' },
    });
    const startSeq = existing.length;

    await prisma.auditEvent.createMany({
      data: events.map((ev, seq) => ({
        reportId: dbReport.id,
        type: normalizeAuditEventType(ev.type, ev.previousQty, ev.newQty),
        itemName: ev.itemName,
        previousQty: ev.previousQty,
        newQty: ev.newQty,
        waiterId: ev.waiterId,
        waiterName: ev.waiterName,
        eventTime: now,
        note: ev.note ?? null,
        seq: startSeq + seq,
      })),
    });

    await prisma.auditReport.update({
      where: { id: dbReport.id },
      data: { updatedAt: now },
    });
  }

  // POST /mobile/order/:id/cancel
  @Post('order/:id/cancel')
  async cancelOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId },
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.registerMobileMutationEchoGuard(posOrderId);

    // Capture which tables this order held before we release them, so the
    // cancellation notification can say which table was freed.
    const heldTables = await (this.prisma as any).table.findMany({
      where: { activeOrderId: posOrderId },
      select: { tableNumber: true },
    });
    const tableLabel = heldTables
      .map((t: any) => String(t.tableNumber).trim())
      .filter((t: string) => t.length > 0)
      .join(', ');

    await this.prisma.order.update({
      where: { id: order.id },
      data: { status: 'cancelled' },
    });

    // Free the table that was holding this order so it no longer shows as occupied
    await (this.prisma as any).table.updateMany({
      where: { activeOrderId: posOrderId },
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });

    this.gateway.broadcastUpdate(
      'order_cancelled',
      {
        posOrderId,
        floor: order.floor,
        ...(tableLabel.length > 0 ? { tableLabel } : {}),
      },
      this.wsExcludeOpts(monitoringSocketId),
    );

    // Tell the Windows POS to mark this order as cancelled in Hive (NOT delete — cancel shows on both sides)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-status',
      posOrderId,
      payload: { posOrderId, status: 'cancelled' },
    });

    return { success: true };
  }

  // POST /mobile/takeaway-orders — create a new takeaway order from the mobile app
  @Post('takeaway-orders')
  async createTakeawayOrder(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: {
    customerName: string;
    pickupTime: string;
    waiterName: string;
    items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    // Resolve current business date
    const bdSetting = await (this.prisma as any).setting.findUnique({ where: { key: 'currentBusinessDate' } });
    const businessDate: string = bdSetting?.value ?? new Date().toISOString().slice(0, 10);

    const totalAmount = body.items.reduce((s, it) => s + it.unitPrice * it.quantity, 0);

    // Allocate a posOrderId and create the order, retrying on the (rare) race
    // where two mobile requests grabbed the same id.
    let order: any;
    for (let attempt = 0; ; attempt++) {
      const candidateId = await this.allocateMobileOrderId();
      this.registerMobileMutationEchoGuard(candidateId);
      try {
        order = await this.prisma.order.create({
          data: {
            posOrderId: candidateId,
            status: 'pending',
            totalAmount: Math.round(totalAmount * 100) / 100,
            guestCount: 1,
            waiterName: body.waiterName,
            floor: 'takeaway',
            businessDate,
            customerName: body.customerName,
            customerPhone: '-',
            pickupTime: body.pickupTime,
            items: {
              create: body.items.map(it => ({
                name: it.itemName,
                quantity: it.quantity,
                price: it.unitPrice,
              })),
            },
          },
          include: { items: true },
        });
        break;
      } catch (e) {
        if (this.isPosOrderIdConflict(e) && attempt < 5) continue;
        throw e;
      }
    }
    const nextId = order.posOrderId;

    this.gateway.broadcastUpdate(
      'takeaway_created',
      {
        posOrderId: nextId,
        customerName: body.customerName,
        pickupTime: body.pickupTime,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );

    // Push to Windows POS in real-time so it appears immediately (durable outbox)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-create',
      posOrderId: nextId,
      payload: {
        posOrderId: nextId,
        customerName: body.customerName,
        pickupTime: body.pickupTime,
        waiterName: body.waiterName,
        businessDate,
        items: body.items,
        totalAmount: order.totalAmount,
      },
    });

    return {
      posOrderId: order.posOrderId,
      status: order.status,
      totalAmount: order.totalAmount,
      customerName: order.customerName,
      pickupTime: order.pickupTime,
      waiterName: order.waiterName,
      businessDate: order.businessDate,
      items: order.items.map((it: any) => ({
        itemName: it.name,
        unitPrice: it.price,
        quantity: it.quantity,
      })),
    };
  }

  // POST /mobile/walk-in-orders — create a dine-in (walk-in) order on table(s)
  @Post('walk-in-orders')
  async createWalkInOrder(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: {
      tableNumbers: (string | number)[];
      floor: string;
      waiterName: string;
      guestCount?: number;
      items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    const floor = (body.floor ?? 'first').toString().trim() || 'first';
    const tableNumbers = Array.isArray(body.tableNumbers)
      ? body.tableNumbers
          .map((t) => String(t).replace(/^table\s*/i, '').trim())
          .filter((t) => t.length > 0)
      : [];
    if (tableNumbers.length === 0) {
      throw new BadRequestException('Select at least one table');
    }
    if (!Array.isArray(body.items) || body.items.length === 0) {
      throw new BadRequestException('Add at least one item');
    }

    const bdSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const businessDate: string =
      bdSetting?.value ?? new Date().toISOString().slice(0, 10);

    const totalAmount =
      Math.round(
        body.items.reduce((s, it) => s + it.unitPrice * it.quantity, 0) * 100,
      ) / 100;
    const guestCount = Number(body.guestCount ?? 0);

    // Allocate a posOrderId and create the order, retrying on the (rare) race
    // where two mobile requests grabbed the same id.
    let order: any;
    for (let attempt = 0; ; attempt++) {
      const candidateId = await this.allocateMobileOrderId();
      // Suppress echo for the order and every reserved table.
      this.registerMobileMutationEchoGuard(candidateId);
      for (const tableNumber of tableNumbers) {
        this.registerMobileMutationEchoGuard(candidateId, { tableNumber, floor });
      }
      try {
        order = await this.prisma.order.create({
          data: {
            posOrderId: candidateId,
            status: 'pending',
            totalAmount,
            guestCount: guestCount > 0 ? guestCount : 1,
            waiterName: body.waiterName,
            floor,
            businessDate,
            customerName: 'Walk-in',
            customerPhone: '-',
            items: {
              create: body.items.map((it) => ({
                name: it.itemName,
                quantity: it.quantity,
                price: it.unitPrice,
              })),
            },
          },
          include: { items: true },
        });
        break;
      } catch (e) {
        if (this.isPosOrderIdConflict(e) && attempt < 5) continue;
        throw e;
      }
    }
    const nextId = order.posOrderId;

    // Reserve the tables in the server DB so mobile live-status reflects it.
    for (const tableNumber of tableNumbers) {
      await (this.prisma as any).table.upsert({
        where: { tableIdentifier: { tableNumber, floor } },
        update: { isReserved: true, activeOrderId: nextId, currentBill: totalAmount },
        create: {
          tableNumber,
          floor,
          isReserved: true,
          activeOrderId: nextId,
          currentBill: totalAmount,
        },
      });
    }

    this.gateway.broadcastUpdate(
      'order_created',
      {
        posOrderId: nextId,
        floor,
        tableNumbers,
        tableLabel: tableNumbers.join(', '),
        walkIn: true,
      },
      this.wsExcludeOpts(monitoringSocketId),
    );
    this.gateway.broadcastUpdate(
      'table_updated',
      { source: 'mobile' },
      this.wsExcludeOpts(monitoringSocketId),
    );

    // Deliver to the Windows POS (durable outbox) so it appears on a table.
    void this.posOutbox.enqueue({
      endpoint: '/mobile-walk-in-order-create',
      posOrderId: nextId,
      payload: {
        posOrderId: nextId,
        tableNumbers,
        floor,
        waiterName: body.waiterName,
        guestCount,
        businessDate,
        items: body.items,
        totalAmount,
      },
    });

    return {
      posOrderId: order.posOrderId,
      status: order.status,
      totalAmount: order.totalAmount,
      floor: order.floor,
      tableNumbers,
      waiterName: order.waiterName,
      businessDate: order.businessDate,
      items: order.items.map((it: any) => ({
        itemName: it.name,
        unitPrice: it.price,
        quantity: it.quantity,
      })),
    };
  }

  // DELETE /mobile/takeaway-orders/:id — fully remove a takeaway order from DB and POS
  @Delete('takeaway-orders/:id')
  async deleteTakeawayOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId },
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.registerMobileMutationEchoGuard(posOrderId);

    await this.prisma.order.delete({ where: { id: order.id } });

    this.gateway.broadcastUpdate(
      'takeaway_deleted',
      { posOrderId },
      this.wsExcludeOpts(monitoringSocketId),
    );

    // Tell POS to fully delete this order from Hive (durable outbox)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-cancel',
      posOrderId,
      payload: { posOrderId },
    });

    return { success: true };
  }

  // GET /mobile/takeaway-orders
  // Returns ALL takeaway orders for the current business day, matching Windows POS exactly.
  @Get('takeaway-orders')
  async getTakeawayOrders() {
    // Use the currentBusinessDate setting — same source Windows POS uses to filter.
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBD: string = businessDateSetting?.value ?? '';

    const orders = await this.prisma.order.findMany({
      where: {
        floor: 'takeaway',
        // Primary: match by stored businessDate (set during sync).
        // Fallback: if businessDate not yet populated (old orders), match by createdAt calendar day.
        ...(currentBD
          ? {
              OR: [
                { businessDate: currentBD },
                { businessDate: '', createdAt: { gte: (() => { const [y,m,d] = currentBD.split('-').map(Number); return new Date(y,m-1,d,0,0,0,0); })(), lt: (() => { const [y,m,d] = currentBD.split('-').map(Number); const s = new Date(y,m-1,d,0,0,0,0); s.setDate(s.getDate()+1); return s; })() } },
              ],
            }
          : {}),
      },
      orderBy: { createdAt: 'asc' },
      include: { items: true },
    });

    return orders.map((o: any) => ({
      posOrderId: o.posOrderId,
      status: o.status,
      totalAmount: Math.round(Number(o.totalAmount) * 100) / 100,
      waiterName: o.waiterName,
      guestCount: o.guestCount,
      customerPhone: o.customerPhone ?? '',
      customerName: o.customerName ?? '',
      pickupTime: o.pickupTime ?? '',
      createdAt: (o.createdAt as Date).toISOString(),
      items: (o.items ?? []).map((it: any) => ({
        itemKey: it.name,
        itemName: it.name,
        unitPrice: Math.round(Number(it.price) * 100) / 100,
        quantity: it.quantity,
        total: Math.round(Number(it.price) * it.quantity * 100) / 100,
      })),
    }));
  }

  // GET /mobile/menu
  @Get('menu')
  async getMenu() {
    const cats = await (this.prisma as any).menuCategory.findMany({
      include: {
        items: {
          include: { variants: true },
          orderBy: { sortOrder: 'asc' },
        },
        subcategories: {
          include: {
            items: {
              include: { variants: true },
              orderBy: { sortOrder: 'asc' },
            },
          },
          orderBy: { sortOrder: 'asc' },
        },
      },
      orderBy: { sortOrder: 'asc' },
    });
    return cats.map((cat: any) => ({
      slug: cat.slug,
      nameEn: cat.nameEn,
      nameKa: cat.nameKa,
      sendToKitchen: cat.sendToKitchen,
      items: (cat.items ?? []).map((it: any) => ({
        nameEn: it.nameEn,
        nameKa: it.nameKa,
        price: Math.round(it.price * 100) / 100,
        sendToKitchen: it.sendToKitchen,
        variants: (it.variants ?? []).map((v: any) => ({
          size: v.size,
          price: v.price,
        })),
      })),
      subcategories: (cat.subcategories ?? []).map((sub: any) => ({
        slug: sub.slug,
        nameEn: sub.nameEn,
        nameKa: sub.nameKa,
        items: (sub.items ?? []).map((it: any) => ({
          nameEn: it.nameEn,
          nameKa: it.nameKa,
          price: Math.round(it.price * 100) / 100,
          sendToKitchen: it.sendToKitchen,
          variants: (it.variants ?? []).map((v: any) => ({
            size: v.size,
            price: v.price,
          })),
        })),
      })),
    }));
  }

  // GET /mobile/users
  @Get('users')
  async getUsers() {
    return this.users.getUsers();
  }

  @Post('users')
  async createUser(
    @Body() payload: { username?: string; pinCode?: string; role?: string },
  ) {
    return this.users.createUser(payload);
  }

  @Post('users/:username/pin')
  async updateUserPin(
    @Param('username') usernameParam: string,
    @Body() payload: { pinCode?: string },
  ) {
    return this.users.updateUserPin(usernameParam, payload);
  }

  @Patch('users/:username')
  async renameUser(
    @Param('username') usernameParam: string,
    @Body() payload: { username?: string },
  ) {
    return this.users.renameUser(usernameParam, payload);
  }

  @Delete('users/:username')
  async deleteUser(@Param('username') usernameParam: string) {
    return this.users.deleteUser(usernameParam);
  }

  // GET /mobile/audit?year=2026&month=4&status=OPEN
  // Returns full AuditReports with events, grouped by day, for a given month.
  // If year/month are omitted, returns the most recent 90 days.
  @Get('audit')
  async getAuditLog(
    @Query('year') yearStr?: string,
    @Query('month') monthStr?: string,
    @Query('status') status?: string,
    @Query('all') allStr?: string,
  ) {
    const where: any = {};
    const includeAllHistory = allStr === '1' || allStr === 'true';

    if (yearStr && monthStr) {
      const y = parseInt(yearStr, 10);
      const m = parseInt(monthStr, 10);
      const from = new Date(y, m - 1, 1);
      const to = new Date(y, m, 1);
      // Match Windows: show reports with activity in this month (not only openedAt).
      where.OR = [
        { openedAt: { gte: from, lt: to } },
        { updatedAt: { gte: from, lt: to } },
        { events: { some: { eventTime: { gte: from, lt: to } } } },
      ];
    } else if (!includeAllHistory) {
      // default: last 90 days
      const from = new Date();
      from.setDate(from.getDate() - 90);
      where.openedAt = { gte: from };
    }

    if (status) {
      where.status = status.toUpperCase();
    }

    const reports = await (this.prisma as any).auditReport.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      include: {
        events: { orderBy: { seq: 'asc' } },
      },
    });

    return reports.map((r: any) => ({
      reportId: r.reportId,
      orderId: r.posOrderId,
      tableNumbers: r.tableNumbers ?? [],
      floor: r.floor,
      openedById: r.openedById,
      openedByName: r.openedByName,
      openedAt: (r.openedAt as Date).toISOString(),
      status: r.status, // OPEN | CLOSED | CANCELLED
      closedAt: r.closedAt ? (r.closedAt as Date).toISOString() : null,
      closedById: r.closedById ?? null,
      closedByName: r.closedByName ?? null,
      locked: r.locked,
      updatedAt: (r.updatedAt as Date).toISOString(),
      events: (r.events ?? []).map((ev: any) => ({
        type: normalizeAuditEventType(ev.type, ev.previousQty, ev.newQty),
        itemName: ev.itemName,
        previousQty: ev.previousQty,
        newQty: ev.newQty,
        waiterId: ev.waiterId,
        waiterName: ev.waiterName,
        timestamp: (ev.eventTime as Date).toISOString(),
        note: ev.note ?? null,
      })),
    }));
  }

  // GET /mobile/sales-report?period=today|week|month
  @Get('sales-report')
  async getSalesReport(
    @Query('period') period: string = 'today',
    @Query('month') month?: string,
  ) {
    const now = new Date();
    let from: Date;
    let where: any;
    let currentBusinessDate: string | null = null;

    if (period === 'all') {
      from = new Date(0);
      where = { status: { not: 'cancelled' } };
    } else if (period === 'week') {
      from = new Date(now);
      from.setDate(from.getDate() - 7);
      from.setHours(0, 0, 0, 0);
      where = { createdAt: { gte: from }, status: { not: 'cancelled' } };
    } else if (period === 'month') {
      const monthMatch = month?.match(/^(\d{4})-(\d{2})$/);
      if (monthMatch) {
        const y = Number(monthMatch[1]);
        const m = Number(monthMatch[2]);
        from = new Date(y, m - 1, 1);
        const to = new Date(y, m, 1);
        where = {
          createdAt: { gte: from, lt: to },
          status: { not: 'cancelled' },
        };
      } else {
        from = new Date(now.getFullYear(), now.getMonth(), 1);
        where = { createdAt: { gte: from }, status: { not: 'cancelled' } };
      }
    } else {
      // today = current business date
      const businessDateSetting = await (this.prisma as any).setting.findUnique({
        where: { key: 'currentBusinessDate' },
      });
      const resolvedBusinessDate =
        businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
      currentBusinessDate = resolvedBusinessDate;
      from = parseBusinessDateStart(resolvedBusinessDate);
      where = { ...businessDateWhere(resolvedBusinessDate), status: { not: 'cancelled' } };
    }

    const [orders, byWaiter, expenses] = await Promise.all([
      this.prisma.order.findMany({
        where,
        include: { items: true },
      }),
      this.prisma.order.groupBy({
        by: ['waiterName'],
        where,
        _sum: { totalAmount: true },
        _count: { id: true },
      }),
      this.prisma.expense.findMany({
        where:
          period === 'today' && currentBusinessDate
            ? {
                createdAt: {
                  gte: parseBusinessDateStart(currentBusinessDate),
                  lt: nextDay(parseBusinessDateStart(currentBusinessDate)),
                },
              }
            : { createdAt: { gte: from } },
        select: { amount: true, category: true },
      }),
    ]);

    const r = (n: number) => Math.round(n * 100) / 100;
    const totalRev = orders.reduce((s, o) => s + Number(o.totalAmount), 0);
    const paymentBreakdown: Record<string, number> = {};
    for (const o of orders) {
      const key = normalizePaymentType((o as any).paymentType);
      paymentBreakdown[key] = (paymentBreakdown[key] ?? 0) + Number(o.totalAmount);
    }
    const cashRev = paymentBreakdown['cash'] ?? 0;
    const cardRev = Object.entries(paymentBreakdown).reduce(
      (sum, [key, amount]) => (key.startsWith('card') ? sum + amount : sum),
      0,
    );
    const totalExpenses = expenses.reduce((sum, e) => sum + Number(e.amount), 0);
    const expenseBreakdownMap = new Map<string, number>();
    for (const e of expenses) {
      const key = (e.category ?? '').trim() || 'სხვა';
      expenseBreakdownMap.set(key, (expenseBreakdownMap.get(key) ?? 0) + Number(e.amount));
    }

    let effectiveTotalRevenue = totalRev;
    let effectiveOrderCount = orders.length;
    let effectiveCashRevenue = cashRev;
    let effectiveCardRevenue = cardRev;
    let effectivePaymentBreakdown: Record<string, number> = { ...paymentBreakdown };
    let effectiveTopItems: Array<{ name: string; qty: number; revenue: number }> | null =
      null;

    // For today, prefer Windows-POS sales summary (local closed-sales records)
    // when available, so mobile payment-method analytics match Windows exactly.
    if (period === 'today' && currentBusinessDate) {
      const summarySetting = await (this.prisma as any).setting.findUnique({
        where: { key: `salesSummary:${currentBusinessDate}` },
      });
      if (summarySetting?.value) {
        try {
          const summary = JSON.parse(summarySetting.value) as {
            totalRevenue?: number;
            orderCount?: number;
            cashRevenue?: number;
            cardRevenue?: number;
            paymentBreakdown?: Record<string, number>;
          };
          effectiveTotalRevenue = Number(summary.totalRevenue ?? effectiveTotalRevenue);
          effectiveOrderCount = Number(summary.orderCount ?? effectiveOrderCount);
          effectiveCashRevenue = Number(summary.cashRevenue ?? effectiveCashRevenue);
          effectiveCardRevenue = Number(summary.cardRevenue ?? effectiveCardRevenue);
          effectivePaymentBreakdown = {
            ...effectivePaymentBreakdown,
            ...(summary.paymentBreakdown ?? {}),
          };
        } catch {
          // Ignore malformed summary and keep DB-derived fallback values.
        }
      }
    }

    if (period === 'all') {
      const allTimeSetting = await (this.prisma as any).setting.findUnique({
        where: { key: 'salesSummary:all_time' },
      });
      if (allTimeSetting?.value) {
        try {
          const summary = JSON.parse(allTimeSetting.value) as {
            totalRevenue?: number;
            orderCount?: number;
            cashRevenue?: number;
            cardRevenue?: number;
            paymentBreakdown?: Record<string, number>;
            topItems?: Array<{ name: string; qty: number; revenue: number }>;
          };
          effectiveTotalRevenue = Number(summary.totalRevenue ?? effectiveTotalRevenue);
          effectiveOrderCount = Number(summary.orderCount ?? effectiveOrderCount);
          effectiveCashRevenue = Number(summary.cashRevenue ?? effectiveCashRevenue);
          effectiveCardRevenue = Number(summary.cardRevenue ?? effectiveCardRevenue);
          effectiveTopItems = Array.isArray(summary.topItems)
            ? summary.topItems
            : null;
          effectivePaymentBreakdown = {
            ...effectivePaymentBreakdown,
            ...(summary.paymentBreakdown ?? {}),
          };
        } catch {
          // Ignore malformed summary and keep DB-derived fallback values.
        }
      }
    }

    if (period === 'month' && month && /^\d{4}-\d{2}$/.test(month)) {
      const summaryRows = await (this.prisma as any).setting.findMany({
        where: { key: { startsWith: 'salesSummary:' } },
        select: { key: true, value: true },
      });
      const monthRows = summaryRows
        .filter((s: any) => s.key.startsWith(`salesSummary:${month}-`))
        .map((s: any) => {
          try {
            return JSON.parse(s.value);
          } catch {
            return null;
          }
        })
        .filter((x: any) => x != null);
      if (monthRows.length > 0) {
        let totalRevenue = 0;
        let orderCount = 0;
        const pb: Record<string, number> = {};
        const itemMap = new Map<string, { qty: number; revenue: number }>();
        for (const row of monthRows) {
          totalRevenue += Number(row.totalRevenue ?? 0);
          orderCount += Number(row.orderCount ?? 0);
          const pbd = (row.paymentBreakdown ?? {}) as Record<string, number>;
          Object.entries(pbd).forEach(([k, v]) => {
            pb[k] = (pb[k] ?? 0) + Number(v);
          });
          const tis = Array.isArray(row.topItems) ? row.topItems : [];
          for (const it of tis) {
            const name = String(it.name ?? '').trim();
            if (!name) continue;
            const cur = itemMap.get(name) ?? { qty: 0, revenue: 0 };
            cur.qty += Number(it.qty ?? 0);
            cur.revenue += Number(it.revenue ?? 0);
            itemMap.set(name, cur);
          }
        }
        effectiveTotalRevenue = totalRevenue;
        effectiveOrderCount = orderCount;
        effectiveCashRevenue = Number(pb['cash'] ?? 0);
        effectiveCardRevenue = Object.entries(pb).reduce(
          (sum, [k, v]) => (k.startsWith('card') ? sum + Number(v) : sum),
          0,
        );
        effectivePaymentBreakdown = pb;
        effectiveTopItems = Array.from(itemMap.entries())
          .sort((a, b) => b[1].revenue - a[1].revenue)
          .map(([name, s]) => ({
            name,
            qty: Math.round(s.qty),
            revenue: r(s.revenue),
          }));
      }
    }

    // Per-item aggregation
    const itemMap = new Map<string, { qty: number; revenue: number }>();
    for (const o of orders) {
      for (const it of (o as any).items ?? []) {
        const cur = itemMap.get(it.name) ?? { qty: 0, revenue: 0 };
        itemMap.set(it.name, {
          qty: cur.qty + it.quantity,
          revenue: cur.revenue + it.quantity * Number(it.price),
        });
      }
    }

    const allItemsSorted = Array.from(itemMap.entries())
      .sort((a, b) => b[1].revenue - a[1].revenue)
      .map(([name, s]) => ({ name, qty: s.qty, revenue: r(s.revenue) }));

    const topItems =
      effectiveTopItems != null && effectiveTopItems.length > 0
        ? effectiveTopItems
            .map((it) => ({
              name: it.name,
              qty: Number(it.qty ?? 0),
              revenue: r(Number(it.revenue ?? 0)),
            }))
            .slice(0, 10)
        : allItemsSorted.slice(0, 10);

    // Build category mapping so mobile report can expand sold items by categories.
    const menuItems = await (this.prisma as any).menuItem.findMany({
      select: {
        nameKa: true,
        nameEn: true,
        category: { select: { nameKa: true } },
        subcategory: { select: { nameKa: true } },
      },
    });
    const nameToCategory = new Map<string, string>();
    for (const it of menuItems) {
      const catName =
        it.subcategory?.nameKa ??
        it.category?.nameKa ??
        'სხვა';
      const ka = (it.nameKa ?? '').trim().toLowerCase();
      const en = (it.nameEn ?? '').trim().toLowerCase();
      if (ka) nameToCategory.set(ka, catName);
      if (en) nameToCategory.set(en, catName);
    }
    const itemsForCategoryGrouping =
      effectiveTopItems != null && effectiveTopItems.length > 0
        ? effectiveTopItems.map((it) => ({
            name: it.name,
            qty: Number(it.qty ?? 0),
            revenue: r(Number(it.revenue ?? 0)),
          }))
        : allItemsSorted;

    const topItemsWithCategory = itemsForCategoryGrouping.map((it) => {
      const key = (it.name ?? '').trim().toLowerCase();
      return {
        ...it,
        category: nameToCategory.get(key) ?? 'სხვა',
      };
    });
    const topItemsByCategoryMap = new Map<
      string,
      { totalRevenue: number; totalQty: number; items: Array<{ name: string; qty: number; revenue: number }> }
    >();
    for (const item of topItemsWithCategory) {
      const category = item.category;
      const cur = topItemsByCategoryMap.get(category) ?? {
        totalRevenue: 0,
        totalQty: 0,
        items: [],
      };
      cur.totalRevenue += item.revenue;
      cur.totalQty += item.qty;
      cur.items.push({ name: item.name, qty: item.qty, revenue: item.revenue });
      topItemsByCategoryMap.set(category, cur);
    }
    const topItemsByCategory = Array.from(topItemsByCategoryMap.entries())
      .map(([category, data]) => ({
        category,
        totalRevenue: r(data.totalRevenue),
        totalQty: data.totalQty,
        items: data.items.sort((a, b) => b.revenue - a.revenue),
      }))
      .sort((a, b) => b.totalRevenue - a.totalRevenue);

    return {
      period,
      from: from.toISOString(),
      to: now.toISOString(),
      totalRevenue: r(effectiveTotalRevenue),
      cashRevenue: r(effectiveCashRevenue),
      cardRevenue: r(effectiveCardRevenue),
      paymentBreakdown: Object.fromEntries(
        Object.entries(effectivePaymentBreakdown).map(([key, value]) => [key, r(value)]),
      ),
      orderCount: effectiveOrderCount,
      avgOrderValue:
        effectiveOrderCount > 0 ? r(effectiveTotalRevenue / effectiveOrderCount) : 0,
      totalExpenses: r(totalExpenses),
      profit: r(effectiveTotalRevenue - totalExpenses),
      expenseBreakdown: Array.from(expenseBreakdownMap.entries()).map(([category, amount]) => ({
        category,
        amount: r(amount),
      })),
      topItems,
      topItemsByCategory,
      byWaiter: byWaiter.map((w) => ({
        waiterName: w.waiterName,
        totalSales: r(Number(w._sum.totalAmount ?? 0)),
        orderCount: w._count.id,
      })),
    };
  }

  // GET /mobile/sales-daily?month=YYYY-MM
  @Get('sales-daily')
  async getSalesDaily(@Query('month') month?: string) {
    const expenses = await this.prisma.expense.findMany({
      select: { amount: true, createdAt: true },
    });
    const expensesByDate = new Map<string, number>();
    const dateKey = (d: Date) => {
      const y = d.getFullYear().toString().padStart(4, '0');
      const m = (d.getMonth() + 1).toString().padStart(2, '0');
      const day = d.getDate().toString().padStart(2, '0');
      return `${y}-${m}-${day}`;
    };
    for (const e of expenses) {
      // Use local date parts instead of UTC ISO split to avoid off-by-one-day
      // shifts for business dates in positive timezones (e.g. +04).
      const date = dateKey(e.createdAt as Date);
      expensesByDate.set(date, (expensesByDate.get(date) ?? 0) + Number(e.amount ?? 0));
    }
    const historyIndexSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'salesSummary:history_index' },
      select: { value: true },
    });
    const summaries = await (this.prisma as any).setting.findMany({
      where: { key: { startsWith: 'salesSummary:' } },
      select: { key: true, value: true },
    });
    const summaryByDate = new Map<string, any>();
    for (const s of summaries) {
      if (s.key === 'salesSummary:all_time') continue;
      const date = s.key.replace('salesSummary:', '');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
      try {
        summaryByDate.set(date, JSON.parse(s.value));
      } catch {
        // ignore malformed
      }
    }

    const orders = await this.prisma.order.findMany({
      select: {
        businessDate: true,
        status: true,
        totalAmount: true,
        paymentType: true,
        createdAt: true,
      },
    });
    const byDate = new Map<
      string,
      {
        totalOrders: number;
        cancelledOrders: number;
        nonCancelledTotal: number;
        paymentBreakdown: Record<string, number>;
      }
    >();
    const dateFromOrder = (o: any) =>
      (o.businessDate && o.businessDate.trim().length > 0
        ? o.businessDate
        : (o.createdAt as Date).toISOString().split('T')[0]) as string;
    for (const o of orders) {
      const date = dateFromOrder(o);
      const cur = byDate.get(date) ?? {
        totalOrders: 0,
        cancelledOrders: 0,
        nonCancelledTotal: 0,
        paymentBreakdown: {},
      };
      cur.totalOrders += 1;
      const isCancelled = (o.status ?? '').toLowerCase() === 'cancelled';
      if (isCancelled) {
        cur.cancelledOrders += 1;
      } else {
        const amount = Number(o.totalAmount ?? 0);
        cur.nonCancelledTotal += amount;
        const method = normalizePaymentType((o as any).paymentType);
        cur.paymentBreakdown[method] = (cur.paymentBreakdown[method] ?? 0) + amount;
      }
      byDate.set(date, cur);
    }

    const allDates = new Set<string>([
      ...Array.from(summaryByDate.keys()),
      ...Array.from(byDate.keys()),
    ]);
    if (historyIndexSetting?.value) {
      try {
        const indexedDates = JSON.parse(historyIndexSetting.value) as string[];
        for (const d of indexedDates) allDates.add(d);
      } catch {
        // ignore malformed index
      }
    }
    let rows = Array.from(allDates).map((date) => {
      const summary = summaryByDate.get(date) as any;
      const fallback = byDate.get(date) ?? {
        totalOrders: 0,
        cancelledOrders: 0,
        nonCancelledTotal: 0,
        paymentBreakdown: {},
      };
      return {
        date,
        totalRevenue: Number(summary?.totalRevenue ?? fallback.nonCancelledTotal ?? 0),
        closedOrders: Number(summary?.orderCount ?? (fallback.totalOrders - fallback.cancelledOrders)),
        cancelledOrders: fallback.cancelledOrders,
        totalOrders: fallback.totalOrders,
        paymentBreakdown: summary?.paymentBreakdown ?? fallback.paymentBreakdown,
        closedTables: Array.isArray(summary?.closedTables) ? summary.closedTables : [],
        totalExpenses:
          Math.round(
            Number(summary?.totalExpenses ?? expensesByDate.get(date) ?? 0) * 100,
          ) / 100,
        profit:
          Math.round(
            (Number(summary?.totalRevenue ?? fallback.nonCancelledTotal ?? 0) -
              Number(summary?.totalExpenses ?? expensesByDate.get(date) ?? 0)) *
              100,
          ) / 100,
      };
    });
    if (month && /^\d{4}-\d{2}$/.test(month)) {
      rows = rows.filter((r) => r.date.startsWith(month));
    }
    rows.sort((a, b) => b.date.localeCompare(a.date));
    return rows;
  }

  // GET /mobile/top-items?limit=10
  @Get('top-items')
  async getTopItems(
    @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
  ) {
    const today = todayStart();
    const items = await (this.prisma as any).orderItem.findMany({
      where: { order: { createdAt: { gte: today } } },
      select: { name: true, quantity: true, price: true },
    });

    const map = new Map<string, { qty: number; revenue: number }>();
    for (const item of items) {
      const cur = map.get(item.name) ?? { qty: 0, revenue: 0 };
      map.set(item.name, {
        qty: cur.qty + item.quantity,
        revenue: cur.revenue + item.quantity * Number(item.price),
      });
    }

    return Array.from(map.entries())
      .sort((a, b) => b[1].revenue - a[1].revenue)
      .slice(0, Math.min(limit, 50))
      .map(([name, stats]) => ({
        name,
        qty: stats.qty,
        revenue: Math.round(stats.revenue * 100) / 100,
      }));
  }

  // GET /mobile/counted-menus
  @Get('counted-menus')
  async getCountedMenus() {
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const drafts = await (this.prisma as any).quickOrderDraft.findMany({
      include: { items: true },
      orderBy: { createdAt: 'desc' },
    });

    return drafts.map((d: any) => {
      const subtotal = Number(d.subtotal);
      const includeServiceFee =
        feeSettings.serviceFeeAvailable && d.includeServiceFee === true;
      const serviceFeeRate = includeServiceFee
        ? Number(d.serviceFeeRate ?? feeSettings.serviceFeePercent / 100)
        : 0;
      const serviceFeeAmount = includeServiceFee
        ? Math.round(subtotal * serviceFeeRate * 100) / 100
        : 0;
      const total = Math.round((subtotal + serviceFeeAmount) * 100) / 100;

      return {
        id: d.draftId,
        displayName: d.displayName,
        subtotal,
        serviceFeeAmount,
        total,
        includeServiceFee,
        serviceFeeRate,
        createdAt: d.createdAt.toISOString(),
        createdBy: d.createdBy,
        items: d.items.map((it: any) => ({
          itemName: it.name,
          quantity: it.quantity,
          unitPrice: it.price,
          total: it.quantity * it.price,
          comment: it.comment,
        })),
      };
    });
  }

  // POST /mobile/counted-menu/save
  @Post('counted-menu/save')
  async saveCountedMenu(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() data: any,
  ) {
    const { displayName, items, subtotal, includeServiceFee, createdBy } = data;
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const shouldInclude =
      feeSettings.serviceFeeAvailable && includeServiceFee === true;
    const serviceFeeRate = feeSettings.serviceFeeAvailable
      ? feeSettings.serviceFeePercent / 100
      : 0;
    const serviceFeeAmount = shouldInclude ? subtotal * serviceFeeRate : 0;
    const total = subtotal + serviceFeeAmount;

    const dbDraft = await (this.prisma as any).quickOrderDraft.create({
      data: {
        draftId: uuidv4(),
        displayName,
        subtotal,
        serviceFeeAmount,
        total,
        includeServiceFee: shouldInclude,
        serviceFeeRate,
        createdBy,
        createdAt: new Date(),
      },
    });

    for (const item of items) {
      await (this.prisma as any).quickOrderDraftItem.create({
        data: {
          draftId: dbDraft.id,
          name: item.itemName,
          quantity: item.quantity,
          price: item.unitPrice,
          comment: item.comment,
        },
      });
    }

    this.gateway.broadcastUpdate(
      'data_updated',
      { type: 'all' },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true, id: dbDraft.draftId };
  }

  // POST /mobile/counted-menu/:id/delete
  @Post('counted-menu/:id/delete')
  async deleteCountedMenu(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    await (this.prisma as any).quickOrderDraft.delete({
      where: { draftId: id },
    });
    this.gateway.broadcastUpdate(
      'data_updated',
      { type: 'all' },
      this.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  /** Do not push WS notifications back to the REST client that initiated the action. */
  private wsExcludeOpts(monitoringSocketId?: string):
    | { excludeSocketIds: string[] }
    | undefined {
    const id = monitoringSocketId?.trim();
    return id ? { excludeSocketIds: [id] } : undefined;
  }

  /** Block POS round-trip WS notifications after this mobile mutation. */
  private registerMobileMutationEchoGuard(
    posOrderId?: number,
    options?: { tableNumber?: string; floor?: string },
  ): void {
    if (posOrderId !== undefined && Number.isFinite(posOrderId)) {
      suppressPosEchoForOrder(posOrderId);
    }
    suppressPosAuditBroadcast();
    const tableNumber = options?.tableNumber?.trim();
    const floor = options?.floor?.trim() ?? 'first';
    if (tableNumber && tableNumber.length > 0) {
      suppressPosEchoForTable(tableNumber, floor);
    }
  }

  /// Allocate a collision-safe posOrderId for a mobile-originated order.
  /// Uses the greater of the persisted counter and the current max posOrderId
  /// already in the DB (never below 90001), then advances the counter. This
  /// survives counter drift and orders synced up from the POS that already sit
  /// in the mobile id range.
  private async allocateMobileOrderId(): Promise<number> {
    const counterKey = 'mobileOrderIdCounter';
    const [counterSetting, maxAgg] = await Promise.all([
      (this.prisma as any).setting.findUnique({ where: { key: counterKey } }),
      this.prisma.order.aggregate({ _max: { posOrderId: true } }),
    ]);
    const counterValue = counterSetting ? Number(counterSetting.value) : 0;
    const maxExisting = Number((maxAgg as any)?._max?.posOrderId ?? 0);
    const nextId = Math.max(counterValue + 1, maxExisting + 1, 90001);
    await (this.prisma as any).setting.upsert({
      where: { key: counterKey },
      update: { value: String(nextId) },
      create: { key: counterKey, value: String(nextId) },
    });
    return nextId;
  }

  /// True when a Prisma error is a unique-constraint violation on posOrderId,
  /// i.e. two requests raced for the same mobile id.
  private isPosOrderIdConflict(error: unknown): boolean {
    const e = error as { code?: string; meta?: { target?: unknown } };
    if (e?.code !== 'P2002') return false;
    const target = e?.meta?.target;
    if (Array.isArray(target)) return target.includes('posOrderId');
    return String(target ?? '').includes('posOrderId');
  }
}

