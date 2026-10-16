import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { emptyWebsiteContent } from '../core/website-content';
import { CommercialLifecycleService } from '../../entitlements/commercial-lifecycle.service';

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
    /** Existing pre-policy requests retain review/retention coverage; no owner writer is used. */
    const legacyRequest = async (
      owner: { venueId: string; access_token: string },
      slug: string,
    ) => {
      const config = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: owner.venueId },
      });
      return db.websiteHostnameRequest.create({
        data: {
          venueId: owner.venueId,
          requestedBy: new JwtService().decode<{ sub: string }>(
            owner.access_token,
          ).sub,
          slug,
          hostname: `${slug}.vynic.localhost`,
          currentHostname: `${config.assignedSlug}.vynic.localhost`,
        },
      });
    };
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

    it('assigns stable addresses, blocks owner changes and retains historical review, tenancy and shutdown', async () => {
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
      expect(responses.map((r) => r.status)).toEqual([403, 403]);
      expect(
        await db.websiteHostnameRequest.count({ where: { venueId: id } }),
      ).toBe(0);
      const pending = await legacyRequest(owner, 'paid-a-' + tag);
      const oldHost = settings.draft.slug + '.vynic.localhost';
      const pendingSlug = pending.slug;
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
        .expect(403);
      await http()
        .post(path + '/hostname-requests')
        .set(bearer(owner.access_token))
        .send({ slug: 'vynic' })
        .expect(403);
      // Platform Admin may register an additional Vynic hostname without changing the assigned identity.
      await http()
        .post(`/platform/venues/${id}/domains`)
        .set(bearer(admin))
        .send({ hostname: 'second-' + tag + '.vynic.localhost' })
        .expect(201);
      expect(
        await db.venueDomain.count({
          where: { venueId: id, hostname: { endsWith: '.vynic.localhost' } },
        }),
      ).toBe(2);
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
      const next = await legacyRequest(owner, 'rejected-' + tag);
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
        ).body as {
          hostname: string;
          hostnameChangeAllowed: boolean;
          draft: typeof emptyWebsiteContent;
        };
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
      expect(a.settings.hostnameChangeAllowed).toBe(false);
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
      const requestA = await legacyRequest(a, contested);
      const requestB = await legacyRequest(b, contested);
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
      await ask(a, 'after-reject-' + tag).expect(403);
      const custom = await activeOwner('race-custom', 'CUSTOM');
      expect(custom.settings).toMatchObject({
        mode: 'CUSTOM',
        state: 'CUSTOM',
        hostname: null,
        hostnameChangeAllowed: false,
      });
      await ask(custom, 'custom-change-' + tag).expect(403);
    });

    it('keeps a lapsed address reserved through grace, then lets another Venue reclaim it', async () => {
      const name = `Reclaim Kitchen ${tag}`;
      const lifecycle = new CommercialLifecycleService(db);
      const owned = async (label: string) => {
        const row = await submit(label);
        const prepared = (
          await review(row.id, { outcome: 'NO_PLAN' }).expect(201)
        ).body.prepared;
        const owner = await register(prepared.invitationPath);
        await db.venue.update({ where: { id: owner.venueId }, data: { name } });
        return owner;
      };
      const act = (venueId: string, body: Record<string, unknown>) =>
        http()
          .post(`/platform/venues/${venueId}/subscription/actions`)
          .set(bearer(admin))
          .send({ confirm: true, reason: 'Disposable reclaim', ...body });
      const website = (o: { venueId: string; access_token: string }) =>
        http()
          .get(`/customer/venues/${o.venueId}/website`)
          .set(bearer(o.access_token));
      const ask = (
        o: { venueId: string; access_token: string },
        slug: string,
      ) =>
        http()
          .post(`/customer/venues/${o.venueId}/website/hostname-requests`)
          .set(bearer(o.access_token))
          .send({ slug });
      const a = await owned('reclaim-a');
      await act(a.venueId, {
        action: 'GRANT_ACTIVE',
        planId: websitePlanId,
        websiteMode: 'SAAS',
      }).expect(201);
      const first = (await website(a).expect(200)).body as {
        hostname: string;
        revision: number;
        draft: typeof emptyWebsiteContent;
      };
      const stem = `reclaimkitchen${tag}`;
      expect(first.hostname).toBe(`${stem}.vynic.localhost`);
      const saved = (
        await http()
          .put(`/customer/venues/${a.venueId}/website/draft`)
          .set(bearer(a.access_token))
          .send({
            expectedRevision: first.revision,
            content: { ...first.draft, heroTitle: 'Reclaim' },
          })
          .expect(200)
      ).body;
      await http()
        .post(`/customer/venues/${a.venueId}/website/publish`)
        .set(bearer(a.access_token))
        .send({ expectedRevision: saved.revision })
        .expect(201);
      await legacyRequest(a, `stale-${tag}`);
      await act(a.venueId, { action: 'SUSPEND' }).expect(201);
      const lapsedAt = new Date();
      await lifecycle.reconcile(a.venueId, lapsedAt);
      const retained = await db.venueDomain.findUniqueOrThrow({
        where: { hostname: first.hostname },
      });
      expect(retained.releaseAfter).not.toBeNull();

      // During grace the name stays reserved, for assignment and requests.
      const b = await owned('reclaim-b');
      await act(b.venueId, {
        action: 'GRANT_ACTIVE',
        planId: websitePlanId,
        websiteMode: 'SAAS',
      }).expect(201);
      expect((await website(b).expect(200)).body.hostname).toBe(
        `${stem}-2.vynic.localhost`,
      );
      await ask(b, stem).expect(403);
      await http()
        .post(`/platform/venues/${b.venueId}/domains`)
        .set(bearer(admin))
        .send({ hostname: first.hostname })
        .expect(409);

      await lifecycle.reconcile(
        a.venueId,
        new Date(retained.releaseAfter!.getTime() + 1),
      );
      const released = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: a.venueId },
      });
      expect(released).toMatchObject({
        assignedSlug: null,
        status: 'PUBLISHED',
      });
      // Content and history remain; the stale pending request was closed.
      expect(released.published).toMatchObject({ heroTitle: 'Reclaim' });
      expect(
        await db.websiteHostnameRequest.findFirstOrThrow({
          where: { venueId: a.venueId, slug: `stale-${tag}` },
        }),
      ).toMatchObject({ status: 'REJECTED' });
      expect(
        await db.platformAuditEvent.findFirstOrThrow({
          where: { targetId: a.venueId, action: 'website.hostname_released' },
        }),
      ).toMatchObject({
        metadata: expect.objectContaining({
          hostname: first.hostname,
          closedRequests: 1,
          source: 'SYSTEM',
        }),
      });

      // Genuinely available: another Venue requests and is approved for it.
      expect(
        (
          await http()
            .get(`/customer/venues/${b.venueId}/website/address/${stem}`)
            .set(bearer(b.access_token))
            .expect(200)
        ).body,
      ).toMatchObject({ available: true });
      const claim = await legacyRequest(b, stem);
      await http()
        .post(
          `/platform/venues/${b.venueId}/hostname-requests/${claim.id}/review`,
        )
        .set(bearer(admin))
        .send({ status: 'APPROVED', reason: 'Released name' })
        .expect(201);
      expect(
        await db.venueDomain.findUniqueOrThrow({
          where: { hostname: first.hostname },
        }),
      ).toMatchObject({ venueId: b.venueId, status: 'ACTIVE' });

      // The lapsed Venue returns with a fresh address and a consistent site.
      await act(a.venueId, { action: 'RESUME' }).expect(201);
      const back = (await website(a).expect(200)).body;
      expect(back.hostname).toBe(`${stem}-2.vynic.localhost`);
      expect(back.pendingHostnameRequest).toBeNull();
      const restored = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: a.venueId },
      });
      expect(restored).toMatchObject({
        assignedSlug: `${stem}-2`,
        slug: `${stem}-2`,
        published: expect.objectContaining({ slug: `${stem}-2` }),
      });
      expect(back.hasUnpublishedChanges).toBe(false);
      await http()
        .get('/api/website/bootstrap')
        .set('Host', back.hostname)
        .expect(200);
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
        .post(`/customer/venues/${venueId}/catalog/mutations`)
        .set(bearer(owner.access_token))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'სალათები', nameEn: 'Salads' },
        })
        .expect(200);
      expect(await db.menuCategory.count({ where: { venueId } })).toBe(1);
      // The owner can save the page draft and the Venue's hours.
      await http()
        .put(`/customer/venues/${venueId}/website/draft`)
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: settings.revision,
          content: { ...emptyWebsiteContent, slug: settings.draft.slug },
        })
        .expect(200);
      await http()
        .put(`/customer/venues/${venueId}/website/public-info`)
        .set(bearer(owner.access_token))
        .send({
          expectedRevision: 0,
          workingHours: [{ day: 1, opens: '10:00', closes: '22:00' }],
        })
        .expect(200);
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: venueId, action: 'venue.cloud_menu_enabled' },
        }),
      ).toMatchObject({ metadata: { source: 'subscription.trial' } });
    });

    it('provisions an operator-chosen CUSTOM Trial with the Cloud catalog and without the generic SaaS editor', async () => {
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
      // CUSTOM changes only who renders the site: a Website-only package gets
      // the same Cloud catalog admission as SAAS.
      expect(
        await db.venue.findUniqueOrThrow({
          where: { id: owner.venueId },
          select: { menuAuthority: true, cloudMenuEditingEnabled: true },
        }),
      ).toEqual({ menuAuthority: 'CLOUD', cloudMenuEditingEnabled: true });
      const catalog = (
        await http()
          .get(`/customer/venues/${owner.venueId}/catalog`)
          .set(bearer(owner.access_token))
          .expect(200)
      ).body;
      expect(catalog).toMatchObject({
        authority: 'CLOUD',
        editingEnabled: true,
        posIncluded: false,
      });
      await http()
        .post(`/customer/venues/${owner.venueId}/catalog/mutations`)
        .set(bearer(owner.access_token))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'სალათები', nameEn: 'Salads' },
        })
        .expect(200);
      expect(
        await db.menuCategory.count({ where: { venueId: owner.venueId } }),
      ).toBe(1);
      expect(
        await db.platformAuditEvent.findFirst({
          where: {
            targetId: owner.venueId,
            action: 'venue.cloud_menu_enabled',
          },
        }),
      ).toMatchObject({ metadata: { from: 'CLOUD', enabled: true } });
    });

    it('never enables owner menu editing for a POS-bundled Website package', async () => {
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
        // New Venues are canonical (D030); a POS package still leaves owner
        // editing to an explicit operator decision.
      ).toEqual({ menuAuthority: 'CLOUD', cloudMenuEditingEnabled: false });
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
