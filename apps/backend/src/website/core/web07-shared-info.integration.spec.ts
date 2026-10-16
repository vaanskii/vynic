import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { CustomerAuth } from '../../customer/customer-auth';
import { CustomerController } from '../../customer/customer.controller';
import { CustomerWebsiteController } from '../../customer/customer-website.controller';
import { CustomerService } from '../../customer/customer.service';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { WebsiteVenueController } from './website-venue.controller';
import { WebsiteVenueService } from './website-venue.service';
import { WebsiteCoreService } from './website-core.service';
import { WebsiteCoreController } from './website-core.controller';
import { VenuePublicProfileService } from './venue-public-profile.service';
import { WebsiteMenuService } from './website-menu.service';
import { WebsitePreviewTokens } from './website-preview';
import { WebsiteLogoService } from './website-logo.service';
import { HostnameRequestsService } from './hostname-requests';
import { emptyWebsiteContent } from './website-content';
import type {
  CustomSiteBootstrap,
  VenueInfo,
  VenueProfile,
} from '../../../../../packages/website-client/src/types';
const url = process.env.WEB07_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'WEB-07 owner -> shared public information / real HTTP + PostgreSQL',
  () => {
    let db: PrismaService, app: INestApplication;
    const oldEnv = { ...process.env };
    const rows: Array<{
      id: string;
      host: string;
      token: string;
      storageKey: string;
      mode: 'CUSTOM' | 'SAAS';
    }> = [];
    const http = () => request(app.getHttpServer() as Server);
    const owner = (i = 0) => ({ Authorization: `Bearer ${rows[i].token}` });
    const profilePath = (i = 0) => `/customer/venues/${rows[i].id}/profile`;
    const infoPath = (i = 0) =>
      `/customer/venues/${rows[i].id}/website/public-info`;
    const shared = async (i = 0) => {
      const res = await http()
        .get('/api/website/venue')
        .set('Host', rows[i].host)
        .expect(200);
      return {
        data: res.body as CustomSiteBootstrap,
        etag: res.headers.etag,
      };
    };
    const fields = (i = 0): VenueInfo => ({
      workingHours: [{ day: 1, opens: '10:00', closes: '01:00' }],
      contactEmail: `public-${i}@test.invalid`,
      mapUrl: `https://maps.test.invalid/venue-${i}`,
      socials: [
        { label: 'Instagram', url: `https://social.test.invalid/venue-${i}` },
      ],
      gallery: [
        {
          url: `/media/website-logos/${rows[i].storageKey}`,
          alt: `Owner photo ${i}`,
        },
      ],
    });
    async function saved(i = 0) {
      return (
        await http()
          .get(`/customer/venues/${rows[i].id}/website`)
          .set(owner(i))
          .expect(200)
      ).body as { shared: { revision: number } };
    }
    async function artifact(name: string, data: unknown) {
      const dir = process.env.WEB07_PUBLIC_CONTRACT_DIR;
      if (!dir) return;
      const path = resolve(dir);
      if (
        !/^\/(?:private\/)?tmp\/vynic-web07-info-[a-z0-9]+\//.test(path + '/')
      )
        throw Error('Only task-owned synthetic artifacts permitted');
      await mkdir(path, { recursive: true });
      await writeFile(resolve(path, name), JSON.stringify(data, null, 2));
    }
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('web07')
      )
        throw Error('Use a fresh disposable_web07 database');
      process.env.JWT_SECRET = 'web07-synthetic-jwt-only';
      process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.localhost';
      const config = new ConfigService({
        NODE_ENV: 'production',
        SAAS_WEBSITE_BASE_DOMAIN: 'vynic.localhost',
        TRUST_PROXY_HOST: 'false',
      });
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const jwt = new JwtService(),
        entitlements = new VenueEntitlementsService(db),
        capabilities = new WebsiteCapabilitiesService(db, entitlements),
        info = new VenuePublicProfileService(db, capabilities),
        menus = new WebsiteMenuService(db),
        tenants = new WebsiteTenantService(db, config),
        core = new WebsiteCoreService(
          db,
          entitlements,
          tenants,
          config,
          menus,
          capabilities,
          info,
        );
      for (const [i, mode] of (
        ['CUSTOM', 'SAAS', 'CUSTOM'] as const
      ).entries()) {
        const tag = randomUUID();
        const org = await db.organization.create({
          data: { name: 'WEB07 synthetic org' },
        });
        const host = `web07-${i}-${tag}.test.invalid`;
        const venue = await db.venue.create({
          data: {
            organizationId: org.id,
            name: `Synthetic venue ${i}`,
            address: `Old public address ${i}`,
            phone: '+995 599 98 93 76',
            legalId: 'private-legal-fixture',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            subscription: { create: { status: 'ACTIVE' } },
            planAssignment: {
              create: { plan: { connect: { key: 'WEBSITE_ONLY' } } },
            },
            websiteConfig: {
              create: {
                mode,
                assignedSlug: `web07-${i}-${tag}`,
                status: mode === 'SAAS' ? 'PUBLISHED' : 'DRAFT',
                published:
                  mode === 'SAAS'
                    ? { ...emptyWebsiteContent, slug: `web07-${i}-${tag}` }
                    : undefined,
                slug: mode === 'SAAS' ? `web07-${i}-${tag}` : undefined,
                revision: mode === 'SAAS' ? 1 : 0,
                publishedRevision: mode === 'SAAS' ? 1 : undefined,
                publishedAt: mode === 'SAAS' ? new Date() : undefined,
              },
            },
            domains: { create: { hostname: host } },
            ...(mode === 'CUSTOM'
              ? {
                  customWebsite: {
                    create: {
                      siteKey: i === 0 ? 'vankisi-web' : 'other-client-web',
                      status: 'ACTIVE',
                    },
                  },
                }
              : {}),
          },
        });
        const storageKey = `${tag}.webp`;
        await db.websiteMediaAsset.create({
          data: {
            venueId: venue.id,
            storageKey,
            purpose: 'GALLERY',
            byteSize: 100,
          },
        });
        const account = await db.customerAccount.create({
          data: {
            email: `owner-${tag}@test.invalid`,
            displayName: 'Synthetic owner',
            passwordHash: 'unused-fixture',
            memberships: { create: { organizationId: org.id, role: 'OWNER' } },
          },
        });
        const token = await jwt.signAsync(
          { sub: account.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        );
        rows.push({ id: venue.id, host, token, storageKey, mode });
      }
      const mod = await Test.createTestingModule({
        controllers: [
          CustomerController,
          CustomerWebsiteController,
          WebsiteVenueController,
          WebsiteCoreController,
        ],
        providers: [
          { provide: PrismaService, useValue: db },
          { provide: ConfigService, useValue: config },
          { provide: JwtService, useValue: jwt },
          { provide: VenueEntitlementsService, useValue: entitlements },
          { provide: WebsiteCapabilitiesService, useValue: capabilities },
          { provide: WebsiteTenantService, useValue: tenants },
          { provide: WebsiteMenuService, useValue: menus },
          { provide: WebsiteCoreService, useValue: core },
          { provide: VenuePublicProfileService, useValue: info },
          {
            provide: WebsiteVenueService,
            useValue: new WebsiteVenueService(
              db,
              entitlements,
              capabilities,
              info,
              menus,
            ),
          },
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
          {
            provide: WebsitePreviewTokens,
            useValue: new WebsitePreviewTokens(db, jwt),
          },
          HostnameRequestsService,
          WebsiteLogoService,
        ],
      }).compile();
      app = mod.createNestApplication({ logger: false });
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      process.env = oldEnv;
    });
    it('owner live profile/info edits reach CUSTOM and SAAS without another page publication', async () => {
      await artifact('custom-before.json', (await shared()).data);
      for (const i of [0, 1]) {
        await http()
          .put(profilePath(i))
          .set(owner(i))
          .send({
            name: `Synthetic venue ${i}`,
            address: `Updated public address ${i}`,
            phone: '+995 555 12 34 56',
            legalId: 'private-legal-fixture',
          })
          .expect(200);
        await http()
          .put(infoPath(i))
          .set(owner(i))
          .send({ expectedRevision: 0, ...fields(i) })
          .expect(200);
        const site = (await shared(i)).data;
        expect(site.profile).toMatchObject({
          address: `Updated public address ${i}`,
          phone: '+995 555 12 34 56',
        });
        expect(site.info).toEqual(fields(i));
        expect(site.capabilities).toMatchObject({ hours: true, gallery: true });
        expect(site.profile).not.toHaveProperty('legalId');
        if (i === 1) {
          const page = (
            await http()
              .get('/api/website/bootstrap')
              .set('Host', rows[i].host)
              .expect(200)
          ).body as { profile: VenueProfile; content: VenueInfo };
          expect(page.content).toMatchObject(fields(i));
          expect(page.profile.phone).toBe(site.profile.phone);
        }
      }
      await artifact('custom-after.json', (await shared()).data);
    });
    it('foreign owner cannot change contact/profile or public information', async () => {
      const before = (await shared()).data;
      await http()
        .put(profilePath())
        .set(owner(2))
        .send({ name: 'Foreign edit', phone: '+995555000000' })
        .expect(404);
      await http()
        .put(infoPath())
        .set(owner(2))
        .send({ expectedRevision: 1, contactEmail: 'foreign@test.invalid' })
        .expect(404);
      expect((await shared()).data).toEqual(before);
    });
    it('Host decides the public Venue despite query/body-like tenant selectors', async () => {
      const res = await http()
        .get(`/api/website/venue?venueId=${rows[2].id}`)
        .set('Host', rows[0].host)
        .set('X-Venue-Id', rows[2].id)
        .expect(200);
      expect((res.body as CustomSiteBootstrap).profile.address).toBe(
        'Updated public address 0',
      );
      await http()
        .get('/api/website/venue')
        .set('Host', 'unregistered.test.invalid')
        .expect(404);
    });
    it('stale owner revision is refused; editing invalid content leaves the current public snapshot', async () => {
      const before = (await shared()).data;
      await http()
        .put(infoPath())
        .set(owner())
        .send({ expectedRevision: 0, contactEmail: 'stale@test.invalid' })
        .expect(409);
      await http()
        .put(infoPath())
        .set(owner())
        .send({ expectedRevision: 1, mapUrl: 'javascript:alert(1)' })
        .expect(400);
      await http()
        .put(infoPath())
        .set(owner())
        .send({
          expectedRevision: 1,
          gallery: [
            {
              url: `/media/website-logos/${rows[2].storageKey}`,
              alt: 'Foreign image',
            },
          ],
        })
        .expect(403);
      expect((await shared()).data).toEqual(before);
    });
    it('a saved edit changes ETag and an old conditional request receives current information', async () => {
      const old = await shared();
      await http()
        .put(infoPath())
        .set(owner())
        .send({ expectedRevision: 1, contactEmail: 'changed@test.invalid' })
        .expect(200);
      const res = await http()
        .get('/api/website/venue')
        .set('Host', rows[0].host)
        .set('If-None-Match', old.etag)
        .expect(200);
      expect(res.headers.etag).not.toBe(old.etag);
      expect((res.body as CustomSiteBootstrap).info.contactEmail).toBe(
        'changed@test.invalid',
      );
    });
    it('operator-off hours/gallery are projected empty and cannot be restored by owner writes', async () => {
      for (const key of ['HOURS', 'GALLERY'] as const)
        await db.venueWebsiteCapability.create({
          data: { venueId: rows[0].id, capability: key, enabled: false },
        });
      const site = (await shared()).data;
      expect(site.capabilities).toMatchObject({ hours: false, gallery: false });
      expect(site.info.workingHours).toEqual([]);
      expect(site.info.gallery).toEqual([]);
      await http()
        .put(infoPath())
        .set(owner())
        .send({ expectedRevision: 2, workingHours: [] })
        .expect(403);
      await artifact('custom-capability-off.json', site);
    });
    it('deliberate empty contact is not replaced by legacy hardcoded values', async () => {
      const rev = (await saved(1)).shared.revision;
      await http()
        .put(profilePath(1))
        .set(owner(1))
        .send({ name: 'Synthetic venue 1', phone: '', address: '' })
        .expect(200);
      await http()
        .put(infoPath(1))
        .set(owner(1))
        .send({
          expectedRevision: rev,
          contactEmail: '',
          mapUrl: '',
          socials: [],
        })
        .expect(200);
      const site = (await shared(1)).data;
      expect(site.profile).toMatchObject({ phone: null, address: null });
      expect(site.info).toMatchObject({
        contactEmail: '',
        mapUrl: '',
        socials: [],
      });
    });
    it('CUSTOM identity and setup status remain server-owned, and unpublished SAAS does not expose info', async () => {
      await db.customWebsiteBinding.update({
        where: { venueId: rows[0].id },
        data: { status: 'SETUP_PENDING' },
      });
      expect((await shared()).data.site).toMatchObject({
        key: 'vankisi-web',
        status: 'SETUP_PENDING',
      });
      await db.venueWebsiteConfig.update({
        where: { venueId: rows[1].id },
        data: {
          status: 'DRAFT',
          published: Prisma.DbNull,
          publishedRevision: null,
          publishedAt: null,
          slug: null,
        },
      });
      await http()
        .get('/api/website/venue')
        .set('Host', rows[1].host)
        .expect(404);
    });
  },
);
