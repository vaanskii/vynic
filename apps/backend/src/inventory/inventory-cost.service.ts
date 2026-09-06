import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';

// Local Decimal constructor: do not change Prisma's process-wide configuration.
const Exact = Prisma.Decimal.clone({
  precision: 60,
  rounding: Prisma.Decimal.ROUND_HALF_UP,
});

/** All currently POSTED procurement, not moving stock valuation or Sale COGS.
 * Cancellation is atomic with reversal, so the entire cancelled receipt is excluded.
 * SUM frozen lineTotal / SUM baseQuantity avoids re-averaging rounded unit costs.
 */
export class InventoryCostService {
  constructor(private readonly prisma: PrismaService) {}

  async bases(tenant: TenantContext, ids: string[]) {
    const rows = await this.prisma.receivingLine.findMany({
      where: {
        stockItemId: { in: ids },
        stockItem: { venueId: tenant.venueId },
        receiving: { venueId: tenant.venueId, status: 'POSTED' },
      },
      orderBy: [
        { receiving: { businessDate: 'desc' } },
        { receiving: { postedAt: 'desc' } },
        { receivingId: 'desc' },
        { lineSequence: 'desc' },
      ],
      select: {
        stockItemId: true,
        baseUnit: true,
        baseQuantity: true,
        lineTotal: true,
        effectiveBaseUnitCost: true,
      },
    });
    const grouped = new Map<
      string,
      {
        quantity: Prisma.Decimal;
        value: Prisma.Decimal;
        unit: string;
        last: string;
      }
    >();
    for (const row of rows) {
      const key = row.stockItemId + ':' + row.baseUnit;
      const group = grouped.get(key) ?? {
        quantity: new Exact(0),
        value: new Exact(0),
        unit: row.baseUnit,
        last: row.effectiveBaseUnitCost.toFixed(6),
      };
      group.quantity = group.quantity.plus(row.baseQuantity.toString());
      group.value = group.value.plus(row.lineTotal.toString());
      grouped.set(key, group);
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
      method: 'POSTED_PURCHASE_WEIGHTED_AVERAGE',
      status: group ? 'AVAILABLE' : 'NO_PURCHASE_HISTORY',
      baseUnit: item.baseUnit,
      weightedUnitCost: group
        ? group.value.div(group.quantity).toFixed(6)
        : null,
      lastPurchaseUnitCost: group?.last ?? null,
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
      const unitCost = group ? group.value.div(group.quantity) : null;
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
      method: 'POSTED_PURCHASE_WEIGHTED_AVERAGE',
      status: complete ? 'AVAILABLE' : 'MISSING_COMPONENT_COST',
      total: complete ? total.toFixed(2) : null,
      totalExact: complete ? total.toFixed(12) : null,
      components,
    };
  }
}
