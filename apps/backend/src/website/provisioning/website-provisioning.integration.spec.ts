import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { emptyWebsiteContent } from '../core/website-content';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Website commercial provisioning / disposable HTTP',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      access: VenueEntitlementsService,
      admin: string,
      websitePlanId: string,
      posPlanId: string;
    const tag = randomUUID().slice(0, 8);
    const password = 'Website trial owner passphrase!';
    const http = () => request(app.getHttpServer());
    const bearer = (token: string) => ({ Authorization: 'Bearer ' + token });
    const trialEndsAt = () =>
      new Date(Date.now() + 14 * 86_400_000).toISOString();
    const tokenOf = (path: string) =>
      new URLSearchParams(path.split('#')[1]).get('token')!;

    /** Public access request exactly as the request-access page submits it. */
    const submit = async (name: string) => {
      const email = `${name}-${tag}@test.invalid`;
      await http()
        .post('/customer/access-requests')
        .send({
          applicantName: 'Owner ' + name,
          businessName: 'Restaurant ' + name,
          email,
          phone: '+995555000000',
        })
        .expect(201);
      return db.onboardingRequest.findFirstOrThrow({ where: { email } });
    };
    const review = (id: string, body: Record<string, unknown>) =>
      http()
        .post(`/platform/onboarding/requests/${id}/review`)
        .set(bearer(admin))
        .send({ status: 'APPROVED', outcome: 'TRIAL', ...body });
    const register = async (invitationPath: string) =>
      (
        await http()
          .post('/customer/invitations/register')
          .send({
            token: tokenOf(invitationPath),
            displayName: 'Owner',
            password,
          })
          .expect(201)
      ).body as { access_token: string; venueId: string };
    const portalVenue = async (owner: { access_token: string }) =>
      (
        await http()
          .get('/customer/portal')
          .set(bearer(owner.access_token))
          .expect(200)
      ).body.venues[0];
    const platformVenue = async (name: string) => {
      const org = (
        await http()
          .post('/platform/organizations')
          .set(bearer(admin))
          .send({ name: `${name} ${tag}` })
          .expect(201)
      ).body;
      return (
        await http()
          .post('/platform/venues')
          .set(bearer(admin))
          .send({
            organizationId: org.id,
            name,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          })
          .expect(201)
      ).body as { id: string };
    };

    beforeAll(async () => {
      if (!url!.includes('website_provisioning') || url!.includes('vankisi'))
        throw new Error('Disposable website_provisioning database required');
      process.env.JWT_SECRET = 'website-provisioning-test-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'website-provisioning-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      access = new VenueEntitlementsService(db);
      app = await onboardingApp(db);
      const user = await db.platformUser.create({
        data: {
          email: `operator-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: 'unused',
        },
      });
      admin = await new JwtService().signAsync(
        { sub: user.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
        },
      );
      websitePlanId = (
        await db.plan.findUniqueOrThrow({ where: { key: 'WEBSITE_ONLY' } })
      ).id;
      posPlanId = (await db.plan.findUniqueOrThrow({ where: { key: 'POS' } }))
        .id;
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('ships a Website-only plan with WEBSITE and neither POS nor Manager', async () => {
      const keys = (
        await db.planFeature.findMany({
          where: { planId: websitePlanId },
          include: { feature: true },
        })
      ).map((f) => f.feature.key);
      expect(keys).toEqual(['WEBSITE']);
    });

    it('refuses a Website Trial approval that does not choose SAAS or CUSTOM, and changes nothing', async () => {
      const row = await submit('unchosen');
      const venues = await db.venue.count();
      await review(row.id, {
        planId: websitePlanId,
        trialEndsAt: trialEndsAt(),
      })
        .expect(400)
        .expect(({ body }) =>
          expect(String(body.message)).toMatch(/SAAS or CUSTOM/),
        );
      await review(row.id, {
        planId: websitePlanId,
        trialEndsAt: trialEndsAt(),
        websiteMode: 'NONE',
      }).expect(400);
      expect(await db.venue.count()).toBe(venues);
      expect(
        (
          await db.onboardingRequest.findUniqueOrThrow({
            where: { id: row.id },
          })
        ).status,
      ).toBe('PENDING');
    });

    it('regression: an approved Website-only SAAS Trial is enabled on the owner dashboard', async () => {
      const row = await submit('saas');
      const reviewed = (
        await review(row.id, {
          planId: websitePlanId,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'SAAS',
        }).expect(201)
      ).body;
      const venueId = reviewed.prepared.venue.id as string;

      // Server truth, each layer on its own.
      const subscription = await db.venueSubscription.findUniqueOrThrow({
        where: { venueId },
      });
      expect(subscription.status).toBe('TRIAL');
      expect(subscription.trialEndsAt!.getTime()).toBeGreaterThan(Date.now());
      expect(
        (await db.venuePlanAssignment.findUniqueOrThrow({ where: { venueId } }))
          .planId,
      ).toBe(websitePlanId);
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({ where: { venueId } }),
      ).toMatchObject({ mode: 'SAAS', status: 'DRAFT' });
      expect(await access.effectiveFeatures(venueId)).toEqual(['WEBSITE']);
      expect(await access.hasFeature(venueId, 'POS')).toBe(false);
      expect(await access.hasFeature(venueId, 'MANAGER_APP')).toBe(false);

      // What the owner actually loads after accepting the invitation.
      const owner = await register(reviewed.prepared.invitationPath);
      expect(owner.venueId).toBe(venueId);
      const venue = await portalVenue(owner);
      expect(venue.features).toEqual(['WEBSITE']);
      expect(venue.websiteState).toBe('SAAS');
      expect(venue.subscription.status).toBe('TRIAL');
      const settings = (
        await http()
          .get(`/customer/venues/${venueId}/website`)
          .set(bearer(owner.access_token))
          .expect(200)
      ).body;
      expect(settings).toMatchObject({
        state: 'SAAS',
        mode: 'SAAS',
        entitled: true,
      });
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: venueId, action: 'venue.website_mode_changed' },
        }),
      ).toMatchObject({ metadata: { from: 'NONE', to: 'SAAS' } });

      // No POS in the package: the owner authors the canonical Cloud catalog.
      expect(
        await db.venue.findUniqueOrThrow({
          where: { id: venueId },
          select: { menuAuthority: true, cloudMenuEditingEnabled: true },
        }),
      ).toEqual({ menuAuthority: 'CLOUD', cloudMenuEditingEnabled: true });
      const catalog = (
        await http()
          .get(`/customer/venues/${venueId}/catalog`)
          .set(bearer(owner.access_token))
          .expect(200)
      ).body;
      expect(catalog).toMatchObject({
        authority: 'CLOUD',
        editingEnabled: true,
        posIncluded: false,
      });
      await http()
        .put(`/customer/venues/${venueId}/catalog/category`)
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: catalog.revision,
          nameKa: 'სალათები',
          nameEn: 'Salads',
        })
        .expect(200);
      expect(await db.menuCategory.count({ where: { venueId } })).toBe(1);
      // Hours live in the SaaS draft, which the owner can now save.
      await http()
        .put(`/customer/venues/${venueId}/website/draft`)
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: settings.revision,
          content: {
            ...emptyWebsiteContent,
            slug: 'saas-' + tag,
            workingHours: [{ day: 1, opens: '10:00', closes: '22:00' }],
          },
        })
        .expect(200);
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: venueId, action: 'venue.cloud_menu_enabled' },
        }),
      ).toMatchObject({ metadata: { source: 'subscription.trial' } });
    });

    it('provisions an operator-chosen CUSTOM Trial without the generic SaaS editor', async () => {
      const row = await submit('custom');
      const reviewed = (
        await review(row.id, {
          planId: websitePlanId,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'CUSTOM',
        }).expect(201)
      ).body;
      const owner = await register(reviewed.prepared.invitationPath);
      const venue = await portalVenue(owner);
      expect(venue.websiteState).toBe('CUSTOM');
      expect(venue.features).toEqual(['WEBSITE']);
      await http()
        .put(`/customer/venues/${owner.venueId}/website/draft`)
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: 0,
          content: { ...emptyWebsiteContent, slug: 'custom-' + tag },
        })
        .expect(403);
      // The owner has no route to switch the implementation.
      await http()
        .put(`/platform/venues/${owner.venueId}/website`)
        .set(bearer(owner.access_token))
        .send({ mode: 'SAAS' })
        .expect(401);
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: owner.venueId },
          })
        ).mode,
      ).toBe('CUSTOM');
      expect(
        (
          await db.venue.findUniqueOrThrow({
            where: { id: owner.venueId },
          })
        ).menuAuthority,
      ).toBe('POS');
    });

    it('never hands a POS-bundled Website package to Cloud menu authority', async () => {
      const { id } = await platformVenue('POS and website');
      const posWebsite = await db.plan.findUniqueOrThrow({
        where: { key: 'POS_WEBSITE' },
      });
      await http()
        .post(`/platform/venues/${id}/subscription/actions`)
        .set(bearer(admin))
        .send({
          action: 'TRIAL',
          planId: posWebsite.id,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'SAAS',
          reason: 'POS and website trial',
        })
        .expect(201);
      expect(
        await db.venue.findUniqueOrThrow({
          where: { id },
          select: { menuAuthority: true, cloudMenuEditingEnabled: true },
        }),
      ).toEqual({ menuAuthority: 'POS', cloudMenuEditingEnabled: false });
    });

    it('manual Trial on a NO_PLAN Venue ends in the same state as an approval', async () => {
      const { id } = await platformVenue('Manual trial');
      await http()
        .post(`/platform/venues/${id}/subscription/actions`)
        .set(bearer(admin))
        .send({
          action: 'TRIAL',
          planId: websitePlanId,
          trialEndsAt: trialEndsAt(),
          reason: 'Sales call',
        })
        .expect(400);
      await http()
        .post(`/platform/venues/${id}/subscription/actions`)
        .set(bearer(admin))
        .send({
          action: 'TRIAL',
          planId: websitePlanId,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'SAAS',
          reason: 'Sales call',
        })
        .expect(201);
      expect(
        (
          await db.venueSubscription.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).status,
      ).toBe('TRIAL');
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).mode,
      ).toBe('SAAS');
      expect(await access.effectiveFeatures(id)).toEqual(['WEBSITE']);
    });

    it('manual Active assignment of a Website plan also requires and provisions a mode', async () => {
      const { id } = await platformVenue('Manual active');
      const grant = (extra: Record<string, unknown>) =>
        http()
          .post(`/platform/venues/${id}/subscription/actions`)
          .set(bearer(admin))
          .send({
            action: 'GRANT_ACTIVE',
            planId: websitePlanId,
            confirm: true,
            reason: 'Signed agreement',
            ...extra,
          });
      await grant({}).expect(400);
      await grant({ websiteMode: 'CUSTOM' }).expect(201);
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).mode,
      ).toBe('CUSTOM');
      expect(await access.effectiveFeatures(id)).toEqual(['WEBSITE']);
    });

    it('reports Website included but not provisioned as setup pending, never as not included', async () => {
      const { id } = await platformVenue('Pending setup');
      // Plan and status set separately, without an operator website choice.
      await http()
        .put(`/platform/venues/${id}/plan`)
        .set(bearer(admin))
        .send({ planId: websitePlanId })
        .expect(200);
      await http()
        .put(`/platform/venues/${id}/subscription`)
        .set(bearer(admin))
        .send({ status: 'TRIAL', trialEndsAt: trialEndsAt() })
        .expect(200);
      expect(await access.effectiveFeatures(id)).toEqual(['WEBSITE']);
      const invitation = (
        await http()
          .post('/platform/onboarding/invitations')
          .set(bearer(admin))
          .send({
            organizationId: (
              await db.venue.findUniqueOrThrow({ where: { id } })
            ).organizationId,
            email: `pending-${tag}@test.invalid`,
          })
          .expect(201)
      ).body;
      const owner = await register(invitation.invitationPath);
      expect((await portalVenue(owner)).websiteState).toBe('SETUP_PENDING');
      expect(
        (
          await http()
            .get(`/customer/venues/${id}/website`)
            .set(bearer(owner.access_token))
            .expect(200)
        ).body.state,
      ).toBe('SETUP_PENDING');

      // The operator finishes setup from the Venue Website tab.
      await http()
        .put(`/platform/venues/${id}/website`)
        .set(bearer(admin))
        .send({ mode: 'SAAS' })
        .expect(200);
      expect((await portalVenue(owner)).websiteState).toBe('SAAS');
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id } })).menuAuthority,
      ).toBe('CLOUD');
    });

    it('keeps a POS-only Trial locked out of Website with no website row', async () => {
      const { id } = await platformVenue('POS only');
      await http()
        .post(`/platform/venues/${id}/subscription/actions`)
        .set(bearer(admin))
        .send({
          action: 'TRIAL',
          planId: posPlanId,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'SAAS',
          reason: 'POS trial',
        })
        .expect(400);
      await http()
        .post(`/platform/venues/${id}/subscription/actions`)
        .set(bearer(admin))
        .send({
          action: 'TRIAL',
          planId: posPlanId,
          trialEndsAt: trialEndsAt(),
          reason: 'POS trial',
        })
        .expect(201);
      expect(await access.effectiveFeatures(id)).toEqual(['POS']);
      expect(
        await db.venueWebsiteConfig.findUnique({ where: { venueId: id } }),
      ).toBeNull();
    });
  },
);
