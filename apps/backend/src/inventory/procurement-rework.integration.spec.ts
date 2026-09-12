import { randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { InventoryService } from './inventory.service';
import { ReceivingService } from './receiving.service';
import { RecipeService } from './recipe.service';
import { SaleConsumptionService } from './sale-consumption.service';
import { SupplierPayments } from './supplier-payments';
import { procurementSummary } from './procurement-summary';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)('Restaurant procurement end to end', () => {
  let db: PrismaService,
    inventory: InventoryService,
    receiving: ReceivingService,
    recipes: RecipeService,
    sales: SaleConsumptionService,
    payments: SupplierPayments;
  const organizationId = randomUUID(),
    a = {
      organizationId,
      venueId: randomUUID(),
      staffId: 'manager',
      username: 'Manager',
    },
    b = { ...a, venueId: randomUUID() };
  let sequence = 0;
  beforeAll(async () => {
    if (!url?.includes('procurement_'))
      throw new Error('Disposable procurement database required');
    db = new PrismaService({ datasourceUrl: url });
    await db.$connect();
    await db.organization.create({
      data: {
        id: organizationId,
        name: 'Procurement proof',
        venues: {
          create: [a, b].map((t) => ({
            id: t.venueId,
            name: 'Restaurant',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          })),
        },
      },
    });
    recipes = new RecipeService(db);
    inventory = new InventoryService(db, recipes);
    receiving = new ReceivingService(db);
    sales = new SaleConsumptionService(db);
    payments = new SupplierPayments(db);
  });
  afterAll(async () => {
    await db?.$disconnect();
  }); // Disposable database is dropped as a whole after verification.
  async function menu(name: string, tenant = a) {
    const category = await db.menuCategory.create({
      data: {
        venueId: tenant.venueId,
        slug: randomUUID(),
        nameKa: 'სასმელები',
        nameEn: 'Drinks',
      },
    });
    return db.menuItem.create({
      data: {
        venueId: tenant.venueId,
        categoryId: category.id,
        nameKa: name,
        nameEn: name,
        price: 5,
        posMenuItemId: randomUUID(),
      },
    });
  }
  async function receive(
    supplierId: string,
    stockItemId: string,
    quantity: string,
    unit: string,
    value: string,
  ) {
    const draft = await receiving.createDraft(a, {
      supplierId,
      businessDate: '2026-09-05',
      lines: [
        {
          stockItemId,
          enteredQuantity: quantity,
          enteredUnit: unit,
          lineTotal: value,
        },
      ],
    });
    expect(draft.status).toBe('DRAFT');
    await Promise.all([
      receiving.post(a, draft.id),
      receiving.post(a, draft.id),
    ]);
    return draft.id;
  }
  async function sale(menuId: string, count: number) {
    const recipe = (await recipes.projection(a.venueId)).find(
      (r) => r.menuItemId === menuId,
    )!;
    const n = ++sequence;
    const body = {
      posSaleId: randomUUID(),
      closureId: randomUUID(),
      orderId: n,
      businessDate: '2026-09-05',
      closedAt: '2026-09-05T10:00:00Z',
      reversedAt: null as string | null,
      snapshot: {
        version: 1,
        policy: 'FISCAL_CLOSE',
        lines: [
          {
            lineSeq: 0,
            itemName: recipe.menuItemName,
            menuItemId: recipe.posMenuItemId,
            variantId: recipe.posMenuVariantId,
            soldQuantity: count,
            status: 'MAPPED',
            reason: null,
            recipeId: recipe.recipeId,
            recipeRevision: recipe.revision,
            components: recipe.components.map((c) => ({
              ...c,
              totalBaseQuantity: new Prisma.Decimal(c.baseQuantityPerUnit)
                .times(count)
                .toFixed(6),
            })),
          },
        ],
      },
    };
    await Promise.all([sales.apply(a, body), sales.apply(a, body)]);
    return body;
  }
  async function balance(id: string) {
    return inventory.getStockItem(a, id);
  }
  function pay(amount: string) {
    return {
      requestId: randomUUID(),
      amount,
      paymentDate: '2026-09-05',
      businessDate: '2026-09-05',
      method: 'cash',
    };
  }
  it('Borjomi and Bakuriani: atomic direct mapping, 10 packs = 100, partial debt, close and exact restore/reclose', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Borjomi' }),
      borjomi = await menu('ბორჯომი'),
      bakuriani = await menu('ბაკურიანი');
    const input = {
      mode: 'menu',
      menuItemId: borjomi.id,
      purchaseUnits: [{ unit: 'pack', baseUnitMultiplier: '10' }],
    };
    const [first, retry] = await Promise.all([
      inventory.addSuppliedItem(a, supplier.id, input),
      inventory.addSuppliedItem(a, supplier.id, input),
    ]);
    expect(first.stockItemId).toBe(retry.stockItemId);
    const second = await inventory.addSuppliedItem(a, supplier.id, {
      ...input,
      menuItemId: bakuriani.id,
    });
    const receipt = await receive(
      supplier.id,
      first.stockItemId,
      '10',
      'pack',
      '120',
    );
    await receive(supplier.id, second.stockItemId, '10', 'pack', '80');
    expect((await balance(first.stockItemId)).currentStock).toBe('100.000');
    expect((await balance(second.stockItemId)).currentStock).toBe('100.000');
    expect((await receiving.detail(a, receipt)).remaining).toBe('120.00');
    const payment = pay('50');
    await Promise.all([
      payments.record(a, receipt, payment),
      payments.record(a, receipt, payment),
    ]);
    expect(await receiving.detail(a, receipt)).toMatchObject({
      paid: '50.00',
      remaining: '70.00',
      paymentStatus: 'PARTIALLY_PAID',
    });
    await expect(
      payments.record(a, receipt, { ...payment, amount: '51' }),
    ).rejects.toThrow();
    await expect(payments.record(a, receipt, pay('71'))).rejects.toThrow();
    await expect(receiving.cancel(a, receipt)).rejects.toThrow();
    const close = await sale(borjomi.id, 4);
    expect((await balance(first.stockItemId)).currentStock).toBe('96.000');
    const movement = await db.stockMovement.findFirstOrThrow({
      where: { stockItemId: first.stockItemId, movementType: 'CONSUMPTION' },
    });
    expect(movement.costPerBaseUnit?.toFixed(2)).toBe('1.20');
    expect(movement.inventoryValueDelta?.toFixed(2)).toBe('-4.80');
    close.reversedAt = '2026-09-05T11:00:00Z';
    await Promise.all([sales.apply(a, close), sales.apply(a, close)]);
    expect((await balance(first.stockItemId)).currentStock).toBe('100.000');
    expect((await balance(first.stockItemId)).currentCost.inventoryValue).toBe(
      '120.000000000000',
    );
    await sale(borjomi.id, 4);
    expect((await balance(first.stockItemId)).currentStock).toBe('96.000');
    await payments.record(a, receipt, pay('70'));
    expect((await receiving.detail(a, receipt)).paymentStatus).toBe('PAID');
  });
  it('Beef 20 kg / 800 GEL, 100 khinkali consume 3.5 kg; new price uses remaining stock', async () => {
    const supplier = await inventory.createSupplier(a, {
      name: 'ხორცი (ბაზარი)',
    });
    const beef = await inventory.addSuppliedItem(a, supplier.id, {
      mode: 'ingredient',
      name: 'Beef',
      baseUnit: 'kg',
    });
    await receive(supplier.id, beef.stockItemId, '20', 'kg', '800');
    expect((await balance(beef.stockItemId)).currentCost.weightedUnitCost).toBe(
      '40.000000',
    );
    const khinkali = await menu('ხინკალი');
    await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [
        { stockItemId: beef.stockItemId, quantity: '35', unit: 'g' },
      ],
    });
    await sale(khinkali.id, 100);
    expect((await balance(beef.stockItemId)).currentStock).toBe('16.500');
    expect((await balance(beef.stockItemId)).currentCost.inventoryValue).toBe(
      '660.000000000000',
    );
    await receive(supplier.id, beef.stockItemId, '15', 'kg', '570');
    expect((await balance(beef.stockItemId)).currentCost.weightedUnitCost).toBe(
      '39.047619',
    );
    const previous = await db.stockMovement.findFirstOrThrow({
      where: { stockItemId: beef.stockItemId, movementType: 'CONSUMPTION' },
    });
    expect(previous.inventoryValueDelta?.toFixed(2)).toBe('-140.00');
  });
  it('moving average 10 @ 10 + 20 @ 13 = 12; consume 5 leaves 25 / 300', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Weighted' }),
      stock = await inventory.addSuppliedItem(a, supplier.id, {
        mode: 'ingredient',
        name: 'Average proof',
        baseUnit: 'kg',
      });
    await receive(supplier.id, stock.stockItemId, '10', 'kg', '100');
    await receive(supplier.id, stock.stockItemId, '20', 'kg', '260');
    const dish = await menu('Dish');
    await recipes.save(a, {
      menuItemId: dish.id,
      components: [
        { stockItemId: stock.stockItemId, quantity: '1', unit: 'kg' },
      ],
    });
    await sale(dish.id, 5);
    expect((await balance(stock.stockItemId)).currentCost).toMatchObject({
      currentQuantity: '25.000000',
      weightedUnitCost: '12.000000',
      inventoryValue: '300.000000000000',
    });
  });
  it('draft beer uses L: 2 kegs x 30, sell 0.5 L', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Brewery' }),
      stock = await inventory.addSuppliedItem(a, supplier.id, {
        mode: 'bulk',
        name: 'Draft beer',
        purchaseUnits: [{ unit: 'keg', baseUnitMultiplier: '30' }],
      });
    await receive(supplier.id, stock.stockItemId, '2', 'keg', '240');
    const beer = await menu('Beer 0.5L');
    await recipes.save(a, {
      menuItemId: beer.id,
      components: [
        { stockItemId: stock.stockItemId, quantity: '0.500', unit: 'L' },
      ],
    });
    await sale(beer.id, 1);
    expect((await balance(stock.stockItemId)).currentStock).toBe('59.500');
    expect((await balance(stock.stockItemId)).currentCost.inventoryValue).toBe(
      '238.000000000000',
    );
  });
  it('unpaid cancellation reverses stock; explicit payment reversal preserves history and permits cancellation', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Returns' }),
      stock = await inventory.addSuppliedItem(a, supplier.id, {
        mode: 'ingredient',
        name: 'Return stock',
        baseUnit: 'kg',
      });
    const unpaid = await receive(
      supplier.id,
      stock.stockItemId,
      '1',
      'kg',
      '10',
    );
    await receiving.cancel(a, unpaid);
    expect((await balance(stock.stockItemId)).currentStock).toBe('0.000');
    const paid = await receive(supplier.id, stock.stockItemId, '1', 'kg', '10');
    await payments.record(a, paid, pay('10'));
    await expect(receiving.cancel(a, paid)).rejects.toThrow();
    const p = await db.supplierPayment.findFirstOrThrow({
        where: { receivingId: paid },
      }),
      input = { paymentDate: '2026-09-05', notes: 'Supplier returned cash' };
    await Promise.all([
      payments.reverse(a, paid, p.id, input),
      payments.reverse(a, paid, p.id, input),
    ]);
    await receiving.cancel(a, paid);
    expect(
      await db.supplierPayment.count({ where: { receivingId: paid } }),
    ).toBe(2);
    expect((await balance(stock.stockItemId)).currentCost.inventoryValue).toBe(
      '0.000000000000',
    );
  });
  it('server Venue blocks foreign Menu, stock, recipe, payment and debt access', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Tenant A' }),
      foreignMenu = await menu('Foreign', b),
      foreignStock = await inventory.createStockItem(b, {
        name: 'Foreign',
        baseUnit: 'kg',
      });
    await expect(
      inventory.addSuppliedItem(a, supplier.id, {
        mode: 'menu',
        menuItemId: foreignMenu.id,
      }),
    ).rejects.toThrow();
    await expect(
      inventory.addSuppliedItem(a, supplier.id, {
        mode: 'existing',
        stockItemId: foreignStock.id,
      }),
    ).rejects.toThrow();
    await expect(
      receiving.createDraft(a, {
        supplierId: supplier.id,
        lines: [
          {
            stockItemId: foreignStock.id,
            enteredQuantity: '1',
            lineTotal: '5',
          },
        ],
      }),
    ).rejects.toThrow();
    const ownMenu = await menu('Own');
    await expect(
      recipes.save(a, {
        menuItemId: ownMenu.id,
        components: [
          { stockItemId: foreignStock.id, quantity: '1', unit: 'kg' },
        ],
      }),
    ).rejects.toThrow();
    const receipt = await db.receiving.findFirstOrThrow({
      where: { venueId: a.venueId, status: 'POSTED' },
    });
    await expect(payments.record(b, receipt.id, pay('1'))).rejects.toThrow();
    expect((await payments.list(b, supplier.id)).receivings).toEqual([]);
  });
  it('catalog and receipt creation retries preserve identity; base-unit pricing remains exact', async () => {
    const supplier = await inventory.createSupplier(a, {
      name: 'Retry supplier',
    });
    const itemInput = {
      requestId: randomUUID(),
      mode: 'ingredient',
      name: 'Retry goods',
      baseUnit: 'kg',
    };
    const [one, two] = await Promise.all([
      inventory.addSuppliedItem(a, supplier.id, itemInput),
      inventory.addSuppliedItem(a, supplier.id, itemInput),
    ]);
    expect(one.stockItemId).toBe(two.stockItemId);
    await expect(
      inventory.addSuppliedItem(a, supplier.id, {
        ...itemInput,
        name: 'Changed',
      }),
    ).rejects.toThrow();
    const input = {
      requestId: randomUUID(),
      supplierId: supplier.id,
      businessDate: '2026-09-05',
      lines: [
        {
          stockItemId: one.stockItemId,
          enteredQuantity: '20000',
          enteredUnit: 'g',
          priceBasis: 'base',
          unitPurchaseCost: '40',
        },
      ],
    };
    const [r1, r2] = await Promise.all([
      receiving.createDraft(a, input),
      receiving.createDraft(a, input),
    ]);
    expect(r1.id).toBe(r2.id);
    expect(r1.documentTotal).toBe('800.00');
    expect(r1.lines[0].baseQuantity).toBe('20.000');
    await receiving.post(a, r1.id);
    expect((await receiving.createDraft(a, input)).status).toBe('POSTED');
    await expect(
      receiving.createDraft(a, { ...input, notes: 'Different' }),
    ).rejects.toThrow();
  });
  it('financial summary distinguishes purchase and cash dates, no receipt-created payment, unknown legacy is explicit', async () => {
    const supplier = await inventory.createSupplier(a, { name: 'Pay later' }),
      stock = await inventory.addSuppliedItem(a, supplier.id, {
        mode: 'ingredient',
        name: 'Later stock',
        baseUnit: 'kg',
      });
    const id = await receive(supplier.id, stock.stockItemId, '1', 'kg', '800');
    const before = await procurementSummary(
      db,
      a,
      new Date('2026-09-05T12:00:00Z'),
    );
    await payments.record(a, id, pay('300'));
    const after = await procurementSummary(
      db,
      a,
      new Date('2026-09-05T12:00:00Z'),
    );
    expect(after.businessDay.total).toBe(before.businessDay.total);
    expect(
      new Prisma.Decimal(after.supplierPayments.businessDay.total)
        .minus(before.supplierPayments.businessDay.total)
        .toFixed(2),
    ).toBe('300.00');
    await db.receiving.update({
      where: { id },
      data: { paymentHistoryKnown: false },
    });
    expect((await receiving.detail(a, id)).paymentStatus).toBe('UNVERIFIED');
    await expect(receiving.cancel(a, id)).rejects.toThrow();
    await payments.verifyHistory(a, id, {
      confirmNoUnrecordedPayments: true,
      notes: 'Compared supplier receipts',
    });
    expect((await receiving.detail(a, id)).paymentStatus).toBe(
      'PARTIALLY_PAID',
    );
  });
  it('market source preserves history, shares stock across suppliers and keeps durable payments', async () => {
    const supplierA = await inventory.createSupplier(a, { name: 'Market A' });
    const supplierB = await inventory.createSupplier(a, { name: 'Market B' });
    const ingredient = await inventory.addSuppliedItem(a, supplierA.id, {
      mode: 'ingredient',
      name: 'Shared flour',
      baseUnit: 'kg',
      requestId: randomUUID(),
    });
    await inventory.addSuppliedItem(a, supplierB.id, {
      mode: 'ingredient',
      stockItemId: ingredient.stockItemId,
      baseUnit: 'kg',
    });
    const before = await db.supplier.count({ where: { venueId: a.venueId } });
    const input = {
      requestId: randomUUID(),
      sourceType: 'SELF_PURCHASE',
      sourceLabel: 'ბათუმის ბაზარი',
      documentDate: '2026-09-10',
      businessDate: '2026-09-10',
      lines: [
        {
          stockItemId: ingredient.stockItemId,
          enteredQuantity: '20',
          enteredUnit: 'kg',
          lineTotal: '800',
        },
      ],
    };
    const draft = await receiving.createDraft(a, input);
    expect(draft.sourceType).toBe('SELF_PURCHASE');
    expect(draft.supplierId).toBeNull();
    expect((await receiving.createDraft(a, input)).id).toBe(draft.id);
    const posted = await receiving.post(a, draft.id);
    expect(posted.supplierName).toBe('ბათუმის ბაზარი');
    expect(await db.supplier.count({ where: { venueId: a.venueId } })).toBe(
      before,
    );
    const payment = {
      requestId: randomUUID(),
      amount: '300',
      paymentDate: '2026-09-10',
      businessDate: '2026-09-10',
      method: 'cash',
    };
    await payments.record(a, draft.id, payment);
    await payments.record(a, draft.id, payment);
    expect((await receiving.detail(a, draft.id)).remaining).toBe('500.00');
    await receive(supplierA.id, ingredient.stockItemId, '2', 'kg', '40');
    await receive(supplierB.id, ingredient.stockItemId, '3', 'kg', '40');
    expect(
      (await inventory.getStockItem(a, ingredient.stockItemId)).currentStock,
    ).toBe('25.000');
    await expect(receiving.createDraft(b, input)).rejects.toThrow();
    await expect(
      receiving.createDraft(a, {
        ...input,
        requestId: randomUUID(),
        supplierId: supplierA.id,
      }),
    ).rejects.toThrow();
    await expect(
      receiving.updateDraft(a, draft.id, { ...input, sourceLabel: 'Changed' }),
    ).rejects.toThrow();
    expect((await receiving.detail(a, draft.id)).supplierName).toBe(
      'ბათუმის ბაზარი',
    );
  });

  it('inline ingredient retries keep one identity and reject changed intent', async () => {
    const input = {
      requestId: randomUUID(),
      name: 'Shared cheese',
      baseUnit: 'kg',
    };
    const [first, second] = await Promise.all([
      inventory.createStockItem(a, input),
      inventory.createStockItem(a, input),
    ]);
    expect(first.id).toBe(second.id);
    await expect(
      inventory.createStockItem(a, { ...input, name: 'Other cheese' }),
    ).rejects.toThrow();
    const dishA = await menu('Dish A'),
      dishB = await menu('Dish B');
    for (const dish of [dishA, dishB])
      await recipes.save(a, {
        menuItemId: dish.id,
        yieldQuantity: '1',
        components: [{ stockItemId: first.id, quantity: '25', unit: 'g' }],
      });
    expect((await inventory.getStockItem(a, first.id)).usedBy).toHaveLength(2);
  });
});
