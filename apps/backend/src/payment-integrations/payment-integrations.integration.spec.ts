import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
jest.mock('axios');
import axios from 'axios';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { PaymentIntegrationsService } from './payment-integrations.service';
import { decryptPaymentConfig } from './payment-config.crypto';
import { CustomerPaymentsController } from '../customer/customer-payments.controller';
import { CustomerService } from '../customer/customer.service';
import { CustomerAuth } from '../customer/customer-auth';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { BogController } from '../website/payment/payment.controller';
import { BogService } from '../website/payment/payment.service';
import { ReservationService } from '../website/reservation/reservation.service';
import { MenuService } from '../website/menu/menu.service';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';
const url = process.env.W1_TEST_DATABASE_URL;
(url ? describe : describe.skip)('W1 disposable PostgreSQL / HTTP', () => {
  let db: PrismaService,
    integrations: PaymentIntegrationsService,
    bog: BogService,
    app: any;
  const venues: any[] = [],
    owners: any[] = [],
    configs: any[] = [];
  const bridge = {
    areWebsiteTablesAvailable: jest.fn().mockResolvedValue(true),
    pushConfirmedReservationToPos: jest.fn(),
  };
  const tag = randomUUID();
  let reservationId: string, orderId: string, revisionId: string;
  const http = () => request(app.getHttpServer());
  const path = (i: number) => `/customer/venues/${venues[i].id}/payments/bog`;
  const auth = (i: number) => ({ Authorization: `Bearer ${owners[i].token}` });
  const create = (i: number) =>
    http()
      .post('/api/bog/create-order')
      .set('Host', new URL(configs[i].returnOrigin).hostname)
      .send({
        venueId: venues[1 - i].id,
        selectedTables: ['table1'],
        selectedDate: '2026-10-01',
        selectedTime: '18:00',
      });
  beforeAll(async () => {
    const u = new URL(url!);
    if (
      u.hostname !== '127.0.0.1' ||
      !(
        (u.port === '55439' && u.pathname === '/vynic_w1_disposable') ||
        (u.port === '55437' && u.pathname === '/vynic_commercial_test')
      )
    )
      throw Error('Only isolated W1 database permitted');
    process.env.PAYMENT_INTEGRATION_MASTER_KEY = '12'.repeat(32);
    process.env.JWT_SECRET = 'w1-test-key';
    db = new PrismaService({ datasourceUrl: url });
    const entitlements = new VenueEntitlementsService(db),
      jwt = new JwtService();
    integrations = new PaymentIntegrationsService(db, entitlements);
    bog = new BogService(new MenuService(db), integrations, db);
    for (const suffix of ['a', 'b']) {
      const org = await db.organization.create({
        data: { name: `W1 ${suffix}` },
      });
      const venue = await db.venue.create({
        data: {
          legacyCommercialAccess: true,
          organizationId: org.id,
          name: `W1 ${suffix}`,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          websiteConfig: { create: { mode: 'CUSTOM' } },
          domains: { create: { hostname: `w1-${suffix}-${tag}.localhost` } },
        },
      });
      venues.push(venue);
      const owner = await db.customerAccount.create({
        data: {
          organizationId: org.id,
          memberships: { create: { organizationId: org.id, role: 'OWNER' } },
          email: `${suffix}-${tag}@test.invalid`,
          passwordHash: 'unused',
          displayName: 'Test Owner',
        },
      });
      owners.push({
        ...owner,
        token: await jwt.signAsync(
          { sub: owner.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        ),
      });
      configs.push({
        clientId: `client-${suffix}-${tag}`,
        clientSecret: `secret-${suffix}-${tag}`,
        returnOrigin: `http://w1-${suffix}-${tag}.localhost:5173`,
      });
      await db.websiteTable.create({
        data: {
          venueId: venue.id,
          websiteTableNumber: 'table1',
          posTableNumber: '1',
          posFloor: '1',
        },
      });
      const f = await db.feature.findUniqueOrThrow({
        where: { key: 'WEBSITE' },
      });
      await db.venueFeatureOverride.create({
        data: { venueId: venue.id, featureId: f.id, effect: 'ENABLED' },
      });
    }
    const mod = await Test.createTestingModule({
      controllers: [CustomerPaymentsController, BogController],
      providers: [
        { provide: PrismaService, useValue: db },
        { provide: PaymentIntegrationsService, useValue: integrations },
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
        { provide: VenueEntitlementsService, useValue: entitlements },
        { provide: BogService, useValue: bog },
        {
          provide: ReservationService,
          useValue: new ReservationService(db, bog, bridge as never),
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
    app = mod.createNestApplication({ rawBody: true });
    await app.init();
    (axios.post as jest.Mock).mockImplementation(
      async (url: string, body: any) =>
        url.includes('openid-connect')
          ? { data: { access_token: 'test-token' } }
          : {
              data: {
                id: `bank-${body.external_order_id}`,
                _links: { redirect: { href: 'https://payment.test/checkout' } },
              },
            },
    );
  });
  afterAll(async () => {
    await app?.close();
    await db?.$disconnect();
  });
  it('denies other owners and encrypts credentials; APIs and audit contain no secrets', async () => {
    await http().get(path(0)).expect(401);
    await http().get(path(0)).set(auth(1)).expect(404);
    await http().put(path(0)).set(auth(1)).send(configs[1]).expect(404);
    await http()
      .post(`${path(0)}/disable`)
      .set(auth(1))
      .send({})
      .expect(404);
    for (const venue of venues)
      await db.venueFeatureOverride.create({
        data: {
          venueId: venue.id,
          featureId: (
            await db.feature.findUniqueOrThrow({
              where: { key: 'ONLINE_PAYMENTS' },
            })
          ).id,
          effect: 'ENABLED',
        },
      });
    for (let i = 0; i < 2; i++) {
      const res = await http()
        .put(path(i))
        .set(auth(i))
        .send(configs[i])
        .expect(200);
      expect(res.body.configured).toBe(true);
      expect(JSON.stringify(res.body)).not.toContain(configs[i].clientSecret);
      expect(JSON.stringify(res.body)).not.toContain(configs[i].clientId);
      const row = await db.paymentIntegration.findFirstOrThrow({
        where: { venueId: venues[i].id },
      });
      expect(row.encryptedConfig).not.toContain(configs[i].clientSecret);
      expect(() =>
        decryptPaymentConfig(venues[1 - i].id, row.id, row.encryptedConfig),
      ).toThrow();
      await expect(
        integrations.credentials(venues[1 - i].id, row.id),
      ).rejects.toThrow();
      expect(
        await db.customerAuditEvent.count({
          where: {
            targetId: venues[i].id,
            action: 'payment_integration.updated',
          },
        }),
      ).toBe(1);
    }
  });
  it('requires entitlement; CUSTOM Host selects credentials ignoring body venue', async () => {
    await db.venueFeatureOverride.deleteMany({
      where: {
        venueId: { in: venues.map((v) => v.id) },
        feature: { key: 'ONLINE_PAYMENTS' },
      },
    });
    await http().put(path(0)).set(auth(0)).send(configs[0]).expect(403);
    await create(0).expect(403);
    expect(
      await db.websiteReservation.count({ where: { venueId: venues[0].id } }),
    ).toBe(0);
    const f = await db.feature.findUniqueOrThrow({
      where: { key: 'ONLINE_PAYMENTS' },
    });
    for (const venue of venues)
      await db.venueFeatureOverride.create({
        data: { venueId: venue.id, featureId: f.id, effect: 'ENABLED' },
      });
    const result = await create(0).expect(201);
    reservationId = result.body.reservation_id;
    const row = await db.websiteReservation.findUniqueOrThrow({
      where: { id: reservationId },
    });
    expect(row.venueId).toBe(venues[0].id);
    revisionId = row.paymentIntegrationId!;
    orderId = row.paymentId!;
    const calls = (axios.post as jest.Mock).mock.calls;
    expect(
      calls.find((c) => c[0].includes('openid-connect'))[2].headers
        .Authorization,
    ).toBe(
      `Basic ${Buffer.from(`${configs[0].clientId}:${configs[0].clientSecret}`).toString('base64')}`,
    );
    expect(
      calls.find((c) => c[0].includes('ecommerce'))[1].redirect_urls.success,
    ).toContain(configs[0].returnOrigin);
    await http()
      .post('/api/bog/create-order')
      .set('Host', 'unknown.invalid')
      .send({})
      .expect(404);
  });
  it('rotation/disconnect audited, new payments denied; status retains original credentials', async () => {
    await http()
      .put(path(0))
      .set(auth(0))
      .send({ ...configs[0], clientSecret: 'rotated-secret' })
      .expect(200);
    await http()
      .post(`${path(0)}/disable`)
      .set(auth(0))
      .send({})
      .expect(201);
    await create(0).expect(403);
    await db.venueFeatureOverride.updateMany({
      where: { venueId: venues[0].id, feature: { key: 'ONLINE_PAYMENTS' } },
      data: { effect: 'DISABLED' },
    });
    (axios.get as jest.Mock).mockResolvedValue({
      data: { external_order_id: reservationId, status: 'completed' },
    });
    (axios.post as jest.Mock).mockClear();
    await http()
      .get(`/api/bog/check-status/${orderId}`)
      .set('Host', new URL(configs[0].returnOrigin).hostname)
      .expect(200);
    expect(
      (axios.post as jest.Mock).mock.calls[0][2].headers.Authorization,
    ).toBe(
      `Basic ${Buffer.from(`${configs[0].clientId}:${configs[0].clientSecret}`).toString('base64')}`,
    );
    (axios.post as jest.Mock).mockClear();
    await http()
      .get(`/api/bog/check-status/${orderId}`)
      .set('Host', new URL(configs[1].returnOrigin).hostname)
      .expect(404);
    expect(axios.post).not.toHaveBeenCalled();
    const events = await db.customerAuditEvent.findMany({
      where: { targetId: venues[0].id },
    });
    expect(events.map((e) => e.action)).toContain(
      'payment_integration.disabled',
    );
    expect(JSON.stringify(events)).not.toContain('rotated-secret');
    expect(JSON.stringify(events)).not.toContain(configs[0].clientSecret);
  });
  it('callback ignores Host, rejects invalid signature and mismatched stored payment reference', async () => {
    const body = {
      event: 'order_payment',
      body: {
        external_order_id: reservationId,
        order_id: orderId,
        order_status: { key: 'completed' },
      },
    };
    await http().post('/api/bog/payment-callback').send(body).expect(401);
    // Only provider signature verification is stubbed: bank private key unavailable.
    const signature = jest
      .spyOn(bog, 'verifyCallbackSignature')
      .mockReturnValue(true);
    await http()
      .post('/api/bog/payment-callback')
      .set('Host', new URL(configs[1].returnOrigin).hostname)
      .set('callback-signature', 'test')
      .send(body)
      .expect(201);
    expect(
      bridge.pushConfirmedReservationToPos.mock.calls.at(-1)[0].venueId,
    ).toBe(venues[0].id);
    await http()
      .post('/api/bog/payment-callback')
      .set('callback-signature', 'test')
      .send({ ...body, body: { ...body.body, order_id: 'wrong' } })
      .expect(400);
    signature.mockRestore();
  });
  it('sanitizes provider failures including axios credential-bearing errors', async () => {
    (axios.post as jest.Mock).mockRejectedValueOnce(
      new Error(configs[0].clientSecret),
    );
    await expect(bog.getAccessToken(venues[0].id, revisionId)).rejects.toThrow(
      'Payment provider authentication failed',
    );
  });
  it('enforces composite tenancy in PostgreSQL and rolls back a failed audit', async () => {
    await expect(
      db.websiteReservation.create({
        data: {
          venueId: venues[1].id,
          paymentIntegrationId: revisionId,
          date: new Date(),
          timeSlot: '18:00',
        },
      }),
    ).rejects.toThrow();
    const count = await db.paymentIntegration.count({
      where: { venueId: venues[1].id },
    });
    await expect(
      integrations.save(venues[1].id, configs[1], {
        customerAccountId: randomUUID(),
      }),
    ).rejects.toThrow();
    expect(
      await db.paymentIntegration.count({ where: { venueId: venues[1].id } }),
    ).toBe(count);
    expect((await integrations.status(venues[1].id)).configured).toBe(true);
  });
  it('provider HTTP failures expose no credentials in response or logs', async () => {
    const logs = [
      jest.spyOn(console, 'error'),
      jest.spyOn(console, 'warn'),
      jest.spyOn(console, 'log'),
    ];
    try {
      (axios.post as jest.Mock).mockRejectedValueOnce({
        message: configs[1].clientSecret,
        config: { headers: { Authorization: configs[1].clientSecret } },
      });
      const response = await create(1).expect(502);
      expect(JSON.stringify(response.body)).not.toContain(
        configs[1].clientSecret,
      );
      for (const log of logs)
        expect(JSON.stringify(log.mock.calls)).not.toContain(
          configs[1].clientSecret,
        );
    } finally {
      logs.forEach((log) => log.mockRestore());
    }
  });
  it('explicit legacy CLI is idempotent, binds existing payments and grants no access', async () => {
    const org = await db.organization.create({ data: { name: 'Legacy' } });
    const v = await db.venue.create({
      data: {
        name: 'Legacy',
        organizationId: org.id,
        timezone: 'Asia/Tbilisi',
        currency: 'GEL',
        domains: { create: { hostname: `legacy-${tag}.localhost` } },
      },
    });
    const booking = await db.websiteReservation.create({
      data: {
        venueId: v.id,
        date: new Date(),
        timeSlot: '18:00',
        paymentId: `legacy-${tag}`,
      },
    });
    const env = {
      ...process.env,
      DATABASE_URL: url!,
      BOG_CLIENT_ID: 'legacy-client',
      BOG_CLIENT_SECRET: 'legacy-secret',
      BOG_RETURN_ORIGIN: `http://legacy-${tag}.localhost:5173`,
    };
    const args = [
      '-r',
      'ts-node/register/transpile-only',
      'scripts/import-bog-integration.ts',
      v.id,
      'test-operator',
      '--confirm-import',
    ];
    for (let i = 0; i < 2; i++) {
      const output = execFileSync(process.execPath, args, {
        env,
        encoding: 'utf8',
      });
      expect(output).toContain('import complete');
      expect(output).not.toContain('legacy-secret');
    }
    expect(
      await db.paymentIntegration.count({ where: { venueId: v.id } }),
    ).toBe(1);
    expect(await db.auditEventLog.count({ where: { venueId: v.id } })).toBe(1);
    expect(
      (
        await db.websiteReservation.findUniqueOrThrow({
          where: { id: booking.id },
        })
      ).paymentIntegrationId,
    ).toBeTruthy();
    expect(await integrations.status(v.id)).toMatchObject({ entitled: false });
    expect(() =>
      execFileSync(process.execPath, args, {
        env: { ...env, BOG_CLIENT_SECRET: 'changed' },
        stdio: 'pipe',
      }),
    ).toThrow();
  });
});
