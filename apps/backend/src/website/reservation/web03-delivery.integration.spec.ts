import * as posIdentity from '../../pos/pos-reservation-id';
import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { Test } from '@nestjs/testing';
import { BadRequestException, type INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../../prisma.service';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { ReservationService } from './reservation.service';
import { WebsitePosReservationBridgeService } from './website-pos-reservation-bridge.service';
import { BogController } from '../payment/payment.controller';
import { BogService } from '../payment/payment.service';
import { WebsiteAuthService } from '../auth/auth.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { EdgeCommandService } from '../../edge/edge-command.service';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { PlatformWebsiteDeliveriesController } from '../../platform/platform-website-deliveries.controller';
import { PlatformAuthService } from '../../platform/platform-auth.service';
import { PlatformAuthGuard } from '../../platform/platform-auth.guard';
import { BOOTSTRAP_VENUE_ID } from '../../auth/legacy-pos-tenant.service';
import type { MenuService } from '../menu/menu.service';
import type { MonitoringGateway } from '../../realtime/monitoring.gateway';
import type { PosOutboxService } from '../../pos/pos-outbox.service';
import type { PosCallbackClient } from '../../pos/pos-callback.client';

const url = process.env.WEB03_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'WEB-03 durable payment handoff / PostgreSQL + real HTTP',
  () => {
    let db: PrismaService,
      app: INestApplication,
      commands: EdgeCommandService,
      dispatcher: PosCommandDispatcher,
      admin: string,
      support: string;
    const envBefore = { ...process.env };
    const wakeup = {
      pushConfirmedReservationToPos: jest.fn(),
      cancelPosReservation: jest.fn(),
    };
    const broadcast = jest.fn();
    const legacyKick = jest.fn();
    const verifySignature = jest.fn(
      (_: string, signature: string) => signature === 'fixture-signature',
    );
    const http = () => request(app.getHttpServer() as Server);
    const worker = () =>
      new WebsitePosReservationBridgeService(
        db,
        { broadcastUpdate: broadcast } as unknown as MonitoringGateway,
        {
          getMenuItemById: () => Promise.resolve({ nameEn: 'Stored item' }),
          getPosItemIdByCloudId: () => Promise.resolve('pos-item'),
        } as unknown as MenuService,
        new PosReservationMirrorService(db),
        dispatcher,
      );
    const lastPaymentStatus = new Map<string, string>();
    const pay = (
      f: { bookingId: string; paymentId: string },
      status = 'completed',
      paymentId = f.paymentId,
    ) => {
      lastPaymentStatus.set(f.bookingId, status);
      return http()
        .post('/api/bog/payment-callback')
        .set('Host', 'foreign.test.invalid')
        .set('callback-signature', 'fixture-signature')
        .send({
          event: 'order_payment',
          body: {
            external_order_id: f.bookingId,
            order_id: paymentId,
            order_status: { key: status },
            payment_detail: { code_description: 'Synthetic payment outcome' },
          },
        });
    };
    async function fixture(
      options: {
        device?: boolean;
        organizationId?: string;
        bootstrap?: boolean;
        posId?: string;
        confirmed?: boolean;
      } = {},
    ) {
      const organizationId =
        options.organizationId ??
        (
          await db.organization.create({
            data: { name: 'WEB03 synthetic organization' },
          })
        ).id;
      const venue = options.bootstrap
        ? await db.venue.findUniqueOrThrow({
            where: { id: BOOTSTRAP_VENUE_ID },
          })
        : await db.venue.create({
            data: {
              organizationId,
              name: 'WEB03 synthetic venue',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
          });
      const device =
        options.device === false
          ? null
          : await db.device.create({
              data: {
                venueId: venue.id,
                installationId: randomUUID(),
                displayName: 'Synthetic POS',
                platform: 'test',
                credentialHash: 'unused-fixture-only',
              },
            });
      if (device)
        await db.venue.update({
          where: { id: venue.id },
          data: { activeOperationalDeviceId: device.id },
        });
      const table = await db.websiteTable.create({
        data: {
          venueId: venue.id,
          websiteTableNumber: randomUUID(),
          posTableNumber: '1',
          posFloor: 'first',
          capacity: 4,
        },
      });
      const revision =
        (await db.paymentIntegration.count({ where: { venueId: venue.id } })) +
        1;
      const integration = await db.paymentIntegration.create({
        data: {
          venueId: venue.id,
          provider: 'BOG',
          revision,
          encryptedConfig: 'unused-fixture-only',
        },
      });
      const paymentId = `synthetic-${randomUUID()}`;
      const booking = await db.websiteReservation.create({
        data: {
          venueId: venue.id,
          paymentIntegrationId: integration.id,
          paymentId,
          date: new Date('2035-01-01'),
          timeSlot: '18:00',
          customerName: 'Synthetic guest',
          customerPhone: 'fixture-phone',
          customerEmail: 'fixture@test.invalid',
          numberOfGuests: 3,
          totalAmount: 25,
          menuItems: JSON.stringify([
            { id: 'cloud-item', name: 'Frozen name', price: 12.5, quantity: 2 },
          ]),
          ...(!options.confirmed
            ? {
                paymentExpectedMinor: '2500',
                paymentCurrency: 'GEL',
                holdState: 'HELD',
                paymentWindowStartedAt: new Date(),
                holdExpiresAt: new Date(Date.now() + 600_000),
                dayHolds: {
                  create: { serviceDate: '2035-01-01', tableCode: 1 },
                },
              }
            : { paymentState: 'UNTRACKED' }),
          ...(options.posId ? { posReservationId: options.posId } : {}),
          ...(options.confirmed ? { status: 'CONFIRMED' } : {}),
          tables: { create: { tableId: table.id } },
        },
      });
      return {
        venueId: venue.id,
        organizationId: venue.organizationId,
        deviceId: device?.id ?? '',
        bookingId: booking.id,
        paymentId,
        tableId: table.id,
      };
    }
    const intents = (f: { bookingId: string }) =>
      db.websiteReservationDeliveryIntent.findMany({
        where: { reservationId: f.bookingId },
        orderBy: { kind: 'desc' },
      });
    const queue = (f: { venueId: string }) =>
      db.edgeCommand.findMany({
        where: { venueId: f.venueId },
        orderBy: { createdAt: 'asc' },
      });
    const read = (f: { venueId: string }, token = admin, suffix = '') =>
      http()
        .get(`/platform/venues/${f.venueId}/website-deliveries${suffix}`)
        .set('Authorization', `Bearer ${token}`);
    const due = (f: { bookingId: string }) =>
      db.websiteReservationDeliveryIntent.updateMany({
        where: { reservationId: f.bookingId, status: 'PENDING' },
        data: { nextAttemptAt: new Date(0) },
      });
    async function failureTrigger(
      table:
        | 'WebsiteReservationDeliveryIntent'
        | 'EdgeCommand'
        | 'reservations',
      operation: 'INSERT' | 'UPDATE',
      work: () => Promise<void>,
    ) {
      const schema = table === 'reservations' ? 'website' : 'pos';
      const condition =
        table === 'reservations'
          ? 'IF NEW."posReservationId" IS NOT NULL THEN RAISE EXCEPTION \'synthetic DB fault\'; END IF;'
          : "RAISE EXCEPTION 'synthetic DB fault';";
      await db.$executeRawUnsafe(
        `CREATE FUNCTION pos.web03_test_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN ${condition} RETURN NEW; END $$`,
      );
      await db.$executeRawUnsafe(
        `CREATE TRIGGER web03_test_fault BEFORE ${operation} ON ${schema}."${table}" FOR EACH ROW EXECUTE FUNCTION pos.web03_test_fault()`,
      );
      try {
        await work();
      } finally {
        await db.$executeRawUnsafe(
          `DROP TRIGGER web03_test_fault ON ${schema}."${table}"`,
        );
        await db.$executeRawUnsafe('DROP FUNCTION pos.web03_test_fault()');
      }
    }
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('web03')
      )
        throw new Error('Use a fresh disposable_web03 database');
      process.env.JWT_SECRET = 'web03-fixture-signing-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      commands = new EdgeCommandService(db);
      dispatcher = new PosCommandDispatcher(
        db,
        commands,
        {} as PosCallbackClient,
        { processDue: legacyKick } as unknown as PosOutboxService,
      );
      const jwt = new JwtService();
      for (const role of ['SUPER_ADMIN', 'SUPPORT_READONLY'] as const) {
        const operator = await db.platformUser.create({
          data: {
            email: `${randomUUID()}@test.invalid`,
            displayName: 'Synthetic operator',
            passwordHash: 'unused-fixture-only',
            role,
          },
        });
        const token = await jwt.signAsync(
          { sub: operator.id, typ: 'PLATFORM' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-platform',
            issuer: 'vynic',
          },
        );
        if (role === 'SUPER_ADMIN') admin = token;
        else support = token;
      }
      const bog = {
        verifyCallbackSignature: verifySignature,
        getPaymentDetailsForReservation: async (
          reservationId: string,
          paymentId: string,
        ) => {
          const row = await db.websiteReservation.findUniqueOrThrow({
            where: { id: reservationId },
          });
          if (row.paymentId !== paymentId)
            throw new BadRequestException('Payment reference mismatch');
          const key = lastPaymentStatus.get(reservationId) ?? 'completed';
          return {
            order_id: paymentId,
            external_order_id: reservationId,
            capture: 'automatic',
            order_status: { key },
            purchase_units: {
              currency_code: 'GEL',
              request_amount: '25.00',
              transfer_amount:
                key === 'refunded'
                  ? '0.00'
                  : key === 'rejected'
                    ? '0.00'
                    : '25.00',
              refund_amount: key === 'refunded' ? '25.00' : '0.00',
            },
          };
        },
      };
      const entitlements = new VenueEntitlementsService(db);
      const mod = await Test.createTestingModule({
        controllers: [BogController, PlatformWebsiteDeliveriesController],
        providers: [
          { provide: PrismaService, useValue: db },
          JwtService,
          PlatformAuthService,
          PlatformAuthGuard,
          {
            provide: ConfigService,
            useValue: new ConfigService({
              PLATFORM_JWT_SECRET: process.env.JWT_SECRET,
            }),
          },
          { provide: BogService, useValue: bog },
          {
            provide: ReservationService,
            useValue: new ReservationService(
              db,
              bog as unknown as BogService,
              wakeup as unknown as WebsitePosReservationBridgeService,
            ),
          },
          { provide: WebsiteAuthService, useValue: {} },
          { provide: VenueEntitlementsService, useValue: entitlements },
          {
            provide: WebsiteCapabilitiesService,
            useValue: new WebsiteCapabilitiesService(db, entitlements),
          },
          {
            provide: WebsiteTenantService,
            useValue: new WebsiteTenantService(
              db,
              new ConfigService({ NODE_ENV: 'production' }),
            ),
          },
        ],
      }).compile();
      app = mod.createNestApplication({ rawBody: true, logger: false });
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      process.env = envBefore;
    });
    it('rejects unsigned callbacks and wrong payment reference before creating intents', async () => {
      const f = await fixture();
      await http().post('/api/bog/payment-callback').send({}).expect(401);
      await pay(f, 'completed', 'foreign-payment').expect(400);
      expect(await intents(f)).toHaveLength(0);
    });
    it('commits paid status + immutable snapshot together, without a premature POS link', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      const [intent] = await intents(f);
      expect(intent).toMatchObject({
        status: 'PENDING',
        kind: 'CREATE',
        queueId: null,
      });
      expect(
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: f.bookingId },
        }),
      ).toMatchObject({
        status: 'CONFIRMED',
        paymentStatus: 'completed',
        posReservationId: null,
      });
      expect(await queue(f)).toHaveLength(0);
      await expect(
        db.websiteReservationDeliveryIntent.update({
          where: { id: intent.id },
          data: { snapshot: {} },
        }),
      ).rejects.toThrow();
    });
    it('rolls back the payment outcome when the intent cannot be persisted', async () => {
      const f = await fixture();
      await failureTrigger(
        'WebsiteReservationDeliveryIntent',
        'INSERT',
        async () => {
          await pay(f).expect(500);
        },
      );
      expect(await intents(f)).toHaveLength(0);
      expect(
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: f.bookingId },
        }),
      ).toMatchObject({ status: 'PENDING', paymentStatus: null });
      await pay(f).expect(200);
      expect(await intents(f)).toHaveLength(1);
    });
    it('concurrent duplicate callbacks retain one snapshot and one allocated identity', async () => {
      const f = await fixture();
      await Promise.all(Array.from({ length: 8 }, () => pay(f).expect(200)));
      expect(await intents(f)).toHaveLength(1);
      await Promise.all([
        worker().processDue(f.venueId),
        worker().processDue(f.venueId),
      ]);
      expect(await queue(f)).toHaveLength(1);
      const [intent] = await intents(f),
        [command] = await queue(f);
      expect(command.payload).toMatchObject({
        reservationId: intent.proposedPosReservationId,
        numberOfGuests: 3,
        tableNumbers: [1],
        preOrderItems: [
          {
            itemName: 'Frozen name',
            unitPrice: 12.5,
            quantity: 2,
            total: 25,
            menuItemId: 'pos-item',
          },
        ],
      });
      expect(
        (
          await db.websiteReservation.findUniqueOrThrow({
            where: { id: f.bookingId },
          })
        ).posReservationId,
      ).toBe(intent.proposedPosReservationId);
    });
    it.each(['EdgeCommand', 'reservations'] as const)(
      '%s fault leaves paid booking recoverable, no orphan link/queue',
      async (table) => {
        const f = await fixture();
        await pay(f).expect(200);
        const [before] = await intents(f);
        await failureTrigger(
          table,
          table === 'reservations' ? 'UPDATE' : 'INSERT',
          async () => {
            await worker().processDue(f.venueId);
          },
        );
        expect(await queue(f)).toHaveLength(0);
        expect(
          (
            await db.websiteReservation.findUniqueOrThrow({
              where: { id: f.bookingId },
            })
          ).posReservationId,
        ).toBeNull();
        expect((await intents(f))[0]).toMatchObject({
          status: 'PENDING',
          proposedPosReservationId: before.proposedPosReservationId,
          lastErrorCode: 'queue_recording_failed',
        });
        await due(f);
        await worker().processDue(f.venueId);
        expect(await queue(f)).toHaveLength(1);
        expect((await intents(f))[0].status).toBe('QUEUED');
      },
    );
    it('lost callback reply/restart and later guest/menu edits never change admitted work', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await db.websiteReservation.update({
        where: { id: f.bookingId },
        data: { customerName: 'Changed later' },
      });
      await expect(
        db.websiteReservation.update({
          where: { id: f.bookingId },
          data: { menuItems: '[]' },
        }),
      ).rejects.toThrow();
      await worker().processDue(f.venueId);
      const [original] = await queue(f);
      expect(original.payload).toMatchObject({
        customerName: 'Synthetic guest',
        preOrderItems: [{ itemName: 'Frozen name' }],
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toEqual([original]);
      await expect(
        db.websiteReservationDeliveryIntent.update({
          where: { id: (await intents(f))[0].id },
          data: { status: 'PENDING' },
        }),
      ).rejects.toThrow();
    });
    it('lost ACK redelivers the same command ID/payload, then terminal success is never revived', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      const [first] = await commands.claim(f);
      await db.edgeCommand.update({
        where: { id: first.commandId },
        data: { claimExpiresAt: new Date(0) },
      });
      const [second] = await commands.claim(f);
      expect(second).toMatchObject({
        commandId: first.commandId,
        payload: first.payload,
        idempotencyKey: first.idempotencyKey,
        attempt: 2,
      });
      await commands.acknowledge(f, {
        commandId: second.commandId,
        status: 'SUCCEEDED',
        code: 'created',
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect((await queue(f))[0]).toMatchObject({
        status: 'SUCCEEDED',
        attemptCount: 2,
      });
      const result = (await read(f).expect(200)).body as {
        items: Array<{ deliveries: Array<{ status: string }> }>;
      };
      expect(result.items[0].deliveries[0].status).toBe('SUCCEEDED');
    });
    it('terminal failure and missing receipts stay visible and are never automatically replayed', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      const [claimed] = await commands.claim(f);
      await commands.acknowledge(f, {
        commandId: claimed.commandId,
        status: 'FAILED',
        code: 'reservation_conflict',
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect((await queue(f))[0].status).toBe('FAILED');
      await db.edgeCommand.delete({ where: { id: claimed.commandId } });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toHaveLength(0);
      expect(JSON.stringify((await read(f).expect(200)).body)).toContain(
        'UNKNOWN',
      );
    });
    it('no Device leaves intent pending; later enrollment admits it once', async () => {
      const f = await fixture({ device: false });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect((await intents(f))[0]).toMatchObject({
        status: 'PENDING',
        lastErrorCode: 'awaiting_pos_enrollment',
      });
      expect(
        await db.posCallbackOutbox.count({ where: { venueId: f.venueId } }),
      ).toBe(0);
      await db.device.create({
        data: {
          venueId: f.venueId,
          installationId: randomUUID(),
          displayName: 'New POS',
          platform: 'test',
          credentialHash: 'unused-fixture-only',
        },
      });
      await due(f);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toHaveLength(1);
    });
    it('disabled Primary never falls back to LAN or a secondary terminal', async () => {
      const f = await fixture();
      await db.device.update({
        where: { id: f.deviceId },
        data: { status: 'DISABLED' },
      });
      const secondary = await db.device.create({
        data: {
          venueId: f.venueId,
          installationId: randomUUID(),
          displayName: 'Secondary',
          platform: 'test',
          credentialHash: 'unused-fixture-only',
        },
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(
        await commands.claim({ ...f, deviceId: secondary.id }),
      ).toHaveLength(0);
      expect(
        await db.posCallbackOutbox.count({ where: { venueId: f.venueId } }),
      ).toBe(0);
      expect((await queue(f))[0].status).toBe('PENDING');
    });
    it('table conflict becomes explicit attention without rebooking or automatic retry', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await db.websiteReservation.create({
        data: {
          venueId: f.venueId,
          date: new Date('2035-01-01'),
          timeSlot: '20:00',
          status: 'CONFIRMED',
          tables: { create: { tableId: f.tableId } },
        },
      });
      await worker().processDue(f.venueId);
      expect((await intents(f))[0]).toMatchObject({
        status: 'ATTENTION',
        lastErrorCode: 'tables_unavailable',
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toHaveLength(0);
    });
    it('cancellation persists before create admission and waits for the same create ACK', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await pay(f, 'refunded').expect(200);
      expect(await intents(f)).toHaveLength(2);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toHaveLength(1);
      expect((await intents(f))[1]).toMatchObject({
        kind: 'CANCEL',
        status: 'PENDING',
        lastErrorCode: 'awaiting_create_ack',
      });
      const [create] = await commands.claim(f);
      await commands.acknowledge(f, {
        commandId: create.commandId,
        status: 'SUCCEEDED',
      });
      await due(f);
      await worker().processDue(f.venueId);
      const rows = await queue(f);
      expect(rows).toHaveLength(2);
      expect(rows[1]).toMatchObject({
        type: 'RESERVATION_STATUS_UPDATE',
        payload: {
          reservationId: (await intents(f))[0].proposedPosReservationId,
          status: 'cancelled',
        },
      });
      await pay(f, 'refunded').expect(200);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toHaveLength(2);
    });
    it('unresolved create outcome puts cancellation into operator attention', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      const [create] = await commands.claim(f);
      await commands.acknowledge(f, {
        commandId: create.commandId,
        status: 'FAILED',
        code: 'outcome_unknown',
      });
      await pay(f, 'refunded').expect(200);
      await worker().processDue(f.venueId);
      expect((await intents(f))[1]).toMatchObject({
        status: 'ATTENTION',
        lastErrorCode: 'create_outcome_unresolved',
      });
      expect(await queue(f)).toHaveLength(1);
    });
    it('historical links and confirmed rows remain untracked; no new IDs or replay', async () => {
      const f = await fixture({ posId: 'old-pos-id', confirmed: true });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await intents(f)).toHaveLength(0);
      expect(await queue(f)).toHaveLength(0);
      expect(JSON.stringify((await read(f).expect(200)).body)).toContain(
        'UNTRACKED',
      );
      const unlinked = await fixture({ confirmed: true });
      await pay(unlinked).expect(200);
      await worker().processDue(unlinked.venueId);
      expect(await intents(unlinked)).toHaveLength(0);
      expect(JSON.stringify((await read(unlinked).expect(200)).body)).toContain(
        'UNTRACKED',
      );
    });
    it('untracked historical refund is reviewed without automatic POS cancellation', async () => {
      const f = await fixture({ posId: 'historical-cancel', confirmed: true });
      await pay(f, 'refunded').expect(200);
      await worker().processDue(f.venueId);
      expect(await intents(f)).toHaveLength(0);
      expect(await queue(f)).toHaveLength(0);
      expect(
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: f.bookingId },
        }),
      ).toMatchObject({
        posReservationId: 'historical-cancel',
        paymentReviewReason: 'historical_payment_snapshot_missing',
      });
    });
    it('same-organization venues and different organizations cannot cross FK, claims or status reads', async () => {
      const a = await fixture(),
        b = await fixture({ organizationId: a.organizationId }),
        c = await fixture();
      await pay(a).expect(200);
      await worker().processDue(a.venueId);
      await expect(
        db.websiteReservationDeliveryIntent.create({
          data: {
            venueId: b.venueId,
            reservationId: a.bookingId,
            kind: 'CANCEL',
            proposedPosReservationId: 'foreign',
            snapshot: {},
          },
        }),
      ).rejects.toThrow();
      expect(await commands.claim(b)).toHaveLength(0);
      expect(await commands.claim(c)).toHaveLength(0);
      expect(JSON.stringify((await read(b).expect(200)).body)).not.toContain(
        a.bookingId,
      );
      const [command] = await queue(a);
      await expect(
        commands.acknowledge(c, { commandId: command.id, status: 'SUCCEEDED' }),
      ).rejects.toThrow('Command not found');
    });
    it('Platform/support can read; customer tokens, anonymous access and write attempts are refused', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await read(f, support).expect(200);
      await http()
        .get(`/platform/venues/${f.venueId}/website-deliveries`)
        .expect(401);
      const customer = await new JwtService().signAsync(
        { sub: randomUUID(), typ: 'CUSTOMER' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-customer',
          issuer: 'vynic',
        },
      );
      await read(f, customer).expect(401);
      await read(f, admin, '?offset=-1').expect(400);
      await http()
        .post(`/platform/venues/${f.venueId}/website-deliveries`)
        .set('Authorization', `Bearer ${admin}`)
        .expect(404);
      const body = JSON.stringify((await read(f).expect(200)).body);
      for (const privateValue of [
        'fixture-phone',
        'fixture@test.invalid',
        f.paymentId,
        'Frozen name',
        'encryptedConfig',
        'snapshot',
      ])
        expect(body).not.toContain(privateValue);
    });
    it('bootstrap legacy outbox and booking link commit together; pruned receipt is unknown, not replayed', async () => {
      const f = await fixture({ bootstrap: true, device: false });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      const [intent] = await intents(f);
      expect(intent).toMatchObject({
        status: 'QUEUED',
        queueTransport: 'legacy',
      });
      const receipt = await db.posCallbackOutbox.findUniqueOrThrow({
        where: { id: intent.queueId! },
      });
      expect(receipt).toMatchObject({
        endpoint: '/mobile-reservation-create',
        venueId: BOOTSTRAP_VENUE_ID,
      });
      expect(legacyKick).toHaveBeenCalledWith({ venueId: BOOTSTRAP_VENUE_ID });
      await db.posCallbackOutbox.update({
        where: { id: receipt.id },
        data: { status: 'delivered' },
      });
      expect(JSON.stringify((await read(f).expect(200)).body)).toContain(
        'DELIVERED_LEGACY',
      );
      await db.posCallbackOutbox.delete({ where: { id: receipt.id } });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(
        await db.posCallbackOutbox.count({ where: { venueId: f.venueId } }),
      ).toBe(0);
      expect(JSON.stringify((await read(f).expect(200)).body)).toContain(
        'UNKNOWN',
      );
    });

    it.each(['partial_completed', 'auth_requested'])(
      '%s cannot confirm a paid booking',
      async (status) => {
        const f = await fixture();
        await pay(f, status).expect(200);
        expect(await intents(f)).toHaveLength(0);
        expect(
          (
            await db.websiteReservation.findUniqueOrThrow({
              where: { id: f.bookingId },
            })
          ).status,
        ).not.toBe('CONFIRMED');
      },
    );
    it('collision allocation reserves a different identity for the second booking', async () => {
      const f = await fixture();
      const second = await db.websiteReservation.create({
        data: {
          venueId: f.venueId,
          date: new Date('2035-01-02'),
          timeSlot: '18:00',
          paymentExpectedMinor: '2500',
          paymentCurrency: 'GEL',
          holdState: 'HELD',
          paymentWindowStartedAt: new Date(),
          holdExpiresAt: new Date(Date.now() + 600_000),
          dayHolds: { create: { tableCode: 1, serviceDate: '2035-01-02' } },
          paymentId: 'synthetic-second-payment',
          paymentIntegrationId: (
            await db.websiteReservation.findUniqueOrThrow({
              where: { id: f.bookingId },
            })
          ).paymentIntegrationId,
          tables: { create: { tableId: f.tableId } },
        },
      });
      const allocation = jest
        .spyOn(posIdentity, 'allocatePosReservationId')
        .mockReturnValueOnce('2030000000000001')
        .mockReturnValueOnce('2030000000000001')
        .mockReturnValue('2030000000000002');
      try {
        await pay(f).expect(200);
        await pay({
          bookingId: second.id,
          paymentId: 'synthetic-second-payment',
        }).expect(200);
        expect((await intents(f))[0].proposedPosReservationId).toBe(
          '2030000000000001',
        );
        expect(
          (await intents({ bookingId: second.id }))[0].proposedPosReservationId,
        ).toBe('2030000000000002');
        expect(allocation).toHaveBeenCalledTimes(3);
      } finally {
        allocation.mockRestore();
      }
    });
    it('a pre-existing different command cannot be rewritten or revived by handoff retry', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      const original = await db.edgeCommand.create({
        data: {
          venueId: f.venueId,
          type: 'RESERVATION_CREATE',
          contractVersion: 2,
          idempotencyKey: `RESERVATION_CREATE:website:${f.bookingId}`,
          payload: { reservationId: 'different-pos-id' },
          status: 'FAILED',
          attemptCount: 4,
        },
      });
      await worker().processDue(f.venueId);
      expect((await intents(f))[0]).toMatchObject({
        status: 'ATTENTION',
        lastErrorCode: 'identity_conflict',
      });
      expect(await queue(f)).toEqual([original]);
      expect(
        (
          await db.websiteReservation.findUniqueOrThrow({
            where: { id: f.bookingId },
          })
        ).posReservationId,
      ).toBeNull();
    });
    it('post-commit notification failure cannot replay committed queue work', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      broadcast.mockImplementationOnce(() => {
        throw new Error('synthetic wake-up failure');
      });
      await worker().processDue(f.venueId);
      const [before] = await queue(f);
      expect((await intents(f))[0].status).toBe('QUEUED');
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await queue(f)).toEqual([before]);
    });
    it('unsupported stored table identity is visible attention, not an endless queue retry', async () => {
      const f = await fixture();
      await db.websiteTable.update({
        where: { id: f.tableId },
        data: { posFloor: 'terrace' },
      });
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      expect(await intents(f)).toHaveLength(0);
      expect(
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: f.bookingId },
        }),
      ).toMatchObject({ paymentReviewReason: 'hold_identity_missing' });
      expect(await queue(f)).toHaveLength(0);
    });

    it('generic enqueue cannot rewrite or revive an outbox-owned terminal command', async () => {
      const f = await fixture();
      await pay(f).expect(200);
      await worker().processDue(f.venueId);
      const [claimed] = await commands.claim(f);
      await commands.acknowledge(f, {
        commandId: claimed.commandId,
        status: 'SUCCEEDED',
      });
      const [before] = await queue(f);
      await expect(
        commands.enqueue(f, {
          type: 'RESERVATION_CREATE',
          payload: claimed.payload as Record<string, unknown>,
          idempotencyKey: claimed.idempotencyKey,
          contractVersion: claimed.contractVersion,
        }),
      ).rejects.toThrow();
      await expect(
        db.edgeCommand.update({
          where: { id: claimed.commandId },
          data: { payload: {} },
        }),
      ).rejects.toThrow();
      expect(await queue(f)).toEqual([before]);
    });
  },
);
