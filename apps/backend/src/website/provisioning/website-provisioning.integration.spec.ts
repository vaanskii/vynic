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
    beforeEach(async () => {
      await app.close();
      app = await onboardingApp(db);
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('assigns stable collision-safe addresses and enforces paid review, concurrency, tenancy and shutdown', async () => {
      const requested = await submit('ownership');
      const prepared = (
        await review(requested.id, {
          planId: websitePlanId,
          trialEndsAt: trialEndsAt(),
          websiteMode: 'SAAS',
        }).expect(201)
      ).body.prepared;
      const owner = await register(prepared.invitationPath);
      const id = owner.venueId;
      const path = `/customer/venues/${id}/website`;
      const actions = (body: Record<string, unknown>) =>
        http()
          .post(`/platform/venues/${id}/subscription/actions`)
          .set(bearer(admin))
          .send({
            reason: 'Disposable ownership proof',
            confirm: true,
            ...body,
          });
      const settings = (
        await http().get(path).set(bearer(owner.access_token)).expect(200)
      ).body;
      expect(settings.draft.slug).toMatch(/^restaurantownership(?:-\d+)?$/);
      expect(settings.hostname).toBe(settings.draft.slug + '.vynic.localhost');
      expect(settings.pendingHostnameRequest).toBeNull();
      expect(settings.hostnameChangeAllowed).toBe(false);
      await http()
        .post(path + '/hostname-requests')
        .set(bearer(owner.access_token))
        .send({ slug: 'trial-denied-' + tag })
        .expect(403);
      await http()
        .put(path + '/draft')
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: settings.revision,
          content: { ...settings.draft, slug: 'direct-denied' },
        })
        .expect(403);
      await http()
        .put(path + '/draft')
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: settings.revision,
          content: {
            ...settings.draft,
            heroTitle: 'Retained content',
            workingHours: [{ day: 1, opens: '10:00', closes: '22:00' }],
          },
        })
        .expect(200);
      await http()
        .post(path + '/publish')
        .set(bearer(owner.access_token))
        .send({ expectedRevision: settings.revision + 1 })
        .expect(201);
      await db.venue.update({
        where: { id },
        data: { name: 'Changed Restaurant Name' },
      });
      expect(
        (await http().get(path).set(bearer(owner.access_token))).body.draft
          .slug,
      ).toBe(settings.draft.slug);
      const before = await db.venueSubscription.findUniqueOrThrow({
        where: { venueId: id },
      });
      expect(before.startedAt).not.toBeNull();
      const end = new Date(
        before.trialEndsAt!.getTime() + 3600000,
      ).toISOString();
      await actions({ action: 'EXTEND_TRIAL', trialEndsAt: end }).expect(201);
      expect(
        (
          await db.venueSubscription.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).startedAt,
      ).toEqual(before.startedAt);
      await actions({ action: 'END_TRIAL', confirm: false }).expect(400);
      await actions({ action: 'END_TRIAL' }).expect(201);
      await http().get(path).set(bearer(owner.access_token)).expect(403);
      await http()
        .get('/api/website/bootstrap')
        .set('Host', settings.draft.slug + '.vynic.localhost')
        .expect(404);
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).draft,
      ).toMatchObject({ heroTitle: 'Retained content' });
      await actions({
        action: 'GRANT_ACTIVE',
        planId: websitePlanId,
        websiteMode: 'SAAS',
      }).expect(201);
      const responses = await Promise.all(
        ['paid-a-', 'paid-b-'].map((prefix) =>
          http()
            .post(path + '/hostname-requests')
            .set(bearer(owner.access_token))
            .send({ slug: prefix + tag }),
        ),
      );
      expect(responses.map((r) => r.status).sort()).toEqual([201, 409]);
      const pending = responses.find((r) => r.status === 201)!.body;
      const oldHost = settings.draft.slug + '.vynic.localhost';
      const pendingSlug = pending.hostname.split('.')[0];
      expect(pending).toEqual({
        id: expect.any(String),
        hostname: pending.hostname,
        currentHostname: oldHost,
        status: 'PENDING',
        createdAt: expect.any(String),
        reviewedAt: null,
        reason: null,
      });
      const listed = (
        await http()
          .get(path + '/hostname-requests')
          .set(bearer(owner.access_token))
          .expect(200)
      ).body;
      expect(listed[0]).not.toHaveProperty('reviewedBy');
      expect(listed[0]).not.toHaveProperty('requestedBy');
      expect(
        (await http().get(path).set(bearer(owner.access_token))).body
          .pendingHostnameRequest,
      ).toMatchObject({ hostname: pending.hostname });
      // Before approval the old address alone serves the restaurant.
      const bootstrap = (host: string) =>
        http().get('/api/website/bootstrap').set('Host', host);
      await bootstrap(oldHost).expect(200);
      await bootstrap(pending.hostname).expect(404);
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).assignedSlug,
      ).toBe(settings.draft.slug);
      // Competing Venue claims the desired hostname before approval: review fails atomically.
      const other = await platformVenue('Other owner');
      await db.venueDomain.create({
        data: { venueId: other.id, hostname: pending.hostname },
      });
      const approve = () =>
        http()
          .post(`/platform/venues/${id}/hostname-requests/${pending.id}/review`)
          .set(bearer(admin))
          .send({ status: 'APPROVED', reason: 'Reviewed' });
      await approve().expect(409);
      await db.venueDomain.delete({ where: { hostname: pending.hostname } });
      await approve().expect(201);
      await approve().expect(409);
      await bootstrap(pending.hostname).expect(200);
      await bootstrap(oldHost).expect(404);
      const approvedSettings = (
        await http().get(path).set(bearer(owner.access_token)).expect(200)
      ).body;
      expect(approvedSettings.hostname).toBe(pending.hostname);
      expect(approvedSettings.pendingHostnameRequest).toBeNull();
      expect(approvedSettings.hasUnpublishedChanges).toBe(false);
      // The current address and reserved names are not requestable.
      await http()
        .post(path + '/hostname-requests')
        .set(bearer(owner.access_token))
        .send({ slug: pendingSlug })
        .expect(409);
      await http()
        .post(path + '/hostname-requests')
        .set(bearer(owner.access_token))
        .send({ slug: 'vynic' })
        .expect(400);
      // Operators register custom domains only; the SaaS namespace is reviewed.
      await http()
        .post(`/platform/venues/${id}/domains`)
        .set(bearer(admin))
        .send({ hostname: 'second-' + tag + '.vynic.localhost' })
        .expect(400);
      expect(
        await db.venueDomain.count({
          where: { venueId: id, hostname: { endsWith: '.vynic.localhost' } },
        }),
      ).toBe(1);
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          })
        ).assignedSlug,
      ).toBe(pendingSlug);
      expect(
        await db.venueDomain.findUnique({
          where: { hostname: pending.hostname },
        }),
      ).toMatchObject({ venueId: id });
      expect(
        await db.venueDomain.findUnique({
          where: { hostname: settings.draft.slug + '.vynic.localhost' },
        }),
      ).toBeNull();
      await http()
        .get(`/customer/venues/${other.id}/website/hostname-requests`)
        .set(bearer(owner.access_token))
        .expect(404);
      const next = (
        await http()
          .post(path + '/hostname-requests')
          .set(bearer(owner.access_token))
          .send({ slug: 'rejected-' + tag })
          .expect(201)
      ).body;
      await http()
        .post(`/platform/venues/${id}/hostname-requests/${next.id}/review`)
        .set(bearer(admin))
        .send({ status: 'REJECTED', reason: 'Not suitable' })
        .expect(201);
      const audits = await db.platformAuditEvent.findMany({
        where: { targetId: id },
      });
      expect(audits.map((a) => a.action)).toEqual(
        expect.arrayContaining([
          'website.hostname_assigned',
          'website.hostname_change_requested',
          'website.hostname_change_approved',
          'website.hostname_change_rejected',
          'subscription.extend_trial',
          'subscription.end_trial',
        ]),
      );
    });

    it('serializes generated name collisions without changing either Venue identity', async () => {
      const first = await platformVenue('Restaurant Collision ' + tag);
      const second = await platformVenue('Restaurant Collision ' + tag);
      const results = await Promise.all(
        [first, second].map((v) =>
          http()
            .post(`/platform/venues/${v.id}/subscription/actions`)
            .set(bearer(admin))
            .send({
              action: 'TRIAL',
              planId: websitePlanId,
              websiteMode: 'SAAS',
              trialEndsAt: trialEndsAt(),
              reason: 'Concurrent generated names',
            }),
        ),
      );
      expect(results.map((r) => r.status)).toEqual([201, 201]);
      const rows = await db.venueWebsiteConfig.findMany({
        where: { venueId: { in: [first.id, second.id] } },
      });
      expect(new Set(rows.map((r) => r.assignedSlug)).size).toBe(2);
      expect(rows.map((r) => r.assignedSlug).sort()).toEqual([
        `restaurantcollision${tag}`,
        `restaurantcollision${tag}-2`,
      ]);
    });

    it('rechecks a contested address at approval, keeps rejected addresses and never offers CUSTOM a SaaS change', async () => {
      const activeOwner = async (name: string, websiteMode: string) => {
        const row = await submit(name);
        const prepared = (
          await review(row.id, { outcome: 'NO_PLAN' }).expect(201)
        ).body.prepared;
        const owner = await register(prepared.invitationPath);
        await http()
          .post(`/platform/venues/${owner.venueId}/subscription/actions`)
          .set(bearer(admin))
          .send({
            action: 'GRANT_ACTIVE',
            planId: websitePlanId,
            websiteMode,
            confirm: true,
            reason: 'Disposable hostname race',
          })
          .expect(201);
        const settings = (
          await http()
            .get(`/customer/venues/${owner.venueId}/website`)
            .set(bearer(owner.access_token))
            .expect(200)
        ).body;
        return { ...owner, settings };
      };
      const ask = (
        owner: { venueId: string; access_token: string },
        slug: string,
      ) =>
        http()
          .post(`/customer/venues/${owner.venueId}/website/hostname-requests`)
          .set(bearer(owner.access_token))
          .send({ slug });
      const decide = (venueId: string, id: string, status: string) =>
        http()
          .post(`/platform/venues/${venueId}/hostname-requests/${id}/review`)
          .set(bearer(admin))
          .send({ status, reason: 'Disposable decision' });
      const a = await activeOwner('race-a', 'SAAS');
      const b = await activeOwner('race-b', 'SAAS');
      expect(a.settings.hostnameChangeAllowed).toBe(true);
      const contested = 'contested-' + tag;
      // Both see the name as available: the browser check is advisory only.
      for (const owner of [a, b])
        expect(
          (
            await http()
              .get(
                `/customer/venues/${owner.venueId}/website/address/${contested}`,
              )
              .set(bearer(owner.access_token))
              .expect(200)
          ).body,
        ).toMatchObject({ valid: true, available: true });
      const requestA = (await ask(a, contested).expect(201)).body;
      const requestB = (await ask(b, contested).expect(201)).body;
      // Venue B's operator decision lands first; its old binding keeps DISABLED.
      const bOld = await db.venueDomain.findUniqueOrThrow({
        where: { hostname: b.settings.hostname },
      });
      await db.venueDomain.update({
        where: { id: bOld.id },
        data: { status: 'DISABLED' },
      });
      await decide(b.venueId, requestB.id, 'APPROVED').expect(201);
      expect(
        await db.venueDomain.findUniqueOrThrow({
          where: { hostname: `${contested}.vynic.localhost` },
        }),
      ).toMatchObject({ venueId: b.venueId, status: 'DISABLED' });
      await decide(a.venueId, requestA.id, 'APPROVED').expect(409);
      // Venue A keeps its identity and its request stays reviewable.
      expect(
        (
          await db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: a.venueId },
          })
        ).assignedSlug,
      ).toBe(a.settings.draft.slug);
      expect(
        await db.venueDomain.findUniqueOrThrow({
          where: { hostname: a.settings.hostname },
        }),
      ).toMatchObject({ venueId: a.venueId, status: 'ACTIVE' });
      await decide(a.venueId, requestA.id, 'REJECTED').expect(201);
      const afterReject = (
        await http()
          .get(`/customer/venues/${a.venueId}/website`)
          .set(bearer(a.access_token))
          .expect(200)
      ).body;
      expect(afterReject.hostname).toBe(a.settings.hostname);
      expect(afterReject.pendingHostnameRequest).toBeNull();
      const rejectedAudit = await db.platformAuditEvent.findFirstOrThrow({
        where: {
          targetId: a.venueId,
          action: 'website.hostname_change_rejected',
        },
      });
      expect(rejectedAudit.metadata).toMatchObject({
        previousHostname: a.settings.hostname,
        hostname: `${contested}.vynic.localhost`,
        activeHostname: a.settings.hostname,
      });
      const approvedAudit = await db.platformAuditEvent.findFirstOrThrow({
        where: {
          targetId: b.venueId,
          action: 'website.hostname_change_approved',
        },
      });
      expect(approvedAudit.metadata).toMatchObject({
        previousHostname: b.settings.hostname,
        activeHostname: `${contested}.vynic.localhost`,
      });
      // After a decision another request may follow.
      await ask(a, 'after-reject-' + tag).expect(201);
      const custom = await activeOwner('race-custom', 'CUSTOM');
      expect(custom.settings).toMatchObject({
        mode: 'CUSTOM',
        state: 'CUSTOM',
        hostname: null,
        hostnameChangeAllowed: false,
      });
      await ask(custom, 'custom-change-' + tag).expect(403);
    });

    it('deduplicates public requests concurrently and customer Trial requests under the Venue lock', async () => {
      const body = {
        email: `duplicate-${tag}@test.invalid`,
        applicantName: 'Owner',
        businessName: 'Business',
        phone: '555',
      };
      const results = await Promise.all(
        [1, 2].map(() => http().post('/customer/access-requests').send(body)),
      );
      expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
      const requestRow = await submit('no-plan-duplicate');
      const prepared = (
        await review(requestRow.id, { outcome: 'NO_PLAN' }).expect(201)
      ).body.prepared;
      const owner = await register(prepared.invitationPath);
      const path = `/customer/venues/${owner.venueId}/trial-requests`;
      const trialResults = await Promise.all(
        [1, 2].map(() =>
          http().post(path).set(bearer(owner.access_token)).send({}),
        ),
      );
      expect(trialResults.map((r) => r.status).sort()).toEqual([201, 409]);
      expect(
        (await http().get(path).set(bearer(owner.access_token)).expect(200))
          .body.status,
      ).toBe('PENDING');
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
            slug: settings.draft.slug,
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
