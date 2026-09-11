jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { MobileDashboardService } from './mobile-dashboard.service';
import { MobileReportsService } from './mobile-reports.service';
import type { TenantContext } from '../../tenancy/tenant-context';

const tenant: TenantContext = {
  venueId: 'venue-a',
  organizationId: 'org-a',
};

type Fixture = {
  settings?: Record<string, unknown>;
  summaryRows?: Array<{ key: string; value: string }>;
  openOrders?: any[];
  tables?: any[];
  expenses?: any[];
};

function makePrisma(fixture: Fixture = {}) {
  const settings = fixture.settings ?? {};
  return {
    setting: {
      findUnique: jest.fn(({ where }: any) => {
        const key = where.venueId_key?.key;
        const value = settings[key];
        if (value === undefined) return Promise.resolve(null);
        return Promise.resolve({ value: String(value) });
      }),
      findMany: jest.fn(() => Promise.resolve(fixture.summaryRows ?? [])),
    },
    order: {
      findMany: jest.fn((args: any) => {
        if (args?.select?.posOrderId) {
          return Promise.resolve(fixture.openOrders ?? []);
        }
        throw new Error('Raw Order revenue query is forbidden');
      }),
      groupBy: jest.fn(() => {
        throw new Error('Raw Order waiter revenue query is forbidden');
      }),
    },
    orderItem: {
      findMany: jest.fn(() => {
        throw new Error('Raw OrderItem revenue query is forbidden');
      }),
    },
    table: {
      findMany: jest.fn(() => Promise.resolve(fixture.tables ?? [])),
    },
    venue: {
      findUniqueOrThrow: jest
        .fn()
        .mockResolvedValue({ timezone: 'Asia/Tbilisi' }),
    },
    payrollPayment: {
      aggregate: jest.fn().mockResolvedValue({ _sum: { amount: null } }),
    },
    obligationPayment: {
      aggregate: jest.fn().mockResolvedValue({ _sum: { amount: null } }),
    },
    supplierPayment: {
      aggregate: jest.fn().mockResolvedValue({ _sum: { amount: null } }),
    },
    receiving: {
      findMany: jest.fn().mockResolvedValue([]),
      aggregate: jest
        .fn()
        .mockResolvedValue({ _sum: { documentTotal: null }, _count: 0 }),
    },
    expense: {
      findMany: jest.fn(() => Promise.resolve(fixture.expenses ?? [])),
    },
    menuItem: {
      findMany: jest.fn(() => Promise.resolve([])),
    },
  } as any;
}

function reports(prisma: any) {
  return new MobileReportsService(prisma);
}

function dashboard(prisma: any) {
  return new MobileDashboardService(prisma, {} as any, {} as any, {} as any);
}

describe('Manager Sale-derived revenue truth', () => {
  const date = '2026-09-04';

  it.each([
    {
      name: 'cash',
      summary: {
        totalRevenue: 100,
        orderCount: 1,
        cashRevenue: 100,
        cardRevenue: 0,
        paymentBreakdown: { cash: 100 },
      },
    },
    {
      name: 'card',
      summary: {
        totalRevenue: 100,
        orderCount: 1,
        cashRevenue: 0,
        cardRevenue: 100,
        paymentBreakdown: { 'card-tbc': 100 },
      },
    },
    {
      name: 'split',
      summary: {
        totalRevenue: 100,
        orderCount: 1,
        cashRevenue: 40,
        cardRevenue: 60,
        paymentBreakdown: { cash: 40, 'card-bog': 60 },
      },
    },
    {
      name: 'advance plus cash',
      summary: {
        totalRevenue: 100,
        orderCount: 1,
        cashRevenue: 80,
        cardRevenue: 0,
        paymentBreakdown: { cash: 80, advance: 20 },
      },
    },
  ])('preserves gross revenue for $name', async ({ summary }) => {
    const prisma = makePrisma({
      settings: {
        currentBusinessDate: date,
        [`salesSummary:${date}`]: JSON.stringify(summary),
      },
    });

    const result = await reports(prisma).getSalesReport(tenant, 'today');

    expect(result.totalRevenue).toBe(100);
    expect(result.orderCount).toBe(1);
    expect(result.cashRevenue).toBe(summary.cashRevenue);
    expect(result.cardRevenue).toBe(summary.cardRevenue);
    expect(result.paymentBreakdown).toEqual(summary.paymentBreakdown);
    expect(prisma.order.findMany).not.toHaveBeenCalled();
    expect(prisma.order.groupBy).not.toHaveBeenCalled();
  });

  it('fails closed when only raw open/cancelled/internal/restored Orders exist', async () => {
    const prisma = makePrisma({
      settings: { currentBusinessDate: date },
    });

    const result = await reports(prisma).getSalesReport(tenant, 'today');

    expect(result.totalRevenue).toBe(0);
    expect(result.orderCount).toBe(0);
    expect(result.paymentBreakdown).toEqual({});
    expect(result.topItems).toEqual([]);
    expect(result.byWaiter).toEqual([]);
    expect(prisma.order.findMany).not.toHaveBeenCalled();
    expect(prisma.order.groupBy).not.toHaveBeenCalled();
  });

  it('uses the same Sale-derived rows for daily and monthly revenue', async () => {
    const fiscal = {
      date: '2026-09-04',
      totalRevenue: 100,
      orderCount: 1,
      totalOrders: 1,
      cancelledOrders: 0,
      cashRevenue: 40,
      cardRevenue: 60,
      paymentBreakdown: { cash: 40, 'card-bog': 60 },
      topItems: [{ name: 'Fiscal', qty: 1, revenue: 100 }],
      totalExpenses: 0,
    };
    const internalOnly = {
      date: '2026-09-05',
      totalRevenue: 0,
      orderCount: 0,
      totalOrders: 1,
      cancelledOrders: 0,
      cashRevenue: 0,
      cardRevenue: 0,
      paymentBreakdown: {},
      topItems: [],
      totalExpenses: 0,
    };
    const rows = [fiscal, internalOnly].map((summary) => ({
      key: `salesSummary:${summary.date}`,
      value: JSON.stringify(summary),
    }));
    rows.push({
      key: 'salesSummary:2026-09-01',
      value: JSON.stringify({
        date: '2026-09-01',
        totalRevenue: 999,
        orderCount: 1,
        paymentBreakdown: { cash: 999 },
      }),
    });
    const prisma = makePrisma({
      settings: {
        'salesSummary:history_index': JSON.stringify([
          fiscal.date,
          internalOnly.date,
        ]),
      },
      summaryRows: rows,
    });

    const daily = await reports(prisma).getSalesDaily(tenant, '2026-09');
    const monthly = await reports(prisma).getSalesReport(
      tenant,
      'month',
      '2026-09',
    );

    expect(daily).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ date: fiscal.date, totalRevenue: 100 }),
        expect.objectContaining({
          date: internalOnly.date,
          totalRevenue: 0,
        }),
      ]),
    );
    expect(monthly.totalRevenue).toBe(100);
    expect(monthly.orderCount).toBe(1);
    expect(monthly.paymentBreakdown).toEqual({ cash: 40, 'card-bog': 60 });
    expect(daily).not.toEqual(
      expect.arrayContaining([expect.objectContaining({ date: '2026-09-01' })]),
    );
    expect(prisma.order.findMany).not.toHaveBeenCalled();
  });

  it('uses the Sale-derived all-time summary without an Order fallback', async () => {
    const prisma = makePrisma({
      settings: {
        'salesSummary:all_time': JSON.stringify({
          totalRevenue: 100,
          orderCount: 1,
          cashRevenue: 80,
          cardRevenue: 0,
          paymentBreakdown: { cash: 80, advance: 20 },
          topItems: [{ name: 'Fiscal', qty: 1, revenue: 100 }],
        }),
      },
    });

    const result = await reports(prisma).getSalesReport(tenant, 'all');

    expect(result.totalRevenue).toBe(100);
    expect(result.cashRevenue).toBe(80);
    expect(result.paymentBreakdown).toEqual({ cash: 80, advance: 20 });
    expect(result.topItems).toEqual([{ name: 'Fiscal', qty: 1, revenue: 100 }]);
    expect(prisma.order.findMany).not.toHaveBeenCalled();
  });

  it('keeps open-table payable separate from dashboard revenue', async () => {
    const todaySummary = {
      totalRevenue: 100,
      orderCount: 1,
      cashRevenue: 100,
      cardRevenue: 0,
      paymentBreakdown: { cash: 100, 'non-fiscal': 900 },
    };
    const prisma = makePrisma({
      settings: {
        currentBusinessDate: date,
        [`salesSummary:${date}`]: JSON.stringify(todaySummary),
        'salesSummary:2026-09-03': JSON.stringify({ totalRevenue: 50 }),
      },
      openOrders: [{ posOrderId: 99, totalAmount: 800, businessDate: date }],
      tables: [
        {
          id: 'table-1',
          tableNumber: '1',
          floor: 'first',
          currentBill: 900,
          isReserved: true,
          activeOrderId: 99,
        },
      ],
    });

    const result = await dashboard(prisma).getDashboard(tenant);

    expect(result.todayRevenue).toBe(100);
    expect(result.closedTablesRevenue).toBe(100);
    expect(result.shiftTotalRevenue).toBe(100);
    expect(result.openTablesPayable).toBe(900);
    expect(result.nonFiscalClosedRevenue).toBe(900);
    expect(result.yesterdayRevenue).toBe(50);
  });

  it('does not turn an open Order into dashboard revenue without a summary', async () => {
    const prisma = makePrisma({
      settings: { currentBusinessDate: date },
      openOrders: [{ posOrderId: 99, totalAmount: 900, businessDate: date }],
      tables: [
        {
          id: 'table-1',
          tableNumber: '1',
          floor: 'first',
          currentBill: 900,
          isReserved: true,
          activeOrderId: 99,
        },
      ],
    });

    const result = await dashboard(prisma).getDashboard(tenant);

    expect(result.todayRevenue).toBe(0);
    expect(result.closedTablesRevenue).toBe(0);
    expect(result.shiftTotalRevenue).toBe(0);
    expect(result.openTablesPayable).toBe(900);
  });

  it('builds financials from the Sale-derived summary and expenses', async () => {
    const prisma = makePrisma({
      settings: {
        currentBusinessDate: date,
        [`salesSummary:${date}`]: JSON.stringify({
          totalRevenue: 100,
          orderCount: 1,
          cashRevenue: 80,
          cardRevenue: 0,
          paymentBreakdown: { cash: 80, advance: 20 },
        }),
      },
      expenses: [
        {
          id: 'expense-1',
          description: 'Supplies',
          category: 'supplies',
          amount: 25,
          paymentType: 'cash',
          createdAt: new Date('2026-09-04T12:00:00.000Z'),
        },
      ],
    });

    const result = await dashboard(prisma).getFinancials(tenant);

    expect(result.revenue).toBe(100);
    expect(result.cashRevenue).toBe(80);
    expect(result.cardRevenue).toBe(0);
    expect(result.orderCount).toBe(1);
    expect(result.expenses).toBe(25);
    expect(result.profit).toBe(75);
    expect(prisma.order.findMany).not.toHaveBeenCalled();
  });

  it('returns unavailable staff/top-item revenue instead of raw Order totals', async () => {
    const prisma = makePrisma({
      settings: { currentBusinessDate: date },
    });
    const service = dashboard(prisma);

    await expect(service.getStaffPerformance(tenant)).resolves.toEqual([]);
    await expect(reports(prisma).getTopItems(tenant, 10)).resolves.toEqual([]);
    expect(prisma.order.findMany).not.toHaveBeenCalled();
    expect(prisma.orderItem.findMany).not.toHaveBeenCalled();
  });
});
