import { createHash } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { stockQuantityText } from './inventory-quantity';
import {
  InventoryAuditAction,
  writeInventoryAudit,
  type InventoryActor,
} from './inventory-audit';

export interface StockLocationInput {
  requestId?: unknown;
  name?: unknown;
}

function locationName(raw: unknown): string {
  if (typeof raw !== 'string' || !raw.trim() || raw.trim().length > 200)
    throw new BadRequestException('Location name must be 1–200 characters');
  return raw.trim();
}

/** Membership comes from the authenticated principal, never a body Venue ID. */
export async function requireStockLocation(
  tx: Prisma.TransactionClient,
  tenant: TenantContext,
  raw: unknown,
): Promise<string> {
  if (typeof raw !== 'string' || !raw.trim())
    throw new BadRequestException('locationId is required');
  const location = await tx.stockLocation.findFirst({
    where: { id: raw.trim(), venueId: tenant.venueId },
    select: { id: true },
  });
  if (!location) throw new NotFoundException('Stock location not found');
  return location.id;
}

/** Quantity locations share the existing Venue-wide valuation basis (D015).
 * No balance is editable; every quantity is derived from StockMovement. */
export class StockLocations {
  constructor(private readonly prisma: PrismaService) {}

  list(tenant: TenantContext) {
    return this.prisma.stockLocation.findMany({
      where: { venueId: tenant.venueId },
      orderBy: [{ isDefault: 'desc' }, { name: 'asc' }, { id: 'asc' }],
      select: {
        id: true,
        name: true,
        isDefault: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  async create(actor: InventoryActor, input: StockLocationInput) {
    const name = locationName(input.name);
    const rawRequestId = input.requestId;
    if (
      typeof rawRequestId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        rawRequestId,
      )
    )
      throw new BadRequestException('requestId must be UUID');
    const requestId = rawRequestId.toLowerCase();
    const fingerprint = createHash('sha256').update(name).digest('hex');
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${actor.venueId + ':stock-location:' + requestId}, 0))`;
      const prior = await tx.stockLocation.findUnique({
        where: {
          venueId_creationRequestId: {
            venueId: actor.venueId,
            creationRequestId: requestId,
          },
        },
      });
      if (prior) {
        if (prior.creationFingerprint !== fingerprint)
          throw new ConflictException(
            'Location request reused with different values',
          );
        return { id: prior.id, name: prior.name, isDefault: prior.isDefault };
      }
      const location = await tx.stockLocation.create({
        data: {
          venueId: actor.venueId,
          name,
          creationRequestId: requestId,
          creationFingerprint: fingerprint,
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.STOCK_LOCATION_CREATED,
        entityType: 'STOCK_LOCATION',
        entityId: location.id,
        data: { name, requestId },
      });
      return {
        id: location.id,
        name: location.name,
        isDefault: location.isDefault,
      };
    });
  }

  async rename(actor: InventoryActor, id: string, input: StockLocationInput) {
    const name = locationName(input.name);
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."StockLocation" WHERE id=${id} AND "venueId"=${actor.venueId} FOR UPDATE`;
      const existing = await tx.stockLocation.findFirst({
        where: { id, venueId: actor.venueId },
      });
      if (!existing) throw new NotFoundException('Stock location not found');
      if (existing.name !== name) {
        await tx.stockLocation.update({ where: { id }, data: { name } });
        await writeInventoryAudit(tx, actor, {
          action: InventoryAuditAction.STOCK_LOCATION_RENAMED,
          entityType: 'STOCK_LOCATION',
          entityId: id,
          data: { previousName: existing.name, name },
        });
      }
      return { id, name, isDefault: existing.isDefault };
    });
  }

  itemBalances(tenant: TenantContext, stockItemId: string) {
    return this.prisma.$transaction(
      async (tx) => {
        const item = await tx.stockItem.findFirst({
          where: { id: stockItemId, venueId: tenant.venueId },
          select: { id: true, baseUnit: true },
        });
        if (!item) throw new NotFoundException('Stock item not found');
        const locations = await tx.stockLocation.findMany({
          where: { venueId: tenant.venueId },
          orderBy: [{ isDefault: 'desc' }, { name: 'asc' }, { id: 'asc' }],
          select: { id: true, name: true, isDefault: true },
        });
        const movements = await tx.stockMovement.groupBy({
          by: ['locationId'],
          where: { venueId: tenant.venueId, stockItemId },
          _sum: { quantityDeltaBase: true },
        });
        const quantities = new Map(
          movements.map((m) => [
            m.locationId,
            new Prisma.Decimal(m._sum.quantityDeltaBase ?? 0),
          ]),
        );
        return {
          stockItemId,
          baseUnit: item.baseUnit,
          source: 'STOCK_MOVEMENT_LEDGER',
          venueQuantity: stockQuantityText(
            movements.reduce(
              (sum, m) => sum.plus(m._sum.quantityDeltaBase ?? 0),
              new Prisma.Decimal(0),
            ),
          ),
          locations: locations.map((location) => ({
            ...location,
            quantity: stockQuantityText(
              quantities.get(location.id) ?? new Prisma.Decimal(0),
            ),
          })),
        };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );
  }
}
