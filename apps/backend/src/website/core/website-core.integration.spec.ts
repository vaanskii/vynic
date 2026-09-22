import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { PrismaService } from '../../prisma.service';
import { CustomerAuth } from '../../customer/customer-auth';
import { CustomerService } from '../../customer/customer.service';
import { CustomerWebsiteController } from '../../customer/customer-website.controller';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteCoreService } from './website-core.service';
import { WebsiteCoreController } from './website-core.controller';
import { emptyWebsiteContent } from './website-content';

const url = process.env.W2_TEST_DATABASE_URL;
(url ? describe : describe.skip)('W2 disposable PostgreSQL / HTTP', () => {
  let db: PrismaService, app: any, core: WebsiteCoreService, featureId: string;
  const venues: any[] = [],
    owners: any[] = [],
    tag = randomUUID().slice(0, 8);
  const config = new ConfigService({
    NODE_ENV: 'development',
    SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local',
    TRUST_PROXY_HOST: 'false',
  });
  const http = () => request(app.getHttpServer());
  const path = (i: number) => `/customer/venues/${venues[i].id}/website`;
  const auth = (i: number) => ({ Authorization: `Bearer ${owners[i].token}` });
  const content = (i: number, heroTitle = `Published ${i}`) => ({
    ...emptyWebsiteContent,
    slug: `w2-${i}-${tag}`,
    heroTitle,
  });
  const host = (i: number) => `${content(i).slug}.vynic.local`;
  const publicGet = (i: number) =>
    http().get('/api/website/bootstrap').set('Host', host(i));
  const save = (i: number, expectedRevision: number, c = content(i)) =>
    http()
      .put(`${path(i)}/draft`)
      .set(auth(i))
      .send({ expectedRevision, content: c });
  const publish = (i: number, expectedRevision: number) =>
    http()
      .post(`${path(i)}/publish`)
      .set(auth(i))
      .send({ expectedRevision });
  beforeAll(async () => {
    const u = new URL(url!);
    if (
      u.hostname !== '127.0.0.1' ||
      u.port !== '55439' ||
      u.pathname !== '/vynic_w2_disposable'
    )
      throw Error('Only disposable W2 database permitted');
    process.env.JWT_SECRET = 'w2-local-test-only';
    db = new PrismaService({ datasourceUrl: url });
    const access = new VenueEntitlementsService(db),
      jwt = new JwtService();
    const hosts = new WebsiteTenantService(db, config);
    core = new WebsiteCoreService(db, access, hosts, config);
    featureId = (
      await db.feature.findUniqueOrThrow({ where: { key: 'WEBSITE' } })
    ).id;
    for (let i = 0; i < 3; i++) {
      const org = await db.organization.create({
        data: { name: `W2 org ${i}` },
      });
      venues.push(
        await db.venue.create({
          data: {
            organizationId: org.id,
            name: `W2 restaurant ${i}`,
            address: 'Public address',
            legalId: 'private-legal',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            websiteConfig: { create: { mode: i === 2 ? 'CUSTOM' : 'SAAS' } },
            domains: { create: { hostname: host(i) } },
            featureOverrides: { create: { featureId, effect: 'ENABLED' } },
          },
        }),
      );
      const owner = await db.customerAccount.create({
        data: {
          organizationId: org.id,
          email: `w2-${i}-${tag}@test.invalid`,
          displayName: 'Owner',
          passwordHash: 'unused',
        },
      });
      owners.push({
        ...owner,
        token: await jwt.signAsync(
          { sub: owner.id, typ: 'CUSTOMER' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-customer',
            issuer: 'vynic',
          },
        ),
      });
    }
    const mod = await Test.createTestingModule({
      controllers: [CustomerWebsiteController, WebsiteCoreController],
      providers: [
        { provide: WebsiteCoreService, useValue: core },
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
    app = mod.createNestApplication();
    await app.init();
  });
  afterAll(async () => {
    await app?.close();
    await db?.$disconnect();
  });
  it('requires owner authority for settings, edits, preview and publish', async () => {
    await http().get(path(0)).expect(401);
    await http()
      .get(`${path(0)}/preview`)
      .expect(401);
    await http().get(path(0)).set(auth(1)).expect(404);
    await http()
      .get(`${path(0)}/preview`)
      .set(auth(1))
      .expect(404);
    await http()
      .put(`${path(0)}/draft`)
      .set(auth(1))
      .send({ expectedRevision: 0, content: content(0) })
      .expect(404);
    await http()
      .post(`${path(0)}/publish`)
      .set(auth(1))
      .send({ expectedRevision: 0 })
      .expect(404);
  });
  it('drafts stay private, preview is authenticated and no-store, explicit publish exposes each Venue only', async () => {
    for (let i = 0; i < 2; i++) {
      await save(i, 0).expect(200);
      await publicGet(i).expect(404);
      const preview = await http()
        .get(`${path(i)}/preview`)
        .set(auth(i))
        .expect(200);
      expect(preview.body.content.heroTitle).toBe(`Published ${i}`);
      expect(preview.headers['cache-control']).toContain('no-store');
      expect(preview.body.profile).not.toHaveProperty('legalId');
      await publish(i, 1).expect(201);
      const res = await publicGet(i).expect(200);
      expect(res.body).toMatchObject({
        schemaVersion: 1,
        mode: 'SAAS',
        preview: false,
        revision: 1,
        content: content(i),
      });
      expect(res.body.profile.name).toBe(venues[i].name);
      expect(res.body).not.toHaveProperty('draft');
    }
  });
  it('edits do not change published state; stale save/publish rejected and only A changes on publish', async () => {
    const beforeB = (await publicGet(1)).body;
    await save(0, 1, content(0, 'Private draft A')).expect(200);
    expect((await publicGet(0)).body.content.heroTitle).toBe('Published 0');
    await save(0, 1).expect(409);
    await publish(0, 1).expect(409);
    await publish(0, 2).expect(201);
    expect((await publicGet(0)).body.content.heroTitle).toBe('Private draft A');
    expect((await publicGet(1)).body).toEqual(beforeB);
    await publish(0, 2).expect(201); // no duplicate publication audit
    const events = await db.customerAuditEvent.findMany({
      where: { targetId: venues[0].id },
    });
    expect(events.filter((e) => e.action === 'website.published')).toHaveLength(
      2,
    );
    expect(
      events.filter((e) => e.action === 'website.draft_saved'),
    ).toHaveLength(2);
    expect(JSON.stringify(events)).not.toContain('Private draft A');
  });
  it('forged IDs/forwarded headers do not override Host, unknown hosts have no local fallback', async () => {
    const res = await http()
      .get(`/api/website/bootstrap?venueId=${venues[1].id}`)
      .set('Host', host(0))
      .set('X-Venue-Id', venues[1].id)
      .set('X-Forwarded-Host', host(1))
      .send({ venueId: venues[1].id })
      .expect(200);
    expect(res.body.content.slug).toBe(content(0).slug);
    for (const h of [
      'unknown.vynic.local',
      'localhost',
      'unregistered.localhost',
    ])
      await http()
        .get(`/api/website/bootstrap?venueId=${venues[0].id}`)
        .set('Host', h)
        .expect(404);
  });
  it('CUSTOM is a marker only; NONE, disabled entitlement, domain and Venue block public SaaS', async () => {
    expect((await publicGet(2).expect(200)).body).toEqual({
      schemaVersion: 1,
      mode: 'CUSTOM',
    });
    await save(2, 0).expect(403);
    await publish(2, 0).expect(403);
    await db.venueWebsiteConfig.update({
      where: { venueId: venues[1].id },
      data: { mode: 'NONE' },
    });
    await publicGet(1).expect(404);
    await db.venueWebsiteConfig.update({
      where: { venueId: venues[1].id },
      data: { mode: 'SAAS' },
    });
    await db.venueFeatureOverride.updateMany({
      where: { venueId: venues[1].id, featureId },
      data: { effect: 'DISABLED' },
    });
    await publicGet(1).expect(404);
    await publish(1, 1).expect(403);
    await save(1, 1, content(1, 'Offline draft')).expect(200);
    await http()
      .get(`${path(1)}/preview`)
      .set(auth(1))
      .expect(200);
    await db.venueFeatureOverride.updateMany({
      where: { venueId: venues[1].id, featureId },
      data: { effect: 'ENABLED' },
    });
    await db.venueDomain.update({
      where: { hostname: host(1) },
      data: { status: 'DISABLED' },
    });
    await publicGet(1).expect(404);
    await db.venueDomain.update({
      where: { hostname: host(1) },
      data: { status: 'ACTIVE' },
    });
    await db.venue.update({
      where: { id: venues[1].id },
      data: { status: 'DISABLED' },
    });
    await publicGet(1).expect(404);
    await db.venue.update({
      where: { id: venues[1].id },
      data: { status: 'ACTIVE' },
    });
  });
  it('cannot claim another Venue domain/slug, failed publish leaves published state unchanged', async () => {
    await save(0, 2, { ...content(0), slug: content(1).slug }).expect(200);
    await publish(0, 3).expect(409);
    expect((await publicGet(0)).body.content.heroTitle).toBe('Private draft A');
    expect((await publicGet(1)).body.content.heroTitle).toBe('Published 1');
  });
  it('concurrent edits accept one revision; audit failure rolls back content and revision', async () => {
    const results = await Promise.all([
      save(0, 3, content(0, 'First')),
      save(0, 3, content(0, 'Second')),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    await expect(
      core.save(
        venues[0].id,
        { expectedRevision: 4, content: content(0) },
        randomUUID(),
      ),
    ).rejects.toThrow();
    expect(
      (
        await db.venueWebsiteConfig.findUniqueOrThrow({
          where: { venueId: venues[0].id },
        })
      ).revision,
    ).toBe(4);
  });
  it('rejects tenant fields, unsafe URLs, invalid hours, oversized content, and unknown themes', async () => {
    for (const patch of [
      { venueId: venues[1].id },
      { themeKey: 'unknown' },
      { about: 'x'.repeat(5001) },
      { socials: [{ label: 'bad', url: 'javascript:alert(1)' }] },
      { workingHours: [{ day: 1, opens: '99:00', closes: '10:00' }] },
    ]) {
      await save(0, 4, { ...content(0), ...patch } as any).expect(400);
    }
    await http()
      .put(`${path(0)}/draft`)
      .set(auth(0))
      .send({ venueId: venues[1].id, expectedRevision: 4, content: content(0) })
      .expect(400);
  });
  it('trusted proxy authority fails closed and commercial suspension blocks SaaS', async () => {
    config.set('TRUST_PROXY_HOST', 'true');
    try {
      const res = await http()
        .get('/api/website/bootstrap')
        .set('Host', host(0))
        .set('X-Forwarded-Host', host(1))
        .expect(200);
      expect(res.body.content.slug).toBe(content(1).slug);
      for (const forwarded of ['unknown.invalid', 'https://malformed.invalid'])
        await http()
          .get('/api/website/bootstrap')
          .set('Host', host(0))
          .set('X-Forwarded-Host', forwarded)
          .expect(404);
    } finally {
      config.set('TRUST_PROXY_HOST', 'false');
    }
    await db.venueSubscription.create({
      data: { venueId: venues[1].id, status: 'SUSPENDED' },
    });
    await publicGet(1).expect(404);
    await publish(1, 2).expect(403);
    await db.venueSubscription.delete({ where: { venueId: venues[1].id } });
  });
  it('publish atomically claims a new subdomain and profiles remain sourced from Venue', async () => {
    const c = { ...content(0), slug: `new-${tag}` };
    await save(0, 4, c).expect(200);
    await http()
      .get('/api/website/bootstrap')
      .set('Host', `${c.slug}.vynic.local`)
      .expect(404);
    await publish(0, 5).expect(201);
    await db.venue.update({
      where: { id: venues[0].id },
      data: { name: 'Updated profile' },
    });
    const res = await http()
      .get('/api/website/bootstrap')
      .set('Host', `${c.slug}.vynic.local`)
      .expect(200);
    expect(res.body.profile.name).toBe('Updated profile');
    expect(res.body.content).not.toHaveProperty('name');
  });
});
