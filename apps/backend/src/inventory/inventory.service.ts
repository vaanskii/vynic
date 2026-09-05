import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
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
} from './inventory-quantity';
import {
  InventoryAuditAction,
  writeInventoryAudit,
  type InventoryActor,
} from './inventory-audit';
import { presentMovement } from './receiving.service';

export { InventoryAuditAction };

/** How many recent movements a Stock Item detail carries. */
const RECENT_MOVEMENT_LIMIT = 20;

export interface PurchaseUnitInput {
  unit?: unknown;
  baseUnitMultiplier?: unknown;
}

export interface StockItemInput {
  name?: unknown;
  sku?: unknown;
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
  constructor(private readonly prisma: PrismaService) {}

  getUnits() {
    return INVENTORY_UNIT_DEFINITIONS;
  }

  async listStockItems(tenant: TenantContext, search?: string) {
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
      include: { purchaseUnits: { orderBy: { unit: 'asc' } } },
    });
    const balances = await this.currentStock(tenant.venueId);
    return rows.map((row) => this.presentStockItem(row, balances.get(row.id)));
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
      include: { purchaseUnits: { orderBy: { unit: 'asc' } } },
    });
    if (!row) throw new NotFoundException('Stock item not found');
    const [balances, movements] = await Promise.all([
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
    ]);
    return {
      ...this.presentStockItem(row, balances.get(cleanId)),
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
    return rows.map((row) => this.presentSupplier(row));
  }

  /** Complete Device-scoped projection for the POS Hive cache. */
  async getCatalog(tenant: TenantContext) {
    const [stockItems, suppliers] = await Promise.all([
      this.listStockItems(tenant),
      this.listSuppliers(tenant),
    ]);
    return {
      // v2 adds derived current stock and item packaging. An older POS ignores
      // both and keeps working from the fields it already knows.
      version: 2,
      generatedAt: new Date().toISOString(),
      units: INVENTORY_UNIT_DEFINITIONS,
      stockItems,
      suppliers,
    };
  }

  async createStockItem(actor: InventoryActor, input: StockItemInput) {
    const data = {
      venueId: actor.venueId,
      name: requiredText(input.name, 'name'),
      sku: optionalSku(input.sku),
      baseUnit: inventoryUnit(input.baseUnit),
      minimumStock: optionalQuantity(input.minimumStock, 'minimumStock'),
      notes: optionalText(input.notes),
      isActive: optionalBoolean(input.isActive, true, 'isActive'),
    };
    const purchaseUnits = has(input, 'purchaseUnits')
      ? readPurchaseUnits(input.purchaseUnits, data.baseUnit)
      : [];
    try {
      const created = await this.prisma.$transaction(async (tx) => {
        const row = await tx.stockItem.create({
          data: {
            ...data,
            purchaseUnits: {
              create: purchaseUnits.map((unit) => ({
                venueId: actor.venueId,
                unit: unit.unit,
                baseUnitMultiplier: unit.baseUnitMultiplier,
              })),
            },
          },
          include: { purchaseUnits: { orderBy: { unit: 'asc' } } },
        });
        await this.audit(tx, actor, {
          action: InventoryAuditAction.STOCK_ITEM_CREATED,
          entityType: 'STOCK_ITEM',
          entityId: row.id,
          data: {
            stockItemId: row.id,
            name: row.name,
            sku: row.sku,
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
          'baseUnit',
          existing.baseUnit,
          input,
          inventoryUnit,
        );
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
        const baseUnit = (data.baseUnit as string | undefined) ?? existing.baseUnit;
        let nextPurchaseUnits: ReturnType<typeof readPurchaseUnits> | null = null;
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
              include: { purchaseUnits: { orderBy: { unit: 'asc' } } },
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
          include: { purchaseUnits: { orderBy: { unit: 'asc' } } },
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
      baseUnit: row.baseUnit,
      minimumStock: decimalText(row.minimumStock),
      isActive: row.isActive,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      // Derived from StockMovement on every read. Never a stored balance.
      currentStock: quantityText(currentStock),
      stockStatus: minimum == null ? 'NO_MINIMUM' : isLowStock ? 'LOW' : 'OK',
      isLowStock,
      purchaseUnits: (row.purchaseUnits ?? []).map((unit: any) => ({
        id: unit.id,
        unit: unit.unit,
        baseUnitMultiplier: multiplierText(unit.baseUnitMultiplier),
      })),
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
    throw new BadRequestException('A Stock Item may hold up to 8 purchase units');
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
