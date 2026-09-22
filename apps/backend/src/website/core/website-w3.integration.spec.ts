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
import { WebsiteMenuService } from './website-menu.service';
import { WebsitePreviewTokens } from './website-preview';
import { WebsiteCoreController } from './website-core.controller';
import { emptyWebsiteContent } from './website-content';

/**
 * W3 isolation proof for the generic SaaS website.
 *
 * Four Venues stand for the four shapes a deployment actually has: two
 * published SaaS restaurants, one on the custom product, and one with the
 * website entitlement withheld. Every claim below is about one restaurant not
 * being able to see, change or be affected by another.
 */
const url = process.env.W3_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'W3 website product / disposable PostgreSQL',
  () => {
    const tag = randomUUID().slice(0, 8);
    const config = new ConfigService({
      NODE_ENV: 'development',
      SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local',
      TRUST_PROXY_HOST: 'false',
      SAAS_WEBSITE_PREVIEW_ORIGIN: 'http://preview.vynic.local:5175',
    });
    // A = SAAS, B = SAAS, C = CUSTOM, D = NONE without the WEBSITE entitlement.
    const shapes = [
      { key: 'a', mode: 'SAAS', entitled: true },
      { key: 'b', mode: 'SAAS', entitled: true },
      { key: 'c', mode: 'CUSTOM', entitled: true },
      { key: 'd', mode: 'NONE', entitled: false },
    ] as const;

    let db: PrismaService, app: any, jwt: JwtService;
    const venues: any[] = [],
      owners: any[] = [],
      items: Record<string, string[]> = {};
    const slug = (i: number) => `w3-${shapes[i].key}-${tag}`;
    const host = (i: number) => `${slug(i)}.vynic.local`;
    const http = () => request(app.getHttpServer());
    const path = (i: number) => `/customer/venues/${venues[i].id}/website`;
    const auth = (i: number) => ({
      Authorization: `Bearer ${owners[i].token}`,
    });
    const content = (i: number, patch: Record<string, unknown> = {}) => ({
      ...emptyWebsiteContent,
      slug: slug(i),
      heroTitle: `Hero ${shapes[i].key.toUpperCase()}`,
      ...patch,
    });
    const publicGet = (i: number, route = 'bootstrap') =>
      http().get(`/api/website/${route}`).set('Host', host(i));
    /** Revision-safe helpers: the contract is proved elsewhere, not re-counted here. */
    const revision = async (i: number) =>
      (await http().get(path(i)).set(auth(i)).expect(200)).body
        .revision as number;
    const saveDraft = async (i: number, patch: Record<string, unknown> = {}) =>
      http()
        .put(`${path(i)}/draft`)
        .set(auth(i))
        .send({
          expectedRevision: await revision(i),
          content: content(i, patch),
        })
        .expect(200);
    const publishNow = async (i: number) =>
      http()
        .post(`${path(i)}/publish`)
        .set(auth(i))
        .send({ expectedRevision: await revision(i) })
        .expect(201);
    const previewToken = async (i: number) =>
      (
        await http()
          .post(`${path(i)}/preview-session`)
          .set(auth(i))
          .send({})
          .expect(201)
      ).body.token as string;

    beforeAll(async () => {
      const u = new URL(url!);
      if (
        u.hostname !== '127.0.0.1' ||
        u.port !== '55439' ||
        u.pathname !== '/vynic_w3_disposable'
      )
        throw Error('Only the disposable website database is permitted');
      process.env.JWT_SECRET = 'website-w3-local-test-only';
      db = new PrismaService({ datasourceUrl: url });
      jwt = new JwtService();
      const access = new VenueEntitlementsService(db);
      const menus = new WebsiteMenuService(db);
      const core = new WebsiteCoreService(
        db,
        access,
        new WebsiteTenantService(db, config),
        config,
        menus,
      );
      const featureId = (
        await db.feature.findUniqueOrThrow({ where: { key: 'WEBSITE' } })
      ).id;

      for (const [i, shape] of shapes.entries()) {
        const org = await db.organization.create({
          data: { name: `W3 org ${shape.key} ${tag}` },
        });
        const venue = await db.venue.create({
          data: {
            organizationId: org.id,
            name: `W3 ${shape.key.toUpperCase()}`,
            address: `${i} Test Street`,
            legalId: 'private-legal',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            websiteConfig: { create: { mode: shape.mode } },
            domains: { create: { hostname: host(i) } },
            featureOverrides: {
              create: {
                featureId,
                effect: shape.entitled ? 'ENABLED' : 'DISABLED',
              },
            },
          },
        });
        venues.push(venue);
        // Each restaurant gets its own operational menu, so a crossed boundary
        // would show up as another restaurant's dish rather than as an id.
        const category = await db.menuCategory.create({
          data: {
            venueId: venue.id,
            slug: `cat-${shape.key}`,
            nameKa: `კატეგორია ${shape.key}`,
            nameEn: `Category ${shape.key}`,
          },
        });
        items[shape.key] = [];
        for (const label of ['Public', 'Hidden']) {
          const item = await db.menuItem.create({
            data: {
              venueId: venue.id,
              categoryId: category.id,
              nameKa: `${label} ${shape.key}`,
              nameEn: `${label} ${shape.key}`,
              price: 10,
              sortOrder: label === 'Public' ? 0 : 1,
            },
          });
          items[shape.key].push(item.id);
        }
        const owner = await db.customerAccount.create({
          data: {
            organizationId: org.id,
            memberships: { create: { organizationId: org.id, role: "OWNER" } },
            email: `w3-${shape.key}-${tag}@test.invalid`,
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
          { provide: WebsiteMenuService, useValue: menus },
          {
            provide: WebsitePreviewTokens,
            useValue: new WebsitePreviewTokens(db, jwt),
          },
          { provide: ConfigService, useValue: config },
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

      // A and B publish; C and D deliberately do not.
      for (const i of [0, 1]) {
        await http()
          .put(`${path(i)}/draft`)
          .set(auth(i))
          .send({
            expectedRevision: 0,
            content: content(i, {
              logoUrl: `/media/${shapes[i].key}/logo.svg`,
              gallery: [{ url: `/media/${shapes[i].key}/one.jpg`, alt: 'One' }],
            }),
          })
          .expect(200);
        await http()
          .post(`${path(i)}/publish`)
          .set(auth(i))
          .send({ expectedRevision: 1 })
          .expect(201);
        await http()
          .put(`${path(i)}/menu`)
          .set(auth(i))
          .send({
            items: [
              {
                menuItemId: items[shapes[i].key][1],
                visibleOnWebsite: false,
                displayName: null,
                description: null,
                imageUrl: null,
                sortOrder: 0,
              },
            ],
          })
          .expect(200);
      }
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('serves each host only its own restaurant, content, media and menu', async () => {
      for (const i of [0, 1]) {
        const other = shapes[1 - i].key;
        const site = (await publicGet(i).expect(200)).body;
        expect(site).toMatchObject({
          schemaVersion: 2,
          mode: 'SAAS',
          preview: false,
        });
        expect(site.profile.name).toBe(venues[i].name);
        expect(site.content.heroTitle).toBe(
          `Hero ${shapes[i].key.toUpperCase()}`,
        );
        expect(site.content.logoUrl).toBe(`/media/${shapes[i].key}/logo.svg`);
        expect(JSON.stringify(site)).not.toContain(`/media/${other}/`);
        expect(site.profile).not.toHaveProperty('legalId');

        const menu = (await publicGet(i, 'menu').expect(200)).body;
        const names = menu.categories.flatMap((c: any) =>
          c.items.map((item: any) => item.name.en),
        );
        expect(names).toEqual([`Public ${shapes[i].key}`]);
        // The item hidden by presentation is gone, not merely flagged.
        expect(JSON.stringify(menu)).not.toContain('Hidden');
        expect(JSON.stringify(menu)).not.toContain(other.toUpperCase());
      }
    });

    it('ignores forged Venue identifiers in queries, bodies and headers', async () => {
      const forged = await http()
        .get(`/api/website/menu?venueId=${venues[1].id}`)
        .set('Host', host(0))
        .set('X-Venue-Id', venues[1].id)
        .set('X-Forwarded-Host', host(1))
        .expect(200);
      expect(JSON.stringify(forged.body)).toContain('Public a');
      expect(JSON.stringify(forged.body)).not.toContain('Public b');
      for (const unknown of ['unknown.vynic.local', 'localhost'])
        await http().get('/api/website/menu').set('Host', unknown).expect(404);
    });

    it('never returns a draft on a public route and publishing A leaves B untouched', async () => {
      const beforeB = (await publicGet(1).expect(200)).body;
      const beforeBMenu = (await publicGet(1, 'menu').expect(200)).body;

      await saveDraft(0, { heroTitle: 'SECRET DRAFT' });
      const publicA = await publicGet(0).expect(200);
      expect(JSON.stringify(publicA.body)).not.toContain('SECRET DRAFT');
      expect(publicA.headers['cache-control']).toBe('private, no-cache');

      await publishNow(0);
      expect((await publicGet(0)).body.content.heroTitle).toBe('SECRET DRAFT');
      expect((await publicGet(1)).body).toEqual(beforeB);
      expect((await publicGet(1, 'menu')).body).toEqual(beforeBMenu);
    });

    it('revalidates a published site by ETag without letting a stale one linger', async () => {
      const first = await publicGet(0).expect(200);
      const etag = first.headers.etag;
      expect(etag).toBeTruthy();
      await publicGet(0).set('If-None-Match', etag).expect(304);
      // A new publication changes the validator immediately, with no purge step.
      await saveDraft(0, { heroTitle: 'Revalidated' });
      await publishNow(0);
      const next = await publicGet(0).set('If-None-Match', etag).expect(200);
      expect(next.body.content.heroTitle).toBe('Revalidated');
      expect(next.headers.etag).not.toBe(etag);
    });

    it('keeps preview authority Venue-scoped, private and separate from the owner session', async () => {
      const tokenA = await previewToken(0);
      const draft = await http()
        .get('/api/website/preview/bootstrap')
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(200);
      expect(draft.body.preview).toBe(true);
      expect(draft.body.profile.name).toBe(venues[0].name);
      expect(draft.headers['cache-control']).toBe('private, no-store');
      expect(draft.headers['x-robots-tag']).toContain('noindex');

      // A's preview token cannot become B's, whatever host it arrives on.
      const onBHost = await http()
        .get('/api/website/preview/bootstrap')
        .set('Host', host(1))
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(200);
      expect(onBHost.body.profile.name).toBe(venues[0].name);
      const menu = await http()
        .get('/api/website/preview/menu')
        .set('Host', host(1))
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(200);
      expect(JSON.stringify(menu.body)).not.toContain('Public b');

      // A's owner cannot mint a preview session for B at all.
      await http()
        .post(`${path(1)}/preview-session`)
        .set(auth(0))
        .send({})
        .expect(404);
      // Neither credential works in the other's place.
      await http()
        .get('/api/website/preview/bootstrap')
        .set(auth(0))
        .expect(401);
      await http()
        .get(path(0))
        .set('Authorization', `Bearer ${tokenA}`)
        .expect(401);
      await http().get('/api/website/preview/bootstrap').expect(401);
    });

    it('refuses a preview token whose owner no longer holds the Venue', async () => {
      const token = await previewToken(1);
      const original = venues[1].organizationId;
      const stranger = await db.organization.create({
        data: { name: `W3 stranger ${tag}` },
      });
      await db.venue.update({
        where: { id: venues[1].id },
        data: { organizationId: stranger.id },
      });
      try {
        await http()
          .get('/api/website/preview/bootstrap')
          .set('Authorization', `Bearer ${token}`)
          .expect(401);
      } finally {
        await db.venue.update({
          where: { id: venues[1].id },
          data: { organizationId: original },
        });
      }
    });

    it('does not render a CUSTOM Venue as a generic site and refuses its generic menu', async () => {
      expect((await publicGet(2).expect(200)).body).toEqual({
        schemaVersion: 2,
        mode: 'CUSTOM',
      });
      await publicGet(2, 'menu').expect(404);
      await http()
        .get(`${path(2)}/menu`)
        .set(auth(2))
        .expect(200);
      await http()
        .post(`${path(2)}/preview-session`)
        .set(auth(2))
        .send({})
        .expect(403);
    });

    it('keeps an unentitled Venue off the public web even after a draft is prepared', async () => {
      await publicGet(3).expect(404);
      await publicGet(3, 'menu').expect(404);
      // NONE mode is not generic editing at all.
      await http()
        .put(`${path(3)}/draft`)
        .set(auth(3))
        .send({ expectedRevision: 0, content: content(3) })
        .expect(403);
      // With SAAS mode but no entitlement, drafting is allowed and publishing is not.
      await db.venueWebsiteConfig.update({
        where: { venueId: venues[3].id },
        data: { mode: 'SAAS' },
      });
      try {
        await http()
          .put(`${path(3)}/draft`)
          .set(auth(3))
          .send({ expectedRevision: 0, content: content(3) })
          .expect(200);
        await http()
          .post(`${path(3)}/publish`)
          .set(auth(3))
          .send({ expectedRevision: 1 })
          .expect(403);
        await publicGet(3).expect(404);
      } finally {
        await db.venueWebsiteConfig.update({
          where: { venueId: venues[3].id },
          data: { mode: 'NONE' },
        });
      }
    });

    it('scopes menu presentation to one Venue and rejects borrowed item identifiers', async () => {
      const borrowed = {
        items: [
          {
            menuItemId: items.b[0],
            visibleOnWebsite: false,
            displayName: 'Taken over',
            description: null,
            imageUrl: null,
            sortOrder: 0,
          },
        ],
      };
      await http()
        .put(`${path(0)}/menu`)
        .set(auth(0))
        .send(borrowed)
        .expect(400);
      await http()
        .put(`${path(1)}/menu`)
        .set(auth(0))
        .send(borrowed)
        .expect(404);
      // Nothing was written by either attempt.
      expect(
        await db.menuItemWebsitePresentation.findUnique({
          where: { menuItemId: items.b[0] },
        }),
      ).toBeNull();
      expect(JSON.stringify((await publicGet(1, 'menu')).body)).not.toContain(
        'Taken over',
      );
    });

    it('applies presentation overrides and refuses unsafe media references', async () => {
      await http()
        .put(`${path(0)}/menu`)
        .set(auth(0))
        .send({
          items: [
            {
              menuItemId: items.a[0],
              visibleOnWebsite: true,
              displayName: 'House speciality',
              description: 'Served all day',
              imageUrl: '/media/a/dish.jpg',
              sortOrder: 5,
            },
          ],
        })
        .expect(200);
      const item = (await publicGet(0, 'menu').expect(200)).body.categories[0]
        .items[0];
      expect(item).toMatchObject({
        displayName: 'House speciality',
        description: 'Served all day',
        imageUrl: '/media/a/dish.jpg',
        price: 10,
      });
      // The operational name is still the authority underneath the override.
      expect(item.name.en).toBe('Public a');

      for (const imageUrl of [
        'http://insecure.invalid/x.jpg',
        'javascript:alert(1)',
        '/media/../../etc/passwd',
        '/not-media/x.jpg',
        `data:image/png;base64,${'A'.repeat(64)}`,
      ])
        await http()
          .put(`${path(0)}/menu`)
          .set(auth(0))
          .send({
            items: [
              {
                menuItemId: items.a[0],
                visibleOnWebsite: true,
                displayName: null,
                description: null,
                imageUrl,
                sortOrder: 0,
              },
            ],
          })
          .expect(400);
    });

    it('removes presentation with the item it describes, leaving no orphan record', async () => {
      const doomed = await db.menuItem.create({
        data: {
          venueId: venues[0].id,
          nameKa: 'Retired',
          nameEn: 'Retired',
          price: 4,
        },
      });
      await http()
        .put(`${path(0)}/menu`)
        .set(auth(0))
        .send({
          items: [
            {
              menuItemId: doomed.id,
              visibleOnWebsite: true,
              displayName: 'Retired special',
              description: null,
              imageUrl: null,
              sortOrder: 0,
            },
          ],
        })
        .expect(200);
      await db.menuItem.delete({ where: { id: doomed.id } });
      expect(
        await db.menuItemWebsitePresentation.findUnique({
          where: { menuItemId: doomed.id },
        }),
      ).toBeNull();
      expect(JSON.stringify((await publicGet(0, 'menu')).body)).not.toContain(
        'Retired',
      );
    });

    it('answers an explicitly empty menu when the owner hides the section', async () => {
      await saveDraft(0, { heroTitle: 'No menu', showMenu: false });
      await publishNow(0);
      const menu = (await publicGet(0, 'menu').expect(200)).body;
      expect(menu).toMatchObject({ enabled: false, categories: [] });
    });

    it('reads content saved before a field existed without failing the page', async () => {
      // A row written by the previous content version, with no v2 fields at all.
      await db.venueWebsiteConfig.update({
        where: { venueId: venues[1].id },
        data: {
          published: {
            slug: slug(1),
            themeKey: 'classic',
            heroTitle: 'Legacy hero',
            heroSubtitle: '',
            about: '',
            seoTitle: '',
            seoDescription: '',
            workingHours: [],
            socials: [],
            gallery: [],
          },
        },
      });
      const site = (await publicGet(1).expect(200)).body;
      expect(site.content).toMatchObject({
        heroTitle: 'Legacy hero',
        logoUrl: '',
        showMenu: true,
        contactEmail: '',
      });
    });
  },
);
