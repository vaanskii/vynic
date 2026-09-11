import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { InventoryService } from './inventory.service';
import { ReceivingService } from './receiving.service';
import { RecipeService, menuGroup } from './recipe.service';
import { InventoryCostService } from './inventory-cost.service';
import type { InventoryActor } from './inventory-audit';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
(databaseUrl ? describe : describe.skip)(
  'Inventory Step 4.5 (disposable PostgreSQL)',
  () => {
    const org = randomUUID(),
      venueA = randomUUID(),
      venueB = randomUUID();
    const actor = (venueId: string): InventoryActor => ({
      venueId,
      organizationId: org,
      staffId: 'manager',
      username: 'Manager',
    });
    const a = actor(venueA),
      b = actor(venueB);
    let db: PrismaService,
      inventory: InventoryService,
      receiving: ReceivingService,
      recipes: RecipeService,
      costs: InventoryCostService;
    beforeAll(async () => {
      db = new PrismaService({ datasourceUrl: databaseUrl });
      await db.$connect();
      await db.organization.create({
        data: {
          id: org,
          name: 'Step45',
          venues: {
            create: [venueA, venueB].map((id) => ({
              id,
              name: 'Test',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })),
          },
        },
      });
      recipes = new RecipeService(db);
      inventory = new InventoryService(db, recipes);
      receiving = new ReceivingService(db);
      costs = new InventoryCostService(db);
    });
    afterAll(async () => {
      const venueId = { in: [venueA, venueB] };
      await db.menuConsumptionComponent.deleteMany({ where: { venueId } });
      await db.menuConsumptionRecipe.deleteMany({ where: { venueId } });
      await db.stockMovement.deleteMany({ where: { venueId } });
      await db.receiving.deleteMany({ where: { venueId } });
      await db.supplierProduct.deleteMany({ where: { venueId } });
      await db.stockItemPurchaseUnit.deleteMany({ where: { venueId } });
      await db.stockItem.deleteMany({ where: { venueId } });
      await db.supplier.deleteMany({ where: { venueId } });
      await db.menuItem.deleteMany({ where: { venueId } });
      await db.menuCategory.deleteMany({ where: { venueId } });
      await db.auditEventLog.deleteMany({ where: { venueId } });
      await db.setting.deleteMany({ where: { venueId } });
      await db.venue.deleteMany({ where: { id: venueId } });
      await db.organization.delete({ where: { id: org } });
      await db.$disconnect();
    });
    const stock = (name: string, baseUnit = 'kg', classification = 'FOOD') =>
      inventory.createStockItem(a, { name, baseUnit, classification });
    async function purchase(
      item: { id: string; baseUnit: string },
      quantity: string,
      price: string,
      day = '2026-09-06',
      supplierId?: string,
      enteredUnit?: string,
    ) {
      supplierId ??= (await inventory.createSupplier(a, { name: 'Market' })).id;
      const draft = await receiving.createDraft(a, {
        supplierId,
        documentDate: day,
        businessDate: day,
        lines: [
          {
            stockItemId: item.id,
            enteredQuantity: quantity,
            enteredUnit: enteredUnit ?? item.baseUnit,
            unitPurchaseCost: price,
          },
        ],
      });
      return receiving.post(a, draft.id);
    }
    async function menu(name: string, group: string, tenant = a) {
      const cat = await db.menuCategory.create({
        data: {
          venueId: tenant.venueId,
          slug: randomUUID(),
          nameKa: group,
          nameEn: group,
        },
      });
      return db.menuItem.create({
        data: {
          venueId: tenant.venueId,
          categoryId: cat.id,
          nameKa: name,
          nameEn: name,
          price: 2.5,
        },
      });
    }

    it('persists classification and projects it after reconnect; validates classification', async () => {
      const beef = await stock('ხორცი');
      const borjomi = await stock('ბორჯომი', 'piece', 'BEVERAGE');
      await db.$disconnect();
      await db.$connect();
      const catalog = await inventory.getCatalog(a);
      expect(
        catalog.stockItems.find((row) => row.id === beef.id)?.classification,
      ).toBe('FOOD');
      expect(
        catalog.stockItems.find((row) => row.id === borjomi.id)?.classification,
      ).toBe('BEVERAGE');
      await expect(
        inventory.createStockItem(a, {
          name: 'bad',
          baseUnit: 'kg',
          classification: 'GUESS',
        }),
      ).rejects.toThrow();
    });

    it('links two products, multiple suppliers, optional email, and preserves receiving after unlink/rename', async () => {
      const supplier = await inventory.createSupplier(a, { name: 'Borjomi' });
      const market = await inventory.createSupplier(a, {
        name: 'ხორცი (ბაზარი)',
      });
      expect(supplier.email).toBeNull();
      const borjomi = await inventory.createStockItem(a, {
        name: 'ბორჯომი',
        baseUnit: 'piece',
        classification: 'BEVERAGE',
        supplierIds: [supplier.id, market.id],
      });
      const bakuriani = await stock('ბაკურიანი', 'piece', 'BEVERAGE');
      await inventory.setSupplierProduct(a, supplier.id, bakuriani.id, true);
      await inventory.setSupplierProduct(a, supplier.id, bakuriani.id, true);
      expect(
        (await inventory.supplierDetail(a, supplier.id)).products,
      ).toHaveLength(2);
      expect(
        (await inventory.listStockItems(a)).find((row) => row.id === borjomi.id)
          ?.supplierIds,
      ).toHaveLength(2);
      const posted = await purchase(
        borjomi,
        '10',
        '1.2',
        '2026-09-06',
        supplier.id,
      );
      const original = await receiving.detail(a, posted.id);
      await inventory.setSupplierProduct(a, supplier.id, borjomi.id, false);
      await inventory.updateSupplier(a, supplier.id, {
        name: 'New company name',
      });
      expect(await receiving.detail(a, posted.id)).toEqual(original);
      expect(
        (await inventory.supplierDetail(a, supplier.id)).recentReceivings[0].id,
      ).toBe(posted.id);
      expect(
        await db.auditEventLog.count({
          where: {
            venueId: a.venueId,
            action: 'SUPPLIER_ITEM_LINKED',
            entityId: supplier.id,
          },
        }),
      ).toBe(1);
      await inventory.updateStockItem(a, borjomi.id, { supplierIds: [] });
      expect((await inventory.getStockItem(a, borjomi.id)).supplierIds).toEqual(
        [],
      );
    });

    it('blocks cross-Venue supplier links, database links, purchase costs and recipe costs', async () => {
      const local = await stock('Local');
      const foreign = await inventory.createStockItem(b, {
        name: 'Foreign',
        baseUnit: 'kg',
      });
      const sa = await inventory.createSupplier(a, { name: 'A' });
      const sb = await inventory.createSupplier(b, { name: 'B' });
      await expect(
        inventory.setSupplierProduct(a, sb.id, local.id, true),
      ).rejects.toThrow('not found');
      await expect(
        inventory.setSupplierProduct(a, sa.id, foreign.id, true),
      ).rejects.toThrow('not found');
      await expect(
        inventory.updateStockItem(a, local.id, { supplierIds: [sb.id] }),
      ).rejects.toThrow('not found');
      await expect(
        inventory.createStockItem(a, {
          name: 'Invalid supplier',
          baseUnit: 'kg',
          supplierIds: [sb.id],
        }),
      ).rejects.toThrow('not found');
      await expect(
        db.supplierProduct.create({
          data: {
            venueId: a.venueId,
            supplierId: sb.id,
            stockItemId: local.id,
          },
        }),
      ).rejects.toThrow();
      await expect(
        db.supplierProduct.create({
          data: {
            venueId: a.venueId,
            supplierId: sa.id,
            stockItemId: foreign.id,
          },
        }),
      ).rejects.toThrow();
      await expect(costs.stockItem(a, foreign.id)).rejects.toThrow('not found');
      const foreignMenu = await menu('Foreign dish', 'Food', b);
      await expect(recipes.detail(a, foreignMenu.id)).rejects.toThrow(
        'not found',
      );
      await expect(inventory.supplierDetail(a, sb.id)).rejects.toThrow(
        'not found',
      );
    });

    it('uses the synced business day independently from invoice date and supports repeated receipts', async () => {
      const item = await stock('Daily');
      const supplier = await inventory.createSupplier(a, {
        name: 'Daily market',
      });
      await db.setting.create({
        data: {
          venueId: a.venueId,
          key: 'currentBusinessDate',
          value: '2026-09-05',
        },
      });
      const draft = () =>
        receiving.createDraft(a, {
          supplierId: supplier.id,
          documentDate: '2026-09-06',
          lines: [
            {
              stockItemId: item.id,
              enteredQuantity: '1',
              unitPurchaseCost: '18',
            },
          ],
        });
      const one = await draft(),
        two = await draft();
      expect(one.businessDate).toBe('2026-09-05');
      expect(two.businessDate).toBe('2026-09-05');
      const posted = await receiving.post(a, one.id);
      expect(posted.movements[0].businessDate).toBe('2026-09-05');
      await db.setting.update({
        where: {
          venueId_key: { venueId: a.venueId, key: 'currentBusinessDate' },
        },
        data: { value: '2026-09-06' },
      });
      expect((await receiving.detail(a, one.id)).businessDate).toBe(
        '2026-09-05',
      );
      const page = await receiving.list(a, {
        from: '2026-09-05',
        to: '2026-09-05',
        supplierId: supplier.id,
      });
      expect(page.receivings).toHaveLength(2);
      expect((await receiving.detail(a, one.id)).documentDate).toBe(
        '2026-09-06',
      );
    });

    it('weights exact frozen value/quantity, preserves daily prices and excludes cancellation/drafts', async () => {
      const item = await stock('Weighted');
      const first = await purchase(item, '10', '10', '2026-09-05');
      const second = await purchase(item, '20', '13', '2026-09-06');
      expect((await costs.stockItem(a, item.id)).weightedUnitCost).toBe(
        '12.000000',
      );
      expect((await costs.stockItem(a, item.id)).lastPurchaseUnitCost).toBe(
        '13.000000',
      );
      expect(
        (await receiving.detail(a, first.id)).lines[0].unitPurchaseCost,
      ).toBe('10.0000');
      await receiving.createDraft(a, {
        supplierId: first.supplierId,
        documentDate: '2026-09-07',
        lines: [
          {
            stockItemId: item.id,
            enteredQuantity: '100',
            unitPurchaseCost: '999',
          },
        ],
      });
      expect((await costs.stockItem(a, item.id)).weightedUnitCost).toBe(
        '12.000000',
      );
      await receiving.cancel(a, second.id, 'Incorrect purchase');
      await receiving.cancel(a, second.id, 'Retry');
      expect((await costs.stockItem(a, item.id)).weightedUnitCost).toBe(
        '10.000000',
      );
      await receiving.cancel(a, first.id, 'Returned');
      expect(await costs.stockItem(a, item.id)).toMatchObject({
        status: 'NO_PURCHASE_HISTORY',
        weightedUnitCost: null,
      });
    });

    it('costs food components exactly without intermediate unit-cost rounding', async () => {
      const items = await Promise.all(
        ['Beef', 'Flour', 'Onion', 'Greens'].map((name) => stock(name)),
      );
      for (let i = 0; i < items.length; i++)
        await purchase(items[i], '1', ['18.5', '2', '1.5', '6'][i]);
      const khinkali = await menu('ხინკალი', 'კერძები');
      await recipes.save(a, {
        menuItemId: khinkali.id,
        components: items.map((item, i) => ({
          stockItemId: item.id,
          quantity: ['35', '25', '8', '3'][i],
          unit: 'g',
        })),
      });
      const detail = await recipes.detail(a, khinkali.id);
      expect(detail.currentCost).toMatchObject({
        status: 'AVAILABLE',
        total: '0.73',
        totalExact: '0.727500000000',
      });
      expect(detail.currentCost.components.map((c) => c.cost)).toEqual([
        '0.647500',
        '0.050000',
        '0.012000',
        '0.018000',
      ]);
      await expect(
        inventory.updateStockItem(a, items[0].id, { baseUnit: 'g' }),
      ).rejects.toThrow('base unit');
      const fractional = await stock('Fractional');
      await purchase(fractional, '3', '0.3333'); // frozen total is exactly 1.00
      const dish = await menu('Three units', 'Food');
      await recipes.save(a, {
        menuItemId: dish.id,
        components: [{ stockItemId: fractional.id, quantity: '3', unit: 'kg' }],
      });
      expect((await recipes.detail(a, dish.id)).currentCost).toMatchObject({
        total: '1.00',
        totalExact: '1.000000000000',
      });
    });

    it('costs packaged drinks, item-specific kegs and half-litre pours exactly', async () => {
      const bottle = await inventory.createStockItem(a, {
        name: 'Borjomi',
        baseUnit: 'piece',
        classification: 'BEVERAGE',
        purchaseUnits: [{ unit: 'pack', baseUnitMultiplier: '10' }],
      });
      const posted = await purchase(
        bottle,
        '10',
        '12',
        '2026-09-06',
        undefined,
        'pack',
      );
      expect(posted.lines[0]).toMatchObject({
        baseQuantity: '100.000',
        lineTotal: '120.00',
      });
      const drink = await menu('Borjomi', 'სასმელები');
      await recipes.save(a, {
        menuItemId: drink.id,
        components: [{ stockItemId: bottle.id, quantity: '1', unit: 'piece' }],
      });
      expect((await recipes.detail(a, drink.id)).currentCost).toMatchObject({
        total: '1.20',
      });
      const draft = await inventory.createStockItem(a, {
        name: 'Draft',
        baseUnit: 'L',
        classification: 'BEVERAGE',
        purchaseUnits: [{ unit: 'keg', baseUnitMultiplier: '30' }],
      });
      await purchase(draft, '1', '180', '2026-09-06', undefined, 'keg');
      expect((await costs.stockItem(a, draft.id)).weightedUnitCost).toBe(
        '6.000000',
      );
      const pour = await menu('Beer 0.5L', 'Beer');
      await recipes.save(a, {
        menuItemId: pour.id,
        components: [{ stockItemId: draft.id, quantity: '0.5', unit: 'L' }],
      });
      expect((await recipes.detail(a, pour.id)).currentCost).toMatchObject({
        total: '3.00',
      });
      expect(
        (await inventory.getStockItem(a, draft.id)).recipeUnits,
      ).not.toContain('keg');
      const legacyCatalog = await inventory.getCatalog(a, 3);
      expect(
        legacyCatalog.stockItems.find((row) => row.id === draft.id)
          ?.purchaseUnits,
      ).toEqual([]);
      expect(
        legacyCatalog.recipes.find((row) => row.menuItemId === pour.id),
      ).toBeDefined();
      expect(
        (await inventory.getCatalog(a, 4)).stockItems.find(
          (row) => row.id === draft.id,
        )?.purchaseUnits[0].unit,
      ).toBe('keg');
    });

    it('reports full business-day purchases independently of the receipt page', async () => {
      const item = await stock('Daily totals');
      for (let i = 0; i < 3; i++) await purchase(item, '1', '2', '2026-08-31');
      const page = await receiving.list(a, {
        from: '2026-08-31',
        to: '2026-08-31',
        take: 1,
      });
      expect(page.receivings).toHaveLength(1);
      expect(page.nextCursor).not.toBeNull();
      expect(page.businessDays).toEqual([
        {
          businessDate: '2026-08-31',
          status: 'POSTED',
          count: 3,
          total: '6.00',
        },
      ]);
      expect(
        (await receiving.list(b, { from: '2026-08-31', to: '2026-08-31' }))
          .businessDays,
      ).toEqual([]);
    });

    it('never makes missing component costs zero or guesses ambiguous menu categories', async () => {
      const missing = await stock('No purchases');
      const dish = await menu('Unknown cost', 'Food');
      const saved = await recipes.save(a, {
        menuItemId: dish.id,
        components: [{ stockItemId: missing.id, quantity: '1', unit: 'kg' }],
      });
      expect((await recipes.detail(a, dish.id)).currentCost).toMatchObject({
        status: 'MISSING_COMPONENT_COST',
        total: null,
      });
      await recipes.disable(a, saved.id);
      expect((await recipes.detail(a, dish.id)).currentCost).toMatchObject({
        status: 'NO_ACTIVE_RECIPE',
        total: null,
      });
      expect(menuGroup(['სასმელები'])).toBe('BEVERAGE');
      expect(menuGroup(['კერძები'])).toBe('FOOD');
      expect(menuGroup(['Specials'])).toBe('OTHER');
    });
  },
);
