import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import request from 'supertest';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { PrismaService } from '../prisma.service';
import { OwnerInvitationsService } from '../customer/owner-invitations.service';
import { PlatformVenueConfigService } from '../platform/platform-venue-config.service';
import { PlatformDirectoryService } from '../platform/platform-directory.service';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';
import { MenuService } from '../website/menu/menu.service';
import { MobileMenuService } from '../mobile/services/mobile-menu.service';
import { MenuCatalogService } from './menu-catalog.service';

/**
 * Canonical Cloud Menu protocol over real HTTP and PostgreSQL
 * (docs/CANONICAL_MENU_SYNC.md). Several enrolled Devices of one Venue act as
 * independent POS terminals; none is primary for the Menu.
 */
const url = process.env.CANONICAL_MENU_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Canonical Menu protocol (disposable PostgreSQL)',
  () => {
    let db: PrismaService, app: any;
    const tag = randomUUID().slice(0, 8);
    const owners: { token: string; id: string }[] = [];
    const devices: string[] = [];
    const id = {
      category: randomUUID(),
      subcategory: randomUUID(),
      khinkali: randomUUID(),
      khachapuri: randomUUID(),
      wine: randomUUID(),
      glass: randomUUID(),
    };
    const http = () => request(app.getHttpServer());
    const owner = (i = 0) => ({ Authorization: `Bearer ${owners[i].token}` });
    const venuePath = (suffix: string, i = 0) =>
      `/customer/venues/${owners[i].id}/${suffix}`;
    const dashboard = (body: object, i = 0) =>
      http()
        .post(venuePath('catalog/mutations', i))
        .set(owner(i))
        .send({ mutationId: randomUUID(), ...body });
    const pos = (device: number, body: object) =>
      http()
        .post('/edge/menu/mutations')
        .set('X-POS-Sync-Key', devices[device])
        .send({ mutationId: randomUUID(), ...body });
    const catalog = (device: number) =>
      http().get('/edge/menu/catalog').set('X-POS-Sync-Key', devices[device]);
    const node = async (
      kind: 'items' | 'variants' | 'categories',
      entityId: string,
    ) =>
      ((await catalog(0).expect(200)).body[kind] as any[]).find(
        (n) => n.id === entityId,
      );
    const enroll = async (i = 0) => {
      const issued = await http()
        .post(venuePath('enrollments', i))
        .set(owner(i))
        .expect(201);
      const enrolled = await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: issued.body.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        })
        .expect(201);
      return enrolled.body.credential as string;
    };

    beforeAll(async () => {
      if (!isFreshDisposableDatabase(url!))
        throw Error('Fresh disposable DB only');
      process.env.JWT_SECRET = 'canonical-menu-test-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'canonical-menu-test-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      const feature = (key: string) =>
        db.feature.upsert({
          where: { key },
          create: { key, name: key },
          update: {},
        });
      const website = await feature('WEBSITE');
      await feature('POS');
      const plan = await db.plan.upsert({
        where: { key: `website-only-${tag}` },
        create: {
          key: `website-only-${tag}`,
          name: 'Website',
          features: { create: { featureId: website.id } },
        },
        update: {},
      });
      app = await onboardingApp(db);
      const admin = await db.platformUser.create({
        data: {
          email: `menu-admin-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: 'unused',
        },
      });
      const actor = { platformUserId: admin.id, role: 'SUPER_ADMIN' } as any;
      for (const label of ['a', 'b']) {
        const prepared = await app
          .get(OwnerInvitationsService)
          .provision(actor, {
            organizationName: `Menu ${label} ${tag}`,
            name: `Menu ${label}`,
            email: `${label}-${tag}@menu.test.invalid`,
            planId: plan.id,
            subscriptionStatus: 'ACTIVE',
            // Venue A renders through SAAS, Venue B through CUSTOM: same catalog rules.
            websiteMode: label === 'a' ? 'SAAS' : 'CUSTOM',
          });
        const accepted = await http()
          .post('/customer/invitations/register')
          .send({
            token: prepared.invitationPath.split('=')[1],
            displayName: `Owner ${label}`,
            password: 'Canonical menu test password!',
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

    it('new Venues start on the canonical model (Website-only, no POS)', async () => {
      const venue = await db.venue.findUniqueOrThrow({
        where: { id: owners[0].id },
      });
      expect(venue.menuAuthority).toBe('CLOUD');
      expect(await db.device.count({ where: { venueId: owners[0].id } })).toBe(
        0,
      );
    });

    it('1. Dashboard creates the full Menu with entity revisions', async () => {
      const created = [
        {
          entityType: 'CATEGORY',
          entityId: id.category,
          patch: { nameKa: 'სამზარეულო', nameEn: 'Kitchen', sortOrder: 0 },
        },
        {
          entityType: 'SUBCATEGORY',
          entityId: id.subcategory,
          patch: {
            categoryId: id.category,
            nameKa: 'ცხელი',
            nameEn: 'Hot',
            sortOrder: 0,
          },
        },
        {
          entityType: 'ITEM',
          entityId: id.khinkali,
          patch: {
            subcategoryId: id.subcategory,
            nameKa: 'ხინკალი',
            nameEn: 'Khinkali',
            price: 2,
            sortOrder: 0,
          },
        },
        {
          entityType: 'ITEM',
          entityId: id.khachapuri,
          patch: {
            subcategoryId: id.subcategory,
            nameKa: 'ხაჭაპური',
            nameEn: 'Khachapuri',
            price: 18,
            sortOrder: 1,
          },
        },
        {
          entityType: 'ITEM',
          entityId: id.wine,
          patch: {
            categoryId: id.category,
            nameKa: 'ღვინო',
            nameEn: 'Wine',
            price: 0,
            sortOrder: 2,
          },
        },
        {
          entityType: 'VARIANT',
          entityId: id.glass,
          patch: { menuItemId: id.wine, size: 0.15, price: 9 },
        },
      ];
      for (const [index, m] of created.entries()) {
        const res = await dashboard({
          ...m,
          operation: 'UPSERT',
          expectedRevision: 0,
        }).expect(200);
        expect(res.body).toMatchObject({
          status: 'ACCEPTED',
          revision: 1,
          sequence: index + 1,
          duplicate: false,
        });
      }
      const tree = await http()
        .get(venuePath('catalog'))
        .set(owner())
        .expect(200);
      expect(tree.body).toMatchObject({ authority: 'CLOUD', sequence: 6 });
      expect(
        tree.body.categories[0].subcategories[0].items.map((i: any) => i.id),
      ).toEqual([id.khinkali, id.khachapuri]);
      expect(
        await db.customerAuditEvent.count({ where: { targetId: id.khinkali } }),
      ).toBe(1);
    });

    it('2/3/16. fresh POS terminals import exact ids and revisions; bootstraps create no rows', async () => {
      const pos = await db.feature.findUniqueOrThrow({ where: { key: 'POS' } });
      await db.venueFeatureOverride.create({
        data: {
          venueId: owners[0].id,
          featureId: pos.id,
          effect: 'ENABLED',
          note: 'adoption proof',
        },
      });
      for (let i = 0; i < 3; i++) devices.push(await enroll());
      const before = await db.menuItem.count({
        where: { venueId: owners[0].id },
      });
      const snapshots = await Promise.all(
        devices.map((_, i) => catalog(i).expect(200)),
      );
      for (const s of snapshots) {
        expect(s.body).toMatchObject({
          version: 2,
          venueId: owners[0].id,
          authority: 'CLOUD',
          sequence: 6,
        });
        expect(s.body.items.map((i: any) => [i.id, i.revision])).toEqual([
          [id.khinkali, 1],
          [id.khachapuri, 1],
          [id.wine, 1],
        ]);
        expect(s.body.variants).toEqual([
          expect.objectContaining({
            id: id.glass,
            menuItemId: id.wine,
            size: 0.15,
            price: 9,
            revision: 1,
          }),
        ]);
      }
      expect(snapshots[1].body).toEqual(snapshots[0].body);
      expect(
        await db.menuItem.count({ where: { venueId: owners[0].id } }),
      ).toBe(before);
      writeFileSync(
        process.env.CANONICAL_MENU_FIXTURE ??
          '/private/tmp/vynic-canonical-menu-snapshot.json',
        JSON.stringify(snapshots[0].body),
      );
    });

    it('12/25. two terminals edit different items concurrently; neither is primary', async () => {
      const primary = await db.venue.findUniqueOrThrow({
        where: { id: owners[0].id },
      });
      const [a, b] = await Promise.all([
        pos(0, {
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: id.khinkali,
          expectedRevision: 1,
          patch: { price: 2.2 },
        }),
        pos(1, {
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: id.khachapuri,
          expectedRevision: 1,
          patch: { price: 19.5 },
        }),
      ]);
      expect(a.status).toBe(200);
      expect(b.status).toBe(200);
      expect(a.body.revision).toBe(2);
      expect(b.body.revision).toBe(2);
      // Device 1 is not the operational primary (or no primary exists at all).
      const secondary = (
        await db.device.findMany({
          where: { venueId: owners[0].id },
          orderBy: { createdAt: 'asc' },
        })
      )[1].id;
      expect(primary.activeOperationalDeviceId).not.toBe(secondary);
      expect(
        await db.menuCatalogMutation.findFirst({
          where: { mutationId: b.body.mutationId },
        }),
      ).toMatchObject({
        actorType: 'DEVICE',
        actorId: secondary,
        source: 'POS',
        changes: { price: { from: 18, to: 19.5 } },
      });
    });

    it('13. same item, same base revision: one accepted, the other an explicit conflict', async () => {
      const [a, b] = await Promise.all([
        pos(0, {
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: id.khinkali,
          expectedRevision: 2,
          patch: { price: 2.4 },
        }),
        pos(1, {
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: id.khinkali,
          expectedRevision: 2,
          patch: { price: 2.3 },
        }),
      ]);
      const statuses = [a.status, b.status].sort();
      expect(statuses).toEqual([200, 409]);
      const loser = a.status === 409 ? a : b;
      const winner = a.status === 200 ? a : b;
      expect(loser.body).toMatchObject({
        code: 'REVISION_CONFLICT',
        message: 'This item was changed on another device.',
        conflict: {
          entityType: 'ITEM',
          entityId: id.khinkali,
          expectedRevision: 2,
          currentRevision: 3,
          deleted: false,
          current: { id: id.khinkali, price: winner === a ? 2.4 : 2.3 },
          pending: { price: winner === a ? 2.3 : 2.4 },
        },
      });
      // No silent overwrite: Cloud still holds the winner.
      expect((await node('items', id.khinkali)).price).toBe(
        winner === a ? 2.4 : 2.3,
      );
      // Re-apply against the current revision is an explicit, audited resolution.
      const reapplied = await pos(a.status === 409 ? 0 : 1, {
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.khinkali,
        expectedRevision: 3,
        patch: loser.body.conflict.pending,
        resolution: 'REAPPLY',
      }).expect(200);
      expect(reapplied.body.revision).toBe(4);
      expect(
        await db.menuCatalogMutation.findFirst({
          where: { mutationId: reapplied.body.mutationId },
        }),
      ).toMatchObject({ resolution: 'REAPPLY' });
    });

    it('14. a duplicate mutation id is applied and audited once', async () => {
      const body = {
        mutationId: randomUUID(),
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.khachapuri,
        expectedRevision: 2,
        patch: { nameEn: 'Imeruli khachapuri' },
      };
      const results = await Promise.all([1, 2, 3].map(() => pos(1, body)));
      expect(results.map((r) => r.status)).toEqual([200, 200, 200]);
      expect(results.filter((r) => r.body.duplicate === false)).toHaveLength(1);
      expect(new Set(results.map((r) => r.body.revision))).toEqual(
        new Set([3]),
      );
      expect(
        await db.menuCatalogMutation.count({
          where: { mutationId: body.mutationId },
        }),
      ).toBe(1);
      expect((await node('items', id.khachapuri)).revision).toBe(3);
      // The same id cannot carry a different change.
      await pos(1, { ...body, patch: { nameEn: 'Other' } }).expect(409);
    });

    it('10/11/19/20. Dashboard edit is canonical for POS, Manager, SAAS and CUSTOM readers', async () => {
      const before = (await node('items', id.khachapuri)).revision;
      await dashboard({
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.khachapuri,
        expectedRevision: before,
        patch: { price: 20 },
      }).expect(200);
      const since = await http()
        .get('/edge/menu/changes?since=6')
        .set('X-POS-Sync-Key', devices[2])
        .expect(200);
      expect(
        since.body.items.find((i: any) => i.id === id.khachapuri),
      ).toMatchObject({ price: 20 });
      expect(since.body.items.map((i: any) => i.id)).not.toContain(id.wine);
      const tenant = { venueId: owners[0].id, organizationId: '' } as any;
      const custom = await new MenuService(db as any).getAllCategories(tenant);
      const manager = await new MobileMenuService(
        db as any,
        undefined as any,
        undefined as any,
      ).getMenu(tenant);
      const website = JSON.stringify(custom);
      expect(website).toContain('"price":20');
      expect(JSON.stringify(manager)).toContain('Imeruli khachapuri');
    });

    it('17. a POS-only Venue (no WEBSITE) uses the same canonical protocol', async () => {
      const organization = await db.organization.create({
        data: { name: `POS only ${tag}` },
      });
      const venue = await app
        .get(PlatformDirectoryService)
        .createVenue({ platformUserId: 'system', role: 'SUPER_ADMIN' } as any, {
          organizationId: organization.id,
          name: 'POS only',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
        });
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: venue.id } }))
          .menuAuthority,
      ).toBe('CLOUD');
      const catalogs = app.get(MenuCatalogService) as MenuCatalogService;
      const device = {
        type: 'DEVICE' as const,
        id: randomUUID(),
        source: 'POS',
      };
      const cat = randomUUID();
      await catalogs.apply(venue.id, device, {
        mutationId: randomUUID(),
        entityType: 'CATEGORY',
        operation: 'UPSERT',
        entityId: cat,
        expectedRevision: 0,
        patch: { nameKa: 'სასმელი', nameEn: 'Drinks', slug: 'drinks' },
      });
      expect((await catalogs.snapshot(venue.id)).categories).toEqual([
        expect.objectContaining({ id: cat, slug: 'drinks', revision: 1 }),
      ]);
    });

    it('15. deletion is a tombstone a disconnected terminal catches up after reconnect', async () => {
      const offlineSince = (await catalog(2).expect(200)).body.sequence;
      const current = await node('items', id.wine);
      const deleted = await pos(0, {
        entityType: 'ITEM',
        operation: 'DELETE',
        entityId: id.wine,
        expectedRevision: current.revision,
      }).expect(200);
      expect(deleted.body).toMatchObject({ deleted: true, entity: null });
      // Idempotent: repeating the delete (or a delete from another terminal) is a no-op.
      await pos(1, {
        entityType: 'ITEM',
        operation: 'DELETE',
        entityId: id.wine,
        expectedRevision: current.revision,
      }).expect(200);
      const caught = await http()
        .get(`/edge/menu/changes?since=${offlineSince}`)
        .set('X-POS-Sync-Key', devices[2])
        .expect(200);
      expect(caught.body.tombstones).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ entityType: 'ITEM', entityId: id.wine }),
          expect.objectContaining({
            entityType: 'VARIANT',
            entityId: id.glass,
          }),
        ]),
      );
      expect(caught.body.items.map((i: any) => i.id)).not.toContain(id.wine);
      // An edit based on the deleted node is a conflict, never a resurrection.
      const stale = await pos(2, {
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.wine,
        expectedRevision: current.revision,
        patch: { price: 5 },
      }).expect(409);
      expect(stale.body.conflict).toMatchObject({
        deleted: true,
        current: null,
      });
      // A non-empty parent is never deleted implicitly.
      const nonEmpty = await dashboard({
        entityType: 'SUBCATEGORY',
        operation: 'DELETE',
        entityId: id.subcategory,
        expectedRevision: 1,
      }).expect(409);
      expect(nonEmpty.body.code).toBe('NOT_EMPTY');
      // A sequence ahead of the server asks for a fresh bootstrap.
      await http()
        .get('/edge/menu/changes?since=999999')
        .set('X-POS-Sync-Key', devices[2])
        .expect(409);
    });

    it('23. Venue A credentials/owners cannot read or mutate Venue B nodes', async () => {
      const other = randomUUID();
      await dashboard(
        {
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: other,
          expectedRevision: 0,
          patch: { nameKa: 'B', nameEn: 'B' },
        },
        1,
      ).expect(200);
      // Device of Venue A addressing Venue B's node: it simply does not exist for A.
      const cross = await pos(0, {
        entityType: 'CATEGORY',
        operation: 'UPSERT',
        entityId: other,
        expectedRevision: 1,
        patch: { nameEn: 'hijack' },
      });
      expect(cross.status).toBe(409);
      expect(JSON.stringify(cross.body)).not.toContain('"B"');
      // Creating with B's id is refused without revealing it.
      const reuse = await pos(0, {
        entityType: 'CATEGORY',
        operation: 'UPSERT',
        entityId: other,
        expectedRevision: 0,
        patch: { nameKa: 'x', nameEn: 'x' },
      }).expect(409);
      expect(reuse.body.code).toBe('ID_UNAVAILABLE');
      // Owner A cannot address Venue B at all.
      await http()
        .post(`/customer/venues/${owners[1].id}/catalog/mutations`)
        .set(owner(0))
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: other,
          expectedRevision: 1,
          patch: { nameEn: 'x' },
        })
        .expect(404);
      // The same mutation id in two Venues are two unrelated mutations.
      const shared = randomUUID();
      await dashboard(
        {
          mutationId: shared,
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'a', nameEn: 'a' },
        },
        0,
      ).expect(200);
      const second = await dashboard(
        {
          mutationId: shared,
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'b', nameEn: 'b' },
        },
        1,
      ).expect(200);
      expect(second.body.duplicate).toBe(false);
      expect(
        (
          await db.menuCategory.findFirstOrThrow({
            where: { posMenuCategoryId: other },
          })
        ).nameEn,
      ).toBe('B');
    });

    it('24. an established POS Venue stays in compatibility mode; nothing converts it', async () => {
      await db.venue.update({
        where: { id: owners[1].id },
        data: { menuAuthority: 'POS' },
      });
      const posFeature = await db.feature.findUniqueOrThrow({
        where: { key: 'POS' },
      });
      await db.venueFeatureOverride.create({
        data: {
          venueId: owners[1].id,
          featureId: posFeature.id,
          effect: 'ENABLED',
          note: 'legacy POS proof',
        },
      });
      const credential = await enroll(1);
      await http()
        .post('/edge/menu/mutations')
        .set('X-POS-Sync-Key', credential)
        .send({
          mutationId: randomUUID(),
          entityType: 'CATEGORY',
          operation: 'UPSERT',
          entityId: randomUUID(),
          expectedRevision: 0,
          patch: { nameKa: 'x', nameEn: 'x' },
        })
        .expect(409)
        .expect((res) => expect(res.body.code).toBe('LEGACY_POS_MENU'));
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: owners[1].id } }))
          .menuAuthority,
      ).toBe('POS');
      // A legacy full snapshot sent to a CLOUD Venue never writes its catalog.
      const sync = new MenuSyncService(db);
      const applied = await sync.sync(
        { venueId: owners[0].id, organizationId: '' } as any,
        [
          {
            id: randomUUID(),
            slug: 'ghost',
            nameKa: 'x',
            nameEn: 'x',
            items: [],
          } as any,
        ],
        1,
      );
      expect(applied).toBe(false);
      expect(
        (await catalog(0).expect(200)).body.categories.map((c: any) => c.slug),
      ).not.toContain('ghost');
    });

    it('owner editing permission gates the Dashboard, never the terminals', async () => {
      await db.venue.update({
        where: { id: owners[0].id },
        data: { cloudMenuEditingEnabled: false },
      });
      const khinkali = await node('items', id.khinkali);
      const denied = await dashboard({
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.khinkali,
        expectedRevision: khinkali.revision,
        patch: { enabled: false },
      }).expect(409);
      expect(denied.body.code).toBe('EDITING_DISABLED');
      await pos(2, {
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: id.khinkali,
        expectedRevision: khinkali.revision,
        patch: { sendToKitchen: false },
      }).expect(200);
      await db.venue.update({
        where: { id: owners[0].id },
        data: { cloudMenuEditingEnabled: true },
      });
    });

    it('ten terminals converge on one catalog with one accepted change per item', async () => {
      const credentials = [...devices];
      while (credentials.length < 10) credentials.push(await enroll());
      const items = Array.from({ length: 10 }, () => randomUUID());
      // Each terminal creates its own product concurrently: no conflicts.
      const created = await Promise.all(
        items.map((itemId, i) =>
          http()
            .post('/edge/menu/mutations')
            .set('X-POS-Sync-Key', credentials[i])
            .send({
              mutationId: randomUUID(),
              entityType: 'ITEM',
              operation: 'UPSERT',
              entityId: itemId,
              expectedRevision: 0,
              patch: {
                categoryId: id.category,
                nameKa: `პროდუქტი ${i}`,
                nameEn: `Product ${i}`,
                price: i + 1,
                sortOrder: 10 + i,
              },
            }),
        ),
      );
      expect(created.every((r) => r.status === 200)).toBe(true);
      // All ten edit the SAME product from the same base revision: exactly one wins.
      const race = await Promise.all(
        credentials.map((credential, i) =>
          http()
            .post('/edge/menu/mutations')
            .set('X-POS-Sync-Key', credential)
            .send({
              mutationId: randomUUID(),
              entityType: 'ITEM',
              operation: 'UPSERT',
              entityId: items[0],
              expectedRevision: 1,
              patch: { price: 50 + i },
            }),
        ),
      );
      expect(race.filter((r) => r.status === 200)).toHaveLength(1);
      expect(race.filter((r) => r.status === 409)).toHaveLength(9);
      const snapshots = await Promise.all(
        credentials.map((c) =>
          http().get('/edge/menu/catalog').set('X-POS-Sync-Key', c),
        ),
      );
      expect(new Set(snapshots.map((s) => JSON.stringify(s.body))).size).toBe(
        1,
      );
    });
  },
);
