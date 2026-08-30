import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import { posWinsOrderConflict } from '../sync-conflict';
import { OrderSync } from '../sync-payload';
import {
  updateExistingTableRecord,
  upsertTableRecord,
} from './table-record-identity';

/**
 * Applies the POS's order snapshot, and reconciles what the snapshot omits.
 *
 * Three things happen here that are easy to lose sight of:
 *
 * - Last-write-wins against the outbox. An order with an undelivered mobile
 *   edit is authoritative on the server until the POS confirms it applied the
 *   change, so a stale POS snapshot cannot revert it. The POS wins only when it
 *   supplies a timestamp strictly newer than the queued edit, and then the
 *   queued change is marked superseded rather than delivered.
 * - Table linking. Active dine-in orders reserve their tables and terminal
 *   orders free them, independently of the table snapshot, because the table
 *   snapshot may have been skipped by the cold-boot guard.
 * - Deletion reconciliation. Orders absent from the snapshot for the current
 *   business date are removed, except those in this payload or still queued in
 *   the outbox — a mobile-created order the POS has not received yet must not
 *   be deleted for being missing from the POS's view.
 */
@Injectable()
export class OrderSyncService {
  constructor(private readonly prisma: PrismaService) {}

  async sync(
    orders: OrderSync[] | undefined,
    businessDate?: string,
  ): Promise<{ didSyncTables: boolean; releasedTables: boolean }> {
    let didSyncTables = false;
    let releasedTables = false;
    if (orders) {
      const incomingPosOrderIds = orders
        .map((o) => o.posOrderId ?? o.orderId)
        .filter((id): id is number => id !== undefined && id !== null);

      // Orders with an undelivered mobile change (outbox) are authoritative on the
      // server until the POS confirms it applied them. Ignore the POS's (stale)
      // snapshot for these so a startup/realtime push can't revert the edit.
      const pendingOutboxRows = await (
        this.prisma as any
      ).posCallbackOutbox.findMany({
        where: { status: 'pending', posOrderId: { not: null } },
        select: { posOrderId: true, createdAt: true },
      });
      const pendingOutboxOrderIds = new Set<number>(
        pendingOutboxRows
          .map((r: { posOrderId: number | null }) => r.posOrderId)
          .filter((id: number | null): id is number => id !== null),
      );
      // Newest queued mobile-edit time per order — the "manager wrote at" side
      // of the same-order last-write-wins comparison below.
      const pendingOutboxEditedAt = new Map<number, Date>();
      for (const row of pendingOutboxRows as Array<{
        posOrderId: number | null;
        createdAt: Date;
      }>) {
        if (row.posOrderId === null) continue;
        const prev = pendingOutboxEditedAt.get(row.posOrderId);
        if (!prev || row.createdAt > prev) {
          pendingOutboxEditedAt.set(row.posOrderId, row.createdAt);
        }
      }

      const terminalStatuses = new Set(['paid', 'closed', 'cancelled']);

      for (const order of orders) {
        const pOrderId = order.posOrderId ?? order.orderId;
        if (pOrderId === undefined) continue;

        // A mobile change for this order is queued for the POS. Resolve the
        // same-order conflict by last-write-wins: the POS (source of truth)
        // wins when its edit is strictly newer than the queued mobile edit;
        // otherwise the mobile edit is authoritative and we ignore the POS's
        // stale snapshot until the POS confirms it applied the change.
        if (pendingOutboxOrderIds.has(pOrderId)) {
          const managerEditedAt = pendingOutboxEditedAt.get(pOrderId);
          const posWins = posWinsOrderConflict(
            order.updatedAt,
            managerEditedAt,
          );

          if (!posWins) {
            console.log(
              `[Sync] Holding order #${pOrderId}: queued mobile edit is newer (or POS sent no timestamp) — ignoring POS snapshot.`,
            );
            continue;
          }

          // POS edit is newer — drop the stale queued mobile change so it isn't
          // delivered back to the POS and overwrite the fresher POS state.
          console.log(
            `[Sync] Order #${pOrderId}: POS edit newer than queued mobile change — POS wins, discarding queued change.`,
          );
          await (this.prisma as any).posCallbackOutbox.updateMany({
            where: { status: 'pending', posOrderId: pOrderId },
            data: { status: 'superseded', lastError: 'pos_newer_edit_won' },
          });
          pendingOutboxOrderIds.delete(pOrderId);
        }

        const dbOrder = await this.prisma.order.upsert({
          where: { posOrderId: pOrderId },
          update: {
            status: order.status,
            totalAmount: order.totalAmount,
            paymentType: order.paymentType ?? 'cash',
            guestCount: order.guestCount ?? 0,
            waiterName: order.waiterName ?? order.createdBy ?? 'პერსონალი',
            floor: order.floor ?? '',
            businessDate: order.businessDate ?? businessDate ?? '',
            customerName: order.customerName ?? '',
            customerPhone: order.customerPhone ?? '',
            pickupTime: order.pickupTime ?? '',
            includeServiceFee: order.includeServiceFee ?? false,
            discountAmount: order.discountAmount ?? 0,
            serviceFeePercent:
              order.serviceFeePercent ?? order.customServiceFeePercentage ?? 10,
          },
          create: {
            posOrderId: pOrderId,
            status: order.status,
            totalAmount: order.totalAmount,
            paymentType: order.paymentType ?? 'cash',
            guestCount: order.guestCount ?? 0,
            waiterName: order.waiterName ?? order.createdBy ?? 'პერსონალი',
            floor: order.floor ?? '',
            businessDate: order.businessDate ?? businessDate ?? '',
            customerName: order.customerName ?? '',
            customerPhone: order.customerPhone ?? '',
            pickupTime: order.pickupTime ?? '',
            includeServiceFee: order.includeServiceFee ?? false,
            discountAmount: order.discountAmount ?? 0,
            serviceFeePercent:
              order.serviceFeePercent ?? order.customServiceFeePercentage ?? 10,
          },
        });

        // Sync Items.
        //
        // One nested write, not a deleteMany followed by loose creates. Prisma
        // runs a nested write in a single transaction, so two overlapping
        // syncs cannot interleave as delete/delete/create/create and leave the
        // order holding every line twice — which is what the manager app was
        // showing after an item was added on the POS.
        if (order.items) {
          await this.prisma.order.update({
            where: { id: dbOrder.id },
            data: {
              items: {
                deleteMany: {},
                create: order.items.map((item: any) => ({
                  name: item.name,
                  quantity: item.quantity,
                  price: item.price,
                })),
              },
            },
          });
        }

        const status = (order.status ?? '').toLowerCase();
        const floor = order.floor ?? 'first';
        const isTakeaway = floor.toLowerCase().includes('takeaway');
        const tableNumbers = Array.isArray(order.tableNumbers)
          ? order.tableNumbers
          : [];

        // Active dine-in orders must reserve tables even when POS table snapshot is stale.
        if (!terminalStatuses.has(status) && !isTakeaway) {
          for (const [tableIndex, rawNum] of tableNumbers.entries()) {
            const tableNumber = String(rawNum)
              .replace(/^table\s*/i, '')
              .trim();
            if (!tableNumber) continue;
            await upsertTableRecord(
              this.prisma,
              {
                tableId: order.tableIds?.[tableIndex],
                tableNumber,
                floor,
              },
              {
                isReserved: true,
                activeOrderId: pOrderId,
                currentBill: order.totalAmount ?? 0,
              },
            );
            didSyncTables = true;
            console.log(
              `[Sync] Linked table ${tableNumber}/${floor} → order #${pOrderId} (${status})`,
            );
          }
        }

        // When POS closes/pays an order, free linked tables even if table snapshot was skipped.
        if (terminalStatuses.has(status)) {
          for (const [tableIndex, rawNum] of tableNumbers.entries()) {
            const tableNumber = String(rawNum)
              .replace(/^table\s*/i, '')
              .trim();
            if (!tableNumber) continue;
            const updatedCount = await updateExistingTableRecord(
              this.prisma,
              {
                tableId: order.tableIds?.[tableIndex],
                tableNumber,
                floor,
              },
              {
                isReserved: false,
                activeOrderId: null,
                currentBill: 0,
              },
            );
            if (updatedCount > 0) {
              releasedTables = true;
              console.log(
                `[Sync] Freed table ${tableNumber}/${floor} (order #${pOrderId} ${status})`,
              );
            }
          }
        }
      }

      // Reconcile takeaway orders for the current business date:
      // if POS restore removed takeaways locally, backend must drop stale rows too.
      const currentBusinessDate = businessDate;
      if (currentBusinessDate) {
        // Never delete an order that still has an undelivered mobile change
        // queued (e.g. a mobile-created takeaway the POS hasn't received yet).
        const protectedPosOrderIds = [
          ...incomingPosOrderIds,
          ...pendingOutboxOrderIds,
        ];
        // Reconcile dine-in orders too (non-takeaway). Without this, stale
        // pre-restore rows can remain and dashboard open-payable gets doubled.
        const staleDineInOrders = await this.prisma.order.findMany({
          where: {
            businessDate: currentBusinessDate,
            NOT: {
              OR: [
                { floor: { contains: 'takeaway', mode: 'insensitive' } },
                { floor: { contains: 'take away', mode: 'insensitive' } },
              ],
            },
            ...(protectedPosOrderIds.length > 0
              ? { posOrderId: { notIn: protectedPosOrderIds } }
              : {}),
          },
          select: { id: true },
        });
        if (staleDineInOrders.length > 0) {
          const staleIds = staleDineInOrders.map((o) => o.id);
          await (this.prisma as any).orderItem.deleteMany({
            where: { orderId: { in: staleIds } },
          });
          await this.prisma.order.deleteMany({
            where: { id: { in: staleIds } },
          });
        }

        await (this.prisma as any).order.deleteMany({
          where: {
            floor: 'takeaway',
            businessDate: currentBusinessDate,
            ...(protectedPosOrderIds.length > 0
              ? { posOrderId: { notIn: protectedPosOrderIds } }
              : {}),
          },
        });
      }
    }
    return { didSyncTables, releasedTables };
  }
}
