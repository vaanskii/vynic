jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../auth/pos-auth-context';
import { BusinessDaySyncService } from './business-day-sync.service';
import { OrderSyncService } from './order-sync.service';

/**
 * The database-level half of money reconciliation.
 *
 * The mocked-Prisma spec proves the ingestion code upserts on the right key.
 * Only a real PostgreSQL proves the constraint behind that key exists and is
 * venue-scoped — and that resending the POS's whole expense snapshot, which is
 * what every full sync does, leaves one row per expense rather than a month's
 * worth of duplicates.
 *
 * Skipped unless `TENANT_INTEGRATION_DATABASE_URL` points at a disposable
 * database with the migrations applied.
 */
const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('POS money reconciliation (PostgreSQL)', () => {
  let prisma: PrismaService;
  let orders: OrderSyncService;
  let businessDay: BusinessDaySyncService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `1a000000-0000-4000-8000-${suffix}`;
  const venueA: TenantContext = {
    venueId: `1a000001-0000-4000-8000-${suffix}`,
    organizationId,
  };
  const venueB: TenantContext = {
    venueId: `1a000002-0000-4000-8000-${suffix}`,
    organizationId,
  };

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Money reconciliation fixture',
        venues: {
          create: [
            {
              id: venueA.venueId,
              name: 'Venue A',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
            {
              id: venueB.venueId,
              name: 'Venue B',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
          ],
        },
      },
    });
    orders = new OrderSyncService(prisma);
    businessDay = new BusinessDaySyncService(prisma);
  });

  afterEach(async () => {
    const venueIds = [venueA.venueId, venueB.venueId];
    await prisma.expense.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.orderItem.deleteMany({
      where: { order: { venueId: { in: venueIds } } },
    });
    await prisma.order.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.setting.deleteMany({ where: { venueId: { in: venueIds } } });
  });

  afterAll(async () => {
    await prisma.venue.deleteMany({ where: { organizationId } });
    await prisma.organization.deleteMany({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  it('stores the order adjustment and keeps the total reconcilable', async () => {
    await orders.sync(
      venueA,
      [
        {
          posOrderId: 900,
          status: 'closed',
          totalAmount: 94.5,
          includeServiceFee: true,
          serviceFeePercent: 10,
          discountAmount: 10,
          manualAdjustmentAmount: -5.5,
          items: [{ name: 'ლუდი', quantity: 2, price: 50 }],
        },
      ],
      '2026-05-10',
    );

    const stored = await prisma.order.findUnique({
      where: {
        venueId_posOrderId: { venueId: venueA.venueId, posOrderId: 900 },
      },
      include: { items: true },
    });

    expect(stored).not.toBeNull();
    expect(stored!.manualAdjustmentAmount).toBeCloseTo(-5.5, 2);
    const itemsTotal = stored!.items.reduce(
      (sum, item) => sum + item.price * item.quantity,
      0,
    );
    const reconciled =
      itemsTotal * (1 + stored!.serviceFeePercent / 100) -
      stored!.discountAmount +
      stored!.manualAdjustmentAmount;
    expect(reconciled).toBeCloseTo(stored!.totalAmount, 2);
  });

  it('defaults an order synced without the field to no adjustment', async () => {
    await orders.sync(
      venueA,
      [{ posOrderId: 901, status: 'open', totalAmount: 40 }],
      '2026-05-10',
    );

    const stored = await prisma.order.findUnique({
      where: {
        venueId_posOrderId: { venueId: venueA.venueId, posOrderId: 901 },
      },
    });
    expect(stored!.manualAdjustmentAmount).toBe(0);
  });

  it('re-ingesting the same expense snapshot does not duplicate it', async () => {
    const snapshot = [
      {
        id: 'exp-1',
        description: 'gas',
        amount: 40,
        category: 'utilities',
        businessDate: '2026-05-10',
        createdAt: '2026-05-10T09:00:00.000Z',
      },
      {
        id: 'exp-2',
        description: 'napkins',
        amount: 12,
        category: 'supplies',
        businessDate: '2026-05-10',
        createdAt: '2026-05-10T10:00:00.000Z',
      },
    ];

    await businessDay.recordExpenses(venueA, snapshot);
    await businessDay.recordExpenses(venueA, snapshot);
    await businessDay.recordExpenses(venueA, snapshot);

    const rows = await prisma.expense.findMany({
      where: { venueId: venueA.venueId },
    });
    expect(rows).toHaveLength(2);
    expect(rows.reduce((sum, row) => sum + row.amount, 0)).toBe(52);
  });

  it('an edited expense updates in place instead of adding a row', async () => {
    await businessDay.recordExpenses(venueA, [
      { id: 'exp-1', description: 'gas', amount: 40, category: 'utilities' },
    ]);
    await businessDay.recordExpenses(venueA, [
      { id: 'exp-1', description: 'gas', amount: 45, category: 'utilities' },
    ]);

    const rows = await prisma.expense.findMany({
      where: { venueId: venueA.venueId },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].amount).toBe(45);
  });

  it('the expense id is scoped to its venue', async () => {
    const record = {
      id: 'exp-shared',
      description: 'gas',
      amount: 40,
      category: 'utilities',
    };
    await businessDay.recordExpenses(venueA, [record]);
    await businessDay.recordExpenses(venueB, [{ ...record, amount: 99 }]);

    const a = await prisma.expense.findMany({
      where: { venueId: venueA.venueId },
    });
    const b = await prisma.expense.findMany({
      where: { venueId: venueB.venueId },
    });
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    expect(a[0].amount).toBe(40);
    expect(b[0].amount).toBe(99);
  });

  it('accepts several id-less records from an older POS build', async () => {
    // The unique index is on a nullable column, so PostgreSQL must treat the
    // NULLs as distinct — otherwise a venue could hold only one legacy
    // expense and the migration would have failed on real data.
    await businessDay.recordExpenses(venueA, [
      { description: 'legacy gas', amount: 40, category: 'utilities' },
      { description: 'legacy napkins', amount: 12, category: 'supplies' },
    ]);

    const rows = await prisma.expense.findMany({
      where: { venueId: venueA.venueId },
    });
    expect(rows).toHaveLength(2);
    expect(rows.every((row) => row.posExpenseId === null)).toBe(true);
  });
});
