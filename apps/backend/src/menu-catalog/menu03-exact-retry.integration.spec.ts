import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import type { MenuEntityKind } from '@prisma/client';
import type { MenuMutation } from './menu-mutation';
import { MenuCatalogService } from './menu-catalog.service';
import {
  menu03App,
  seedMenu03,
  menu03Request,
  menu03Outcome,
  type Menu03Fixture,
} from '../../test/menu03.fixture';

const url = process.env.MENU03_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'MENU03 real HTTP / PostgreSQL exact outcome',
  () => {
    let runtime: Awaited<ReturnType<typeof menu03App>>;
    let fixture: Menu03Fixture;
    const send = (
      body: unknown,
      writer: 'DEVICE' | 'OWNER' = 'DEVICE',
      i = 0,
    ) => menu03Request(runtime.base, fixture.venues[i], body, writer);
    const mutation = (
      entityType: MenuEntityKind,
      entityId: string,
      patch: MenuMutation['patch'],
      expectedRevision = 0,
    ): MenuMutation => ({
      mutationId: randomUUID(),
      entityType,
      entityId,
      operation: 'UPSERT',
      expectedRevision,
      patch,
      resolution: null,
    });
    async function create(kind: MenuEntityKind) {
      const categoryId = randomUUID(),
        menuItemId = randomUUID(),
        entityId = randomUUID();
      if (kind !== 'CATEGORY')
        expect(
          (
            await send(
              mutation('CATEGORY', categoryId, {
                nameKa: 'Parent',
                nameEn: 'Parent',
              }),
            )
          ).status,
        ).toBe(200);
      if (kind === 'VARIANT')
        expect(
          (
            await send(
              mutation('ITEM', menuItemId, {
                categoryId,
                nameKa: 'Parent item',
                nameEn: 'Parent item',
                price: 10,
              }),
            )
          ).status,
        ).toBe(200);
      const patch =
        kind === 'CATEGORY'
          ? { nameKa: 'Original', nameEn: 'Original' }
          : kind === 'SUBCATEGORY'
            ? { categoryId, nameKa: 'Original', nameEn: 'Original' }
            : kind === 'ITEM'
              ? {
                  categoryId,
                  nameKa: 'Original',
                  nameEn: 'Original',
                  price: 10,
                }
              : { menuItemId, size: 0.15, price: 10 };
      const body = mutation(kind, entityId, patch);
      expect((await send(body)).status).toBe(200);
      return body;
    }
    beforeAll(async () => {
      runtime = await menu03App(url!);
      fixture = await seedMenu03(runtime.db, runtime.app);
    });
    afterAll(async () => {
      await runtime?.app.close();
      await runtime?.db.$disconnect();
    });

    for (const kind of [
      'CATEGORY',
      'SUBCATEGORY',
      'ITEM',
      'VARIANT',
    ] as const) {
      it(`${kind}: immediate / later edit / delete / DELETE / changed-body replay`, async () => {
        const initial = await create(kind);
        const m1 = mutation(
          kind,
          initial.entityId,
          kind === 'VARIANT' ? { price: 12 } : { nameEn: 'M1' },
          1,
        );
        m1.resolution = 'REAPPLY';
        const original = await send(m1, 'OWNER');
        expect(original.status).toBe(200);
        expect(original.body.revision).toBe(2);
        const where = {
          venueId_mutationId: {
            venueId: fixture.venues[0].venueId,
            mutationId: m1.mutationId,
          },
        };
        const saved = await runtime.db.menuCatalogMutation.findUniqueOrThrow({
          where,
        });
        expect(saved.acceptedResult).toEqual(original.body);
        expect(saved.resolution).toBe('REAPPLY');
        const immediate = await send(m1);
        expect(immediate.status).toBe(200);
        expect(immediate.body.duplicate).toBe(true);
        expect(menu03Outcome(immediate.body)).toEqual(
          menu03Outcome(original.body),
        );
        const m2 = mutation(
          kind,
          initial.entityId,
          kind === 'VARIANT' ? { price: 20 } : { nameEn: 'M2' },
          2,
        );
        expect((await send(m2)).status).toBe(200);
        expect(menu03Outcome((await send(m1)).body)).toEqual(
          menu03Outcome(original.body),
        );
        const del = {
          ...m2,
          mutationId: randomUUID(),
          operation: 'DELETE',
          expectedRevision: 3,
          patch: undefined,
        };
        const deleted = await send(del);
        expect(deleted.status).toBe(200);
        expect(deleted.body).toMatchObject({
          deleted: true,
          entity: null,
          revision: 4,
        });
        expect(menu03Outcome((await send(m1)).body)).toEqual(
          menu03Outcome(original.body),
        );
        await create('CATEGORY');
        expect(menu03Outcome((await send(del, 'OWNER')).body)).toEqual(
          menu03Outcome(deleted.body),
        );
        const changed = await send({
          ...m1,
          patch: kind === 'VARIANT' ? { price: 99 } : { nameEn: 'Reused' },
        });
        expect(changed.status).toBe(409);
        expect(changed.body.code).toBe('MUTATION_ID_REUSED');
        expect(
          await runtime.db.menuCatalogMutation.findUniqueOrThrow({ where }),
        ).toEqual(saved);
        const feed = await runtime.app
          .get<MenuCatalogService>(MenuCatalogService)
          .changes(fixture.venues[0].venueId, original.body.sequence);
        expect(
          feed.tombstones.filter((t) => t.entityId === initial.entityId),
        ).toHaveLength(1);
      });
    }

    it('concurrent exact requests serialize into one durable result and one owner audit', async () => {
      const body = mutation('CATEGORY', randomUUID(), {
        nameKa: 'Concurrent',
        nameEn: 'Concurrent',
      });

      const results = await Promise.all(
        Array.from({ length: 5 }, () => send(body, 'OWNER')),
      );
      expect(results.map((r) => r.status)).toEqual([200, 200, 200, 200, 200]);
      expect(results.filter((r) => !r.body.duplicate)).toHaveLength(1);
      for (const result of results)
        expect(menu03Outcome(result.body)).toEqual(
          menu03Outcome(results[0].body),
        );
      expect(
        await runtime.db.menuCatalogMutation.count({
          where: { mutationId: body.mutationId },
        }),
      ).toBe(1);
      expect(
        await runtime.db.customerAuditEvent.count({
          where: { targetId: body.entityId },
        }),
      ).toBe(1);
    });

    it('stores only the server response, ignoring client-supplied replay envelopes', async () => {
      const body = mutation('CATEGORY', randomUUID(), {
        nameKa: 'Trusted',
        nameEn: 'Trusted',
      });
      const forged = {
        status: 'ACCEPTED',
        entity: { privateSecret: 'untrusted-client-field' },
      };
      const result = await send({
        ...body,
        acceptedResult: forged,
        entity: forged.entity,
      });
      expect(result.status).toBe(200);
      const saved = await runtime.db.menuCatalogMutation.findUniqueOrThrow({
        where: {
          venueId_mutationId: {
            venueId: fixture.venues[0].venueId,
            mutationId: body.mutationId,
          },
        },
      });
      expect(saved.acceptedResult).toEqual(result.body);
      expect(JSON.stringify(saved.acceptedResult)).not.toContain(
        'privateSecret',
      );
      expect(menu03Outcome((await send(body)).body)).toEqual(
        menu03Outcome(result.body),
      );
    });

    it('same mutation ID is independently scoped to two Venues; forged tenant selectors grant nothing', async () => {
      const a = mutation('CATEGORY', randomUUID(), {
        nameKa: 'A private',
        nameEn: 'A private',
      });
      const ra = await send({ ...a, venueId: fixture.venues[1].venueId });
      const foreignFirst = await send(a, 'DEVICE', 1);
      expect(foreignFirst.status).toBe(409);
      expect(foreignFirst.body.code).toBe('ID_UNAVAILABLE');
      expect(foreignFirst.body.entity).toBeUndefined();
      const b = {
        ...a,
        entityId: randomUUID(),
        patch: { nameKa: 'B private', nameEn: 'B private' },
      };
      const rb = await send(b, 'DEVICE', 1);
      expect(ra.status).toBe(200);
      expect(rb.status).toBe(200);
      expect(rb.body.entityId).not.toBe(ra.body.entityId);
      expect(menu03Outcome((await send(a)).body)).toEqual(
        menu03Outcome(ra.body),
      );
      expect(menu03Outcome((await send(b, 'OWNER', 1)).body)).toEqual(
        menu03Outcome(rb.body),
      );
      expect((await send(a, 'DEVICE', 1)).body.code).toBe('MUTATION_ID_REUSED');
      const foreignOwner = await menu03Request(
        runtime.base,
        { ...fixture.venues[0], venueId: fixture.venues[1].venueId },
        b,
        'OWNER',
      );
      expect(foreignOwner.status).toBe(404);
      const invalidDevice = await menu03Request(
        runtime.base,
        { ...fixture.venues[0], credential: 'legacy-shared-key' },
        a,
      );
      expect(invalidDevice.status).toBe(401);
      expect(
        await runtime.db.menuCatalogMutation.count({
          where: { mutationId: a.mutationId },
        }),
      ).toBe(2);
    });

    it('no-op UPSERT and already-missing DELETE replay their original sequence after unrelated activity', async () => {
      const first = await create('CATEGORY');
      const noop = { ...first, mutationId: randomUUID(), expectedRevision: 1 };
      const a = await send(noop);
      const missing = {
        mutationId: randomUUID(),
        entityType: 'ITEM',
        entityId: randomUUID(),
        operation: 'DELETE',
        expectedRevision: 0,
      };
      const b = await send(missing);
      expect(b.body.revision).toBe(0);
      await create('CATEGORY');
      expect(menu03Outcome((await send(noop)).body)).toEqual(
        menu03Outcome(a.body),
      );
      expect(menu03Outcome((await send(missing)).body)).toEqual(
        menu03Outcome(b.body),
      );
    });

    it('conflict, invalid input and policy denial are not durable outcomes', async () => {
      const first = await create('CATEGORY');
      const conflict = {
        ...first,
        mutationId: randomUUID(),
        expectedRevision: 0,
        patch: { nameEn: 'Pending' },
      };
      expect((await send(conflict)).body.code).toBe('REVISION_CONFLICT');
      await send({
        ...first,
        mutationId: randomUUID(),
        expectedRevision: 1,
        patch: { nameEn: 'Newer' },
      });
      expect((await send(conflict)).body.conflict?.currentRevision).toBe(2);
      const invalid = {
        ...first,
        mutationId: randomUUID(),
        patch: { arbitraryResponse: { status: 'ACCEPTED' } },
      };
      expect((await send(invalid)).status).toBe(400);
      const denied = {
        ...first,
        mutationId: randomUUID(),
        expectedRevision: 2,
      };
      await runtime.db.venue.update({
        where: { id: fixture.venues[0].venueId },
        data: { cloudMenuEditingEnabled: false },
      });
      expect((await send(denied, 'OWNER')).body.code).toBe('EDITING_DISABLED');
      await runtime.db.venue.update({
        where: { id: fixture.venues[0].venueId },
        data: { cloudMenuEditingEnabled: true },
      });
      expect(
        await runtime.db.menuCatalogMutation.count({
          where: {
            mutationId: {
              in: [conflict.mutationId, invalid.mutationId, denied.mutationId],
            },
          },
        }),
      ).toBe(0);
      expect((await send(denied, 'OWNER')).status).toBe(200);
    });

    it('legacy row remains incomplete, preserves fingerprint protection and requests resync', async () => {
      const body = await create('CATEGORY');
      const where = {
        venueId_mutationId: {
          venueId: fixture.venues[0].venueId,
          mutationId: body.mutationId,
        },
      };
      await runtime.db.menuCatalogMutation.update({
        where,
        data: { acceptedResult: Prisma.DbNull },
      });
      const before = await runtime.db.menuCatalogMutation.findUniqueOrThrow({
        where,
      });
      const retry = await send(body);
      expect(retry.status).toBe(409);
      expect(retry.body).toMatchObject({
        code: 'MUTATION_RESULT_UNAVAILABLE',
        resyncRequired: true,
        mutationId: body.mutationId,
      });
      expect(retry.body.entity).toBeUndefined();
      expect(
        (await send({ ...body, patch: { nameEn: 'Changed' } })).body.code,
      ).toBe('MUTATION_ID_REUSED');
      expect(
        await runtime.db.menuCatalogMutation.findUniqueOrThrow({ where }),
      ).toEqual(before);
    });

    it('a newly instantiated Nest service and Prisma connection replay the same result after deletion', async () => {
      const body = await create('CATEGORY');
      const original = await send(body);
      await send({
        ...body,
        mutationId: randomUUID(),
        operation: 'DELETE',
        patch: undefined,
        expectedRevision: 1,
      });
      await runtime.app.close();
      await runtime.db.$disconnect();
      runtime = await menu03App(url!);
      expect(menu03Outcome((await send(body)).body)).toEqual(
        menu03Outcome(original.body),
      );
    });
  },
);
