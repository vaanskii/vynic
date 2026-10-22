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
import { requestOrderEdit } from './manager-order-edit';
import { MobileOrdersService } from './mobile-orders.service';
import { OrderSyncService } from '../../pos/sync/snapshot/order-sync.service';
import { SyncController } from '../../pos/sync/sync.controller';
import { IngestPosSnapshotService } from '../../pos/sync/application/ingest-pos-snapshot.service';
import { IngestAuditReportsService } from '../../pos/sync/application/ingest-audit-reports.service';
import { PosConnectionRegistry } from '../../pos/sync/pos-connection.registry';
import { LegacyPosTenantService } from '../../auth/legacy-pos-tenant.service';
import { readFileSync } from 'node:fs';
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

const url = process.env.MGR05_TEST_DATABASE_URL;
const integration = url ? describe : describe.skip;
integration('MGR05 real guarded HTTP/PostgreSQL atomic edit lifecycle', () => {
  let db: PrismaService,
    app: Awaited<ReturnType<typeof onboardingApp>>,
    base: string;
  let seeded: Awaited<ReturnType<typeof seedMenu03>>,
    actor: ManagerAuthContext,
    token: string,
    deviceId: string,
    tableId: string,
    requestId: string;
  let fixture: any, baseline: any;
  const post = async (path: string, body: any, auth = token, edge = false) => {
    const r = await fetch(base + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(auth
          ? edge
            ? { 'X-POS-Sync-Key': auth }
            : { Authorization: `Bearer ${auth}` }
          : {}),
      },
      body: JSON.stringify(body),
    });
    return { status: r.status, body: (await r.json()) as any };
  };
  const body = () => ({ requestId, ...fixture.payload.request });
  const edit = (value: any = body(), auth = token, id = '1') =>
    post(`/mobile/order/${id}/edit-request`, value, auth);
  const claim = async (versions = [2, 1]) => {
    const r = await post(
      '/edge/commands/claim',
      { acceptedContractVersions: versions },
      seeded.venues[0].credential,
      true,
    );
    expect(r.status).toBe(201);
    return r.body.commands;
  };
  const ack = (
    id: string,
    value: any = {
      status: 'SUCCEEDED',
      code: 'order_edited',
      resultProjection: fixture.result,
    },
    credential = seeded.venues[0].credential,
  ) =>
    post('/edge/commands/ack', { commandId: id, ...value }, credential, true);
  const row = () =>
    db.order.findUniqueOrThrow({
      where: { venueId_posOrderId: { venueId: actor.venueId, posOrderId: 1 } },
      include: { items: true },
    });
  beforeAll(async () => {
    if (!url || !isFreshDisposableDatabase(url))
      throw Error('Fresh disposable MGR05 database required');
    process.env.JWT_SECRET = 'mgr05-synthetic-test-only-signing';
    process.env.COOKIE_ENCRYPTION_KEY = 'mgr05-synthetic-test-only-cookie';
    db = new PrismaService({ datasourceUrl: url });
    const controllerDependencies: any[] = Reflect.getMetadata(
      'design:paramtypes',
      MobileController,
    );
    const unused = controllerDependencies
      .filter((type) => type !== VenueEntitlementsService)
      .map((type) => ({
        provide: type,
        useValue:
          type === MobileOrdersService
            ? new MobileOrdersService(db, {} as any, {} as any, {} as any)
            : {},
      }));
    const connection = {
      restore: async () => {},
      register: async () => {},
      hasCallbackUrl: () => true,
    };
    const staffSync: any = { withDatabase: () => staffSync };
    const broadcasts: any = {
      relayPosHints: async () => ({
        hadOrderLineTouch: false,
        hadTableTouch: false,
      }),
      announceSnapshotApplied: () => {},
      announceDayClosed: () => {},
    };
    const ingest = new IngestPosSnapshotService(
      { kickPending: async () => {} } as any,
      connection as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      staffSync,
      {} as any,
      broadcasts,
    );
    app = await onboardingApp(db, undefined, {
      controllers: [MobileController, EdgeTransportController, SyncController],
      providers: [
        ...unused,
        JwtStrategy,
        ManagerTenantService,
        { provide: IngestPosSnapshotService, useValue: ingest },
        { provide: IngestAuditReportsService, useValue: {} },
        { provide: PosConnectionRegistry, useValue: connection },
        {
          provide: LegacyPosTenantService,
          useValue: { resolveContext: async () => null },
        },
        { provide: InventoryService, useValue: {} },
        { provide: SaleConsumptionService, useValue: {} },
      ],
    });
    await app.listen(0, '127.0.0.1');
    base = await app.getUrl();
    seeded = await seedMenu03(db, app);
    const feature = await db.feature.upsert({
      where: { key: 'MANAGER_APP' },
      update: {},
      create: { key: 'MANAGER_APP', name: 'Synthetic Manager' },
    });
    for (const v of seeded.venues) {
      const assignment = await db.venuePlanAssignment.findUniqueOrThrow({
        where: { venueId: v.venueId },
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
      const staff = await db.staff.create({
        data: {
          venueId: v.venueId,
          username: `manager-${randomUUID()}`,
          role: 'MANAGER',
          pinHash: 'unused-synthetic-only',
        },
      });
      if (v === seeded.venues[0]) {
        const venue = await db.venue.findUniqueOrThrow({
          where: { id: v.venueId },
        });
        actor = {
          venueId: v.venueId,
          organizationId: venue.organizationId,
          staffId: staff.id,
          username: staff.username,
          role: 'MANAGER',
        };
        token = new JwtService().sign(
          {
            sub: staff.id,
            username: 'ignored',
            role: 'WAITER',
            venueId: seeded.venues[1].venueId,
          },
          { secret: process.env.JWT_SECRET },
        );
      }
    }
    deviceId = seeded.venues[0].credential.split('.')[1];
    await db.venue.update({
      where: { id: actor.venueId },
      data: { activeOperationalDeviceId: deviceId },
    });
    tableId = randomUUID();
    const path = process.env.MGR05_NATIVE_FIXTURE;
    if (!path || !/^\/(?:private\/)?tmp\/vynic-mgr05-/.test(path))
      throw Error('Owned native fixture required');
    fixture = JSON.parse(readFileSync(path, 'utf8'));
    baseline = JSON.parse(fixture.payload.baseline.image);
    await db.table.create({
      data: {
        id: tableId,
        venueId: actor.venueId,
        tableNumber: '7',
        floor: 'first',
        isReserved: true,
        activeOrderId: 1,
        currentBill: baseline.totalAmount,
      },
    });
  }, 60000);

  beforeEach(async () => {
    requestId = randomUUID();
    await db.edgeCommand.deleteMany({ where: { venueId: actor.venueId } });
    await db.order.deleteMany({
      where: { venueId: actor.venueId, posOrderId: 1 },
    });
    await db.order.create({
      data: {
        venueId: actor.venueId,
        posOrderId: 1,
        status: baseline.status,
        totalAmount: baseline.totalAmount,
        waiterName: baseline.createdBy,
        floor: baseline.floor,
        businessDate: '2026-10-01',
        includeServiceFee: baseline.includeServiceFee,
        serviceFeePercent: 3,
        discountAmount: baseline.discountAmount,
        manualAdjustmentAmount: baseline.manualAdjustmentAmount,
        managerEditProjection: {
          ...fixture.payload.baseline,
          sourceDeviceId: deviceId,
        },
        items: {
          create: baseline.items.map((i: any) => ({
            name: i.itemName,
            quantity: i.quantity,
            price: i.unitPrice,
            menuItemId: i.menuItemId,
            variantId: i.variantId,
          })),
        },
      },
    });
    await db.venue.update({
      where: { id: actor.venueId },
      data: { activeOperationalDeviceId: deviceId },
    });
    await db.table.update({
      where: { id: tableId },
      data: {
        activeOrderId: 1,
        isReserved: true,
        currentBill: baseline.totalAmount,
      },
    });
  });
  afterAll(async () => {
    if (db && actor)
      await db.edgeCommand.deleteMany({ where: { venueId: actor.venueId } });
    await app?.close();
    await db?.$disconnect();
  });
  test('queue acceptance leaves order/lines/table/audit unchanged', async () => {
    const before = await row(),
      table = await db.table.findUniqueOrThrow({ where: { id: tableId } });
    const r = await edit();
    expect(r.status).toBe(202);
    expect(r.body.success).toBe(false);
    expect(r.body.posDelivery.status).toBe('QUEUED');
    expect(await row()).toEqual(before);
    expect(
      await db.table.findUniqueOrThrow({ where: { id: tableId } }),
    ).toEqual(table);
    const command = await db.edgeCommand.findUniqueOrThrow({
      where: { id: r.body.posDelivery.commandId },
    });
    expect(command.deviceId).toBe(deviceId);
    expect((command.payload as any).actorStaffId).toBe(actor.staffId);
  });
  test('strict DTO rejects malformed/missing items and line-total injection before queue', async () => {
    const malformed = [
      { items: undefined },
      { items: null },
      { items: [{ ...body().items[0], quantity: 1.5 }] },
      { items: [{ ...body().items[0], unitPrice: -1 }] },
      { items: [{ ...body().items[0], total: 1 }] },
      { items: [body().items[0], body().items[0]] },
      { customServiceFeePercentage: 101 },
      { requestId: 'bad' },
      { expectedFingerprint: 'bad' },
    ];
    const before = await row();
    for (const change of malformed)
      expect((await edit({ ...body(), ...change })).status).toBe(400);
    expect(await row()).toEqual(before);
    expect(
      await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
    ).toBe(0);
  });
  test('missing/closed/stale states reject explicitly without mutating existing order', async () => {
    expect((await edit(body(), token, '999')).status).toBe(404);
    expect(
      (await edit({ ...body(), expectedFingerprint: '0'.repeat(64) })).status,
    ).toBe(409);
    await db.order.update({
      where: { id: (await row()).id },
      data: { status: 'paid' },
    });
    expect((await edit()).status).toBe(409);
    expect(
      await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
    ).toBe(0);
  });
  test('client tenant/actor fields cannot widen current Staff authority', async () => {
    expect((await edit(body(), '')).status).toBe(401);
    const r = await edit({
      ...body(),
      venueId: seeded.venues[1].venueId,
      actorStaffId: randomUUID(),
      updatedBy: 'spoof',
    });
    expect(r.status).toBe(202);
    const command = await db.edgeCommand.findUniqueOrThrow({
      where: { id: r.body.posDelivery.commandId },
    });
    expect(command.venueId).toBe(actor.venueId);
    expect((command.payload as any).actorUsername).toBe(actor.username);
  });
  test('deactivated principal is rejected from current Staff row', async () => {
    await db.staff.update({
      where: { id: actor.staffId },
      data: { isActive: false },
    });
    try {
      expect((await edit()).status).toBe(401);
    } finally {
      await db.staff.update({
        where: { id: actor.staffId },
        data: { isActive: true },
      });
    }
  });
  test('concurrent lost-response retries retain one immutable command and conflicting body is409', async () => {
    const outcomes = await Promise.all(
      Array.from({ length: 12 }, () => edit()),
    );
    expect(
      new Set(outcomes.map((r) => r.body.posDelivery.commandId)).size,
    ).toBe(1);
    expect(
      await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
    ).toBe(1);
    expect((await edit({ ...body(), includeServiceFee: true })).status).toBe(
      409,
    );
  });
  test('missing primary and missing/wrong primary baseline are unavailable without queue', async () => {
    await db.venue.update({
      where: { id: actor.venueId },
      data: { activeOperationalDeviceId: null },
    });
    expect((await edit()).body.posDelivery.status).toBe('UNAVAILABLE');
    await db.venue.update({
      where: { id: actor.venueId },
      data: { activeOperationalDeviceId: deviceId },
    });
    await db.order.update({
      where: { id: (await row()).id },
      data: {
        managerEditProjection: {
          ...fixture.payload.baseline,
          sourceDeviceId: randomUUID(),
        },
      },
    });
    expect((await edit()).body.posDelivery.status).toBe('UNAVAILABLE');
    await db.order.update({
      where: { id: (await row()).id },
      data: { managerEditProjection: require('@prisma/client').Prisma.DbNull },
    });
    expect((await edit()).body.posDelivery.status).toBe('UNAVAILABLE');
    expect(
      await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
    ).toBe(0);
  });
  test('version1 client cannot claim this additive command; source rejection stays terminal', async () => {
    const r = await edit();
    expect(await claim([1])).toEqual([]);
    const [command] = await claim();
    expect(
      (await ack(command.commandId, { status: 'FAILED', code: 'stale_order' }))
        .status,
    ).toBe(201);
    const retried = await edit();
    expect(retried.body.posDelivery.status).toBe('FAILED');
    expect(retried.body.posDelivery.code).toBe('stale_order');
    expect((await row()).items[0].quantity).toBe(4);
    expect(r.body.posDelivery.commandId).toBe(command.commandId);
  });
  test('native POS result atomically replaces mirror/lines/bills and retains exact terminal result', async () => {
    await edit();
    const [command] = await claim();
    const r = await ack(command.commandId);
    expect(r.status).toBe(201);
    const after = await row();
    expect(after.totalAmount).toBe(18.34);
    expect(after.items).toHaveLength(1);
    expect(after.items[0].quantity).toBe(5);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: tableId } }))
        .currentBill,
    ).toBe(18.34);
    const retry = await edit();
    expect(retry.body.success).toBe(true);
    expect(retry.body.editProjection).toEqual(fixture.result);
    expect((await ack(command.commandId)).body.alreadyAcknowledged).toBe(true);
    const detail = await fetch(base + '/mobile/order/1', {
      headers: { Authorization: `Bearer ${token}` },
    });
    const exact = (await detail.json()) as any;
    expect(exact.advanceAmount).toBe(1.17);
    expect(exact.packageItems).toHaveLength(1);
    expect(exact.items[0].comment).toBe(' keep ');
  });
  test('invalid or foreign result cannot complete command or project another Venue', async () => {
    await edit();
    const [command] = await claim();
    expect(
      (
        await ack(command.commandId, {
          status: 'SUCCEEDED',
          code: 'order_edited',
        })
      ).status,
    ).toBe(400);
    expect(
      (await ack(command.commandId, undefined, seeded.venues[1].credential))
        .status,
    ).toBe(404);
    expect(
      (
        await db.edgeCommand.findUniqueOrThrow({
          where: { id: command.commandId },
        })
      ).status,
    ).toBe('CLAIMED');
    expect((await row()).items[0].quantity).toBe(4);
  });
  test('delayed ACK does not overwrite a later edit/close or newer table-only snapshot', async () => {
    await edit();
    const [command] = await claim();
    await db.table.update({
      where: { id: tableId },
      data: { currentBill: 99 },
    });
    await ack(command.commandId);
    expect(
      (await db.table.findUniqueOrThrow({ where: { id: tableId } }))
        .currentBill,
    ).toBe(99);
    requestId = randomUUID();
    await db.order.update({
      where: { id: (await row()).id },
      data: {
        managerEditProjection: {
          ...fixture.payload.baseline,
          sourceDeviceId: deviceId,
        },
        totalAmount: baseline.totalAmount,
      },
    });
    await edit();
    const [later] = await claim();
    await db.order.update({
      where: { id: (await row()).id },
      data: { status: 'paid', totalAmount: 77 },
    });
    await ack(later.commandId);
    expect((await row()).totalAmount).toBe(77);
  });
  test('legacy snapshot invalidates stale edit authority; inconsistent modern projection rejects before writes', async () => {
    const sync = new OrderSyncService(db);
    const incoming: any = {
      posOrderId: 1,
      status: 'confirmed',
      totalAmount: 55,
      floor: 'first',
      tableNumbers: ['7'],
      items: [{ name: 'Later POS', quantity: 1, price: 55 }],
    };
    await edit();
    const [command] = await claim();
    await sync.sync(
      { ...actor, deviceId, authenticationMode: 'device' } as any,
      [incoming],
      '2026-10-01',
    );
    expect((await row()).managerEditProjection).toBeNull();
    await ack(command.commandId);
    expect((await row()).totalAmount).toBe(55);
    await expect(
      sync.sync(
        actor,
        [{ ...incoming, managerEditProjection: fixture.payload.baseline }],
        '2026-10-01',
      ),
    ).rejects.toThrow('inconsistent_order_edit_projection');
    expect((await row()).totalAmount).toBe(55);
  });
  test('actual Device-authenticated HTTP snapshot retains edit authority across ingestion and rejects incoherent lines', async () => {
    const incoming: any = {
      ...baseline,
      posOrderId: 1,
      managerEditProjection: {
        ...fixture.payload.baseline,
        sourceDeviceId: seeded.venues[1].venueId,
      },
    };
    const value = {
      realtimeOnly: true,
      businessDate: '2026-10-01',
      orders: [incoming],
    };
    expect(
      (
        await post(
          '/sync/manager-data',
          value,
          seeded.venues[0].credential,
          true,
        )
      ).status,
    ).toBe(201);
    expect((await row()).managerEditProjection).toEqual({
      ...fixture.payload.baseline,
      sourceDeviceId: deviceId,
    });
    expect((await edit()).body.posDelivery.status).toBe('QUEUED');
    const before = await row();
    expect(
      (
        await post(
          '/sync/manager-data',
          {
            ...value,
            orders: [
              { ...incoming, items: [{ ...incoming.items[0], quantity: 99 }] },
            ],
          },
          seeded.venues[0].credential,
          true,
        )
      ).status,
    ).toBe(400);
    expect(await row()).toEqual(before);
    expect(
      (
        await post(
          '/sync/manager-data',
          { ...value, venueId: actor.venueId },
          seeded.venues[1].credential,
          true,
        )
      ).status,
    ).toBe(201);
    const foreign = await db.order.findUniqueOrThrow({
      where: {
        venueId_posOrderId: {
          venueId: seeded.venues[1].venueId,
          posOrderId: 1,
        },
      },
    });
    expect((foreign.managerEditProjection as any).sourceDeviceId).toBe(
      seeded.venues[1].credential.split('.')[1],
    );
    expect(await row()).toEqual(before);
  });
  async function installNativeVariant(suffix: string) {
    fixture = JSON.parse(
      readFileSync(
        process.env.MGR05_NATIVE_FIXTURE! + suffix + '.json',
        'utf8',
      ),
    );
    baseline = JSON.parse(fixture.payload.baseline.image);
    await db.order.update({
      where: { id: (await row()).id },
      data: {
        totalAmount: baseline.totalAmount,
        includeServiceFee: baseline.includeServiceFee,
        managerEditProjection: {
          ...fixture.payload.baseline,
          sourceDeviceId: deviceId,
        },
        items: {
          deleteMany: {},
          create: baseline.items.map((i: any) => ({
            name: i.itemName,
            quantity: i.quantity,
            price: i.unitPrice,
            menuItemId: i.menuItemId,
            variantId: i.variantId,
          })),
        },
      },
    });
    await db.table.update({
      where: { id: tableId },
      data: { currentBill: baseline.totalAmount },
    });
  }
  test('native distinct comments on the same menu key survive actual snapshot, command and ACK', async () => {
    const original = { fixture, baseline };
    try {
      await installNativeVariant('.two-line');
      expect(
        (
          await post(
            '/sync/manager-data',
            {
              realtimeOnly: true,
              businessDate: '2026-10-01',
              orders: [
                {
                  ...baseline,
                  posOrderId: 1,
                  managerEditProjection: fixture.payload.baseline,
                },
              ],
            },
            seeded.venues[0].credential,
            true,
          )
        ).status,
      ).toBe(201);
      expect((await edit()).status).toBe(202);
      const [command] = await claim();
      expect((await ack(command.commandId)).status).toBe(201);
      expect((await row()).items).toHaveLength(2);
      const exact = JSON.parse(
        ((await row()).managerEditProjection as any).image,
      );
      expect(exact.items.map((i: any) => i.comment)).toEqual([
        ' keep ',
        'second note',
      ]);
      expect(new Set(exact.items.map((i: any) => i.lineUuid)).size).toBe(2);
    } finally {
      fixture = original.fixture;
      baseline = original.baseline;
    }
  });
  test('actual native default fee result projects 12 percent without hardcoded10', async () => {
    const original = { fixture, baseline };
    try {
      await installNativeVariant('.default-fee');
      await edit();
      const [command] = await claim();
      expect((await ack(command.commandId)).status).toBe(201);
      const after = await row();
      expect(after.serviceFeePercent).toBe(12);
      expect(after.totalAmount).toBe(19.84);
    } finally {
      fixture = original.fixture;
      baseline = original.baseline;
    }
  });
  for (const inserted of [0, 1])
    test(`real nested insert failure after delete and ${inserted} inserted lines rolls back every mirror effect`, async () => {
      const original = { fixture, baseline };
      try {
        await installNativeVariant('.two-line');
        const before = await row(),
          table = await db.table.findUniqueOrThrow({ where: { id: tableId } });
        await edit();
        const [command] = await claim();
        if (!/^[a-f0-9-]{36}$/.test(before.id))
          throw Error('Owned UUID required');
        await db.$executeRawUnsafe(
          `CREATE FUNCTION pos.mgr05_line_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW."orderId" = '${before.id}' AND (SELECT count(*) FROM pos."OrderItem" WHERE "orderId" = NEW."orderId") = ${inserted} THEN RAISE EXCEPTION 'Owned MGR05 nested insert failure'; END IF; RETURN NEW; END $$`,
        );
        await db.$executeRawUnsafe(
          'CREATE TRIGGER mgr05_line_fault BEFORE INSERT ON pos."OrderItem" FOR EACH ROW EXECUTE FUNCTION pos.mgr05_line_fault()',
        );
        expect((await ack(command.commandId)).status).toBe(500);
        expect(await row()).toEqual(before);
        expect(
          await db.table.findUniqueOrThrow({ where: { id: tableId } }),
        ).toEqual(table);
        expect(
          (
            await db.edgeCommand.findUniqueOrThrow({
              where: { id: command.commandId },
            })
          ).status,
        ).toBe('CLAIMED');
      } finally {
        await db.$executeRawUnsafe(
          'DROP TRIGGER IF EXISTS mgr05_line_fault ON pos."OrderItem"',
        );
        await db.$executeRawUnsafe(
          'DROP FUNCTION IF EXISTS pos.mgr05_line_fault()',
        );
        fixture = original.fixture;
        baseline = original.baseline;
      }
    });
  for (const point of [
    'enqueue',
    'order_after',
    'table_after',
    'completion_before',
  ])
    test(`transaction fault ${point} preserves original complete mirror/command`, async () => {
      const wrap = (target: any) =>
        new Proxy(target, {
          get(t, k) {
            const value = Reflect.get(t, k);
            if (k === 'edgeCommand' || k === 'order' || k === 'table')
              return new Proxy(value, {
                get(model, operation) {
                  const method = Reflect.get(model, operation);
                  if (
                    (point === 'enqueue' &&
                      k === 'edgeCommand' &&
                      operation === 'create') ||
                    (point === 'completion_before' &&
                      k === 'edgeCommand' &&
                      operation === 'update')
                  )
                    return () => {
                      throw Error('Synthetic DB fault');
                    };
                  if (
                    (point === 'order_after' &&
                      k === 'order' &&
                      operation === 'update') ||
                    (point === 'table_after' &&
                      k === 'table' &&
                      operation === 'updateMany')
                  )
                    return async (args: any) => {
                      await method.call(model, args);
                      throw Error('Synthetic DB fault');
                    };
                  return typeof method === 'function'
                    ? method.bind(model)
                    : method;
                },
              });
            return typeof value === 'function' ? value.bind(t) : value;
          },
        });
      const proxy = new Proxy(db, {
        get(t, k) {
          if (k === '$transaction')
            return (work: any) => t.$transaction((tx) => work(wrap(tx)));
          const value = Reflect.get(t, k);
          return typeof value === 'function' ? value.bind(t) : value;
        },
      });
      const before = await row(),
        table = await db.table.findUniqueOrThrow({ where: { id: tableId } });
      if (point === 'enqueue') {
        await expect(
          requestOrderEdit(proxy, actor, '1', body()),
        ).rejects.toThrow('Synthetic DB fault');
        expect(
          await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
        ).toBe(0);
      } else {
        await edit();
        const [command] = await claim();
        await expect(
          new EdgeCommandService(proxy).acknowledge(
            {
              venueId: actor.venueId,
              organizationId: actor.organizationId,
              deviceId,
            },
            {
              commandId: command.commandId,
              status: 'SUCCEEDED',
              code: 'order_edited',
              resultProjection: fixture.result,
            },
          ),
        ).rejects.toThrow('Synthetic DB fault');
        expect(
          (
            await db.edgeCommand.findUniqueOrThrow({
              where: { id: command.commandId },
            })
          ).status,
        ).toBe('CLAIMED');
      }
      expect(await row()).toEqual(before);
      expect(
        await db.table.findUniqueOrThrow({ where: { id: tableId } }),
      ).toEqual(table);
    });
});
