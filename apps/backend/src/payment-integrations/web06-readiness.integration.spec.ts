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
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { PlatformWebsiteCapabilitiesController } from '../platform/platform-website-capabilities.controller';
import { WebsiteVenueController } from '../website/core/website-venue.controller';
import { WebsiteVenueService } from '../website/core/website-venue.service';
import {
  PaymentIntegrationsService,
  type BogConfig,
} from './payment-integrations.service';
import { emptyWebsiteContent } from '../website/core/website-content';
import type { CapabilityState } from '../website/tenancy/website-capabilities';
import { PlatformCustomWebsiteController } from '../platform/platform-custom-website.controller';
import { CustomWebsiteService } from '../website/custom/custom-website.service';
import type { CustomPaymentStatus } from '../website/custom/custom-website';

const url = process.env.WEB06_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'WEB-06 current BOG readiness / real HTTP and PostgreSQL',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      integrations: PaymentIntegrationsService,
      admin: string;
    const tag = randomUUID().slice(0, 8),
      beforeEnv = { ...process.env };
    const fixtures: Array<{
      id: string;
      hostname: string;
      ownerId: string;
      ownerToken: string;
      config: BogConfig;
    }> = [];
    const http = () => request(app.getHttpServer() as Server);
    const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });
    const merchantPath = (f: (typeof fixtures)[number]) =>
      `/customer/venues/${f.id}/payments/bog`;
    const save = (f: (typeof fixtures)[number], version: string) =>
      http()
        .put(merchantPath(f))
        .set(bearer(f.ownerToken))
        .send({ ...f.config, clientSecret: `fixture-only-${version}` });
    const status = async (f: (typeof fixtures)[number]) =>
      (await http().get(merchantPath(f)).set(bearer(f.ownerToken)).expect(200))
        .body as { configured: boolean; revision: number | null };
    const capabilities = async (f: (typeof fixtures)[number]) =>
      (
        await http()
          .get(`/platform/venues/${f.id}/website-capabilities`)
          .set(bearer(admin))
          .expect(200)
      ).body as CapabilityState[];
    const customStatus = async (f: (typeof fixtures)[number]) => {
      const response = await http()
        .get(`/platform/venues/${f.id}/custom-website`)
        .set(bearer(admin));
      expect({
        status: response.status,
        message: (response.body as { message?: unknown }).message,
      }).toEqual({ status: 200, message: undefined });
      return response.body as {
        venueId: string;
        payments: CustomPaymentStatus;
      };
    };
    const publicFlags = async (f: (typeof fixtures)[number]) =>
      (
        await http()
          .get('/api/website/venue')
          .set('Host', f.hostname)
          .expect(200)
      ).body as {
        capabilities: { onlinePayments: boolean; reservations: boolean };
      };
    const createFixture = async (mode: 'SAAS' | 'CUSTOM', label: string) => {
      const organizationId = (
        await db.organization.create({ data: { name: `WEB06 ${label}` } })
      ).id;
      const slug = `${label}-${tag}`,
        hostname = `${slug}.vynic.localhost`;
      const venue = await db.venue.create({
        data: {
          organizationId,
          name: label,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          legacyCommercialAccess: true,
          websiteConfig: {
            create: {
              mode,
              ...(mode === 'SAAS'
                ? {
                    status: 'PUBLISHED',
                    assignedSlug: slug,
                    slug,
                    draft: { ...emptyWebsiteContent, slug },
                    published: { ...emptyWebsiteContent, slug },
                    revision: 1,
                    publishedRevision: 1,
                    publishedAt: new Date(),
                  }
                : {}),
            },
          },
          domains: { create: { hostname } },
        },
      });
      for (const key of ['WEBSITE', 'ONLINE_PAYMENTS'])
        await db.venueFeatureOverride.create({
          data: {
            venueId: venue.id,
            featureId: (await db.feature.findUniqueOrThrow({ where: { key } }))
              .id,
            effect: 'ENABLED',
          },
        });
      await db.websiteTable.create({
        data: {
          venueId: venue.id,
          websiteTableNumber: 'table1',
          posTableNumber: '1',
          posFloor: '1',
        },
      });
      const owner = await db.customerAccount.create({
        data: {
          email: `${label}-${tag}@test.invalid`,
          displayName: 'Synthetic owner',
          passwordHash: 'unused',
          memberships: { create: { organizationId, role: 'OWNER' } },
        },
      });
      const ownerToken = await new JwtService().signAsync(
        { sub: owner.id, typ: 'CUSTOMER' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-customer',
          issuer: 'vynic',
        },
      );
      const f = {
        id: venue.id,
        hostname,
        ownerId: owner.id,
        ownerToken,
        config: {
          clientId: 'fixture-only-client',
          clientSecret: 'fixture-only-initial',
          returnOrigin: `https://${hostname}`,
        },
      };
      fixtures.push(f);
      return f;
    };
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('web06')
      )
        throw new Error('Use a fresh disposable_web06 database');
      process.env.JWT_SECRET = 'web06-test-only-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'web06-test-only-cookie-key';
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = '42'.repeat(32);
      process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.localhost';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const operator = await db.platformUser.create({
        data: {
          email: `web06-${tag}@test.invalid`,
          displayName: 'Synthetic operator',
          passwordHash: 'unused',
        },
      });
      admin = await new JwtService().signAsync(
        { sub: operator.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
        },
      );
      app = await onboardingApp(db, undefined, {
        controllers: [
          PlatformWebsiteCapabilitiesController,
          WebsiteVenueController,
          PlatformCustomWebsiteController,
        ],
        providers: [WebsiteVenueService, CustomWebsiteService],
      });
      integrations = app.get(PaymentIntegrationsService);
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      process.env = beforeEnv;
    });
    it.each(['SAAS', 'CUSTOM'] as const)(
      '%s r1 -> r2 keeps payment/reservation readiness on the current enabled revision',
      async (mode) => {
        const f = await createFixture(mode, mode.toLowerCase());
        expect(await status(f)).toMatchObject({
          configured: false,
          revision: null,
        });
        await save(f, 'r1').expect(200);
        expect(
          (await capabilities(f)).find((s) => s.key === 'ONLINE_PAYMENTS'),
        ).toMatchObject({ ready: true, live: true });
        await save(f, 'r2').expect(200);
        const rows = await db.paymentIntegration.findMany({
          where: { venueId: f.id },
          orderBy: { revision: 'asc' },
          select: { revision: true, enabled: true },
        });
        expect(rows).toEqual([
          { revision: 1, enabled: false },
          { revision: 2, enabled: true },
        ]);
        expect(await status(f)).toMatchObject({
          configured: true,
          revision: 2,
        });
        expect(
          (await capabilities(f)).find((s) => s.key === 'ONLINE_PAYMENTS'),
        ).toMatchObject({ ready: true, live: true });
        expect(
          (await capabilities(f)).find((s) => s.key === 'RESERVATIONS'),
        ).toMatchObject({ ready: true, live: true });
        expect((await publicFlags(f)).capabilities).toMatchObject({
          onlinePayments: true,
          reservations: true,
        });
      },
    );
    it('uses revision order even when historical timestamps are out of order', async () => {
      const f = await createFixture('CUSTOM', 'skew');
      await save(f, 'skew-r1').expect(200);
      await save(f, 'skew-r2').expect(200);
      await db.paymentIntegration.updateMany({
        where: { venueId: f.id, revision: 1 },
        data: { createdAt: new Date('2099-01-01') },
      });
      await db.paymentIntegration.updateMany({
        where: { venueId: f.id, revision: 2 },
        data: { createdAt: new Date('2000-01-01') },
      });
      expect(await status(f)).toMatchObject({ configured: true, revision: 2 });
      expect((await publicFlags(f)).capabilities.onlinePayments).toBe(true);
    });
    it('disconnect reports the latest disabled revision; reconnect keeps all previous revisions', async () => {
      const f = fixtures[0];
      await http()
        .post(merchantPath(f) + '/disable')
        .set(bearer(f.ownerToken))
        .expect(201);
      expect(await status(f)).toMatchObject({ configured: false, revision: 2 });
      expect(
        (await capabilities(f)).find((s) => s.key === 'ONLINE_PAYMENTS'),
      ).toMatchObject({ ready: false, live: false });
      expect((await publicFlags(f)).capabilities).toMatchObject({
        onlinePayments: false,
        reservations: false,
      });
      await save(f, 'r3').expect(200);
      expect(await status(f)).toMatchObject({ configured: true, revision: 3 });
      expect((await publicFlags(f)).capabilities.onlinePayments).toBe(true);
      expect(
        await db.paymentIntegration.count({ where: { venueId: f.id } }),
      ).toBe(3);
    });
    it('keeps missing-config Venue isolated and refuses another owner payment settings', async () => {
      const missing = await createFixture('CUSTOM', 'missing');
      expect(await status(missing)).toMatchObject({
        configured: false,
        revision: null,
      });
      expect((await publicFlags(missing)).capabilities.onlinePayments).toBe(
        false,
      );
      await http()
        .get(merchantPath(missing))
        .set(bearer(fixtures[0].ownerToken))
        .expect(404);
      expect(
        (await capabilities(missing)).find((s) => s.key === 'ONLINE_PAYMENTS'),
      ).toMatchObject({
        readyDetail: 'Bank of Georgia is not configured',
        ready: false,
      });
    });
    it('status reads expose no secrets, need no decryption key and never rewrite stored history', async () => {
      const f = fixtures[0],
        before = await db.paymentIntegration.findMany({
          where: { venueId: f.id },
          orderBy: { revision: 'asc' },
        });
      delete process.env.PAYMENT_INTEGRATION_MASTER_KEY;
      try {
        const responses = [
          await status(f),
          await capabilities(f),
          await publicFlags(f),
        ];
        expect(JSON.stringify(responses).includes('fixture-only')).toBe(false);
        expect(JSON.stringify(responses).includes('encryptedConfig')).toBe(
          false,
        );
        expect(await status(f)).toMatchObject({
          configured: true,
          revision: 3,
        });
      } finally {
        process.env.PAYMENT_INTEGRATION_MASTER_KEY = '42'.repeat(32);
      }
      const after = await db.paymentIntegration.findMany({
        where: { venueId: f.id },
        orderBy: { revision: 'asc' },
      });
      expect(JSON.stringify(before) === JSON.stringify(after)).toBe(true);
      const original = before[0];
      // An already-created payment still reads its pinned disabled integration by ID.
      const old = await integrations.credentials(f.id, original.id);
      expect(old.clientSecret === 'fixture-only-r1').toBe(true);
    });
    it('keeps entitlement and explicit capability policy independent of configured readiness', async () => {
      const f = fixtures[1];
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/ONLINE_PAYMENTS`)
        .set(bearer(admin))
        .send({ enabled: false })
        .expect(200);
      expect(
        (await capabilities(f)).find((s) => s.key === 'ONLINE_PAYMENTS'),
      ).toMatchObject({ ready: true, live: false, enabled: false });
      await http()
        .put(`/platform/venues/${f.id}/website-capabilities/ONLINE_PAYMENTS`)
        .set(bearer(admin))
        .send({ enabled: true })
        .expect(200);
      await db.venueFeatureOverride.updateMany({
        where: { venueId: f.id, feature: { key: 'ONLINE_PAYMENTS' } },
        data: { effect: 'DISABLED' },
      });
      expect(
        (await capabilities(f)).find((s) => s.key === 'ONLINE_PAYMENTS'),
      ).toMatchObject({ ready: true, live: false, commercial: false });
      expect((await publicFlags(f)).capabilities.onlinePayments).toBe(false);
    });
    it('CUSTOM operator status follows the greatest revision across rotation, clock skew, disable and reconnect', async () => {
      const f = await createFixture('CUSTOM', 'custom-status-rotation');
      await save(f, 'custom-status-r1').expect(200);
      expect((await customStatus(f)).payments).toBe('ENABLED');
      await save(f, 'custom-status-r2').expect(200);
      expect((await customStatus(f)).payments).toBe('ENABLED');
      // Synthetic historical metadata: neither timestamp nor an old enabled row
      // may override the current revision's disabled state.
      await db.paymentIntegration.updateMany({
        where: { venueId: f.id, revision: 2 },
        data: { enabled: false, createdAt: new Date('2000-01-01') },
      });
      await db.paymentIntegration.updateMany({
        where: { venueId: f.id, revision: 1 },
        data: { enabled: true, createdAt: new Date('2099-01-01') },
      });
      expect((await customStatus(f)).payments).toBe('DISABLED');
      expect(await status(f)).toMatchObject({ configured: false, revision: 2 });
      await save(f, 'custom-status-r3').expect(200);
      expect((await customStatus(f)).payments).toBe('ENABLED');
      expect(await status(f)).toMatchObject({ configured: true, revision: 3 });
    });
    it('CUSTOM status keeps missing configuration, entitlement and Platform authority scoped to each Venue', async () => {
      const configured = await createFixture(
        'CUSTOM',
        'custom-status-configured',
      );
      await save(configured, 'custom-status-isolated').expect(200);
      const missing = await createFixture('CUSTOM', 'custom-status-missing');
      expect(await customStatus(missing)).toMatchObject({
        venueId: missing.id,
        payments: 'NOT_CONFIGURED',
      });
      expect((await customStatus(configured)).payments).toBe('ENABLED');
      await db.venueFeatureOverride.updateMany({
        where: { venueId: configured.id, feature: { key: 'ONLINE_PAYMENTS' } },
        data: { effect: 'DISABLED' },
      });
      expect((await customStatus(configured)).payments).toBe('NOT_INCLUDED');
      await http()
        .get(`/platform/venues/${configured.id}/custom-website`)
        .set(bearer(configured.ownerToken))
        .expect(401);
      await http()
        .get(`/platform/venues/${missing.id}/custom-website`)
        .expect(401);
    });
    it('CUSTOM status requires no decryption key, discloses no credentials and preserves pinned history', async () => {
      const f = await createFixture('CUSTOM', 'custom-status-history');
      await save(f, 'custom-history-r1').expect(200);
      await save(f, 'custom-history-r2').expect(200);
      const before = await db.paymentIntegration.findMany({
        where: { venueId: f.id },
        orderBy: { revision: 'asc' },
      });
      delete process.env.PAYMENT_INTEGRATION_MASTER_KEY;
      try {
        const view = await customStatus(f);
        expect(view.payments).toBe('ENABLED');
        expect(JSON.stringify(view)).not.toMatch(
          /fixture-only|encryptedConfig|clientSecret|clientId/,
        );
      } finally {
        process.env.PAYMENT_INTEGRATION_MASTER_KEY = '42'.repeat(32);
      }
      expect(
        await db.paymentIntegration.findMany({
          where: { venueId: f.id },
          orderBy: { revision: 'asc' },
        }),
      ).toEqual(before);
      expect(
        (await integrations.credentials(f.id, before[0].id)).clientSecret ===
          'fixture-only-custom-history-r1',
      ).toBe(true);
    });
  },
);
