import { Prisma } from '@prisma/client';
import type { ManagerAuthContext } from '../auth/manager-auth-context';

export const InventoryAuditAction = {
  STOCK_ITEM_CREATED: 'STOCK_ITEM_CREATED',
  STOCK_ITEM_UPDATED: 'STOCK_ITEM_UPDATED',
  STOCK_ITEM_DISABLED: 'STOCK_ITEM_DISABLED',
  SUPPLIER_CREATED: 'SUPPLIER_CREATED',
  SUPPLIER_UPDATED: 'SUPPLIER_UPDATED',
  SUPPLIER_DISABLED: 'SUPPLIER_DISABLED',
  RECEIVING_CREATED: 'RECEIVING_CREATED',
  RECEIVING_UPDATED: 'RECEIVING_UPDATED',
  RECEIVING_POSTED: 'RECEIVING_POSTED',
  RECEIVING_CANCELLED: 'RECEIVING_CANCELLED',
  RECIPE_CREATED: 'RECIPE_CREATED',
  RECIPE_UPDATED: 'RECIPE_UPDATED',
  RECIPE_DISABLED: 'RECIPE_DISABLED',
} as const;

export type InventoryAuditEntityType =
  | 'STOCK_ITEM'
  | 'SUPPLIER'
  | 'RECEIVING'
  | 'RECIPE';

export type InventoryActor = Pick<
  ManagerAuthContext,
  'staffId' | 'username' | 'venueId' | 'organizationId'
>;

/**
 * One venue-wide audit row, written in the same transaction as the change.
 *
 * StockMovement is already durable quantity history, so movements are counted
 * and summarised here rather than copied — a posted document contributes one
 * row that says what happened, not one row per line.
 */
export function writeInventoryAudit(
  tx: Prisma.TransactionClient,
  actor: InventoryActor,
  event: {
    action: string;
    entityType: InventoryAuditEntityType;
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
