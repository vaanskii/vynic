import type { Server } from 'node:http';
import type { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { CustomerAuth } from '../src/customer/customer-auth';
import { CustomerWebsiteController } from '../src/customer/customer-website.controller';
import { CustomerService } from '../src/customer/customer.service';
import { EnrollmentRateLimiter } from '../src/edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../src/entitlements/venue-entitlements.service';
import { PrismaService } from '../src/prisma.service';
import { HostnameRequestsService } from '../src/website/core/hostname-requests';
import { VenuePublicProfileService } from '../src/website/core/venue-public-profile.service';
import { WebsiteCoreController } from '../src/website/core/website-core.controller';
import { WebsiteCoreService } from '../src/website/core/website-core.service';
import { WebsiteLogoService } from '../src/website/core/website-logo.service';
import { WebsiteMenuService } from '../src/website/core/website-menu.service';
import { WebsitePreviewTokens } from '../src/website/core/website-preview';
import { WebsiteVenueController } from '../src/website/core/website-venue.controller';
import { WebsiteVenueService } from '../src/website/core/website-venue.service';
import { WebsiteCapabilitiesService } from '../src/website/tenancy/website-capabilities.service';
import { WebsiteCapabilityGuard } from '../src/website/tenancy/website-capability.guard';
import { WebsiteTenantGuard } from '../src/website/tenancy/website-tenant.guard';
import { WebsiteTenantService } from '../src/website/tenancy/website-tenant.service';
import { isFreshDisposableDatabase } from './disposable-database';
import {
  WEB02_BASE_DOMAIN,
  fixtures,
  type FixtureKey,
  type LiveInfo,
} from './web02-public-info.fixture';

/**
 * The real public website surface for WEB-02 upgrade proofs: the SAAS
 * bootstrap, the shared `/api/website/venue` contract (CUSTOM and SAAS) and
 * the owner Dashboard, over one Prisma client on a disposable database.
 * Production host resolution: unknown/disabled hosts fail closed.
 */
export async function web02App(url: string, mediaDir: string) {
  if (!isFreshDisposableDatabase(url) || !url.includes('_web02_'))
    throw Error(
      'WEB-02 proofs run only on a fresh disposable_*_web02_* database',
    );
  process.env.JWT_SECRET = 'web02-local-test-only';
  const db = new PrismaService({ datasourceUrl: url });
  const config = new ConfigService({
    NODE_ENV: 'production',
    SAAS_WEBSITE_BASE_DOMAIN: WEB02_BASE_DOMAIN,
    TRUST_PROXY_HOST: 'false',
    SAAS_WEBSITE_PREVIEW_ORIGIN: 'http://preview.vynic.local:5175',
    WEBSITE_MEDIA_DIR: mediaDir,
  });
  const jwt = new JwtService();
  const access = new VenueEntitlementsService(db);
  const tenants = new WebsiteTenantService(db, config);
  const capabilities = new WebsiteCapabilitiesService(db, access);
  const publicInfo = new VenuePublicProfileService(db, capabilities);
  const menus = new WebsiteMenuService(db);
  const core = new WebsiteCoreService(
    db,
    access,
    tenants,
    config,
    menus,
    capabilities,
    publicInfo,
  );
  const logos = new WebsiteLogoService(config, db);
  const mod = await Test.createTestingModule({
    controllers: [
      WebsiteCoreController,
      WebsiteVenueController,
      CustomerWebsiteController,
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
      { provide: WebsiteCoreService, useValue: core },
      { provide: WebsiteMenuService, useValue: menus },
      {
        provide: WebsitePreviewTokens,
        useValue: new WebsitePreviewTokens(db, jwt),
      },
      HostnameRequestsService,
      { provide: WebsiteLogoService, useValue: logos },
      {
        provide: CustomerService,
        useValue: new CustomerService(db, access, {} as never, {} as never),
      },
      {
        provide: CustomerAuth,
        useValue: new CustomerAuth(db, jwt, new EnrollmentRateLimiter()),
      },
    ],
  }).compile();
  const app: INestApplication = mod.createNestApplication();
  await app.init();
  const http = () => request(app.getHttpServer() as Server);
  return { db, app, http, jwt, capabilities, logos };
}

/** A Dashboard owner of the fixture Venue's organization (created post-upgrade). */
export async function ownerToken(
  db: PrismaService,
  jwt: JwtService,
  key: FixtureKey,
) {
  const organizationId = `web02-org-${key}`;
  const owner = await db.customerAccount.create({
    data: {
      organizationId,
      memberships: { create: { organizationId, role: 'OWNER' } },
      email: `owner-${key}-${Date.now()}@web02.test`,
      displayName: `Owner ${key}`,
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
  return { id: owner.id, auth: { Authorization: `Bearer ${token}` } };
}

export async function platformUser(
  db: PrismaService,
  status: 'ACTIVE' | 'DISABLED' = 'ACTIVE',
) {
  return db.platformUser.create({
    data: {
      email: `operator-${status.toLowerCase()}-${Date.now()}@web02.test`,
      displayName: `WEB-02 operator ${status}`,
      passwordHash: 'unused',
      status,
    },
  });
}

/** A JSON response body, read as data rather than `any`. */
export type Json = Record<string, unknown>;
export const json = (response: { body: unknown }) => response.body as Json;
/** The SAAS page payload's `content` (page document + shared fields). */
export const content = (response: { body: unknown }) =>
  json(response).content as Json;
/** The shared `/api/website/venue` contract's `info`. */
export const info = (response: { body: unknown }) =>
  json(response).info as Json;

/** The five shared fields a public response carries. */
export function shared(body: Record<string, unknown>): LiveInfo {
  return {
    workingHours: body.workingHours as LiveInfo['workingHours'],
    contactEmail: body.contactEmail as string,
    mapUrl: body.mapUrl as string,
    socials: body.socials as LiveInfo['socials'],
    gallery: body.gallery as LiveInfo['gallery'],
  };
}

/** Text that belongs to one fixture Venue and must never cross to another. */
export function markers(key: FixtureKey) {
  return [
    `a-${key}@`,
    `b-${key}@`,
    `maps.example/a-${key}`,
    `maps.example/b-${key}`,
    `published ${key}`,
    `draft ${key}`,
    `Hero ${key}`,
  ];
}

/** Text of a private (never-published) draft value that must not be public. */
export function privateMarkers(key: FixtureKey) {
  const fixture = fixtures.find((f) => f.key === key)!;
  if (!fixture.expectedPrivateDraft) return [];
  return [
    fixture.expectedPrivateDraft.contactEmail,
    fixture.expectedPrivateDraft.mapUrl,
    ...fixture.expectedPrivateDraft.socials.map((s) => s.label),
    ...fixture.expectedPrivateDraft.gallery.map((g) => g.url),
  ].filter(
    (value) =>
      value &&
      !JSON.stringify(fixture.expectedLive).includes(JSON.stringify(value)),
  );
}
