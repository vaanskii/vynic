import { BusinessDaySyncService } from './business-day-sync.service';
import { OrderSyncService } from './order-sync.service';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * What the Cloud does with the two fields it needs to reconcile POS money:
 * the order's manual adjustment, and the expense's own POS-side id.
 *
 * Prisma is a recording Proxy, so these drive the real ingestion code and
 * assert the shape of the write — which key an expense is upserted on, and
 * what an order carries when the POS omits a field it does not know about.
 */

type Call = { key: string; arg: any };

function makeMockPrisma(): { prisma: any; calls: Call[] } {
  const calls: Call[] = [];
  let seq = 0;

  const modelProxy = (model: string) =>
    new Proxy(
      {},
      {
        get: (_t, methodProp) => {
          if (typeof methodProp === 'symbol') return undefined;
          const method = String(methodProp);
          return (arg: any) => {
            calls.push({ key: `${model}.${method}`, arg });
            switch (method) {
              case 'upsert':
                return Promise.resolve({ id: `id-${++seq}` });
              case 'create':
              case 'update':
                return Promise.resolve({ id: `id-${++seq}` });
              case 'findMany':
                return Promise.resolve([]);
              case 'findUnique':
              case 'findFirst':
                return Promise.resolve(null);
              case 'updateMany':
              case 'deleteMany':
                return Promise.resolve({ count: 0 });
              default:
                return Promise.resolve(null);
            }
          };
        },
      },
    );

  const prisma = new Proxy(
    {},
    { get: (_t, model) => (typeof model === 'symbol' ? undefined : modelProxy(String(model))) },
  );

  return { prisma, calls };
}

const tenant: TenantContext = {
  venueId: 'venue-a',
  organizationId: 'org-a',
};

function orderUpserts(calls: Call[]) {
  return calls.filter((c) => c.key === 'order.upsert');
}

describe('POS → Cloud order reconciliation', () => {
  it('persists manualAdjustmentAmount on both sides of the upsert', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new OrderSyncService(prisma);

    await service.sync(
      tenant,
      [
        {
          posOrderId: 501,
          status: 'open',
          totalAmount: 84.5,
          discountAmount: 10,
          manualAdjustmentAmount: -5.5,
        },
      ],
      undefined,
    );

    const [upsert] = orderUpserts(calls);
    expect(upsert).toBeDefined();
    expect(upsert.arg.create.manualAdjustmentAmount).toBe(-5.5);
    expect(upsert.arg.update.manualAdjustmentAmount).toBe(-5.5);
  });

  it('lets the Cloud reconcile the total it was sent', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new OrderSyncService(prisma);

    // A 100.00 bill: 10% service fee on, 10.00 discount, 5.50 taken off by
    // hand. The POS's totalAmount is the only figure the Cloud used to get,
    // with nothing explaining the 5.50.
    await service.sync(
      tenant,
      [
        {
          posOrderId: 502,
          status: 'closed',
          totalAmount: 94.5,
          includeServiceFee: true,
          serviceFeePercent: 10,
          discountAmount: 10,
          manualAdjustmentAmount: -5.5,
          items: [{ name: 'ლუდი', quantity: 2, price: 50 }],
        },
      ],
      undefined,
    );

    const stored = orderUpserts(calls)[0].arg.create;
    const itemsTotal = 100;
    const reconciled =
      itemsTotal * (1 + stored.serviceFeePercent / 100) -
      stored.discountAmount +
      stored.manualAdjustmentAmount;
    expect(reconciled).toBeCloseTo(stored.totalAmount, 2);
  });

  it('treats an old POS payload without the field as no adjustment', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new OrderSyncService(prisma);

    await service.sync(
      tenant,
      [{ posOrderId: 503, status: 'open', totalAmount: 40 }],
      undefined,
    );

    const upsert = orderUpserts(calls)[0];
    expect(upsert.arg.create.manualAdjustmentAmount).toBe(0);
    expect(upsert.arg.update.manualAdjustmentAmount).toBe(0);
  });
});

describe('POS → Cloud expense reconciliation', () => {
  it('upserts on the venue-scoped POS id rather than inserting', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new BusinessDaySyncService(prisma);

    await service.recordExpenses(tenant, [
      {
        id: 'expense-uuid-1',
        description: 'gas',
        amount: 40,
        category: 'utilities',
        createdAt: '2026-05-10T09:00:00.000Z',
        businessDate: '2026-05-10',
      },
    ]);

    expect(calls.filter((c) => c.key === 'expense.create')).toHaveLength(0);
    const [upsert] = calls.filter((c) => c.key === 'expense.upsert');
    expect(upsert.arg.where).toEqual({
      venueId_posExpenseId: {
        venueId: 'venue-a',
        posExpenseId: 'expense-uuid-1',
      },
    });
    expect(upsert.arg.create.businessDate).toBe('2026-05-10');
    expect(upsert.arg.update.amount).toBe(40);
  });

  it('re-sending the same snapshot writes to the same key every time', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new BusinessDaySyncService(prisma);
    const snapshot = [
      { id: 'e1', description: 'gas', amount: 40, category: 'utilities' },
      { id: 'e2', description: 'napkins', amount: 12, category: 'supplies' },
    ];

    await service.recordExpenses(tenant, snapshot);
    await service.recordExpenses(tenant, snapshot);
    await service.recordExpenses(tenant, snapshot);

    expect(calls.filter((c) => c.key === 'expense.create')).toHaveLength(0);
    const keys = calls
      .filter((c) => c.key === 'expense.upsert')
      .map((c) => c.arg.where.venueId_posExpenseId.posExpenseId);
    expect(keys).toEqual(['e1', 'e2', 'e1', 'e2', 'e1', 'e2']);
  });

  it('still accepts an id-less record from an older POS build', async () => {
    const { prisma, calls } = makeMockPrisma();
    const service = new BusinessDaySyncService(prisma);

    await service.recordExpenses(tenant, [
      { description: 'gas', amount: 40, category: 'utilities' },
      { id: '   ', description: 'napkins', amount: 12, category: 'supplies' },
    ]);

    expect(calls.filter((c) => c.key === 'expense.upsert')).toHaveLength(0);
    const creates = calls.filter((c) => c.key === 'expense.create');
    expect(creates).toHaveLength(2);
    expect(creates[0].arg.data.venueId).toBe('venue-a');
    expect(creates[0].arg.data.posExpenseId).toBeUndefined();
  });
});
