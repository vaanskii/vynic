import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { emptyWebsiteContent } from '../website/core/website-content';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';

const url = process.env.PLATFORM_DOMAIN_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Platform-managed domains / real HTTP and PostgreSQL',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      resolver: WebsiteTenantService;
    let admin: string,
      readonly: string,
      owner: string,
      adminId: string,
      ownerId: string,
      organizationId: string,
      featureId: string;
    let custom: string, saas: string, websitePlanId: string;
    const tag = randomUUID().slice(0, 8),
      originalEnv = { ...process.env };
    const http = () => request(app.getHttpServer() as Server);
    const auth = (token = admin) => ({ Authorization: `Bearer ${token}` });
    const root = (id: string) => `/platform/venues/${id}/domains`;
    const register = (id: string, hostname: string) =>
      http().post(root(id)).set(auth()).send({ hostname });
    const rename = (
      id: string,
      domainId: string,
      expectedHostname: string,
      hostname: string,
      reason = 'Support approved change',
    ) =>
      http()
        .patch(`${root(id)}/${domainId}`)
        .set(auth())
        .send({ expectedHostname, hostname, reason });
    const venue = async (
      name: string,
      mode: 'SAAS' | 'CUSTOM',
      published = false,
    ) => {
      const row = await db.venue.create({
        data: {
          organizationId,
          name,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          menuAuthority: 'CLOUD',
          subscription: {
            create: {
              status: 'TRIAL',
              trialEndsAt: new Date(Date.now() + 86400000),
            },
          },
        },
      });
      await db.venueFeatureOverride.create({
        data: { venueId: row.id, featureId, effect: 'ENABLED' },
      });
      await db.venuePlanAssignment.create({
        data: { venueId: row.id, planId: websitePlanId },
      });
      const slug = `site-${name}-${tag}`,
        content = {
          ...emptyWebsiteContent,
          slug,
          heroTitle: 'Retained content',
        };
      await db.venueWebsiteConfig.create({
        data: {
          venueId: row.id,
          mode,
          ...(mode === 'SAAS' ? { assignedSlug: slug, draft: content } : {}),
          ...(published
            ? {
                slug,
                published: content,
                status: 'PUBLISHED',
                revision: 3,
                publishedRevision: 3,
                publishedAt: new Date(),
              }
            : {}),
        },
      });
      if (mode === 'SAAS')
        await db.venueDomain.create({
          data: { venueId: row.id, hostname: `${slug}.vynic.localhost` },
        });
      return row.id;
    };
    const token = (id: string, type: 'PLATFORM' | 'CUSTOMER') =>
      new JwtService().signAsync(
        { sub: id, typ: type },
        {
          secret: process.env.JWT_SECRET,
          audience: type === 'PLATFORM' ? 'vynic-platform' : 'vynic-customer',
          issuer: 'vynic',
        },
      );
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('admin_domains')
      )
        throw new Error('Use a fresh disposable_admin_domains database');
      process.env.JWT_SECRET = 'disposable-admin-domain-test-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'disposable-domain-cookie-key';
      process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.localhost';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      organizationId = (
        await db.organization.create({ data: { name: `Domain proof ${tag}` } })
      ).id;
      featureId = (
        await db.feature.findUniqueOrThrow({ where: { key: 'WEBSITE' } })
      ).id;
      websitePlanId = (
        await db.plan.findUniqueOrThrow({ where: { key: 'WEBSITE_ONLY' } })
      ).id;
      adminId = (
        await db.platformUser.create({
          data: {
            email: `admin-${tag}@test.invalid`,
            displayName: 'Synthetic operator',
            passwordHash: 'unused',
          },
        })
      ).id;
      const supportId = (
        await db.platformUser.create({
          data: {
            email: `support-${tag}@test.invalid`,
            displayName: 'Read-only support',
            passwordHash: 'unused',
            role: 'SUPPORT_READONLY',
          },
        })
      ).id;
      ownerId = (
        await db.customerAccount.create({
          data: {
            email: `owner-${tag}@test.invalid`,
            displayName: 'Synthetic owner',
            passwordHash: 'unused',
            memberships: { create: { organizationId, role: 'OWNER' } },
          },
        })
      ).id;
      [admin, readonly, owner] = await Promise.all([
        token(adminId, 'PLATFORM'),
        token(supportId, 'PLATFORM'),
        token(ownerId, 'CUSTOMER'),
      ]);
      custom = await venue('custom', 'CUSTOM');
      saas = await venue('saas', 'SAAS', true);
      app = await onboardingApp(db);
      resolver = new WebsiteTenantService(
        db,
        new ConfigService({ NODE_ENV: 'production' }),
      );
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      process.env = originalEnv;
    });

    it('registers a normalized Vynic subdomain for CUSTOM with real tenant resolution and audit', async () => {
      const hostname = `kitchen-${tag}.vynic.localhost`;
      expect(
        (await register(custom, ` ${hostname.toUpperCase()}:443 `).expect(201))
          .body,
      ).toMatchObject({ hostname, venueId: custom });
      await expect(resolver.resolveByHostname(hostname)).resolves.toMatchObject(
        { tenant: { venueId: custom }, configuredMode: 'CUSTOM' },
      );
      expect(
        await db.platformAuditEvent.findFirst({
          where: { targetId: custom, action: 'venue.domain_registered' },
        }),
      ).toMatchObject({ platformUserId: adminId });
    });
    it('allows Admin restaurant labels reserved from automatic/customer assignment', async () => {
      await register(custom, 'demo.vynic.localhost').expect(201);
    });
    it('adds SaaS aliases without replacing the exact assigned/public identity', async () => {
      const before = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: saas },
      });
      await register(saas, `alias-${tag}.vynic.localhost`).expect(201);
      await register(saas, `${before.assignedSlug}.example`).expect(201);
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: saas },
        }),
      ).toEqual(before);
      const product = (
        await http()
          .get(`/platform/venues/${saas}/product`)
          .set(auth())
          .expect(200)
      ).body as { website: { hostname: string } };
      expect(product.website.hostname).toBe(
        `${before.assignedSlug}.vynic.localhost`,
      );
    });
    it('renames CUSTOM, preserves lifecycle/identity and deduplicates lost-response retry', async () => {
      const original = await db.venueDomain.create({
        data: {
          venueId: custom,
          hostname: `old-${tag}.example`,
          status: 'DISABLED',
          releaseAfter: new Date(Date.now() + 86400000),
        },
      });
      const hostname = `new-${tag}.vynic.localhost`,
        first = await rename(
          custom,
          original.id,
          original.hostname,
          hostname,
        ).expect(200);
      expect(first.body).toMatchObject({
        id: original.id,
        hostname,
        status: 'DISABLED',
        createdAt: original.createdAt.toISOString(),
        releaseAfter: original.releaseAfter!.toISOString(),
      });
      expect(
        (
          await rename(custom, original.id, original.hostname, hostname).expect(
            200,
          )
        ).body,
      ).toEqual(first.body);
      expect(
        await db.platformAuditEvent.count({
          where: {
            action: 'venue.domain_hostname_changed',
            metadata: { path: ['domainId'], equals: original.id },
          },
        }),
      ).toBe(1);
      await expect(
        resolver.resolveByHostname(original.hostname),
      ).resolves.toBeNull();
      await expect(resolver.resolveByHostname(hostname)).resolves.toBeNull();
      await http()
        .put(`${root(custom)}/${original.id}/status`)
        .set(auth())
        .send({ status: 'ACTIVE' })
        .expect(200);
      await expect(resolver.resolveByHostname(hostname)).resolves.toMatchObject(
        { tenant: { venueId: custom } },
      );
    });
    it('serializes competing edits against the displayed hostname', async () => {
      const domain = await db.venueDomain.create({
        data: { venueId: custom, hostname: `race-old-${tag}.example` },
      });
      const results = await Promise.all(
        ['a', 'b'].map((s) =>
          rename(
            custom,
            domain.id,
            domain.hostname,
            `race-${s}-${tag}.example`,
          ),
        ),
      );
      expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
      expect(
        await db.platformAuditEvent.count({
          where: {
            action: 'venue.domain_hostname_changed',
            metadata: { path: ['domainId'], equals: domain.id },
          },
        }),
      ).toBe(1);
    });
    it('admits one Venue when two Admin registrations race for a hostname', async () => {
      const hostname = `contested-${tag}.vynic.localhost`,
        results = await Promise.all(
          [custom, saas].map((id) => register(id, hostname)),
        );
      expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
      expect(await db.venueDomain.count({ where: { hostname } })).toBe(1);
    });
    it('protects disabled/retained names and cross-Venue domain identities', async () => {
      const occupied = await db.venueDomain.create({
        data: {
          venueId: saas,
          hostname: `retained-${tag}.example`,
          status: 'DISABLED',
          releaseAfter: new Date(Date.now() + 86400000),
        },
      });
      const source = await db.venueDomain.create({
        data: { venueId: custom, hostname: `source-${tag}.example` },
      });
      await register(custom, occupied.hostname).expect(409);
      await rename(
        custom,
        source.id,
        source.hostname,
        occupied.hostname,
      ).expect(409);
      await rename(
        custom,
        occupied.id,
        occupied.hostname,
        `spoof-${tag}.example`,
      ).expect(404);
      expect(
        await db.venueDomain.findUnique({ where: { id: source.id } }),
      ).toEqual(source);
      expect(
        await db.venueDomain.findUnique({ where: { id: occupied.id } }),
      ).toEqual(occupied);
    });
    it('protects a retained assigned identity without a domain row', async () => {
      const id = await venue('held', 'SAAS'),
        config = await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        });
      const hostname = `${config.assignedSlug}.vynic.localhost`;
      await db.venueDomain.delete({ where: { hostname } });
      await register(custom, hostname).expect(409);
    });
    it('moves published SaaS mirrors together, closes previous requests and fences stale owner drafts', async () => {
      const before = await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: saas },
        }),
        domain = await db.venueDomain.findUniqueOrThrow({
          where: { hostname: `${before.assignedSlug}.vynic.localhost` },
        });
      const legacy = await db.websiteHostnameRequest.create({
        data: {
          venueId: saas,
          requestedBy: ownerId,
          slug: `legacy-${tag}`,
          hostname: `legacy-${tag}.vynic.localhost`,
          currentHostname: domain.hostname,
        },
      });
      const slug = `renamed-${tag}`;
      await rename(
        saas,
        domain.id,
        domain.hostname,
        `${slug}.vynic.localhost`,
      ).expect(200);
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: saas },
        }),
      ).toMatchObject({
        assignedSlug: slug,
        slug,
        revision: 4,
        publishedRevision: 4,
        draft: { slug, heroTitle: 'Retained content' },
        published: { slug, heroTitle: 'Retained content' },
        publishedAt: before.publishedAt,
      });
      expect(
        await db.websiteHostnameRequest.findUnique({
          where: { id: legacy.id },
        }),
      ).toMatchObject({ status: 'REJECTED', reviewedBy: adminId });
      await expect(
        resolver.resolveByHostname(domain.hostname),
      ).resolves.toBeNull();
      await expect(
        resolver.resolveByHostname(`${slug}.vynic.localhost`),
      ).resolves.toMatchObject({ tenant: { venueId: saas } });
      const stale = await http()
        .put(`/customer/venues/${saas}/website/draft`)
        .set(auth(owner))
        .send({ expectedRevision: before.revision, content: before.draft });
      expect([403, 409]).toContain(stale.status);
    });
    it('keeps unpublished edits unpublished and external aliases separate from assigned SaaS identity', async () => {
      const id = await venue('draft', 'SAAS', true),
        before = await db.venueWebsiteConfig.update({
          where: { venueId: id },
          data: {
            revision: 6,
            draft: {
              ...emptyWebsiteContent,
              slug: `site-draft-${tag}`,
              heroTitle: 'Unpublished edit',
            },
          },
        });
      const domain = await db.venueDomain.findUniqueOrThrow({
        where: { hostname: `${before.assignedSlug}.vynic.localhost` },
      });
      await rename(
        id,
        domain.id,
        domain.hostname,
        `unpublished-${tag}.vynic.localhost`,
      ).expect(200);
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        }),
      ).toMatchObject({
        revision: 7,
        publishedRevision: 3,
        draft: { heroTitle: 'Unpublished edit' },
        published: { heroTitle: 'Retained content' },
      });
      await rename(
        id,
        domain.id,
        `unpublished-${tag}.vynic.localhost`,
        `external-${tag}.example`,
      ).expect(400);
    });
    it('clears a former SAAS assignment when its CUSTOM hostname changes', async () => {
      const id = await venue('former', 'SAAS', true);
      const config = await db.venueWebsiteConfig.findUniqueOrThrow({
        where: { venueId: id },
      });
      const domain = await db.venueDomain.findUniqueOrThrow({
        where: { hostname: `${config.assignedSlug}.vynic.localhost` },
      });
      await db.venueWebsiteConfig.update({
        where: { venueId: id },
        data: { mode: 'CUSTOM' },
      });
      await rename(
        id,
        domain.id,
        domain.hostname,
        `former-${tag}.example`,
      ).expect(200);
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        }),
      ).toMatchObject({
        mode: 'CUSTOM',
        assignedSlug: null,
        published: config.published,
      });
      await register(custom, domain.hostname).expect(201);
    });
    it('rolls back domain and SaaS mirrors on audit failure', async () => {
      const id = await venue('rollback', 'SAAS', true),
        before = await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        }),
        domain = await db.venueDomain.findUniqueOrThrow({
          where: { hostname: `${before.assignedSlug}.vynic.localhost` },
        });
      await db.$executeRawUnsafe(
        `CREATE FUNCTION pos.disposable_domain_audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='venue.domain_hostname_changed' AND NEW.metadata->>'reason'='inject-audit-failure' THEN RAISE EXCEPTION 'synthetic audit failure'; END IF; RETURN NEW; END $$`,
      );
      await db.$executeRawUnsafe(
        `CREATE TRIGGER disposable_domain_audit_fail BEFORE INSERT ON pos."PlatformAuditEvent" FOR EACH ROW EXECUTE FUNCTION pos.disposable_domain_audit_fail()`,
      );
      try {
        await rename(
          id,
          domain.id,
          domain.hostname,
          `rollback-${tag}.vynic.localhost`,
          'inject-audit-failure',
        ).expect(500);
        expect(
          await db.venueDomain.findUnique({ where: { id: domain.id } }),
        ).toEqual(domain);
        expect(
          await db.venueWebsiteConfig.findUnique({ where: { venueId: id } }),
        ).toEqual(before);
      } finally {
        await db.$executeRawUnsafe(
          `DROP TRIGGER disposable_domain_audit_fail ON pos."PlatformAuditEvent"`,
        );
        await db.$executeRawUnsafe(
          `DROP FUNCTION pos.disposable_domain_audit_fail()`,
        );
      }
    });
    it.each([
      'vynic.localhost',
      'api.vynic.localhost',
      'admin.vynic.localhost',
      'preview.vynic.localhost',
      'www.vynic.localhost',
    ])('protects deployment origin %s', async (hostname) => {
      await register(custom, hostname).expect(400);
    });
    it('denies anonymous, owner and read-only Platform writes through real guards', async () => {
      const domain = await db.venueDomain.findFirstOrThrow({
        where: { venueId: custom },
      });
      await http()
        .post(root(custom))
        .send({ hostname: `anonymous-${tag}.example` })
        .expect(401);
      for (const [credential, status] of [
        [owner, 401],
        [readonly, 403],
      ] as const) {
        await http()
          .post(root(custom))
          .set(auth(credential))
          .send({ hostname: `denied-${tag}.example` })
          .expect(status);
        await http()
          .patch(`${root(custom)}/${domain.id}`)
          .set(auth(credential))
          .send({
            hostname: `denied-${tag}.example`,
            expectedHostname: domain.hostname,
            reason: 'Denied',
          })
          .expect(status);
        await http()
          .delete(`${root(custom)}/${domain.id}`)
          .set(auth(credential))
          .expect(status);
      }
      expect(
        await db.venueDomain.findUnique({ where: { id: domain.id } }),
      ).toEqual(domain);
    });
    it('blocks owner changes and requests in both modes and Trial/Active plans', async () => {
      const before = await db.websiteHostnameRequest.count();
      for (const id of [custom, saas])
        for (const status of ['TRIAL', 'ACTIVE'] as const) {
          await db.venueSubscription.update({
            where: { venueId: id },
            data: { status },
          });
          await http()
            .post(`/customer/venues/${id}/website/hostname-requests`)
            .set(auth(owner))
            .send({ slug: `owner-change-${tag}` })
            .expect(403);
          const settings = (
            await http()
              .get(`/customer/venues/${id}/website`)
              .set(auth(owner))
              .expect(200)
          ).body as { hostnameChangeAllowed: boolean };
          expect(settings.hostnameChangeAllowed).toBe(false);
        }
      expect(await db.websiteHostnameRequest.count()).toBe(before);
      await http()
        .post(`/customer/venues/${randomUUID()}/website/hostname-requests`)
        .set(auth(owner))
        .send({ slug: 'foreign' })
        .expect(404);
    });
    it('releases the renamed identity atomically and makes the name available', async () => {
      const id = await venue('release', 'SAAS'),
        config = await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        }),
        domain = await db.venueDomain.findUniqueOrThrow({
          where: { hostname: `${config.assignedSlug}.vynic.localhost` },
        });
      const hostname = `released-${tag}.vynic.localhost`;
      await rename(id, domain.id, domain.hostname, hostname).expect(200);
      expect(
        (
          await http()
            .delete(`${root(id)}/${domain.id}`)
            .set(auth())
            .expect(200)
        ).body,
      ).toEqual({ released: hostname });
      expect(
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: id },
        }),
      ).toMatchObject({ assignedSlug: null });
      await register(custom, hostname).expect(201);
    });
  },
);
