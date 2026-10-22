import { randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { PrismaService } from '../prisma.service';
import type { InventoryActor } from './inventory-audit';
import { InventoryService } from './inventory.service';
import { ReceivingService } from './receiving.service';
import { RecipeService } from './recipe.service';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase =
  url && isFreshDisposableDatabase(url) ? describe : describe.skip;

function signal() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => (resolve = done));
  return { promise, resolve };
}

/** Pause after a real database read, while retaining its transaction locks. */
function transactionProbe(
  db: PrismaService,
  gate?: { model: string; method: string },
) {
  const entered = signal();
  const released = signal();
  let resolvePid!: (pid: number) => void;
  const pid = new Promise<number>((done) => (resolvePid = done));
  const serviceDb = new Proxy(db, {
    get(target, property) {
      if (property === '$transaction') {
        return (work: (tx: Prisma.TransactionClient) => Promise<unknown>) =>
          target.$transaction(
            async (tx) => {
              const [connection] = await tx.$queryRaw<{ pid: number }[]>`
                SELECT pg_backend_pid() AS pid
              `;
              resolvePid(connection.pid);
              const probed = new Proxy(tx, {
                get(transaction, name) {
                  const value = Reflect.get(transaction, name);
                  if (name === gate?.model) {
                    return new Proxy(value, {
                      get(model, method) {
                        const call = Reflect.get(model, method);
                        if (method === gate.method) {
                          return async (...args: unknown[]) => {
                            const result = await call.apply(model, args);
                            entered.resolve();
                            await released.promise;
                            return result;
                          };
                        }
                        return typeof call === 'function'
                          ? call.bind(model)
                          : call;
                      },
                    });
                  }
                  return typeof value === 'function'
                    ? value.bind(transaction)
                    : value;
                },
              });
              return work(probed);
            },
            { timeout: 15000 },
          );
      }
      const value = Reflect.get(target, property);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  return {
    db: serviceDb,
    pid,
    entered: entered.promise,
    release: released.resolve,
  };
}

function observe<T>(work: Promise<T>) {
  let finished = false;
  const result = work.then(
    (value): PromiseFulfilledResult<T> => {
      finished = true;
      return { status: 'fulfilled', value };
    },
    (reason): PromiseRejectedResult => {
      finished = true;
      return { status: 'rejected', reason };
    },
  );
  return { result, finished: () => finished };
}

/** Observe the actual PostgreSQL wait; no scheduler-dependent sleep assertion. */
async function expectBlocked(
  db: PrismaService,
  pid: number,
  finished: () => boolean,
) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const [state] = await db.$queryRaw<{ blockers: number[] }[]>`
      SELECT pg_blocking_pids(${pid}::int) AS blockers
    `;
    if (state.blockers.length) return;
    if (finished())
      throw Error('Unit-sensitive request bypassed the stock lock');
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw Error('Expected a PostgreSQL stock-item lock wait');
}

describeDatabase(
  'Inventory unit integrity (owned disposable PostgreSQL)',
  () => {
    let db: PrismaService;
    let inventory: InventoryService;
    let receiving: ReceivingService;
    let recipes: RecipeService;
    let actor: InventoryActor;
    let organizationId: string;
    const suffix = randomUUID();

    beforeAll(async () => {
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const org = await db.organization.create({ data: { name: suffix } });
      organizationId = org.id;
      const venue = await db.venue.create({
        data: {
          organizationId,
          name: suffix,
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      actor = {
        venueId: venue.id,
        organizationId,
        staffId: 'synthetic-unit-manager',
        username: 'Synthetic unit manager',
      };
      recipes = new RecipeService(db);
      inventory = new InventoryService(db, recipes);
      receiving = new ReceivingService(db);
    });

    afterAll(async () => {
      if (!db) return;
      if (actor) {
        const where = { venueId: actor.venueId };
        await db.stockMovement.deleteMany({ where });
        await db.receivingLine.deleteMany({
          where: { receiving: { venueId: actor.venueId } },
        });
        await db.receiving.deleteMany({ where });
        await db.menuConsumptionComponent.deleteMany({ where });
        await db.menuConsumptionRecipe.deleteMany({ where });
        await db.stockItem.deleteMany({ where });
        await db.supplier.deleteMany({ where });
        await db.menuItem.deleteMany({ where });
        await db.menuCategory.deleteMany({ where });
        await db.auditEventLog.deleteMany({ where });
        await db.venue.delete({ where: { id: actor.venueId } });
      }
      if (organizationId)
        await db.organization.delete({ where: { id: organizationId } });
      await db.$disconnect();
    });

    async function item() {
      return inventory.createStockItem(actor, {
        name: randomUUID(),
        baseUnit: 'kg',
      });
    }

    async function menuItem() {
      const category = await db.menuCategory.create({
        data: {
          venueId: actor.venueId,
          slug: randomUUID(),
          nameKa: 'Synthetic category',
          nameEn: 'Synthetic category',
        },
      });
      return db.menuItem.create({
        data: {
          venueId: actor.venueId,
          categoryId: category.id,
          posMenuItemId: randomUUID(),
          nameKa: 'Synthetic recipe',
          nameEn: 'Synthetic recipe',
          price: 10,
        },
      });
    }

    async function draft(stockItemId: string) {
      return receiving.createDraft(actor, {
        sourceType: 'SELF_PURCHASE',
        documentDate: '2026-10-17',
        businessDate: '2026-10-17',
        lines: [{ stockItemId, enteredQuantity: '1', unitPurchaseCost: '10' }],
      });
    }

    it('rejects rounded-zero recipes atomically and keeps the minimum representable portion valid', async () => {
      const stock = await item();
      const menu = await menuItem();
      const auditCount = await db.auditEventLog.count({
        where: { venueId: actor.venueId },
      });
      const input = {
        menuItemId: menu.id,
        components: [{ stockItemId: stock.id, quantity: '0.001', unit: 'kg' }],
      };
      await expect(
        recipes.save(actor, { ...input, yieldQuantity: '10000' }),
      ).rejects.toThrow(
        'Consumption per sold unit must be at least 0.000001 base units after rounding',
      );
      expect(
        await db.menuConsumptionRecipe.count({
          where: { menuItemId: menu.id },
        }),
      ).toBe(0);
      expect(
        await db.menuConsumptionComponent.count({
          where: { stockItemId: stock.id },
        }),
      ).toBe(0);
      expect(
        await db.stockMovement.count({ where: { stockItemId: stock.id } }),
      ).toBe(0);
      expect(
        await db.auditEventLog.count({ where: { venueId: actor.venueId } }),
      ).toBe(auditCount);
      const saved = await recipes.save(actor, {
        ...input,
        yieldQuantity: '2000',
      });
      expect(saved.components[0].baseQuantityPerUnit).toBe('0.000001');
    });

    it('a first receipt holds its unit through posting and refuses a waiting unit edit', async () => {
      const stock = await item();
      const receipt = await draft(stock.id);
      const holder = transactionProbe(db, {
        model: 'stockItem',
        method: 'findMany',
      });
      const posting = observe(
        new ReceivingService(holder.db).post(actor, receipt.id),
      );
      await holder.entered;
      const waiter = transactionProbe(db);
      const edit = observe(
        new InventoryService(waiter.db, recipes).updateStockItem(
          actor,
          stock.id,
          { baseUnit: 'g' },
        ),
      );
      try {
        await expectBlocked(db, await waiter.pid, edit.finished);
      } finally {
        holder.release();
        await Promise.all([posting.result, edit.result]);
      }
      expect((await posting.result).status).toBe('fulfilled');
      const edited = await edit.result;
      expect(edited.status).toBe('rejected');
      if (edited.status === 'rejected')
        expect(edited.reason.message).toContain('must keep its base unit');
      const row = await db.stockItem.findUniqueOrThrow({
        where: { id: stock.id },
      });
      expect(row.baseUnit).toBe('kg');
      expect((await receiving.detail(actor, receipt.id)).status).toBe('POSTED');
      expect((await inventory.getStockItem(actor, stock.id)).currentStock).toBe(
        '1.000',
      );
    });

    it('a first recipe holds its unit through saving and refuses a waiting unit edit', async () => {
      const stock = await item();
      const menu = await menuItem();
      const holder = transactionProbe(db, {
        model: 'stockItem',
        method: 'findMany',
      });
      const saving = observe(
        new RecipeService(holder.db).save(actor, {
          menuItemId: menu.id,
          components: [{ stockItemId: stock.id, quantity: '1', unit: 'kg' }],
        }),
      );
      await holder.entered;
      const waiter = transactionProbe(db);
      const edit = observe(
        new InventoryService(waiter.db, recipes).updateStockItem(
          actor,
          stock.id,
          { baseUnit: 'g' },
        ),
      );
      try {
        await expectBlocked(db, await waiter.pid, edit.finished);
      } finally {
        holder.release();
        await Promise.all([saving.result, edit.result]);
      }
      expect((await saving.result).status).toBe('fulfilled');
      expect((await edit.result).status).toBe('rejected');
      expect(
        (await db.stockItem.findUniqueOrThrow({ where: { id: stock.id } }))
          .baseUnit,
      ).toBe('kg');
      expect(
        (await recipes.detail(actor, menu.id)).recipe?.components[0].baseUnit,
      ).toBe('kg');
    });

    for (const kind of ['receipt', 'recipe'] as const) {
      it(`a unit edit completes before a waiting first ${kind} validates its units`, async () => {
        const stock = await item();
        const receipt = kind === 'receipt' ? await draft(stock.id) : null;
        const menu = kind === 'recipe' ? await menuItem() : null;
        const holder = transactionProbe(db, {
          model: 'menuConsumptionComponent',
          method: 'findFirst',
        });
        const edit = observe(
          new InventoryService(holder.db, recipes).updateStockItem(
            actor,
            stock.id,
            { baseUnit: 'g' },
          ),
        );
        await holder.entered;
        const waiter = transactionProbe(db);
        const work = observe<unknown>(
          kind === 'receipt'
            ? new ReceivingService(waiter.db).post(actor, receipt!.id)
            : new RecipeService(waiter.db).save(actor, {
                menuItemId: menu!.id,
                components: [
                  { stockItemId: stock.id, quantity: '1', unit: 'kg' },
                ],
              }),
        );
        try {
          await expectBlocked(db, await waiter.pid, work.finished);
        } finally {
          holder.release();
          await Promise.all([edit.result, work.result]);
        }
        expect((await edit.result).status).toBe('fulfilled');
        expect(
          (await db.stockItem.findUniqueOrThrow({ where: { id: stock.id } }))
            .baseUnit,
        ).toBe('g');
        if (kind === 'receipt') {
          const posted = await work.result;
          expect(posted.status).toBe('rejected');
          if (posted.status === 'rejected')
            expect(posted.reason.message).toContain('base unit changed');
          expect((await receiving.detail(actor, receipt!.id)).status).toBe(
            'DRAFT',
          );
          expect(
            await db.stockMovement.count({ where: { stockItemId: stock.id } }),
          ).toBe(0);
        } else {
          expect((await work.result).status).toBe('fulfilled');
          const saved = (await recipes.detail(actor, menu!.id)).recipe!;
          expect(saved.components[0].baseUnit).toBe('g');
          expect(saved.components[0].baseQuantityPerUnit).toBe('1000.000000');
        }
      });
    }
  },
);
