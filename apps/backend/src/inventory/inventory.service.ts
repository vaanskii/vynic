import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import {
  INVENTORY_UNIT_DEFINITIONS,
  inventoryUnit,
  type InventoryUnit,
} from './inventory-unit';

export const InventoryAuditAction = {
  STOCK_ITEM_CREATED: 'STOCK_ITEM_CREATED',
  STOCK_ITEM_UPDATED: 'STOCK_ITEM_UPDATED',
  STOCK_ITEM_DISABLED: 'STOCK_ITEM_DISABLED',
  SUPPLIER_CREATED: 'SUPPLIER_CREATED',
  SUPPLIER_UPDATED: 'SUPPLIER_UPDATED',
  SUPPLIER_DISABLED: 'SUPPLIER_DISABLED',
} as const;

type InventoryActor = Pick<
  ManagerAuthContext,
  'staffId' | 'username' | 'venueId' | 'organizationId'
>;

export interface StockItemInput {
  name?: unknown;
  sku?: unknown;
  baseUnit?: unknown;
  minimumStock?: unknown;
  notes?: unknown;
  isActive?: unknown;
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
    });
    return rows.map((row) => this.presentStockItem(row));
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
      version: 1,
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
    try {
      const created = await this.prisma.$transaction(async (tx) => {
        const row = await tx.stockItem.create({ data });
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
        if (changes.length === 0) return this.presentStockItem(existing);

        const wasActive = existing.isActive;
        const updated = await tx.stockItem.update({
          where: { id: existing.id },
          data,
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
        return this.presentStockItem(updated);
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

  private presentStockItem(row: any) {
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
      // Step 1 has no movements. This is explicitly derived, never editable.
      currentStock: '0',
      stockStatus: 'NO_MOVEMENTS',
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
    return tx.auditEventLog.create({
      data: {
        venueId: actor.venueId,
        action: event.action,
        userId: actor.staffId,
        entityType: event.entityType,
        entityId: event.entityId,
        deviceType: 'manager',
        data: {
          actorId: actor.staffId,
          actorName: actor.username,
          source: 'MANAGER',
          ...event.data,
        } as Prisma.InputJsonValue,
      },
    });
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

function rethrowInventoryConstraint(error: unknown): never {
  if (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
  ) {
    throw new ConflictException('SKU already exists in this Venue');
  }
  throw error;
}
