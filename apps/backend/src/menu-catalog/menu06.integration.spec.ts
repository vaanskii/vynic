import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import {
  menu06App,
  seedMenu06,
  menu06Product,
  menu06Intent,
  menu06Http,
} from '../../test/menu06.fixture';
import { RecipeService } from '../inventory/recipe.service';
import { MenuService } from '../website/menu/menu.service';
import { MobileMenuService } from '../mobile/services/mobile-menu.service';
import { WebsiteMenuService } from '../website/core/website-menu.service';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';
const url = process.env.MENU06_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'MENU06 real PostgreSQL and guarded HTTP',
  () => {
    let live: Awaited<ReturnType<typeof menu06App>>,
      venues: Awaited<ReturnType<typeof seedMenu06>>['venues'];
    const evidence: unknown[] = [];
    const mutate = (
      v: (typeof venues)[number],
      kind: string,
      id: string,
      revision: number,
      patch?: object,
      owner = false,
    ) =>
      menu06Http(
        live.base,
        v,
        owner
          ? `/customer/venues/${v.venueId}/catalog/mutations`
          : '/edge/menu/mutations',
        {
          mutationId: randomUUID(),
          entityType: kind,
          entityId: id,
          operation: patch ? 'UPSERT' : 'DELETE',
          expectedRevision: revision,
          ...(patch ? { patch } : {}),
        },
        'POST',
        owner,
      );
    const quantities = async (stockItemId: string) =>
      (
        await live.db.stockMovement.findMany({
          where: { stockItemId },
          orderBy: { createdAt: 'asc' },
        })
      ).map((m) => Number(m.quantityDeltaBase).toFixed(6));
    beforeAll(async () => {
      live = await menu06App(url!);
      ({ venues } = await seedMenu06(live.db, live.app));
    }, 60000);
    afterAll(async () => {
      if (process.env.MENU06_HTTP_PROOF)
        writeFileSync(
          process.env.MENU06_HTTP_PROOF,
          JSON.stringify(
            {
              transport:
                'real Nest HTTP / Device, customer, Host guards / Prisma / PostgreSQL',
              backendPid: process.pid,
              cases: evidence,
            },
            null,
            2,
          ) + '\n',
        );
      await live?.app.close();
      await live?.db.$disconnect();
    });
    for (const kind of ['ITEM', 'VARIANT'])
      it(`${kind}: preserve history, delayed consumption, concurrent retries, reverse, restore and exact original retry`, async () => {
        const p = await menu06Product(
            live.db,
            live.app,
            venues[0],
            kind === 'VARIANT',
          ),
          intent = menu06Intent(p),
          frozen = JSON.stringify(intent),
          id = kind === 'ITEM' ? p.itemId : p.variantId!;
        const recipe = await live.db.menuConsumptionRecipe.findUniqueOrThrow({
            where: { id: p.recipe.recipeId },
            include: { components: true },
          }),
          presentation =
            await live.db.menuItemWebsitePresentation.findUniqueOrThrow({
              where: { menuItemId: p.itemId },
            });
        const mutation = {
            mutationId: randomUUID(),
            entityType: kind,
            entityId: id,
            operation: 'DELETE',
            expectedRevision: 1,
          },
          removed = await menu06Http(
            live.base,
            venues[0],
            '/edge/menu/mutations',
            mutation,
          );
        expect(removed.status).toBe(200);
        expect(removed.body.deleted).toBe(true);
        const row =
          kind === 'ITEM'
            ? await live.db.menuItem.findUniqueOrThrow({ where: { id } })
            : await live.db.menuItemVariant.findUniqueOrThrow({
                where: { id },
              });
        expect(row.retiredAt).not.toBeNull();
        expect(row.revision).toBe(2);
        expect(
          await live.db.menuConsumptionRecipe.findUnique({
            where: { id: p.recipe.recipeId },
            include: { components: true },
          }),
        ).toEqual(recipe);
        expect(
          await live.db.menuItemWebsitePresentation.findUnique({
            where: { menuItemId: p.itemId },
          }),
        ).toEqual(presentation);
        const attempts = await Promise.all(
          Array.from({ length: 4 }, () =>
            menu06Http(
              live.base,
              venues[0],
              '/edge/inventory/consumption',
              intent,
            ),
          ),
        );
        expect(attempts.every((r) => r.status === 201)).toBe(true);
        expect(await quantities(p.stockId)).toEqual(['10.000000', '-2.000000']);
        const reversed = {
          ...intent,
          reversedAt: '2026-10-01T11:00:00.000Z',
          restoreBusinessDate: '2026-10-01',
        };
        for (let i = 0; i < 2; i++)
          expect(
            (
              await menu06Http(
                live.base,
                venues[0],
                '/edge/inventory/consumption',
                reversed,
              )
            ).status,
          ).toBe(201);
        expect(await quantities(p.stockId)).toEqual([
          '10.000000',
          '-2.000000',
          '2.000000',
        ]);
        expect(JSON.stringify(intent)).toBe(frozen);
        expect(
          (await mutate(venues[0], kind, id, 2, { price: 12 })).status,
        ).toBe(409);
        const restored = await mutate(
          venues[0],
          kind,
          id,
          2,
          { restore: true },
          true,
        );
        expect(restored.status).toBe(200);
        expect(restored.body.revision).toBe(3);
        expect(restored.body.entityId).toBe(id);
        expect(
          await live.db.menuCatalogTombstone.count({ where: { entityId: id } }),
        ).toBe(0);
        expect((await mutate(venues[0], kind, id, 3)).status).toBe(200);
        expect(
          await menu06Http(
            live.base,
            venues[0],
            '/edge/menu/mutations',
            mutation,
          ),
        ).toEqual({
          status: removed.status,
          body: { ...removed.body, duplicate: true },
        });
        const reused = await menu06Http(
          live.base,
          venues[0],
          '/edge/menu/mutations',
          { ...mutation, expectedRevision: 4 },
        );
        expect(reused.status).toBe(409);
        expect(reused.body.code).toBe('MUTATION_ID_REUSED');
        evidence.push({
          kind,
          id,
          recipeId: p.recipe.recipeId,
          removed,
          restored: restored.body,
          exactReplay: true,
          intentUnchanged: true,
          recipeUnchanged: true,
          presentationUnchanged: true,
          concurrentRetries: 4,
          quantities: await quantities(p.stockId),
        });
      });
    it('apply, retry, retire, reverse, retry conserves stock', async () => {
      const p = await menu06Product(live.db, live.app, venues[0]),
        i = menu06Intent(p);
      for (let n = 0; n < 2; n++)
        expect(
          (
            await menu06Http(
              live.base,
              venues[0],
              '/edge/inventory/consumption',
              i,
            )
          ).status,
        ).toBe(201);
      expect((await mutate(venues[0], 'ITEM', p.itemId, 1)).status).toBe(200);
      for (let n = 0; n < 2; n++)
        expect(
          (
            await menu06Http(
              live.base,
              venues[0],
              '/edge/inventory/consumption',
              { ...i, reversedAt: '2026-10-01T12:00:00.000Z' },
            )
          ).status,
        ).toBe(201);
      expect(await quantities(p.stockId)).toEqual([
        '10.000000',
        '-2.000000',
        '2.000000',
      ]);
      evidence.push({
        case: 'apply-retry-retire-reverse-retry',
        quantities: await quantities(p.stockId),
      });
    });
    it('nested parents reject active children; parent-first restore keeps all identities', async () => {
      const p = await menu06Product(live.db, live.app, venues[0], true);
      for (const [k, id] of [
        ['CATEGORY', p.categoryId],
        ['SUBCATEGORY', p.subcategoryId],
      ]) {
        const r = await mutate(venues[0], k, id, 1);
        expect(r.status).toBe(409);
        expect(r.body.code).toBe('NOT_EMPTY');
      }
      for (const [k, id] of [
        ['ITEM', p.itemId],
        ['SUBCATEGORY', p.subcategoryId],
        ['CATEGORY', p.categoryId],
      ])
        expect((await mutate(venues[0], k, id, 1)).status).toBe(200);
      expect(
        (
          await live.db.menuItemVariant.findUniqueOrThrow({
            where: { id: p.variantId! },
          })
        ).retiredAt,
      ).not.toBeNull();
      expect(
        (await mutate(venues[0], 'ITEM', p.itemId, 2, { restore: true }))
          .status,
      ).toBe(409);
      for (const [k, id] of [
        ['CATEGORY', p.categoryId],
        ['SUBCATEGORY', p.subcategoryId],
        ['ITEM', p.itemId],
        ['VARIANT', p.variantId!],
      ])
        expect(
          (await mutate(venues[0], k, id, 2, { restore: true })).status,
        ).toBe(200);
      expect(
        await live.db.menuConsumptionRecipe.count({
          where: { id: p.recipe.recipeId },
        }),
      ).toBe(1);
      evidence.push({
        case: 'parent-rejection-and-nested-restoration',
        itemId: p.itemId,
      });
    });
    for (const index of [0, 1])
      it(`${index === 0 ? 'SAAS' : 'CUSTOM'} active Device/owner/Manager/public reads and presentation restoration`, async () => {
        const v = venues[index],
          p = await menu06Product(live.db, live.app, v, true);
        expect(
          JSON.stringify(
            await live.app.get(WebsiteMenuService).publicMenu(v.venueId),
          ),
        ).toContain(p.itemId);
        const publicGet = async (path: string) => {
          const r = await request(live.base).get(path).set('Host', v.host);
          return { status: r.status, body: r.body as unknown };
        };
        expect(
          JSON.stringify((await publicGet('/api/website/venue/menu')).body),
        ).toContain('Preserved public name');
        expect((await mutate(v, 'ITEM', p.itemId, 1)).status).toBe(200);
        const reads = [
          await menu06Http(live.base, v, '/edge/menu/catalog'),
          await menu06Http(
            live.base,
            v,
            `/customer/venues/${v.venueId}/catalog`,
            undefined,
            'GET',
            true,
          ),
          await publicGet('/api/menu'),
          await publicGet('/api/website/venue/menu'),
        ];
        for (const r of reads) {
          expect(r.status).toBe(200);
          expect(JSON.stringify(r.body)).not.toContain(p.itemId);
          expect(JSON.stringify(r.body)).not.toContain(p.variantId);
        }
        expect(
          JSON.stringify(
            await new MobileMenuService(
              live.db,
              undefined!,
              undefined!,
            ).getMenu(p.tenant),
          ),
        ).not.toContain(p.itemId);
        const recipes = live.app.get(RecipeService);
        expect(
          JSON.stringify(await recipes.listMenuItems(p.tenant)),
        ).not.toContain(p.itemId);
        expect(
          (await recipes.projection(v.venueId)).map((r) => r.recipeId),
        ).not.toContain(p.recipe.recipeId);
        await expect(
          live.app
            .get(MenuService)
            .getBookableSelection(p.tenant, p.itemId, p.variantId!),
        ).rejects.toThrow();
        const history = await menu06Http(
          live.base,
          v,
          `/customer/venues/${v.venueId}/catalog/retired`,
          undefined,
          'GET',
          true,
        );
        expect(history.status).toBe(200);
        expect(JSON.stringify(history.body)).toContain(p.itemId);
        for (const [k, id] of [
          ['ITEM', p.itemId],
          ['VARIANT', p.variantId!],
        ])
          expect((await mutate(v, k, id, 2, { restore: true })).status).toBe(
            200,
          );
        expect(
          JSON.stringify((await publicGet('/api/website/venue/menu')).body),
        ).toContain('Preserved public name');
        evidence.push({
          case: 'active-surfaces',
          mode: index === 0 ? 'SAAS' : 'CUSTOM',
          statuses: reads.map((r) => r.status),
          managerExcluded: true,
          presentationRestored: true,
        });
      });
    it('retired variant rejects parent, selected variant and legacy variant selection', async () => {
      const p = await menu06Product(live.db, live.app, venues[0], true);
      expect((await mutate(venues[0], 'VARIANT', p.variantId!, 1)).status).toBe(
        200,
      );
      for (const [id, variant] of [
        [p.itemId, p.variantId!],
        [p.variantId!, undefined],
        [p.itemId, undefined],
      ])
        await expect(
          live.app
            .get(MenuService)
            .getBookableSelection(p.tenant, id!, variant),
        ).rejects.toThrow();
      evidence.push({ case: 'retired-variant-selection', allRejected: true });
    });
    it('Restrict blocks physical child and parent purge when history/config depends on them', async () => {
      const p = await menu06Product(live.db, live.app, venues[0], true);
      for (const action of [
        () => live.db.menuItem.delete({ where: { id: p.itemId } }),
        () => live.db.menuItemVariant.delete({ where: { id: p.variantId! } }),
        () => live.db.menuCategory.delete({ where: { id: p.categoryId } }),
      ])
        await expect(action()).rejects.toMatchObject({ code: 'P2003' });
      expect(
        await live.db.menuConsumptionRecipe.count({
          where: { id: p.recipe.recipeId },
        }),
      ).toBe(1);
      evidence.push({
        case: 'destructive-FK-rejection',
        item: true,
        variant: true,
        parent: true,
      });
    });
    it('two Venue owner/Device/item/variant/recipe/stock/Sale negatives fail closed', async () => {
      const a = await menu06Product(live.db, live.app, venues[0], true),
        b = await menu06Product(live.db, live.app, venues[1], true);
      await live.db.menuItem.updateMany({
        where: { id: { in: [a.itemId, b.itemId] } },
        data: { posMenuItemId: 'same-external-menu06' },
      });
      await live.db.menuItemVariant.updateMany({
        where: { id: { in: [a.variantId!, b.variantId!] } },
        data: { posMenuVariantId: 'same-external-variant-menu06' },
      });
      expect(
        (
          await menu06Http(
            live.base,
            venues[1],
            `/customer/venues/${venues[0].venueId}/catalog/mutations`,
            {
              mutationId: randomUUID(),
              entityType: 'ITEM',
              entityId: a.itemId,
              operation: 'DELETE',
              expectedRevision: 1,
            },
            'POST',
            true,
          )
        ).status,
      ).toBe(404);
      expect(
        (await mutate(venues[1], 'ITEM', a.itemId, 1, { price: 99 })).status,
      ).toBe(409);
      expect(
        (await live.db.menuItem.findUniqueOrThrow({ where: { id: a.itemId } }))
          .price,
      ).toBe(10);
      expect((await fetch(live.base + '/edge/menu/retired')).status).toBe(401);
      const ia = menu06Intent(a);
      ia.snapshot.lines[0].menuItemId = 'same-external-menu06';
      ia.snapshot.lines[0].variantId = 'same-external-variant-menu06';
      expect(
        (
          await menu06Http(
            live.base,
            venues[0],
            '/edge/inventory/consumption',
            ia,
          )
        ).status,
      ).toBe(201);
      expect(
        (
          await menu06Http(
            live.base,
            venues[1],
            '/edge/inventory/consumption',
            ia,
          )
        ).status,
      ).toBe(400);
      const ib = { ...menu06Intent(b), posSaleId: ia.posSaleId };
      ib.snapshot.lines[0].menuItemId = 'same-external-menu06';
      ib.snapshot.lines[0].variantId = 'same-external-variant-menu06';
      for (const field of ['recipeId'] as const) {
        const bad = structuredClone(ib);
        bad.snapshot.lines[0][field] = ia.snapshot.lines[0][field];
        expect(
          (
            await menu06Http(
              live.base,
              venues[1],
              '/edge/inventory/consumption',
              bad,
            )
          ).status,
        ).toBe(400);
      }
      for (const [field, foreignId] of [
        ['menuItemId', a.itemId],
        ['variantId', a.variantId!],
      ] as const) {
        const bad = structuredClone(ib);
        bad.snapshot.lines[0][field] = foreignId;
        expect(
          (
            await menu06Http(
              live.base,
              venues[1],
              '/edge/inventory/consumption',
              bad,
            )
          ).status,
        ).toBe(400);
      }
      const badStock = structuredClone(ib);
      badStock.snapshot.lines[0].components[0].stockItemId = a.stockId;
      expect(
        (
          await menu06Http(
            live.base,
            venues[1],
            '/edge/inventory/consumption',
            badStock,
          )
        ).status,
      ).toBe(400);
      expect(
        (
          await menu06Http(
            live.base,
            venues[1],
            '/edge/inventory/consumption',
            ib,
          )
        ).status,
      ).toBe(201);
      expect(
        await live.db.saleConsumption.count({
          where: { posSaleId: ia.posSaleId },
        }),
      ).toBe(2);
      const changed = structuredClone(ia);
      changed.snapshot.lines[0].itemName = 'changed';
      expect(
        (
          await menu06Http(
            live.base,
            venues[0],
            '/edge/inventory/consumption',
            changed,
          )
        ).status,
      ).toBe(409);
      evidence.push({
        case: 'two-venue',
        foreignOwner: 404,
        foreignDeviceEntity: 409,
        missingDevice: 401,
        foreignItemVariantRecipeStock: 400,
        immutableSale: 409,
        sameExternalIdsSafe: true,
        sameSaleIdSeparateRows: 2,
      });
    });
    it('retirement and restoration preserve disabled availability independently', async () => {
      const p = await menu06Product(live.db, live.app, venues[0]);
      expect(
        (await mutate(venues[0], 'ITEM', p.itemId, 1, { enabled: false }))
          .status,
      ).toBe(200);
      const active = await menu06Http(
        live.base,
        venues[0],
        '/edge/menu/catalog',
      );
      expect(JSON.stringify(active.body)).toContain(p.itemId);
      expect((await mutate(venues[0], 'ITEM', p.itemId, 2)).status).toBe(200);
      const retired = await live.db.menuItem.findUniqueOrThrow({
        where: { id: p.itemId },
      });
      expect(retired.enabled).toBe(false);
      expect(retired.retiredAt).not.toBeNull();
      expect(
        (await mutate(venues[0], 'ITEM', p.itemId, 3, { restore: true }))
          .status,
      ).toBe(200);
      const restored = await live.db.menuItem.findUniqueOrThrow({
        where: { id: p.itemId },
      });
      expect(restored.enabled).toBe(false);
      expect(restored.retiredAt).toBeNull();
      evidence.push({
        case: 'availability-independent-of-retirement',
        stableId: p.itemId,
        enabledAfterRestore: false,
      });
    });
    it('restore missing hard-deleted identity rejects fabrication', async () => {
      const r = await mutate(venues[0], 'ITEM', randomUUID(), 2, {
        restore: true,
      });
      expect(r.status).toBe(409);
      expect(r.body.code).toBe('HISTORICAL_IDENTITY_UNAVAILABLE');
      evidence.push({ case: 'already-deleted-policy', result: r });
    });
    it('legacy snapshot omission retires and reappearance restores same IDs; CLOUD ignores it', async () => {
      const p = await menu06Product(live.db, live.app, venues[0], true);
      await live.db.venue.update({
        where: { id: venues[0].venueId },
        data: { menuAuthority: 'POS' },
      });
      await live.db.menuCategory.update({
        where: { id: p.categoryId },
        data: { posMenuCategoryId: p.categoryId, slug: 'legacy-menu06' },
      });
      await live.db.menuSubcategory.update({
        where: { id: p.subcategoryId },
        data: {
          posMenuSubcategoryId: p.subcategoryId,
          slug: 'legacy-sub-menu06',
        },
      });
      await live.db.menuItem.update({
        where: { id: p.itemId },
        data: { posMenuItemId: p.itemId },
      });
      await live.db.menuItemVariant.update({
        where: { id: p.variantId! },
        data: { posMenuVariantId: p.variantId },
      });
      const sync = new MenuSyncService(live.db);
      await sync.sync(p.tenant, [], 1);
      expect(
        (await live.db.menuItem.findUniqueOrThrow({ where: { id: p.itemId } }))
          .retiredAt,
      ).not.toBeNull();
      expect(
        await live.db.menuConsumptionRecipe.count({
          where: { id: p.recipe.recipeId },
        }),
      ).toBe(1);
      await sync.sync(
        p.tenant,
        [
          {
            id: p.categoryId,
            slug: 'legacy-menu06',
            nameKa: 'Synthetic',
            nameEn: 'Synthetic',
            subcategories: [
              {
                id: p.subcategoryId,
                slug: 'legacy-sub-menu06',
                nameKa: 'Synthetic',
                nameEn: 'Synthetic',
                items: [
                  {
                    id: p.itemId,
                    nameKa: 'Synthetic flour dish',
                    nameEn: 'Synthetic flour dish',
                    price: 10,
                    variants: [{ id: p.variantId!, size: 1, price: 10 }],
                  },
                ],
              },
            ],
          },
        ],
        1,
      );
      expect(
        (await live.db.menuItem.findUniqueOrThrow({ where: { id: p.itemId } }))
          .retiredAt,
      ).toBeNull();
      expect(
        (
          await live.db.menuItemVariant.findUniqueOrThrow({
            where: { id: p.variantId! },
          })
        ).retiredAt,
      ).toBeNull();
      await live.db.venue.update({
        where: { id: venues[0].venueId },
        data: { menuAuthority: 'CLOUD' },
      });
      await sync.sync(p.tenant, [], 1);
      expect(
        (await live.db.menuItem.findUniqueOrThrow({ where: { id: p.itemId } }))
          .retiredAt,
      ).toBeNull();
      evidence.push({
        case: 'legacy-writer',
        retirement: true,
        sameIdRestore: true,
        cloudIgnoresSnapshot: true,
      });
    });
  },
);
