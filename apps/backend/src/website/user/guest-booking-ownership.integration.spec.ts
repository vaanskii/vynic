import 'reflect-metadata';
jest.mock('axios');
jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
import axios from 'axios';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import type { WebsiteMode } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { encryptPaymentConfig } from '../../payment-integrations/payment-config.crypto';
import { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { WebsiteAuthController } from '../auth/auth.controller';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { WebsiteAuthService } from '../auth/auth.service';
import { CryptoService } from '../common/crypto.service';
import { CsrfService } from '../common/csrf.service';
import { emptyWebsiteContent } from '../core/website-content';
import { MenuService } from '../menu/menu.service';
import { BogController } from '../payment/payment.controller';
import { BogService } from '../payment/payment.service';
import { TableController } from '../reservation/reservation.controller';
import { ReservationService } from '../reservation/reservation.service';
import { WebsitePosReservationBridgeService } from '../reservation/website-pos-reservation-bridge.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { UserController } from './user.controller';
import { UserService } from './user.service';

const url = process.env.SEC02_TEST_DATABASE_URL;
const providerPost = jest.spyOn(axios, 'post');
const providerGet = jest.spyOn(axios, 'get');
type Session = { cookie: string; id: string; email: string };
type Fixture = { venueId: string; host: string; itemId: string };
type Created = { id: string; date: string; paymentId: string };

// The runner owns creation/migrations/cleanup. No default database, reset or drop.
(url ? describe : describe.skip)('SEC-02 real PostgreSQL / Nest HTTP', () => {
  let db: PrismaService;
  let app: INestApplication;
  let alice: Session;
  let bob: Session;
  let admin: Session;
  let guests: Created[];
  let historical: string;
  const fixtures: Fixture[] = [];
  const tag = randomUUID();
  const victimEmail = `victim-${tag}@example.invalid`;
  const password = 'SEC02-synthetic-password';
  const originalKey = process.env.PAYMENT_INTEGRATION_MASTER_KEY;
  const originalCookieKey = process.env.COOKIE_ENCRYPTION_KEY;
  const providerOrders = new Map<string, string>();
  const http = () => request(app.getHttpServer() as Server);
  let day = 0;

  const privateValues = [
    'SEC02 private guest name',
    'SEC02 private phone',
    'SEC02 private notes',
    victimEmail,
  ];
  const privateKeys = [
    'customerEmail',
    'notes',
    'menuItems',
    'paymentId',
    'paymentIntegrationId',
    'paymentStatus',
    'userId',
    'user',
    'customerInfo',
  ];

  function noPrivateData(body: unknown) {
    const serialized = JSON.stringify(body);
    for (const value of privateValues) expect(serialized).not.toContain(value);
    for (const key of privateKeys)
      expect(serialized).not.toContain(`"${key}":`);
  }

  async function session(
    i: number,
    email: string,
    signup = true,
  ): Promise<Session> {
    const host = fixtures[i].host;
    const csrf = await http()
      .get('/api/auth/csrf')
      .set('Host', host)
      .expect(200);
    const token = (csrf.body as { csrfToken: string }).csrfToken;
    const response = await http()
      .post(`/api/auth/${signup ? 'signup' : 'signin'}`)
      .set('Host', host)
      .set('Cookie', `csrf_token=${token}`)
      .set('X-CSRF-Token', token)
      .send(
        signup
          ? { phone: `sec02-${randomUUID()}`, email, password }
          : { identifier: email, password },
      )
      .expect(201);
    const cookies = response.headers['set-cookie'] as unknown as string[];
    expect(
      cookies.some(
        (cookie) =>
          cookie.startsWith('access_token=') && cookie.includes('HttpOnly'),
      ),
    ).toBe(true);
    const cookie = cookies.map((entry) => entry.split(';')[0]).join('; ');
    const verified = await http()
      .get('/api/auth/verify')
      .set('Host', host)
      .set('Cookie', cookie)
      .expect(200);
    const body = verified.body as {
      isAuthenticated: boolean;
      user: { id: string };
    };
    expect(body.isAuthenticated).toBe(true);
    return { cookie, id: body.user.id, email };
  }

  const mine = (i: number, user: Session, query = '') =>
    http()
      .get(`/api/user/reservations${query}`)
      .set('Host', fixtures[i].host)
      .set('Cookie', user.cookie);

  async function create(
    i: number,
    user?: Session,
    route = '/api/tables/reservations',
    extra: Record<string, unknown> = {},
  ): Promise<Created> {
    const date = new Date(Date.UTC(2032, 0, ++day)).toISOString().slice(0, 10);
    let call = http().post(route).set('Host', fixtures[i].host);
    if (user) call = call.set('Cookie', user.cookie);
    const result = await call
      .send({
        selectedTables: ['table1'],
        selectedDate: date,
        selectedTime: '18:00',
        menuItems: [{ id: fixtures[i].itemId, quantity: 1, price: 0.01 }],
        totalAmount: 1,
        customerEmail: victimEmail,
        customerName: privateValues[0],
        customerPhone: privateValues[1],
        notes: privateValues[2],
        ...extra,
      })
      .expect(201);
    const body = result.body as {
      reservation?: { id: string };
      reservation_id?: string;
    };
    const id = body.reservation?.id ?? body.reservation_id;
    expect(typeof id).toBe('string');
    const stored = await db.websiteReservation.findUniqueOrThrow({
      where: { id: id! },
    });
    expect(stored.venueId).toBe(fixtures[i].venueId);
    expect(stored.userId).toBe(user?.id ?? null);
    expect(stored.totalAmount).toBe(110);
    expect(stored.paymentId).toMatch(/^sec02-fake-provider-/);
    return { id: stored.id, date, paymentId: stored.paymentId! };
  }

  beforeAll(async () => {
    const parsed = new URL(url!);
    if (
      !isFreshDisposableDatabase(parsed) ||
      !/^\/disposable_sec02_[a-z0-9_]+$/.test(parsed.pathname)
    )
      throw new Error(
        'SEC-02 requires a freshly created verification-owned disposable_sec02_* database on 127.0.0.1',
      );
    process.env.PAYMENT_INTEGRATION_MASTER_KEY = '42'.repeat(32);
    process.env.COOKIE_ENCRYPTION_KEY = 'sec02-synthetic-cookie';
    db = new PrismaService({ datasourceUrl: url });
    await db.$connect();
    const features = await db.feature.findMany({
      where: { key: { in: ['WEBSITE', 'ONLINE_PAYMENTS'] } },
    });
    expect(features).toHaveLength(2);
    const plan = await db.plan.create({
      data: {
        key: `sec02-${tag}`,
        name: 'SEC02 synthetic',
        features: {
          create: features.map((feature) => ({ featureId: feature.id })),
        },
      },
    });
    for (const mode of ['CUSTOM', 'SAAS'] satisfies WebsiteMode[]) {
      const organization = await db.organization.create({
        data: { name: `SEC02 ${mode} ${tag}` },
      });
      const host = `sec02-${mode.toLowerCase()}-${tag}.localhost`;
      const venue = await db.venue.create({
        data: {
          organizationId: organization.id,
          name: `SEC02 ${mode}`,
          currency: 'GEL',
          timezone: 'Asia/Tbilisi',
          domains: { create: { hostname: host } },
          websiteConfig: {
            create:
              mode === 'CUSTOM'
                ? { mode }
                : {
                    mode,
                    status: 'PUBLISHED',
                    slug: `sec02-${tag}`,
                    revision: 1,
                    publishedRevision: 1,
                    publishedAt: new Date(),
                    published: { ...emptyWebsiteContent, slug: `sec02-${tag}` },
                  },
          },
          planAssignment: { create: { planId: plan.id } },
          subscription: { create: { status: 'ACTIVE' } },
        },
      });
      await db.websiteTable.create({
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
          nameEn: 'SEC02 private preorder',
          nameKa: 'Meal',
          price: 100,
        },
      });
      const integrationId = randomUUID();
      await db.paymentIntegration.create({
        data: {
          id: integrationId,
          venueId: venue.id,
          provider: 'BOG',
          revision: 1,
          encryptedConfig: encryptPaymentConfig(venue.id, integrationId, {
            clientId: `sec02-client-${mode}`,
            clientSecret: `sec02-secret-${mode}`,
            returnOrigin: `http://${host}`,
          }),
        },
      });
      fixtures.push({ venueId: venue.id, host, itemId: item.id });
    }
    const entitlements = new VenueEntitlementsService(db);
    const menu = new MenuService(db);
    const bog = new BogService(
      menu,
      new PaymentIntegrationsService(db, entitlements),
      db,
    );
    // Availability and public-map reads use the actual Cloud mirror and Prisma.
    // Dispatch itself is outside SEC-02; fail loudly if a test accidentally reaches it.
    const unexpectedDispatch = () => {
      throw new Error('SEC-02 must not dispatch operational commands');
    };
    const bridge = new WebsitePosReservationBridgeService(
      db,
      {} as never,
      menu,
      new PosReservationMirrorService(db),
      { dispatch: unexpectedDispatch } as never,
    );
    const crypto = new CryptoService();
    const auth = new WebsiteAuthService(
      db,
      new JwtService(),
      new ConfigService({
        JWT_SECRET: 'sec02-synthetic-access',
        JWT_REFRESH_SECRET: 'sec02-synthetic-refresh',
      }),
      crypto,
    );
    const module = await Test.createTestingModule({
      controllers: [
        WebsiteAuthController,
        UserController,
        TableController,
        BogController,
      ],
      providers: [
        { provide: PrismaService, useValue: db },
        { provide: WebsiteAuthService, useValue: auth },
        { provide: CryptoService, useValue: crypto },
        CsrfService,
        EnrollmentRateLimiter,
        { provide: UserService, useValue: new UserService(db) },
        { provide: BogService, useValue: bog },
        {
          provide: ReservationService,
          useValue: new ReservationService(db, bog, bridge),
        },
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
    app = module.createNestApplication({ rawBody: true });
    app.use(cookieParser());
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    expect(jest.isMockFunction(providerPost)).toBe(true);
    expect(jest.isMockFunction(providerGet)).toBe(true);
    providerPost.mockImplementation((target: string, body: unknown) => {
      if (target.includes('openid-connect'))
        return Promise.resolve({ data: { access_token: 'sec02-fake-token' } });
      const payload = body as {
        external_order_id: string;
        purchase_units: { total_amount: number; currency: string };
      };
      expect(payload.purchase_units).toMatchObject({
        total_amount: 110,
        currency: 'GEL',
      });
      const id = `sec02-fake-provider-${randomUUID()}`;
      providerOrders.set(id, payload.external_order_id);
      return Promise.resolve({
        data: {
          id,
          _links: { redirect: { href: 'https://bank.invalid/sec02' } },
        },
      });
    });
    providerGet.mockImplementation(async (target: string) => {
      const id = decodeURIComponent(target.split('/').at(-1)!);
      const reservationId = providerOrders.get(id);
      if (!reservationId) throw new Error('Unknown synthetic provider order');
      const booking = await db.websiteReservation.findUniqueOrThrow({
        where: { id: reservationId },
      });
      return Promise.resolve({
        data: {
          order_id: id,
          external_order_id: reservationId,
          order_status: { key: 'created' },
          capture: 'automatic',
          purchase_units: {
            currency_code: 'GEL',
            request_amount: (
              Number(booking.paymentExpectedMinor) / 100
            ).toFixed(2),
            transfer_amount: '0.00',
            refund_amount: '0.00',
          },
        },
      });
    });
    alice = await session(0, `alice-${tag}@example.invalid`);
    bob = await session(1, `bob-${tag}@example.invalid`);
    admin = await session(0, `admin-${tag}@example.invalid`);
    await db.websiteUser.update({
      where: { id: admin.id },
      data: { role: 'SUPER_ADMIN', adminVenueId: fixtures[0].venueId },
    });
    guests = [
      await create(0),
      await create(1, undefined, '/api/bog/create-order'),
    ];
    // Publication of paid/historical fixtures is explicit seed state, not a bank charge.
    await db.websiteReservation.updateMany({
      where: { id: { in: guests.map((g) => g.id) } },
      data: { status: 'CONFIRMED' },
    });
    const old = await db.websiteReservation.create({
      data: {
        venueId: fixtures[0].venueId,
        userId: alice.id,
        date: new Date('2025-01-01'),
        timeSlot: '18:00',
        status: 'COMPLETED',
        customerEmail: 'historical-different@example.invalid',
        notes: 'Historical owned booking',
      },
    });
    historical = old.id;
  });

  afterAll(async () => {
    await app?.close();
    await db?.$disconnect();
    if (originalKey === undefined)
      delete process.env.PAYMENT_INTEGRATION_MASTER_KEY;
    else process.env.PAYMENT_INTEGRATION_MASTER_KEY = originalKey;
    if (originalCookieKey === undefined)
      delete process.env.COOKIE_ENCRYPTION_KEY;
    else process.env.COOKIE_ENCRYPTION_KEY = originalCookieKey;
  });

  it('unverified victim-email signup returns zero guest bookings and zero private fields at either Venue', async () => {
    const before = await db.websiteReservation.findMany({
      where: { id: { in: guests.map((g) => g.id) } },
      orderBy: { id: 'asc' },
    });
    const attacker = await session(0, victimEmail);
    const sameAccountOnB = await session(1, victimEmail, false);
    expect(sameAccountOnB.id).toBe(attacker.id);
    for (const [i, account] of [
      [0, attacker],
      [1, sameAccountOnB],
    ] as const) {
      const response = await mine(i, account).expect(200);
      expect(response.body).toEqual([]);
      noPrivateData(response.body);
    }
    expect(
      await db.websiteReservation.findMany({
        where: { id: { in: guests.map((g) => g.id) } },
        orderBy: { id: 'asc' },
      }),
    ).toEqual(before);
  });

  describe.each([0, 1])('Venue %i (CUSTOM / SAAS)', (i) => {
    it.each(['/api/tables/reservations', '/api/bog/create-order'])(
      '%s binds only the session user and Host; owner alone sees the confirmed booking',
      async (route) => {
        const booking = await create(i, alice, route, {
          userId: bob.id,
          venueId: fixtures[1 - i].venueId,
        });
        await db.websiteReservation.update({
          where: { id: booking.id },
          data: { status: 'CONFIRMED' },
        });
        const owner = await mine(i, alice).expect(200);
        expect(
          (owner.body as Array<{ id: string }>).map((row) => row.id),
        ).toContain(booking.id);
        const other = await mine(i, bob).expect(200);
        expect(other.body).toEqual([]);
        noPrivateData(other.body);
        const foreign = await mine(1 - i, alice).expect(200);
        expect(
          (foreign.body as Array<{ id: string }>).map((row) => row.id),
        ).not.toContain(booking.id);
      },
    );

    it.each(['/api/tables/reservations', '/api/bog/create-order'])(
      '%s keeps anonymous creation operational and discards forged body ownership',
      async (route) => {
        const booking = await create(i, undefined, route, {
          userId: bob.id,
          venueId: fixtures[1 - i].venueId,
        });
        const stored = await db.websiteReservation.findUniqueOrThrow({
          where: { id: booking.id },
        });
        expect(stored).toMatchObject({
          userId: null,
          venueId: fixtures[i].venueId,
          status: 'PENDING',
          notes: privateValues[2],
        });
        const availability = await http()
          .get(
            `/api/tables/availability/table1?date=${booking.date}&timeSlot=18:00`,
          )
          .set('Host', fixtures[i].host)
          .expect(200);
        expect(availability.body).toMatchObject({ isAvailable: false });
      },
    );

    it('ignores forged query identities and reservation ID; no guest claim endpoint exists', async () => {
      const response = await mine(
        i,
        bob,
        `?venueId=${fixtures[1 - i].venueId}&userId=${alice.id}&customerEmail=${victimEmail}&reservationId=${guests[0].id}`,
      ).expect(200);
      expect(response.body).toEqual([]);
      for (const id of [guests[0].id, guests[1].id, historical]) {
        await http()
          .get(`/api/user/reservations/${id}`)
          .set('Host', fixtures[i].host)
          .set('Cookie', bob.cookie)
          .expect(404);
      }
    });

    it('anonymous and ordinary-user maps keep the public occupancy projection without private data', async () => {
      for (const cookie of ['', alice.cookie, bob.cookie]) {
        const response = await http()
          .get(`/api/tables/reservations?date=${guests[i].date}`)
          .set('Host', fixtures[i].host)
          .set('Cookie', cookie)
          .expect(200);
        const rows = response.body as Array<Record<string, unknown>>;
        expect(rows).toHaveLength(1);
        expect(rows[0]).toMatchObject({
          id: guests[i].id,
          customerName: null,
          customerPhone: null,
        });
        noPrivateData(rows);
      }
    });

    it('denies anonymous, tampered and unrelated principal cookies on my reservations', async () => {
      for (const cookie of [
        '',
        'access_token=forged',
        'customer_access_token=forged',
        'platform_access_token=forged',
      ]) {
        const response = await http()
          .get('/api/user/reservations')
          .set('Host', fixtures[i].host)
          .set('Cookie', cookie)
          .expect(401);
        noPrivateData(response.body);
      }
    });

    it('rechecks the live WebsiteUser and rejects a valid cookie after that identity is removed', async () => {
      const removed = await session(i, `removed-${i}-${tag}@example.invalid`);
      await db.websiteUser.delete({ where: { id: removed.id } });
      await mine(i, removed).expect(401);
    });
  });

  it('returns the paid menu snapshot even after the catalog name and price differ', async () => {
    const item = await db.menuItem.create({
      data: {
        venueId: fixtures[0].venueId,
        nameEn: 'Current name',
        nameKa: 'Current name ka',
        price: 99,
      },
    });
    const frozen = [
      {
        id: item.id,
        variantId: 'paid-large',
        name: 'Paid drink 1L',
        price: 12.5,
        quantity: 2,
      },
    ];
    const booking = await db.websiteReservation.create({
      data: {
        venueId: fixtures[0].venueId,
        userId: alice.id,
        date: new Date('2025-01-02'),
        timeSlot: '18:00',
        status: 'COMPLETED',
        menuItems: JSON.stringify(frozen),
      },
    });
    const response = await mine(0, alice).expect(200);
    expect(
      response.body.find((row: { id: string }) => row.id === booking.id),
    ).toMatchObject({ menuItems: frozen });
  });

  it('preserves historical authenticated ownership and does not require matching contact email', async () => {
    const response = await mine(0, alice).expect(200);
    expect(response.body).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: historical,
          notes: 'Historical owned booking',
          customerEmail: 'historical-different@example.invalid',
        }),
      ]),
    );
    expect((await mine(0, bob).expect(200)).body).toEqual([]);
    expect((await mine(1, alice).expect(200)).body).not.toEqual(
      expect.arrayContaining([expect.objectContaining({ id: historical })]),
    );
  });

  it('limits the restaurant administrator to its explicit adminVenueId', async () => {
    const own = await http()
      .get(`/api/tables/reservations?date=${guests[0].date}`)
      .set('Host', fixtures[0].host)
      .set('Cookie', admin.cookie)
      .expect(200);
    expect(own.body).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: guests[0].id,
          customerName: privateValues[0],
          customerPhone: privateValues[1],
        }),
      ]),
    );
    const foreign = await http()
      .get(
        `/api/tables/reservations?date=${guests[1].date}&venueId=${fixtures[0].venueId}`,
      )
      .set('Host', fixtures[1].host)
      .set('Cookie', admin.cookie)
      .expect(200);
    noPrivateData(foreign.body);
    await db.websiteUser.update({
      where: { id: admin.id },
      data: { adminVenueId: null },
    });
    try {
      const unbound = await http()
        .get(`/api/tables/reservations?date=${guests[0].date}`)
        .set('Host', fixtures[0].host)
        .set('Cookie', admin.cookie)
        .expect(200);
      noPrivateData(unbound.body);
    } finally {
      await db.websiteUser.update({
        where: { id: admin.id },
        data: { adminVenueId: fixtures[0].venueId },
      });
    }
  });

  it.each(['unknown', 'disabled-host', 'disabled-venue'])(
    'fails closed for %s despite forged browser Venue identity',
    async (kind) => {
      const host =
        kind === 'unknown' ? 'sec02-unknown.invalid' : fixtures[0].host;
      if (kind === 'disabled-host')
        await db.venueDomain.update({
          where: { hostname: host },
          data: { status: 'DISABLED' },
        });
      if (kind === 'disabled-venue')
        await db.venue.update({
          where: { id: fixtures[0].venueId },
          data: { status: 'DISABLED' },
        });
      try {
        const response = await http()
          .get(`/api/user/reservations?venueId=${fixtures[0].venueId}`)
          .set('Host', host)
          .set('Cookie', alice.cookie)
          .expect(404);
        noPrivateData(response.body);
      } finally {
        if (kind === 'disabled-host')
          await db.venueDomain.update({
            where: { hostname: host },
            data: { status: 'ACTIVE' },
          });
        if (kind === 'disabled-venue')
          await db.venue.update({
            where: { id: fixtures[0].venueId },
            data: { status: 'ACTIVE' },
          });
      }
    },
  );

  it('keeps commercial and CUSTOMER_ACCOUNTS guards authoritative on ownership reads', async () => {
    await db.venueWebsiteCapability.create({
      data: {
        venueId: fixtures[0].venueId,
        capability: 'CUSTOMER_ACCOUNTS',
        enabled: false,
      },
    });
    try {
      await mine(0, alice).expect(404);
    } finally {
      await db.venueWebsiteCapability.delete({
        where: {
          venueId_capability: {
            venueId: fixtures[0].venueId,
            capability: 'CUSTOMER_ACCOUNTS',
          },
        },
      });
    }
    await db.venueSubscription.update({
      where: { venueId: fixtures[0].venueId },
      data: { status: 'SUSPENDED' },
    });
    try {
      expect([403, 404]).toContain((await mine(0, alice)).status);
    } finally {
      await db.venueSubscription.update({
        where: { venueId: fixtures[0].venueId },
        data: { status: 'ACTIVE' },
      });
    }
  });

  it.each([0, 1])(
    'payment status for Venue %i never grants private booking access from an identifier',
    async (i) => {
      const booking = await create(i);
      for (const route of [
        `/api/bog/check-status/${booking.paymentId}`,
        `/api/bog/check-reservation-status/${booking.id}`,
      ]) {
        for (const cookie of ['', alice.cookie, bob.cookie]) {
          const response = await http()
            .get(route)
            .set('Host', fixtures[i].host)
            .set('Cookie', cookie)
            .expect(200);
          expect(response.body).toEqual({ success: true, status: 'PENDING' });
          noPrivateData(response.body);
        }
      }
      const before = await db.websiteReservation.findUniqueOrThrow({
        where: { id: booking.id },
      });
      providerGet.mockClear();
      await http()
        .get(`/api/bog/check-status/${booking.paymentId}`)
        .set('Host', fixtures[1 - i].host)
        .expect(404);
      const foreign = await http()
        .get(
          `/api/bog/check-reservation-status/${booking.id}?venueId=${fixtures[i].venueId}`,
        )
        .set('Host', fixtures[1 - i].host)
        .expect(200);
      expect(foreign.body).toEqual({
        success: false,
        message: 'Payment ID not found for this reservation',
      });
      expect(providerGet).not.toHaveBeenCalled();
      noPrivateData(foreign.body);
      expect(
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: booking.id },
        }),
      ).toEqual(before);
    },
  );
});
