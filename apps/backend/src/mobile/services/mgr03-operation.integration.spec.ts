import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma.service';
import { MobileController } from '../mobile.controller';
import { MobileOrdersService } from './mobile-orders.service';
import { MobileReservationsService } from './mobile-reservations.service';
import { JwtStrategy } from '../../auth/jwt.strategy';
import { ManagerTenantService } from '../../auth/manager-tenant.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { InventoryService } from '../../inventory/inventory.service';
import { SaleConsumptionService } from '../../inventory/sale-consumption.service';
import { EdgeTransportController } from '../../edge/edge-transport.controller';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { seedMenu03 } from '../../../test/menu03.fixture';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import type { Type } from '@nestjs/common';
import type { Prisma, Staff } from '@prisma/client';
type Projection = Prisma.InputJsonObject & { image: string };
type HttpBody = {
  success: boolean;
  accepted: boolean;
  message: string;
  posOrderId: number;
  posDelivery: { status: string; commandId: string; code: string };
  commands: {
    commandId: string;
    type: string;
    payload: { actorStaffId: string };
  }[];
};
// These unused collaborators deliberately fail if future tests execute them.
function stub<T>(): T {
  return {} as T;
}
const url = process.env.MGR03_TEST_DATABASE_URL;
const integration = url ? describe : describe.skip;
const kinds = [
  'order_cancel',
  'takeaway_cancel',
  'takeaway_create',
  'dine_in_create',
  'reservation_create',
  'reservation_status',
  'reservation_delete',
];
integration(
  'MGR03 real guarded HTTP/PostgreSQL/native Edge operation delivery',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      base: string,
      seeded: Awaited<ReturnType<typeof seedMenu03>>;
    let staff: Staff,
      actorToken: string,
      otherToken: string,
      foreignToken: string,
      deviceId: string,
      projection: Projection,
      planId: string,
      resFeatureId: string;
    let requestId: string;
    const send = async (
      path: string,
      body: unknown,
      auth = actorToken,
      method = 'POST',
      edge = false,
    ) => {
      const response = await fetch(base + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(auth
            ? edge
              ? { 'X-POS-Sync-Key': auth }
              : { Authorization: `Bearer ${auth}` }
            : {}),
        },
        ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
      });
      return {
        status: response.status,
        body: (await response.json()) as HttpBody,
      };
    };
    const body = (kind: string): Record<string, unknown> =>
      kind.endsWith('_cancel')
        ? { posOrderId: 1 }
        : kind === 'reservation_status'
          ? { reservationId: 'booking', status: 'confirmed' }
          : kind === 'reservation_delete'
            ? { reservationId: 'booking' }
            : kind === 'reservation_create'
              ? {
                  customerName: 'Synthetic guest',
                  customerPhone: 'synthetic',
                  tableNumbers: [19],
                  reservationDate: '2026-10-02',
                  reservationTime: '18:00',
                  numberOfGuests: 2,
                  preOrderItems: [],
                }
              : kind === 'takeaway_create'
                ? {
                    customerName: 'Synthetic guest',
                    pickupTime: '18:00',
                    items: [
                      {
                        itemName: 'Synthetic dish',
                        unitPrice: 10,
                        quantity: 2,
                      },
                    ],
                  }
                : {
                    floor: 'first',
                    tableNumbers: ['19'],
                    guestCount: 2,
                    items: [
                      {
                        itemName: 'Synthetic dish',
                        unitPrice: 10,
                        quantity: 2,
                      },
                    ],
                  };
    const submit = (
      kind = 'takeaway_create',
      b = body(kind),
      id = requestId,
      auth = actorToken,
    ) =>
      send(
        `/mobile/operation-requests/${kind}`,
        { requestId: id, body: b },
        auth,
      );
    const status = (id = requestId, auth = actorToken) =>
      send(`/mobile/operation-requests/${id}`, undefined, auth, 'GET');
    const claim = (
      credential = seeded.venues[0].credential,
      versions = [2, 1],
    ) =>
      send(
        '/edge/commands/claim',
        { acceptedContractVersions: versions },
        credential,
        'POST',
        true,
      );
    const ack = (
      id: string,
      result: Record<string, unknown> = {
        status: 'SUCCEEDED',
        code: 'native_complete',
      },
      credential = seeded.venues[0].credential,
    ) =>
      send(
        '/edge/commands/ack',
        { ...result, commandId: id },
        credential,
        'POST',
        true,
      );
    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url))
        throw Error('Owned fresh disposable MGR03 DB required');
      process.env.JWT_SECRET = 'mgr03-synthetic-test-only';
      process.env.COOKIE_ENCRYPTION_KEY = 'mgr03-synthetic-cookie-only';
      db = new PrismaService({ datasourceUrl: url });
      const dependencies = Reflect.getMetadata(
        'design:paramtypes',
        MobileController,
      ) as Type<unknown>[];
      app = await onboardingApp(db, undefined, {
        controllers: [MobileController, EdgeTransportController],
        providers: [
          ...dependencies
            .filter((t) => t !== VenueEntitlementsService)
            .map((t) => ({
              provide: t,
              useValue:
                t === MobileOrdersService
                  ? new MobileOrdersService(db, stub(), stub(), stub())
                  : t === MobileReservationsService
                    ? new MobileReservationsService(
                        stub(),
                        stub(),
                        stub(),
                        stub(),
                        db,
                      )
                    : {},
            })),
          JwtStrategy,
          ManagerTenantService,
          { provide: InventoryService, useValue: {} },
          { provide: SaleConsumptionService, useValue: {} },
        ],
      });
      await app.listen(0, '127.0.0.1');
      base = await app.getUrl();
      seeded = await seedMenu03(db, app);
      planId = (
        await db.venuePlanAssignment.findUniqueOrThrow({
          where: { venueId: seeded.venues[0].venueId },
        })
      ).planId;
      for (const key of ['MANAGER_APP', 'MANAGER_RESERVATIONS']) {
        const feature = await db.feature.upsert({
          where: { key },
          create: { key, name: `Synthetic ${key}` },
          update: {},
        });
        await db.planFeature.create({
          data: { planId, featureId: feature.id },
        });
        if (key === 'MANAGER_RESERVATIONS') resFeatureId = feature.id;
      }
      const createStaff = async (venueId: string) =>
        db.staff.create({
          data: {
            venueId,
            username: `mgr03-${randomUUID()}`,
            role: 'MANAGER',
            pinHash: 'unused-synthetic-only',
          },
        });
      const token = (s: Staff) =>
        new JwtService().sign(
          {
            sub: s.id,
            username: 'client cannot supply actor',
            role: 'WAITER',
            venueId: seeded.venues[1].venueId,
          },
          { secret: process.env.JWT_SECRET },
        );
      staff = await createStaff(seeded.venues[0].venueId);
      actorToken = token(staff);
      otherToken = token(await createStaff(staff.venueId));
      foreignToken = token(await createStaff(seeded.venues[1].venueId));
      deviceId = seeded.venues[0].credential.split('.')[1];
      const file = process.env.MGR03_NATIVE_FIXTURE;
      if (!file || !/^\/(?:private\/)?tmp\/vynic-mgr03-[^/]+\//.test(file))
        throw Error('Owned native fixture required');
      projection = (
        JSON.parse(readFileSync(file, 'utf8')) as { projection: Projection }
      ).projection;
      await db.table.create({
        data: {
          venueId: staff.venueId,
          tableNumber: '19',
          floor: 'first',
          isReserved: false,
        },
      });
    }, 60000);
    beforeEach(async () => {
      requestId = randomUUID();
      await db.edgeCommand.deleteMany({ where: { venueId: staff.venueId } });
      await db.order.deleteMany({ where: { venueId: staff.venueId } });
      await db.posReservation.deleteMany({ where: { venueId: staff.venueId } });
      await db.venue.update({
        where: { id: staff.venueId },
        data: { activeOperationalDeviceId: deviceId },
      });
      const order = JSON.parse(projection.image) as {
        items: { itemName: string; quantity: number; unitPrice: number }[];
      };
      await db.order.create({
        data: {
          venueId: staff.venueId,
          posOrderId: 1,
          status: 'confirmed',
          totalAmount: 10.01,
          waiterName: staff.username,
          floor: 'first',
          businessDate: '2026-10-01',
          managerEditProjection: { ...projection, sourceDeviceId: deviceId },
          items: {
            create: order.items.map((i) => ({
              name: i.itemName,
              quantity: i.quantity,
              price: i.unitPrice,
            })),
          },
        },
      });
      await db.posReservation.create({
        data: {
          venueId: staff.venueId,
          posReservationId: 'booking',
          customerName: 'Synthetic booking',
          tableNumbers: [7],
          tableRefs: ['first/7'],
          reservationDate: new Date('2026-10-01'),
          reservationTime: '18:00',
          status: 'pending',
        },
      });
      await db.setting.upsert({
        where: {
          venueId_key: { venueId: staff.venueId, key: 'currentBusinessDate' },
        },
        create: {
          venueId: staff.venueId,
          key: 'currentBusinessDate',
          value: '2026-10-01',
        },
        update: { value: '2026-10-01' },
      });
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });
    for (const kind of kinds) {
      it(`${kind}: QUEUED is only acceptance; real native execution/lost ACK/reopen supplies completion`, async () => {
        const beforeOrders = await db.order.findMany({
            where: { venueId: staff.venueId },
            include: { items: true },
          }),
          beforeReservations = await db.posReservation.findMany({
            where: { venueId: staff.venueId },
          });
        const pending = await submit(kind);
        expect(pending.status).toBe(202);
        expect(pending.body.success).toBe(false);
        expect(pending.body.posDelivery.status).toBe('QUEUED');
        expect(
          await db.order.findMany({
            where: { venueId: staff.venueId },
            include: { items: true },
          }),
        ).toEqual(beforeOrders);
        expect(
          await db.posReservation.findMany({
            where: { venueId: staff.venueId },
          }),
        ).toEqual(beforeReservations);
        const offered = await claim();
        expect(offered.status).toBe(201);
        expect(offered.body.commands).toHaveLength(1);
        const command = offered.body.commands[0];
        expect(command.type).toBe('MANAGER_OPERATION');
        expect(command.payload.actorStaffId).toBe(staff.id);
        expect((await status()).body.posDelivery.status).toBe('CLAIMED');
        const root = process.env.MGR03_NATIVE_RECEIPTS!,
          flutter = process.env.MGR03_FLUTTER!;
        if (
          !root ||
          !/^\/(?:private\/)?tmp\/vynic-mgr03-[^/]+\//.test(root) ||
          !flutter
        )
          throw Error('Owned native worker inputs required');
        const run = mkdtempSync(join(root, `native-http-${kind}-`));
        writeFileSync(join(run, 'claim.json'), JSON.stringify(command));
        const worker = spawnSync(
          flutter,
          [
            'test',
            '--no-pub',
            '--reporter',
            'expanded',
            'test/live/mgr03_http_edge_worker_test.dart',
          ],
          {
            cwd: resolve(__dirname, '../../../../operations'),
            env: {
              ...process.env,
              MGR03_NATIVE_RUN: run,
              MGR03_NATIVE_STAGE: 'execute',
            },
            encoding: 'utf8',
            timeout: 60000,
          },
        );
        writeFileSync(join(run, 'worker.log'), worker.stdout + worker.stderr);
        expect(worker.status).toBe(0);
        const native = JSON.parse(
          readFileSync(join(run, 'native-result.json'), 'utf8'),
        ) as {
          status: string;
          lostAckPreservedLaterWork: boolean;
          acks: Record<string, unknown>[];
        };
        expect(native.status).toBe('PASS');
        expect(native.lostAckPreservedLaterWork).toBe(true);
        expect((await status()).body.success).toBe(false);
        expect((await ack(command.commandId, native.acks[1])).status).toBe(201);
        const completed = await submit(kind);
        expect(completed.body.success).toBe(true);
        expect(completed.body.posDelivery.status).toBe('SUCCEEDED');
        expect(completed.body.posDelivery.commandId).toBe(command.commandId);
        expect(
          await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
        ).toBe(1);
        // Execution acknowledgment never invents an operational mirror update.
        expect(
          await db.order.findMany({
            where: { venueId: staff.venueId },
            include: { items: true },
          }),
        ).toEqual(beforeOrders);
        expect(
          await db.posReservation.findMany({
            where: { venueId: staff.venueId },
          }),
        ).toEqual(beforeReservations);
      }, 90000);
    }
    it('12 concurrent duplicate POSTs retain one command, one allocated reference and original normalized request', async () => {
      const results = await Promise.all(
        Array.from({ length: 12 }, () => submit()),
      );
      expect(results.every((r) => r.status === 202)).toBe(true);
      expect(
        new Set(results.map((r) => r.body.posDelivery.commandId)).size,
      ).toBe(1);
      expect(new Set(results.map((r) => r.body.posOrderId)).size).toBe(1);
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(1);
      const conflict = await submit('takeaway_create', {
        ...body('takeaway_create'),
        customerName: 'Different guest',
      });
      expect(conflict.status).toBe(409);
      expect(conflict.body.message).toBe('request_conflict');
    });
    it('changed operation kind cannot reuse a retained UUID', async () => {
      await submit();
      const r = await submit('reservation_create');
      expect(r.status).toBe(409);
    });
    it('missing selected primary is visible unavailable with no command or allocation', async () => {
      await db.venue.update({
        where: { id: staff.venueId },
        data: { activeOperationalDeviceId: null },
      });
      const before = await db.setting.findMany({
        where: { venueId: staff.venueId },
      });
      const r = await submit();
      expect(r.status).toBe(202);
      expect(r.body.accepted).toBe(false);
      expect(r.body.posDelivery.status).toBe('UNAVAILABLE');
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(0);
      expect(
        await db.setting.findMany({ where: { venueId: staff.venueId } }),
      ).toEqual(before);
    });
    for (const baseline of ['missing', 'different-primary'])
      it(`cancellation ${baseline} baseline is no-effect unavailable`, async () => {
        await db.order.updateMany({
          where: { venueId: staff.venueId },
          data: {
            managerEditProjection:
              baseline === 'missing'
                ? undefined
                : { ...projection, sourceDeviceId: randomUUID() },
          },
        });
        if (baseline === 'missing')
          await db.$executeRawUnsafe(
            'UPDATE pos."Order" SET "managerEditProjection"=NULL WHERE "venueId"=$1',
            staff.venueId,
          );
        const r = await submit('order_cancel');
        expect(r.body.posDelivery.status).toBe('UNAVAILABLE');
        expect(
          await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
        ).toBe(0);
      });
    it('actor, Venue and selected Device derive from authenticated current Staff, not body or JWT claims', async () => {
      const r = await submit('takeaway_create', {
        ...body('takeaway_create'),
        venueId: seeded.venues[1].venueId,
        staffId: randomUUID(),
        waiterName: 'forged',
        createdBy: 'forged',
      });
      expect(r.status).toBe(202);
      const row = await db.edgeCommand.findUniqueOrThrow({
        where: { id: r.body.posDelivery.commandId },
      });
      expect(row.venueId).toBe(staff.venueId);
      expect(row.deviceId).toBe(deviceId);
      expect((row.payload as Prisma.JsonObject).waiterName).toBe(
        staff.username,
      );
      expect((row.payload as Prisma.JsonObject).createdBy).toBe(staff.username);
    });
    it('another Staff or Venue cannot read retained request status', async () => {
      await submit();
      expect((await status(requestId, otherToken)).status).toBe(404);
      expect((await status(requestId, foreignToken)).status).toBe(404);
    });
    it('foreign reservation/order identities fail before creating any command', async () => {
      expect(
        (
          await submit('reservation_delete', {
            reservationId: 'foreign-booking',
          })
        ).status,
      ).toBe(404);
      expect((await submit('order_cancel', { posOrderId: 777 })).status).toBe(
        404,
      );
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(0);
    });
    it('reservation feature denial is explicit and creates no command', async () => {
      await db.planFeature.delete({
        where: { planId_featureId: { planId, featureId: resFeatureId } },
      });
      try {
        expect((await submit('reservation_create')).status).toBe(403);
        expect(
          await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
        ).toBe(0);
      } finally {
        await db.planFeature.create({
          data: { planId, featureId: resFeatureId },
        });
      }
    });
    it('expired claim with exhausted attempts is retained uncertainty, never success or new identity', async () => {
      const r = await submit();
      await claim();
      await db.edgeCommand.update({
        where: { id: r.body.posDelivery.commandId },
        data: { claimExpiresAt: new Date(0), attemptCount: 5, maxAttempts: 5 },
      });
      expect((await claim()).body.commands).toHaveLength(0);
      const failed = await submit();
      expect(failed.body.success).toBe(false);
      expect(failed.body.posDelivery.code).toBe(
        'lease_expired_attempts_exhausted',
      );
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(1);
    });
    for (const code of [
      'order_id_conflict',
      'manager_operation_outcome_unknown',
    ])
      it(`POS ${code} is retained and cannot revive`, async () => {
        const r = await submit();
        await claim();
        await ack(r.body.posDelivery.commandId, { status: 'FAILED', code });
        const retained = await submit();
        expect(retained.body.success).toBe(false);
        expect(retained.body.posDelivery.status).toBe('FAILED');
        expect(retained.body.posDelivery.code).toBe(code);
        expect((await claim()).body.commands).toHaveLength(0);
      });
    it('old contract-only POS cannot claim the new guarded type', async () => {
      await submit();
      expect(
        (await claim(seeded.venues[0].credential, [1])).body.commands,
      ).toHaveLength(0);
      expect((await status()).body.posDelivery.status).toBe('QUEUED');
    });
    it('foreign Device cannot ACK current Venue command', async () => {
      const r = await submit();
      await claim();
      expect(
        (
          await ack(
            r.body.posDelivery.commandId,
            undefined,
            seeded.venues[1].credential,
          )
        ).status,
      ).toBe(404);
      expect((await status()).body.posDelivery.status).toBe('CLAIMED');
    });
    it('missing request UUID, invalid lines/date/status/unknown kind and unauthenticated callers have no effects', async () => {
      const invalid = [
        [
          'takeaway_create',
          {
            ...body('takeaway_create'),
            items: [{ itemName: 'Bad', unitPrice: NaN, quantity: 1 }],
          },
        ],
        [
          'reservation_create',
          { ...body('reservation_create'), reservationDate: '2026-02-30' },
        ],
        [
          'reservation_status',
          { reservationId: 'booking', status: 'completed' },
        ],
        ['unsupported', {}],
      ] as const;
      for (const [kind, b] of invalid)
        expect((await submit(kind, b)).status).toBe(400);
      expect(
        (
          await send('/mobile/operation-requests/takeaway_create', {
            body: body('takeaway_create'),
          })
        ).status,
      ).toBe(400);
      expect(
        (
          await submit(
            'takeaway_create',
            body('takeaway_create'),
            requestId,
            '',
          )
        ).status,
      ).toBe(401);
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(0);
    });
    it('legacy create/cancel routes without retained UUID cannot mutate mirrors or queue work', async () => {
      for (const path of [
        '/mobile/takeaway-orders',
        '/mobile/walk-in-orders',
        '/mobile/reservations',
        '/mobile/order/1/cancel',
        '/mobile/reservations/booking/status',
      ])
        expect(
          (
            await send(
              path,
              body(
                path.includes('reservation')
                  ? 'reservation_create'
                  : 'takeaway_create',
              ),
            )
          ).status,
        ).toBe(400);
      expect(
        await db.edgeCommand.count({ where: { venueId: staff.venueId } }),
      ).toBe(0);
      expect(
        (await db.order.findFirstOrThrow({ where: { venueId: staff.venueId } }))
          .status,
      ).toBe('confirmed');
    });
    it('same request resolves retained outcome after primary is cleared, with no fresh allocation', async () => {
      const first = await submit();
      await db.venue.update({
        where: { id: staff.venueId },
        data: { activeOperationalDeviceId: null },
      });
      const retry = await submit();
      expect(retry.body.posDelivery.commandId).toBe(
        first.body.posDelivery.commandId,
      );
      expect(retry.body.posOrderId).toBe(first.body.posOrderId);
    });
  },
);
