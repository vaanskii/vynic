import { randomUUID } from 'node:crypto';
jest.mock('uuid', () => ({ v4: () => randomUUID() }));
import { Prisma } from '@prisma/client';
import { inventoryPhase8Fixture } from '../../test/inventory-phase8.fixture';
import { InventoryCostService } from './inventory-cost.service';
import { presentMovement } from './receiving.service';
import { SupplierPayments } from './supplier-payments';

const url = process.env.INV8_TEST_DATABASE_URL;
(url ? describe : describe.skip)('INV-02/04 real HTTP and PostgreSQL', () => {
  let f: Awaited<ReturnType<typeof inventoryPhase8Fixture>>;
  beforeAll(async () => {
    f = await inventoryPhase8Fixture(url!);
  }, 30000);
  afterAll(async () => {
    if (f) await f.close();
  });
  const day = '2026-09-05';
  async function purchase(
    stockItemId: string,
    quantity: string,
    price: string,
    supplierId?: string,
  ) {
    supplierId ??= (
      await f.inventory.createSupplier(f.a.actor, {
        name: 'Synthetic supplier',
      })
    ).id;
    const draft = (await f.receiving.createDraft(f.a.actor, {
      supplierId,
      documentDate: day,
      businessDate: day,
      lines: [
        {
          stockItemId,
          enteredQuantity: quantity,
          enteredUnit: 'kg',
          unitPurchaseCost: price,
        },
      ],
    })) as { id: string };
    await Promise.all([
      f.receiving.post(f.a.actor, draft.id),
      f.receiving.post(f.a.actor, draft.id),
    ]);
    return draft;
  }
  async function stockItem(name: string) {
    return (await f.inventory.createStockItem(f.a.actor, {
      name,
      baseUnit: 'kg',
    })) as { id: string };
  }
  async function mapped() {
    const stock = await stockItem('Synthetic ingredient');
    const cat = await f.db.menuCategory.create({
      data: {
        venueId: f.a.tenant.venueId,
        slug: randomUUID(),
        nameKa: 'Test',
        nameEn: 'Test',
      },
    });
    const menu = await f.db.menuItem.create({
      data: {
        venueId: f.a.tenant.venueId,
        categoryId: cat.id,
        nameKa: 'Test',
        nameEn: 'Test',
        price: 100,
        posMenuItemId: randomUUID(),
      },
    });
    await f.recipes.save(f.a.actor, {
      menuItemId: menu.id,
      components: [{ stockItemId: stock.id, quantity: '1', unit: 'kg' }],
    });
    const recipe = (await f.recipes.projection(f.a.tenant.venueId)).find(
      (r) => r.menuItemId === menu.id,
    )!;
    const payload = {
      posSaleId: randomUUID(),
      closureId: randomUUID(),
      orderId: 53,
      businessDate: day,
      closedAt: day + 'T10:00:00.000Z',
      snapshot: {
        version: 1,
        policy: 'FISCAL_CLOSE',
        lines: [
          {
            lineSeq: 0,
            itemName: 'Test',
            menuItemId: recipe.posMenuItemId,
            soldQuantity: 5,
            status: 'MAPPED',
            recipeId: recipe.recipeId,
            recipeRevision: recipe.revision,
            components: recipe.components.map((c) => ({
              ...c,
              totalBaseQuantity: new Prisma.Decimal(c.baseQuantityPerUnit)
                .times(5)
                .toFixed(6),
            })),
          },
        ],
      },
    };
    return { stock, menu, recipe, payload };
  }
  it('late offline Sale freezes acceptance cost and concurrent restore uses its original value after recipe/price changes', async () => {
    const { stock, menu, payload } = await mapped();
    await purchase(stock.id, '10', '10');
    await purchase(stock.id, '20', '13');
    await Promise.all([
      f.consumption.apply(f.a.tenant, payload),
      f.consumption.apply(f.a.tenant, payload),
    ]);
    const original = await f.db.stockMovement.findFirstOrThrow({
      where: { stockItemId: stock.id, movementType: 'CONSUMPTION' },
    });
    expect(presentMovement(original)).toMatchObject({
      costPerBaseUnit: '12.000000000000',
      inventoryValueDelta: '-60.000000000000',
      valueOrigin: 'CLOUD_ACCEPTANCE',
      businessDate: day,
    });
    expect(original.createdAt.getTime()).toBeGreaterThan(
      Date.parse(payload.closedAt),
    );
    const frozen = presentMovement(original);
    await purchase(stock.id, '5', '50');
    await f.recipes.save(f.a.actor, {
      menuItemId: menu.id,
      components: [{ stockItemId: stock.id, quantity: '2', unit: 'kg' }],
    });
    const restore = {
      ...payload,
      reversedAt: '2026-09-06T10:00:00.000Z',
      restoreBusinessDate: '2026-09-06',
    };
    await Promise.all([
      f.consumption.apply(f.a.tenant, restore),
      f.consumption.apply(f.a.tenant, restore),
    ]);
    await f.consumption.apply(f.a.tenant, payload);
    expect(
      presentMovement(
        await f.db.stockMovement.findUniqueOrThrow({
          where: { id: original.id },
        }),
      ),
    ).toEqual(frozen);
    const reversal = await f.db.stockMovement.findMany({
      where: { reversalOfMovementId: original.id },
    });
    expect(reversal).toHaveLength(1);
    expect(presentMovement(reversal[0])).toMatchObject({
      quantityDeltaBase: '5.000',
      inventoryValueDelta: '60.000000000000',
      valueOrigin: 'FROZEN_ORIGINAL_REVERSAL',
    });
    await expect(
      f.consumption.apply(f.a.tenant, { ...payload, orderId: 54 }),
    ).rejects.toThrow('immutable');
    const stored = await f.db.saleConsumption.findUniqueOrThrow({
      where: {
        venueId_posSaleId: {
          venueId: f.a.tenant.venueId,
          posSaleId: payload.posSaleId,
        },
      },
    });
    expect(
      (await f.get('/mobile/inventory/consumptions/' + stored.id)).body,
    ).toMatchObject({
      reversedAt: restore.reversedAt,
      lines: [
        {
          components: [
            {
              movements: expect.arrayContaining([
                expect.objectContaining({
                  inventoryValueDelta: '-60.000000000000',
                }),
                expect.objectContaining({
                  valueOrigin: 'FROZEN_ORIGINAL_REVERSAL',
                }),
              ]) as unknown,
            },
          ],
        },
      ],
    });
    expect(
      (await f.get('/mobile/inventory/consumptions/' + stored.id, f.b.token))
        .status,
    ).toBe(404);
  });
  it('unknown/negative cost remains provisional; reconstructed current basis is explicit', async () => {
    const { stock, menu, payload } = await mapped();
    expect(
      (await f.inventory.listStockItems(f.a.tenant, undefined, true)).find(
        (r) => r.id === stock.id,
      ),
    ).toMatchObject({
      weightedUnitCost: null,
      costStatus: 'NO_PURCHASE_HISTORY',
    });
    await f.consumption.apply(f.a.tenant, payload);
    const cost = await new InventoryCostService(f.db).stockItem(
      f.a.tenant,
      stock.id,
    );
    expect(cost).toMatchObject({
      status: 'PROVISIONAL',
      weightedUnitCost: null,
      provenance: {
        historicalCloseTimeCogs: false,
        ordering: 'CLOUD_ACCEPTANCE',
      },
    });
    const recipe = await f.db.menuConsumptionRecipe.findFirstOrThrow({
      where: { menuItemId: menu.id },
      include: { components: true },
    });
    expect(
      await new InventoryCostService(f.db).recipe(f.a.tenant, recipe),
    ).toMatchObject({
      status: 'MISSING_COMPONENT_COST',
      components: [{ status: 'PROVISIONAL', cost: null }],
    });
    const s = await stockItem('Reconstructed');
    await purchase(s.id, '10', '10');
    // Isolated legacy-backfill fixture, never a production mutation.
    await f.db.stockMovement.updateMany({
      where: { stockItemId: s.id },
      data: { valuationStatus: 'RECONSTRUCTED' },
    });
    expect(
      await new InventoryCostService(f.db).stockItem(f.a.tenant, s.id),
    ).toMatchObject({ provenance: { includesReconstructedHistory: true } });
    const result = await f.get(
      '/mobile/inventory/stock-items/' + s.id + '/movements',
    );
    expect(result.status).toBe(200);
    expect(result.body).toMatchObject({
      items: [{ valueOrigin: 'RECONSTRUCTED_RECORDED_ORDER' }],
    });
  });

  let firstCursor: string;
  let historyIds: string[];
  it('205 tied same-day records remain complete under retry and newly arriving/backdated Sales', async () => {
    historyIds = Array.from({ length: 205 }, () => randomUUID())
      .sort()
      .reverse();
    await f.db.saleConsumption.createMany({
      data: historyIds.map((id, i) => ({
        id,
        venueId: f.b.tenant.venueId,
        posSaleId: id,
        closureId: id,
        orderId: i + 1,
        businessDate: day,
        closedAt: new Date(day + 'T10:00:00Z'),
        createdAt: new Date(day),
        policy: 'FISCAL_CLOSE',
        snapshot: {},
      })),
    });
    const path =
      '/mobile/inventory/consumptions/page?from=' + day + '&to=' + day;
    const first = await f.get(path, f.b.token);
    expect(first.status).toBe(200);
    const page = first.body as unknown as {
      items: { id: string }[];
      nextCursor: string;
    };
    firstCursor = page.nextCursor;
    expect(page.items.map((r) => r.id)).toEqual(historyIds.slice(0, 50));
    await f.db.saleConsumption.createMany({
      data: [9, 11].map((hour) => ({
        venueId: f.b.tenant.venueId,
        posSaleId: randomUUID(),
        closureId: randomUUID(),
        orderId: hour,
        businessDate: day,
        closedAt: new Date(`${day}T${hour.toString().padStart(2, '0')}:00:00Z`),
        policy: 'FISCAL_CLOSE',
        snapshot: {},
      })),
    });
    const ids = page.items.map((r) => r.id);
    let cursor: string | null = firstCursor;
    while (cursor) {
      const nextPath = path + '&cursor=' + cursor;
      const next = await f.get(nextPath, f.b.token);
      const retry = await f.get(nextPath, f.b.token);
      expect(next.body).toEqual(retry.body);
      expect(next.status).toBe(200);
      const p = next.body as unknown as {
        items: { id: string }[];
        nextCursor: string | null;
      };
      ids.push(...p.items.map((r) => r.id));
      cursor = p.nextCursor;
    }
    expect(ids).toEqual(historyIds);
    expect(new Set(ids).size).toBe(205);
    const old = await f.get('/mobile/inventory/consumptions', f.b.token);
    expect(Array.isArray(old.body)).toBe(true);
    expect(old.body).toHaveLength(100);
  });
  it('rejects malformed, cross-tenant and changed-filter cursors/date ranges without authority from client input', async () => {
    for (const q of [
      'cursor=%%%',
      'from=2026-02-30',
      'from=2026-10-01&to=2026-09-01',
      'limit=101',
      'unmapped=maybe',
    ])
      expect(
        (await f.get('/mobile/inventory/consumptions/page?' + q, f.b.token))
          .status,
      ).toBe(400);
    expect(
      (
        await f.get(
          '/mobile/inventory/consumptions/page?cursor=' + firstCursor,
          f.b.token,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await f.get(
          `/mobile/inventory/consumptions/page?from=${day}&to=${day}&cursor=${firstCursor}`,
          f.a.token,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await f.get(
          '/mobile/inventory/consumptions/page?venueId=' + f.b.tenant.venueId,
        )
      ).body,
    ).not.toMatchObject({
      items: expect.arrayContaining([
        expect.objectContaining({ id: historyIds[0] }),
      ]) as unknown,
    });
    expect(
      (await f.get('/mobile/inventory/consumptions/page', '')).status,
    ).toBe(401);
  });
  it('complete Stock movement pages preserve frozen values, stable ties, tenant and entitlement guards', async () => {
    const stock = await stockItem('History stock');
    // Unknown-cost issues are valid isolated fixtures. Values are trigger-owned.
    const ids = Array.from({ length: 205 }, () => randomUUID())
      .sort()
      .reverse();
    await f.db.stockMovement.createMany({
      data: ids.map((id) => ({
        id,
        venueId: f.a.tenant.venueId,
        stockItemId: stock.id,
        movementType: 'CONSUMPTION',
        quantityDeltaBase: '-1',
        baseUnit: 'kg',
        businessDate: day,
        effectiveAt: new Date(day),
        createdAt: new Date(day),
        actorId: 'synthetic',
        actorName: 'Synthetic',
        source: 'POS',
      })),
    });
    const path = '/mobile/inventory/stock-items/' + stock.id + '/movements';
    const found: string[] = [];
    let cursor: string | null = null;
    do {
      const response = await f.get(path + (cursor ? '?cursor=' + cursor : ''));
      expect(response.status).toBe(200);
      const p = response.body as unknown as {
        items: { id: string }[];
        nextCursor: string | null;
      };
      found.push(...p.items.map((r) => r.id));
      cursor = p.nextCursor;
      if (found.length === 50)
        await f.db.stockMovement.create({
          data: {
            venueId: f.a.tenant.venueId,
            stockItemId: stock.id,
            movementType: 'CONSUMPTION',
            quantityDeltaBase: '-2',
            baseUnit: 'kg',
            businessDate: day,
            effectiveAt: new Date(day),
            actorId: 'synthetic',
            actorName: 'Synthetic',
            source: 'POS',
          },
        });
    } while (cursor);
    expect(found).toEqual(ids);
    expect((await f.get(path, f.b.token)).status).toBe(404);
    const profitability = await f.db.feature.findUniqueOrThrow({
      where: { key: 'PROFITABILITY' },
    });
    await f.db.venueFeatureOverride.updateMany({
      where: { venueId: f.a.tenant.venueId, featureId: profitability.id },
      data: { effect: 'DISABLED' },
    });
    const withoutCost = await f.get(path);
    expect(withoutCost.status).toBe(200);
    expect(JSON.stringify(withoutCost.body)).not.toMatch(
      /inventoryValueDelta|costPerBaseUnit|valuationSequence|valueOrigin/,
    );
    await f.db.venueFeatureOverride.updateMany({
      where: { venueId: f.a.tenant.venueId, featureId: profitability.id },
      data: { effect: 'ENABLED' },
    });
    const inv = await f.db.feature.findUniqueOrThrow({
      where: { key: 'INVENTORY' },
    });
    await f.db.venueFeatureOverride.updateMany({
      where: { venueId: f.a.tenant.venueId, featureId: inv.id },
      data: { effect: 'DISABLED' },
    });
    expect((await f.get(path)).status).toBe(403);
    await f.db.venueFeatureOverride.updateMany({
      where: { venueId: f.a.tenant.venueId, featureId: inv.id },
      data: { effect: 'ENABLED' },
    });
  });
  it('revenue, close payments, supplier debt and stock value reconcile without claiming realized profit/cashflow', async () => {
    await f.db.setting.create({
      data: {
        venueId: f.a.tenant.venueId,
        key: 'currentBusinessDate',
        value: day,
      },
    });
    const stock = await stockItem('Financial stock');
    const receipt = await purchase(stock.id, '10', '80');
    const payments = new SupplierPayments(f.db);
    const input = {
      requestId: randomUUID(),
      amount: '300.00',
      paymentDate: day,
      businessDate: day,
      method: 'cash',
    };
    const result = await Promise.all([
      payments.record(f.a.actor, receipt.id, input),
      payments.record(f.a.actor, receipt.id, input),
    ]);
    expect(result[0]).toEqual(result[1]);
    const instant = new Date(day);
    await f.db.cloudSale.create({
      data: {
        venueId: f.a.tenant.venueId,
        posSaleId: randomUUID(),
        posOrderId: 1,
        businessDate: day,
        createdAt: instant,
        closedAt: instant,
        gross: '100',
        subtotal: '100',
        serviceFee: '0',
        discount: '0',
        manualAdjustment: '0',
        advanceApplied: '20',
        amountDueNow: '80',
        collectedNow: '80',
        paymentMethod: 'cash',
        isFiscal: true,
        createdBy: 'Synthetic',
        tableNumbers: [],
        floor: '1',
        sourceRevision: 1,
        sourceUpdatedAt: instant,
        payments: {
          create: [
            { method: 'cash', amount: '80' },
            { method: 'advance', amount: '20' },
          ],
        },
      },
    });
    await f.db.saleLedgerDay.create({
      data: {
        venueId: f.a.tenant.venueId,
        businessDate: day,
        completeness: 'COMPLETE',
        reconciliation: 'MATCHED',
        expectedSaleCount: 1,
        expectedRevenue: '100',
        ledgerSaleCount: 1,
        ledgerRevenue: '100',
        declaredCompleteAt: instant,
        lastSyncedAt: instant,
      },
    });
    const financial = await f.dashboard.getFinancials(f.a.tenant);
    expect(financial).toMatchObject({
      revenueExact: '100.00',
      totalOutflows: '300.00',
      differenceExact: '-200.00',
      metricDefinitions: {
        realizedProfitAvailable: false,
        completeCashflowAvailable: false,
      },
    });
    expect(
      await f.ledger.getSummary(f.a.tenant, { from: day, to: day }),
    ).toMatchObject({
      revenue: '100.00',
      cashCollected: '80.00',
      advanceApplied: '20.00',
    });
    expect(
      await new InventoryCostService(f.db).stockItem(f.a.tenant, stock.id),
    ).toMatchObject({ inventoryValue: '800.000000000000' });
    expect(await f.receiving.detail(f.a.tenant, receipt.id)).toMatchObject({
      paid: '300.00',
      remaining: '500.00',
    });
    const payment = await f.db.supplierPayment.findUniqueOrThrow({
      where: {
        venueId_requestId: {
          venueId: f.a.tenant.venueId,
          requestId: input.requestId,
        },
      },
    });
    const reversal = {
      paymentDate: day,
      businessDate: day,
      notes: 'Synthetic reversal',
    };
    await Promise.all([
      payments.reverse(f.a.actor, receipt.id, payment.id, reversal),
      payments.reverse(f.a.actor, receipt.id, payment.id, reversal),
    ]);
    expect(
      await f.db.supplierPayment.count({ where: { reversalOfId: payment.id } }),
    ).toBe(1);
    expect(await f.receiving.detail(f.a.tenant, receipt.id)).toMatchObject({
      paid: '0.00',
      remaining: '800.00',
    });
  });
  it('current Staff role and active status gate history even with an existing token', async () => {
    await f.db.staff.update({
      where: { id: f.b.actor.staffId },
      data: { role: 'WAITER' },
    });
    expect(
      (await f.get('/mobile/inventory/consumptions/page', f.b.token)).status,
    ).toBe(401);
    await f.db.staff.update({
      where: { id: f.b.actor.staffId },
      data: { role: 'MANAGER', isActive: false },
    });
    expect(
      (await f.get('/mobile/inventory/consumptions/page', f.b.token)).status,
    ).toBe(401);
  });
});
