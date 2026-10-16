import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
jest.mock('axios');
import axios from 'axios';
import * as argon from 'argon2';
import { randomUUID, createHash } from 'node:crypto';
import { websiteVenueIdentity } from '../core/website-identity';
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
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { WebsiteCapabilityGuard } from '../tenancy/website-capability.guard';
import { PlatformWebsiteCapabilitiesController } from '../../platform/platform-website-capabilities.controller';
import { VenuePublicProfileService } from '../core/venue-public-profile.service';
import { WebsiteVenueController } from '../core/website-venue.controller';
import { WebsiteVenueService } from '../core/website-venue.service';
import { emptyWebsiteContent } from '../core/website-content';
import { WebsiteAuthController } from '../auth/auth.controller';
import { CsrfService } from '../common/csrf.service';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { UserController } from '../user/user.controller';
import { UserService } from '../user/user.service';
import { CustomWebsiteService } from './custom-website.service';
import { MenuCatalogService } from '../../menu-catalog/menu-catalog.service';

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

      const capabilities = new WebsiteCapabilitiesService(db, access);
      const publicInfo = new VenuePublicProfileService(db, capabilities);
      const core = new WebsiteCoreService(
        db,
        access,
        tenants,
        config,
        menus,
        capabilities,
        publicInfo,
      );
      const customers = new CustomerService(
        db,
        access,
        {} as never,
        {} as never,
      );
      const mod = await Test.createTestingModule({
        controllers: [
          WebsiteVenueController,
          WebsiteAuthController,
          PlatformWebsiteCapabilitiesController,
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
          { provide: WebsiteCapabilitiesService, useValue: capabilities },
          WebsiteCapabilityGuard,
          { provide: VenuePublicProfileService, useValue: publicInfo },
          {
            provide: WebsiteVenueService,
            useValue: new WebsiteVenueService(
              db,
              access,
              capabilities,
              publicInfo,
              menus,
            ),
          },
          CsrfService,
          EnrollmentRateLimiter,
          { provide: WebsiteMenuService, useValue: menus },
          {
            provide: CustomWebsiteService,
            useValue: new CustomWebsiteService(db, access, config),
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
            useValue: new RestaurantFoundationService(
              db,
              customers,
              access,
              new MenuCatalogService(db),
            ),
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
            .get('/api/website/venue')
            .set('Host', `${host(k)}:5176`)
            .expect(200)
        ).body;
        expect(boot).toMatchObject({
          mode: 'CUSTOM',
          site: { key: `custom-${k}-web`, status: 'ACTIVE' },
          profile: { name: `Restaurant ${k.toUpperCase()} ${tag}` },
          info: { workingHours: [], gallery: [] },
          capabilities: {
            menu: true,
            reservations: true,
            onlinePayments: true,
            customerAccounts: true,
          },
        });
        expect(JSON.stringify(boot)).not.toContain('private-legal');

        const menu = JSON.stringify(
          (
            await http()
              .get('/api/website/venue/menu')
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
          .get(`/api/website/venue?venueId=${venues.b.id}`)
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

    it('applies one set of capability rules to SAAS and CUSTOM hosts', async () => {
      for (const route of ['/api/website/venue', '/api/menu', '/api/tables'])
        await http()
          .get(route)
          .set('Host', `unknown-${tag}.vynic.localhost`)
          .expect(404);

      // A SAAS site is not launched until its owner publishes it: nothing
      // shared answers for its host before that.
      for (const route of [
        '/api/website/venue',
        '/api/website/venue/menu',
        '/api/menu',
        '/api/tables',
      ])
        await http().get(route).set('Host', saasHost).expect(404);
      const slug = saasHost.split('.')[0];
      await http()
        .put(`/customer/venues/${venues.s.id}/website/draft`)
        .set(ownerAuth(owners.s))
        .send({
          expectedRevision: 0,
          content: { ...emptyWebsiteContent, slug, heroTitle: 'S' },
        })
        .expect(200);
      await http()
        .post(`/customer/venues/${venues.s.id}/website/publish`)
        .set(ownerAuth(owners.s))
        .send({ expectedRevision: 1 })
        .expect(201);

      // Launched, it reads the same shared contract a CUSTOM site does.
      expect(
        (
          await http()
            .get('/api/website/venue')
            .set('Host', saasHost)
            .expect(200)
        ).body,
      ).toMatchObject({
        mode: 'SAAS',
        site: null,
        profile: { name: `Restaurant S ${tag}` },
        capabilities: { onlinePayments: false, reservations: false },
      });
      await http().get('/api/menu').set('Host', saasHost).expect(200);
      expect(
        (await http().get('/api/tables').set('Host', saasHost).expect(200))
          .body,
      ).toEqual([]);
      // Neither mode can take payments without the commercial feature.
      await order(saasHost).expect(403);

      // The operator switch means the same thing for either renderer.
      for (const [id, h] of [
        [venues.s.id, saasHost],
        [venues.a.id, host('a')],
      ]) {
        await http()
          .put(`/platform/venues/${id}/website-capabilities/MENU`)
          .set(platform())
          .send({ enabled: false })
          .expect(200);
        await http().get('/api/menu').set('Host', h).expect(404);
        await http().get('/api/website/venue/menu').set('Host', h).expect(404);
        expect(
          (await http().get('/api/website/venue').set('Host', h).expect(200))
            .body.capabilities.menu,
        ).toBe(false);
        await http()
          .put(`/platform/venues/${id}/website-capabilities/MENU`)
          .set(platform())
          .send({ enabled: true })
          .expect(200);
      }
      // The generic renderer honours it too.
      await http()
        .put(`/platform/venues/${venues.s.id}/website-capabilities/MENU`)
        .set(platform())
        .send({ enabled: false })
        .expect(200);
      expect(
        (
          await http()
            .get('/api/website/menu')
            .set('Host', saasHost)
            .expect(200)
        ).body,
      ).toMatchObject({ enabled: false, categories: [] });
      await http()
        .put(`/platform/venues/${venues.s.id}/website-capabilities/MENU`)
        .set(platform())
        .send({ enabled: true })
        .expect(200);

      // The generic page contract is unchanged: CUSTOM hosts get the marker only.
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
        // A already holds table1 for Nov 2 from the anonymous booking above.
        // Distinct days preserve the approved whole-day occupancy contract.
        const res = await order(host(k), {
          selectedDate: k === 'a' ? '2026-11-03' : '2026-11-02',
        })
          .set('Cookie', cookie)
          .expect(201);
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
      await http().get('/api/website/venue').set('Host', host('b')).expect(403);
      await order(host('b')).expect(403);
      await http()
        .get('/api/website/bootstrap')
        .set('Host', host('b'))
        .expect(404);
      // A is unaffected.
      await http().get('/api/website/venue').set('Host', host('a')).expect(200);
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
        .post(`/customer/venues/${c.id}/catalog/mutations`)
        .set(ownerAuth(c.token))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: categoryId,
          expectedRevision: 0,
          patch: { nameKa: 'ცხელი', nameEn: 'Hot dishes' },
        })
        .expect(200);
      await http()
        .post(`/customer/venues/${c.id}/catalog/mutations`)
        .set(ownerAuth(c.token))
        .send({
          mutationId: randomUUID(),
          entityType: 'SUBCATEGORY',
          operation: 'UPSERT',
          entityId: subcategoryId,
          expectedRevision: 0,
          patch: { categoryId, nameKa: 'მწვადი', nameEn: 'Grill' },
        })
        .expect(200);
      await http()
        .post(`/customer/venues/${c.id}/catalog/mutations`)
        .set(ownerAuth(c.token))
        .send({
          mutationId: randomUUID(),
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: itemId,
          expectedRevision: 0,
          patch: {
            subcategoryId,
            nameKa: 'ღორის მწვადი',
            nameEn: 'Pork mtsvadi',
            price: 24,
            enabled: true,
          },
        })
        .expect(200);
      await http()
        .post(`/customer/venues/${c.id}/catalog/mutations`)
        .set(ownerAuth(c.token))
        .send({
          mutationId: randomUUID(),
          entityType: 'VARIANT',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: {
            menuItemId: itemId,
            price: 32,
            size: 1,
          },
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
          .get('/api/website/venue/menu')
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
        // A .localhost name is not public, and no frontend identity is
        // recorded yet, so no local URL is invented either.
        publicUrl: null,
        localFrontend: { state: 'NO_SITE_KEY', hostname: cHost, url: null },
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
        .post(`/customer/venues/${d.id}/catalog/mutations`)
        .set(ownerAuth(d.token))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'ახალი', nameEn: 'New' },
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
              .get('/api/website/venue/menu')
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
      // Local frontends behind a host-preserving /api proxy to this backend,
      // one dev server per custom frontend, each on its own port.
      const frontend = () =>
        nodeHttp.createServer((req, res) => {
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
      const listen = async (server: nodeHttp.Server) => {
        await new Promise<void>((resolve) =>
          server.listen(0, '127.0.0.1', resolve),
        );
        return (server.address() as AddressInfo).port;
      };
      const siteA = frontend();
      const siteB = frontend();
      const portA = await listen(siteA);
      const portB = await listen(siteB);
      const view = async (k: 'a' | 'b') =>
        (
          await http()
            .get(`/platform/venues/${venues[k].id}/custom-website`)
            .set(platform())
            .expect(200)
        ).body;
      const check = (k: 'a' | 'b') =>
        http()
          .post(`/platform/venues/${venues[k].id}/custom-website/check`)
          .set(platform());

      // Only A is mapped. The former global port is set to B's port and must
      // not be used for anyone: it is reported as stale instead.
      process.env.CUSTOM_WEBSITE_LOCAL_FRONTENDS = `custom-a-web=${portA}`;
      process.env.CUSTOM_WEBSITE_DEV_PORT = String(portB);
      try {
        const a = await view('a');
        expect(a).toMatchObject({
          status: 'ACTIVE',
          primaryDomain: host('a'),
          publicUrl: null,
          localFrontend: {
            state: 'CONFIGURED',
            siteKey: 'custom-a-web',
            hostname: host('a'),
            port: portA,
            url: `http://${host('a')}:${portA}/`,
            source: 'CUSTOM_WEBSITE_LOCAL_FRONTENDS',
          },
        });
        expect(a.localFrontend.problems).toContain(
          'CUSTOM_WEBSITE_DEV_PORT is no longer read; map each frontend in CUSTOM_WEBSITE_LOCAL_FRONTENDS',
        );
        // The domain never carries the port.
        expect(a.domains.map((d: any) => d.hostname)).toEqual([host('a')]);
        expect((await view('b')).localFrontend).toMatchObject({
          state: 'NOT_CONFIGURED',
          port: null,
          url: null,
        });

        // Support may look, not trigger outbound requests.
        await http()
          .post(`/platform/venues/${venues.a.id}/custom-website/check`)
          .set(platform('support-token'))
          .expect(403);
        const checkA = (await check('a').expect(200)).body;
        expect(checkA).toMatchObject({
          availability: 'REACHABLE',
          hostname: host('a'),
          url: a.localFrontend.url,
          frontend: { status: 200 },
          api: { state: 'OK' },
        });
        expect(Date.parse(checkA.checkedAt)).toBeGreaterThan(
          Date.now() - 60_000,
        );
        await check('a').expect(429);

        // Unmapped B: refused as not configured, never sent to a guessed port.
        const unmapped = await check('b').expect(409);
        expect(unmapped.body.message).toContain(
          'Local frontend for custom-b-web is not configured',
        );

        // Mapping B gives it its own URL without moving A.
        process.env.CUSTOM_WEBSITE_LOCAL_FRONTENDS = `custom-a-web=${portA},custom-b-web=${portB}`;
        expect((await view('a')).localFrontend.url).toBe(
          `http://${host('a')}:${portA}/`,
        );
        const b = await view('b');
        expect(b.localFrontend.url).toBe(`http://${host('b')}:${portB}/`);
        const checkB = (await check('b').expect(200)).body;
        expect(checkB).toMatchObject({
          availability: 'REACHABLE',
          url: `http://${host('b')}:${portB}/`,
          frontend: { status: 200 },
        });
        // B's Trial ended earlier in this suite: its site answers, the shared
        // backend refuses to serve it, and never answers with A's data.
        expect(checkB.api.state).toBe('FAILED');
        expect(checkB.api.detail).toBe('/api answered 403');

        // Owners see status and domains, never local development config.
        const owner = JSON.stringify(
          (
            await http()
              .get(`/customer/venues/${venues.a.id}/website`)
              .set({ Authorization: `Bearer ${owners.a}` })
              .expect(200)
          ).body,
        );
        expect(owner).not.toContain('localFrontend');
        expect(owner).not.toContain('CUSTOM_WEBSITE');
        expect(owner).not.toContain(String(portA));
      } finally {
        await new Promise((resolve) => siteA.close(resolve));
        await new Promise((resolve) => siteB.close(resolve));
      }

      // Configured ACTIVE, yet nothing answers: the two are reported apart.
      // (A fresh service instance, so the per-Venue rate limit is not hit.)
      const down = await new CustomWebsiteService(
        db,
        new VenueEntitlementsService(db),
        {
          get: (key: string) =>
            key === 'CUSTOM_WEBSITE_LOCAL_FRONTENDS'
              ? `custom-a-web=${portA}`
              : undefined,
        } as unknown as ConfigService,
      ).checkRuntime(venues.a.id);
      expect(down).toMatchObject({
        availability: 'UNREACHABLE',
        frontend: { status: null, detail: 'Connection refused' },
      });
      expect(
        (
          await db.customWebsiteBinding.findUniqueOrThrow({
            where: { venueId: venues.a.id },
          })
        ).status,
      ).toBe('ACTIVE');
      // Only CUSTOM Venues, only their own registered domains.
      await http()
        .post(`/platform/venues/${venues.s.id}/custom-website/check`)
        .set(platform())
        .expect(409);
      delete process.env.CUSTOM_WEBSITE_LOCAL_FRONTENDS;
      delete process.env.CUSTOM_WEBSITE_DEV_PORT;
    });

    it('keeps domains port-free and local development out of production', async () => {
      const g = await makeVenue('Custom G prod', 'WEBSITE_ONLY');
      const gLocal = `custom-g-${tag}.localhost`;
      const gPublic = `custom-g-${tag}.invalid`;
      await http()
        .put(`/platform/venues/${g.id}/website`)
        .set(platform())
        .send({ mode: 'CUSTOM' })
        .expect(200);
      // Scheme and path are refused; a port is not part of the domain.
      for (const bad of [
        `http://${gLocal}:5174/path`,
        `${gLocal}/path`,
        `https://${gLocal}`,
      ])
        await http()
          .post(`/platform/venues/${g.id}/domains`)
          .set(platform())
          .send({ hostname: bad })
          .expect(400);
      const stored = (
        await http()
          .post(`/platform/venues/${g.id}/domains`)
          .set(platform())
          .send({ hostname: `${gLocal}:5174` })
          .expect(201)
      ).body;
      expect(stored.hostname).toBe(gLocal);
      await http()
        .post(`/platform/venues/${g.id}/domains`)
        .set(platform())
        .send({ hostname: gPublic })
        .expect(201);
      await http()
        .put(`/platform/venues/${g.id}/custom-website`)
        .set(platform())
        .send({ siteKey: 'custom-g-web', status: 'ACTIVE' })
        .expect(200);
      expect(
        (
          await db.venueDomain.findMany({
            where: { venueId: g.id },
            orderBy: { hostname: 'asc' },
          })
        ).map((d) => d.hostname),
      ).toEqual([gPublic, gLocal].sort());

      const env: Record<string, string> = {
        CUSTOM_WEBSITE_LOCAL_FRONTENDS: 'custom-g-web=5174',
        CUSTOM_WEBSITE_DEV_PORT: '5176',
      };
      const service = (nodeEnv: string) =>
        new CustomWebsiteService(db, new VenueEntitlementsService(db), {
          get: (key: string) => (key === 'NODE_ENV' ? nodeEnv : env[key]),
        } as unknown as ConfigService);

      // Development: the public domain stays the primary identity; the local
      // frontend is the .localhost domain plus the mapped port.
      const dev = await service('development').platformView(g.id);
      expect(dev).toMatchObject({
        primaryDomain: gPublic,
        publicUrl: `https://${gPublic}/`,
        localFrontend: { url: `http://${gLocal}:5174/` },
      });

      // Production: no local frontend, no port, no dev setting anywhere.
      const prod = await service('production').platformView(g.id);
      expect(prod).toMatchObject({
        primaryDomain: gPublic,
        publicUrl: `https://${gPublic}/`,
      });
      expect(prod).not.toHaveProperty('localFrontend');
      const text = JSON.stringify(prod);
      for (const leak of ['5174', '5176', 'localFrontend', 'CUSTOM_WEBSITE'])
        expect(text).not.toContain(leak);
      // The production check goes to the public name only, and the existing
      // public-address rules apply (this name does not resolve).
      const checked = await service('production').checkRuntime(g.id);
      expect(checked).toMatchObject({
        hostname: gPublic,
        url: `https://${gPublic}/`,
        availability: 'UNREACHABLE',
        api: { state: 'NOT_CHECKED' },
      });
    }, 20_000);

    it('keeps hours, contact and gallery as Venue data both renderers read live', async () => {
      const f = await makeVenue('Custom F info', 'WEBSITE_ONLY');
      const fHost = `custom-f-${tag}.vynic.localhost`;
      await http()
        .put(`/platform/venues/${f.id}/website`)
        .set(platform())
        .send({ mode: 'CUSTOM' })
        .expect(200);
      await http()
        .post(`/platform/venues/${f.id}/domains`)
        .set(platform())
        .send({ hostname: fHost })
        .expect(201);
      const hours = [
        { day: 1, opens: '10:00', closes: '22:00' },
        { day: 6, opens: '12:00', closes: '02:00' },
      ];
      // The CUSTOM owner edits the same Venue data a SAAS owner does.
      const settings = (
        await http()
          .put(`/customer/venues/${f.id}/website/public-info`)
          .set(ownerAuth(f.token))
          .send({
            expectedRevision: 0,
            workingHours: hours,
            contactEmail: 'Hello@Example.test',
            socials: [{ label: 'Instagram', url: 'https://instagram.com/f' }],
          })
          .expect(200)
      ).body;
      expect(settings.shared).toMatchObject({
        revision: 1,
        workingHours: hours,
        contactEmail: 'hello@example.test',
      });
      expect(
        settings.capabilities.find((c: any) => c.key === 'HOURS'),
      ).toMatchObject({ available: true, live: true });
      // A stale editor is refused rather than overwriting.
      await http()
        .put(`/customer/venues/${f.id}/website/public-info`)
        .set(ownerAuth(f.token))
        .send({ expectedRevision: 0, contactEmail: '' })
        .expect(409);
      // Unknown fields and SAAS page fields are not Venue data.
      await http()
        .put(`/customer/venues/${f.id}/website/public-info`)
        .set(ownerAuth(f.token))
        .send({ expectedRevision: 1, heroTitle: 'x' })
        .expect(400);
      // Another owner cannot write it.
      await http()
        .put(`/customer/venues/${f.id}/website/public-info`)
        .set(ownerAuth(owners.a))
        .send({ expectedRevision: 1, contactEmail: '' })
        .expect(404);

      expect(
        (await http().get('/api/website/venue').set('Host', fHost).expect(200))
          .body,
      ).toMatchObject({
        mode: 'CUSTOM',
        info: {
          workingHours: hours,
          contactEmail: 'hello@example.test',
          socials: [{ label: 'Instagram', url: 'https://instagram.com/f' }],
        },
        capabilities: { hours: true, gallery: false },
      });

      // Operator policy: hours off means off in public and for owner edits.
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/HOURS`)
        .set(platform('support-token'))
        .send({ enabled: false })
        .expect(403);
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/HOURS`)
        .set(platform())
        .send({ enabled: false })
        .expect(200);
      expect(
        (await http().get('/api/website/venue').set('Host', fHost).expect(200))
          .body,
      ).toMatchObject({
        info: { workingHours: [] },
        capabilities: { hours: false },
      });
      await http()
        .put(`/customer/venues/${f.id}/website/public-info`)
        .set(ownerAuth(f.token))
        .send({ expectedRevision: 1, workingHours: [] })
        .expect(403);
      // Other fields still save while hours are off.
      await http()
        .put(`/customer/venues/${f.id}/website/public-info`)
        .set(ownerAuth(f.token))
        .send({ expectedRevision: 1, workingHours: hours, mapUrl: '' })
        .expect(200);
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: f.id, action: 'venue.website_capability_changed' },
        }),
      ).toMatchObject({
        platformUserId: admin.id,
        metadata: { capability: 'HOURS', from: true, to: false },
      });

      // No impossible switches: payments need the package, unbuilt ones do not exist.
      const states = (
        await http()
          .get(`/platform/venues/${f.id}/website-capabilities`)
          .set(platform('support-token'))
          .expect(200)
      ).body;
      expect(states.map((c: any) => c.key)).toEqual([
        'MENU',
        'HOURS',
        'RESERVATIONS',
        'GALLERY',
        'CUSTOMER_ACCOUNTS',
        'ONLINE_PAYMENTS',
        'EVENTS',
        'BANQUETS',
        'ONLINE_ORDERING',
      ]);
      expect(
        states.find((c: any) => c.key === 'ONLINE_PAYMENTS'),
      ).toMatchObject({ commercial: false, canEnable: false });
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/ONLINE_PAYMENTS`)
        .set(platform())
        .send({ enabled: false })
        .expect(200);
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/ONLINE_PAYMENTS`)
        .set(platform())
        .send({ enabled: true })
        .expect(409);
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/EVENTS`)
        .set(platform())
        .send({ enabled: true })
        .expect(400);

      // A SAAS owner's hours are the same kind of data, live without publishing.
      const saasInfo = (
        await http()
          .get(`/customer/venues/${venues.s.id}/website`)
          .set(ownerAuth(owners.s))
          .expect(200)
      ).body.shared;
      await http()
        .put(`/customer/venues/${venues.s.id}/website/public-info`)
        .set(ownerAuth(owners.s))
        .send({ expectedRevision: saasInfo.revision, workingHours: hours })
        .expect(200);
      expect(
        (
          await http()
            .get('/api/website/bootstrap')
            .set('Host', saasHost)
            .expect(200)
        ).body.content.workingHours,
      ).toEqual(hours);
      expect(
        (
          await http()
            .get('/api/website/venue')
            .set('Host', saasHost)
            .expect(200)
        ).body.info.workingHours,
      ).toEqual(hours);
    });

    it('offers website sign-in only where customer accounts are available', async () => {
      // Guards run before CSRF: 403 here means the host admits accounts.
      await http()
        .post('/api/auth/signin')
        .set('Host', host('a'))
        .send({ identifier: 'x', password: 'y' })
        .expect(403);
      await http()
        .put(
          `/platform/venues/${venues.a.id}/website-capabilities/CUSTOMER_ACCOUNTS`,
        )
        .set(platform())
        .send({ enabled: false })
        .expect(200);
      for (const route of ['/api/auth/signin', '/api/auth/signup'])
        await http().post(route).set('Host', host('a')).send({}).expect(404);
      await http()
        .get('/api/user/reservations')
        .set('Host', host('a'))
        .set('Cookie', await cookieFor(`customer-${tag}@test.invalid`))
        .expect(404);
      await http()
        .put(
          `/platform/venues/${venues.a.id}/website-capabilities/CUSTOMER_ACCOUNTS`,
        )
        .set(platform())
        .send({ enabled: true })
        .expect(200);
      await http()
        .post('/api/auth/signin')
        .set('Host', `unknown-${tag}.vynic.localhost`)
        .send({})
        .expect(404);
    });

    it('WEB05 records only public build fingerprints with operator authorization, exact retry and immutable audit', async () => {
      const venueA = venues.a as { id: string };
      const path = `/platform/venues/${venueA.id}/custom-website`;
      const buildId = 'a'.repeat(64);
      await http()
        .put(path)
        .set(platform('support-token'))
        .send({ expectedBuildId: buildId })
        .expect(403);
      await http()
        .put(path)
        .set(ownerAuth(owners.a))
        .send({ expectedBuildId: buildId })
        .expect(401);
      await http()
        .put(path)
        .set(platform())
        .send({ expectedBuildId: 'not-a-build' })
        .expect(400);
      const saved = (
        await http()
          .put(path)
          .set(platform())
          .send({ expectedBuildId: buildId })
          .expect(200)
      ).body as Record<string, unknown>;
      expect(saved.expectedBuildId).toBe(buildId);
      expect(saved.publicIdentity).toBe(websiteVenueIdentity(venueA.id));
      const events = await db.platformAuditEvent.count({
        where: {
          targetId: venueA.id,
          action: 'venue.custom_website_build_changed',
        },
      });
      const retry = (
        await http()
          .put(path)
          .set(platform())
          .send({ expectedBuildId: buildId })
          .expect(200)
      ).body as Record<string, unknown>;
      expect(retry.updatedAt).toBe(saved.updatedAt);
      expect(
        await db.platformAuditEvent.count({
          where: {
            targetId: venueA.id,
            action: 'venue.custom_website_build_changed',
          },
        }),
      ).toBe(events);
      await http()
        .put(path)
        .set(platform())
        .send({ siteKey: 'different-reviewed-web' })
        .expect(200);
      expect(
        (
          await db.customWebsiteBinding.findUniqueOrThrow({
            where: { venueId: venueA.id },
          })
        ).expectedBuildId,
      ).toBeNull();
      await http()
        .put(path)
        .set(platform())
        .send({ siteKey: 'custom-a-web', expectedBuildId: buildId })
        .expect(200);
    });

    it('WEB05 HTTP observation distinguishes same-name Venues, recorded builds and tracking statuses without mutating them', async () => {
      const venueA = venues.a as { id: string };
      const venueB = venues.b as { id: string };
      let fixtureError: unknown;
      const html = '<html>WEB05 independently built synthetic page</html>';
      const buildId = 'a'.repeat(64);
      let wrongVenue = false;
      let changeDuringRead: null | 'BUILD' | 'DOMAIN' = null;
      let rootGate: Promise<void> | null = null;
      let enteredRoot: (() => void) | null = null;
      const server = nodeHttp.createServer((req, res) => {
        void (async () => {
          if (req.url === '/api/website/venue') {
            const response = await http()
              .get('/api/website/venue')
              .set('Host', host(wrongVenue ? 'b' : 'a'));
            res.statusCode = response.status;
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify(response.body));
          } else if (req.url === '/vynic-site-manifest.json') {
            if (changeDuringRead === 'BUILD')
              await db.customWebsiteBinding.update({
                where: { venueId: venueA.id },
                data: { expectedBuildId: 'b'.repeat(64) },
              });
            if (changeDuringRead === 'DOMAIN')
              await db.venueDomain.updateMany({
                where: { venueId: venueA.id, hostname: host('a') },
                data: { status: 'DISABLED' },
              });
            res.setHeader('content-type', 'application/json');
            res.end(
              JSON.stringify({
                schemaVersion: 1,
                renderer: 'CUSTOM',
                siteKey: 'custom-a-web',
                buildId,
                htmlDigest: createHash('sha256').update(html).digest('hex'),
              }),
            );
          } else {
            if (rootGate) {
              enteredRoot?.();
              await rootGate;
            }
            res.setHeader('content-type', 'text/html');
            res.end(html);
          }
        })().catch((error: unknown) => {
          fixtureError = error;
          res.statusCode = 500;
          res.end('Synthetic fixture failed');
        });
      });
      await new Promise<void>((resolve) =>
        server.listen(0, '127.0.0.1', resolve),
      );
      const port = (server.address() as AddressInfo).port;
      const service = () =>
        new CustomWebsiteService(
          db,
          new VenueEntitlementsService(db),
          new ConfigService({
            NODE_ENV: 'development',
            CUSTOM_WEBSITE_LOCAL_FRONTENDS: `custom-a-web=${port}`,
          }),
        );
      try {
        await db.venue.updateMany({
          where: { id: { in: [venueA.id, venueB.id] } },
          data: { name: 'Identical public restaurant name' },
        });
        for (const status of ['ACTIVE', 'SETUP_PENDING', 'ERROR'] as const) {
          await db.customWebsiteBinding.update({
            where: { venueId: venueA.id },
            data: { status, siteKey: 'custom-a-web', expectedBuildId: buildId },
          });
          const result = await service().checkRuntime(venueA.id);
          expect(result.api.state).toBe('OK');
          expect(result.build.state).toBe('VERIFIED');
          expect(result.facts).toMatchObject({
            commercial: true,
            domainRegistration: true,
            rendererDeployed: true,
            bindingIdentityVerified: true,
            publicationLive: status === 'ACTIVE',
          });
          expect(result.environment).toBe('LOCAL_DEVELOPMENT');
          expect(
            (
              await db.customWebsiteBinding.findUniqueOrThrow({
                where: { venueId: venueA.id },
              })
            ).status,
          ).toBe(status);
        }
        await db.customWebsiteBinding.update({
          where: { venueId: venueB.id },
          data: { siteKey: 'custom-a-web', status: 'ACTIVE' },
        });
        await db.venueSubscription.update({
          where: { venueId: venueB.id },
          // The earlier expiry case reconciles B to SUSPENDED. Renew only this
          // isolated fixture for the independent same-name identity assertion.
          data: {
            status: 'TRIAL',
            trialEndsAt: new Date(Date.now() + 86400000),
            trialEndedAt: null,
            suspendedAt: null,
            suspendedFrom: null,
          },
        });
        wrongVenue = true;
        const wrong = await service().checkRuntime(venueA.id);
        expect(wrong.api.state).toBe('WRONG_SITE');
        expect(wrong.facts.bindingIdentityVerified).toBe(false);
        expect(wrong.facts.publicationLive).toBe(false);
        wrongVenue = false;
        for (const change of ['BUILD', 'DOMAIN'] as const) {
          await db.customWebsiteBinding.update({
            where: { venueId: venueA.id },
            data: { status: 'ACTIVE', expectedBuildId: buildId },
          });
          await db.venueDomain.updateMany({
            where: { venueId: venueA.id, hostname: host('a') },
            data: { status: 'ACTIVE' },
          });
          changeDuringRead = change;
          const stale = await service().checkRuntime(venueA.id);
          expect(stale.observationCurrent).toBe(false);
          expect(stale.facts.bindingIdentityVerified).toBe(false);
          expect(stale.facts.publicationLive).toBe(false);
        }
        // Disabled domains are not contacted by another check.
        changeDuringRead = null;
        await expect(service().checkRuntime(venueA.id)).rejects.toThrow(
          /active domain|NO_LOCAL_DOMAIN|Not configured/i,
        );
        await db.venueDomain.updateMany({
          where: { venueId: venueA.id, hostname: host('a') },
          data: { status: 'ACTIVE' },
        });
        let releaseRoot!: () => void;
        rootGate = new Promise<void>((resolve) => {
          releaseRoot = resolve;
        });
        const entered = new Promise<void>((resolve) => {
          enteredRoot = resolve;
        });
        const oneService = service();
        const first = oneService.checkRuntime(venueA.id);
        await entered;
        const now = Date.now();
        const clock = jest.spyOn(Date, 'now').mockReturnValue(now + 6000);
        try {
          await expect(oneService.checkRuntime(venueA.id)).rejects.toThrow(
            /check just ran/i,
          );
        } finally {
          clock.mockRestore();
          releaseRoot();
        }
        expect((await first).facts.bindingIdentityVerified).toBe(true);
        expect(fixtureError).toBeUndefined();
      } finally {
        await new Promise<void>((resolve, reject) =>
          server.close((error) => (error ? reject(error) : resolve())),
        );
      }
    });
  },
);
