import { withOperationalAuthority } from '../edge/operational-authority';
import type { EdgeDeviceContext } from '../edge/edge-device-context';
import { presentMovement } from './receiving.service';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';

function object(raw: unknown): Record<string, any> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    throw new BadRequestException('Inventory object required');
  return raw as Record<string, any>;
}
function text(raw: unknown, field: string): string {
  if (typeof raw !== 'string' || !raw.trim() || raw.length > 500)
    throw new BadRequestException(`Invalid ${field}`);
  return raw;
}
function integer(raw: unknown, field: string, min = 1): number {
  if (
    !Number.isSafeInteger(raw) ||
    (raw as number) < min ||
    (raw as number) > 2147483647
  )
    throw new BadRequestException(`Invalid ${field}`);
  return raw as number;
}
function instant(raw: unknown): Date {
  const date = new Date(text(raw, 'timestamp'));
  if (!Number.isFinite(date.getTime()))
    throw new BadRequestException('Invalid timestamp');
  return date;
}
function exact(raw: unknown): Prisma.Decimal {
  if (typeof raw !== 'string' || !/^\d{1,15}\.\d{6}$/.test(raw))
    throw new BadRequestException(
      'Inventory quantity requires six decimal places',
    );
  const value = new Prisma.Decimal(raw);
  if (!value.isPositive())
    throw new BadRequestException('Consumption quantity must be positive');
  return value;
}
function canonical(value: any): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object')
    return `{${Object.keys(value)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`)
      .join(',')}}`;
  return JSON.stringify(value);
}

/** Device -> Venue writes; Cloud is the only StockMovement authority. Each
 * snapshot + complete movement set + optional reversal commits atomically. */
@Injectable()
export class SaleConsumptionService {
  constructor(private readonly prisma: PrismaService) {}

  applyFromDevice(device: EdgeDeviceContext, raw: unknown) {
    return withOperationalAuthority(this.prisma, device, (db) =>
      new SaleConsumptionService(db).apply(device, raw),
    );
  }

  async apply(tenant: TenantContext, raw: unknown) {
    const body = object(raw);
    const posSaleId = text(body.posSaleId, 'posSaleId');
    const closureId = text(body.closureId, 'closureId');
    const orderId = integer(body.orderId, 'orderId');
    const businessDate = text(body.businessDate, 'businessDate');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(businessDate))
      throw new BadRequestException('Invalid businessDate');
    const closedAt = instant(body.closedAt);
    const reversedAt =
      body.reversedAt == null ? null : instant(body.reversedAt);
    if (reversedAt && reversedAt < closedAt)
      throw new BadRequestException('Restore predates close');
    const restoreBusinessDate = reversedAt
      ? text(
          body.restoreBusinessDate ?? reversedAt.toISOString().slice(0, 10),
          'restoreBusinessDate',
        )
      : null;
    if (restoreBusinessDate && !/^\d{4}-\d{2}-\d{2}$/.test(restoreBusinessDate))
      throw new BadRequestException('Invalid restoreBusinessDate');
    const snapshot = object(body.snapshot);
    if (
      snapshot.version !== 1 ||
      !['FISCAL_CLOSE', 'INTERNAL_EXCLUDED'].includes(snapshot.policy) ||
      !Array.isArray(snapshot.lines) ||
      snapshot.lines.length > 2000
    )
      throw new BadRequestException('Invalid consumption snapshot');
    if (snapshot.catalogGeneratedAt != null)
      instant(snapshot.catalogGeneratedAt);
    const frozen = {
      posSaleId,
      closureId,
      orderId,
      businessDate,
      closedAt: closedAt.toISOString(),
      snapshot,
    };
    return this.prisma.$transaction(
      async (tx) => {
        // Serialize the same durable identity across devices/processes, including
        // its first insertion; timestamps are never idempotency keys.
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${tenant.venueId + ':' + posSaleId}, 0))`;
        const itemIds: string[] = [
          ...new Set<string>(
            snapshot.lines.flatMap((l: any) =>
              l.components.map((c: any) => String(c.stockItemId)),
            ),
          ),
        ].sort();
        if (itemIds.length)
          await tx.$queryRaw(
            Prisma.sql`SELECT id FROM pos."StockItem" WHERE "venueId"=${tenant.venueId} AND id IN (${Prisma.join(itemIds)}) ORDER BY id FOR UPDATE`,
          );
        let stored = await tx.saleConsumption.findUnique({
          where: { venueId_posSaleId: { venueId: tenant.venueId, posSaleId } },
        });
        if (stored && canonical(stored.snapshot) !== canonical(frozen))
          throw new ConflictException('Consumption snapshot is immutable');
        if (!stored) {
          const sequences = new Set<number>();
          // Validate every reference before any movement. Old revisions are
          // intentionally accepted: offline snapshots are historical definitions.
          for (const rawLine of snapshot.lines) {
            const line = object(rawLine);
            const seq = integer(line.lineSeq, 'lineSeq', 0);
            if (sequences.has(seq))
              throw new BadRequestException('Duplicate source line');
            sequences.add(seq);
            integer(line.soldQuantity, 'soldQuantity');
            text(line.itemName, 'itemName');
            for (const field of ['menuItemId', 'variantId', 'variantName'])
              if (line[field] != null) text(line[field], field);
            if (!Array.isArray(line.components) || line.components.length > 500)
              throw new BadRequestException('Invalid components');
            if (snapshot.policy === 'INTERNAL_EXCLUDED') {
              if (
                line.status !== 'EXCLUDED' ||
                line.reason !== 'INTERNAL_POLICY'
              )
                throw new BadRequestException(
                  'Internal consumption is excluded',
                );
            } else if (!['MAPPED', 'UNMAPPED'].includes(line.status))
              throw new BadRequestException('Invalid line status');
            if (line.status !== 'MAPPED') {
              if (
                line.components.length ||
                line.recipeId != null ||
                line.recipeRevision != null
              )
                throw new BadRequestException(
                  'Unmapped/excluded lines cannot consume',
                );
              if (
                ![
                  'INTERNAL_POLICY',
                  'MANUAL_LINE',
                  'NO_ACTIVE_RECIPE',
                  'INVALID_LOCAL_RECIPE',
                ].includes(line.reason)
              )
                throw new BadRequestException('Invalid unmapped reason');
              continue;
            }
            text(line.menuItemId, 'mapped menuItemId');
            integer(line.recipeRevision, 'recipeRevision');
            const recipe = await tx.menuConsumptionRecipe.findFirst({
              where: {
                id: text(line.recipeId, 'recipeId'),
                venueId: tenant.venueId,
              },
              include: { menuItem: true, variant: true },
            });
            if (
              !recipe ||
              recipe.menuItem.posMenuItemId !== line.menuItemId ||
              (recipe.variant?.posMenuVariantId ?? null) !==
                (line.variantId ?? null) ||
              (line.variantId == null && recipe.variantId != null) ||
              line.recipeRevision > recipe.revision
            )
              throw new BadRequestException(
                'Recipe does not belong to this Venue/product/revision',
              );
            if (!line.components.length)
              throw new BadRequestException('Mapped line needs components');
            const ids = new Set<string>();
            for (const rawComponent of line.components) {
              const c = object(rawComponent);
              const id = text(c.stockItemId, 'stockItemId');
              if (ids.has(id))
                throw new BadRequestException('Duplicate component');
              ids.add(id);
              const stock = await tx.stockItem.findFirst({
                where: { id, venueId: tenant.venueId },
              });
              if (!stock || stock.baseUnit !== c.baseUnit)
                throw new BadRequestException(
                  'Stock item/unit does not belong to this Venue',
                );
              text(c.stockItemName, 'stockItemName');
              const perUnit = exact(c.baseQuantityPerUnit);
              if (
                perUnit.greaterThanOrEqualTo('1000000000000') ||
                !perUnit
                  .times(line.soldQuantity)
                  .equals(exact(c.totalBaseQuantity))
              )
                throw new BadRequestException(
                  'Consumption total must equal per-unit quantity × sold quantity',
                );
            }
          }
          stored = await tx.saleConsumption.create({
            data: {
              venueId: tenant.venueId,
              posSaleId,
              closureId,
              orderId,
              businessDate,
              closedAt,
              catalogGeneratedAt: snapshot.catalogGeneratedAt ?? null,
              policy: snapshot.policy,
              snapshot: frozen as Prisma.InputJsonValue,
            },
          });
          for (const line of snapshot.lines) {
            const created = await tx.saleConsumptionLine.create({
              data: {
                venueId: tenant.venueId,
                consumptionId: stored.id,
                lineSeq: line.lineSeq,
                menuItemId: line.menuItemId ?? null,
                variantId: line.variantId ?? null,
                itemName: line.itemName,
                variantName: line.variantName ?? null,
                soldQuantity: line.soldQuantity,
                status: line.status,
                reason: line.reason ?? null,
                recipeId: line.recipeId ?? null,
                recipeRevision: line.recipeRevision ?? null,
              },
            });
            for (const c of line.components) {
              const component = await tx.saleConsumptionComponent.create({
                data: {
                  venueId: tenant.venueId,
                  lineId: created.id,
                  stockItemId: c.stockItemId,
                  stockItemNameSnapshot: c.stockItemName,
                  baseUnit: c.baseUnit,
                  baseQuantityPerUnit: c.baseQuantityPerUnit,
                  totalBaseQuantity: c.totalBaseQuantity,
                },
              });
              await tx.stockMovement.create({
                data: {
                  venueId: tenant.venueId,
                  stockItemId: c.stockItemId,
                  consumptionComponentId: component.id,
                  movementType: 'CONSUMPTION',
                  quantityDeltaBase: exact(c.totalBaseQuantity).negated(),
                  baseUnit: c.baseUnit,
                  businessDate,
                  effectiveAt: closedAt,
                  actorId: 'POS',
                  actorName: 'POS',
                  source: 'POS',
                  details: {
                    consumptionId: stored.id,
                    posSaleId,
                    closureId,
                    orderId,
                    lineSeq: line.lineSeq,
                  },
                },
              });
            }
          }
        }
        if (reversedAt && !stored.reversedAt) {
          const originals = await tx.stockMovement.findMany({
            where: {
              venueId: tenant.venueId,
              movementType: 'CONSUMPTION',
              consumptionComponent: { line: { consumptionId: stored.id } },
            },
          });
          for (const movement of originals) {
            await tx.stockMovement.create({
              data: {
                venueId: tenant.venueId,
                stockItemId: movement.stockItemId,
                consumptionComponentId: movement.consumptionComponentId,
                movementType: 'CONSUMPTION_REVERSAL',
                reversalOfMovementId: movement.id,
                quantityDeltaBase: movement.quantityDeltaBase.negated(),
                baseUnit: movement.baseUnit,
                businessDate: restoreBusinessDate!,
                effectiveAt: reversedAt,
                actorId: 'POS',
                actorName: 'POS',
                source: 'POS',
                details: {
                  consumptionId: stored.id,
                  posSaleId,
                  closureId,
                  orderId,
                },
              },
            });
          }
          await tx.saleConsumption.update({
            where: { id: stored.id },
            data: { reversedAt },
          });
        }
        // A delayed close ACK never erases a previously applied reversal.
        return { posSaleId, revision: reversedAt ? 2 : 1 };
      },
      { timeout: 30000 },
    );
  }

  async list(
    tenant: TenantContext,
    options: { from?: string; to?: string; unmapped?: string } = {},
  ) {
    return this.prisma.saleConsumption.findMany({
      where: {
        venueId: tenant.venueId,
        businessDate: { gte: options.from, lte: options.to },
        ...(options.unmapped === 'true'
          ? { lines: { some: { status: 'UNMAPPED' } } }
          : {}),
      },
      orderBy: [{ closedAt: 'desc' }, { id: 'desc' }],
      take: 100,
      omit: { snapshot: true },
      include: { lines: { orderBy: { lineSeq: 'asc' } } },
    });
  }

  async detail(tenant: TenantContext, id: string) {
    const row = await this.prisma.saleConsumption.findFirst({
      where: { venueId: tenant.venueId, id },
      include: {
        lines: {
          orderBy: { lineSeq: 'asc' },
          include: { components: { include: { movements: true } } },
        },
      },
    });
    if (!row) throw new NotFoundException('Sale consumption not found');
    return {
      ...row,
      lines: row.lines.map((line) => ({
        ...line,
        components: line.components.map((component) => ({
          ...component,
          movements: component.movements.map(presentMovement),
          baseQuantityPerUnit: component.baseQuantityPerUnit.toFixed(6),
          totalBaseQuantity: component.totalBaseQuantity.toFixed(6),
        })),
      })),
    };
  }
}
