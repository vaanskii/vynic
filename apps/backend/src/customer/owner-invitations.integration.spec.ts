import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID, createHash } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { emptyWebsiteContent } from '../website/core/website-content';

const url = process.env.ONBOARDING_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Owner invitations and SaaS onboarding / disposable HTTP',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      admin: string,
      readonly: string,
      planId: string;
    let a: any, b: any, ownerA: any, ownerB: any;
    const tag = randomUUID().slice(0, 8);
    const password = 'Owner-created long passphrase!';
    const http = () => request(app.getHttpServer());
    const bearer = (token: string) => ({ Authorization: 'Bearer ' + token });
    const tokenOf = (row: any) =>
      new URLSearchParams(row.invitationPath.split('#')[1]).get('token')!;
    const prepare = async (email: string) =>
      (
        await http()
          .post('/platform/onboarding/customers')
          .set(bearer(admin))
          .send({
            organizationName: 'Organization ' + email,
            name: 'Restaurant ' + email,
            email,
            planId,
            trialDays: 14,
          })
          .expect(201)
      ).body;
    const invite = async (organizationId: string, email: string) =>
      (
        await http()
          .post('/platform/onboarding/invitations')
          .set(bearer(admin))
          .send({ organizationId, email })
          .expect(201)
      ).body;
    beforeAll(async () => {
      const parsed = new URL(url!);
      if (
        parsed.hostname !== '127.0.0.1' ||
        parsed.port !== '55439' ||
        parsed.pathname !== '/vynic_onboarding_phase3_disposable'
      )
        throw Error('Disposable onboarding database required');
      process.env.JWT_SECRET = 'onboarding-test-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'onboarding-test-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      app = await onboardingApp(db);
      for (const role of ['SUPER_ADMIN', 'SUPPORT_READONLY'] as const) {
        const user = await db.platformUser.create({
          data: {
            email: role + tag + '@test.invalid',
            displayName: role,
            passwordHash: 'unused',
            role,
          },
        });
        const token = await new JwtService().signAsync(
          { sub: user.id, typ: 'PLATFORM' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-platform',
            issuer: 'vynic',
          },
        );
        if (role === 'SUPER_ADMIN') admin = token;
        else readonly = token;
      }
      const plan = await db.plan.create({
        data: {
          key: 'onboarding-' + tag,
          name: 'Website trial',
          features: {
            create: ['POS', 'MANAGER_APP', 'WEBSITE'].map((key) => ({
              feature: { connect: { key } },
            })),
          },
        },
      });
      planId = plan.id;
      await http()
        .put('/platform/onboarding/policy')
        .set(bearer(admin))
        .send({
          enabled: true,
          trialPlanId: planId,
          trialDays: 14,
          defaultWebsiteMode: 'SAAS',
        })
        .expect(200);
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('prepares Organization, Venue, plan, trial and draft without an owner password', async () => {
      a = await prepare('invited-' + tag + '@test.invalid');
      expect(
        await db.customerAccount.findUnique({
          where: { email: a.invitation.email },
        }),
      ).toBeNull();
      expect(
        await db.venueSubscription.findUnique({
          where: { venueId: a.venue.id },
        }),
      ).toMatchObject({ status: 'TRIAL' });
      expect(
        await db.venueWebsiteConfig.findUnique({
          where: { venueId: a.venue.id },
        }),
      ).toMatchObject({ mode: 'SAAS', status: 'DRAFT' });
      const stored = await db.ownerInvitation.findUniqueOrThrow({
        where: { id: a.invitation.id },
      });
      expect(stored.tokenHash).toBe(
        createHash('sha256').update(tokenOf(a)).digest('hex'),
      );
      expect(JSON.stringify(stored)).not.toContain(tokenOf(a));
      const listed = (
        await http()
          .get('/platform/onboarding/invitations')
          .set(bearer(admin))
          .expect(200)
      ).body;
      expect(JSON.stringify(listed)).not.toContain(stored.tokenHash);
      expect(
        JSON.stringify(
          await db.platformAuditEvent.findMany({
            where: { targetId: stored.id },
          }),
        ),
      ).not.toContain(tokenOf(a));
      await http()
        .post('/platform/onboarding/invitations')
        .set(bearer(readonly))
        .send({ organizationId: a.organization.id, email: 'no@test.invalid' })
        .expect(403);
      await http()
        .put('/platform/onboarding/policy')
        .set(bearer(admin))
        .send({
          enabled: true,
          trialPlanId: planId,
          trialDays: 14,
          defaultWebsiteMode: 'CUSTOM',
        })
        .expect(400);
    });

    it('accepts a new owner once, with no second Organization or Venue', async () => {
      const before = [await db.organization.count(), await db.venue.count()];
      const data = {
        token: tokenOf(a),
        displayName: 'Invited Owner',
        password,
      };
      const responses = await Promise.all([
        http().post('/customer/invitations/register').send(data),
        http().post('/customer/invitations/register').send(data),
      ]);
      expect(responses.map((r) => r.status).sort()).toEqual([201, 400]);
      ownerA = responses.find((r) => r.status === 201)!.body;
      expect([await db.organization.count(), await db.venue.count()]).toEqual(
        before,
      );
      expect(ownerA.venueId).toBe(a.venue.id);
      expect(ownerA.organizationId).toBe(a.organization.id);
      const portal = (
        await http()
          .get('/customer/portal')
          .set(bearer(ownerA.access_token))
          .expect(200)
      ).body;
      expect(portal.venues.map((v: any) => v.venue.id)).toEqual([a.venue.id]);
      expect(portal.venues[0].organization.accounts[0].id).toBe(
        ownerA.account.id,
      );
      await http()
        .post('/customer/invitations/accept')
        .set(bearer(ownerA.access_token))
        .send({ token: tokenOf(a) })
        .expect(400);
    });

    it('preserves self signup and creates OWNER membership / trial / SaaS draft', async () => {
      ownerB = (
        await http()
          .post('/customer/auth/signup')
          .send({
            displayName: 'Self Owner',
            email: 'self-' + tag + '@test.invalid',
            password,
          })
          .expect(201)
      ).body;
      b = (
        await http()
          .post('/customer/venues')
          .set(bearer(ownerB.access_token))
          .send({ name: 'Self Restaurant' })
          .expect(201)
      ).body;
      expect(
        await db.organizationMembership.count({
          where: {
            customerAccountId: ownerB.account.id,
            organizationId: b.organizationId,
            role: 'OWNER',
          },
        }),
      ).toBe(1);
      expect(
        await db.venueSubscription.findUnique({ where: { venueId: b.id } }),
      ).toMatchObject({ status: 'TRIAL' });
      expect(
        await db.venueWebsiteConfig.findUnique({ where: { venueId: b.id } }),
      ).toMatchObject({ mode: 'SAAS', status: 'DRAFT' });
      await http()
        .get('/customer/venues/' + b.id)
        .set(bearer(ownerA.access_token))
        .expect(404);
      await http()
        .put('/customer/venues/' + b.id + '/website/draft')
        .set(bearer(ownerA.access_token))
        .send({})
        .expect(404);
      await http()
        .post('/customer/venues')
        .set(bearer(ownerA.access_token))
        .send({ name: 'Spoof', organizationId: b.organizationId })
        .expect(400);
      await http().get('/customer/portal').set(bearer(admin)).expect(401);
      await http()
        .get('/platform/onboarding/invitations')
        .set(bearer(ownerA.access_token))
        .expect(401);
    });

    it('requires normal authentication for an existing account and never attaches the wrong account', async () => {
      const invitation = await invite(a.organization.id, ownerB.account.email);
      await http()
        .post('/customer/invitations/register')
        .send({ token: tokenOf(invitation), displayName: 'Imposter', password })
        .expect(409);
      await http()
        .post('/customer/invitations/accept')
        .set(bearer(ownerA.access_token))
        .send({ token: tokenOf(invitation) })
        .expect(403);
      const login = (
        await http()
          .post('/customer/auth/login')
          .send({ email: ownerB.account.email, password })
          .expect(201)
      ).body;
      await http()
        .post('/customer/invitations/accept')
        .set(bearer(login.access_token))
        .send({ token: tokenOf(invitation), organizationId: b.organizationId })
        .expect(201);
      const portal = (
        await http()
          .get('/customer/portal')
          .set(bearer(login.access_token))
          .expect(200)
      ).body;
      expect(portal.venues.map((v: any) => v.venue.id).sort()).toEqual(
        [a.venue.id, b.id].sort(),
      );
      expect(
        await db.customerAccount.count({
          where: { email: ownerB.account.email },
        }),
      ).toBe(1);
      const preview = (
        await http()
          .post('/customer/venues/' + b.id + '/website/preview-session')
          .set(bearer(login.access_token))
          .send({})
          .expect(201)
      ).body;
      // Legacy provenance cannot grant access once the membership is removed.
      await db.organizationMembership.delete({
        where: {
          customerAccountId_organizationId: {
            customerAccountId: ownerB.account.id,
            organizationId: b.organizationId,
          },
        },
      });
      await http()
        .get('/customer/venues/' + b.id)
        .set(bearer(login.access_token))
        .expect(404);
      await db.organizationMembership.create({
        data: {
          customerAccountId: ownerB.account.id,
          organizationId: b.organizationId,
        },
      });
    });

    it('rejects expired/revoked/replaced links, preserves history, and does not regenerate accepted invites', async () => {
      const expired = await invite(
        a.organization.id,
        'expire-' + tag + '@test.invalid',
      );
      await db.ownerInvitation.update({
        where: { id: expired.invitation.id },
        data: { expiresAt: new Date(0) },
      });
      await http()
        .post('/customer/invitations/inspect')
        .send({ token: tokenOf(expired) })
        .expect(400);
      await http()
        .post('/customer/invitations/accept')
        .set(bearer(ownerA.access_token))
        .send({ token: tokenOf(expired) })
        .expect(400);
      const revoked = await invite(
        a.organization.id,
        'revoke-' + tag + '@test.invalid',
      );
      await http()
        .post(
          '/platform/onboarding/invitations/' +
            revoked.invitation.id +
            '/revoke',
        )
        .set(bearer(admin))
        .send({})
        .expect(201);
      await http()
        .post('/customer/invitations/register')
        .send({ token: tokenOf(revoked), displayName: 'No', password })
        .expect(400);
      const renewed = (
        await http()
          .post(
            '/platform/onboarding/invitations/' +
              expired.invitation.id +
              '/regenerate',
          )
          .set(bearer(admin))
          .send({})
          .expect(201)
      ).body;
      expect(tokenOf(renewed)).not.toBe(tokenOf(expired));
      await http()
        .post('/customer/invitations/inspect')
        .send({ token: tokenOf(renewed) })
        .expect(201);
      await http()
        .post(
          '/platform/onboarding/invitations/' + a.invitation.id + '/regenerate',
        )
        .set(bearer(admin))
        .send({})
        .expect(409);
    });

    it('publishes both flows, keeps drafts private, and blocks disabled Website / CUSTOM', async () => {
      for (const [venueId, owner, slug] of [
        [a.venue.id, ownerA, 'assisted-' + tag],
        [b.id, ownerB, 'self-' + tag],
      ]) {
        const path = '/customer/venues/' + venueId + '/website';
        const content = {
          ...emptyWebsiteContent,
          slug,
          heroTitle: 'Published ' + slug,
        };
        await http()
          .put(path + '/draft')
          .set(bearer(owner.access_token))
          .send({ expectedRevision: 0, content })
          .expect(200);
        const preview = (
          await http()
            .post(path + '/preview-session')
            .set(bearer(owner.access_token))
            .send({})
            .expect(201)
        ).body;
        const previewBody = (
          await http()
            .get('/api/website/preview/bootstrap')
            .set(bearer(preview.token))
            .expect(200)
        ).body;
        expect(previewBody.preview).toBe(true);
        await http()
          .get('/api/website/bootstrap')
          .set('Host', slug + '.vynic.localhost:5175')
          .expect(404);
        await http()
          .post(path + '/publish')
          .set(bearer(owner.access_token))
          .send({ expectedRevision: 1 })
          .expect(201);
        const publicBody = (
          await http()
            .get('/api/website/bootstrap')
            .set('Host', slug + '.vynic.localhost:5175')
            .expect(200)
        ).body;
        expect(publicBody.preview).toBe(false);
        expect(JSON.stringify(publicBody)).toContain('Published ' + slug);
        await http()
          .put(path + '/draft')
          .set(bearer(owner.access_token))
          .send({
            expectedRevision: 1,
            content: { ...content, heroTitle: 'PRIVATE DRAFT' },
          })
          .expect(200);
        const publicAfter = (
          await http()
            .get('/api/website/bootstrap')
            .set('Host', slug + '.vynic.localhost:5175')
            .expect(200)
        ).body;
        expect(JSON.stringify(publicAfter)).not.toContain('PRIVATE DRAFT');
      }
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'WEBSITE' },
      });
      await db.venueFeatureOverride.create({
        data: {
          venueId: a.venue.id,
          featureId: feature.id,
          effect: 'DISABLED',
        },
      });
      await http()
        .get('/api/website/bootstrap')
        .set('Host', 'assisted-' + tag + '.vynic.localhost:5175')
        .expect(404);
      await db.venueWebsiteConfig.update({
        where: { venueId: b.id },
        data: { mode: 'CUSTOM' },
      });
      const custom = await http()
        .get('/api/website/bootstrap')
        .set('Host', 'self-' + tag + '.vynic.localhost:5175')
        .expect(200);
      expect(custom.body).toEqual({ schemaVersion: 2, mode: 'CUSTOM' });
    });

    it('does not create websites when default is NONE or the plan has no WEBSITE', async () => {
      await db.onboardingPolicy.update({
        where: { id: 'default' },
        data: { defaultWebsiteMode: 'NONE', enabled: false },
      });
      const none = await prepare('none-' + tag + '@test.invalid');
      expect(
        await db.venueWebsiteConfig.findUnique({
          where: { venueId: none.venue.id },
        }),
      ).toBeNull();
      // Assisted onboarding stays available with self-registration disabled.
      await db.onboardingPolicy.update({
        where: { id: 'default' },
        data: { defaultWebsiteMode: 'SAAS' },
      });
      const plan = await db.plan.create({
        data: { key: 'no-website-' + tag, name: 'No website' },
      });
      planId = plan.id;
      const noFeature = await prepare('no-feature-' + tag + '@test.invalid');
      expect(
        await db.venueWebsiteConfig.findUnique({
          where: { venueId: noFeature.venue.id },
        }),
      ).toBeNull();
    });
  },
);
