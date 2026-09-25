import { HostnameRequestsService } from '../website/core/hostname-requests';
import { SubscriptionService } from '../subscriptions/subscription.service';
import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import sharp from 'sharp';
import { PrismaService } from '../prisma.service';
import { CustomerAuth, CustomerGuard } from './customer-auth';
import { CustomerService } from './customer.service';
import {
  CustomerController,
  CustomerAuthController,
} from './customer.controller';
import { CustomerWebsiteController } from './customer-website.controller';
import { CustomerPaymentsController } from './customer-payments.controller';
import { CustomerCatalogController } from './restaurant-foundation.controller';
import { RestaurantFoundationService } from './restaurant-foundation.service';
import { OwnerInvitationsService } from './owner-invitations.service';
import {
  CustomerOwnerInvitationsController,
  PlatformOwnerInvitationsController,
} from './owner-invitations.controller';
import {
  OnboardingRequestsService,
  PublicAccessRequestsController,
  PlatformAccessRequestsController,
  CustomerTrialRequestsController,
} from './onboarding-requests';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { PlatformCommercialController } from '../platform/platform-commercial.controller';
import { PlatformAuthService } from '../platform/platform-auth.service';
import { PlatformAuditService } from '../platform/platform-audit.service';
import { PlatformVenueConfigService } from '../platform/platform-venue-config.service';
import { PlatformDirectoryService } from '../platform/platform-directory.service';
import { PlatformCatalogController } from '../platform/platform-catalog.controller';
import { PlanCatalogService } from '../platform/plan-catalog.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { DeviceEnrollmentService } from '../edge/device-enrollment.service';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import {
  CommercialLifecycleService,
  DOMAIN_GRACE_MS,
} from '../entitlements/commercial-lifecycle.service';
import { WebsiteCoreService } from '../website/core/website-core.service';
import { WebsiteMenuService } from '../website/core/website-menu.service';
import { WebsiteLogoService } from '../website/core/website-logo.service';
import { WebsitePreviewTokens } from '../website/core/website-preview';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';
import { emptyWebsiteContent } from '../website/core/website-content';
import { PaymentIntegrationsService } from '../payment-integrations/payment-integrations.service';

const url = process.env.COMMERCIAL_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Commercial Access Hardening — disposable PostgreSQL and real HTTP',
  () => {
    let db: PrismaService,
      app: any,
      access: VenueEntitlementsService,
      commercial: PlatformCommercialService,
      config: PlatformVenueConfigService,
      invitations: OwnerInvitationsService,
      media: WebsiteLogoService,
      core: WebsiteCoreService;
    let actor: any,
      operator: string,
      root: string,
      a: any,
      b: any,
      websitePlan: any,
      posPlan: any;
    const tag = randomUUID().slice(0, 8);
    const http = () => request(app.getHttpServer());
    const auth = (token: string) => ({ Authorization: `Bearer ${token}` });
    const future = () => new Date(Date.now() + 86400000).toISOString();
    const draft = (slug: string) => ({
      ...emptyWebsiteContent,
      slug,
      heroTitle: 'Our restaurant',
    });
    const base = (v: any) => `/customer/venues/${v.id}`;
    const assign = async (v: any, plan: any, status = 'TRIAL') => {
      const lifecycle = new SubscriptionService(db);
      // Operators choose the website implementation whenever WEBSITE is sold.
      const websiteMode = (await db.planFeature.count({
        where: { planId: plan.id, feature: { key: 'WEBSITE' } },
      }))
        ? 'SAAS'
        : undefined;
      const existing = await db.venueSubscription.findUnique({
        where: { venueId: v.id },
      });
      if (status === 'SUSPENDED')
        return lifecycle.action(actor, v.id, {
          action: 'SUSPEND',
          confirm: true,
          reason: 'Regression fixture suspension',
        });
      if (existing?.billingManaged) {
        const assignment = await db.venuePlanAssignment.findUnique({
          where: { venueId: v.id },
        });
        if (
          status === 'ACTIVE' &&
          existing.status === 'ACTIVE' &&
          assignment?.planId === plan.id
        )
          return existing;
        await lifecycle.action(actor, v.id, {
          action: 'CANCEL_NOW',
          confirm: true,
          reason: 'End previous regression fixture agreement',
        });
        return lifecycle.action(actor, v.id, {
          action: status === 'TRIAL' ? 'TRIAL' : 'GRANT_ACTIVE',
          planId: plan.id,
          trialEndsAt: future(),
          confirm: true,
          reason: 'Start next regression scenario',
          websiteMode,
        });
      }
      return http()
        .put(`/platform/venues/${v.id}/subscription`)
        .set(auth(operator))
        .send({
          planId: plan.id,
          status,
          trialEndsAt: future(),
          note: 'Regression fixture assignment',
          websiteMode,
        })
        .expect(200);
    };
    const prepare = async (label: string) => {
      const result = await invitations.provision(actor, {
        organizationName: label,
        name: label,
        email: `${label}-${tag}@test.invalid`,
      });
      const accepted = await invitations.accept(
        {
          token: result.invitationPath.split('=')[1],
          displayName: label,
          password: 'test-only-password',
        },
        label,
      );
      return {
        ...result.venue,
        token: accepted.access_token,
        accountId: accepted.account.id,
      };
    };
    beforeAll(async () => {
      const target = new URL(url!);
      if (
        target.hostname !== '127.0.0.1' ||
        target.port !== '55437' ||
        target.pathname !== '/vynic_commercial_test'
      )
        throw Error('Only isolated commercial test database allowed');
      process.env.JWT_SECRET = 'commercial-test-only-signing-key';
      process.env.PLATFORM_JWT_SECRET = process.env.JWT_SECRET;
      process.env.COOKIE_ENCRYPTION_KEY = 'commercial-test-only-vault-key';
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = Buffer.alloc(32, 7).toString(
        'base64',
      );
      db = new PrismaService({ datasourceUrl: url });
      root = await mkdtemp('/tmp/vynic-commercial-media-');
      const settings = new ConfigService({
        WEBSITE_MEDIA_DIR: root,
        SAAS_WEBSITE_BASE_DOMAIN: 'vynic.test',
        NODE_ENV: 'test',
      });
      const jwt = new JwtService(),
        limiter = new EnrollmentRateLimiter(),
        audit = new PlatformAuditService(db);
      const credentials = new DeviceCredentialService(db);
      const enrollments = new DeviceEnrollmentService(
        db,
        credentials,
        audit,
        limiter,
      );
      access = new VenueEntitlementsService(db);
      commercial = new PlatformCommercialService(db, new StaffPinVault(db));
      const owners = new CustomerService(
        db,
        access,
        commercial,
        enrollments,
        settings,
      );
      const customerAuth = new CustomerAuth(db, jwt, limiter);
      invitations = new OwnerInvitationsService(db, customerAuth, limiter);
      const platformAuth = new PlatformAuthService(db, jwt, settings);
      const user = await db.platformUser.create({
        data: {
          email: `operator-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: 'unused',
        },
      });
      actor = { platformUserId: user.id, role: 'SUPER_ADMIN' };
      operator = await jwt.signAsync(
        { sub: user.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
          expiresIn: 3600,
        },
      );
      const directory = new PlatformDirectoryService(db, audit);
      config = new PlatformVenueConfigService(db, access, directory, audit);
      media = new WebsiteLogoService(settings, db);
      const menu = new WebsiteMenuService(db);
      core = new WebsiteCoreService(
        db,
        access,
        new WebsiteTenantService(db, settings),
        settings,
        menu,
      );
      const providers: any[] = [
        [PrismaService, db],
        [ConfigService, settings],
        [CustomerAuth, customerAuth],
        [CustomerService, owners],
        [PlatformAuthService, platformAuth],
        [OwnerInvitationsService, invitations],
        [
          OnboardingRequestsService,
          new OnboardingRequestsService(
            db,
            limiter,
            invitations,
            owners,
            commercial,
          ),
        ],
        [PlatformCommercialService, commercial],
        [PlatformAuditService, audit],
        [PlatformVenueConfigService, config],
        [PlanCatalogService, new PlanCatalogService(db)],
        [WebsiteCoreService, core],
        [WebsiteMenuService, menu],
        [WebsiteLogoService, media],
        [WebsitePreviewTokens, new WebsitePreviewTokens(db, jwt)],
        [
          PaymentIntegrationsService,
          new PaymentIntegrationsService(db, access),
        ],
        [
          RestaurantFoundationService,
          new RestaurantFoundationService(db, owners, access),
        ],
      ];
      const module = await Test.createTestingModule({
        controllers: [
          CustomerController,
          CustomerAuthController,
          CustomerWebsiteController,
          CustomerPaymentsController,
          CustomerCatalogController,
          CustomerOwnerInvitationsController,
          PlatformOwnerInvitationsController,
          PublicAccessRequestsController,
          PlatformAccessRequestsController,
          CustomerTrialRequestsController,
          PlatformCommercialController,
          PlatformCatalogController,
        ],
        providers: [
          HostnameRequestsService,
          ...providers.map(([provide, useValue]) => ({ provide, useValue })),
          CustomerGuard,
        ],
      }).compile();
      app = module.createNestApplication();
      await app.init();
      websitePlan = await db.plan.findUniqueOrThrow({
        where: { key: 'WEBSITE_ONLY' },
      });
      posPlan = await db.plan.findUniqueOrThrow({ where: { key: 'POS' } });
      b = await prepare('other');
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      if (root) await rm(root, { recursive: true, force: true });
    });

    it('public requests create no account, Venue, subscription, domain, enrollment or media', async () => {
      const counts = async () =>
        Promise.all([
          db.customerAccount.count(),
          db.venue.count(),
          db.venueSubscription.count(),
          db.venueDomain.count(),
          db.deviceEnrollment.count(),
          db.websiteMediaAsset.count(),
        ]);
      const before = await counts();
      await http()
        .post('/customer/access-requests')
        .send({
          applicantName: 'Applicant',
          businessName: 'New restaurant',
          email: `applicant-${tag}@test.invalid`,
          phone: '+995555123456',
          requestedPlanId: websitePlan.id,
        })
        .expect(201);
      expect(await counts()).toEqual(before);
      await http()
        .post('/customer/auth/signup')
        .send({
          email: `signup-${tag}@test.invalid`,
          password: 'test-only-password',
        })
        .expect(403);
    });
    it('approval and invitation acceptance grant dashboard ownership but no package', async () => {
      const row = await db.onboardingRequest.findFirstOrThrow({
        where: { email: `applicant-${tag}@test.invalid` },
      });
      const reviewed = (
        await http()
          .post(`/platform/onboarding/requests/${row.id}/review`)
          .set(auth(operator))
          .send({ status: 'APPROVED' })
          .expect(201)
      ).body;
      expect(reviewed.prepared.venue.subscription).toBeUndefined();
      const registered = (
        await http()
          .post('/customer/invitations/register')
          .send({
            token: reviewed.prepared.invitationPath.split('=')[1],
            displayName: 'Owner',
            password: 'test-only-password',
          })
          .expect(201)
      ).body;
      a = {
        ...reviewed.prepared.venue,
        token: registered.access_token,
        accountId: registered.account.id,
      };
      const portal = (
        await http().get('/customer/portal').set(auth(a.token)).expect(200)
      ).body;
      expect(portal.venues[0]).toMatchObject({
        features: [],
        plan: null,
        subscription: { status: 'NO_PLAN' },
        venue: { loginCode: null },
        managers: [],
        devices: [],
      });
      expect(
        await db.venuePlanAssignment.findUnique({ where: { venueId: a.id } }),
      ).toBeNull();
      await http()
        .post(`/platform/onboarding/requests/${row.id}/review`)
        .set(auth(operator))
        .send({ status: 'APPROVED' })
        .expect(409);
    });
    it('NO_PLAN refuses all direct paid APIs while identity editing stays available', async () => {
      await db.venueWebsiteConfig.create({
        data: { venueId: a.id, mode: 'SAAS' },
      });
      await http()
        .put(`${base(a)}/profile`)
        .set(auth(a.token))
        .send({ name: 'New restaurant' })
        .expect(200);
      for (const path of [
        '/website',
        '/website/preview',
        '/website/menu',
        '/catalog',
        '/payments/bog',
      ])
        await http()
          .get(base(a) + path)
          .set(auth(a.token))
          .expect(403);
      for (const path of [
        '/website/publish',
        '/website/preview-session',
        '/enrollments',
      ])
        await http()
          .post(base(a) + path)
          .set(auth(a.token))
          .send({ expectedRevision: 0 })
          .expect(403);
      await http()
        .put(`${base(a)}/website/draft`)
        .set(auth(a.token))
        .send({ expectedRevision: 0, content: draft('new-' + tag) })
        .expect(403);
      await http()
        .post(`${base(a)}/managers`)
        .set(auth(a.token))
        .send({
          requestId: randomUUID(),
          username: 'manager',
          displayName: 'Manager',
          role: 'MANAGER',
          pin: '6789',
        })
        .expect(403);
      await http()
        .put(`${base(a)}/payments/bog`)
        .set(auth(a.token))
        .send({
          clientId: 'x',
          clientSecret: 'x',
          returnOrigin: 'https://x.test',
        })
        .expect(403);
      await http()
        .put(`${base(a)}/devices/${randomUUID()}/printers`)
        .set(auth(a.token))
        .send({})
        .expect(403);
      await expect(
        config.registerDomain(actor, a.id, `locked-${tag}.test`),
      ).rejects.toMatchObject({ status: 403 });
    });
    it('customers can request a trial but only an operator can activate its chosen plan', async () => {
      await http()
        .post(`${base(a)}/trial-requests`)
        .set(auth(a.token))
        .send({ requestedPlanId: websitePlan.id })
        .expect(201);
      expect(await access.effectiveFeatures(a.id)).toEqual([]);
      const row = await db.onboardingRequest.findFirstOrThrow({
        where: { requestedVenueId: a.id, status: 'PENDING' },
      });
      await http()
        .post(`/platform/onboarding/requests/${row.id}/review`)
        .set(auth(a.token))
        .send({ status: 'APPROVED' })
        .expect(401);
      await http()
        .post(`/platform/onboarding/requests/${row.id}/review`)
        .set(auth(operator))
        .send({
          status: 'APPROVED',
          planId: websitePlan.id,
          trialEndsAt: future(),
        })
        .expect(201);
      expect(await access.effectiveFeatures(a.id)).toEqual(['WEBSITE']);
      await config.enableCloudMenu(actor, a.id, true);
      await http()
        .put(`${base(a)}/website/draft`)
        .set(auth(a.token))
        .send({
          expectedRevision: 0,
          content: draft(
            (
              await db.venueWebsiteConfig.findUniqueOrThrow({
                where: { venueId: a.id },
              })
            ).assignedSlug!,
          ),
        })
        .expect(200);
      await http()
        .get(`${base(a)}/website/preview`)
        .set(auth(a.token))
        .expect(200);
      await http()
        .post(`${base(a)}/website/publish`)
        .set(auth(a.token))
        .send({ expectedRevision: 1 })
        .expect(201);
      await http()
        .post(`${base(a)}/website/logo`)
        .set(auth(a.token))
        .attach('file', Buffer.from('image'), 'test.png')
        .expect(403);
      await http()
        .post(`${base(a)}/enrollments`)
        .set(auth(a.token))
        .send({})
        .expect(403);
      await assign(b, posPlan);
      expect(await access.effectiveFeatures(b.id)).toEqual(['POS']);
      await http()
        .post(`${base(b)}/enrollments`)
        .set(auth(b.token))
        .send({})
        .expect(201);
      await http()
        .get(`${base(b)}/website/preview`)
        .set(auth(b.token))
        .expect(403);
    });
    it('expired trials suspend once, suppress client feature keys, stop public serving and release domains after grace', async () => {
      const deadline = new Date(Date.now() - 1000);
      await db.venueSubscription.update({
        where: { venueId: a.id },
        data: { trialEndsAt: deadline },
      });
      await Promise.all([
        access.effectiveFeatures(a.id),
        access.effectiveFeatures(a.id),
      ]);
      expect(await access.effectiveFeatures(a.id)).toEqual([]);
      expect(
        await db.platformAuditEvent.count({
          where: { targetId: a.id, action: 'venue.trial_expired' },
        }),
      ).toBe(1);
      await expect(
        core.bootstrap({
          host: `${(await db.venueWebsiteConfig.findUniqueOrThrow({ where: { venueId: a.id } })).assignedSlug}.vynic.test`,
        }),
      ).rejects.toMatchObject({ status: 404 });
      const domain = await db.venueDomain.findFirstOrThrow({
        where: { venueId: a.id },
      });
      expect(domain.releaseAfter).not.toBeNull();
      await new CommercialLifecycleService(db).reconcile(
        a.id,
        new Date(domain.releaseAfter!.getTime() + 1),
      );
      expect(await db.venueDomain.count({ where: { venueId: a.id } })).toBe(0);
      expect(
        await db.platformAuditEvent.count({
          where: { targetId: a.id, action: 'domain.released_after_grace' },
        }),
      ).toBe(1);
    });
    it('ACTIVE media quotas include unattached files and prohibit cross-Venue references', async () => {
      await assign(a, websitePlan, 'ACTIVE');
      await assign(b, websitePlan, 'ACTIVE');
      // Unchanged published content must reclaim its address after expiry released it.
      await http()
        .post(`${base(a)}/website/publish`)
        .set(auth(a.token))
        .send({ expectedRevision: 1 })
        .expect(201);
      expect(await db.venueDomain.count({ where: { venueId: a.id } })).toBe(1);
      // Assignment provisioned B as SAAS already.
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: b.id },
          })
        ).mode,
      ).toBe('SAAS');
      const image = await sharp({
        create: { width: 32, height: 32, channels: 3, background: '#123456' },
      })
        .png()
        .toBuffer();
      const uploaded = (
        await http()
          .post(`${base(a)}/website/logo`)
          .set(auth(a.token))
          .attach('file', image, 'logo.png')
          .expect(201)
      ).body;
      const asset = await db.websiteMediaAsset.findFirstOrThrow({
        where: { venueId: a.id },
      });
      expect(asset.byteSize).toBeGreaterThan(0);
      expect(asset.purpose).toBe('logo');
      await http()
        .put(`${base(b)}/website/draft`)
        .set(auth(b.token))
        .send({
          expectedRevision: 0,
          content: {
            ...draft(
              (
                await db.venueWebsiteConfig.findUniqueOrThrow({
                  where: { venueId: b.id },
                })
              ).assignedSlug!,
            ),
            logoUrl: uploaded.url,
          },
        })
        .expect(403);
      await db.plan.update({
        where: { id: websitePlan.id },
        data: { mediaQuotaFiles: 1 },
      });
      const uploads = await Promise.all(
        [0, 1].map(() =>
          http()
            .post(`${base(a)}/website/hero`)
            .set(auth(a.token))
            .attach('file', image, 'hero.png'),
        ),
      );
      expect(uploads.map((r) => r.status)).toEqual([403, 403]);
      await media.cleanup(new Date(Date.now() + 2 * 86400000));
      expect(
        await db.websiteMediaAsset.count({ where: { venueId: a.id } }),
      ).toBe(0);
      await expect(media.read(asset.storageKey)).rejects.toMatchObject({
        status: 404,
      });
      const raced = await Promise.all(
        [0, 1].map(() =>
          http()
            .post(`${base(a)}/website/hero`)
            .set(auth(a.token))
            .attach('file', image, 'hero.png'),
        ),
      );
      expect(raced.map((r) => r.status).sort()).toEqual([201, 403]);
      await media.cleanup(new Date(Date.now() + 2 * 86400000));
      await db.plan.update({
        where: { id: websitePlan.id },
        data: { mediaQuotaFiles: 50 },
      });
    });
    it('WEBSITE overrides close every draft/preview/menu/upload/publication API', async () => {
      await config.setFeatureOverride(actor, a.id, 'WEBSITE', 'DISABLED');
      for (const path of [
        '/website',
        '/website/preview',
        '/website/menu',
        '/catalog',
      ])
        await http()
          .get(base(a) + path)
          .set(auth(a.token))
          .expect(403);
      await http()
        .put(`${base(a)}/website/draft`)
        .set(auth(a.token))
        .send({ expectedRevision: 1, content: draft('off-' + tag) })
        .expect(403);
      await http()
        .put(`${base(a)}/website/menu`)
        .set(auth(a.token))
        .send({ items: [] })
        .expect(403);
      await http()
        .post(`${base(a)}/website/publish`)
        .set(auth(a.token))
        .send({ expectedRevision: 1 })
        .expect(403);
      await http()
        .post(`${base(a)}/website/hero`)
        .set(auth(a.token))
        .attach('file', Buffer.from('x'), 'x.png')
        .expect(403);
      await config.clearFeatureOverride(actor, a.id, 'WEBSITE');
    });
    it('adopts referenced legacy disk media with ownership and quota accounting', async () => {
      const v = await prepare('legacy-media');
      const key = `${randomUUID()}.webp`;
      await writeFile(`${root}/${key}`, Buffer.from('existing-asset'));
      await db.venueWebsiteConfig.create({
        data: {
          venueId: v.id,
          mode: 'SAAS',
          draft: {
            ...draft('legacy-' + tag),
            logoUrl: `/media/website-logos/${key}`,
          },
        },
      });
      await media.cleanup();
      expect(
        await db.websiteMediaAsset.findUnique({ where: { storageKey: key } }),
      ).toMatchObject({
        venueId: v.id,
        byteSize: 14,
        purpose: 'legacy',
        unusedSince: null,
      });
      await media.cleanup(new Date(Date.now() + 3 * 86400000));
      expect(await media.read(key)).toEqual(Buffer.from('existing-asset'));
    });
    it('NON_FISCAL_CLOSE is never inherited, only an explicit Venue override', async () => {
      for (const plan of await db.plan.findMany()) {
        if (plan.status !== 'ACTIVE') continue;
        await assign(b, plan);
        expect(await access.hasFeature(b.id, 'NON_FISCAL_CLOSE')).toBe(false);
      }
      await config.setFeatureOverride(
        actor,
        b.id,
        'NON_FISCAL_CLOSE',
        'ENABLED',
        'Explicit operator policy',
      );
      expect(await access.hasFeature(b.id, 'NON_FISCAL_CLOSE')).toBe(true);
      expect(await access.hasFeature(a.id, 'NON_FISCAL_CLOSE')).toBe(false);
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'NON_FISCAL_CLOSE' },
      });
      await expect(
        db.planFeature.create({
          data: { planId: websitePlan.id, featureId: feature.id },
        }),
      ).rejects.toThrow();
      await config.clearFeatureOverride(actor, b.id, 'NON_FISCAL_CLOSE');
    });
    it('catalog edits preserve agreed prices and reject policy features', async () => {
      const body = {
        key: 'PRICE_' + tag.toUpperCase(),
        name: 'Price test',
        status: 'ACTIVE',
        priceMinor: 1900,
        currency: 'GEL',
        billingPeriod: 'MONTH',
        featureKeys: ['WEBSITE'],
      };
      const plan = (
        await http()
          .post('/platform/plans')
          .set(auth(operator))
          .send(body)
          .expect(201)
      ).body;
      await assign(a, plan, 'ACTIVE');
      await http()
        .put(`/platform/plans/${plan.id}`)
        .set(auth(operator))
        .send({ ...body, priceMinor: 9900 })
        .expect(200);
      await assign(a, plan, 'ACTIVE');
      expect(
        (
          await db.venuePlanAssignment.findUniqueOrThrow({
            where: { venueId: a.id },
          })
        ).agreedPriceMinor,
      ).toBe(1900);
      await http()
        .put(`/platform/plans/${plan.id}`)
        .set(auth(operator))
        .send({ ...body, featureKeys: ['NON_FISCAL_CLOSE'] })
        .expect(400);
    });
    it('Manager provisioning is deliberate, accepted owners use memberships, suspension hides credentials', async () => {
      const plan = await db.plan.findUniqueOrThrow({
        where: { key: 'POS_MANAGER' },
      });
      await assign(a, plan, 'ACTIVE');
      await http()
        .post(`${base(a)}/managers`)
        .set(auth(a.token))
        .send({
          requestId: randomUUID(),
          username: 'manager-' + tag,
          displayName: 'Manager',
          role: 'MANAGER',
          pin: '684219',
        })
        .expect(201);
      const active = (await http().get(base(a)).set(auth(a.token)).expect(200))
        .body;
      expect(active.venue.loginCode).toBe(a.loginCode);
      expect(active.managers).toHaveLength(1);
      await assign(a, plan, 'SUSPENDED');
      const suspended = (
        await http().get(base(a)).set(auth(a.token)).expect(200)
      ).body;
      expect(suspended.features).toEqual([]);
      expect(suspended.venue.loginCode).toBeNull();
      await http()
        .post(`${base(a)}/enrollments`)
        .set(auth(a.token))
        .send({})
        .expect(403);
      const staffId = active.managers[0].id;
      await http()
        .post(`${base(a)}/managers/${staffId}/reset`)
        .set(auth(a.token))
        .send({ requestId: randomUUID(), pin: '246810' })
        .expect(403);
      await http()
        .post(`${base(a)}/managers/${staffId}/disable`)
        .set(auth(a.token))
        .send({ requestId: randomUUID() })
        .expect(201);
    });
    it('trial extension/reactivation and suspension are audited; missing dates cannot grant trials', async () => {
      await assign(a, websitePlan);
      await http()
        .put(`/platform/venues/${a.id}/subscription`)
        .set(auth(operator))
        .send({ status: 'TRIAL', planId: websitePlan.id, trialEndsAt: null })
        .expect(400);
      await assign(a, websitePlan);
      const extended = new Date(Date.now() + 7 * 86400000).toISOString();
      await http()
        .put(`/platform/venues/${a.id}/subscription`)
        .set(auth(operator))
        .send({
          status: 'TRIAL',
          trialEndsAt: extended,
          note: 'Approved extension',
        })
        .expect(200);
      expect(
        (
          await db.venueSubscription.findUniqueOrThrow({
            where: { venueId: a.id },
          })
        ).trialEndsAt!.toISOString(),
      ).toBe(extended);
      expect(await access.effectiveFeatures(a.id)).toEqual(['WEBSITE']);
      const events = await db.platformAuditEvent.findMany({
        where: { action: 'venue.subscription_changed', targetId: a.id },
      });
      expect(
        events.some((e) => (e.metadata as any)?.note === 'Approved extension'),
      ).toBe(true);
    });
    it('a fresh missing-subscription Venue cannot use even ENABLED overrides; only marked legacy can', async () => {
      const venue = await db.venue.create({
        data: {
          organizationId: a.organizationId,
          name: 'No row',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          featureOverrides: {
            create: {
              feature: { connect: { key: 'WEBSITE' } },
              effect: 'ENABLED',
            },
          },
        },
      });
      expect(venue.legacyCommercialAccess).toBe(false);
      expect(venue.cloudMenuEditingEnabled).toBe(false);
      expect(await access.effectiveFeatures(venue.id)).toEqual([]);
      // Explicitly emulates the migration marker, never an API input.
      await db.venue.update({
        where: { id: venue.id },
        data: { legacyCommercialAccess: true },
      });
      expect(await access.effectiveFeatures(venue.id)).toEqual(['WEBSITE']);
    });
    it('cross-Venue requests stay denied, while migrated CUSTOM fixtures remain entitled', async () => {
      await http().get(base(b)).set(auth(a.token)).expect(404);
      await http()
        .put(`${base(b)}/profile`)
        .set(auth(a.token))
        .send({ name: 'Stolen' })
        .expect(404);
      await http()
        .post(`${base(b)}/trial-requests`)
        .set(auth(a.token))
        .send({})
        .expect(404);
      const vankisi = await db.venue.findFirstOrThrow({
        where: { loginCode: 'vankisi' },
      });
      expect(
        (
          await db.venueSubscription.findUniqueOrThrow({
            where: { venueId: vankisi.id },
          })
        ).status,
      ).toBe('ACTIVE');
      expect(await access.websiteAccess(vankisi.id)).toMatchObject({
        entitled: true,
        effectiveMode: 'CUSTOM',
      });
      expect(await access.hasFeature(vankisi.id, 'NON_FISCAL_CLOSE')).toBe(
        false,
      );
    });
    it('HTTP billing boundary rejects owner payment claims, isolates tenants and accepts audited manual confirmation', async () => {
      const v = await prepare('billing-http');
      await http()
        .get(`${base(v)}/subscription`)
        .set(auth(v.token))
        .expect(200);
      await http()
        .get(`${base(v)}/subscription`)
        .set(auth(a.token))
        .expect(404);
      await http()
        .post(`${base(v)}/subscription/actions`)
        .set(auth(v.token))
        .send({
          action: 'GRANT_ACTIVE',
          planId: websitePlan.id,
          confirm: true,
          reason: 'Forged',
        })
        .expect(403);
      const quote = (
        await http()
          .post(`${base(v)}/subscription/quote`)
          .set(auth(v.token))
          .send({
            planId: websitePlan.id,
            paymentSucceeded: true,
            eventTime: '2000-01-01',
            amountMinor: 1,
          })
          .expect(201)
      ).body;
      expect(await access.effectiveFeatures(v.id)).toEqual([]);
      await http()
        .post(`${base(v)}/subscription/manual-success`)
        .set(auth(v.token))
        .send({ operationId: quote.id })
        .expect(404);
      await http()
        .post(`/platform/venues/${v.id}/subscription/manual-success`)
        .set(auth(v.token))
        .send({ operationId: quote.id })
        .expect(401);
      await http()
        .post(`/platform/venues/${v.id}/subscription/manual-success`)
        .set(auth(operator))
        .send({
          operationId: quote.id,
          confirm: true,
          reason: 'Verified disposable payment',
          reference: `test-receipt-${tag}`,
        })
        .expect(201);
      expect(await access.effectiveFeatures(v.id)).toEqual(['WEBSITE']);
      const state = (
        await http()
          .get(`${base(v)}/subscription`)
          .set(auth(v.token))
          .expect(200)
      ).body;
      expect(state.status).toBe('ACTIVE');
      expect(state.billingManaged).toBe(true);
      expect(state.history).toBeUndefined();
      expect(new Date(state.currentPeriodStart).getUTCFullYear()).toBe(
        new Date().getUTCFullYear(),
      );
      await http()
        .post(`${base(v)}/subscription/actions`)
        .set(auth(v.token))
        .send({ action: 'SCHEDULE_CANCEL' })
        .expect(201);
      expect(await access.effectiveFeatures(v.id)).toEqual(['WEBSITE']);
      await http()
        .post(`${base(v)}/subscription/actions`)
        .set(auth(v.token))
        .send({ action: 'UNDO_CANCEL' })
        .expect(201);
    });
    it('read-only support cannot quote, confirm money or mutate commercial access', async () => {
      const support = await db.platformUser.create({
        data: {
          email: `readonly-${tag}@test.invalid`,
          displayName: 'Support',
          passwordHash: 'unused',
          role: 'SUPPORT_READONLY',
        },
      });
      const token = await new JwtService().signAsync(
        { sub: support.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
        },
      );
      await http()
        .get(`/platform/venues/${a.id}/subscription`)
        .set(auth(token))
        .expect(200);
      for (const endpoint of ['actions', 'quote', 'manual-success'])
        await http()
          .post(`/platform/venues/${a.id}/subscription/${endpoint}`)
          .set(auth(token))
          .send({ action: 'SUSPEND', planId: websitePlan.id })
          .expect(403);
    });
  },
);
