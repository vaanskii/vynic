import { PrismaService } from '../prisma.service';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { InventoryService } from './inventory.service';
import { RecipeService } from './recipe.service';
import { ReceivingService } from './receiving.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * Receiving against real PostgreSQL.
 *
 * These are the claims that only a database can settle: that a transaction
 * either posts a whole document or none of it, that two simultaneous posts
 * cannot double a venue's stock, and that a Venue cannot reach another Venue's
 * suppliers, items, documents or movements.
 */
describeDatabase('Receiving and the stock ledger (PostgreSQL)', () => {
  let prisma: PrismaService;
  let inventory: InventoryService;
  let receiving: ReceivingService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `d0000000-0000-4000-8000-${suffix}`;
  const venueAId = `d1000000-0000-4000-8000-${suffix}`;
  const venueBId = `d2000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const actor = (venueId: string, staffId: string): ManagerAuthContext => ({
    venueId,
    organizationId,
    staffId,
    username: staffId,
    role: 'MANAGER',
  });
  const a = actor(venueAId, 'manager-a');
  const b = actor(venueBId, 'manager-b');
  const tenantA = { venueId: venueAId, organizationId };
  const tenantB = { venueId: venueBId, organizationId };

  /** Current stock as the Manager list would show it. */
  async function stockOf(venueId: string, stockItemId: string) {
    const balances = await inventory.currentStock(venueId, [stockItemId]);
    return (balances.get(stockItemId) ?? 0).toString();
  }

  async function freshVenue() {
    await prisma.stockMovement.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.receivingLine.deleteMany({
      where: { receiving: { venueId: { in: venueIds } } },
    });
    await prisma.receiving.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockItemPurchaseUnit.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.supplier.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    inventory = new InventoryService(prisma, new RecipeService(prisma));
    receiving = new ReceivingService(prisma);
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Receiving fixture',
        venues: {
          create: venueIds.map((id, index) => ({
            id,
            name: `Receiving Venue ${index}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          })),
        },
      },
    });
  });

  beforeEach(freshVenue);

  afterAll(async () => {
    await freshVenue();
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  async function beefFixture() {
    const supplier = await inventory.createSupplier(a, {
      name: 'Meat Supplier',
    });
    const beef = await inventory.createStockItem(a, {
      name: 'Beef',
      baseUnit: 'kg',
      minimumStock: '10',
    });
    return { supplier, beef };
  }

  function draft(
    supplierId: string,
    lines: { stockItemId: string; qty: string; unit?: string; cost: string }[],
    waybill = '12345',
  ) {
    return receiving.createDraft(a, {
      supplierId,
      waybillNumber: waybill,
      documentDate: '2026-09-05',
      lines: lines.map((line) => ({
        stockItemId: line.stockItemId,
        enteredQuantity: line.qty,
        enteredUnit: line.unit,
        unitPurchaseCost: line.cost,
      })),
    });
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  it('a draft is editable and moves no stock', async () => {
    const { supplier, beef } = await beefFixture();
    const created = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15.00' },
    ]);

    expect(created.status).toBe('DRAFT');
    expect(created.documentTotal).toBe('750.00');
    expect(await stockOf(venueAId, beef.id)).toBe('0');

    const edited = await receiving.updateDraft(a, created.id, {
      supplierId: supplier.id,
      documentDate: '2026-09-05',
      waybillNumber: '12345-B',
      lines: [
        { stockItemId: beef.id, enteredQuantity: '20', unitPurchaseCost: '16' },
      ],
    });
    expect(edited.documentTotal).toBe('320.00');
    expect(edited.lines).toHaveLength(1);
    expect(await stockOf(venueAId, beef.id)).toBe('0');
  });

  it('posting freezes the document and creates the movements', async () => {
    const { supplier, beef } = await beefFixture();
    const created = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15.00' },
    ]);

    const posted = await receiving.post(a, created.id);
    expect(posted.result).toBe('posted');
    expect(posted.status).toBe('POSTED');
    expect(posted.postedByName).toBe('manager-a');
    expect(posted.movements).toHaveLength(1);
    expect(posted.movements[0]).toMatchObject({
      movementType: 'RECEIVING',
      quantityDeltaBase: '50.000',
      baseUnit: 'kg',
      businessDate: '2026-09-05',
    });
    expect(await stockOf(venueAId, beef.id)).toBe('50');

    await expect(
      receiving.updateDraft(a, created.id, {
        supplierId: supplier.id,
        documentDate: '2026-09-05',
        lines: [
          {
            stockItemId: beef.id,
            enteredQuantity: '999',
            unitPurchaseCost: '1',
          },
        ],
      }),
    ).rejects.toThrow('cannot be edited');
    await expect(receiving.deleteDraft(a, created.id)).rejects.toThrow(
      'Only a draft Receiving can be deleted',
    );
    expect(await stockOf(venueAId, beef.id)).toBe('50');
  });

  it('a draft may be deleted; posted history may not', async () => {
    const { supplier, beef } = await beefFixture();
    const disposable = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '1', cost: '1' },
    ]);
    await expect(
      receiving.deleteDraft(a, disposable.id),
    ).resolves.toMatchObject({ deleted: true });
    await expect(receiving.detail(tenantA, disposable.id)).rejects.toThrow(
      'Receiving not found',
    );
  });

  it('refuses to post an empty document', async () => {
    const { supplier } = await beefFixture();
    const empty = await receiving.createDraft(a, {
      supplierId: supplier.id,
      documentDate: '2026-09-05',
      lines: [],
    });
    await expect(receiving.post(a, empty.id)).rejects.toThrow(
      'at least one line',
    );
  });

  // ── Derived stock ───────────────────────────────────────────────────────

  it('derives stock across several documents and a cancellation', async () => {
    const { supplier, beef } = await beefFixture();

    const first = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15.00' },
    ]);
    await receiving.post(a, first.id);
    expect(await stockOf(venueAId, beef.id)).toBe('50');

    const second = await draft(
      supplier.id,
      [{ stockItemId: beef.id, qty: '20', cost: '15.00' }],
      '12346',
    );
    await receiving.post(a, second.id);
    expect(await stockOf(venueAId, beef.id)).toBe('70');

    const cancelled = await receiving.cancel(a, first.id);
    expect(cancelled.result).toBe('cancelled');
    expect(await stockOf(venueAId, beef.id)).toBe('20');

    // The original receipt is still there. Cancelling adds, never deletes.
    const detail = await receiving.detail(tenantA, first.id);
    expect(detail.status).toBe('CANCELLED');
    expect(detail.movements).toHaveLength(2);
    expect(detail.movements.map((m) => m.movementType)).toEqual([
      'RECEIVING',
      'RECEIVING_REVERSAL',
    ]);
    expect(detail.movements[1].quantityDeltaBase).toBe('-50.000');
    expect(detail.movements[1].reversalOfMovementId).toBe(
      detail.movements[0].id,
    );
    expect(detail.lines).toHaveLength(1);
  });

  it('an item with no movements reads as an exact zero', async () => {
    const { beef } = await beefFixture();
    const [presented] = await inventory.listStockItems(tenantA);
    expect(presented.id).toBe(beef.id);
    expect(presented.currentStock).toBe('0.000');
    expect(presented.stockStatus).toBe('LOW');
  });

  it('reports low stock only against a configured minimum', async () => {
    const { supplier } = await beefFixture();
    const unthresholded = await inventory.createStockItem(a, {
      name: 'Salt',
      baseUnit: 'kg',
    });
    expect(unthresholded.stockStatus).toBe('NO_MINIMUM');
    expect(unthresholded.isLowStock).toBe(false);

    const beef = (await inventory.listStockItems(tenantA)).find(
      (item) => item.name === 'Beef',
    )!;
    const posted = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.post(a, posted.id);

    const after = (await inventory.listStockItems(tenantA)).find(
      (item) => item.id === beef.id,
    )!;
    expect(after.currentStock).toBe('50.000');
    expect(after.stockStatus).toBe('OK');
    expect(after.isLowStock).toBe(false);
  });

  // ── Units and packaging ─────────────────────────────────────────────────

  it('converts a compatible unit into the item base unit', async () => {
    const { supplier } = await beefFixture();
    const flour = await inventory.createStockItem(a, {
      name: 'Flour',
      baseUnit: 'kg',
    });
    const oil = await inventory.createStockItem(a, {
      name: 'Oil',
      baseUnit: 'L',
    });
    const document = await draft(supplier.id, [
      { stockItemId: flour.id, qty: '5000', unit: 'g', cost: '0.004' },
      { stockItemId: oil.id, qty: '1500', unit: 'ml', cost: '0.006' },
    ]);
    expect(document.lines[0]).toMatchObject({
      enteredQuantity: '5000.000',
      enteredUnit: 'g',
      baseQuantity: '5.000',
      baseUnit: 'kg',
    });
    expect(document.lines[1].baseQuantity).toBe('1.500');

    await receiving.post(a, document.id);
    expect(await stockOf(venueAId, flour.id)).toBe('5');
    expect(await stockOf(venueAId, oil.id)).toBe('1.5');
  });

  it('rejects an incompatible unit rather than storing a guess', async () => {
    const { supplier } = await beefFixture();
    const oil = await inventory.createStockItem(a, {
      name: 'Oil L',
      baseUnit: 'L',
    });
    await expect(
      draft(supplier.id, [
        { stockItemId: oil.id, qty: '5', unit: 'kg', cost: '1' },
      ]),
    ).rejects.toThrow('Cannot convert kg to L');
    expect(await prisma.receiving.count({ where: { venueId: venueAId } })).toBe(
      0,
    );
  });

  it('applies each item’s own box, and refuses an unconfigured one', async () => {
    const { supplier } = await beefFixture();
    const lemonade = await inventory.createStockItem(a, {
      name: 'Lemonade 0.5L',
      baseUnit: 'bottle',
      purchaseUnits: [
        { unit: 'box', baseUnitMultiplier: '24' },
        { unit: 'pack', baseUnitMultiplier: '6' },
      ],
    });
    const wine = await inventory.createStockItem(a, {
      name: 'Wine',
      baseUnit: 'bottle',
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '6' }],
    });
    const water = await inventory.createStockItem(a, {
      name: 'Water',
      baseUnit: 'bottle',
    });

    expect(lemonade.purchaseUnits).toEqual([
      { id: expect.any(String), unit: 'box', baseUnitMultiplier: '24' },
      { id: expect.any(String), unit: 'pack', baseUnitMultiplier: '6' },
    ]);

    const document = await draft(supplier.id, [
      { stockItemId: lemonade.id, qty: '10', unit: 'box', cost: '28.80' },
      { stockItemId: wine.id, qty: '10', unit: 'box', cost: '60.00' },
    ]);
    expect(document.lines[0]).toMatchObject({
      baseQuantity: '240.000',
      baseUnit: 'bottle',
      lineTotal: '288.00',
      // AD: what a future weighted-average step needs, preserved now.
      effectiveBaseUnitCost: '1.200000',
    });
    expect(document.lines[1].baseQuantity).toBe('60.000');

    await receiving.post(a, document.id);
    expect(await stockOf(venueAId, lemonade.id)).toBe('240');
    expect(await stockOf(venueAId, wine.id)).toBe('60');

    await expect(
      draft(supplier.id, [
        { stockItemId: water.id, qty: '3', unit: 'box', cost: '1' },
      ]),
    ).rejects.toThrow();
  });

  it('refuses a packaging ratio for the item’s own base unit', async () => {
    await expect(
      inventory.createStockItem(a, {
        name: 'Confused',
        baseUnit: 'bottle',
        purchaseUnits: [{ unit: 'bottle', baseUnitMultiplier: '1' }],
      }),
    ).rejects.toThrow('needs no purchase ratio');
  });

  // ── Money ───────────────────────────────────────────────────────────────

  it('keeps the document total exact across awkward decimals', async () => {
    const { supplier } = await beefFixture();
    const item = await inventory.createStockItem(a, {
      name: 'Sachet',
      baseUnit: 'piece',
    });
    const document = await draft(supplier.id, [
      { stockItemId: item.id, qty: '1', cost: '0.10' },
      { stockItemId: item.id, qty: '1', cost: '0.20' },
    ]);
    expect(document.lines.map((line) => line.lineTotal)).toEqual([
      '0.10',
      '0.20',
    ]);
    expect(document.documentTotal).toBe('0.30');

    const stored = await prisma.receiving.findUniqueOrThrow({
      where: { id: document.id },
    });
    expect(stored.documentTotal.toFixed(2)).toBe('0.30');
  });

  // ── Idempotency and concurrency ─────────────────────────────────────────

  it('repeated posting returns already_posted and moves nothing more', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);

    const first = await receiving.post(a, document.id);
    const second = await receiving.post(a, document.id);
    const third = await receiving.post(a, document.id);

    expect(first.result).toBe('posted');
    expect(second.result).toBe('already_posted');
    expect(third.result).toBe('already_posted');
    expect(await stockOf(venueAId, beef.id)).toBe('50');
    expect(
      await prisma.stockMovement.count({ where: { receivingId: document.id } }),
    ).toBe(1);
  });

  it('repeated cancellation adds no second reversal', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.post(a, document.id);

    const first = await receiving.cancel(a, document.id, 'wrong supplier');
    const second = await receiving.cancel(a, document.id);
    const third = await receiving.cancel(a, document.id);

    expect(first.result).toBe('cancelled');
    expect(second.result).toBe('already_cancelled');
    expect(third.result).toBe('already_cancelled');
    expect(first.cancellationReason).toBe('wrong supplier');
    expect(await stockOf(venueAId, beef.id)).toBe('0');
    expect(
      await prisma.stockMovement.count({
        where: { receivingId: document.id, movementType: 'RECEIVING_REVERSAL' },
      }),
    ).toBe(1);
  });

  it('two simultaneous posts cannot double the stock', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);

    const outcomes = await Promise.allSettled([
      receiving.post(a, document.id),
      receiving.post(a, document.id),
      receiving.post(a, document.id),
      receiving.post(a, document.id),
    ]);
    const results = outcomes.flatMap((outcome) =>
      outcome.status === 'fulfilled' ? [outcome.value.result] : [],
    );
    expect(results.filter((result) => result === 'posted')).toHaveLength(1);
    expect(await stockOf(venueAId, beef.id)).toBe('50');
    expect(
      await prisma.stockMovement.count({ where: { receivingId: document.id } }),
    ).toBe(1);
  });

  it('two simultaneous cancellations write one reversal', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.post(a, document.id);

    await Promise.allSettled([
      receiving.cancel(a, document.id),
      receiving.cancel(a, document.id),
      receiving.cancel(a, document.id),
    ]);
    expect(
      await prisma.stockMovement.count({
        where: { receivingId: document.id, movementType: 'RECEIVING_REVERSAL' },
      }),
    ).toBe(1);
    expect(await stockOf(venueAId, beef.id)).toBe('0');
  });

  it('a failed line leaves no partial posting behind', async () => {
    const { supplier, beef } = await beefFixture();
    const other = await inventory.createStockItem(a, {
      name: 'Cheese',
      baseUnit: 'kg',
    });
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
      { stockItemId: other.id, qty: '10', cost: '20' },
    ]);
    // The base unit moves under the open draft: posting must refuse whole.
    await inventory.updateStockItem(a, other.id, { baseUnit: 'g' });

    await expect(receiving.post(a, document.id)).rejects.toThrow(
      'base unit changed',
    );
    expect(await stockOf(venueAId, beef.id)).toBe('0');
    expect(
      await prisma.stockMovement.count({ where: { receivingId: document.id } }),
    ).toBe(0);
    expect(
      (await receiving.detail(tenantA, document.id)).status,
    ).toBe('DRAFT');
  });

  // ── History safety ──────────────────────────────────────────────────────

  it('renaming a Supplier or a Stock Item never rewrites a posted document', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.post(a, document.id);

    await inventory.updateSupplier(a, supplier.id, {
      name: 'Renamed Meat Co',
      isActive: false,
    });
    await inventory.updateStockItem(a, beef.id, { name: 'Beef shoulder' });

    const detail = await receiving.detail(tenantA, document.id);
    expect(detail.supplierName).toBe('Meat Supplier');
    expect(detail.supplierId).toBe(supplier.id);
    expect(detail.lines[0].stockItemName).toBe('Beef');
    expect(detail.lines[0].stockItemId).toBe(beef.id);

    // The live catalog moved on; the document did not.
    const live = (await inventory.listStockItems(tenantA)).find(
      (item) => item.id === beef.id,
    )!;
    expect(live.name).toBe('Beef shoulder');
    expect(live.currentStock).toBe('50.000');
  });

  // ── History reads ───────────────────────────────────────────────────────

  it('lists, filters and pages Receiving history', async () => {
    const { supplier, beef } = await beefFixture();
    const other = await inventory.createSupplier(a, { name: 'Greengrocer' });
    const posted = await draft(
      supplier.id,
      [{ stockItemId: beef.id, qty: '5', cost: '10' }],
      'WB-1',
    );
    await receiving.post(a, posted.id);
    await receiving.createDraft(a, {
      supplierId: other.id,
      documentDate: '2026-09-06',
      waybillNumber: 'WB-2',
      lines: [
        { stockItemId: beef.id, enteredQuantity: '1', unitPurchaseCost: '1' },
      ],
    });

    const all = await receiving.list(tenantA);
    expect(all.receivings).toHaveLength(2);
    expect(all.receivings[0].waybillNumber).toBe('WB-2');
    expect(all.receivings[0].lineCount).toBe(1);

    expect(
      (await receiving.list(tenantA, { status: 'POSTED' })).receivings,
    ).toHaveLength(1);
    expect(
      (await receiving.list(tenantA, { supplierId: other.id })).receivings,
    ).toHaveLength(1);
    expect(
      (await receiving.list(tenantA, { search: 'WB-1' })).receivings,
    ).toHaveLength(1);
    expect(
      (await receiving.list(tenantA, { search: 'greengrocer' })).receivings,
    ).toHaveLength(1);
    expect(
      (await receiving.list(tenantA, { from: '2026-09-06' })).receivings,
    ).toHaveLength(1);

    const firstPage = await receiving.list(tenantA, { take: 1 });
    expect(firstPage.receivings).toHaveLength(1);
    expect(firstPage.nextCursor).toBe(firstPage.receivings[0].id);
    const secondPage = await receiving.list(tenantA, {
      take: 1,
      cursor: firstPage.nextCursor!,
    });
    expect(secondPage.receivings).toHaveLength(1);
    expect(secondPage.receivings[0].id).not.toBe(firstPage.receivings[0].id);
  });

  it('a Stock Item detail carries the balance and its recent movements', async () => {
    const { supplier, beef } = await beefFixture();
    const first = await draft(
      supplier.id,
      [{ stockItemId: beef.id, qty: '50', cost: '15' }],
      'WB-A',
    );
    await receiving.post(a, first.id);
    const second = await draft(
      supplier.id,
      [{ stockItemId: beef.id, qty: '20', cost: '15' }],
      'WB-B',
    );
    await receiving.post(a, second.id);
    await receiving.cancel(a, second.id);

    const detail = await inventory.getStockItem(tenantA, beef.id);
    expect(detail.currentStock).toBe('50.000');
    expect(detail.recentMovements).toHaveLength(3);
    expect(detail.recentMovements[0].movementType).toBe('RECEIVING_REVERSAL');
    expect(detail.recentMovements[0].quantityDeltaBase).toBe('-20.000');
    expect(detail.recentMovements[0].receiving).toMatchObject({
      waybillNumber: 'WB-B',
      status: 'CANCELLED',
    });
  });

  // ── Audit ───────────────────────────────────────────────────────────────

  it('records create, update, post and cancel as venue-wide audit', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.updateDraft(a, document.id, {
      supplierId: supplier.id,
      documentDate: '2026-09-05',
      waybillNumber: '12345',
      lines: [
        { stockItemId: beef.id, enteredQuantity: '50', unitPurchaseCost: '15' },
      ],
    });
    await receiving.post(a, document.id);
    await receiving.cancel(a, document.id, 'returned');

    const rows = await prisma.auditEventLog.findMany({
      where: { venueId: venueAId, entityType: 'RECEIVING' },
      orderBy: { createdAt: 'asc' },
    });
    expect(rows.map((row) => row.action)).toEqual([
      'RECEIVING_CREATED',
      'RECEIVING_UPDATED',
      'RECEIVING_POSTED',
      'RECEIVING_CANCELLED',
    ]);
    expect(rows.every((row) => row.entityId === document.id)).toBe(true);

    const postedRow = rows[2].data as Record<string, unknown>;
    expect(postedRow).toMatchObject({
      supplierId: supplier.id,
      waybillNumber: '12345',
      documentDate: '2026-09-05',
      lineCount: 1,
      documentTotal: '750.00',
      previousStatus: 'DRAFT',
      newStatus: 'POSTED',
      movementCount: 1,
      actorName: 'manager-a',
      source: 'MANAGER',
    });
    // The ledger already holds every movement; audit summarises, never mirrors.
    expect(postedRow).not.toHaveProperty('lines');
    expect((rows[3].data as Record<string, unknown>).reversalCount).toBe(1);
  });

  // ── Tenancy ─────────────────────────────────────────────────────────────

  it('keeps Receiving, movements and their references inside one Venue', async () => {
    const { supplier, beef } = await beefFixture();
    const document = await draft(supplier.id, [
      { stockItemId: beef.id, qty: '50', cost: '15' },
    ]);
    await receiving.post(a, document.id);

    const supplierB = await inventory.createSupplier(b, { name: 'B supplier' });
    const itemB = await inventory.createStockItem(b, {
      name: 'B beef',
      baseUnit: 'kg',
    });

    // Venue A cannot reference Venue B's supplier or stock item.
    await expect(
      receiving.createDraft(a, {
        supplierId: supplierB.id,
        documentDate: '2026-09-05',
        lines: [
          { stockItemId: beef.id, enteredQuantity: '1', unitPurchaseCost: '1' },
        ],
      }),
    ).rejects.toThrow('Supplier not found');
    await expect(
      receiving.createDraft(a, {
        supplierId: supplier.id,
        documentDate: '2026-09-05',
        lines: [
          {
            stockItemId: itemB.id,
            enteredQuantity: '1',
            unitPurchaseCost: '1',
          },
        ],
      }),
    ).rejects.toThrow('not found');

    // Venue B cannot read, cancel or count Venue A's document or movements.
    await expect(receiving.detail(tenantB, document.id)).rejects.toThrow(
      'Receiving not found',
    );
    await expect(receiving.cancel(b, document.id)).rejects.toThrow(
      'Receiving not found',
    );
    expect((await receiving.list(tenantB)).receivings).toHaveLength(0);
    expect(await stockOf(venueBId, itemB.id)).toBe('0');
    expect((await inventory.currentStock(venueBId)).size).toBe(0);

    // And Venue A is untouched by the attempts.
    expect(await stockOf(venueAId, beef.id)).toBe('50');
  });
});
