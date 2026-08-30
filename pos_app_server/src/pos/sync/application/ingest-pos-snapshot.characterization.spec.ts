// Stub heavy transitive modules so importing the controller doesn't pull in the
// realtime gateway → firebase-admin / uuid (ESM) chain that ts-jest can't load.
jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
jest.mock('../../../auth/auth.service', () => ({ AuthService: class {} }));
jest.mock('../../../auth/pos-sync.guard', () => ({ PosSyncGuard: class {} }));
jest.mock('../../../auth/jwt-auth.guard', () => ({ JwtAuthGuard: class {} }));
jest.mock('../../../auth/roles.guard', () => ({ RolesGuard: class {} }));

import { IngestPosSnapshotService } from './ingest-pos-snapshot.service';
import { PosConnectionRegistry } from '../pos-connection.registry';
import { PosCallbackClient } from '../../pos-callback.client';
import {
  suppressPosEchoForOrder,
  suppressPosEchoForTable,
  suppressPosEchoForReservation,
} from '../../sync-echo-guard';

/**
 * Characterization tests for `POST /sync/manager-data`.
 *
 * These describe what the endpoint does TODAY, not what it should do. They
 * exist so the Step 2A layering refactor cannot silently change persistence
 * order, side-effect order, conflict handling or reconciliation.
 *
 * The strongest assertion here is the ordered `trace`: every Prisma call and
 * every WebSocket broadcast lands in one list in the order it happened, so a
 * refactor that moves a broadcast before its database write fails loudly.
 *
 * Prisma is a Proxy that records `<model>.<method>` and returns sane defaults,
 * so the real controller logic runs without a database.
 */

type CtorArgs = ConstructorParameters<typeof IngestPosSnapshotService>;
type Snapshot = Record<string, unknown>;
type Override = (arg: unknown) => unknown;
type PrismaMethod = (arg?: unknown) => Promise<unknown>;

/** Reads a nested path without spreading `any` through the assertions. */
function at(value: unknown, ...path: Array<string | number>): unknown {
  let cursor = value;
  for (const key of path) {
    if (cursor === null || cursor === undefined) return undefined;
    cursor = (cursor as Record<string | number, unknown>)[key];
  }
  return cursor;
}

function obj(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function defaultResult(
  method: string,
  arg: unknown,
  nextId: () => number,
): unknown {
  switch (method) {
    case 'upsert':
      return {
        id: `id-${nextId()}`,
        ...obj(at(arg, 'create')),
        ...obj(at(arg, 'update')),
        ...obj(at(arg, 'where')),
      };
    case 'create':
    case 'update':
      return { id: `id-${nextId()}`, ...obj(at(arg, 'data')) };
    case 'findMany':
      return [];
    case 'findFirst':
    case 'findUnique':
      return null;
    case 'count':
      return 0;
    case 'updateMany':
    case 'deleteMany':
      return { count: 0 };
    default:
      return null;
  }
}

interface Call {
  key: string;
  arg: unknown;
}

interface Broadcast {
  event: string;
  payload: unknown;
}

interface Harness {
  service: IngestPosSnapshotService;
  calls: Call[];
  /** Prisma calls and WS broadcasts interleaved, in the order they happened. */
  trace: string[];
  broadcasts: Broadcast[];
  kickPending: jest.Mock;
  vaultWrite: jest.Mock;
  sync: (payload: Snapshot) => Promise<{ success: boolean; syncedAt: string }>;
}

function makeHarness(overrides: Record<string, Override> = {}): Harness {
  const calls: Call[] = [];
  const trace: string[] = [];
  const broadcasts: Broadcast[] = [];
  let seq = 0;
  const nextId = () => ++seq;

  const modelProxy = (model: string) =>
    new Proxy<Record<string, PrismaMethod>>(
      {},
      {
        get: (_target, methodProp) => {
          if (typeof methodProp === 'symbol') return undefined;
          const method = methodProp;
          const call: PrismaMethod = (arg?: unknown) => {
            const key = `${model}.${method}`;
            calls.push({ key, arg });
            trace.push(`db:${key}`);
            const override = overrides[key];
            if (override) {
              const result = override(arg);
              if (result !== undefined) return Promise.resolve(result);
            }
            return Promise.resolve(defaultResult(method, arg, nextId));
          };
          return call;
        },
      },
    );

  const prisma = new Proxy<Record<string, Record<string, PrismaMethod>>>(
    {},
    {
      get: (_target, model) =>
        typeof model === 'symbol' ? undefined : modelProxy(model),
    },
  );

  const broadcastUpdate = jest.fn((event: string, payload: unknown) => {
    broadcasts.push({ event, payload });
    trace.push(`ws:${event}`);
  });
  const kickPending = jest.fn(() => Promise.resolve());
  const vaultRead = jest.fn(() => Promise.resolve({}));
  const vaultWrite = jest.fn(() => Promise.resolve());

  const posConnection = new PosConnectionRegistry(
    prisma as unknown as CtorArgs[0],
    new PosCallbackClient(),
  );
  const service = new IngestPosSnapshotService(
    prisma as unknown as CtorArgs[0],
    { broadcastUpdate } as unknown as CtorArgs[1],
    { kickPending } as unknown as CtorArgs[2],
    { read: vaultRead, write: vaultWrite } as unknown as CtorArgs[3],
    posConnection,
  );

  return {
    service,
    calls,
    trace,
    broadcasts,
    kickPending,
    vaultWrite,
    sync: (payload: Snapshot) => service.execute(payload),
  };
}

/** Only the pending-outbox rows the ORDER loop asks for (it selects createdAt). */
function outboxOrderRows(rows: unknown[]): Override {
  return (arg) => (at(arg, 'select', 'createdAt') ? rows : undefined);
}

function settingKeys(calls: Call[]): unknown[] {
  return calls
    .filter((c) => c.key === 'setting.upsert')
    .map((c) => at(c.arg, 'where', 'key'));
}

function callKeys(calls: Call[]): string[] {
  return calls.map((c) => c.key);
}

function events(broadcasts: Broadcast[]): string[] {
  return broadcasts.map((b) => b.event);
}

const BUSINESS_DATE = '2026-06-27';

describe('POST /sync/manager-data — response contract', () => {
  it('returns { success, syncedAt } for an empty payload and still kicks the outbox', async () => {
    const h = makeHarness();

    const result = await h.sync({});

    expect(result.success).toBe(true);
    expect(typeof result.syncedAt).toBe('string');
    expect(new Date(result.syncedAt).toString()).not.toBe('Invalid Date');
    expect(h.kickPending).toHaveBeenCalledTimes(1);
  });

  it('writes nothing and broadcasts nothing for an empty payload', async () => {
    const h = makeHarness();

    await h.sync({});

    expect(h.trace).toEqual([]);
  });
});

describe('POST /sync/manager-data — full snapshot side-effect order', () => {
  it('performs persistence and broadcasts in exactly the recorded order', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      posCallbackUrl: 'http://10.10.10.4:8081',
      posConnectionKey: 'key-1',
      businessDate: BUSINESS_DATE,
      dailySalesTotal: 400,
      tables: [
        {
          tableNumber: '3',
          floor: 'first',
          isReserved: true,
          activeOrderId: 7,
          currentBill: 25,
        },
      ],
      orders: [
        {
          posOrderId: 7,
          status: 'open',
          totalAmount: 25,
          floor: 'first',
          tableNumbers: ['3'],
          items: [{ name: 'Coffee', quantity: 1, price: 25 }],
        },
      ],
      expenses: [{ description: 'Milk', amount: 5, category: 'supplies' }],
      settings: { serviceFeePercent: 10, serviceFeeEnabled: true },
      salesSummary: {
        date: BUSINESS_DATE,
        totalRevenue: 400,
        orderCount: 4,
        cashRevenue: 200,
        cardRevenue: 200,
        paymentBreakdown: { cash: 200, card: 200 },
      },
    });

    // The literal recorded trace. If a refactor reorders a write, or moves a
    // broadcast relative to its write, this list changes and the test fails.
    expect(h.trace).toEqual([
      // 1. POS callback handshake is persisted first.
      'db:setting.upsert',
      'db:setting.upsert',
      // 2. Table snapshot: staleness probe, then the upsert.
      'db:table.count',
      'db:table.upsert',
      // 3. Orders: pending-outbox probe, order upsert, nested items write,
      //    then the dine-in table link.
      'db:posCallbackOutbox.findMany',
      'db:order.upsert',
      'db:order.update',
      'db:table.upsert',
      // 4. Deletion reconciliation for the business date.
      'db:order.findMany',
      'db:order.deleteMany',
      // 5. Expenses.
      'db:expense.create',
      // 6. Aggregate broadcasts come AFTER all of the above.
      'ws:order_updated',
      'ws:table_updated',
      'ws:data_updated',
      // 7. Business-day tracking.
      'db:setting.findUnique',
      'db:setting.upsert',
      'db:setting.findUnique',
      'db:setting.upsert',
      // 8. Reporting values.
      'db:setting.upsert', // salesSummary:<date>
      'db:setting.upsert', // restaurant:serviceFeePercent
      'db:setting.upsert', // restaurant:serviceFeeEnabled
      'db:setting.upsert', // dailySalesTotal:<date>
      'db:setting.upsert', // openTablesPayable:<date>
    ]);
  });

  it('persists the POS callback url and connection key under stable setting keys', async () => {
    const h = makeHarness();

    await h.sync({
      posCallbackUrl: 'http://10.10.10.4:8081',
      posConnectionKey: 'key-1',
    });

    expect(settingKeys(h.calls)).toEqual([
      'pos:callback_url',
      'pos:connection_key',
    ]);
  });

  it('rejects a non-private POS callback url without persisting it', async () => {
    const h = makeHarness();

    await h.sync({ posCallbackUrl: 'http://evil.example.com/hook' });

    expect(settingKeys(h.calls)).toEqual([]);
  });
});

describe('POST /sync/manager-data — realtimeOnly fast path', () => {
  it('skips menu, staff, all-time and history work but still syncs tables', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      realtimeOnly: true,
      businessDate: BUSINESS_DATE,
      tables: [{ tableNumber: '1', floor: 'first', isReserved: false }],
      menu: [{ slug: 'drinks', nameKa: 'ს', nameEn: 'Drinks' }],
      staff: [{ username: 'mary', role: 'WAITER' }],
      salesAllTimeSummary: {
        totalRevenue: 1,
        orderCount: 1,
        cashRevenue: 1,
        cardRevenue: 0,
        paymentBreakdown: {},
      },
      salesHistoryByDate: {
        [BUSINESS_DATE]: {
          date: BUSINESS_DATE,
          totalRevenue: 1,
          orderCount: 1,
          totalOrders: 1,
          cancelledOrders: 0,
          cashRevenue: 1,
          cardRevenue: 0,
          paymentBreakdown: {},
        },
      },
    });

    const keys = callKeys(h.calls);
    expect(keys).not.toContain('menuCategory.upsert');
    expect(keys).not.toContain('staff.upsert');
    expect(keys).not.toContain('staff.findMany');
    expect(keys).toContain('table.upsert');

    expect(settingKeys(h.calls)).not.toContain('salesSummary:all_time');
    expect(settingKeys(h.calls)).not.toContain('salesSummary:history_index');
  });
});

describe('POST /sync/manager-data — table snapshot policy', () => {
  it('ignores an all-free cold-boot snapshot while the server still holds reserved tables', async () => {
    const h = makeHarness({ 'table.count': () => 2 });

    await h.sync({
      tables: [{ tableNumber: '1', floor: 'first', isReserved: false }],
    });

    expect(callKeys(h.calls)).not.toContain('table.upsert');
    expect(events(h.broadcasts)).not.toContain('table_updated');
  });

  it('applies that same all-free snapshot when it arrives on the realtime path', async () => {
    const h = makeHarness({ 'table.count': () => 2 });

    await h.sync({
      realtimeOnly: true,
      tables: [{ tableNumber: '1', floor: 'first', isReserved: false }],
    });

    expect(h.calls.filter((c) => c.key === 'table.upsert')).toHaveLength(1);
    expect(events(h.broadcasts)).toContain('table_updated');
  });

  it('treats a table carrying an activeOrderId as reserved even when isReserved is false', async () => {
    const h = makeHarness();

    await h.sync({
      tables: [
        {
          tableNumber: '4',
          floor: 'second',
          isReserved: false,
          activeOrderId: 12,
          currentBill: 60,
        },
      ],
    });

    const upsert = h.calls.find((c) => c.key === 'table.upsert');
    expect(at(upsert?.arg, 'update')).toEqual({
      isReserved: true,
      activeOrderId: 12,
      currentBill: 60,
    });
  });

  it('zeroes activeOrderId and currentBill for a free table', async () => {
    const h = makeHarness();

    await h.sync({
      tables: [
        {
          tableNumber: '4',
          floor: 'second',
          isReserved: true,
          currentBill: 60,
        },
        {
          tableNumber: '5',
          floor: 'second',
          isReserved: false,
          currentBill: 9,
        },
      ],
    });

    const free = h.calls.filter((c) => c.key === 'table.upsert')[1];
    expect(at(free.arg, 'update')).toEqual({
      isReserved: false,
      activeOrderId: null,
      currentBill: 0,
    });
  });

  it('skips table sync entirely for an empty tables array', async () => {
    const h = makeHarness();

    await h.sync({ tables: [] });

    expect(h.trace).toEqual([]);
  });
});

describe('POST /sync/manager-data — order sync and table linking', () => {
  it('replaces order items through one nested write, never a bare deleteMany', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      orders: [
        {
          posOrderId: 9,
          status: 'open',
          totalAmount: 30,
          floor: 'first',
          tableNumbers: [],
          items: [{ name: 'Tea', quantity: 2, price: 15 }],
        },
      ],
    });

    expect(callKeys(h.calls)).not.toContain('orderItem.deleteMany');
    const update = h.calls.find((c) => c.key === 'order.update');
    expect(at(update?.arg, 'data', 'items', 'deleteMany')).toEqual({});
    expect(at(update?.arg, 'data', 'items', 'create')).toEqual([
      { name: 'Tea', quantity: 2, price: 15 },
    ]);
  });

  it('reserves the tables of an active dine-in order and strips a "Table " prefix', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      orders: [
        {
          posOrderId: 9,
          status: 'open',
          totalAmount: 30,
          floor: 'first',
          tableNumbers: ['Table 6'],
        },
      ],
    });

    const link = h.calls.find((c) => c.key === 'table.upsert');
    expect(at(link?.arg, 'where', 'tableIdentifier')).toEqual({
      tableNumber: '6',
      floor: 'first',
    });
    expect(at(link?.arg, 'update')).toEqual({
      isReserved: true,
      activeOrderId: 9,
      currentBill: 30,
    });
  });

  it('does not reserve tables for a takeaway order', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      orders: [
        {
          posOrderId: 9,
          status: 'open',
          totalAmount: 30,
          floor: 'takeaway',
          tableNumbers: ['1'],
        },
      ],
    });

    expect(callKeys(h.calls)).not.toContain('table.upsert');
  });

  it.each(['paid', 'closed', 'cancelled'])(
    'frees linked tables when the POS reports status "%s"',
    async (status) => {
      const h = makeHarness({
        'posCallbackOutbox.findMany': outboxOrderRows([]),
        'table.updateMany': () => ({ count: 1 }),
      });

      await h.sync({
        orders: [
          {
            posOrderId: 9,
            status,
            totalAmount: 30,
            floor: 'first',
            tableNumbers: ['6'],
          },
        ],
      });

      const free = h.calls.find((c) => c.key === 'table.updateMany');
      expect(at(free?.arg, 'where')).toEqual({
        tableNumber: '6',
        floor: 'first',
      });
      expect(at(free?.arg, 'data')).toEqual({
        isReserved: false,
        activeOrderId: null,
        currentBill: 0,
      });
      // Freeing a table is itself a table change → mobile must be told.
      expect(events(h.broadcasts)).toContain('table_updated');
    },
  );

  it('does not broadcast table_updated when no table row was actually freed', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
      'table.updateMany': () => ({ count: 0 }),
    });

    await h.sync({
      orders: [
        {
          posOrderId: 9,
          status: 'paid',
          totalAmount: 30,
          floor: 'first',
          tableNumbers: ['6'],
        },
      ],
    });

    expect(events(h.broadcasts)).not.toContain('table_updated');
  });

  it('falls back to orderId when posOrderId is absent, and skips an order with neither', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      orders: [
        {
          orderId: 42,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
        },
        { status: 'open', totalAmount: 10, floor: 'first' },
      ],
    });

    const upserts = h.calls.filter((c) => c.key === 'order.upsert');
    expect(upserts).toHaveLength(1);
    expect(at(upserts[0].arg, 'where', 'posOrderId')).toBe(42);
  });

  it('applies the documented field defaults when the POS omits them', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      businessDate: BUSINESS_DATE,
      orders: [
        { posOrderId: 9, status: 'open', totalAmount: 30, createdBy: 'nino' },
      ],
    });

    const upsert = h.calls.find((c) => c.key === 'order.upsert');
    expect(at(upsert?.arg, 'create')).toMatchObject({
      paymentType: 'cash',
      guestCount: 0,
      waiterName: 'nino',
      floor: '',
      businessDate: BUSINESS_DATE,
      includeServiceFee: false,
      discountAmount: 0,
      serviceFeePercent: 10,
    });
  });
});

describe('POST /sync/manager-data — order deletion reconciliation', () => {
  it('protects incoming and queued order ids, and deletes items before their orders', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([
        { posOrderId: 77, createdAt: new Date('2026-06-27T09:00:00.000Z') },
      ]),
      'order.findMany': () => [{ id: 'stale-1' }],
    });

    await h.sync({
      businessDate: BUSINESS_DATE,
      orders: [
        {
          posOrderId: 9,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
        },
      ],
    });

    const stale = h.calls.find((c) => c.key === 'order.findMany');
    expect(at(stale?.arg, 'where', 'posOrderId', 'notIn')).toEqual([9, 77]);
    expect(at(stale?.arg, 'where', 'businessDate')).toBe(BUSINESS_DATE);

    const keys = callKeys(h.calls);
    expect(keys.indexOf('orderItem.deleteMany')).toBeLessThan(
      keys.indexOf('order.deleteMany'),
    );

    const takeaway = h.calls.filter((c) => c.key === 'order.deleteMany').pop();
    expect(at(takeaway?.arg, 'where', 'floor')).toBe('takeaway');
    expect(at(takeaway?.arg, 'where', 'posOrderId', 'notIn')).toEqual([9, 77]);
  });

  it('does not reconcile deletions at all when the payload carries no business date', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
      'order.findMany': () => [{ id: 'stale-1' }],
    });

    await h.sync({
      orders: [
        {
          posOrderId: 9,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
        },
      ],
    });

    const keys = callKeys(h.calls);
    expect(keys).not.toContain('order.deleteMany');
    expect(keys).not.toContain('orderItem.deleteMany');
  });
});

describe('POST /sync/manager-data — menu sync', () => {
  it('upserts categories, subcategories and items and rewrites variants in place', async () => {
    const h = makeHarness();

    await h.sync({
      menu: [
        {
          slug: 'drinks',
          nameKa: 'სასმელი',
          nameEn: 'Drinks',
          sendToKitchen: false,
          subcategories: [
            {
              slug: 'hot',
              nameKa: 'ცხელი',
              nameEn: 'Hot',
              items: [
                {
                  nameKa: 'ყავა',
                  nameEn: 'Coffee',
                  price: 5,
                  variants: [{ size: 'L', price: 7 }],
                },
              ],
            },
          ],
          items: [{ nameKa: 'წყალი', nameEn: 'Water', price: 2 }],
        },
      ],
    });

    expect(h.trace).toEqual([
      'db:menuCategory.upsert',
      'db:menuSubcategory.upsert',
      'db:menuItem.findFirst',
      'db:menuItem.create',
      'db:menuItemVariant.deleteMany',
      'db:menuItemVariant.create',
      'db:menuItem.findFirst',
      'db:menuItem.create',
      'ws:data_updated',
    ]);
  });

  it('updates an existing item instead of creating a duplicate', async () => {
    const h = makeHarness({ 'menuItem.findFirst': () => ({ id: 'item-1' }) });

    await h.sync({
      menu: [
        {
          slug: 'drinks',
          nameKa: 'ს',
          nameEn: 'Drinks',
          items: [{ nameKa: 'წყალი', nameEn: 'Water', price: 2 }],
        },
      ],
    });

    const keys = callKeys(h.calls);
    expect(keys).toContain('menuItem.update');
    expect(keys).not.toContain('menuItem.create');
  });

  it('carries payload order into sortOrder for categories and items', async () => {
    const h = makeHarness();

    await h.sync({
      menu: [
        { slug: 'a', nameKa: 'a', nameEn: 'A' },
        {
          slug: 'b',
          nameKa: 'b',
          nameEn: 'B',
          items: [
            { nameKa: 'x', nameEn: 'X', price: 1 },
            { nameKa: 'y', nameEn: 'Y', price: 2 },
          ],
        },
      ],
    });

    const cats = h.calls
      .filter((c) => c.key === 'menuCategory.upsert')
      .map((c) => at(c.arg, 'update', 'sortOrder'));
    expect(cats).toEqual([0, 1]);
    const items = h.calls
      .filter((c) => c.key === 'menuItem.create')
      .map((c) => at(c.arg, 'data', 'sortOrder'));
    expect(items).toEqual([0, 1]);
  });
});

describe('POST /sync/manager-data — staff sync', () => {
  it('hashes a supplied pin, stores the plaintext in the vault, and normalizes the role', async () => {
    const h = makeHarness({ 'staff.findMany': () => [] });

    await h.sync({
      staff: [{ username: 'mary', role: 'WAITER', pin: '1234' }],
    });

    const upsert = h.calls.find((c) => c.key === 'staff.upsert');
    const pinHash = at(upsert?.arg, 'update', 'pinHash');
    expect(typeof pinHash).toBe('string');
    expect(pinHash).not.toBe('1234');
    expect(at(upsert?.arg, 'update', 'isActive')).toBe(true);
    expect(h.vaultWrite).toHaveBeenCalledWith({ mary: '1234' });
  });

  it('updates role only for an existing member sent without a pin, and never writes the vault', async () => {
    const h = makeHarness({
      'staff.findUnique': () => ({ username: 'mary' }),
      'staff.findMany': () => [{ username: 'mary' }],
    });

    await h.sync({ staff: [{ username: 'mary', role: 'MANAGER' }] });

    expect(callKeys(h.calls)).not.toContain('staff.upsert');
    const update = h.calls.find((c) => c.key === 'staff.update');
    expect(at(update?.arg, 'data')).toEqual({
      role: 'MANAGER',
      isActive: true,
    });
    expect(h.vaultWrite).not.toHaveBeenCalled();
  });

  it('refuses to create an unknown member that arrives without a pin', async () => {
    const h = makeHarness({
      'staff.findUnique': () => null,
      'staff.findMany': () => [],
    });

    await h.sync({ staff: [{ username: 'ghost', role: 'WAITER' }] });

    const keys = callKeys(h.calls);
    expect(keys).not.toContain('staff.upsert');
    expect(keys).not.toContain('staff.update');
  });

  it('does not issue a delete when every server member is still present', async () => {
    const h = makeHarness({
      'staff.findUnique': () => ({ username: 'mary' }),
      'staff.findMany': () => [{ username: 'mary' }],
    });

    await h.sync({ staff: [{ username: 'mary', role: 'WAITER' }] });

    expect(callKeys(h.calls)).not.toContain('staff.deleteMany');
  });
});

describe('POST /sync/manager-data — realtime hints and echo suppression', () => {
  it('broadcasts orders_bulk_touch and suppresses the plain order_updated toast', async () => {
    const h = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });

    await h.sync({
      orders: [
        {
          posOrderId: 31,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
        },
      ],
      touchedOrderHints: [{ posOrderId: 31, tableLabel: 'Table 3' }],
    });

    expect(events(h.broadcasts)).toContain('orders_bulk_touch');
    expect(events(h.broadcasts)).not.toContain('order_updated');
  });

  it('keeps only the newest hint per order id', async () => {
    const h = makeHarness();

    await h.sync({
      touchedOrderHints: [
        { posOrderId: 31, changeSummary: 'first' },
        { posOrderId: 31, changeSummary: 'second' },
      ],
    });

    const touch = h.broadcasts.find((b) => b.event === 'orders_bulk_touch');
    expect(at(touch?.payload, 'touches')).toHaveLength(1);
    expect(at(touch?.payload, 'touches', 0, 'changeSummary')).toBe('second');
    expect(at(touch?.payload, 'source')).toBe('pos_sync');
  });

  it('drops an order hint whose echo is suppressed', async () => {
    suppressPosEchoForOrder(4242);
    const h = makeHarness();

    await h.sync({ touchedOrderHints: [{ posOrderId: 4242 }] });

    expect(events(h.broadcasts)).not.toContain('orders_bulk_touch');
  });

  it('reads each touched table back from the database before broadcasting it', async () => {
    const h = makeHarness({
      'table.findFirst': () => ({
        tableNumber: '3',
        floor: 'first',
        isReserved: true,
        activeOrderId: 31,
        currentBill: 40,
      }),
    });

    await h.sync({
      touchedTableHints: [
        { tableNumber: '3', floor: 'first', changeType: 'reserved' },
      ],
    });

    // Hints alone do not set `changed`, so no aggregate data_updated follows.
    expect(h.trace).toEqual(['db:table.findFirst', 'ws:tables_bulk_touch']);
    const touch = h.broadcasts.find((b) => b.event === 'tables_bulk_touch');
    expect(at(touch?.payload, 'tables')).toEqual([
      {
        tableNumber: '3',
        floor: 'first',
        isReserved: true,
        isOccupied: true,
        activeOrderId: 31,
        currentBill: 40,
      },
    ]);
  });

  it('drops a table hint whose echo is suppressed', async () => {
    suppressPosEchoForTable('9', 'first');
    const h = makeHarness();

    await h.sync({
      touchedTableHints: [
        { tableNumber: '9', floor: 'first', changeType: 'freed' },
      ],
    });

    expect(events(h.broadcasts)).not.toContain('tables_bulk_touch');
  });

  it('relays the latest reservation hint and flags a walk-in', async () => {
    const h = makeHarness();

    await h.sync({
      touchedReservationHints: [
        { reservationId: 'r-1', action: 'created' },
        {
          reservationId: 'r-2',
          action: 'updated',
          customerName: 'Walk-in',
          linkedOrderId: 55,
        },
      ],
    });

    const relay = h.broadcasts.find((b) => b.event === 'data_updated');
    expect(at(relay?.payload, 'type')).toBe('reservations');
    expect(at(relay?.payload, 'reservationId')).toBe('r-2');
    expect(at(relay?.payload, 'touches')).toHaveLength(2);
    expect(at(relay?.payload, 'walkIn')).toBe(true);
    expect(at(relay?.payload, 'posOrderId')).toBe(55);
  });

  it('drops a reservation hint whose echo is suppressed', async () => {
    suppressPosEchoForReservation('r-echo');
    const h = makeHarness();

    await h.sync({ touchedReservationHints: [{ reservationId: 'r-echo' }] });

    expect(h.broadcasts).toHaveLength(0);
  });
});

describe('POST /sync/manager-data — business day rollover', () => {
  it('clears every table and announces day_closed only after the table sync has run', async () => {
    const h = makeHarness({
      'setting.findUnique': (arg) =>
        at(arg, 'where', 'key') === 'currentBusinessDate'
          ? { value: '2026-06-26' }
          : null,
    });

    await h.sync({
      businessDate: BUSINESS_DATE,
      tables: [
        { tableNumber: '1', floor: 'first', isReserved: true, currentBill: 10 },
      ],
    });

    expect(h.trace).toEqual([
      'db:table.count',
      'db:table.upsert', // the POS snapshot is applied first…
      'ws:table_updated',
      'ws:data_updated',
      'db:setting.findUnique', // currentBusinessDate
      'db:setting.upsert',
      'db:setting.findUnique', // businessDayOpenedAt:<date>
      'db:setting.upsert',
      'db:table.updateMany', // …and only then is the floor wiped
      'ws:day_closed',
      'db:setting.upsert', // openTablesPayable:<date>
    ]);

    const wipe = h.calls.find((c) => c.key === 'table.updateMany');
    expect(wipe?.arg).toEqual({
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });
  });

  it('does not wipe tables on the very first business date the server sees', async () => {
    const h = makeHarness({ 'setting.findUnique': () => null });

    await h.sync({ businessDate: BUSINESS_DATE });

    expect(callKeys(h.calls)).not.toContain('table.updateMany');
    expect(events(h.broadcasts)).not.toContain('day_closed');
  });

  it('stamps businessDayOpenedAt once and leaves it alone on later pushes', async () => {
    const h = makeHarness({
      'setting.findUnique': (arg) =>
        at(arg, 'where', 'key') === 'currentBusinessDate'
          ? { value: BUSINESS_DATE }
          : { value: '2026-06-27T06:00:00.000Z' },
    });

    await h.sync({ businessDate: BUSINESS_DATE });

    expect(settingKeys(h.calls)).not.toContain(
      `businessDayOpenedAt:${BUSINESS_DATE}`,
    );
  });
});

describe('POST /sync/manager-data — reporting values', () => {
  it('stores each summary family under its documented settings key', async () => {
    const h = makeHarness();

    await h.sync({
      businessDate: BUSINESS_DATE,
      dailySalesTotal: 950,
      salesSummary: {
        date: BUSINESS_DATE,
        totalRevenue: 950,
        orderCount: 9,
        cashRevenue: 500,
        cardRevenue: 450,
        paymentBreakdown: { cash: 500, card: 450 },
      },
      salesAllTimeSummary: {
        totalRevenue: 9000,
        orderCount: 90,
        cashRevenue: 5000,
        cardRevenue: 4000,
        paymentBreakdown: {},
      },
      salesHistoryByDate: {
        '2026-06-26': {
          date: '2026-06-26',
          totalRevenue: 100,
          orderCount: 1,
          totalOrders: 1,
          cancelledOrders: 0,
          cashRevenue: 100,
          cardRevenue: 0,
          paymentBreakdown: {},
        },
        'not-a-date': { date: 'not-a-date' },
      },
      settings: { serviceFeePercent: 12, serviceFeeEnabled: false },
    });

    // 'not-a-date' is rejected by the YYYY-MM-DD guard and never stored.
    expect(settingKeys(h.calls)).toEqual([
      'currentBusinessDate',
      `businessDayOpenedAt:${BUSINESS_DATE}`,
      `salesSummary:${BUSINESS_DATE}`,
      'salesSummary:all_time',
      'salesSummary:2026-06-26',
      'salesSummary:history_index',
      'restaurant:serviceFeePercent',
      'restaurant:serviceFeeEnabled',
      `dailySalesTotal:${BUSINESS_DATE}`,
      `openTablesPayable:${BUSINESS_DATE}`,
    ]);

    const valueOf = (key: string) =>
      at(
        h.calls.find(
          (c) =>
            c.key === 'setting.upsert' && at(c.arg, 'where', 'key') === key,
        )?.arg,
        'update',
        'value',
      );
    expect(valueOf('restaurant:serviceFeePercent')).toBe('12');
    expect(valueOf('restaurant:serviceFeeEnabled')).toBe('false');
    expect(valueOf(`dailySalesTotal:${BUSINESS_DATE}`)).toBe('950');
  });

  it('derives openTablesPayable from the occupied tables in the payload', async () => {
    const h = makeHarness();

    await h.sync({
      businessDate: BUSINESS_DATE,
      tables: [
        { tableNumber: '1', floor: 'first', isReserved: true, currentBill: 30 },
        {
          tableNumber: '2',
          floor: 'first',
          isReserved: false,
          activeOrderId: 8,
          currentBill: 12,
        },
        {
          tableNumber: '3',
          floor: 'first',
          isReserved: false,
          currentBill: 99,
        },
      ],
    });

    const payable = h.calls.find(
      (c) =>
        c.key === 'setting.upsert' &&
        at(c.arg, 'where', 'key') === `openTablesPayable:${BUSINESS_DATE}`,
    );
    expect(at(payable?.arg, 'update', 'value')).toBe('42');
  });
});

describe('POST /sync/manager-data — repeat delivery', () => {
  it('produces an identical side-effect trace when the same snapshot is replayed', async () => {
    const payload: Snapshot = {
      businessDate: BUSINESS_DATE,
      tables: [
        {
          tableNumber: '1',
          floor: 'first',
          isReserved: true,
          activeOrderId: 3,
          currentBill: 20,
        },
      ],
      orders: [
        {
          posOrderId: 3,
          status: 'open',
          totalAmount: 20,
          floor: 'first',
          tableNumbers: ['1'],
          items: [{ name: 'Tea', quantity: 1, price: 20 }],
        },
      ],
    };

    const first = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });
    await first.sync(structuredClone(payload));

    const second = makeHarness({
      'posCallbackOutbox.findMany': outboxOrderRows([]),
    });
    await second.sync(structuredClone(payload));

    expect(second.trace).toEqual(first.trace);
  });
});
