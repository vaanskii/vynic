// Stub heavy transitive modules so importing the controller doesn't pull in the
// realtime gateway → firebase-admin / uuid (ESM) chain that ts-jest can't load.
// We inject our own gateway/guard doubles at construction time anyway.
jest.mock('../../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
jest.mock('../../../auth/auth.service', () => ({ AuthService: class {} }));
jest.mock('../../../auth/pos-sync.guard', () => ({ PosSyncGuard: class {} }));
jest.mock('../../../auth/jwt-auth.guard', () => ({ JwtAuthGuard: class {} }));
jest.mock('../../../auth/roles.guard', () => ({ RolesGuard: class {} }));

import { IngestPosSnapshotService } from './ingest-pos-snapshot.service';
import { PosConnectionRegistry } from '../pos-connection.registry';
import { BusinessDaySyncService } from '../snapshot/business-day-sync.service';
import { MenuSyncService } from '../snapshot/menu-sync.service';
import { OrderSyncService } from '../snapshot/order-sync.service';
import { StaffSyncService } from '../snapshot/staff-sync.service';
import { SyncBroadcastService } from '../snapshot/sync-broadcast.service';
import { TableSyncService } from '../snapshot/table-sync.service';
import { PosCallbackClient } from '../../pos-callback.client';

/**
 * Use-case tests for the same-order last-write-wins resolution and the staff
 * reconcile protection inside `POST /sync/manager-data`.
 *
 * Prisma is replaced with a Proxy mock that records every `<model>.<method>`
 * call and returns sensible defaults, so the test drives the *real* ingestion
 * logic (order loop + staff reconcile) without a database.
 */

type Call = { key: string; arg: any };

function defaultResult(method: string, arg: any, nextId: () => number): any {
  switch (method) {
    case 'upsert':
      return {
        id: `id-${nextId()}`,
        ...(arg?.create ?? {}),
        ...(arg?.update ?? {}),
        ...(arg?.where ?? {}),
      };
    case 'create':
    case 'update':
      return { id: `id-${nextId()}`, ...(arg?.data ?? {}) };
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

function makeMockPrisma(overrides: Record<string, (arg: any) => any> = {}): {
  prisma: any;
  calls: Call[];
} {
  const calls: Call[] = [];
  let seq = 0;
  const nextId = () => ++seq;

  const modelProxy = (model: string) =>
    new Proxy(
      {},
      {
        get: (_t, methodProp) => {
          if (typeof methodProp === 'symbol') return undefined;
          const method = String(methodProp);
          return (arg: any) => {
            const key = `${model}.${method}`;
            calls.push({ key, arg });
            const ov = overrides[key];
            if (ov) {
              const r = ov(arg);
              if (r !== undefined) return Promise.resolve(r);
            }
            return Promise.resolve(defaultResult(method, arg, nextId));
          };
        },
      },
    );

  const prisma = new Proxy(
    {},
    {
      get: (_t, model) => {
        if (typeof model === 'symbol') return undefined;
        return modelProxy(String(model));
      },
    },
  );

  return { prisma, calls };
}

function makeIngestService(prisma: any) {
  const gateway = { broadcastUpdate: jest.fn() } as any;
  const posOutbox = { kickPending: jest.fn() } as any;
  const posCallback = new PosCallbackClient();
  const pinVault = {
    read: jest.fn(async () => ({})),
    write: jest.fn(async () => {}),
  } as any;
  const posConnection = new PosConnectionRegistry(prisma, posCallback);
  return new IngestPosSnapshotService(
    posOutbox,
    posConnection,
    new MenuSyncService(prisma),
    new TableSyncService(prisma),
    new OrderSyncService(prisma),
    new StaffSyncService(prisma, pinVault),
    new BusinessDaySyncService(prisma),
    new SyncBroadcastService(prisma, gateway),
  );
}

const T1 = '2026-06-27T10:00:00.000Z'; // older
const T2 = '2026-06-27T10:05:00.000Z'; // newer
const BUSINESS_DATE = '2026-06-27';

function orderQueryRows(rows: any[]) {
  // The order loop selects { posOrderId, createdAt }; the staff reconcile
  // selects { endpoint, payload }. Branch on the requested select.
  return (arg: any) => {
    if (arg?.select?.createdAt) return rows;
    return undefined; // let other findMany calls fall through
  };
}

describe('IngestPosSnapshotService /sync/manager-data — order last-write-wins', () => {
  it('POS wins and the queued mobile change is superseded when the POS edit is newer', async () => {
    const { prisma, calls } = makeMockPrisma({
      'posCallbackOutbox.findMany': orderQueryRows([
        { posOrderId: 5, createdAt: new Date(T1) },
      ]),
    });
    const ingest = makeIngestService(prisma);

    await ingest.execute({
      businessDate: BUSINESS_DATE,
      orders: [
        {
          posOrderId: 5,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
          updatedAt: T2, // POS edited AFTER the queued mobile change
          items: [],
        },
      ],
    });

    const superseded = calls.find(
      (c) =>
        c.key === 'posCallbackOutbox.updateMany' &&
        c.arg?.data?.status === 'superseded' &&
        c.arg?.where?.posOrderId === 5,
    );
    expect(superseded).toBeDefined();

    const upsertedOrder5 = calls.find(
      (c) => c.key === 'order.upsert' && c.arg?.where?.posOrderId === 5,
    );
    expect(upsertedOrder5).toBeDefined(); // POS snapshot applied
  });

  it('mobile wins — POS snapshot is held and nothing is superseded — when the queued change is newer', async () => {
    const { prisma, calls } = makeMockPrisma({
      'posCallbackOutbox.findMany': orderQueryRows([
        { posOrderId: 5, createdAt: new Date(T2) }, // queued change is newer
      ]),
    });
    const ingest = makeIngestService(prisma);

    await ingest.execute({
      businessDate: BUSINESS_DATE,
      orders: [
        {
          posOrderId: 5,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
          updatedAt: T1, // POS edit is older than the queued mobile change
          items: [],
        },
      ],
    });

    const upsertedOrder5 = calls.find(
      (c) => c.key === 'order.upsert' && c.arg?.where?.posOrderId === 5,
    );
    expect(upsertedOrder5).toBeUndefined(); // held — POS snapshot ignored

    const superseded = calls.find(
      (c) =>
        c.key === 'posCallbackOutbox.updateMany' &&
        c.arg?.data?.status === 'superseded',
    );
    expect(superseded).toBeUndefined();
  });

  it('mobile wins when the POS sends no timestamp (backwards-compatible hold)', async () => {
    const { prisma, calls } = makeMockPrisma({
      'posCallbackOutbox.findMany': orderQueryRows([
        { posOrderId: 5, createdAt: new Date(T1) },
      ]),
    });
    const ingest = makeIngestService(prisma);

    await ingest.execute({
      businessDate: BUSINESS_DATE,
      orders: [
        {
          posOrderId: 5,
          status: 'open',
          totalAmount: 10,
          floor: 'first',
          tableNumbers: [],
          // no updatedAt
          items: [],
        },
      ],
    });

    const upsertedOrder5 = calls.find(
      (c) => c.key === 'order.upsert' && c.arg?.where?.posOrderId === 5,
    );
    expect(upsertedOrder5).toBeUndefined();
  });
});

describe('IngestPosSnapshotService /sync/manager-data — staff reconcile protection', () => {
  it('keeps a server user that has a queued mobile create, deletes a genuinely-stale one', async () => {
    const { prisma, calls } = makeMockPrisma({
      'posCallbackOutbox.findMany': (arg: any) => {
        if (arg?.select?.endpoint) {
          return [
            { endpoint: '/mobile-user-create', payload: { username: 'john' } },
          ];
        }
        if (arg?.select?.createdAt) return [];
        return undefined;
      },
      // Server currently has mary (incoming), john (queued create), bob (stale).
      'staff.findMany': () => [
        { username: 'mary' },
        { username: 'john' },
        { username: 'bob' },
      ],
    });
    const ingest = makeIngestService(prisma);

    await ingest.execute({
      businessDate: BUSINESS_DATE,
      // POS snapshot only knows about mary.
      staff: [{ username: 'mary', role: 'WAITER', pin: '1234' }],
    } as any);

    const del = calls.find((c) => c.key === 'staff.deleteMany');
    expect(del).toBeDefined();
    const deleted: string[] = del!.arg.where.username.in;
    expect(deleted).toContain('bob'); // stale → removed
    expect(deleted).not.toContain('john'); // protected by queued create
    expect(deleted).not.toContain('mary'); // present in POS snapshot
  });
});
