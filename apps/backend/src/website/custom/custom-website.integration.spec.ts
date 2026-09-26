import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
jest.mock('axios');
import axios from 'axios';
import * as argon from 'argon2';
import { randomUUID } from 'node:crypto';
import * as nodeHttp from 'node:http';
import type { AddressInfo } from 'node:net';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import { PlatformAuditService } from '../../platform/platform-audit.service';
import { PlatformAuthGuard } from '../../platform/platform-auth.guard';
import { PlatformAuthService } from '../../platform/platform-auth.service';
import { PlatformCustomWebsiteController } from '../../platform/platform-custom-website.controller';
import { PlatformDeviceService } from '../../platform/platform-device.service';
import { PlatformDirectoryService } from '../../platform/platform-directory.service';
import { PlatformVenueConfigService } from '../../platform/platform-venue-config.service';
import { PlatformVenuesController } from '../../platform/platform-venues.controller';
import { CustomerAuth } from '../../customer/customer-auth';
import { CustomerService } from '../../customer/customer.service';
import { CustomerWebsiteController } from '../../customer/customer-website.controller';
import { CustomerCatalogController } from '../../customer/restaurant-foundation.controller';
import { RestaurantFoundationService } from '../../customer/restaurant-foundation.service';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { WebsiteAuthService } from '../auth/auth.service';
import { CryptoService } from '../common/crypto.service';
import { HostnameRequestsService } from '../core/hostname-requests';
import { WebsiteCoreController } from '../core/website-core.controller';
import { WebsiteCoreService } from '../core/website-core.service';
import { WebsiteLogoService } from '../core/website-logo.service';
import { WebsiteMenuService } from '../core/website-menu.service';
import { WebsitePreviewTokens } from '../core/website-preview';
import { MenuController } from '../menu/menu.controller';
import { MenuService } from '../menu/menu.service';
import { BogController } from '../payment/payment.controller';
import { BogService } from '../payment/payment.service';
import { TableController } from '../reservation/reservation.controller';
import { ReservationService } from '../reservation/reservation.service';
import { WebsitePosReservationBridgeService } from '../reservation/website-pos-reservation-bridge.service';
import { CustomWebsiteGuard } from '../tenancy/custom-website.guard';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { UserController } from '../user/user.controller';
import { UserService } from '../user/user.service';
import { CustomWebsiteController } from './custom-website.controller';
import { CustomWebsiteService } from './custom-website.service';

/**
 * CUSTOM website registration, binding and isolation, over HTTP.
 *
 * Two CUSTOM restaurants (A, B) are provisioned exactly as an operator would:
 * Website plan, CUSTOM selected on the Platform route, frontend identity and
 * domains registered, status moved through the readiness checklist. A SAAS
 * restaurant (S) stands for the generic product. Every public request carries
 * only a Host; each claim is that one restaurant cannot see or act as another.
 */
const url = process.env.CUSTOM_WEBSITE_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'CUSTOM website binding / disposable PostgreSQL',
  () => {
    const tag = randomUUID().slice(0, 8);
    const config = new ConfigService({
      // Development on purpose: the local fallback must still refuse an
      // unregistered named *.localhost site.
      NODE_ENV: 'development',
      SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local',
      TRUST_PROXY_HOST: 'false',
    });
    let db: PrismaService, app: any, authService: WebsiteAuthService;
    let integrations: PaymentIntegrationsService;
    let crypto: CryptoService;
    const venues: Record<'a' | 'b' | 's', any> = {} as never;
    const owners: Record<string, string> = {};
    const items: Record<string, { shown: string; hidden: string }> = {};
    let saasHost: string;
    let admin: { id: string }, support: { id: string };
    let customer: { id: string };
    const host = (k: 'a' | 'b') => `custom-${k}-${tag}.vynic.localhost`;
    const ownerAuth = (token: string) => ({ Authorization: `Bearer ${token}` });
    // A further restaurant with its own owner, created as a sale would be.
    let makeVenue: (
      label: string,
      planKey: 'WEBSITE_ONLY' | 'POS_WEBSITE',
    ) => Promise<{ id: string; token: string }>;
    const http = () => request(app.getHttpServer());
    const platform = (token = 'admin-token') => ({
      Authorization: `Bearer ${token}`,
    });
    const cookieFor = async (identifier: string) => {
      const tokens = await authService.signin({
        identifier,
        password: 'correct-horse',
      });
      return `access_token=${encodeURIComponent(crypto.encrypt(tokens.access_token))}`;
    };
    const order = (h: string, body: Record<string, unknown> = {}) =>
      http()
        .post('/api/bog/create-order')
        .set('Host', h)
        .send({
          selectedTables: ['table1'],
          selectedDate: '2026-11-02',
          selectedTime: '19:00',
          customerName: `Guest-${tag}`,
          customerPhone: `+995-guest-${tag}`,
          customerEmail: `guest-${tag}@test.invalid`,
          ...body,
        });

    beforeAll(async () => {
      const u = new URL(url!);
      if (!isFreshDisposableDatabase(u))
        throw Error('Only a fresh disposable_* database is permitted');
      process.env.JWT_SECRET = 'custom-website-test-only';
      process.env.COOKIE_ENCRYPTION_KEY = 'custom-website-cookie-test-only';
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = '34'.repeat(32);
      process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.local';
      db = new PrismaService({ datasourceUrl: url });
      const jwt = new JwtService();
      const access = new VenueEntitlementsService(db);
      const tenants = new WebsiteTenantService(db, config);
      const menus = new WebsiteMenuService(db);
      integrations = new PaymentIntegrationsService(db, access);
      const bog = new BogService(new MenuService(db), integrations, db);
      crypto = new CryptoService();
      authService = new WebsiteAuthService(db, jwt, config, crypto);
      const bridge = {
        areWebsiteTablesAvailable: jest.fn().mockResolvedValue(true),
        getUnavailableTableCodesForDate: jest.fn().mockResolvedValue(new Set()),
        fetchPosReservations: jest.fn().mockResolvedValue([]),
        fetchPosBookingsForDate: jest.fn().mockResolvedValue([]),
        mapPosTableCodesToWebsiteTables: jest.fn().mockReturnValue([]),
        pushConfirmedReservationToPos: jest.fn(),
      };
      const audit = new PlatformAuditService(db);
      const directory = new PlatformDirectoryService(db, audit);

      admin = await db.platformUser.create({
        data: {
          email: `ops-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: 'unused',
        },
      });
      support = await db.platformUser.create({
        data: {
          email: `support-${tag}@test.invalid`,
          displayName: 'Support',
          passwordHash: 'unused',
          role: 'SUPPORT_READONLY',
        },
      });
      const principals: Record<string, unknown> = {
        'admin-token': {
          platformUserId: admin.id,
          role: 'SUPER_ADMIN',
          email: `ops-${tag}@test.invalid`,
          displayName: 'Operator',
        },
        'support-token': {
          platformUserId: support.id,
          role: 'SUPPORT_READONLY',
          email: `support-${tag}@test.invalid`,
          displayName: 'Support',
        },
      };

      const trial = {
        status: 'TRIAL' as const,
        startedAt: new Date(),
        trialEndsAt: new Date(Date.now() + 14 * 86_400_000),
      };
      const onlinePayments = await db.feature.findUniqueOrThrow({
        where: { key: 'ONLINE_PAYMENTS' },
      });
      makeVenue = async (label, planKey) => {
        const org = await db.organization.create({
          data: { name: `${label} ${tag}` },
        });
        const venue = await db.venue.create({
          data: {
            organizationId: org.id,
            name: `${label} ${tag}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            planAssignment: { create: { plan: { connect: { key: planKey } } } },
            subscription: { create: trial },
          },
        });
        const owner = await db.customerAccount.create({
          data: {
            organizationId: org.id,
            memberships: { create: { organizationId: org.id, role: 'OWNER' } },
            email: `owner-${label.replace(/\W/g, '')}-${tag}@test.invalid`,
            displayName: 'Owner',
            passwordHash: 'unused',
          },
        });
        const token = await jwt.signAsync(
          { sub: owner.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        );
        return { id: venue.id, token };
      };
      for (const k of ['a', 'b', 's'] as const) {
        const org = await db.organization.create({
          data: { name: `Custom ${k} ${tag}` },
        });
        venues[k] = await db.venue.create({
          data: {
            organizationId: org.id,
            name: `Restaurant ${k.toUpperCase()} ${tag}`,
            phone: `+99555500000${k === 'a' ? 1 : k === 'b' ? 2 : 3}`,
            address: `${k.toUpperCase()} street`,
            legalId: `private-legal-${k}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            planAssignment: {
              create: { plan: { connect: { key: 'WEBSITE_ONLY' } } },
            },
            subscription: { create: trial },
            featureOverrides:
              k === 's'
                ? undefined
                : {
                    create: { featureId: onlinePayments.id, effect: 'ENABLED' },
                  },
          },
        });
        const owner = await db.customerAccount.create({
          data: {
            organizationId: org.id,
            memberships: { create: { organizationId: org.id, role: 'OWNER' } },
            email: `owner-${k}-${tag}@test.invalid`,
            displayName: 'Owner',
            passwordHash: 'unused',
          },
        });
        owners[k] = await jwt.signAsync(
          { sub: owner.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        );
        if (k === 's') continue;
        // Each restaurant's own canonical menu: a crossed boundary shows up as
        // another restaurant's dish.
        const category = await db.menuCategory.create({
          data: {
            venueId: venues[k].id,
            slug: `cat-${k}`,
            nameKa: `კატეგორია ${k}`,
            nameEn: `Category ${k}`,
          },
        });
        const [shown, hidden] = await Promise.all(
          ['Shown', 'Hidden'].map((label, i) =>
            db.menuItem.create({
              data: {
                venueId: venues[k].id,
                categoryId: category.id,
                nameKa: `${label} ${k}`,
                nameEn: `${label} ${k}`,
                price: k === 'a' ? 10 : 20,
                sortOrder: i,
              },
            }),
          ),
        );
        items[k] = { shown: shown.id, hidden: hidden.id };
        await db.menuItemWebsitePresentation.create({
          data: {
            menuItemId: hidden.id,
            venueId: venues[k].id,
            visibleOnWebsite: false,
          },
        });
        await db.websiteTable.create({
          data: {
            venueId: venues[k].id,
            websiteTableNumber: 'table1',
            posTableNumber: '1',
            posFloor: 'first',
          },
        });
      }
      // A table only B has: A's host must not be able to book it.
      await db.websiteTable.create({
        data: {
          venueId: venues.b.id,
          websiteTableNumber: `b-only-${tag}`,
          posTableNumber: '9',
          posFloor: 'first',
        },
      });

      const password = await argon.hash('correct-horse');
      customer = await db.websiteUser.create({
        data: {
          phone: `+99559${tag.replace(/\D/g, '0').slice(0, 7)}1`,
          email: `customer-${tag}@test.invalid`,
          password,
        },
      });
      // A website administrator bound to A only.
      await db.websiteUser.create({
        data: {
          phone: `+99559${tag.replace(/\D/g, '0').slice(0, 7)}2`,
          email: `site-admin-${tag}@test.invalid`,
          password,
          role: 'SUPER_ADMIN',
          adminVenueId: venues.a.id,
        },
      });

      const core = new WebsiteCoreService(db, access, tenants, config, menus);
      const customers = new CustomerService(
        db,
        access,
        {} as never,
        {} as never,
      );
      const mod = await Test.createTestingModule({
        controllers: [
          CustomWebsiteController,
          MenuController,
          TableController,
          BogController,
          UserController,
          PlatformVenuesController,
          PlatformCustomWebsiteController,
          CustomerWebsiteController,
          CustomerCatalogController,
          WebsiteCoreController,
        ],
        providers: [
          { provide: PrismaService, useValue: db },
          { provide: ConfigService, useValue: config },
          { provide: VenueEntitlementsService, useValue: access },
          { provide: WebsiteTenantService, useValue: tenants },
          WebsiteTenantGuard,
          CustomWebsiteGuard,
          { provide: WebsiteMenuService, useValue: menus },
          {
            provide: CustomWebsiteService,
            useValue: new CustomWebsiteService(db, access, menus, config),
          },
          { provide: MenuService, useValue: new MenuService(db) },
          { provide: PaymentIntegrationsService, useValue: integrations },
          { provide: BogService, useValue: bog },
          {
            provide: ReservationService,
            useValue: new ReservationService(db, bog, bridge as never),
          },
          { provide: WebsitePosReservationBridgeService, useValue: bridge },
          { provide: WebsiteAuthService, useValue: authService },
          { provide: CryptoService, useValue: crypto },
          { provide: UserService, useValue: new UserService(db) },
          {
            provide: PlatformAuthService,
            useValue: { resolve: async (t: string) => principals[t] ?? null },
          },
          PlatformAuthGuard,
          { provide: PlatformDirectoryService, useValue: directory },
          {
            provide: PlatformVenueConfigService,
            useValue: new PlatformVenueConfigService(
              db,
              access,
              directory,
              audit,
            ),
          },
          { provide: PlatformDeviceService, useValue: {} },
          { provide: WebsiteCoreService, useValue: core },
          HostnameRequestsService,
          WebsiteLogoService,
          {
            provide: WebsitePreviewTokens,
            useValue: new WebsitePreviewTokens(db, jwt),
          },
          {
            provide: CustomerService,
            useValue: customers,
          },
          {
            provide: RestaurantFoundationService,
            useValue: new RestaurantFoundationService(db, customers, access),
          },
          {
            provide: CustomerAuth,
            useValue: new CustomerAuth(db, jwt, new EnrollmentRateLimiter()),
          },
        ],
      }).compile();
      app = mod.createNestApplication({ rawBody: true });
      app.use(cookieParser());
      await app.init();

      (axios.post as jest.Mock).mockImplementation(
        async (target: string, body: any, options: any) =>
          target.includes('openid-connect')
            ? {
                data: {
                  // The bank token proves which Venue's credentials were used.
                  access_token: `token-for-${
                    Buffer.from(
                      options.headers.Authorization.slice(6),
                      'base64',
                    )
                      .toString()
                      .split(':')[0]
                  }`,
                },
              }
            : {
                data: {
                  id: `bank-${body.external_order_id}`,
                  _links: {
                    redirect: { href: 'https://payment.test/checkout' },
                  },
                },
              },
      );
    });

    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('provisions CUSTOM through the operator workflow only', async () => {
      // The binding belongs to CUSTOM Venues; nothing to bind before selection.
      await http()
        .put(`/platform/venues/${venues.a.id}/custom-website`)
        .set(platform())
        .send({ siteKey: 'custom-a-web' })
        .expect(409);

      for (const k of ['a', 'b'] as const)
        await http()
          .put(`/platform/venues/${venues[k].id}/website`)
          .set(platform())
          .send({ mode: 'CUSTOM' })
          .expect(200);
      await http()
        .put(`/platform/venues/${venues.s.id}/website`)
        .set(platform())
        .send({ mode: 'SAAS' })
        .expect(200);
      saasHost = (
        await db.venueDomain.findFirstOrThrow({
          where: { venueId: venues.s.id },
        })
      ).hostname;

      // Support is read-only; an invalid identity is refused.
      await http()
        .put(`/platform/venues/${venues.a.id}/custom-website`)
        .set(platform('support-token'))
        .send({ siteKey: 'custom-a-web' })
        .expect(403);
      await http()
        .put(`/platform/venues/${venues.a.id}/custom-website`)
        .set(platform())
        .send({ siteKey: 'Custom A!' })
        .expect(400);

      // ACTIVE claims a working site: identity and a domain are required.
      const early = await http()
        .put(`/platform/venues/${venues.a.id}/custom-website`)
        .set(platform())
        .send({ siteKey: 'custom-a-web', status: 'ACTIVE' })
        .expect(409);
      expect(early.body.readiness).toMatchObject({
        siteKey: true,
        activeDomain: false,
      });

      for (const k of ['a', 'b'] as const) {
        await http()
          .post(`/platform/venues/${venues[k].id}/domains`)
          .set(platform())
          .send({ hostname: host(k) })
          .expect(201);
        await http()
          .put(`/platform/venues/${venues[k].id}/custom-website`)
          .set(platform())
          .send({ siteKey: `custom-${k}-web`, status: 'ACTIVE' })
          .expect(200);
        await integrations.save(
          venues[k].id,
          {
            clientId: `client-${k}-${tag}`,
            clientSecret: `secret-${k}-${tag}`,
            returnOrigin: `http://${host(k)}:5176`,
          },
          { importOperator: 'test' },
        );
      }
      // A domain already bound to A can never be attached to B.
      await http()
        .post(`/platform/venues/${venues.b.id}/domains`)
        .set(platform())
        .send({ hostname: host('a') })
        .expect(409);

      const view = (
        await http()
          .get(`/platform/venues/${venues.a.id}/custom-website`)
          .set(platform('support-token'))
          .expect(200)
      ).body;
      expect(view).toMatchObject({
        mode: 'CUSTOM',
        entitled: true,
        commercialStatus: 'TRIAL',
        status: 'ACTIVE',
        siteKey: 'custom-a-web',
        payments: 'ENABLED',
        capabilities: {
          menu: true,
          onlinePayments: true,
          reservations: true,
          customerAccounts: true,
        },
        readiness: { complete: true },
      });
      expect(view.domains.map((d: any) => d.hostname)).toEqual([host('a')]);
      const actions = view.audit.map((e: any) => e.action);
      expect(actions).toEqual(
        expect.arrayContaining([
          'venue.website_mode_changed',
          'venue.domain_registered',
          'venue.custom_website_site_key_changed',
          'venue.custom_website_status_changed',
        ]),
      );
      expect(view.audit.every((e: any) => e.actor === 'Operator')).toBe(true);
      // Secrets never reach the operator view.
      expect(JSON.stringify(view)).not.toContain(`secret-a-${tag}`);
    });

    it('resolves each Host to only its own Venue', async () => {
      for (const [k, other] of [
        ['a', 'b'],
        ['b', 'a'],
      ] as const) {
        const boot = (
          await http()
            .get('/api/website/custom/bootstrap')
            .set('Host', `${host(k)}:5176`)
            .expect(200)
        ).body;
        expect(boot).toMatchObject({
          mode: 'CUSTOM',
          site: { key: `custom-${k}-web`, status: 'ACTIVE' },
          profile: { name: `Restaurant ${k.toUpperCase()} ${tag}` },
          capabilities: { reservations: true, onlinePayments: true },
        });
        expect(JSON.stringify(boot)).not.toContain('private-legal');

        const menu = JSON.stringify(
          (
            await http()
              .get('/api/website/custom/menu')
              .set('Host', host(k))
              .expect(200)
          ).body,
        );
        expect(menu).toContain(items[k].shown);
        expect(menu).not.toContain(items[k].hidden);
        expect(menu).not.toContain(items[other].shown);

        const legacy = JSON.stringify(
          (await http().get('/api/menu').set('Host', host(k)).expect(200)).body,
        );
        expect(legacy).toContain(items[k].shown);
        expect(legacy).not.toContain(items[other].shown);
      }
    });

    it('ignores forged Venue identity in query, headers and body', async () => {
      const forged = (
        await http()
          .get(`/api/website/custom/bootstrap?venueId=${venues.b.id}`)
          .set('Host', host('a'))
          .set('X-Venue-Id', venues.b.id)
          .set('X-Domain', host('b'))
          .set('X-Forwarded-Host', host('b'))
          .expect(200)
      ).body;
      expect(forged.site.key).toBe('custom-a-web');

      // A table that exists only at B is simply not found through A's host.
      await order(host('a'), {
        venueId: venues.b.id,
        organizationId: venues.b.organizationId,
        selectedTables: [`b-only-${tag}`],
      }).expect(400);
    });

    it('refuses unknown hosts and never serves a SAAS Venue as CUSTOM', async () => {
      for (const route of [
        '/api/website/custom/bootstrap',
        '/api/menu',
        '/api/tables',
      ])
        await http()
          .get(route)
          .set('Host', `unknown-${tag}.vynic.localhost`)
          .expect(404);

      for (const route of [
        '/api/website/custom/bootstrap',
        '/api/website/custom/menu',
        '/api/menu',
        '/api/tables',
        '/api/tables/availability?date=2026-11-02',
      ])
        await http().get(route).set('Host', saasHost).expect(404);
      await order(saasHost).expect(404);

      // The generic SaaS contract is unchanged: CUSTOM hosts get the marker only.
      expect(
        (
          await http()
            .get('/api/website/bootstrap')
            .set('Host', host('a'))
            .expect(200)
        ).body,
      ).toEqual({ schemaVersion: 2, mode: 'CUSTOM' });
      await http().get('/api/website/menu').set('Host', host('a')).expect(404);
    });

    it('books and pays through each Venue’s own integration and session', async () => {
      const anonymous = await order(host('a'), { userId: customer.id }).expect(
        201,
      );
      const guestBooking = await db.websiteReservation.findUniqueOrThrow({
        where: { id: anonymous.body.reservation_id },
        include: { paymentIntegration: true },
      });
      // A browser-supplied account id attaches nothing.
      expect(guestBooking.userId).toBeNull();
      expect(guestBooking.venueId).toBe(venues.a.id);

      const cookie = await cookieFor(`customer-${tag}@test.invalid`);
      for (const k of ['a', 'b'] as const) {
        const res = await order(host(k)).set('Cookie', cookie).expect(201);
        const booking = await db.websiteReservation.findUniqueOrThrow({
          where: { id: res.body.reservation_id },
          include: { paymentIntegration: true },
        });
        expect(booking.venueId).toBe(venues[k].id);
        expect(booking.userId).toBe(customer.id);
        expect(booking.paymentIntegration!.venueId).toBe(venues[k].id);
        // The provider was authenticated with this Venue's own client id.
        const bankCall = (axios.post as jest.Mock).mock.calls
          .filter(([target]) => target.includes('/ecommerce/orders'))
          .find(([, body]) => body.external_order_id === booking.id);
        expect(bankCall[2].headers.Authorization).toBe(
          `Bearer token-for-client-${k}-${tag}`,
        );
        expect(bankCall[1].redirect_urls.success).toContain(
          `http://${host(k)}:5176/`,
        );
      }

      // Settlement is covered by the W1 callback proof; here the bookings are
      // simply confirmed so the account view lists them.
      await db.websiteReservation.updateMany({
        where: { userId: customer.id },
        data: { status: 'CONFIRMED' },
      });
      // The global account sees only this site's bookings.
      for (const [k, other] of [
        ['a', 'b'],
        ['b', 'a'],
      ] as const) {
        const mine = (
          await http()
            .get('/api/user/reservations')
            .set('Host', host(k))
            .set('Cookie', cookie)
            .expect(200)
        ).body;
        const ids = JSON.stringify(mine);
        const own = await db.websiteReservation.findMany({
          where: { venueId: venues[k].id, userId: customer.id },
        });
        const foreign = await db.websiteReservation.findMany({
          where: { venueId: venues[other].id, userId: customer.id },
        });
        expect(own.length).toBeGreaterThan(0);
        for (const r of own) expect(ids).toContain(r.id);
        for (const r of foreign) expect(ids).not.toContain(r.id);
      }
    });

    it('limits a website administrator to the Venue it administers', async () => {
      const cookie = await cookieFor(`site-admin-${tag}@test.invalid`);
      const own = (
        await http()
          .get('/api/tables/reservations?date=2026-11-02')
          .set('Host', host('a'))
          .set('Cookie', cookie)
          .expect(200)
      ).body;
      expect(JSON.stringify(own)).toContain(`Guest-${tag}`);
      const foreign = (
        await http()
          .get('/api/tables/reservations?date=2026-11-02')
          .set('Host', host('b'))
          .set('Cookie', cookie)
          .expect(200)
      ).body;
      // B has bookings too, but this administrator gets B's anonymous map.
      expect(foreign.length).toBeGreaterThan(0);
      expect(JSON.stringify(foreign)).not.toContain(`Guest-${tag}`);
      expect(JSON.stringify(foreign)).not.toContain(`guest-${tag}`);
      // Anonymous visitors see occupancy without names or phones.
      const anonymous = (
        await http()
          .get('/api/tables/reservations?date=2026-11-02')
          .set('Host', host('a'))
          .expect(200)
      ).body;
      expect(anonymous.length).toBeGreaterThan(0);
      expect(JSON.stringify(anonymous)).not.toContain(`Guest-${tag}`);
      expect(JSON.stringify(anonymous)).not.toContain(`guest-${tag}`);
    });

    it('keeps mode, frontend and domains out of owner hands', async () => {
      const owner = { Authorization: `Bearer ${owners.a}` };
      const settings = (
        await http()
          .get(`/customer/venues/${venues.a.id}/website`)
          .set(owner)
          .expect(200)
      ).body;
      expect(settings).toMatchObject({
        mode: 'CUSTOM',
        state: 'CUSTOM',
        custom: { status: 'ACTIVE' },
        domains: [host('a')],
      });
      // The generic editor cannot be used to leave CUSTOM.
      const draft = await http()
        .put(`/customer/venues/${venues.a.id}/website/draft`)
        .set(owner)
        .send({ expectedRevision: 0, content: { mode: 'SAAS' } });
      expect(draft.status).toBeGreaterThanOrEqual(400);
      // Owner tokens are not Platform tokens.
      await http()
        .put(`/platform/venues/${venues.a.id}/website`)
        .set(owner)
        .send({ mode: 'SAAS' })
        .expect(401);
      await http()
        .put(`/platform/venues/${venues.a.id}/custom-website`)
        .set(owner)
        .send({ siteKey: 'restaurant-x-web' })
        .expect(401);
      const row = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: venues.a.id },
      });
      expect(row.mode).toBe('CUSTOM');
    });

    it('stops serving when the commercial Trial ends, without a fallback renderer', async () => {
      await db.venueSubscription.update({
        where: { venueId: venues.b.id },
        data: { trialEndsAt: new Date(Date.now() - 60_000) },
      });
      await http()
        .get('/api/website/custom/bootstrap')
        .set('Host', host('b'))
        .expect(403);
      await order(host('b')).expect(403);
      await http()
        .get('/api/website/bootstrap')
        .set('Host', host('b'))
        .expect(404);
      // A is unaffected.
      await http()
        .get('/api/website/custom/bootstrap')
        .set('Host', host('a'))
        .expect(200);
    });

    it('gives a Website-only CUSTOM Venue the same canonical Cloud catalog as SAAS', async () => {
      const c = await makeVenue('Custom C cloud', 'WEBSITE_ONLY');
      const cHost = `custom-c-${tag}.vynic.localhost`;
      await http()
        .put(`/platform/venues/${c.id}/website`)
        .set(platform())
        .send({ mode: 'CUSTOM' })
        .expect(200);
      // CUSTOM decides only the renderer; no POS in the package means Cloud.
      expect(
        await db.venue.findUniqueOrThrow({
          where: { id: c.id },
          select: { menuAuthority: true, cloudMenuEditingEnabled: true },
        }),
      ).toEqual({ menuAuthority: 'CLOUD', cloudMenuEditingEnabled: true });
      expect(await db.venueDomain.count({ where: { venueId: c.id } })).toBe(0);
      expect(await db.menuCategory.count({ where: { venueId: c.id } })).toBe(0);

      // Nothing to check before a domain exists.
      await http()
        .post(`/platform/venues/${c.id}/custom-website/check`)
        .set(platform())
        .expect(409);

      // The owner authors the catalog from the Dashboard.
      const read = async () =>
        (
          await http()
            .get(`/customer/venues/${c.id}/catalog`)
            .set(ownerAuth(c.token))
            .expect(200)
        ).body;
      expect(await read()).toMatchObject({
        authority: 'CLOUD',
        editingEnabled: true,
        posIncluded: false,
      });
      const categoryId = randomUUID();
      const subcategoryId = randomUUID();
      const itemId = randomUUID();
      await http()
        .put(`/customer/venues/${c.id}/catalog/category`)
        .set(ownerAuth(c.token))
        .send({
          id: categoryId,
          expectedRevision: (await read()).revision,
          nameKa: 'ცხელი',
          nameEn: 'Hot dishes',
        })
        .expect(200);
      await http()
        .put(`/customer/venues/${c.id}/catalog/subcategory`)
        .set(ownerAuth(c.token))
        .send({
          id: subcategoryId,
          categoryId,
          expectedRevision: (await read()).revision,
          nameKa: 'მწვადი',
          nameEn: 'Grill',
        })
        .expect(200);
      await http()
        .put(`/customer/venues/${c.id}/catalog/item`)
        .set(ownerAuth(c.token))
        .send({
          id: itemId,
          subcategoryId,
          expectedRevision: (await read()).revision,
          nameKa: 'ღორის მწვადი',
          nameEn: 'Pork mtsvadi',
          price: 24,
          enabled: true,
        })
        .expect(200);
      await http()
        .put(`/customer/venues/${c.id}/catalog/variant`)
        .set(ownerAuth(c.token))
        .send({
          menuItemId: itemId,
          expectedRevision: (await read()).revision,
          nameKa: 'დიდი',
          nameEn: 'Large',
          price: 32,
          size: 1,
        })
        .expect(200);

      // The custom frontend on C's domain receives that same catalog.
      await http()
        .post(`/platform/venues/${c.id}/domains`)
        .set(platform())
        .send({ hostname: cHost })
        .expect(201);
      const menu = (
        await http()
          .get('/api/website/custom/menu')
          .set('Host', cHost)
          .expect(200)
      ).body;
      expect(JSON.stringify(menu)).toContain('Pork mtsvadi');
      const legacy = (
        await http().get('/api/menu').set('Host', cHost).expect(200)
      ).body;
      expect(JSON.stringify(legacy)).toContain('Pork mtsvadi');
      expect(JSON.stringify(menu)).not.toContain('Shown a');

      // Website only: POS and Manager stay out of the package.
      const features = (
        await http()
          .get(`/platform/venues/${c.id}/product`)
          .set(platform())
          .expect(200)
      ).body;
      expect(features.effectiveFeatures).toEqual(['WEBSITE']);
      expect(features.menuManagement).toMatchObject({
        authority: 'CLOUD',
        enabled: true,
        posIncluded: false,
        needsCloudAuthority: false,
      });
      expect(
        (
          await http()
            .get(`/platform/venues/${c.id}/custom-website`)
            .set(platform())
            .expect(200)
        ).body,
      ).toMatchObject({
        primaryDomain: cHost,
        publicUrl: `http://${cHost}:5176/`,
        menu: { authority: 'CLOUD', editingEnabled: true, posIncluded: false },
      });
    });

    it('keeps POS authority for a CUSTOM Venue whose package includes POS', async () => {
      const d = await makeVenue('Custom D pos', 'POS_WEBSITE');
      const dHost = `custom-d-${tag}.vynic.localhost`;
      // The POS-mirrored catalog that exists before the website is sold.
      const category = await db.menuCategory.create({
        data: {
          venueId: d.id,
          slug: `pos-cat-${tag}`,
          nameKa: 'POS კატეგორია',
          nameEn: 'POS category',
        },
      });
      await db.menuItem.create({
        data: {
          venueId: d.id,
          categoryId: category.id,
          nameKa: 'POS კერძი',
          nameEn: 'POS dish',
          price: 15,
        },
      });
      await http()
        .put(`/platform/venues/${d.id}/website`)
        .set(platform())
        .send({ mode: 'CUSTOM' })
        .expect(200);
      expect(
        await db.venue.findUniqueOrThrow({
          where: { id: d.id },
          select: { menuAuthority: true, cloudMenuEditingEnabled: true },
        }),
      ).toEqual({ menuAuthority: 'POS', cloudMenuEditingEnabled: false });

      // The Dashboard is not a second operational menu writer.
      const catalog = (
        await http()
          .get(`/customer/venues/${d.id}/catalog`)
          .set(ownerAuth(d.token))
          .expect(200)
      ).body;
      expect(catalog).toMatchObject({ authority: 'POS', posIncluded: true });
      await http()
        .put(`/customer/venues/${d.id}/catalog/category`)
        .set(ownerAuth(d.token))
        .send({
          expectedRevision: catalog.revision,
          nameKa: 'ახალი',
          nameEn: 'New',
        })
        .expect(409);
      expect(await db.menuCategory.count({ where: { venueId: d.id } })).toBe(1);

      // The custom frontend reads the same canonical projection POS feeds.
      await http()
        .post(`/platform/venues/${d.id}/domains`)
        .set(platform())
        .send({ hostname: dHost })
        .expect(201);
      expect(
        JSON.stringify(
          (
            await http()
              .get('/api/website/custom/menu')
              .set('Host', dHost)
              .expect(200)
          ).body,
        ),
      ).toContain('POS dish');
      const product = (
        await http()
          .get(`/platform/venues/${d.id}/product`)
          .set(platform())
          .expect(200)
      ).body.menuManagement;
      expect(product).toMatchObject({
        authority: 'POS',
        posIncluded: true,
        needsCloudAuthority: false,
        canEnableCloud: false,
      });
    });

    it('reports and repairs a Website-only CUSTOM Venue left on POS authority', async () => {
      // The state CUSTOM provisioning used to leave: no POS, no menu writer.
      const e = await makeVenue('Custom E stuck', 'WEBSITE_ONLY');
      await db.venueWebsiteConfig.create({
        data: { venueId: e.id, mode: 'CUSTOM' },
      });
      const product = async () =>
        (
          await http()
            .get(`/platform/venues/${e.id}/product`)
            .set(platform())
            .expect(200)
        ).body.menuManagement;
      expect(await product()).toMatchObject({
        authority: 'POS',
        enabled: false,
        canEnableCloud: true,
        reason: null,
        posIncluded: false,
        needsCloudAuthority: true,
      });
      expect(
        (
          await http()
            .get(`/platform/venues/${e.id}/custom-website`)
            .set(platform())
            .expect(200)
        ).body.menu,
      ).toMatchObject({ authority: 'POS', needsCloudAuthority: true });
      // The owner is told setup is unfinished, not that POS manages the menu.
      expect(
        (
          await http()
            .get(`/customer/venues/${e.id}/catalog`)
            .set(ownerAuth(e.token))
            .expect(200)
        ).body,
      ).toMatchObject({ authority: 'POS', posIncluded: false });

      // Repair: the existing audited Dashboard menu editing control.
      await http()
        .put(`/platform/venues/${e.id}/menu-management/cloud`)
        .set(platform('support-token'))
        .send({ enabled: true })
        .expect(403);
      await http()
        .put(`/platform/venues/${e.id}/menu-management/cloud`)
        .set(platform())
        .send({ enabled: true })
        .expect(200);
      expect(await product()).toMatchObject({
        authority: 'CLOUD',
        enabled: true,
        needsCloudAuthority: false,
      });
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: e.id, action: 'venue.cloud_menu_enabled' },
        }),
      ).toMatchObject({ platformUserId: admin.id });
    });

    it('checks runtime availability on demand, separately from setup status', async () => {
      // A local frontend behind a host-preserving /api proxy to this backend.
      const site = nodeHttp.createServer((req, res) => {
        if (!req.url?.startsWith('/api/')) {
          res.setHeader('content-type', 'text/html');
          res.end('<!doctype html><title>custom</title>');
          return;
        }
        void http()
          .get(req.url)
          .set('Host', req.headers.host ?? '')
          .then((answer) => {
            res.statusCode = answer.status;
            res.setHeader(
              'content-type',
              String(answer.headers['content-type'] ?? 'text/plain'),
            );
            res.end(answer.text);
          });
      });
      await new Promise<void>((resolve) =>
        site.listen(0, '127.0.0.1', resolve),
      );
      process.env.CUSTOM_WEBSITE_DEV_PORT = String(
        (site.address() as AddressInfo).port,
      );
      try {
        const view = (
          await http()
            .get(`/platform/venues/${venues.a.id}/custom-website`)
            .set(platform())
            .expect(200)
        ).body;
        expect(view).toMatchObject({
          status: 'ACTIVE',
          primaryDomain: host('a'),
          publicUrl: `http://${host('a')}:${process.env.CUSTOM_WEBSITE_DEV_PORT}/`,
        });
        // Support may look, not trigger outbound requests.
        await http()
          .post(`/platform/venues/${venues.a.id}/custom-website/check`)
          .set(platform('support-token'))
          .expect(403);
        const check = (
          await http()
            .post(`/platform/venues/${venues.a.id}/custom-website/check`)
            .set(platform())
            .expect(200)
        ).body;
        expect(check).toMatchObject({
          availability: 'REACHABLE',
          hostname: host('a'),
          url: view.publicUrl,
          frontend: { status: 200 },
          api: { state: 'OK' },
        });
        expect(Date.parse(check.checkedAt)).toBeGreaterThan(
          Date.now() - 60_000,
        );
        await http()
          .post(`/platform/venues/${venues.a.id}/custom-website/check`)
          .set(platform())
          .expect(429);
      } finally {
        await new Promise((resolve) => site.close(resolve));
      }

      // Configured ACTIVE, yet nothing answers: the two are reported apart.
      const down = (
        await http()
          .post(`/platform/venues/${venues.b.id}/custom-website/check`)
          .set(platform())
          .expect(200)
      ).body;
      expect(down).toMatchObject({
        availability: 'UNREACHABLE',
        frontend: { status: null, detail: 'Connection refused' },
      });
      expect(
        (
          await db.customWebsiteBinding.findUniqueOrThrow({
            where: { venueId: venues.b.id },
          })
        ).status,
      ).toBe('ACTIVE');
      // Only CUSTOM Venues, only their own registered domains.
      await http()
        .post(`/platform/venues/${venues.s.id}/custom-website/check`)
        .set(platform())
        .expect(409);
      delete process.env.CUSTOM_WEBSITE_DEV_PORT;
    });
  },
);
