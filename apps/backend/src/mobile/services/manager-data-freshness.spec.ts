import { of, firstValueFrom } from 'rxjs';
import type { CallHandler, ExecutionContext } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import {
  managerSource,
  recordManagerSource,
  ManagerDataFreshnessInterceptor,
  FRESHNESS_HEADER,
} from './manager-data-freshness';
import type { PosAuthContext } from '../../auth/pos-auth-context';
import type { SyncPayload } from '../../pos/sync/sync-payload';

describe('MGR04 accepted source provenance', () => {
  const auth: PosAuthContext = {
    venueId: 'venue-a',
    organizationId: 'org-a',
    deviceId: 'device-a',
    authenticationMode: 'device',
  };
  let values: Map<string, string>, db: PrismaService, primary: string | null;
  const full = (): SyncPayload => ({
    syncedAt: '2026-10-07T10:00:00Z',
    businessDate: '2026-10-07',
    tableLayout: { version: 1, physicalTableIds: [] },
    tables: [],
    orders: [],
    reservations: [],
    menu: [],
    salesHistoryByDate: {},
    salesSummary: {
      date: '2026-10-07',
      totalRevenue: 0,
      orderCount: 0,
      cashRevenue: 0,
      cardRevenue: 0,
      paymentBreakdown: {},
    },
  });
  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-10-07T11:00:00Z'));
    values = new Map();
    primary = 'device-a';
    db = {
      setting: {
        findMany: jest.fn(
          (args: { where: { venueId: string; key: { in: string[] } } }) =>
            Promise.resolve(
              args.where.key.in.flatMap((key) => {
                const value = values.get(args.where.venueId + ':' + key);
                return value ? [{ key, value }] : [];
              }),
            ),
        ),
        upsert: jest.fn(
          async (args: {
            create: { key: string; value: string; venueId: string };
          }) => {
            values.set(
              args.create.venueId + ':' + args.create.key,
              args.create.value,
            );
            await Promise.resolve();
          },
        ),
        findUnique: jest.fn(
          async (args: {
            where: { venueId_key: { key: string; venueId: string } };
          }) => {
            const value = values.get(
              args.where.venueId_key.venueId + ':' + args.where.venueId_key.key,
            );
            return await Promise.resolve(value ? { value } : null);
          },
        ),
      },
      venue: {
        findUnique: jest.fn(() =>
          Promise.resolve({
            activeOperationalDeviceId: primary,
            menuAuthority: 'POS',
          }),
        ),
      },
      saleLedgerDay: { findUnique: jest.fn(() => Promise.resolve(null)) },
    } as unknown as PrismaService;
  });
  afterEach(() => jest.useRealTimers());
  test('summary-only upload cannot freshen retained COMPLETE ledger totals', async () => {
    values.set('venue-a:currentBusinessDate', '2026-10-07');
    (db.saleLedgerDay.findUnique as jest.Mock).mockResolvedValue({
      completeness: 'COMPLETE',
    });
    await recordManagerSource(
      db,
      auth,
      {
        ...full(),
        saleLedgerDays: [
          {
            businessDate: '2026-10-07',
            expectedSaleCount: 0,
            expectedRevenue: '0.00',
            uploadComplete: true,
          },
        ],
      },
      true,
      true,
      true,
    );
    await recordManagerSource(
      db,
      auth,
      { ...full(), syncedAt: '2026-10-07T10:30:00Z' },
      true,
      true,
    );
    expect((await managerSource(db, auth, 'dashboard')).sourceUpdatedAt).toBe(
      '2026-10-07T10:00:00.000Z',
    );
    expect((await managerSource(db, auth, 'financials')).sourceUpdatedAt).toBe(
      '2026-10-07T10:00:00.000Z',
    );
  });
  test('ledger read for an uncovered date/range remains unknown', async () => {
    values.set('venue-a:currentBusinessDate', '2026-10-07');
    const headers: Record<string, string> = {};
    const context = {
      getHandler: () => function getFinancialSummary() {},
      switchToHttp: () => ({
        getRequest: () => ({
          user: auth,
          query: { from: '2026-10-06', to: '2026-10-07' },
        }),
        getResponse: () => ({
          setHeader: (key: string, value: string) => {
            headers[key] = value;
          },
        }),
      }),
    } as unknown as ExecutionContext;
    await firstValueFrom(
      await new ManagerDataFreshnessInterceptor(db).intercept(context, {
        handle: () => of({ total: 0 }),
      }),
    );
    expect(JSON.parse(headers[FRESHNESS_HEADER])).toMatchObject({
      sourceUpdatedAt: null,
      completeness: 'UNKNOWN',
    });
  });
  test('accepted UTC source differs from server receipt and GET never freshens either', async () => {
    await recordManagerSource(db, auth, full(), true, true);
    const first = await managerSource(db, auth, 'dashboard');
    expect(first).toMatchObject({
      source: 'POS',
      sourceUpdatedAt: '2026-10-07T10:00:00.000Z',
      receivedAt: '2026-10-07T11:00:00.000Z',
      completeness: 'KNOWN',
    });
    jest.setSystemTime(new Date('2026-10-07T18:00:00Z'));
    expect(await managerSource(db, auth, 'dashboard')).toEqual(first);
  });
  test.each(['2026-10-07T10:00:00', 'garbage', '2026-10-07T12:00:00Z'])(
    'ambiguous/invalid/future clock %s stays unknown',
    async (time) => {
      await recordManagerSource(
        db,
        auth,
        { ...full(), syncedAt: time },
        true,
        true,
      );
      expect(await managerSource(db, auth, 'dashboard')).toMatchObject({
        sourceUpdatedAt: null,
        completeness: 'UNKNOWN',
        receivedAt: '2026-10-07T11:00:00.000Z',
      });
    },
  );
  test('skipped cold table snapshot cannot advance table or dashboard source', async () => {
    await recordManagerSource(db, auth, full(), true, true);
    const previous = await managerSource(db, auth, 'tables');
    await recordManagerSource(
      db,
      auth,
      { ...full(), syncedAt: '2026-10-07T10:30:00Z' },
      false,
      true,
    );
    expect(await managerSource(db, auth, 'tables')).toEqual(previous);
    expect((await managerSource(db, auth, 'dashboard')).sourceUpdatedAt).toBe(
      previous.sourceUpdatedAt,
    );
  });
  test('realtime and omission cannot advance financial/history/reservations source', async () => {
    await recordManagerSource(db, auth, full(), true, true);
    await recordManagerSource(
      db,
      auth,
      {
        realtimeOnly: true,
        syncedAt: '2026-10-07T10:30:00Z',
        tables: [],
        orders: [],
      },
      true,
      false,
    );
    expect((await managerSource(db, auth, 'tables')).sourceUpdatedAt).toBe(
      '2026-10-07T10:30:00.000Z',
    );
    for (const block of [
      'dashboard',
      'financials',
      'sales_daily',
      'reservations',
    ] as const)
      expect((await managerSource(db, auth, block)).sourceUpdatedAt).toBe(
        '2026-10-07T10:00:00.000Z',
      );
  });
  test('skipped reservation rows are explicit partial', async () => {
    await recordManagerSource(db, auth, full(), true, false);
    expect((await managerSource(db, auth, 'reservations')).completeness).toBe(
      'PARTIAL',
    );
  });
  test('primary replacement, other tenant and corrupt legacy setting invalidate source', async () => {
    await recordManagerSource(db, auth, full(), true, true);
    expect(
      (await managerSource(db, { ...auth, venueId: 'venue-b' }, 'dashboard'))
        .source,
    ).toBe('UNKNOWN');
    primary = 'device-b';
    expect(
      (await managerSource(db, auth, 'dashboard')).sourceUpdatedAt,
    ).toBeNull();
    values.set('venue-a:manager:data-freshness:dashboard', 'bad-json');
    expect((await managerSource(db, auth, 'dashboard')).completeness).toBe(
      'UNKNOWN',
    );
  });
  test('counted menus are Cloud data and unsupported staff attribution is unavailable', async () => {
    expect((await managerSource(db, auth, 'counted_menus')).source).toBe(
      'CLOUD',
    );
    expect(
      (await managerSource(db, auth, 'staff_performance')).completeness,
    ).toBe('UNAVAILABLE');
  });
  test('metadata is read before handler data so concurrent ingest cannot label old payload newer', async () => {
    await recordManagerSource(db, auth, full(), true, true);
    const headers: Record<string, string> = {};
    const context = {
      getHandler: () => function getTables() {},
      switchToHttp: () => ({
        getRequest: () => ({ user: auth }),
        getResponse: () => ({
          setHeader: (key: string, value: string) => {
            headers[key] = value;
          },
        }),
      }),
    } as unknown as ExecutionContext;
    const next: CallHandler = {
      handle: () => {
        values.set(
          'venue-a:manager:data-freshness:tables',
          JSON.stringify({
            source: 'POS',
            sourceUpdatedAt: '2026-10-07T10:30:00Z',
            receivedAt: '2026-10-07T11:00:00Z',
            deviceId: 'device-a',
          }),
        );
        return of([{ id: 'old-or-new-complete-snapshot' }]);
      },
    };
    await firstValueFrom(
      await new ManagerDataFreshnessInterceptor(db).intercept(context, next),
    );
    expect(JSON.parse(headers[FRESHNESS_HEADER])).toMatchObject({
      sourceUpdatedAt: null,
      completeness: 'UNKNOWN',
    });
  });
});
