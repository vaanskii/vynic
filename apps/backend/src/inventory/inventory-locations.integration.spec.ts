import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { resolve } from 'node:path';
import { Prisma } from '@prisma/client';
import { inventoryPhase8Fixture } from '../../test/inventory-phase8.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import {
  assertMatrixComplete,
  delegate,
  venueFilter,
  venueModels,
} from '../local-tools/deletion-matrix';

// Match the existing HTTP fixture's CJS Jest adapter for uuid's ESM package.
jest.mock('uuid', () => ({
  v4: () => randomUUID(),
}));

const url = process.env.INV1_TEST_DATABASE_URL;
const describeDatabase =
  url && isFreshDisposableDatabase(url) ? describe : describe.skip;
const runProcess = promisify(execFile);

describeDatabase(
  'INV-01 F1 quantity locations (owned PostgreSQL and HTTP)',
  () => {
    let f: Awaited<ReturnType<typeof inventoryPhase8Fixture>>;
    beforeAll(async () => {
      f = await inventoryPhase8Fixture(url!);
    });
    afterAll(async () => {
      await f?.close();
    });

    function identity(raw: unknown): { id: string } {
      if (
        !raw ||
        typeof raw !== 'object' ||
        !('id' in raw) ||
        typeof raw.id !== 'string'
      )
        throw Error('Fixture returned no durable identity');
      return { id: raw.id };
    }
    async function location(name = 'Synthetic warehouse') {
      return f.inventory.createLocation(f.a.actor, {
        requestId: randomUUID(),
        name,
      });
    }
    async function receipt(
      stockItemId: string,
      locationId?: string,
      cost = '3',
      qty = '20',
    ) {
      const draft = identity(
        await f.receiving.createDraft(f.a.actor, {
          requestId: randomUUID(),
          sourceType: 'SELF_PURCHASE',
          sourceLabel: 'Synthetic purchase',
          locationId,
          documentDate: '2026-09-01',
          lines: [
            { stockItemId, enteredQuantity: qty, unitPurchaseCost: cost },
          ],
        }),
      );
      await f.receiving.post(f.a.actor, draft.id);
      return draft;
    }
    async function request(
      path: string,
      method: string,
      input: unknown,
      token = f.a.token,
    ) {
      const response = await fetch(f.base + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: 'Bearer ' + token } : {}),
        },
        body: JSON.stringify(input),
      });
      return {
        status: response.status,
        body: (await response.json()) as Record<string, unknown>,
      };
    }
    async function retryProcess(kind: string, input: string) {
      const result = await runProcess(
        process.execPath,
        [
          '-r',
          'ts-node/register/transpile-only',
          resolve(
            __dirname,
            '../../test/inventory-location-process.fixture.ts',
          ),
        ],
        {
          cwd: resolve(__dirname, '../..'),
          env: {
            ...process.env,
            INV1_TEST_DATABASE_URL: url,
            INV1_RETRY_ACTOR: JSON.stringify(f.a.actor),
            INV1_RETRY_KIND: kind,
            INV1_RETRY_INPUT: input,
          },
          timeout: 20000,
        },
      );
      return JSON.parse(result.stdout) as Record<string, unknown>;
    }

    it('new Venues get exactly one durable default, and SQL rejects a second default', async () => {
      const a = await f.inventory.locations(f.a.tenant);
      const b = await f.inventory.locations(f.b.tenant);
      expect(a).toHaveLength(1);
      expect(b).toHaveLength(1);
      expect(a[0]).toMatchObject({ isDefault: true, name: 'ძირითადი მარაგი' });
      expect(a[0].id).not.toBe(b[0].id);
      await expect(
        f.db.stockLocation.create({
          data: {
            venueId: f.a.tenant.venueId,
            name: 'Duplicate default',
            isDefault: true,
          },
        }),
      ).rejects.toMatchObject({ code: 'P2002' });
    });

    it('concurrent creation, renamed retry and UUID casing retain one identity and one atomic audit', async () => {
      const input = {
        requestId: randomUUID(),
        name: 'Synthetic concurrent warehouse',
      };
      const rows = await Promise.all(
        Array.from({ length: 8 }, () =>
          f.inventory.createLocation(f.a.actor, input),
        ),
      );
      expect(new Set(rows.map((r) => r.id)).size).toBe(1);
      await f.inventory.renameLocation(f.a.actor, rows[0].id, {
        name: 'Renamed warehouse',
      });
      expect(
        await f.inventory.createLocation(f.a.actor, {
          ...input,
          requestId: input.requestId.toUpperCase(),
        }),
      ).toMatchObject({ id: rows[0].id, name: 'Renamed warehouse' });
      expect(
        await f.db.auditEventLog.count({
          where: { entityId: rows[0].id, action: 'STOCK_LOCATION_CREATED' },
        }),
      ).toBe(1);
      await expect(
        f.inventory.createLocation(f.a.actor, {
          ...input,
          name: 'Different intent',
        }),
      ).rejects.toMatchObject({ status: 409 });
      await expect(
        f.inventory.renameLocation(f.b.actor, rows[0].id, {
          name: 'Other Venue',
        }),
      ).rejects.toMatchObject({ status: 404 });
      const b = await f.inventory.createLocation(f.b.actor, input);
      expect(b.id).not.toBe(rows[0].id);
    });

    it('a new process safely retries a committed location and receiving after a lost response', async () => {
      const input = { requestId: randomUUID(), name: 'Process warehouse' };
      const original = await retryProcess('location', JSON.stringify(input));
      expect(await retryProcess('location', JSON.stringify(input))).toEqual(
        original,
      );
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Process flour',
          baseUnit: 'kg',
        }),
      );
      const draft = identity(
        await f.receiving.createDraft(f.a.actor, {
          sourceType: 'SELF_PURCHASE',
          sourceLabel: 'Synthetic',
          locationId: original.id,
          documentDate: '2026-09-01',
          lines: [
            {
              stockItemId: item.id,
              enteredQuantity: '20',
              unitPurchaseCost: '3',
            },
          ],
        }),
      );
      expect(await retryProcess('receiving', draft.id)).toMatchObject({
        result: 'posted',
      });
      expect(await retryProcess('receiving', draft.id)).toMatchObject({
        result: 'already_posted',
      });
      expect(
        await f.db.stockMovement.count({ where: { receivingId: draft.id } }),
      ).toBe(1);
      expect(
        await f.db.auditEventLog.count({
          where: { entityId: draft.id, action: 'RECEIVING_POSTED' },
        }),
      ).toBe(1);
    }, 30000);

    it('selected receipt location survives old-client edits, concurrent posting and a payment without changing Venue value or debt semantics', async () => {
      const selected = await location();
      const supplier = identity(
        await f.inventory.createSupplier(f.a.actor, {
          name: 'Synthetic flour supplier',
        }),
      );
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Flour',
          baseUnit: 'kg',
        }),
      );
      const input = {
        supplierId: supplier.id,
        documentDate: '2026-09-01',
        lines: [
          {
            stockItemId: item.id,
            enteredQuantity: '20',
            unitPurchaseCost: '3',
          },
        ],
      };
      const draft = identity(
        await f.receiving.createDraft(f.a.actor, {
          ...input,
          locationId: selected.id,
        }),
      );
      const edited = await f.receiving.updateDraft(f.a.actor, draft.id, input);
      expect(edited.locationId).toBe(selected.id);
      await Promise.all(
        Array.from({ length: 4 }, () => f.receiving.post(f.a.actor, draft.id)),
      );
      await f.receiving.recordPayment(f.a.actor, draft.id, {
        requestId: randomUUID(),
        amount: '30',
        paymentDate: '2026-09-02',
        method: 'cash',
      });
      const balances = await f.inventory.locationBalances(f.a.tenant, item.id);
      expect(balances.venueQuantity).toBe('20.000');
      expect(
        balances.locations.find((l) => l.id === selected.id)?.quantity,
      ).toBe('20.000');
      expect((await f.receiving.detail(f.a.tenant, draft.id)).remaining).toBe(
        '30.00',
      );
      const movements = await f.db.stockMovement.findMany({
        where: { receivingId: draft.id },
      });
      expect(movements).toHaveLength(1);
      expect(movements[0].locationId).toBe(selected.id);
      expect(movements[0].inventoryValueDelta?.toFixed(12)).toBe(
        '60.000000000000',
      );
      expect(
        (await f.get('/mobile/inventory/stock-items/' + item.id + '/locations'))
          .body,
      ).toMatchObject({ venueQuantity: '20.000' });
      expect(
        (await f.get('/mobile/inventory/stock-items/' + item.id + '/movements'))
          .body,
      ).toMatchObject({ items: [{ locationId: selected.id }] });
    });

    it('receipt reversal uses its original location and value after a rename and later price changes, once under concurrency', async () => {
      const selected = await location('Reverse warehouse');
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Reversal flour',
          baseUnit: 'kg',
        }),
      );
      const first = await receipt(item.id, selected.id);
      await receipt(item.id, undefined, '9', '10');
      await f.inventory.renameLocation(f.a.actor, selected.id, {
        name: 'Renamed after receipt',
      });
      await Promise.all(
        Array.from({ length: 4 }, () =>
          f.receiving.cancel(f.a.actor, first.id, 'Synthetic correction'),
        ),
      );
      const moves = await f.db.stockMovement.findMany({
        where: { receivingId: first.id },
        orderBy: { valuationSequence: 'asc' },
      });
      expect(moves).toHaveLength(2);
      expect(moves.every((m) => m.locationId === selected.id)).toBe(true);
      expect(moves[1].inventoryValueDelta?.toFixed(12)).toBe(
        '-60.000000000000',
      );
      expect(moves[1].costPerBaseUnit?.toFixed(12)).toBe('3.000000000000');
      const balances = await f.inventory.locationBalances(f.a.tenant, item.id);
      expect(balances.venueQuantity).toBe('10.000');
      expect(
        balances.locations.find((l) => l.id === selected.id)?.quantity,
      ).toBe('0.000');
    });

    it('foreign locations are rejected by HTTP and composite SQL ownership, with no document or audit writes', async () => {
      const foreign = (await f.inventory.locations(f.b.tenant))[0];
      const input = {
        requestId: randomUUID(),
        sourceType: 'SELF_PURCHASE',
        sourceLabel: 'Synthetic',
        documentDate: '2026-09-01',
        locationId: foreign.id,
      };
      expect(
        (await request('/mobile/inventory/receivings', 'POST', input)).status,
      ).toBe(404);
      expect(
        await f.db.receiving.count({
          where: {
            venueId: f.a.tenant.venueId,
            creationRequestId: input.requestId,
          },
        }),
      ).toBe(0);
      await expect(
        f.db.receiving.create({
          data: {
            venueId: f.a.tenant.venueId,
            locationId: foreign.id,
            sourceType: 'SELF_PURCHASE',
            supplierNameSnapshot: 'Synthetic',
            documentDate: '2026-09-01',
            businessDate: '2026-09-01',
            receivedAt: new Date(),
            createdById: 'proof',
            createdByName: 'proof',
          },
        }),
      ).rejects.toMatchObject({ code: 'P2003' });
      const item = identity(
        await f.inventory.createStockItem(f.b.actor, {
          name: 'Other Venue item',
          baseUnit: 'kg',
        }),
      );
      expect(
        (await f.get('/mobile/inventory/stock-items/' + item.id + '/locations'))
          .status,
      ).toBe(404);
    });

    it('committed movement and posted receipt locations cannot be rewritten or reversed in another location', async () => {
      const selected = await location('Immutable warehouse');
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Immutable flour',
          baseUnit: 'kg',
        }),
      );
      const r = await receipt(item.id, selected.id);
      const original = await f.db.stockMovement.findFirstOrThrow({
        where: { receivingId: r.id },
      });
      const other = (await f.inventory.locations(f.a.tenant))[0].id;
      await expect(
        f.db.receiving.update({
          where: { id: r.id },
          data: { locationId: other },
        }),
      ).rejects.toThrow('immutable');
      await expect(
        f.db.stockMovement.update({
          where: { id: original.id },
          data: { locationId: other },
        }),
      ).rejects.toThrow('immutable');
      await expect(
        f.db.stockMovement.create({
          data: {
            venueId: f.a.tenant.venueId,
            stockItemId: item.id,
            locationId: other,
            movementType: 'RECEIVING_REVERSAL',
            quantityDeltaBase: '-20',
            baseUnit: 'kg',
            reversalOfMovementId: original.id,
            businessDate: '2026-09-01',
            effectiveAt: new Date(),
            actorId: 'proof',
            actorName: 'proof',
            source: 'MANAGER',
          },
        }),
      ).rejects.toThrow('differs from source');
      expect(
        await f.db.stockMovement.count({ where: { receivingId: r.id } }),
      ).toBe(1);
    });

    it('old version-1 POS snapshots use the default, preserving negative location quantities and D015 Venue valuation through restore/retry', async () => {
      const selected = await location('Legacy purchase warehouse');
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Legacy flour',
          baseUnit: 'kg',
        }),
      );
      await receipt(item.id, selected.id);
      const category = await f.db.menuCategory.create({
        data: {
          venueId: f.a.tenant.venueId,
          slug: randomUUID(),
          nameKa: 'Synthetic',
          nameEn: 'Synthetic',
        },
      });
      const menu = await f.db.menuItem.create({
        data: {
          venueId: f.a.tenant.venueId,
          categoryId: category.id,
          nameKa: 'Synthetic',
          nameEn: 'Synthetic',
          price: 10,
          posMenuItemId: randomUUID(),
        },
      });
      await f.recipes.save(f.a.actor, {
        menuItemId: menu.id,
        components: [{ stockItemId: item.id, quantity: '2.5', unit: 'kg' }],
      });
      const recipe = (await f.recipes.projection(f.a.tenant.venueId)).find(
        (r) => r.menuItemId === menu.id,
      )!;
      const payload = {
        posSaleId: randomUUID(),
        closureId: randomUUID(),
        orderId: 1,
        businessDate: '2026-09-01',
        closedAt: '2026-09-01T12:00:00.000Z',
        snapshot: {
          version: 1,
          policy: 'FISCAL_CLOSE',
          lines: [
            {
              lineSeq: 0,
              itemName: 'Synthetic',
              menuItemId: recipe.posMenuItemId,
              soldQuantity: 1,
              status: 'MAPPED',
              recipeId: recipe.recipeId,
              recipeRevision: recipe.revision,
              components: recipe.components.map((c) => ({
                ...c,
                totalBaseQuantity: '2.500000',
              })),
            },
          ],
        },
      };
      await Promise.all([
        f.consumption.apply(f.a.tenant, payload),
        f.consumption.apply(f.a.tenant, payload),
      ]);
      const balances = await f.inventory.locationBalances(f.a.tenant, item.id);
      expect(balances.venueQuantity).toBe('17.500');
      expect(balances.locations.find((l) => l.isDefault)?.quantity).toBe(
        '-2.500',
      );
      expect(
        balances.locations.find((l) => l.id === selected.id)?.quantity,
      ).toBe('20.000');
      const original = await f.db.stockMovement.findFirstOrThrow({
        where: { stockItemId: item.id, movementType: 'CONSUMPTION' },
      });
      expect(original.inventoryValueDelta?.toFixed(12)).toBe('-7.500000000000');
      await Promise.all(
        Array.from({ length: 4 }, () =>
          f.consumption.apply(f.a.tenant, {
            ...payload,
            reversedAt: '2026-09-02T12:00:00.000Z',
          }),
        ),
      );
      const reverse = await f.db.stockMovement.findMany({
        where: { reversalOfMovementId: original.id },
      });
      expect(reverse).toHaveLength(1);
      expect(reverse[0].locationId).toBe(original.locationId);
      expect(reverse[0].inventoryValueDelta?.toFixed(12)).toBe(
        '7.500000000000',
      );
      expect(
        (await f.inventory.locationBalances(f.a.tenant, item.id)).venueQuantity,
      ).toBe('20.000');
    });

    it('a failing audit rolls back location creation, and retry can commit exactly once afterward', async () => {
      const input = {
        requestId: randomUUID(),
        name: 'Synthetic rollback location',
      };
      await f.db.$executeRawUnsafe(
        `CREATE FUNCTION pos.inv1_proof_audit_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='STOCK_LOCATION_CREATED' AND NEW.data->>'name'='Synthetic rollback location' THEN RAISE EXCEPTION 'Injected isolated proof failure'; END IF; RETURN NEW; END $$`,
      );
      await f.db.$executeRawUnsafe(
        `CREATE TRIGGER inv1_proof_audit_failure BEFORE INSERT ON pos."AuditEventLog" FOR EACH ROW EXECUTE FUNCTION pos.inv1_proof_audit_failure()`,
      );
      try {
        expect(
          (await request('/mobile/inventory/locations', 'POST', input)).status,
        ).toBe(500);
        expect(
          await f.db.stockLocation.count({
            where: {
              venueId: f.a.tenant.venueId,
              creationRequestId: input.requestId,
            },
          }),
        ).toBe(0);
      } finally {
        await f.db.$executeRawUnsafe(
          `DROP TRIGGER inv1_proof_audit_failure ON pos."AuditEventLog"`,
        );
        await f.db.$executeRawUnsafe(
          `DROP FUNCTION pos.inv1_proof_audit_failure()`,
        );
      }
      expect(
        (await request('/mobile/inventory/locations', 'POST', input)).status,
      ).toBe(201);
    });

    it('balances conserve the Venue sum within one read snapshot during concurrent receipts and reversals', async () => {
      const selected = await location('Concurrent balance warehouse');
      const item = identity(
        await f.inventory.createStockItem(f.a.actor, {
          name: 'Concurrent flour',
          baseUnit: 'kg',
        }),
      );
      const writer = (async () => {
        for (let i = 0; i < 6; i++) {
          const r = await receipt(item.id, i % 2 ? selected.id : undefined);
          await f.receiving.cancel(f.a.actor, r.id, 'Synthetic balancing');
        }
      })();
      for (let i = 0; i < 12; i++) {
        const result = await f.inventory.locationBalances(f.a.tenant, item.id);
        const sum = result.locations.reduce(
          (q, l) => q.plus(l.quantity),
          new Prisma.Decimal(0),
        );
        expect(sum.equals(result.venueQuantity)).toBe(true);
      }
      await writer;
      expect(
        (await f.inventory.locationBalances(f.a.tenant, item.id)).venueQuantity,
      ).toBe('0.000');
      expect(
        (await f.inventory.currentStock(f.a.tenant.venueId))
          .get(item.id)
          ?.isZero(),
      ).toBe(true);
    });

    it('the existing child-first deletion matrix handles location references, retains another Venue and fully rolls back', async () => {
      assertMatrixComplete();
      const aBefore = await f.db.stockLocation.count({
        where: { venueId: f.a.tenant.venueId },
      });
      const bBefore = await f.db.stockLocation.count({
        where: { venueId: f.b.tenant.venueId },
      });
      await expect(
        f.db.$transaction(async (tx) => {
          for (const model of venueModels) {
            await delegate(tx, model).deleteMany({
              where: venueFilter(model, [f.a.tenant.venueId]),
            });
          }
          await tx.venue.delete({ where: { id: f.a.tenant.venueId } });
          expect(
            await tx.stockLocation.count({
              where: { venueId: f.a.tenant.venueId },
            }),
          ).toBe(0);
          expect(
            await tx.stockLocation.count({
              where: { venueId: f.b.tenant.venueId },
            }),
          ).toBe(bBefore);
          throw Error('Synthetic deletion proof rollback');
        }),
      ).rejects.toThrow('Synthetic deletion proof rollback');
      expect(
        await f.db.stockLocation.count({
          where: { venueId: f.a.tenant.venueId },
        }),
      ).toBe(aBefore);
      expect(
        await f.db.venue.count({ where: { id: f.a.tenant.venueId } }),
      ).toBe(1);
    });

    it('location reads/writes retain Manager identity and Inventory entitlement denial, without permitting balance edits', async () => {
      const path = '/mobile/inventory/locations';
      expect((await f.get(path, '')).status).toBe(401);
      expect(
        (
          await request(
            path,
            'POST',
            { requestId: randomUUID(), name: 'Denied' },
            '',
          )
        ).status,
      ).toBe(401);
      await f.db.staff.update({
        where: { id: f.a.actor.staffId },
        data: { role: 'WAITER' },
      });
      try {
        expect((await f.get(path)).status).toBe(401);
      } finally {
        await f.db.staff.update({
          where: { id: f.a.actor.staffId },
          data: { role: 'MANAGER' },
        });
      }
      const feature = await f.db.feature.findUniqueOrThrow({
        where: { key: 'INVENTORY' },
      });
      await f.db.venueFeatureOverride.updateMany({
        where: { venueId: f.a.tenant.venueId, featureId: feature.id },
        data: { effect: 'DISABLED' },
      });
      try {
        expect((await f.get(path)).status).toBe(403);
        expect(
          (
            await request(path, 'POST', {
              requestId: randomUUID(),
              name: 'Denied',
            })
          ).status,
        ).toBe(403);
      } finally {
        await f.db.venueFeatureOverride.updateMany({
          where: { venueId: f.a.tenant.venueId, featureId: feature.id },
          data: { effect: 'ENABLED' },
        });
      }
      const target = (await f.inventory.locations(f.a.tenant))[0];
      expect(
        (await request(path + '/' + target.id, 'PATCH', { quantity: '999' }))
          .status,
      ).toBe(400);
    });
  },
);
