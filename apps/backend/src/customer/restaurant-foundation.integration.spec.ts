import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { OwnerInvitationsService } from './owner-invitations.service';
import { PlatformVenueConfigService } from '../platform/platform-venue-config.service';
import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import request from 'supertest';
import sharp from 'sharp';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';

const url = process.env.FOUNDATION_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Website-only restaurant foundation (disposable PostgreSQL)',
  () => {
    let db: PrismaService, app: any;
    const owners: { token: string; id: string }[] = [];
    const tag = randomUUID().slice(0, 8);
    const ids = {
      category: randomUUID(),
      subcategory: randomUUID(),
      item: randomUUID(),
      variant: randomUUID(),
    };
    const http = () => request(app.getHttpServer());
    const auth = (index = 0) => ({
      Authorization: `Bearer ${owners[index].token}`,
    });
    const path = (suffix: string, index = 0) =>
      `/customer/venues/${owners[index].id}/${suffix}`;
    beforeAll(async () => {
      const parsed = new URL(url!);
      if (
        !isFreshDisposableDatabase(parsed) &&
        (parsed.hostname !== '127.0.0.1' ||
          !(
            (parsed.port === '55439' &&
              parsed.pathname === '/vynic_foundation_phase3_disposable') ||
            (parsed.port === '55437' &&
              parsed.pathname === '/vynic_commercial_test')
          ))
      )
        throw Error('Disposable foundation DB only');
      process.env.JWT_SECRET = 'foundation-test-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'foundation-test-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      const feature = await db.feature.upsert({
        where: { key: 'WEBSITE' },
        create: { key: 'WEBSITE', name: 'Website' },
        update: {},
      });
      const plan = await db.plan.upsert({
        where: { key: 'website-only-local' },
        create: {
          key: 'website-only-local',
          name: 'Website',
          features: { create: { featureId: feature.id } },
        },
        update: {},
      });
      await db.onboardingPolicy.upsert({
        where: { id: 'default' },
        create: {
          enabled: true,
          trialPlanId: plan.id,
          defaultWebsiteMode: 'SAAS',
        },
        update: {
          enabled: true,
          trialPlanId: plan.id,
          defaultWebsiteMode: 'SAAS',
        },
      });
      app = await onboardingApp(db);
      const admin = await db.platformUser.create({
        data: {
          email: `foundation-admin-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: 'unused',
        },
      });
      const actor = { platformUserId: admin.id, role: 'SUPER_ADMIN' } as any;
      for (const label of ['a', 'b']) {
        const prepared = await app
          .get(OwnerInvitationsService)
          .provision(actor, {
            organizationName: `Foundation ${label}`,
            name: `Foundation ${label}`,
            email: `${label}-${tag}@foundation.test.invalid`,
            planId: plan.id,
            subscriptionStatus: 'ACTIVE',
          });
        const accepted = await http()
          .post('/customer/invitations/register')
          .send({
            token: prepared.invitationPath.split('=')[1],
            displayName: `Owner ${label}`,
            password: 'Foundation test password!',
          })
          .expect(201);
        await app
          .get(PlatformVenueConfigService)
          .enableCloudMenu(actor, prepared.venue.id, true);
        owners.push({
          token: accepted.body.access_token,
          id: prepared.venue.id,
        });
      }
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });
    it('rejects owner catalog writes while Admin has disabled editing', async () => {
      await db.venue.update({
        where: { id: owners[0].id },
        data: { cloudMenuEditingEnabled: false },
      });
      try {
        const read = await http().get(path('catalog')).set(auth()).expect(200);
        expect(read.body.editingEnabled).toBe(false);
        await http()
          .post(path('catalog/mutations'))
          .set(auth())
          .send({
            mutationId: randomUUID(),
            entityType: 'CATEGORY',
            operation: 'UPSERT',
            entityId: randomUUID(),
            expectedRevision: 0,
            patch: { nameKa: 'დაბლოკილი', nameEn: 'Blocked' },
          })
          .expect(409);
      } finally {
        await db.venue.update({
          where: { id: owners[0].id },
          data: { cloudMenuEditingEnabled: true },
        });
      }
    });
    it('onboards without Device or Manager and permits profile editing', async () => {
      const res = await http().get('/customer/portal').set(auth()).expect(200);
      expect(res.body.venues[0]).toMatchObject({
        features: ['WEBSITE'],
        devices: [],
        managers: [],
        ready: true,
        venue: { menuAuthority: 'CLOUD' },
      });
      await http()
        .put(path('profile'))
        .set(auth())
        .send({
          name: 'Cloud Restaurant',
          branchName: 'Main',
          address: 'Test Street',
          phone: '555000',
          legalId: 'test',
        })
        .expect(200);
      await http().post(path('enrollments')).set(auth()).expect(403);
    });
    it('authors canonical hierarchy with stable IDs, prices, revisions and variants', async () => {
      const mutations = [
        ['category', { id: ids.category, nameKa: 'სასმელი', nameEn: 'Drinks' }],
        [
          'subcategory',
          {
            id: ids.subcategory,
            categoryId: ids.category,
            nameKa: 'ჩაი',
            nameEn: 'Tea',
          },
        ],
        [
          'item',
          {
            id: ids.item,
            subcategoryId: ids.subcategory,
            nameKa: 'ჩაი',
            nameEn: 'Tea',
            price: 12.5,
            enabled: true,
          },
        ],
        [
          'variant',
          { id: ids.variant, menuItemId: ids.item, size: 0.5, price: 8.5 },
        ],
      ] as const;
      for (const [sequence, [kind, { id, ...patch }]] of mutations.entries()) {
        const saved = await http()
          .post(path('catalog/mutations'))
          .set(auth())
          .send({
            mutationId: randomUUID(),
            entityType: kind.toUpperCase(),
            operation: 'UPSERT',
            entityId: id,
            expectedRevision: 0,
            patch: kind === 'variant' ? patch : { ...patch, sortOrder: 0 },
          })
          .expect(200);
        expect(saved.body).toMatchObject({
          revision: 1,
          sequence: sequence + 1,
        });
      }
      const tree = await http().get(path('catalog')).set(auth()).expect(200);
      expect(tree.body.categories[0].subcategories[0].items[0]).toMatchObject({
        id: ids.item,
        price: 12.5,
        revision: 1,
        variants: [{ id: ids.variant, price: 8.5, revision: 1 }],
      });
      // A stale entity revision is an explicit conflict, never an overwrite.
      await http()
        .post(path('catalog/mutations'))
        .set(auth())
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: ids.category,
          expectedRevision: 0,
          patch: { nameKa: 'stale', nameEn: 'stale' },
        })
        .expect(409);
    });
    it('uploads media, adds presentation, previews and publishes with no POS', async () => {
      const bytes = await sharp({
        create: { width: 4, height: 4, channels: 3, background: '#885522' },
      })
        .png()
        .toBuffer();
      const upload = await http()
        .post(path('website/logo'))
        .set(auth())
        .attach('file', bytes, 'logo.png')
        .expect(201);
      await http().get(upload.body.url).expect(200);
      await http()
        .put(path('website/menu'))
        .set(auth())
        .send({
          items: [
            {
              menuItemId: ids.item,
              visibleOnWebsite: true,
              displayName: 'Mountain Tea',
              description: 'Fresh tea',
              imageUrl: upload.body.url,
              sortOrder: 0,
            },
          ],
        })
        .expect(200);
      const settings = await http()
        .get(path('website'))
        .set(auth())
        .expect(200);
      const saved = await http()
        .put(path('website/draft'))
        .set(auth())
        .send({
          expectedRevision: settings.body.revision,
          content: {
            ...settings.body.draft,
            slug: `foundation-${tag}`,
            heroTitle: 'Cloud Restaurant',
            logoUrl: upload.body.url,
            showMenu: true,
          },
        })
        .expect(200);
      await http().get(path('website/preview')).set(auth()).expect(200);
      await http()
        .post(path('website/publish'))
        .set(auth())
        .send({ expectedRevision: saved.body.revision })
        .expect(201);
      const publicMenu = await http()
        .get('/api/website/menu')
        .set('Host', `foundation-${tag}.vynic.localhost`)
        .expect(200);
      expect(JSON.stringify(publicMenu.body)).toContain('Mountain Tea');
      expect(JSON.stringify(publicMenu.body)).toContain(ids.item);
      expect(await db.device.count({ where: { venueId: owners[0].id } })).toBe(
        0,
      );
      await http()
        .get('/api/website/menu?venueId=' + owners[0].id)
        .set('Host', 'unknown.vynic.localhost')
        .expect(404);
    });
    it('enforces owner isolation, parent ownership and both authority fences', async () => {
      await http().get(path('catalog')).set(auth(1)).expect(404);
      // Another Venue's parent does not exist for this owner.
      const foreignParent = await http()
        .post(path('catalog/mutations', 1))
        .set(auth(1))
        .send({
          mutationId: randomUUID(),
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: {
            subcategoryId: ids.subcategory,
            nameKa: 'x',
            nameEn: 'x',
            price: 1,
          },
        })
        .expect(409);
      expect(foreignParent.body.code).toBe('PARENT_MISSING');
      // A legacy full snapshot never writes a canonical catalog.
      await expect(
        new MenuSyncService(db).sync({ venueId: owners[0].id } as any, [], 1),
      ).resolves.toBe(false);
      await db.venue.update({
        where: { id: owners[1].id },
        data: { menuAuthority: 'POS' },
      });
      await http()
        .post(path('catalog/mutations', 1))
        .set(auth(1))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'x', nameEn: 'x' },
        })
        .expect(409);
      await new MenuSyncService(db).sync(
        { venueId: owners[1].id } as any,
        [],
        1,
      );
    });
    it('a second published Host cannot expose the first Venue catalog', async () => {
      const settings = await http()
        .get(path('website', 1))
        .set(auth(1))
        .expect(200);
      const saved = await http()
        .put(path('website/draft', 1))
        .set(auth(1))
        .send({
          expectedRevision: settings.body.revision,
          content: {
            ...settings.body.draft,
            slug: `foundation-b-${tag}`,
            heroTitle: 'Second restaurant',
            showMenu: true,
          },
        })
        .expect(200);
      await http()
        .post(path('website/publish', 1))
        .set(auth(1))
        .send({ expectedRevision: saved.body.revision })
        .expect(201);
      const result = await http()
        .get('/api/website/menu?venueId=' + owners[0].id)
        .set('Host', `foundation-b-${tag}.vynic.localhost`)
        .expect(200);
      expect(JSON.stringify(result.body)).not.toContain(ids.item);
    });
    it('disabled products disappear publicly without changing presentation', async () => {
      const toggle = (enabled: boolean, expectedRevision: number) =>
        http()
          .post(path('catalog/mutations'))
          .set(auth())
          .send({
            mutationId: randomUUID(),
            entityType: 'ITEM',
            operation: 'UPSERT',
            entityId: ids.item,
            expectedRevision,
            patch: { enabled },
          })
          .expect(200);
      const disabled = await toggle(false, 1);
      expect(disabled.body.revision).toBe(2);
      const hidden = await http()
        .get('/api/website/menu')
        .set('Host', `foundation-${tag}.vynic.localhost`)
        .expect(200);
      expect(JSON.stringify(hidden.body)).not.toContain(ids.item);
      await toggle(true, 2);
    });
    it('enables POS on the SAME Venue, enrolls and freezes a server-owned bootstrap', async () => {
      const pos = await db.feature.findUniqueOrThrow({ where: { key: 'POS' } });
      await db.venueFeatureOverride.create({
        data: {
          venueId: owners[0].id,
          featureId: pos.id,
          effect: 'ENABLED',
          note: 'Disposable adoption proof',
        },
      });
      const issued = await http()
        .post(path('enrollments'))
        .set(auth())
        .expect(201);
      const enrolled = await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: issued.body.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        })
        .expect(201);
      const first = await http()
        .post('/edge/restaurant-foundation/bootstrap')
        .set('X-POS-Sync-Key', enrolled.body.credential)
        .send({ venueId: owners[1].id })
        .expect(201);
      expect(first.body).toMatchObject({
        version: 1,
        venueId: owners[0].id,
        authority: 'CLOUD',
        operationalActivationAllowed: false,
      });
      expect(
        first.body.categories[0].subcategories[0].items[0].variants[0],
      ).toMatchObject({ id: ids.variant, price: 8.5 });
      const retry = await http()
        .post('/edge/restaurant-foundation/bootstrap')
        .set('X-POS-Sync-Key', enrolled.body.credential)
        .expect(201);
      expect(retry.body).toEqual(first.body);
      writeFileSync(
        '/private/tmp/vynic-foundation-bootstrap.json',
        JSON.stringify(first.body),
      );
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: owners[0].id } }))
          .menuAuthority,
      ).toBe('CLOUD');
    });
  },
);
