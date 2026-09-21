import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';

// Local Decimal constructor: do not change Prisma's process-wide configuration.
const Exact = Prisma.Decimal.clone({
  precision: 60,
  rounding: Prisma.Decimal.ROUND_HALF_UP,
});

/** Current value comes from frozen movement values, including consumption. */
export class InventoryCostService {
  constructor(private readonly prisma: PrismaService) {}
  async bases(tenant: TenantContext, ids: string[]) {
    const rows = await this.prisma.stockMovement.findMany({
      where: { venueId: tenant.venueId, stockItemId: { in: ids } },
      orderBy: { valuationSequence: 'asc' },
      include: { receiving: { select: { status: true } } },
    });
    const grouped = new Map<
      string,
      {
        quantity: Prisma.Decimal;
        value: Prisma.Decimal;
        unit: string;
        last: string | null;
        cost: Prisma.Decimal | null;
        provisional: boolean;
        hasPurchase: boolean;
      }
    >();
    for (const row of rows) {
      const key = row.stockItemId + ':' + row.baseUnit;
      const g = grouped.get(key) ?? {
        quantity: new Exact(0),
        value: new Exact(0),
        unit: row.baseUnit,
        last: null,
        cost: null,
        provisional: false,
        hasPurchase: false,
      };
      g.quantity = g.quantity.plus(row.quantityDeltaBase.toString());
      g.value = g.value.plus(row.inventoryValueDelta?.toString() ?? '0');
      if (
        row.movementType === 'RECEIVING' &&
        row.receiving?.status !== 'CANCELLED'
      )
        g.hasPurchase = true;
      if (
        row.movementType === 'RECEIVING' &&
        row.receiving?.status !== 'CANCELLED'
      )
        g.last = row.costPerBaseUnit?.toFixed(6) ?? null;
      if (row.costPerBaseUnit != null)
        g.cost = new Exact(row.costPerBaseUnit.toString());
      if (
        row.valuationStatus === 'PROVISIONAL' ||
        row.inventoryValueDelta == null
      )
        g.provisional = true;
      grouped.set(key, g);
    }
    for (const g of grouped.values()) {
      if (g.quantity.gt(0) && g.value.gte(0)) g.cost = g.value.div(g.quantity);
      if (!g.hasPurchase && g.quantity.isZero()) g.cost = null;
      if (g.quantity.lt(0) || g.value.lt(0)) g.provisional = true;
    }
    return grouped;
  }

  async stockItem(tenant: TenantContext, id: string) {
    const item = await this.prisma.stockItem.findFirst({
      where: { id, venueId: tenant.venueId },
    });
    if (!item) throw new NotFoundException('Stock item not found');
    const group = (await this.bases(tenant, [id])).get(
      id + ':' + item.baseUnit,
    );
    return {
      method: 'MOVING_WEIGHTED_AVERAGE',
      status: group?.provisional
        ? 'PROVISIONAL'
        : group?.cost != null
          ? 'AVAILABLE'
          : 'NO_PURCHASE_HISTORY',
      baseUnit: item.baseUnit,
      weightedUnitCost: group?.cost?.toFixed(6) ?? null,
      lastPurchaseUnitCost: group?.last ?? null,
      currentQuantity: group?.quantity.toFixed(6) ?? '0.000000',
      inventoryValue: group?.value.toFixed(12) ?? '0.000000000000',
      purchaseQuantity: group?.quantity.toFixed(3) ?? '0.000',
      purchaseValue: group?.value.toFixed(2) ?? '0.00',
    };
  }

  async recipe(
    tenant: TenantContext,
    recipe: {
      isActive: boolean;
      components: {
        stockItemId: string;
        stockItemNameSnapshot: string;
        baseUnit: string;
        baseQuantityPerUnit: Prisma.Decimal;
      }[];
    } | null,
  ) {
    if (!recipe || !recipe.isActive)
      return { status: 'NO_ACTIVE_RECIPE', total: null, components: [] };
    const bases = await this.bases(
      tenant,
      recipe.components.map((c) => c.stockItemId),
    );
    let total = new Exact(0);
    let complete = true;
    const components = recipe.components.map((component) => {
      const group = bases.get(component.stockItemId + ':' + component.baseUnit);
      const unitCost = group?.provisional ? null : (group?.cost ?? null);
      const cost =
        unitCost?.times(component.baseQuantityPerUnit.toString()) ?? null;
      if (cost == null) complete = false;
      else total = total.plus(cost);
      return {
        stockItemId: component.stockItemId,
        stockItemName: component.stockItemNameSnapshot,
        baseUnit: component.baseUnit,
        quantity: component.baseQuantityPerUnit.toFixed(6),
        weightedUnitCost: unitCost?.toFixed(6) ?? null,
        cost: cost?.toFixed(6) ?? null,
        status: cost == null ? 'NO_PURCHASE_HISTORY' : 'AVAILABLE',
      };
    });
    return {
      method: 'MOVING_WEIGHTED_AVERAGE',
      status: complete ? 'AVAILABLE' : 'MISSING_COMPONENT_COST',
      total: complete ? total.toFixed(2) : null,
      totalExact: complete ? total.toFixed(12) : null,
      components,
    };
  }
}
