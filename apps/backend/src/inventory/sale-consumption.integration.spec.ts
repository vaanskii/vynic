import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { EdgeTransportController } from '../edge/edge-transport.controller';
import { EdgeCommandService } from '../edge/edge-command.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { SaleConsumptionService } from './sale-consumption.service';
import { InventoryService } from './inventory.service';
import { RecipeService } from './recipe.service';
import { ReceivingService } from './receiving.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
(databaseUrl ? describe : describe.skip)(
  'Sale consumption (disposable PostgreSQL)',
  () => {
    let prisma: PrismaService;
    let service: SaleConsumptionService;
    let inventory: InventoryService;
    let recipes: RecipeService;
    let receiving: ReceivingService;
    const organizationId = `consumption-${process.pid}`;
    const a = {
      organizationId,
      venueId: `${organizationId}-a`,
      staffId: 'manager',
      username: 'Manager',
      role: 'MANAGER' as const,
    };
    const b = { ...a, venueId: `${organizationId}-b` };
    const scope = { venueId: { in: [a.venueId, b.venueId] } };
    let n = 0;
    beforeAll(async () => {
      prisma = new PrismaService({ datasourceUrl: databaseUrl });
      await prisma.$connect();
      service = new SaleConsumptionService(prisma);
      recipes = new RecipeService(prisma);
      inventory = new InventoryService(prisma, recipes);
      receiving = new ReceivingService(prisma);
      await prisma.organization.create({
        data: {
          id: organizationId,
          name: 'Consumption test',
          venues: {
            create: [a, b].map((t) => ({
              id: t.venueId,
              name: t.venueId,
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })),
          },
        },
      });
    });
    afterAll(async () => {
      await prisma.stockMovement.deleteMany({ where: scope });
      await prisma.saleConsumptionComponent.deleteMany({ where: scope });
      await prisma.saleConsumptionLine.deleteMany({ where: scope });
      await prisma.saleConsumption.deleteMany({ where: scope });
      await prisma.receivingLine.deleteMany({ where: { receiving: scope } });
      await prisma.receiving.deleteMany({ where: scope });
      await prisma.menuConsumptionComponent.deleteMany({ where: scope });
      await prisma.menuConsumptionRecipe.deleteMany({ where: scope });
      await prisma.stockItemPurchaseUnit.deleteMany({ where: scope });
      await prisma.stockItem.deleteMany({ where: scope });
      await prisma.supplier.deleteMany({ where: scope });
      await prisma.menuItemVariant.deleteMany({ where: { menuItem: scope } });
      await prisma.menuItem.deleteMany({ where: scope });
      await prisma.menuCategory.deleteMany({ where: scope });
      await prisma.auditEventLog.deleteMany({ where: scope });
      await prisma.venue.deleteMany({ where: { organizationId } });
      await prisma.organization.delete({ where: { id: organizationId } });
      await prisma.$disconnect();
    });
    async function fixture(
      unit = 'bottle',
      quantity = '1',
      variants = false,
      tenant = a,
    ) {
      const seq = ++n;
      const category = await prisma.menuCategory.create({
        data: {
          venueId: tenant.venueId,
          slug: `cat-${seq}`,
          nameKa: 'Test',
          nameEn: 'Test',
        },
      });
      const menu = await prisma.menuItem.create({
        data: {
          venueId: tenant.venueId,
          categoryId: category.id,
          nameKa: `Product ${seq}`,
          nameEn: 'Product',
          price: 10,
          posMenuItemId: `pos-${seq}`,
          ...(variants
            ? {
                variants: {
                  create: [
                    { posMenuVariantId: `small-${seq}`, size: 1, price: 10 },
                    { posMenuVariantId: `large-${seq}`, size: 2, price: 20 },
                  ],
                },
              }
            : {}),
        },
        include: { variants: { orderBy: { size: 'asc' } } },
      });
      const stock = await inventory.createStockItem(tenant, {
        name: `Stock ${seq}`,
        baseUnit: unit,
      });
      await recipes.save(tenant, {
        menuItemId: menu.id,
        ...(variants ? { variantId: menu.variants[0].id } : {}),
        components: [{ stockItemId: stock.id, quantity, unit }],
      });
      const recipe = (await recipes.projection(tenant.venueId)).find(
        (r) => r.menuItemId === menu.id,
      )!;
      return { menu, stock, recipe };
    }
    function payload(recipe: any, soldQuantity = 8) {
      const id = ++n;
      return {
        posSaleId: `sale-${id}`,
        closureId: `closure-${id}`,
        orderId: id,
        businessDate: '2026-09-05',
        closedAt: '2026-09-05T10:00:00.000Z',
        reversedAt: null as string | null,
        snapshot: {
          version: 1,
          policy: 'FISCAL_CLOSE',
          catalogGeneratedAt: '2026-09-05T09:00:00.000Z',
          lines: [
            {
              lineSeq: 0,
              itemName: 'Product',
              menuItemId: recipe.posMenuItemId,
              variantId: recipe.posMenuVariantId,
              soldQuantity,
              status: 'MAPPED',
              reason: null,
              recipeId: recipe.recipeId,
              recipeRevision: recipe.revision,
              components: recipe.components.map((c: any) => ({
                ...c,
                totalBaseQuantity: new Prisma.Decimal(c.baseQuantityPerUnit)
                  .times(soldQuantity)
                  .toFixed(6),
              })),
            },
          ],
        },
      };
    }
    async function receive(stock: any, quantity: string) {
      const supplier = await inventory.createSupplier(a, {
        name: `Supplier ${++n}`,
      });
      const draft = await receiving.createDraft(a, {
        supplierId: supplier.id,
        documentDate: '2026-09-05',
        lines: [
          {
            stockItemId: stock.id,
            enteredQuantity: quantity,
            enteredUnit: stock.baseUnit,
            unitPurchaseCost: '1',
          },
        ],
      });
      await receiving.post(a, draft.id);
      return draft;
    }
    it('direct bottles: 400 - 8 = 392; concurrent replay and restore happen exactly once; Receiving still reverses', async () => {
      const f = await fixture();
      const receipt = await receive(f.stock, '400');
      const row = payload(f.recipe);
      await Promise.all([
        service.apply(a, row),
        service.apply(a, row),
        service.apply(a, row),
      ]);
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '392.000',
      );
      row.reversedAt = '2026-09-05T11:00:00.000Z';
      await Promise.all([service.apply(a, row), service.apply(a, row)]);
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '400.000',
      );
      expect(
        await prisma.stockMovement.count({
          where: { stockItemId: f.stock.id, movementType: 'CONSUMPTION' },
        }),
      ).toBe(1);
      expect(
        await prisma.stockMovement.count({
          where: {
            stockItemId: f.stock.id,
            movementType: 'CONSUMPTION_REVERSAL',
          },
        }),
      ).toBe(1);
      await service.apply(a, { ...row, reversedAt: null });
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '400.000',
      );
      await receiving.cancel(a, receipt.id, 'test reversal');
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '0.000',
      );
    });
    it('draft variants consume exactly 2.900L, without variant guessing', async () => {
      const f = await fixture('L', '0.500', true);
      await recipes.save(a, {
        menuItemId: f.menu.id,
        variantId: f.menu.variants[1].id,
        components: [{ stockItemId: f.stock.id, quantity: '0.300', unit: 'L' }],
      });
      const other = (await recipes.projection(a.venueId)).find(
        (r) => r.variantId === f.menu.variants[1].id,
      )!;
      await receive(f.stock, '120');
      const row = payload(f.recipe, 4);
      row.snapshot.lines.push({
        ...payload(other, 3).snapshot.lines[0],
        lineSeq: 1,
      });
      await service.apply(a, row);
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '117.100',
      );
      const bad = payload(f.recipe, 1);
      bad.snapshot.lines[0].variantId = other.posMenuVariantId;
      await expect(service.apply(a, bad)).rejects.toThrow(
        'Recipe does not belong',
      );
    });
    it('three ingredients are atomic and exact; negative stock is visible without a minimum', async () => {
      const f = await fixture('kg', '0.035');
      const flour = await inventory.createStockItem(a, {
        name: 'Flour',
        baseUnit: 'kg',
      });
      const onion = await inventory.createStockItem(a, {
        name: 'Onion',
        baseUnit: 'kg',
      });
      await recipes.save(a, {
        menuItemId: f.menu.id,
        components: [
          { stockItemId: f.stock.id, quantity: '0.035', unit: 'kg' },
          { stockItemId: flour.id, quantity: '0.025', unit: 'kg' },
          { stockItemId: onion.id, quantity: '0.008', unit: 'kg' },
        ],
      });
      const recipe = (await recipes.projection(a.venueId)).find(
        (r) => r.menuItemId === f.menu.id,
      )!;
      const bad = payload(recipe, 10);
      bad.snapshot.lines[0].components[2].totalBaseQuantity = '0.090000';
      await expect(service.apply(a, bad)).rejects.toThrow('Consumption total');
      expect(
        await prisma.saleConsumption.count({
          where: { posSaleId: bad.posSaleId },
        }),
      ).toBe(0);
      expect(
        await prisma.stockMovement.count({
          where: { stockItemId: f.stock.id },
        }),
      ).toBe(0);
      await service.apply(a, payload(recipe, 10));
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '-0.350',
      );
      expect((await inventory.getStockItem(a, flour.id)).currentStock).toBe(
        '-0.250',
      );
      expect((await inventory.getStockItem(a, onion.id)).currentStock).toBe(
        '-0.080',
      );
      expect((await inventory.getStockItem(a, f.stock.id)).stockStatus).toBe(
        'NEGATIVE',
      );
    });
    it('old recipe revision survives change/disable, restore and re-close use separate frozen sets', async () => {
      const f = await fixture('kg', '0.035');
      const old = payload(f.recipe, 10);
      await recipes.save(a, {
        menuItemId: f.menu.id,
        components: [
          { stockItemId: f.stock.id, quantity: '0.040', unit: 'kg' },
        ],
      });
      await service.apply(a, old); // delayed offline receipt of old revision
      await service.apply(a, {
        ...old,
        reversedAt: '2026-09-05T12:00:00.000Z',
      });
      const freshRecipe = (await recipes.projection(a.venueId)).find(
        (r) => r.menuItemId === f.menu.id,
      )!;
      const fresh = payload(freshRecipe, 10);
      await recipes.disable(a, freshRecipe.recipeId);
      expect(
        (await recipes.projection(a.venueId)).some(
          (r) => r.recipeId === freshRecipe.recipeId,
        ),
      ).toBe(false);
      await service.apply(a, fresh); // captured before disable, still honest history
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '-0.400',
      );
      const history = await service.list(a);
      const detail = await service.detail(
        a,
        history.find((r) => r.posSaleId === old.posSaleId)!.id,
      );
      expect(detail.lines[0].components[0].baseQuantityPerUnit).toBe(
        '0.035000',
      );
      const mutated = structuredClone(old);
      mutated.snapshot.lines[0].itemName = 'Changed';
      await expect(service.apply(a, mutated)).rejects.toThrow('immutable');
    });
    it('unmapped and internal exclusions remain readable without fabricated movements', async () => {
      const f = await fixture();
      const invalidMapped = payload(f.recipe);
      invalidMapped.snapshot.lines[0].menuItemId = null;
      await expect(service.apply(a, invalidMapped)).rejects.toThrow(
        'mapped menuItemId',
      );
      const row: any = payload(f.recipe);
      row.snapshot.lines = [
        {
          lineSeq: 0,
          itemName: 'Manual',
          menuItemId: null,
          variantId: null,
          soldQuantity: 8,
          status: 'UNMAPPED',
          reason: 'MANUAL_LINE',
          components: [],
        },
      ];
      await service.apply(a, row);
      expect(
        (await service.list(a, { unmapped: 'true' })).some(
          (r) => r.posSaleId === row.posSaleId,
        ),
      ).toBe(true);
      const excluded = {
        ...row,
        posSaleId: 'internal',
        closureId: 'internal',
        snapshot: {
          ...row.snapshot,
          policy: 'INTERNAL_EXCLUDED',
          lines: [
            {
              ...row.snapshot.lines[0],
              status: 'EXCLUDED',
              reason: 'INTERNAL_POLICY',
            },
          ],
        },
      };
      await service.apply(a, excluded);
      expect(
        await prisma.stockMovement.count({
          where: { stockItemId: f.stock.id },
        }),
      ).toBe(0);
    });
    it('rejects cross-Venue recipe, stock, reversal and detail reads', async () => {
      const f = await fixture();
      const foreign = await fixture('bottle', '1', false, b);
      const row = payload(f.recipe);
      await service.apply(a, row);
      await expect(service.apply(b, row)).rejects.toThrow(
        'Recipe does not belong',
      );
      await expect(
        service.apply(b, { ...row, reversedAt: '2026-09-05T12:00:00Z' }),
      ).rejects.toThrow('Recipe does not belong');
      const bad = payload(f.recipe);
      bad.snapshot.lines[0].components[0].stockItemId = foreign.stock.id;
      await expect(service.apply(a, bad)).rejects.toThrow('Stock item/unit');
      const saved = (await service.list(a)).find(
        (r) => r.posSaleId === row.posSaleId,
      )!;
      await expect(service.detail(b, saved.id)).rejects.toThrow('not found');
      expect(
        (await service.list(b)).some((r) => r.posSaleId === row.posSaleId),
      ).toBe(false);
    });
    it('HTTP consumption uses the authenticated Device Venue and acknowledges valid effects', async () => {
      const f = await fixture();
      const row = payload(f.recipe, 1);
      const module = await Test.createTestingModule({
        controllers: [EdgeTransportController],
        providers: [
          {
            provide: VenueEntitlementsService,
            useValue: new VenueEntitlementsService(prisma),
          },
          { provide: SaleConsumptionService, useValue: service },
          { provide: InventoryService, useValue: inventory },
          { provide: EdgeCommandService, useValue: {} },
          {
            provide: DeviceCredentialService,
            useValue: {
              isDeviceCredential: (key: string) => key === 'test-device',
              verifyCredential: async () => ({
                ...a,
                deviceId: 'test-device-id',
              }),
            },
          },
        ],
      }).compile();
      const app = module.createNestApplication();
      await app.init();
      try {
        await request(app.getHttpServer())
          .post('/edge/inventory/consumption')
          .send(row)
          .expect(401);
        const response = await request(app.getHttpServer())
          .post('/edge/inventory/consumption')
          .set('X-POS-Sync-Key', 'test-device')
          .send({ ...row, venueId: b.venueId })
          .expect(201);
        expect(response.body).toEqual({
          posSaleId: row.posSaleId,
          revision: 1,
        });
        expect(
          await prisma.saleConsumption.count({
            where: { posSaleId: row.posSaleId, venueId: a.venueId },
          }),
        ).toBe(1);
        expect(
          await prisma.saleConsumption.count({
            where: { posSaleId: row.posSaleId, venueId: b.venueId },
          }),
        ).toBe(0);
        await request(app.getHttpServer())
          .post('/edge/inventory/consumption')
          .set('X-POS-Sync-Key', 'test-device')
          .send({})
          .expect(400);
      } finally {
        await app.close();
      }
    });

    it('a crash after the first component write rolls the entire effect back', async () => {
      const f = await fixture('kg', '0.035');
      const other = await inventory.createStockItem(a, {
        name: 'Second ingredient',
        baseUnit: 'kg',
      });
      await recipes.save(a, {
        menuItemId: f.menu.id,
        components: [
          { stockItemId: f.stock.id, quantity: '0.035', unit: 'kg' },
          { stockItemId: other.id, quantity: '0.025', unit: 'kg' },
        ],
      });
      const recipe = (await recipes.projection(a.venueId)).find(
        (r) => r.menuItemId === f.menu.id,
      )!;
      const row = payload(recipe, 10);
      let writes = 0;
      const failing = new SaleConsumptionService({
        $transaction: (fn: any, options: any) =>
          prisma.$transaction(
            (tx) =>
              fn(
                new Proxy(tx, {
                  get(target, key) {
                    if (key === 'stockMovement')
                      return {
                        ...tx.stockMovement,
                        create: async (args: any) => {
                          if (++writes === 2)
                            throw new Error('simulated crash');
                          return tx.stockMovement.create(args);
                        },
                      };
                    return Reflect.get(target, key);
                  },
                }),
              ),
            options,
          ),
      } as unknown as PrismaService);
      await expect(failing.apply(a, row)).rejects.toThrow('simulated crash');
      expect(writes).toBe(2);
      expect(
        await prisma.saleConsumption.count({
          where: { posSaleId: row.posSaleId },
        }),
      ).toBe(0);
      expect(
        await prisma.stockMovement.count({
          where: { stockItemId: f.stock.id },
        }),
      ).toBe(0);
      await service.apply(a, row);
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '-0.350',
      );
    });
    it('restore before first delivery atomically records both sets on their business dates', async () => {
      const f = await fixture();
      const row = {
        ...payload(f.recipe),
        reversedAt: '2026-09-06T11:00:00.000Z',
        restoreBusinessDate: '2026-09-06',
      };
      await service.apply(a, row);
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '0.000',
      );
      const reversal = await prisma.stockMovement.findFirstOrThrow({
        where: {
          stockItemId: f.stock.id,
          movementType: 'CONSUMPTION_REVERSAL',
        },
      });
      expect(reversal.businessDate).toBe('2026-09-06');
      expect(reversal.reversalOfMovementId).not.toBeNull();
    });

    it('retains sub-milligram recipe precision in the authoritative ledger', async () => {
      const f = await fixture('kg', '0.001');
      await recipes.save(a, {
        menuItemId: f.menu.id,
        yieldQuantity: '100',
        components: [
          { stockItemId: f.stock.id, quantity: '0.001', unit: 'kg' },
        ],
      });
      const recipe = (await recipes.projection(a.venueId)).find(
        (r) => r.menuItemId === f.menu.id,
      )!;
      await service.apply(a, payload(recipe, 3));
      expect((await inventory.getStockItem(a, f.stock.id)).currentStock).toBe(
        '-0.000030',
      );
    });
  },
);
