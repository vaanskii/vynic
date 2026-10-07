import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import type { Type } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MobileController } from '../mobile.controller';
import { MobileDashboardService } from './mobile-dashboard.service';
import { MobileReportsService } from './mobile-reports.service';
import { MobileSaleLedgerService } from './mobile-sale-ledger.service';
import { MobileReservationsService } from './mobile-reservations.service';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { JwtStrategy } from '../../auth/jwt.strategy';
import { ManagerTenantService } from '../../auth/manager-tenant.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { LegacyPosTenantService } from '../../auth/legacy-pos-tenant.service';
import { SyncController } from '../../pos/sync/sync.controller';
import { IngestPosSnapshotService } from '../../pos/sync/application/ingest-pos-snapshot.service';
import { IngestAuditReportsService } from '../../pos/sync/application/ingest-audit-reports.service';
import { PosConnectionRegistry } from '../../pos/sync/pos-connection.registry';
import { MenuSyncService } from '../../pos/sync/snapshot/menu-sync.service';
import { TableSyncService } from '../../pos/sync/snapshot/table-sync.service';
import { OrderSyncService } from '../../pos/sync/snapshot/order-sync.service';
import { ReservationSyncService } from '../../pos/sync/snapshot/reservation-sync.service';
import { BusinessDaySyncService } from '../../pos/sync/snapshot/business-day-sync.service';
import { SyncBroadcastService } from '../../pos/sync/snapshot/sync-broadcast.service';
import { SaleLedgerSyncService } from '../../pos/sync/snapshot/sale-ledger-sync.service';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { seedMenu03 } from '../../../test/menu03.fixture';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import type { ManagerSourceStamp } from './manager-data-freshness';
import type { TenantContext } from '../../auth/pos-auth-context';
import { writeFileSync } from 'node:fs';

function stub<T>(value: unknown): T {
  return value as T;
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw Error('Expected record');
  return value as Record<string, unknown>;
}
const url = process.env.MGR04_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'MGR04 real HTTP/PostgreSQL source metadata',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      base: string;
    let seeded: Awaited<ReturnType<typeof seedMenu03>>,
      venueId: string,
      token: string,
      dashboard: MobileDashboardService;
    const id = randomUUID(),
      day = '2026-10-07',
      source1 = '2026-10-07T09:00:00.000Z',
      source2 = '2026-10-07T09:30:00.000Z';
    const summary = {
      date: day,
      totalRevenue: 120,
      orderCount: 1,
      cashRevenue: 120,
      cardRevenue: 0,
      paymentBreakdown: { cash: 120 },
    };
    const snapshot = () => ({
      syncedAt: source1,
      businessDate: day,
      tables: [
        {
          tableId: id,
          tableNumber: '1',
          floor: 'main',
          tableKind: 'PHYSICAL',
          tableLabel: 'Main 1',
          floorLabel: 'Main',
          tableSortOrder: 1,
          floorSortOrder: 1,
          isReserved: true,
          activeOrderId: 7,
          currentBill: 45,
        },
      ],
      tableLayout: { version: 1, physicalTableIds: [id] },
      orders: [
        {
          posOrderId: 7,
          status: 'confirmed',
          totalAmount: 45,
          businessDate: day,
          tableNumbers: ['1'],
          tableIds: [id],
          floor: 'main',
          items: [],
        },
      ],
      reservations: [],
      salesSummary: summary,
      salesAllTimeSummary: {
        totalRevenue: 120,
        orderCount: 1,
        cashRevenue: 120,
        cardRevenue: 0,
        paymentBreakdown: { cash: 120 },
        topItems: [{ name: 'Synthetic', qty: 1, revenue: 120 }],
      },
      salesHistoryByDate: {
        [day]: { ...summary, totalOrders: 1, cancelledOrders: 0 },
      },
    });
    async function post(
      data: unknown,
      credential = seeded.venues[0].credential,
    ) {
      const response = await fetch(base + '/sync/manager-data', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-POS-Sync-Key': credential,
          'X-Vynic-Menu-Client': JSON.stringify({
            version: 1,
            capabilities: ['CANONICAL_MENU_V2'],
          }),
        },
        body: JSON.stringify(data),
      });
      return {
        status: response.status,
        body: (await response.json()) as unknown,
      };
    }
    async function get(path: string, auth = token) {
      const response = await fetch(base + path, {
        headers: auth ? { Authorization: `Bearer ${auth}` } : {},
      });
      const header = response.headers.get('x-vynic-data-freshness');
      return {
        status: response.status,
        body: (await response.json()) as unknown,
        freshness: header ? (JSON.parse(header) as ManagerSourceStamp) : null,
      };
    }
    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url))
        throw Error('Fresh disposable MGR04 database required');
      process.env.JWT_SECRET = 'mgr04-synthetic-only-signing';
      process.env.COOKIE_ENCRYPTION_KEY = 'mgr04-synthetic-only-cookie';
      db = new PrismaService({ datasourceUrl: url });
      const gateway = { broadcastUpdate: jest.fn() },
        connection = {
          restore: async () => {},
          register: async () => {},
          hasCallbackUrl: () => true,
        };
      const ingest = new IngestPosSnapshotService(
        stub({ kickPending: async () => {} }),
        stub(connection),
        new MenuSyncService(db),
        new TableSyncService(db),
        new OrderSyncService(db),
        new ReservationSyncService(db),
        stub({ withDatabase: () => ({}) }),
        new BusinessDaySyncService(db),
        new SyncBroadcastService(db, stub(gateway)),
        new SaleLedgerSyncService(db),
      );
      dashboard = new MobileDashboardService(
        db,
        stub(gateway),
        stub({}),
        stub({}),
        new MobileSaleLedgerService(db),
      );
      const reservations = new MobileReservationsService(
        new PosReservationMirrorService(db),
        stub({}),
        stub(gateway),
        stub({}),
        db,
      );
      const deps = Reflect.getMetadata(
        'design:paramtypes',
        MobileController,
      ) as Type<unknown>[];
      app = await onboardingApp(db, undefined, {
        controllers: [MobileController, SyncController],
        providers: [
          ...deps
            .filter((t) => t !== VenueEntitlementsService)
            .map((t) => ({
              provide: t,
              useValue:
                t === MobileDashboardService
                  ? dashboard
                  : t === MobileReportsService
                    ? new MobileReportsService(db)
                    : t === MobileSaleLedgerService
                      ? new MobileSaleLedgerService(db)
                      : t === MobileReservationsService
                        ? reservations
                        : {},
            })),
          JwtStrategy,
          ManagerTenantService,
          LegacyPosTenantService,
          { provide: IngestPosSnapshotService, useValue: ingest },
          { provide: IngestAuditReportsService, useValue: {} },
          { provide: PosConnectionRegistry, useValue: connection },
        ],
      });
      await app.listen(0, '127.0.0.1');
      base = await app.getUrl();
      seeded = await seedMenu03(db, app);
      venueId = seeded.venues[0].venueId;
      const assignment = await db.venuePlanAssignment.findUniqueOrThrow({
        where: { venueId },
      });
      for (const key of ['MANAGER_APP', 'MANAGER_RESERVATIONS']) {
        const feature = await db.feature.upsert({
          where: { key },
          update: {},
          create: { key, name: 'Synthetic ' + key },
        });
        await db.planFeature.upsert({
          where: {
            planId_featureId: {
              planId: assignment.planId,
              featureId: feature.id,
            },
          },
          update: {},
          create: { planId: assignment.planId, featureId: feature.id },
        });
      }
      const staff = await db.staff.create({
        data: {
          venueId,
          username: 'mgr04-' + randomUUID(),
          role: 'MANAGER',
          pinHash: 'unused-synthetic',
        },
      });
      token = new JwtService().sign(
        { sub: staff.id, venueId: seeded.venues[1].venueId },
        { secret: process.env.JWT_SECRET },
      );
    }, 60000);
    beforeEach(async () => {
      await db.venue.update({
        where: { id: venueId },
        data: {
          activeOperationalDeviceId: seeded.venues[0].credential.split('.')[1],
        },
      });
      await db.order.deleteMany({ where: { venueId } });
      await db.table.deleteMany({ where: { venueId } });
      await db.posReservation.deleteMany({ where: { venueId } });
      await db.saleLedgerDay.deleteMany({ where: { venueId } });
      await db.setting.deleteMany({
        where: {
          venueId,
          OR: [
            { key: { startsWith: 'manager:data-freshness:' } },
            { key: { startsWith: 'salesSummary:' } },
          ],
        },
      });
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });
    test('real accepted source survives repeated GET and appears in dashboard model', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const first = await get('/mobile/dashboard'),
        second = await get('/mobile/dashboard');
      expect(first.status).toBe(200);
      expect(first.freshness).toMatchObject({
        source: 'POS',
        sourceUpdatedAt: source1,
        completeness: 'KNOWN',
      });
      expect(record(first.body).snapshotAt).toBe(source1);
      expect(second.freshness).toEqual(first.freshness);
      expect(first.freshness?.receivedAt).not.toBe(source1);
      if (process.env.MGR04_FIXTURE_OUTPUT)
        writeFileSync(
          process.env.MGR04_FIXTURE_OUTPUT,
          JSON.stringify(
            { dashboard: first, tables: await get('/mobile/tables') },
            null,
            2,
          ),
        );
    });
    test('API up/POS idle retains source time and partial ledger warning', async () => {
      expect(
        (
          await post({
            ...snapshot(),
            saleLedger: [],
            saleLedgerDays: [
              {
                businessDate: day,
                expectedSaleCount: 99,
                expectedRevenue: '120.00',
                uploadComplete: false,
              },
            ],
          })
        ).status,
      ).toBe(201);
      const result = await get('/mobile/dashboard');
      expect(result.freshness?.sourceUpdatedAt).toBe(source1);
      expect(record(result.body).financialProvenance).toBe('PARTIAL');
      expect(record(result.body).financialWarning).toBeTruthy();
    });
    test('summary-only upload cannot freshen complete ledger; uncovered ranges stay unknown', async () => {
      expect(
        (
          await post({
            ...snapshot(),
            saleLedger: [],
            saleLedgerDays: [
              {
                businessDate: day,
                expectedSaleCount: 0,
                expectedRevenue: '0.00',
                uploadComplete: true,
              },
            ],
          })
        ).status,
      ).toBe(201);
      const first = await get('/mobile/dashboard');
      expect(record(first.body).financialProvenance).toBe('LEDGER_COMPLETE');
      expect(first.freshness?.sourceUpdatedAt).toBe(source1);
      expect((await post({ ...snapshot(), syncedAt: source2 })).status).toBe(
        201,
      );
      const second = await get('/mobile/dashboard');
      expect(record(second.body).financialProvenance).toBe('LEDGER_COMPLETE');
      expect(record(second.body).todayRevenue).toBe(
        record(first.body).todayRevenue,
      );
      expect(second.freshness?.sourceUpdatedAt).toBe(source1);
      expect(
        (await get('/mobile/financial-summary?from=2026-10-06&to=2026-10-07'))
          .freshness?.completeness,
      ).toBe('UNKNOWN');
      expect(
        (await get('/mobile/financial-summary?from=2026-10-07&to=2026-10-07'))
          .freshness?.sourceUpdatedAt,
      ).toBe(source1);
    });
    test('realtime advances tables while omitted reporting and reservations retain their age', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const { tables, tableLayout, orders } = snapshot();
      expect(
        (
          await post({
            realtimeOnly: true,
            businessDate: day,
            syncedAt: source2,
            tables,
            tableLayout,
            orders,
          })
        ).status,
      ).toBe(201);
      expect((await get('/mobile/tables')).freshness?.sourceUpdatedAt).toBe(
        source2,
      );
      expect((await get('/mobile/dashboard')).freshness?.sourceUpdatedAt).toBe(
        source1,
      );
      expect(
        (await get('/mobile/reservations')).freshness?.sourceUpdatedAt,
      ).toBe(source1);
    });
    test('cold all-free guard cannot freshen retained occupancy', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const cold = {
        ...snapshot(),
        syncedAt: source2,
        tables: snapshot().tables.map((t) => ({
          ...t,
          isReserved: false,
          activeOrderId: undefined,
          currentBill: 0,
        })),
        orders: [],
      };
      expect((await post(cold)).status).toBe(201);
      expect((await get('/mobile/tables')).freshness?.sourceUpdatedAt).toBe(
        source1,
      );
      expect((await get('/mobile/dashboard')).freshness?.sourceUpdatedAt).toBe(
        source1,
      );
    });
    test('legacy ambiguous source remains unknown, never HTTP now', async () => {
      expect(
        (await post({ ...snapshot(), syncedAt: '2026-10-07T09:00:00' })).status,
      ).toBe(201);
      const result = await get('/mobile/dashboard');
      expect(result.freshness).toMatchObject({
        sourceUpdatedAt: null,
        completeness: 'UNKNOWN',
      });
      expect(record(result.body).snapshotAt).toBeNull();
    });
    test('primary replacement invalidates stamp and another device cannot spoof Venue freshness', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const previous = (await get('/mobile/tables')).freshness;
      const otherId = randomUUID(),
        other = snapshot();
      await db.venue.update({
        where: { id: seeded.venues[1].venueId },
        data: {
          activeOperationalDeviceId: seeded.venues[1].credential.split('.')[1],
        },
      });
      expect(
        (
          await post(
            {
              ...other,
              venueId,
              syncedAt: source2,
              tables: other.tables.map((t) => ({ ...t, tableId: otherId })),
              tableLayout: { version: 1, physicalTableIds: [otherId] },
              orders: other.orders.map((o) => ({ ...o, tableIds: [otherId] })),
            },
            seeded.venues[1].credential,
          )
        ).status,
      ).toBe(201);
      expect((await get('/mobile/tables')).freshness).toEqual(previous);
      await db.venue.update({
        where: { id: venueId },
        data: { activeOperationalDeviceId: null },
      });
      expect((await get('/mobile/tables')).freshness).toMatchObject({
        sourceUpdatedAt: null,
        completeness: 'UNKNOWN',
      });
    });
    test('rejected transactional snapshot leaves value and metadata unchanged', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const previous = (await get('/mobile/tables')).freshness;
      expect(
        (
          await post({
            ...snapshot(),
            syncedAt: source2,
            orders: [
              {
                ...snapshot().orders[0],
                managerEditProjection: { broken: true },
              },
            ],
          })
        ).status,
      ).toBe(400);
      expect((await get('/mobile/tables')).freshness).toEqual(previous);
    });
    test('today-only upload cannot freshen all-time report; missing top-items are unavailable', async () => {
      expect((await post(snapshot())).status).toBe(201);
      const old = await get('/mobile/sales-report?period=all');
      expect(old.status).toBe(200);
      expect(old.freshness?.sourceUpdatedAt).toBe(source1);
      const today = Object.fromEntries(
        Object.entries(snapshot()).filter(
          ([key]) =>
            !['salesAllTimeSummary', 'salesHistoryByDate'].includes(key),
        ),
      );
      expect((await post({ ...today, syncedAt: source2 })).status).toBe(201);
      expect(
        (await get('/mobile/sales-report?period=all')).freshness
          ?.sourceUpdatedAt,
      ).toBe(source1);
      expect((await get('/mobile/top-items')).freshness?.completeness).toBe(
        'UNAVAILABLE',
      );
    });
    test('skipped malformed reservation rows return PARTIAL, not complete empty list', async () => {
      expect(
        (
          await post({
            ...snapshot(),
            reservations: [{ id: 'invalid-date', reservationDate: 'garbage' }],
          })
        ).status,
      ).toBe(201);
      const result = await get('/mobile/reservations');
      expect(result.status).toBe(200);
      expect(result.freshness?.completeness).toBe('PARTIAL');
    });
    test('concurrent source generation change marks returned data unknown', async () => {
      expect((await post(snapshot())).status).toBe(201);
      let enter: () => void = () => {},
        release: () => void = () => {};
      const entered = new Promise<void>((resolve) => {
          enter = resolve;
        }),
        blocked = new Promise<void>((resolve) => {
          release = resolve;
        });
      const original = dashboard.getTables.bind(dashboard) as (
        tenant: TenantContext,
      ) => Promise<unknown[]>;
      const spy = jest
        .spyOn(dashboard, 'getTables')
        .mockImplementationOnce(async (tenant) => {
          enter();
          await blocked;
          return original(tenant);
        });
      const pending = get('/mobile/tables');
      await entered;
      expect((await post({ ...snapshot(), syncedAt: source2 })).status).toBe(
        201,
      );
      release();
      const result = await pending;
      spy.mockRestore();
      expect(result.status).toBe(200);
      expect(result.freshness).toMatchObject({
        sourceUpdatedAt: null,
        completeness: 'UNKNOWN',
      });
    });
  },
);
