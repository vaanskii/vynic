import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { procurementSummary } from './procurement-summary';
import { InventoryCostService } from './inventory-cost.service';
import { SupplierPayments } from './supplier-payments';
import { Prisma, StockItemClassification } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import {
  INVENTORY_UNIT_DEFINITIONS,
  inventoryUnit,
  type InventoryUnit,
} from './inventory-unit';
import {
  multiplierText,
  positiveMultiplier,
  quantityText,
  stockQuantityText,
  recipeUnitsFor,
} from './inventory-quantity';
import {
  InventoryAuditAction,
  writeInventoryAudit,
  type InventoryActor,
} from './inventory-audit';
import { presentMovement } from './receiving.service';
import { RecipeService, menuGroup } from './recipe.service';

export { InventoryAuditAction };

/** How many recent movements a Stock Item detail carries. */
const RECENT_MOVEMENT_LIMIT = 20;

export interface PurchaseUnitInput {
  unit?: unknown;
  baseUnitMultiplier?: unknown;
}

export interface StockItemInput {
  requestId?: unknown;
  name?: unknown;
  sku?: unknown;
  classification?: unknown;
  supplierIds?: unknown;
  baseUnit?: unknown;
  minimumStock?: unknown;
  notes?: unknown;
  isActive?: unknown;
  /** When present, replaces this item's entire packaging configuration. */
  purchaseUnits?: unknown;
}

export interface SupplierInput {
  name?: unknown;
  taxId?: unknown;
  phone?: unknown;
  email?: unknown;
  address?: unknown;
  notes?: unknown;
  isActive?: unknown;
}

type Change = {
  field: string;
  previousValue: unknown;
  newValue: unknown;
};

@Injectable()
export class InventoryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly recipes: RecipeService,
  ) {}

  getUnits() {
    return INVENTORY_UNIT_DEFINITIONS;
  }

  async listStockItems(
    tenant: TenantContext,
    search?: string,
    withPrices = false,
  ) {
    const query = search?.trim();
    const rows = await this.prisma.stockItem.findMany({
      where: {
        venueId: tenant.venueId,
        ...(query
          ? {
              OR: [
                { name: { contains: query, mode: 'insensitive' as const } },
                { sku: { contains: query, mode: 'insensitive' as const } },
              ],
            }
          : {}),
      },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }, { id: 'asc' }],
      include: {
        supplierProducts: true,
        purchaseUnits: { orderBy: { unit: 'asc' } },
      },
    });
    const balances = await this.currentStock(tenant.venueId);
    const lastPrices = withPrices
      ? await this.prisma.receivingLine.findMany({
          where: {
            stockItem: { venueId: tenant.venueId },
            receiving: { venueId: tenant.venueId, status: 'POSTED' },
          },
          distinct: ['stockItemId', 'baseUnit'],
          orderBy: [
            { receiving: { businessDate: 'desc' } },
            { receiving: { postedAt: 'desc' } },
            { receivingId: 'desc' },
            { lineSequence: 'desc' },
          ],
          select: {
            stockItemId: true,
            baseUnit: true,
            effectiveBaseUnitCost: true,
          },
        })
      : [];
    const prices = new Map(
      lastPrices.map((r) => [
        r.stockItemId + ':' + r.baseUnit,
        r.effectiveBaseUnitCost.toFixed(6),
      ]),
    );
    return rows.map((row) => ({
      ...this.presentStockItem(row, balances.get(row.id)),
      ...(withPrices
        ? {
            lastPurchaseUnitCost:
              prices.get(row.id + ':' + row.baseUnit) ?? null,
          }
        : {}),
    }));
  }

  /**
   * One Stock Item with its packaging and its most recent ledger movements.
   *
   * The movements are shown, not summed here: the balance still comes from the
   * whole ledger, so a page of recent rows can never quietly become the truth.
   */
  async getStockItem(tenant: TenantContext, id: string) {
    const cleanId = requiredText(id, 'id');
    const row = await this.prisma.stockItem.findFirst({
      where: { id: cleanId, venueId: tenant.venueId },
      include: {
        supplierProducts: {
          include: { supplier: { select: { id: true, name: true } } },
        },
        purchaseUnits: { orderBy: { unit: 'asc' } },
      },
    });
    if (!row) throw new NotFoundException('Stock item not found');
    const [balances, movements, usedBy] = await Promise.all([
      this.currentStock(tenant.venueId, [cleanId]),
      this.prisma.stockMovement.findMany({
        where: { venueId: tenant.venueId, stockItemId: cleanId },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: RECENT_MOVEMENT_LIMIT,
        include: {
          receiving: {
            select: {
              id: true,
              waybillNumber: true,
              documentDate: true,
              supplierNameSnapshot: true,
              status: true,
            },
          },
        },
      }),
      // Which products consume this item. Inventory administration asks this
      // before disabling or renaming anything.
      this.recipes.usageForStockItem(tenant, cleanId),
    ]);
    return {
      ...this.presentStockItem(row, balances.get(cleanId)),
      currentCost: await new InventoryCostService(this.prisma).stockItem(
        tenant,
        cleanId,
      ),
      usedBy,
      suppliers: row.supplierProducts.map((link) => link.supplier),
      purchaseHistory: (
        await this.prisma.receivingLine.findMany({
          where: {
            stockItemId: cleanId,
            receiving: { venueId: tenant.venueId, status: 'POSTED' },
          },
          include: {
            receiving: {
              select: { businessDate: true, supplierNameSnapshot: true },
            },
          },
          orderBy: { receiving: { postedAt: 'desc' } },
          take: 20,
        })
      ).map((l) => ({
        receivingId: l.receivingId,
        businessDate: l.receiving.businessDate,
        supplierName: l.receiving.supplierNameSnapshot,
        quantity: l.baseQuantity.toFixed(3),
        baseUnit: l.baseUnit,
        total: l.lineTotal.toFixed(2),
        unitCost: l.effectiveBaseUnitCost.toFixed(6),
      })),
      recentMovements: movements.map((movement) => ({
        ...presentMovement(movement),
        receiving: movement.receiving
          ? {
              id: movement.receiving.id,
              waybillNumber: movement.receiving.waybillNumber,
              documentDate: movement.receiving.documentDate,
              supplierName: movement.receiving.supplierNameSnapshot,
              status: movement.receiving.status,
            }
          : null,
      })),
    };
  }

  /**
   * Current stock, derived from the movement ledger and nowhere else.
   *
   * There is deliberately no stored balance column to drift out of step: an
   * item with no movements is absent from the result and reads as an exact
   * zero, which is a real answer rather than a placeholder.
   */
  async currentStock(
    venueId: string,
    stockItemIds?: readonly string[],
  ): Promise<Map<string, Prisma.Decimal>> {
    const grouped = await this.prisma.stockMovement.groupBy({
      by: ['stockItemId'],
      where: {
        venueId,
        ...(stockItemIds ? { stockItemId: { in: [...stockItemIds] } } : {}),
      },
      _sum: { quantityDeltaBase: true },
    });
    return new Map(
      grouped.map((row) => [
        row.stockItemId,
        new Prisma.Decimal(row._sum.quantityDeltaBase ?? 0),
      ]),
    );
  }

  async listSuppliers(tenant: TenantContext, search?: string) {
    const query = search?.trim();
    const rows = await this.prisma.supplier.findMany({
      where: {
        venueId: tenant.venueId,
        ...(query
          ? {
              OR: [
                { name: { contains: query, mode: 'insensitive' as const } },
                { taxId: { contains: query, mode: 'insensitive' as const } },
                { phone: { contains: query, mode: 'insensitive' as const } },
                { email: { contains: query, mode: 'insensitive' as const } },
              ],
            }
          : {}),
      },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }, { id: 'asc' }],
    });
    const links = await this.prisma.supplierProduct.findMany({
      where: { venueId: tenant.venueId },
    });
    return rows.map((row) => ({
      ...this.presentSupplier(row),
      stockItemIds: links
        .filter((link) => link.supplierId === row.id)
        .map((link) => link.stockItemId),
    }));
  }

  /** Complete Device-scoped projection for the POS Hive cache. */
  async overview(tenant: TenantContext) {
    const [procurement, items, unmapped] = await Promise.all([
      procurementSummary(this.prisma, tenant),
      this.listStockItems(tenant),
      this.prisma.saleConsumptionLine.findMany({
        where: {
          venueId: tenant.venueId,
          status: 'UNMAPPED',
          consumption: { venueId: tenant.venueId, reversedAt: null },
        },
        distinct: ['menuItemId', 'variantId', 'itemName'],
        select: {
          menuItemId: true,
          variantId: true,
          itemName: true,
          variantName: true,
        },
        orderBy: { id: 'asc' },
      }),
    ]);
    return {
      procurement,
      lowStock: items.filter((i) => i.isActive && i.stockStatus === 'LOW')
        .length,
      negativeStock: items.filter(
        (i) => i.isActive && i.stockStatus === 'NEGATIVE',
      ).length,
      unmappedCount: unmapped.length,
      unmapped,
    };
  }

  async inspection(tenant: TenantContext) {
    const overview = await this.overview(tenant);
    const [items, receivings, menuItems] = await Promise.all([
      this.prisma.stockItem.findMany({
        where: { venueId: tenant.venueId },
        select: {
          id: true,
          movements: {
            where: { venueId: tenant.venueId },
            take: 20,
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          },
        },
      }),
      this.prisma.receiving.findMany({
        where: {
          venueId: tenant.venueId,
          businessDate: overview.procurement.businessDate,
          status: 'POSTED',
        },
        take: 100,
        orderBy: [{ postedAt: 'desc' }, { id: 'desc' }],
        select: {
          id: true,
          supplierNameSnapshot: true,
          documentTotal: true,
          businessDate: true,
        },
      }),
      this.recipes.listMenuItems(tenant),
    ]);
    return {
      ...overview,
      menuItems,
      costsByItem: Object.fromEntries(
        [
          ...(await new InventoryCostService(this.prisma).bases(
            tenant,
            items.map((i) => i.id),
          )),
        ].map(([key, g]) => [
          key.slice(0, key.lastIndexOf(':')),
          {
            unitCost: g.cost?.toFixed(6) ?? null,
            inventoryValue: g.value.toFixed(12),
            status: g.provisional ? 'PROVISIONAL' : 'AVAILABLE',
          },
        ]),
      ),
      movementsByItem: Object.fromEntries(
        items.map((item) => [item.id, item.movements.map(presentMovement)]),
      ),
      receivings: receivings.map((r) => ({
        ...r,
        documentTotal: r.documentTotal.toFixed(2),
      })),
    };
  }

  async getCatalog(tenant: TenantContext, version: 3 | 4 | 5 = 4) {
    const [stockItems, suppliers, recipes] = await Promise.all([
      this.listStockItems(tenant),
      this.listSuppliers(tenant),
      this.recipes.projection(tenant.venueId),
    ]);
    return {
      // Older POS decoders reject unknown purchase units. Keep their recipe
      // refresh working by omitting the new purchasing-only keg label.
      version,
      generatedAt: new Date().toISOString(),
      units: INVENTORY_UNIT_DEFINITIONS.filter(
        (unit) => version >= 4 || unit.code !== 'keg',
      ),
      stockItems:
        version >= 4
          ? stockItems
          : stockItems.map((item) => ({
              ...item,
              purchaseUnits: item.purchaseUnits.filter(
                (unit) => unit.unit !== 'keg',
              ),
            })),
      suppliers,
      recipes,
      ...(version >= 5 ? { inspection: await this.inspection(tenant) } : {}),
    };
  }

  async createStockItem(actor: InventoryActor, input: StockItemInput) {
    const requestId =
      input.requestId == null
        ? null
        : requiredText(input.requestId, 'requestId');
    if (requestId && !/^[0-9a-f-]{36}$/i.test(requestId))
      throw new BadRequestException('requestId must be UUID');
    // Inline ingredient creation carries only ingredient properties. Complex
    // supplier/packaging setup uses the existing atomic supplier-items route.
    if (requestId && (has(input, 'supplierIds') || has(input, 'purchaseUnits')))
      throw new BadRequestException(
        'Use supplied-item creation for supplier packaging',
      );
    const data = {
      venueId: actor.venueId,
      name: requiredText(input.name, 'name'),
      sku: optionalSku(input.sku),
      classification: classification(input.classification ?? 'FOOD'),
      baseUnit: stockBaseUnit(input.baseUnit),
      minimumStock: optionalQuantity(input.minimumStock, 'minimumStock'),
      notes: optionalText(input.notes),
      isActive: optionalBoolean(input.isActive, true, 'isActive'),
    };
    const purchaseUnits = has(input, 'purchaseUnits')
      ? readPurchaseUnits(input.purchaseUnits, data.baseUnit)
      : [];
    try {
      const created = await this.prisma.$transaction(async (tx) => {
        if (requestId) {
          await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${actor.venueId + ':item:' + requestId},0))`;
          const prior = await tx.stockItem.findUnique({
            where: {
              venueId_creationRequestId: {
                venueId: actor.venueId,
                creationRequestId: requestId,
              },
            },
            include: {
              supplierProducts: true,
              purchaseUnits: { orderBy: { unit: 'asc' } },
            },
          });
          if (prior) {
            if (
              Object.entries(data).some(
                ([key, value]) =>
                  String(prior[key] ?? '') !== String(value ?? ''),
              )
            )
              throw new ConflictException(
                'Ingredient request already used with different values',
              );
            return prior;
          }
        }
        const row = await tx.stockItem.create({
          data: {
            ...data,
            creationRequestId: requestId,
            purchaseUnits: {
              create: purchaseUnits.map((unit) => ({
                venueId: actor.venueId,
                unit: unit.unit,
                baseUnitMultiplier: unit.baseUnitMultiplier,
              })),
            },
          },
          include: {
            supplierProducts: true,
            purchaseUnits: { orderBy: { unit: 'asc' } },
          },
        });
        if (has(input, 'supplierIds')) {
          await this.replaceSuppliers(tx, actor, row.id, input.supplierIds);
          row.supplierProducts = await tx.supplierProduct.findMany({
            where: { venueId: actor.venueId, stockItemId: row.id },
          });
        }
        await this.audit(tx, actor, {
          action: InventoryAuditAction.STOCK_ITEM_CREATED,
          entityType: 'STOCK_ITEM',
          entityId: row.id,
          data: {
            stockItemId: row.id,
            name: row.name,
            sku: row.sku,
            classification: row.classification,
            supplierIds: (row.supplierProducts ?? []).map(
              (link: any) => link.supplierId,
            ),
            baseUnit: row.baseUnit,
            minimumStock: decimalText(row.minimumStock),
            isActive: row.isActive,
            purchaseUnits: purchaseUnitSummary(row.purchaseUnits),
          },
        });
        return row;
      });
      return this.presentStockItem(created);
    } catch (error) {
      rethrowInventoryConstraint(error);
    }
  }

  async updateStockItem(
    actor: InventoryActor,
    id: string,
    input: StockItemInput,
  ) {
    const cleanId = requiredText(id, 'id');
    try {
      return await this.prisma.$transaction(async (tx) => {
        const existing = await tx.stockItem.findFirst({
          where: { id: cleanId, venueId: actor.venueId },
        });
        if (!existing) throw new NotFoundException('Stock item not found');

        const data: Record<string, unknown> = {};
        const changes: Change[] = [];
        assignChange(data, changes, 'name', existing.name, input, requiredText);
        assignChange(data, changes, 'sku', existing.sku, input, optionalSku);
        assignChange(
          data,
          changes,
          'classification',
          existing.classification,
          input,
          classification,
        );
        if (has(input, 'supplierIds'))
          await this.replaceSuppliers(
            tx,
            actor,
            existing.id,
            input.supplierIds,
          );
        assignChange(
          data,
          changes,
          'baseUnit',
          existing.baseUnit,
          input,
          stockBaseUnit,
        );
        if (data.baseUnit != null && data.baseUnit !== existing.baseUnit) {
          const [receiving, recipe] = await Promise.all([
            tx.receivingLine.findFirst({
              where: {
                stockItemId: existing.id,
                receiving: {
                  venueId: actor.venueId,
                  status: { in: ['POSTED', 'CANCELLED'] },
                },
              },
            }),
            tx.menuConsumptionComponent.findFirst({
              where: { venueId: actor.venueId, stockItemId: existing.id },
            }),
          ]);
          if (receiving || recipe)
            throw new ConflictException(
              'A used stock item must keep its base unit',
            );
        }
        if (has(input, 'minimumStock')) {
          const next = optionalQuantity(input.minimumStock, 'minimumStock');
          const previousText = decimalText(existing.minimumStock);
          const nextText = decimalText(next);
          if (previousText !== nextText) {
            data.minimumStock = next;
            changes.push({
              field: 'minimumStock',
              previousValue: previousText,
              newValue: nextText,
            });
          }
        }
        assignChange(
          data,
          changes,
          'notes',
          existing.notes,
          input,
          optionalText,
        );
        if (has(input, 'isActive')) {
          const next = requiredBoolean(input.isActive, 'isActive');
          if (next !== existing.isActive) {
            data.isActive = next;
            changes.push({
              field: 'isActive',
              previousValue: existing.isActive,
              newValue: next,
            });
          }
        }

        // Packaging arrives as one declared set, so removing "pack" is
        // expressed by sending the set without it rather than by a delete call.
        const baseUnit =
          (data.baseUnit as string | undefined) ?? existing.baseUnit;
        let nextPurchaseUnits: ReturnType<typeof readPurchaseUnits> | null =
          null;
        if (has(input, 'purchaseUnits')) {
          const current = await tx.stockItemPurchaseUnit.findMany({
            where: { stockItemId: existing.id },
            orderBy: { unit: 'asc' },
          });
          const declared = readPurchaseUnits(input.purchaseUnits, baseUnit);
          const previousText = purchaseUnitSummary(current);
          const nextText = purchaseUnitSummary(declared);
          if (previousText !== nextText) {
            nextPurchaseUnits = declared;
            changes.push({
              field: 'purchaseUnits',
              previousValue: previousText,
              newValue: nextText,
            });
          }
        }

        if (changes.length === 0) {
          return this.presentStockItem(
            await tx.stockItem.findUniqueOrThrow({
              where: { id: existing.id },
              include: {
                supplierProducts: true,
                purchaseUnits: { orderBy: { unit: 'asc' } },
              },
            }),
            (await this.currentStock(actor.venueId, [existing.id])).get(
              existing.id,
            ),
          );
        }

        if (nextPurchaseUnits != null) {
          await tx.stockItemPurchaseUnit.deleteMany({
            where: { stockItemId: existing.id },
          });
          if (nextPurchaseUnits.length > 0) {
            await tx.stockItemPurchaseUnit.createMany({
              data: nextPurchaseUnits.map((unit) => ({
                venueId: actor.venueId,
                stockItemId: existing.id,
                unit: unit.unit,
                baseUnitMultiplier: unit.baseUnitMultiplier,
              })),
            });
          }
        }

        const wasActive = existing.isActive;
        const updated = await tx.stockItem.update({
          where: { id: existing.id },
          data,
          include: {
            supplierProducts: true,
            purchaseUnits: { orderBy: { unit: 'asc' } },
          },
        });
        await this.audit(tx, actor, {
          action:
            wasActive && updated.isActive === false
              ? InventoryAuditAction.STOCK_ITEM_DISABLED
              : InventoryAuditAction.STOCK_ITEM_UPDATED,
          entityType: 'STOCK_ITEM',
          entityId: updated.id,
          data: {
            stockItemId: updated.id,
            name: updated.name,
            changes,
          },
        });
        return this.presentStockItem(
          updated,
          (await this.currentStock(actor.venueId, [existing.id])).get(
            existing.id,
          ),
        );
      });
    } catch (error) {
      rethrowInventoryConstraint(error);
    }
  }

  async createSupplier(actor: InventoryActor, input: SupplierInput) {
    const data = {
      venueId: actor.venueId,
      name: requiredText(input.name, 'name'),
      taxId: optionalText(input.taxId),
      phone: optionalText(input.phone),
      email: optionalEmail(input.email),
      address: optionalText(input.address),
      notes: optionalText(input.notes),
      isActive: optionalBoolean(input.isActive, true, 'isActive'),
    };
    const created = await this.prisma.$transaction(async (tx) => {
      const row = await tx.supplier.create({ data });
      await this.audit(tx, actor, {
        action: InventoryAuditAction.SUPPLIER_CREATED,
        entityType: 'SUPPLIER',
        entityId: row.id,
        data: {
          supplierId: row.id,
          name: row.name,
          isActive: row.isActive,
          populatedContactFields: contactFields(row),
        },
      });
      return row;
    });
    return this.presentSupplier(created);
  }

  async updateSupplier(
    actor: InventoryActor,
    id: string,
    input: SupplierInput,
  ) {
    const cleanId = requiredText(id, 'id');
    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.supplier.findFirst({
        where: { id: cleanId, venueId: actor.venueId },
      });
      if (!existing) throw new NotFoundException('Supplier not found');

      const data: Record<string, unknown> = {};
      const changes: Change[] = [];
      assignChange(data, changes, 'name', existing.name, input, requiredText);
      for (const field of ['taxId', 'phone', 'address', 'notes'] as const) {
        assignPrivateChange(data, changes, field, existing[field], input);
      }
      if (has(input, 'email')) {
        const next = optionalEmail(input.email);
        if (next !== existing.email) {
          data.email = next;
          changes.push({
            field: 'email',
            previousValue: existing.email != null,
            newValue: next != null,
          });
        }
      }
      if (has(input, 'isActive')) {
        const next = requiredBoolean(input.isActive, 'isActive');
        if (next !== existing.isActive) {
          data.isActive = next;
          changes.push({
            field: 'isActive',
            previousValue: existing.isActive,
            newValue: next,
          });
        }
      }
      if (changes.length === 0) return this.presentSupplier(existing);

      const wasActive = existing.isActive;
      const updated = await tx.supplier.update({
        where: { id: existing.id },
        data,
      });
      await this.audit(tx, actor, {
        action:
          wasActive && updated.isActive === false
            ? InventoryAuditAction.SUPPLIER_DISABLED
            : InventoryAuditAction.SUPPLIER_UPDATED,
        entityType: 'SUPPLIER',
        entityId: updated.id,
        data: { supplierId: updated.id, name: updated.name, changes },
      });
      return this.presentSupplier(updated);
    });
  }

  async addSuppliedItem(actor: InventoryActor, supplierId: string, input: any) {
    const mode = input.mode;
    if (!['menu', 'ingredient', 'bulk', 'existing'].includes(mode))
      throw new BadRequestException('Invalid supplied item mode');
    return this.prisma.$transaction(async (tx) => {
      const supplier = await tx.supplier.findFirst({
        where: { id: supplierId, venueId: actor.venueId, isActive: true },
      });
      if (!supplier) throw new NotFoundException('Supplier not found');
      const menuId =
        mode === 'menu' ? requiredText(input.menuItemId, 'menuItemId') : null;
      if (menuId)
        await tx.$queryRaw`SELECT id FROM pos."MenuItem" WHERE id=${menuId} AND "venueId"=${actor.venueId} FOR UPDATE`;
      const menu = menuId
        ? await tx.menuItem.findFirst({
            where: { id: menuId, venueId: actor.venueId },
            include: { variants: true, category: true, subcategory: true },
          })
        : null;
      if (menuId && !menu) throw new NotFoundException('Menu item not found');
      const variantId = optionalText(input.variantId);
      if (menu && variantId && !menu.variants.some((v) => v.id === variantId))
        throw new NotFoundException('Menu variant not found');
      if (menu && menu.variants.length && !variantId)
        throw new BadRequestException('Select the Menu variant');
      const recipe = menu
        ? await tx.menuConsumptionRecipe.findFirst({
            where: {
              venueId: actor.venueId,
              menuItemId: menu.id,
              variantKey: variantId ?? '',
            },
            include: { components: true },
          })
        : null;
      if (
        recipe &&
        (!recipe.isActive ||
          recipe.components.length !== 1 ||
          !recipe.components[0].baseQuantityPerUnit.eq(1) ||
          !['piece', 'bottle'].includes(recipe.components[0].baseUnit))
      )
        throw new BadRequestException(
          'This Menu item has a recipe; use its existing ingredients or edit the recipe explicitly',
        );
      const requestId =
        input.requestId == null
          ? null
          : requiredText(input.requestId, 'requestId');
      if (requestId && !/^[0-9a-f-]{36}$/i.test(requestId))
        throw new BadRequestException('requestId must be UUID');
      if (requestId)
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${actor.venueId + ':item:' + requestId},0))`;
      const previous = requestId
        ? await tx.stockItem.findUnique({
            where: {
              venueId_creationRequestId: {
                venueId: actor.venueId,
                creationRequestId: requestId,
              },
            },
          })
        : null;
      if (
        recipe &&
        input.stockItemId &&
        recipe.components[0].stockItemId !== input.stockItemId
      )
        throw new BadRequestException('Menu already linked to different stock');
      const stockId =
        previous?.id ??
        recipe?.components[0].stockItemId ??
        (input.stockItemId
          ? requiredText(input.stockItemId, 'stockItemId')
          : null);
      let item = stockId
        ? await tx.stockItem.findFirst({
            where: { id: stockId, venueId: actor.venueId, isActive: true },
          })
        : null;
      if (stockId && !item) throw new NotFoundException('Stock item not found');
      if (mode === 'existing' && !item)
        throw new BadRequestException('Choose an inventory item');
      const baseUnit = menu
        ? 'piece'
        : mode === 'bulk'
          ? 'L'
          : stockBaseUnit(input.baseUnit ?? 'kg');
      if (
        previous &&
        (previous.name !== (menu?.nameKa ?? input.name?.trim()) ||
          previous.baseUnit !== baseUnit)
      )
        throw new BadRequestException(
          'Creation request already used for different goods',
        );
      if (menu && item && !['piece', 'bottle'].includes(item.baseUnit))
        throw new BadRequestException('Direct Menu goods require piece stock');
      if (!item) {
        item = await tx.stockItem.create({
          data: {
            creationRequestId: requestId,
            venueId: actor.venueId,
            name: menu?.nameKa ?? requiredText(input.name, 'name'),
            baseUnit,
            classification:
              mode === 'bulk' ||
              menuGroup([
                menu?.category?.nameKa,
                menu?.category?.nameEn,
                menu?.subcategory?.nameKa,
                menu?.subcategory?.nameEn,
              ]) === 'BEVERAGE'
                ? 'BEVERAGE'
                : 'FOOD',
          },
        });
        await writeInventoryAudit(tx, actor, {
          action: 'STOCK_ITEM_CREATED',
          entityType: 'STOCK_ITEM',
          entityId: item.id,
          data: { name: item.name, baseUnit: item.baseUnit },
        });
      }
      if (input.purchaseUnits != null) {
        const units = readPurchaseUnits(input.purchaseUnits, item.baseUnit);
        for (const unit of units) {
          const old = await tx.stockItemPurchaseUnit.findUnique({
            where: {
              stockItemId_unit: { stockItemId: item.id, unit: unit.unit },
            },
          });
          if (old && !old.baseUnitMultiplier.eq(unit.baseUnitMultiplier))
            throw new BadRequestException(
              'Packaging differs from existing item; edit packaging explicitly',
            );
          if (!old)
            await tx.stockItemPurchaseUnit.create({
              data: { venueId: actor.venueId, stockItemId: item.id, ...unit },
            });
        }
      }
      const linked = await tx.supplierProduct.createMany({
        data: [{ venueId: actor.venueId, supplierId, stockItemId: item.id }],
        skipDuplicates: true,
      });
      if (menu && !recipe)
        await this.recipes.save(
          actor,
          {
            menuItemId: menu.id,
            variantId,
            yieldQuantity: '1',
            components: [
              { stockItemId: item.id, quantity: '1', unit: item.baseUnit },
            ],
          },
          tx,
        );
      if (linked.count)
        await writeInventoryAudit(tx, actor, {
          action: 'SUPPLIER_ITEM_LINKED',
          entityType: 'SUPPLIER',
          entityId: supplierId,
          data: { stockItemId: item.id, menuItemId: menu?.id ?? null },
        });
      return { stockItemId: item.id, menuItemId: menu?.id ?? null };
    });
  }

  async supplierDetail(tenant: TenantContext, id: string) {
    const supplier = await this.prisma.supplier.findFirst({
      where: { venueId: tenant.venueId, id },
    });
    if (!supplier) throw new NotFoundException('Supplier not found');
    const [links, recentReceivings] = await Promise.all([
      this.prisma.supplierProduct.findMany({
        where: { venueId: tenant.venueId, supplierId: id },
        include: { stockItem: { include: { purchaseUnits: true } } },
      }),
      this.prisma.receiving.findMany({
        where: { venueId: tenant.venueId, supplierId: id },
        orderBy: [{ businessDate: 'desc' }, { createdAt: 'desc' }],
        take: 20,
        select: {
          id: true,
          businessDate: true,
          supplierNameSnapshot: true,
          status: true,
          documentTotal: true,
        },
      }),
    ]);
    return {
      ...this.presentSupplier(supplier),
      settlement: await new SupplierPayments(this.prisma).list(tenant, id),
      products: links.map((link) => ({
        id: link.stockItem.id,
        name: link.stockItem.name,
        classification: link.stockItem.classification,
        baseUnit: link.stockItem.baseUnit,
        purchaseUnits: link.stockItem.purchaseUnits.map((u) => ({
          unit: u.unit,
          baseUnitMultiplier: u.baseUnitMultiplier.toString(),
        })),
      })),
      recentReceivings: recentReceivings.map((row) => ({
        ...row,
        documentTotal: row.documentTotal.toFixed(2),
      })),
    };
  }

  async setSupplierProduct(
    actor: InventoryActor,
    supplierId: string,
    stockItemId: string,
    linked: boolean,
  ) {
    return this.prisma.$transaction(async (tx) => {
      const supplier = await tx.supplier.findFirst({
        where: { venueId: actor.venueId, id: supplierId },
      });
      const item = await tx.stockItem.findFirst({
        where: { venueId: actor.venueId, id: stockItemId },
      });
      if (!supplier || !item)
        throw new NotFoundException('Supplier or stock item not found');
      // Serialize catalog edits for this item, including full replacement in its editor.
      await tx.$queryRaw`SELECT id FROM pos."StockItem" WHERE id = ${stockItemId} AND "venueId" = ${actor.venueId} FOR UPDATE`;
      const key = { venueId: actor.venueId, supplierId, stockItemId };
      const changed = linked
        ? (
            await tx.supplierProduct.createMany({
              data: [key],
              skipDuplicates: true,
            })
          ).count
        : (await tx.supplierProduct.deleteMany({ where: key })).count;
      if (changed)
        await writeInventoryAudit(tx, actor, {
          action: linked ? 'SUPPLIER_ITEM_LINKED' : 'SUPPLIER_ITEM_UNLINKED',
          entityType: 'SUPPLIER',
          entityId: supplierId,
          data: {
            supplierId,
            supplierName: supplier.name,
            stockItemId,
            stockItemName: item.name,
          },
        });
      return { linked };
    });
  }

  private async replaceSuppliers(
    tx: Prisma.TransactionClient,
    actor: InventoryActor,
    stockItemId: string,
    raw: unknown,
  ) {
    if (
      !Array.isArray(raw) ||
      raw.length > 100 ||
      raw.some((id) => typeof id !== 'string')
    )
      throw new BadRequestException('supplierIds must be a list of IDs');
    const ids = [...new Set(raw as string[])].sort();
    const suppliers = await tx.supplier.findMany({
      where: { venueId: actor.venueId, id: { in: ids } },
    });
    if (suppliers.length !== ids.length)
      throw new NotFoundException('Supplier not found');
    await tx.$queryRaw`SELECT id FROM pos."StockItem" WHERE id = ${stockItemId} AND "venueId" = ${actor.venueId} FOR UPDATE`;
    const before = (
      await tx.supplierProduct.findMany({
        where: { venueId: actor.venueId, stockItemId },
      })
    )
      .map((link) => link.supplierId)
      .sort();
    if (JSON.stringify(before) === JSON.stringify(ids)) return;
    await tx.supplierProduct.deleteMany({
      where: { venueId: actor.venueId, stockItemId },
    });
    await tx.supplierProduct.createMany({
      data: ids.map((supplierId) => ({
        venueId: actor.venueId,
        stockItemId,
        supplierId,
      })),
    });
    await writeInventoryAudit(tx, actor, {
      action: 'STOCK_ITEM_SUPPLIERS_UPDATED',
      entityType: 'STOCK_ITEM',
      entityId: stockItemId,
      data: { stockItemId, previousSupplierIds: before, supplierIds: ids },
    });
  }

  private presentStockItem(row: any, balance?: Prisma.Decimal) {
    const currentStock = new Prisma.Decimal(balance ?? 0);
    const minimum =
      row.minimumStock == null ? null : new Prisma.Decimal(row.minimumStock);
    const isLowStock =
      minimum != null && currentStock.lessThanOrEqualTo(minimum);
    return {
      id: row.id,
      name: row.name,
      sku: row.sku,
      classification: row.classification,
      supplierIds: (row.supplierProducts ?? []).map(
        (link: any) => link.supplierId,
      ),
      baseUnit: row.baseUnit,
      minimumStock: decimalText(row.minimumStock),
      isActive: row.isActive,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      // Derived from StockMovement on every read. Never a stored balance.
      currentStock: stockQuantityText(currentStock),
      stockStatus: currentStock.isNegative()
        ? 'NEGATIVE'
        : minimum == null
          ? 'NO_MINIMUM'
          : isLowStock
            ? 'LOW'
            : 'OK',
      isLowStock,
      purchaseUnits: (row.purchaseUnits ?? []).map((unit: any) => ({
        id: unit.id,
        unit: unit.unit,
        baseUnitMultiplier: multiplierText(unit.baseUnitMultiplier),
      })),
      // What a recipe may legitimately be written in for this item. One
      // authority for the rule, so the Manager editor cannot offer `box`.
      recipeUnits: recipeUnitsFor(row.baseUnit),
    };
  }

  private presentSupplier(row: any) {
    return {
      id: row.id,
      name: row.name,
      taxId: row.taxId,
      phone: row.phone,
      email: row.email,
      address: row.address,
      notes: row.notes,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private audit(
    tx: Prisma.TransactionClient,
    actor: InventoryActor,
    event: {
      action: string;
      entityType: 'STOCK_ITEM' | 'SUPPLIER';
      entityId: string;
      data: Record<string, unknown>;
    },
  ) {
    return writeInventoryAudit(tx, actor, event);
  }
}

function has(input: object, field: string): boolean {
  return Object.prototype.hasOwnProperty.call(input, field);
}

function requiredText(raw: unknown, field: string): string {
  const value = typeof raw === 'string' ? raw.trim() : '';
  if (!value) throw new BadRequestException(`${field} is required`);
  if (value.length > 500) {
    throw new BadRequestException(`${field} is too long`);
  }
  return value;
}

function optionalText(raw: unknown): string | null {
  if (raw == null) return null;
  if (typeof raw !== 'string') throw new BadRequestException('Expected text');
  const value = raw.trim();
  if (value.length > 2000) throw new BadRequestException('Text is too long');
  return value || null;
}

function optionalSku(raw: unknown): string | null {
  const value = optionalText(raw);
  if (value == null) return null;
  if (value.length > 100) throw new BadRequestException('sku is too long');
  return value.toUpperCase();
}

function optionalEmail(raw: unknown): string | null {
  const value = optionalText(raw);
  if (value == null) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    throw new BadRequestException('email is invalid');
  }
  return value;
}

function optionalQuantity(raw: unknown, field: string): Prisma.Decimal | null {
  if (raw == null || raw === '') return null;
  const text = String(raw).trim();
  if (!/^\d+(?:\.\d{1,3})?$/.test(text)) {
    throw new BadRequestException(
      `${field} must be a non-negative number with up to 3 decimals`,
    );
  }
  const value = new Prisma.Decimal(text);
  if (value.isNegative()) {
    throw new BadRequestException(`${field} must not be negative`);
  }
  return value;
}

function optionalBoolean(
  raw: unknown,
  fallback: boolean,
  field: string,
): boolean {
  if (raw == null) return fallback;
  return requiredBoolean(raw, field);
}

function requiredBoolean(raw: unknown, field: string): boolean {
  if (typeof raw !== 'boolean') {
    throw new BadRequestException(`${field} must be boolean`);
  }
  return raw;
}

function decimalText(value: unknown): string | null {
  if (value == null) return null;
  return new Prisma.Decimal(value as any).toFixed(3);
}

function assignChange(
  data: Record<string, unknown>,
  changes: Change[],
  field: string,
  previous: unknown,
  input: object,
  normalize: (raw: unknown, field: string) => unknown,
) {
  if (!has(input, field)) return;
  const next = normalize((input as Record<string, unknown>)[field], field);
  if (next === previous) return;
  data[field] = next;
  changes.push({ field, previousValue: previous, newValue: next });
}

function assignPrivateChange(
  data: Record<string, unknown>,
  changes: Change[],
  field: string,
  previous: unknown,
  input: object,
) {
  if (!has(input, field)) return;
  const next = optionalText((input as Record<string, unknown>)[field]);
  if (next === previous) return;
  data[field] = next;
  changes.push({
    field,
    previousValue: previous != null,
    newValue: next != null,
  });
}

function contactFields(row: Record<string, unknown>): string[] {
  return ['taxId', 'phone', 'email', 'address', 'notes'].filter(
    (field) => row[field] != null,
  );
}

/**
 * The packaging rows a Stock Item declares, validated as a set.
 *
 * A ratio for the item's own base unit is refused rather than stored as 1: it
 * would be a second, silently authoritative answer to a question the base unit
 * already settles.
 */
function readPurchaseUnits(
  raw: unknown,
  baseUnit: string,
): { unit: InventoryUnit; baseUnitMultiplier: Prisma.Decimal }[] {
  if (raw == null) return [];
  if (!Array.isArray(raw)) {
    throw new BadRequestException('purchaseUnits must be an array');
  }
  if (raw.length > 8) {
    throw new BadRequestException(
      'A Stock Item may hold up to 8 purchase units',
    );
  }
  const seen = new Set<string>();
  return raw.map((entry) => {
    const row = (entry ?? {}) as PurchaseUnitInput;
    const unit = inventoryUnit(row.unit);
    if (unit === baseUnit) {
      throw new BadRequestException(
        `${unit} is this item's base unit and needs no purchase ratio`,
      );
    }
    if (seen.has(unit)) {
      throw new BadRequestException(`purchase unit ${unit} is listed twice`);
    }
    seen.add(unit);
    return {
      unit,
      baseUnitMultiplier: positiveMultiplier(
        row.baseUnitMultiplier,
        `purchaseUnits.${unit}.baseUnitMultiplier`,
      ),
    };
  });
}

/** `box=24, pack=6` — stable text so an audit change reads as one value. */
function purchaseUnitSummary(
  rows: readonly { unit: string; baseUnitMultiplier: unknown }[],
): string {
  return rows
    .map((row) => `${row.unit}=${multiplierText(row.baseUnitMultiplier)}`)
    .sort()
    .join(', ');
}

function rethrowInventoryConstraint(error: unknown): never {
  if (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
  ) {
    throw new ConflictException('SKU already exists in this Venue');
  }
  throw error;
}

function classification(raw: unknown): StockItemClassification {
  if (raw === 'FOOD' || raw === 'BEVERAGE') return raw;
  throw new BadRequestException('classification must be FOOD or BEVERAGE');
}

function stockBaseUnit(raw: unknown): InventoryUnit {
  const unit = inventoryUnit(raw);
  if (unit === 'keg')
    throw new BadRequestException(
      'keg is a purchase package; use L as the base unit',
    );
  return unit;
}
