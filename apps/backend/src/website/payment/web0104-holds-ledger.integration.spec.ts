import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
jest.mock('axios');
import axios from 'axios';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { Test } from '@nestjs/testing';
import type { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma.service';
import request from 'supertest';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { BogService } from './payment.service';
import { BogController } from './payment.controller';
import { MenuService } from '../menu/menu.service';
import { TableController } from '../reservation/reservation.controller';
import { ReservationService } from '../reservation/reservation.service';
import { WebsiteAuthService } from '../auth/auth.service';
import { WebsitePosReservationBridgeService } from '../reservation/website-pos-reservation-bridge.service';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandService } from '../../edge/edge-command.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import { encryptPaymentConfig } from '../../payment-integrations/payment-config.crypto';
import { CustomerWebsitePaymentReviewsController } from '../../customer/customer-website-payment-reviews.controller';
import { PlatformWebsitePaymentReviewsController } from '../../platform/platform-website-payment-reviews.controller';
import { CustomerAuth, CustomerGuard } from '../../customer/customer-auth';
import { CustomerService } from '../../customer/customer.service';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { PlatformAuthService } from '../../platform/platform-auth.service';
import { PlatformAuthGuard } from '../../platform/platform-auth.guard';
import type { MonitoringGateway } from '../../realtime/monitoring.gateway';
import type { PosOutboxService } from '../../pos/pos-outbox.service';
import type { PosCallbackClient } from '../../pos/pos-callback.client';

const url = process.env.WEB0104_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'WEB-01/04 approved whole-day holds + money ledger / actual HTTP and PostgreSQL',
  () => {
    let db: PrismaService,
      app: INestApplication,
      bog: BogService,
      reservations: ReservationService,
      bridge: WebsitePosReservationBridgeService,
      admin: string;
    const originalEnv = { ...process.env };
    const post = jest.spyOn(axios, 'post'),
      get = jest.spyOn(axios, 'get');
    type Fixture = {
      venueId: string;
      organizationId: string;
      host: string;
      itemId: string;
      tableId: number;
      ownerToken: string;
      integrationId: string;
      clientId: string;
    };
    const fixtures: Fixture[] = [];
    const provider = new Map<string, Record<string, unknown>>();
    const createdRequests: Array<{
      bookingId: string;
      ttl: number;
      capture: string;
      amount: number;
    }> = [];
    let beforeCreateReply:
      | ((bookingId: string, paymentId: string) => Promise<void>)
      | undefined;
    let replacementCreateId: string | undefined;
    let loseNextCreate = false,
      failReads = false,
      createDay = 0;
    const http = () => request(app.getHttpServer() as Server);
    const f0 = () => fixtures[0];
    const freshDate = () =>
      new Date(Date.UTC(2030, 0, ++createDay)).toISOString().slice(0, 10);
    const create = (f = f0(), date = freshDate(), time = '18:00') =>
      http()
        .post('/api/bog/create-order')
        .set('Host', f.host)
        .send({
          selectedTables: ['table1'],
          selectedDate: date,
          selectedTime: time,
          menuItems: [{ id: f.itemId, quantity: 1 }],
          customerName: 'Synthetic guest',
          customerEmail: 'guest@test.invalid',
          customerPhone: 'fixture-phone',
          totalAmount: 0.01,
        });
    const receipt = (
      id: string,
      bookingId: string,
      status = 'completed',
      remaining = '11.00',
      refund = '0.00',
      dates?: { created: Date; expires: Date },
    ) => ({
      order_id: id,
      external_order_id: bookingId,
      capture: 'automatic',
      order_status: { key: status },
      purchase_units: {
        request_amount: '11.00',
        transfer_amount: remaining,
        refund_amount: refund,
        currency_code: 'GEL',
      },
      zoned_create_date: (dates?.created ?? new Date()).toISOString(),
      zoned_expire_date: (
        dates?.expires ?? new Date(Date.now() + 600_000)
      ).toISOString(),
    });
    async function seed(
      options: {
        expired?: boolean;
        confirmed?: boolean;
        historical?: boolean;
        storedDate?: Date;
        date?: string;
        fixture?: Fixture;
      } = {},
    ) {
      const f = options.fixture ?? f0(),
        now = Date.now();
      const createdAt = new Date(
        now - (options.expired ? 15 * 60_000 : 60_000),
      );
      const expiresAt = new Date(
        now + (options.expired ? -2 * 60_000 : 9 * 60_000),
      );
      const row = await db.websiteReservation.create({
        data: {
          venueId: f.venueId,
          paymentIntegrationId: f.integrationId,
          date:
            options.storedDate ??
            new Date(`${options.date ?? freshDate()}T00:00:00Z`),
          timeSlot: '18:00',
          totalAmount: 11,
          customerName: 'Synthetic private guest',
          customerPhone: 'fixture-private-phone',
          menuItems: JSON.stringify([
            { id: f.itemId, name: 'Captured dish', price: 10, quantity: 1 },
          ]),
          createdAt,
          status: options.confirmed ? 'CONFIRMED' : 'PENDING',
          ...(!options.historical
            ? {
                paymentExpectedMinor: '1100',
                paymentCurrency: 'GEL',
                paymentState: options.confirmed ? 'PAID' : 'PENDING',
                paymentWindowStartedAt: new Date(createdAt.getTime() + 1000),
                holdExpiresAt: expiresAt,
                holdState: options.confirmed ? 'CONFIRMED' : 'HELD',
                ...(options.confirmed
                  ? {
                      paymentGrossMinor: '1100',
                      paymentRefundedMinor: '0',
                      paymentTimelyProofAt: new Date(
                        createdAt.getTime() + 10_000,
                      ),
                    }
                  : {}),
                dayHolds: {
                  create: {
                    serviceDate:
                      options.date ??
                      new Date(Date.UTC(2030, 0, createDay))
                        .toISOString()
                        .slice(0, 10),
                    tableCode: 1,
                    status: options.confirmed ? 'CONFIRMED' : 'HELD',
                  },
                },
              }
            : { paymentState: 'UNTRACKED' }),
          tables: { create: { tableId: f.tableId } },
        },
      });
      const paymentId = `synthetic-bank-${row.id}`;
      await db.websiteReservation.update({
        where: { id: row.id },
        data: { paymentId },
      });
      provider.set(
        paymentId,
        receipt(paymentId, row.id, 'completed', '11.00', '0.00', {
          created: new Date(createdAt.getTime() + 1000),
          expires: expiresAt,
        }),
      );
      return { ...row, paymentId, expiresAt, f };
    }
    const callback = (
      bookingId: string,
      paymentId: string,
      snapshot: Record<string, unknown>,
      sentAt = new Date(),
    ) =>
      http()
        .post('/api/bog/payment-callback')
        .set('callback-signature', 'fixture-signature')
        .send({
          event: 'order_payment',
          zoned_request_time: sentAt.toISOString(),
          body: {
            ...snapshot,
            external_order_id: bookingId,
            order_id: paymentId,
          },
        });
    const pay = (row: Awaited<ReturnType<typeof seed>>, sentAt = new Date()) =>
      callback(row.id, row.paymentId, provider.get(row.paymentId)!, sentAt);
    const booking = (id: string) =>
      db.websiteReservation.findUniqueOrThrow({ where: { id } });
    const observations = (id: string) =>
      db.websitePaymentObservation.findMany({ where: { reservationId: id } });
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('web0104')
      )
        throw new Error('Use a fresh disposable_web0104 database');
      process.env.JWT_SECRET = 'web0104-synthetic-signing-key';
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = '34'.repeat(32);
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const jwt = new JwtService(),
        config = new ConfigService({
          NODE_ENV: 'production',
          PLATFORM_JWT_SECRET: process.env.JWT_SECRET,
        });
      const entitlements = new VenueEntitlementsService(db),
        menu = new MenuService(db);
      bog = new BogService(
        menu,
        new PaymentIntegrationsService(db, entitlements),
        db,
      );
      const dispatcher = new PosCommandDispatcher(
        db,
        new EdgeCommandService(db),
        {} as PosCallbackClient,
        { processDue: () => Promise.resolve() } as unknown as PosOutboxService,
      );
      bridge = new WebsitePosReservationBridgeService(
        db,
        { broadcastUpdate: () => {} } as unknown as MonitoringGateway,
        menu,
        new PosReservationMirrorService(db),
        dispatcher,
      );
      reservations = new ReservationService(db, bog, bridge);
      const organization = await db.organization.create({
        data: { name: 'Synthetic WEB0104 organization' },
      });
      for (let i = 0; i < 3; i++) {
        const orgId =
          i < 2
            ? organization.id
            : (
                await db.organization.create({
                  data: { name: 'Other synthetic organization' },
                })
              ).id;
        const host = `web0104-${i}-${randomUUID()}.localhost`;
        const venue = await db.venue.create({
          data: {
            organizationId: orgId,
            name: `Synthetic venue ${i}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            legacyCommercialAccess: true,
            websiteConfig: { create: { mode: 'CUSTOM' } },
            domains: { create: { hostname: host } },
          },
        });
        for (const key of ['WEBSITE', 'ONLINE_PAYMENTS'])
          await db.venueFeatureOverride.create({
            data: {
              venueId: venue.id,
              featureId: (
                await db.feature.findUniqueOrThrow({ where: { key } })
              ).id,
              effect: 'ENABLED',
            },
          });
        const table = await db.websiteTable.create({
          data: {
            venueId: venue.id,
            websiteTableNumber: 'table1',
            posTableNumber: '1',
            posFloor: 'first',
          },
        });
        const item = await db.menuItem.create({
          data: {
            venueId: venue.id,
            posMenuItemId: `fixture-item-${i}`,
            nameEn: 'Captured dish',
            nameKa: 'სატესტო კერძი',
            price: 10,
          },
        });
        const clientId = `synthetic-client-${i}`;
        const integrationId = randomUUID();
        const integration = await db.paymentIntegration.create({
          data: {
            venueId: venue.id,
            id: integrationId,
            provider: 'BOG',
            revision: 1,
            encryptedConfig: encryptPaymentConfig(venue.id, integrationId, {
              clientId,
              clientSecret: 'synthetic-unused-secret',
              returnOrigin: `https://${host}`,
            }),
          },
        });
        const owner = await db.customerAccount.create({
          data: {
            email: `owner-${randomUUID()}@test.invalid`,
            displayName: 'Synthetic owner',
            passwordHash: 'unused-fixture-only',
            memberships: { create: { organizationId: orgId, role: 'OWNER' } },
          },
        });
        const ownerToken = await jwt.signAsync(
          { sub: owner.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        );
        const device = await db.device.create({
          data: {
            venueId: venue.id,
            installationId: randomUUID(),
            displayName: 'Synthetic POS',
            platform: 'test',
            credentialHash: 'unused-fixture-only',
          },
        });
        await db.venue.update({
          where: { id: venue.id },
          data: { activeOperationalDeviceId: device.id },
        });
        fixtures.push({
          venueId: venue.id,
          organizationId: orgId,
          host,
          itemId: item.id,
          tableId: table.id,
          ownerToken,
          integrationId: integration.id,
          clientId,
        });
      }
      const operator = await db.platformUser.create({
        data: {
          email: `admin-${randomUUID()}@test.invalid`,
          displayName: 'Synthetic admin',
          passwordHash: 'unused-fixture-only',
        },
      });
      admin = await jwt.signAsync(
        { sub: operator.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
        },
      );
      post.mockImplementation(async (endpoint: string, input: unknown) => {
        if (endpoint.includes('openid-connect'))
          return { data: { access_token: 'synthetic-bank-token' } };
        const data = input as {
          external_order_id: string;
          ttl: number;
          capture: string;
          purchase_units: { total_amount: number };
        };
        const row = await booking(data.external_order_id);
        const id = `synthetic-bank-${row.id}`;
        provider.set(id, receipt(id, row.id, 'created', '0.00', '0.00'));
        createdRequests.push({
          bookingId: row.id,
          ttl: data.ttl,
          capture: data.capture,
          amount: data.purchase_units.total_amount,
        });
        if (loseNextCreate) {
          loseNextCreate = false;
          throw new Error('Synthetic lost create reply');
        }
        if (beforeCreateReply) await beforeCreateReply(row.id, id);
        return {
          data: {
            id: replacementCreateId ?? id,
            _links: {
              redirect: { href: 'https://bank.test.invalid/checkout' },
            },
          },
        };
      });
      get.mockImplementation((endpoint: string) => {
        if (failReads)
          return Promise.reject(
            new Error('Synthetic receipt read unavailable'),
          );
        const id = decodeURIComponent(endpoint.split('/').at(-1)!);
        const data = provider.get(id);
        return data
          ? Promise.resolve({ data })
          : Promise.reject(new Error('Synthetic payment not found'));
      });
      jest
        .spyOn(bog, 'verifyCallbackSignature')
        .mockImplementation(
          (_, signature) => signature === 'fixture-signature',
        );
      const mod = await Test.createTestingModule({
        controllers: [
          BogController,
          TableController,
          CustomerWebsitePaymentReviewsController,
          PlatformWebsitePaymentReviewsController,
        ],
        providers: [
          { provide: PrismaService, useValue: db },
          { provide: ConfigService, useValue: config },
          { provide: JwtService, useValue: jwt },
          { provide: BogService, useValue: bog },
          { provide: ReservationService, useValue: reservations },
          {
            provide: WebsiteAuthService,
            useValue: { tryGetUserFromRequest: () => Promise.resolve(null) },
          },
          { provide: VenueEntitlementsService, useValue: entitlements },
          {
            provide: WebsiteTenantService,
            useValue: new WebsiteTenantService(db, config),
          },
          {
            provide: WebsiteCapabilitiesService,
            useValue: new WebsiteCapabilitiesService(db, entitlements),
          },
          {
            provide: CustomerService,
            useValue: new CustomerService(
              db,
              entitlements,
              {} as never,
              {} as never,
            ),
          },
          {
            provide: CustomerAuth,
            useValue: new CustomerAuth(db, jwt, new EnrollmentRateLimiter()),
          },
          CustomerGuard,
          PlatformAuthService,
          PlatformAuthGuard,
        ],
      }).compile();
      app = mod.createNestApplication({ rawBody: true, logger: false });
      await app.init();
    });
    afterEach(() => {
      beforeCreateReply = undefined;
      replacementCreateId = undefined;
      failReads = false;
      loseNextCreate = false;
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      process.env = originalEnv;
      jest.restoreAllMocks();
    });

    it('20 parallel requests for the same physical table/day admit one hold and one bank order', async () => {
      const date = freshDate(),
        before = createdRequests.length;
      const responses = await Promise.all(
        Array.from({ length: 20 }, (_, i) =>
          create(f0(), date, i % 2 ? '20:00' : '18:00'),
        ),
      );
      expect(responses.filter((r) => r.status === 201)).toHaveLength(1);
      expect(responses.filter((r) => r.status === 400)).toHaveLength(19);
      expect(
        await db.websiteReservationDayHold.count({
          where: { venueId: f0().venueId, serviceDate: date, status: 'HELD' },
        }),
      ).toBe(1);
      expect(createdRequests.slice(before)).toHaveLength(1);
      expect(createdRequests.at(-1)).toMatchObject({
        ttl: 10,
        capture: 'automatic',
        amount: 11,
      });
    });
    it('different days and different Venues in the same/different organizations hold independently', async () => {
      const date = freshDate();
      await create(fixtures[0], date).expect(201);
      await create(fixtures[1], date).expect(201);
      await create(fixtures[2], date).expect(201);
      await create(fixtures[0], freshDate()).expect(201);
    });
    it('aliases cannot double-allocate a physical POS table', async () => {
      await db.websiteTable.create({
        data: {
          venueId: f0().venueId,
          websiteTableNumber: 'alias',
          posTableNumber: '01',
          posFloor: 'first',
        },
      });
      const date = freshDate();
      await create(f0(), date).expect(201);
      await http()
        .post('/api/bog/create-order')
        .set('Host', f0().host)
        .send({
          selectedTables: ['alias'],
          selectedDate: date,
          selectedTime: '22:00',
          menuItems: [],
        })
        .expect(400);
    });
    it('fully verified timely payment records immutable observation, confirms occupancy and queues exactly once', async () => {
      const row = await seed(),
        sentAt = new Date();
      await Promise.all(
        Array.from({ length: 8 }, () => pay(row, sentAt).expect(200)),
      );
      expect(await booking(row.id)).toMatchObject({
        status: 'CONFIRMED',
        paymentState: 'PAID',
        paymentGrossMinor: '1100',
        paymentRefundedMinor: '0',
        holdState: 'CONFIRMED',
        paymentReviewReason: null,
      });
      expect(await observations(row.id)).toHaveLength(1);
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id, kind: 'CREATE' },
        }),
      ).toBe(1);
      expect(
        await db.edgeCommand.count({
          where: {
            venueId: row.venueId,
            idempotencyKey: `RESERVATION_CREATE:website:${row.id}`,
          },
        }),
      ).toBe(1);
      const observation = (await observations(row.id))[0];
      await expect(
        db.websitePaymentObservation.update({
          where: { id: observation.id },
          data: { reason: 'changed' },
        }),
      ).rejects.toThrow();
    });
    it('unsigned callback and wrong provider references cannot alter money or occupancy', async () => {
      const row = await seed();
      await http()
        .post('/api/bog/payment-callback')
        .send({ event: 'order_payment', body: provider.get(row.paymentId) })
        .expect(401);
      provider.set(row.paymentId, {
        ...provider.get(row.paymentId),
        external_order_id: randomUUID(),
      });
      await pay(row).expect(400);
      expect(await observations(row.id)).toHaveLength(0);
      expect((await booking(row.id)).paymentState).toBe('PENDING');
    });
    it.each([
      ['currency_code', 'USD', 'currency_mismatch'],
      ['request_amount', '1.00', 'requested_amount_mismatch'],
      ['transfer_amount', '1.00', 'partial_payment'],
      ['transfer_amount', '11.001', 'receipt_incomplete'],
    ] as const)(
      '%s=%s never confirms an underpaid/unverified booking',
      async (field, value, reason) => {
        const row = await seed();
        const raw = provider.get(row.paymentId)!;
        provider.set(row.paymentId, {
          ...raw,
          purchase_units: {
            ...(raw.purchase_units as Record<string, unknown>),
            [field]: value,
          },
        });
        await pay(row).expect(200);
        expect(await booking(row.id)).toMatchObject({
          status: 'PENDING',
          paymentReviewReason: reason,
        });
        expect(
          await db.websiteReservationDeliveryIntent.count({
            where: { reservationId: row.id },
          }),
        ).toBe(0);
      },
    );
    it.each(['auth_requested', 'blocked', 'partial_completed'])(
      '%s is not a full paid booking',
      async (status) => {
        const row = await seed();
        provider.set(row.paymentId, {
          ...provider.get(row.paymentId),
          capture: 'manual',
          order_status: { key: status },
        });
        await pay(row).expect(200);
        expect((await booking(row.id)).status).toBe('PENDING');
        expect(
          await db.websiteReservationDeliveryIntent.count({
            where: { reservationId: row.id },
          }),
        ).toBe(0);
      },
    );
    it('late callback carrying a signed completed snapshot sent before deadline confirms a still-free original hold', async () => {
      const row = await seed({ expired: true });
      const sent = new Date(row.expiresAt.getTime() - 30_000);
      await pay(row, sent).expect(200);
      expect(await booking(row.id)).toMatchObject({
        status: 'CONFIRMED',
        paymentState: 'PAID',
        holdState: 'CONFIRMED',
        paymentReviewReason: null,
      });
    });
    it('timely proof after occupancy reassignment requires owner review, never steals another hold', async () => {
      const date = freshDate(),
        old = await seed({ expired: true, date });
      await reservations.cleanupExpiredPendingReservations();
      await create(f0(), date).expect(201);
      await pay(old, new Date(old.expiresAt.getTime() - 30_000)).expect(200);
      expect(await booking(old.id)).toMatchObject({
        status: 'FAILED',
        paymentState: 'PAID',
        paymentReviewReason: 'on_time_payment_hold_reassigned',
      });
      expect(
        await db.websiteReservationDayHold.count({
          where: { venueId: f0().venueId, serviceDate: date, status: 'HELD' },
        }),
      ).toBe(1);
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: old.id },
        }),
      ).toBe(0);
    });
    it('unproven timing after expiry is review, not an invented late payment or automatic restoration', async () => {
      const row = await seed({ expired: true });
      await pay(row).expect(200);
      expect(await booking(row.id)).toMatchObject({
        status: 'FAILED',
        paymentState: 'PAID',
        paymentReviewReason: 'payment_timing_unproven',
        holdState: 'EXPIRED',
      });
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id },
        }),
      ).toBe(0);
    });
    it('provider order creation after deadline proves genuinely late payment and never triggers refund/restore', async () => {
      const row = await seed({ expired: true });
      provider.set(row.paymentId, receipt(row.paymentId, row.id));
      const count = createdRequests.length;
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentReviewReason).toBe('late_payment');
      expect(createdRequests.length).toBe(count);
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id },
        }),
      ).toBe(0);
    });
    it('partial refund preserves confirmed whole-day booking and original gross; older complete/pending observations cannot undo it', async () => {
      const row = await seed({ confirmed: true });
      provider.set(
        row.paymentId,
        receipt(row.paymentId, row.id, 'refunded_partially', '9.00', '2.00'),
      );
      await pay(row).expect(200);
      expect(await booking(row.id)).toMatchObject({
        status: 'CONFIRMED',
        paymentState: 'PARTIALLY_REFUNDED',
        paymentGrossMinor: '1100',
        paymentRefundedMinor: '200',
        holdState: 'CONFIRMED',
      });
      provider.set(row.paymentId, receipt(row.paymentId, row.id));
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentRefundedMinor).toBe('200');
      provider.set(
        row.paymentId,
        receipt(row.paymentId, row.id, 'processing', '0.00', '0.00'),
      );
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentState).toBe('PARTIALLY_REFUNDED');
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id, kind: 'CANCEL' },
        }),
      ).toBe(0);
    });
    it('a refund request alone does not cancel, and a proven full refund releases occupancy without reopening on stale complete', async () => {
      const row = await seed({ confirmed: true });
      provider.set(
        row.paymentId,
        receipt(row.paymentId, row.id, 'refund_requested'),
      );
      await pay(row).expect(200);
      expect((await booking(row.id)).status).toBe('CONFIRMED');
      provider.set(
        row.paymentId,
        receipt(row.paymentId, row.id, 'refunded', '0.00', '11.00'),
      );
      await pay(row).expect(200);
      expect(await booking(row.id)).toMatchObject({
        status: 'FAILED',
        paymentState: 'REFUNDED',
        paymentRefundedMinor: '1100',
        holdState: 'RELEASED',
      });
      provider.set(row.paymentId, receipt(row.paymentId, row.id));
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentState).toBe('REFUNDED');
    });
    it('provider read outage retains signed notification and recovers via pinned reconciliation', async () => {
      const row = await seed();
      failReads = true;
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentReviewReason).toBe(
        'provider_receipt_unavailable',
      );
      expect(await observations(row.id)).toHaveLength(1);
      failReads = false;
      await db.websiteReservation.update({
        where: { id: row.id },
        data: { nextPaymentCheckAt: new Date(0) },
      });
      await reservations.reconcileOutstandingPayments();
      expect((await booking(row.id)).paymentState).toBe('PAID');
    });
    it('lost create reply keeps held identity and its signed provider callback recovers without a second order', async () => {
      const date = freshDate();
      loseNextCreate = true;
      const before = createdRequests.length;
      await create(f0(), date).expect(502);
      const row = await db.websiteReservation.findFirstOrThrow({
        where: { id: createdRequests.at(-1)!.bookingId, venueId: f0().venueId },
      });
      const id = `synthetic-bank-${row.id}`;
      provider.set(id, receipt(id, row.id));
      await create(f0(), date).expect(400);
      expect(createdRequests.length - before).toBe(1);
      await callback(row.id, id, provider.get(id)!).expect(200);
      expect(await booking(row.id)).toMatchObject({
        paymentId: id,
        paymentState: 'PAID',
        status: 'CONFIRMED',
      });
    });
    it('historical money is reviewed, never reconstructed or dispatched from an old Float amount', async () => {
      const row = await seed({ historical: true });
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentReviewReason).toBe(
        'historical_payment_snapshot_missing',
      );
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id },
        }),
      ).toBe(0);
    });
    it('owner review is tenant-bound/read-only and excludes guest/payment credentials; Platform can assist', async () => {
      const row = await seed({ expired: true });
      await pay(row).expect(200);
      const path = `/customer/venues/${row.venueId}/website-payment-reviews`;
      const response = await http()
        .get(path)
        .set('Authorization', `Bearer ${row.f.ownerToken}`)
        .expect(200);
      const text = JSON.stringify(response.body);
      expect(text).toContain(row.id);
      for (const value of [
        'Synthetic private guest',
        'fixture-private-phone',
        'encryptedConfig',
        'clientSecret',
        '"snapshot"',
        'signedReceipt',
      ])
        expect(text).not.toContain(value);
      await http()
        .get(path)
        .set('Authorization', `Bearer ${fixtures[2].ownerToken}`)
        .expect(404);
      await http().get(path).expect(401);
      await http()
        .post(path)
        .set('Authorization', `Bearer ${row.f.ownerToken}`)
        .expect(404);
      await http()
        .get(`/platform/venues/${row.venueId}/website-payment-reviews`)
        .set('Authorization', `Bearer ${admin}`)
        .expect(200);
      await http()
        .get(`/platform/venues/${row.venueId}/website-payment-reviews`)
        .set('Authorization', `Bearer ${row.f.ownerToken}`)
        .expect(401);
    });
    it('anonymous receipt return exposes only REVIEW, no private booking fields', async () => {
      const row = await seed({ expired: true });
      await pay(row).expect(200);
      const response = await http()
        .get(`/api/bog/check-status/${row.paymentId}`)
        .set('Host', row.f.host)
        .expect(200);
      expect(response.body as { success: boolean; status: string }).toEqual({
        success: true,
        status: 'REVIEW',
      });
      await http()
        .get(`/api/bog/check-status/${row.paymentId}`)
        .set('Host', fixtures[2].host)
        .expect(404);
    });
    it('the bank TTL and frozen website window are both ten minutes', async () => {
      await create().expect(201);
      const request = createdRequests.at(-1)!;
      const row = await booking(request.bookingId);
      expect(request.ttl).toBe(10);
      expect(
        row.holdExpiresAt!.getTime() - row.paymentWindowStartedAt!.getTime(),
      ).toBe(600_000);
      const deadline = row.holdExpiresAt;
      provider.set(row.paymentId!, receipt(row.paymentId!, row.id));
      await callback(
        row.id,
        row.paymentId!,
        provider.get(row.paymentId!)!,
      ).expect(200);
      expect((await booking(row.id)).holdExpiresAt).toEqual(deadline);
    });
    it('signed timely proof survives receipt outage and a new reconciler after expiry', async () => {
      const row = await seed({ expired: true });
      failReads = true;
      await pay(row, new Date(row.expiresAt.getTime() - 30_000)).expect(200);
      expect(await booking(row.id)).toMatchObject({
        status: 'FAILED',
        paymentReviewReason: 'provider_receipt_unavailable',
        paymentTimelyProofAt: new Date(row.expiresAt.getTime() - 30_000),
      });
      failReads = false;
      await db.websiteReservation.update({
        where: { id: row.id },
        data: { nextPaymentCheckAt: new Date(0) },
      });
      await new ReservationService(
        db,
        bog,
        bridge,
      ).reconcileOutstandingPayments();
      expect(await booking(row.id)).toMatchObject({
        status: 'CONFIRMED',
        paymentState: 'PAID',
        paymentReviewReason: null,
      });
    });
    it('a future provider create clock does not prove a genuinely late payment', async () => {
      const row = await seed({ expired: true });
      provider.set(
        row.paymentId,
        receipt(row.paymentId, row.id, 'completed', '11.00', '0.00', {
          created: new Date(Date.now() + 600_000),
          expires: new Date(Date.now() + 1200_000),
        }),
      );
      await pay(row).expect(200);
      expect((await booking(row.id)).paymentReviewReason).toBe(
        'payment_timing_unproven',
      );
    });
    async function fault(
      table: 'WebsiteReservationDayHold' | 'WebsitePaymentObservation',
      work: () => Promise<void>,
    ) {
      await db.$executeRawUnsafe(
        "CREATE FUNCTION pos.web0104_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Synthetic WEB0104 failure'; END $$",
      );
      await db.$executeRawUnsafe(
        `CREATE TRIGGER web0104_fault BEFORE INSERT ON pos."${table}" FOR EACH ROW EXECUTE FUNCTION pos.web0104_fault()`,
      );
      try {
        await work();
      } finally {
        await db.$executeRawUnsafe(
          `DROP TRIGGER web0104_fault ON pos."${table}"`,
        );
        await db.$executeRawUnsafe('DROP FUNCTION pos.web0104_fault()');
      }
    }
    it('hold insertion failure rolls back the booking and makes no bank order', async () => {
      const before = await db.websiteReservation.count({
          where: { venueId: f0().venueId },
        }),
        orders = createdRequests.length;
      await fault('WebsiteReservationDayHold', async () => {
        await create().expect(500);
      });
      expect(
        await db.websiteReservation.count({ where: { venueId: f0().venueId } }),
      ).toBe(before);
      expect(createdRequests).toHaveLength(orders);
    });
    it('observation failure rolls back money, hold confirmation and intent; retry commits once', async () => {
      const row = await seed(),
        sent = new Date();
      await fault('WebsitePaymentObservation', async () => {
        await pay(row, sent).expect(500);
      });
      expect(await booking(row.id)).toMatchObject({
        status: 'PENDING',
        paymentState: 'PENDING',
        holdState: 'HELD',
        paymentGrossMinor: null,
      });
      expect(await observations(row.id)).toHaveLength(0);
      expect(
        await db.websiteReservationDeliveryIntent.count({
          where: { reservationId: row.id },
        }),
      ).toBe(0);
      await pay(row, sent).expect(200);
      expect(await observations(row.id)).toHaveLength(1);
      expect((await booking(row.id)).status).toBe('CONFIRMED');
    });
    it('settlement and owner review survive disabled website/payment access and original merchant revision', async () => {
      const row = await seed();
      await db.paymentIntegration.update({
        where: { id: row.f.integrationId },
        data: { enabled: false },
      });
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'ONLINE_PAYMENTS' },
      });
      await db.venueFeatureOverride.update({
        where: {
          venueId_featureId: { venueId: row.venueId, featureId: feature.id },
        },
        data: { effect: 'DISABLED' },
      });
      try {
        await pay(row).expect(200);
        expect((await booking(row.id)).status).toBe('CONFIRMED');
        const exception = await seed({ expired: true });
        await pay(exception).expect(200);
        const page = await http()
          .get(`/customer/venues/${row.venueId}/website-payment-reviews`)
          .set('Authorization', `Bearer ${row.f.ownerToken}`)
          .expect(200);
        expect(JSON.stringify(page.body)).toContain(exception.id);
        expect(
          (page.body as { financialDecisionOwner: string })
            .financialDecisionOwner,
        ).toBe('RESTAURANT_OWNER');
      } finally {
        await db.venueFeatureOverride.update({
          where: {
            venueId_featureId: { venueId: row.venueId, featureId: feature.id },
          },
          data: { effect: 'ENABLED' },
        });
        await db.paymentIntegration.update({
          where: { id: row.f.integrationId },
          data: { enabled: true },
        });
      }
    });
    it('the frozen whole-day identity drives review and POS delivery independently of stored UTC timestamp', async () => {
      const row = await seed({
        date: '2030-02-05',
        storedDate: new Date('2030-02-04T20:00:00Z'),
      });
      await pay(row).expect(200);
      const command = await db.edgeCommand.findFirstOrThrow({
        where: {
          venueId: row.venueId,
          idempotencyKey: `RESERVATION_CREATE:website:${row.id}`,
        },
      });
      expect(command.payload).toMatchObject({ reservationDate: '2030-02-05' });
      const late = await seed({
        date: '2030-02-06',
        storedDate: new Date('2030-02-05T20:00:00Z'),
        expired: true,
      });
      await pay(late).expect(200);
      const response = await http()
        .get(`/customer/venues/${row.venueId}/website-payment-reviews`)
        .set('Authorization', `Bearer ${row.f.ownerToken}`)
        .expect(200);
      expect(
        (
          response.body as { items: Array<{ bookingId: string; date: string }> }
        ).items.find((item) => item.bookingId === late.id)?.date,
      ).toBe('2030-02-06');
    });
    it('a pending callback that pins identity before a conflicting create reply cannot release another bank-bound hold', async () => {
      beforeCreateReply = async (bookingId, paymentId) => {
        await callback(bookingId, paymentId, provider.get(paymentId)!).expect(
          200,
        );
      };
      replacementCreateId = 'synthetic-conflicting-reply';
      await create().expect(400);
      const id = createdRequests.at(-1)!.bookingId;
      expect(await booking(id)).toMatchObject({
        paymentId: `synthetic-bank-${id}`,
        status: 'PENDING',
        holdState: 'HELD',
        paymentState: 'PENDING',
      });
      expect(
        await db.websiteReservationDayHold.findFirstOrThrow({
          where: { reservationId: id },
        }),
      ).toMatchObject({ status: 'HELD' });
    });
    it('snapshot/hold identities and composite tenant bindings are enforced by PostgreSQL', async () => {
      const row = await seed();
      await expect(
        db.websiteReservation.update({
          where: { id: row.id },
          data: { paymentExpectedMinor: '1' },
        }),
      ).rejects.toThrow();
      await expect(
        db.websiteReservation.update({
          where: { id: row.id },
          data: { paymentId: 'foreign' },
        }),
      ).rejects.toThrow();
      const hold = await db.websiteReservationDayHold.findFirstOrThrow({
        where: { reservationId: row.id },
      });
      await expect(
        db.websiteReservationDayHold.update({
          where: { id: hold.id },
          data: { tableCode: 2 },
        }),
      ).rejects.toThrow();
      await expect(
        db.websiteReservationDayHold.create({
          data: {
            venueId: fixtures[2].venueId,
            reservationId: row.id,
            serviceDate: freshDate(),
            tableCode: 1,
          },
        }),
      ).rejects.toThrow();
    });
  },
);
