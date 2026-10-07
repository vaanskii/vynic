import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma.service';
import { MobileController } from '../mobile.controller';
import { MobileDashboardService } from './mobile-dashboard.service';
import { requestTableRepair } from './manager-table-repair';
import { JwtStrategy } from '../../auth/jwt.strategy';
import { ManagerTenantService } from '../../auth/manager-tenant.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { EdgeTransportController } from '../../edge/edge-transport.controller';
import { EdgeCommandService } from '../../edge/edge-command.service';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { seedMenu03 } from '../../../test/menu03.fixture';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { InventoryService } from '../../inventory/inventory.service';
import { SaleConsumptionService } from '../../inventory/sale-consumption.service';
import { DeviceCredentialService } from '../../auth/device-credential.service';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';

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
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const url = process.env.MGR01_TEST_DATABASE_URL;
const integration = url ? describe : describe.skip;
integration('MGR01 generic layout real HTTP/PostgreSQL', () => {
  let db: PrismaService,
    app: Awaited<ReturnType<typeof onboardingApp>>,
    base: string;
  let seeded: Awaited<ReturnType<typeof seedMenu03>>,
    token: string,
    venueId: string;
  const ids = Array.from({ length: 7 }, () => randomUUID());
  const day = '2026-10-07';
  const physical = () => [
    {
      tableId: ids[0],
      tableNumber: '10',
      floor: 'first',
      tableKind: 'PHYSICAL',
      tableLabel: 'Main 10',
      floorLabel: 'Main hall',
      floorSortOrder: 2,
      tableSortOrder: 10,
      isReserved: true,
      activeOrderId: 70,
      currentBill: 45,
    },
    {
      tableId: ids[1],
      tableNumber: '1',
      floor: 'terrace',
      tableKind: 'PHYSICAL',
      tableLabel: 'Terrace 1',
      floorLabel: 'Terrace',
      floorSortOrder: 1,
      tableSortOrder: 1,
      isReserved: false,
      currentBill: 0,
    },
    {
      tableId: ids[2],
      tableNumber: '11',
      floor: 'second',
      tableKind: 'PHYSICAL',
      tableLabel: 'VIP 11',
      floorLabel: 'VIP',
      floorSortOrder: 3,
      tableSortOrder: 11,
      isReserved: false,
      currentBill: 0,
    },
    {
      tableId: ids[3],
      tableNumber: 'Table Garden',
      floor: 'ქართული სართული',
      tableKind: 'PHYSICAL',
      tableLabel: 'ბაღის მაგიდა',
      floorLabel: 'ქართული დარბაზი',
      floorSortOrder: 4,
      tableSortOrder: 1,
      isReserved: true,
      currentBill: 0,
    },
    {
      tableId: ids[4],
      tableNumber: '1',
      floor: 'takeaway lounge',
      tableKind: 'PHYSICAL',
      tableLabel: 'Lounge 1',
      floorLabel: 'Lounge',
      floorSortOrder: 5,
      tableSortOrder: 1,
      isReserved: true,
      activeOrderId: 71,
      currentBill: 20,
    },
    {
      tableId: ids[5],
      tableNumber: '2',
      floor: 'first',
      tableKind: 'PHYSICAL',
      tableLabel: 'Main 2',
      floorLabel: 'Main hall',
      floorSortOrder: 2,
      tableSortOrder: 2,
      isReserved: true,
      activeOrderId: 70,
      currentBill: 45,
    },
    {
      tableId: ids[6],
      tableNumber: '3',
      floor: 'first',
      tableKind: 'PHYSICAL',
      tableLabel: 'Main 3',
      floorLabel: 'Main hall',
      floorSortOrder: 2,
      tableSortOrder: 3,
      isReserved: true,
      activeOrderId: 999,
      currentBill: 17,
    },
  ];
  const orders = () => [
    {
      posOrderId: 70,
      status: 'confirmed',
      totalAmount: 45,
      businessDate: day,
      tableNumbers: ['10', '2'],
      tableIds: [ids[0], ids[5]],
      floor: 'first',
      items: [],
    },
    {
      posOrderId: 71,
      status: 'confirmed',
      totalAmount: 20,
      businessDate: day,
      tableNumbers: ['1'],
      tableIds: [ids[4]],
      floor: 'takeaway lounge',
      items: [],
    },
    {
      posOrderId: 72,
      status: 'confirmed',
      totalAmount: 500,
      businessDate: day,
      tableNumbers: ['carrier'],
      floor: 'transport',
      items: [],
    },
  ];
  const snapshot = () => ({
    realtimeOnly: true,
    businessDate: day,
    tables: [
      ...physical(),
      {
        tableNumber: 'carrier',
        floor: 'transport',
        isReserved: true,
        activeOrderId: 72,
        currentBill: 500,
        tableKind: 'VIRTUAL',
      },
    ],
    orders: orders(),
    tableLayout: { version: 1, physicalTableIds: ids },
  });
  const post = async (
    payload: unknown,
    credential = seeded.venues[0].credential,
  ) => {
    const r = await fetch(base + '/sync/manager-data', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-POS-Sync-Key': credential,
        'X-Vynic-Menu-Client': JSON.stringify({
          version: 1,
          capabilities: ['CANONICAL_MENU_V2'],
        }),
      },
      body: JSON.stringify(payload),
    });
    return { status: r.status, body: (await r.json()) as any };
  };
  const get = async (path: string, auth = token) => {
    const r = await fetch(base + path, {
      headers: auth ? { Authorization: `Bearer ${auth}` } : {},
    });
    return { status: r.status, body: (await r.json()) as any };
  };
  beforeAll(async () => {
    if (!url || !isFreshDisposableDatabase(url))
      throw Error('Fresh disposable MGR01 database required');
    process.env.JWT_SECRET = 'mgr01-synthetic-only-signing';
    process.env.COOKIE_ENCRYPTION_KEY = 'mgr01-synthetic-only-cookie';
    db = new PrismaService({ datasourceUrl: url });
    const gateway = { broadcastUpdate: jest.fn() };
    const connection = {
      restore: async () => {},
      register: async () => {},
      hasCallbackUrl: () => true,
    };
    const ingest = new IngestPosSnapshotService(
      { kickPending: async () => {} } as any,
      connection as any,
      new MenuSyncService(db),
      new TableSyncService(db),
      new OrderSyncService(db),
      new ReservationSyncService(db),
      { withDatabase: () => ({}) } as any,
      new BusinessDaySyncService(db),
      new SyncBroadcastService(db, gateway as any),
    );
    const deps: any[] = Reflect.getMetadata(
      'design:paramtypes',
      MobileController,
    );
    app = await onboardingApp(db, undefined, {
      controllers: [MobileController, SyncController],
      providers: [
        ...deps
          .filter((t) => t !== VenueEntitlementsService)
          .map((t) => ({
            provide: t,
            useValue:
              t === MobileDashboardService
                ? new MobileDashboardService(
                    db,
                    gateway as any,
                    {} as any,
                    {} as any,
                  )
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
    const feature = await db.feature.upsert({
      where: { key: 'MANAGER_APP' },
      update: {},
      create: { key: 'MANAGER_APP', name: 'Synthetic Manager' },
    });
    const assignment = await db.venuePlanAssignment.findUniqueOrThrow({
      where: { venueId },
    });
    await db.planFeature.upsert({
      where: {
        planId_featureId: { planId: assignment.planId, featureId: feature.id },
      },
      update: {},
      create: { planId: assignment.planId, featureId: feature.id },
    });
    const staff = await db.staff.create({
      data: {
        venueId,
        username: 'mgr01-synthetic-' + randomUUID(),
        role: 'MANAGER',
        pinHash: 'unused-synthetic',
      },
    });
    token = new JwtService().sign(
      { sub: staff.id, venueId: seeded.venues[1].venueId },
      { secret: process.env.JWT_SECRET },
    );
    await db.venue.update({
      where: { id: venueId },
      data: {
        activeOperationalDeviceId: seeded.venues[0].credential.split('.')[1],
      },
    });
  }, 60000);
  beforeEach(async () => {
    await db.order.deleteMany({ where: { venueId } });
    await db.table.deleteMany({ where: { venueId } });
    await db.setting.upsert({
      where: { venueId_key: { venueId, key: 'currentBusinessDate' } },
      update: { value: day },
      create: { venueId, key: 'currentBusinessDate', value: day },
    });
  });
  afterAll(async () => {
    await app?.close();
    await db?.$disconnect();
  });
  test('additive migration preserves pre-layout table identity and occupancy', async () => {
    const row = await db.table.create({
      data: {
        venueId,
        floor: 'terrace',
        tableNumber: '1',
        isReserved: true,
        activeOrderId: 55,
        currentBill: 30,
      },
    });
    await db.$transaction(async (tx) => {
      await tx.$executeRawUnsafe(
        'ALTER TABLE "pos"."Table" DROP CONSTRAINT "Table_tableKind_check"',
      );
      for (const field of [
        'tableKind',
        'tableLabel',
        'floorLabel',
        'tableSortOrder',
        'floorSortOrder',
      ])
        await tx.$executeRawUnsafe(
          `ALTER TABLE "pos"."Table" DROP COLUMN "${field}"`,
        );
      const sql = readFileSync(
        join(
          process.cwd(),
          'prisma/migrations/20261007120000_manager_table_layout/migration.sql',
        ),
        'utf8',
      );
      for (const statement of sql
        .split(';')
        .map((s) => s.trim())
        .filter(Boolean))
        await tx.$executeRawUnsafe(statement);
    });
    const after = await db.table.findUniqueOrThrow({ where: { id: row.id } });
    expect(after).toMatchObject({
      id: row.id,
      activeOrderId: 55,
      currentBill: 30,
      isReserved: true,
      tableKind: null,
    });
  });
  test('HTTP tables/dashboard include generic floors, preserve aliases and deduplicate merged payable', async () => {
    expect((await post(snapshot())).status).toBe(201);
    const tables = await get('/mobile/tables');
    expect(tables.status).toBe(200);
    expect(tables.body).toHaveLength(7);
    expect(tables.body.map((t: any) => [t.floor, t.tableNumber])).toEqual([
      ['terrace', '1'],
      ['first', '2'],
      ['first', '3'],
      ['first', '10'],
      ['second', '11'],
      ['ქართული სართული', 'Table Garden'],
      ['takeaway lounge', '1'],
    ]);
    const metrics = await get('/mobile/dashboard');
    expect(metrics.status).toBe(200);
    expect(metrics.body).toMatchObject({
      totalTables: 7,
      occupiedTables: 4,
      reservedTables: 1,
      freeTables: 2,
      activeTablesCount: 5,
      openTablesPayable: 65,
      occupancyPercentage: 71.4,
    });
    if (process.env.MGR01_FIXTURE_OUTPUT)
      writeFileSync(
        process.env.MGR01_FIXTURE_OUTPUT,
        JSON.stringify(
          { tables: tables.body, dashboard: metrics.body },
          null,
          2,
        ),
      );
  });
  test('legacy unknown custom rows stay visible; names never classify a virtual carrier', async () => {
    await db.table.createMany({
      data: [
        { venueId, tableNumber: 'TA-1', floor: 'custom' },
        { venueId, tableNumber: '5', floor: 'second' },
        { venueId, tableNumber: '1', floor: 'transport', tableKind: 'VIRTUAL' },
      ],
    });
    expect(
      (await get('/mobile/tables')).body.map((t: any) => t.tableNumber),
    ).toEqual(['TA-1', '5']);
    expect((await get('/mobile/dashboard')).body.totalTables).toBe(2);
  });
  test('legacy partial snapshots preserve classification and do not retire omitted physical rows', async () => {
    await post(snapshot());
    expect(
      (
        await post({
          realtimeOnly: true,
          tables: [
            {
              tableId: ids[0],
              tableNumber: '10',
              floor: 'first',
              isReserved: false,
            },
          ],
        })
      ).status,
    ).toBe(201);
    const row = await db.table.findUniqueOrThrow({ where: { id: ids[0] } });
    expect(row.tableLabel).toBe('Main 10');
    expect(row.tableKind).toBe('PHYSICAL');
    expect((await get('/mobile/tables')).body).toHaveLength(7);
    expect(
      (
        await db.table.findFirstOrThrow({
          where: { venueId, floor: 'transport' },
        })
      ).tableKind,
    ).toBe('VIRTUAL');
  });
  test('complete layout retires deleted physical rows and order-created carriers, preserving retained occupancy', async () => {
    await post(snapshot());
    const data = snapshot();
    data.tables = data.tables.filter((t) => t.tableId !== ids[2]);
    data.tableLayout.physicalTableIds = ids.filter((id) => id !== ids[2]);
    data.orders.push({
      posOrderId: 73,
      status: 'confirmed',
      totalAmount: 80,
      businessDate: day,
      tableNumbers: ['new-carrier'],
      floor: 'transport',
      items: [],
    } as any);
    expect((await post(data)).status).toBe(201);
    expect((await get('/mobile/tables')).body).toHaveLength(6);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[2] } })).tableKind,
    ).toBe('VIRTUAL');
    expect(
      (
        await db.table.findFirstOrThrow({
          where: { venueId, tableNumber: 'new-carrier' },
        })
      ).tableKind,
    ).toBe('VIRTUAL');
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[0] } }))
        .activeOrderId,
    ).toBe(70);
  });
  test('UUID rename/adoption and order linking retain exact Table-prefixed physical aliases', async () => {
    await db.table.create({
      data: { venueId, floor: 'first', tableNumber: '10' },
    });
    await post(snapshot());
    const data = snapshot();
    data.tables[0].tableNumber = 'Table Garden 2';
    data.orders[0].tableNumbers = ['Table Garden 2', '2'];
    expect((await post(data)).status).toBe(201);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[0] } })).tableNumber,
    ).toBe('Table Garden 2');
    expect(
      await db.table.count({ where: { venueId, tableNumber: 'Garden 2' } }),
    ).toBe(0);
  });
  test('cold all-free full snapshot preserves existing table occupancy and layout classification', async () => {
    await post(snapshot());
    const data = snapshot();
    delete (data as any).orders;
    data.realtimeOnly = false;
    data.tables = data.tables.map((t) => ({
      ...t,
      isReserved: false,
      activeOrderId: undefined,
      currentBill: 0,
    }));
    expect((await post(data)).status).toBe(201);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[0] } }))
        .activeOrderId,
    ).toBe(70);
    expect((await get('/mobile/tables')).body).toHaveLength(7);
  });
  test('retained display-era UUID orders resolve the current layout alias and floor', async () => {
    const data = snapshot();
    data.orders[0].tableNumbers = ['Table 10', 'Table 2'];
    data.orders.push({
      posOrderId: 74,
      status: 'confirmed',
      totalAmount: 5,
      businessDate: day,
      tableNumbers: ['21'],
      tableIds: [ids[2]],
      floor: 'second',
      items: [],
    } as any);
    expect((await post(data)).status).toBe(201);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[0] } })).tableNumber,
    ).toBe('10');
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[2] } })).tableNumber,
    ).toBe('11');
    expect(
      await db.table.count({
        where: { venueId, tableNumber: { in: ['Table 10', '21'] } },
      }),
    ).toBe(0);
  });
  test('cold empty complete layout cannot hide retained occupancy; explicit realtime empty layout retires it', async () => {
    await post(snapshot());
    const data = {
      realtimeOnly: false,
      tables: [],
      tableLayout: { version: 1, physicalTableIds: [] },
    };
    expect((await post(data)).status).toBe(201);
    expect((await get('/mobile/tables')).body).toHaveLength(7);
    expect((await post({ ...data, realtimeOnly: true })).status).toBe(201);
    expect((await get('/mobile/tables')).body).toHaveLength(0);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: ids[0] } }))
        .activeOrderId,
    ).toBe(70);
  });
  test('Manager/device tenant authority rejects unsigned/nonprimary requests and ignores spoofed tenant', async () => {
    expect((await get('/mobile/tables', '')).status).toBe(401);
    const response = await post({
      ...snapshot(),
      venueId: seeded.venues[1].venueId,
    });
    expect(response.status).toBe(201);
    expect(
      await db.table.count({ where: { venueId: seeded.venues[1].venueId } }),
    ).toBe(0);
    const replacement = await app
      .get(DeviceCredentialService)
      .issueCredential({
        venueId,
        installationId: randomUUID(),
        displayName: 'Synthetic secondary',
        platform: 'WINDOWS',
      });
    expect((await post(snapshot(), replacement.credential)).status).toBe(403);
  });
  for (const malformed of [
    'kind',
    'missing_label',
    'fractional_order',
    'floor_conflict',
    'duplicate_id',
    'duplicate_alias',
    'incomplete_membership',
    'missing_tables',
    'bad_version',
  ]) {
    test(`malformed ${malformed} projection fails before any partial snapshot write`, async () => {
      await post(snapshot());
      const before = await db.table.findMany({
        where: { venueId },
        orderBy: { id: 'asc' },
      });
      const data: any = snapshot();
      data.tables[0].currentBill = 999;
      if (malformed === 'kind') data.tables[1].tableKind = 'mystery';
      if (malformed === 'missing_label') delete data.tables[1].tableLabel;
      if (malformed === 'fractional_order') data.tables[1].tableSortOrder = 1.5;
      if (malformed === 'floor_conflict')
        data.tables[0].floorLabel = 'different';
      if (malformed === 'duplicate_id') data.tables[1].tableId = ids[0];
      if (malformed === 'duplicate_alias') {
        data.tables[1].floor = 'first';
        data.tables[1].tableNumber = '10';
      }
      if (malformed === 'incomplete_membership')
        data.tableLayout.physicalTableIds = ids.slice(1);
      if (malformed === 'missing_tables') delete data.tables;
      if (malformed === 'bad_version') data.tableLayout.version = 99;
      expect((await post(data)).status).toBe(400);
      expect(
        await db.table.findMany({ where: { venueId }, orderBy: { id: 'asc' } }),
      ).toEqual(before);
    });
  }
});
