import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import { MonitoringGateway } from '../../../realtime/monitoring.gateway';
import {
  filterSuppressedOrderIds,
  isPosEchoSuppressed,
  isReservationEchoSuppressed,
  isTableEchoSuppressed,
} from '../../sync-echo-guard';
import { OrderSync, SyncPayload } from '../sync-payload';

/** Keep the latest hint per order so rapid service-fee toggles emit one touch. */
function dedupeOrderHintsByPosOrderId<T extends { posOrderId: number }>(
  hints: T[],
): T[] {
  const byId = new Map<number, T>();
  for (const h of hints) {
    if (!Number.isFinite(h.posOrderId)) continue;
    byId.set(h.posOrderId, h);
  }
  return [...byId.values()];
}

export interface RelayedHints {
  hadOrderLineTouch: boolean;
  hadTableTouch: boolean;
}

export interface SnapshotAnnouncement {
  orders?: OrderSync[];
  hadOrderLineTouch: boolean;
  hadTableTouch: boolean;
  didSyncTables: boolean;
  releasedTables: boolean;
  changed: boolean;
}

/**
 * Everything the sync flow tells connected manager apps.
 *
 * All of it lives here so the "no broadcast before its write" rule is checkable
 * in one file. Every relay is filtered through the echo guard first: a mobile
 * edit pushes to the POS and comes back in the next snapshot, and the device
 * that made the change must not be notified about its own round-trip.
 *
 * The precise, per-record touches take priority over the coarse ones — when a
 * snapshot carries order or table hints the blanket `order_updated` toast is
 * suppressed, so the manager app shows one notification rather than two.
 */
@Injectable()
export class SyncBroadcastService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
  ) {}

  /** Relays the POS's per-record change hints. */
  async relayPosHints(data: SyncPayload): Promise<RelayedHints> {
    const touchedOrderHints = Array.isArray(data.touchedOrderHints)
      ? data.touchedOrderHints
          .map((h: any) => ({
            posOrderId: Number(h?.posOrderId),
            occurredAt:
              typeof h?.occurredAt === 'string' &&
              h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
            tableLabel:
              typeof h?.tableLabel === 'string' ? h.tableLabel.trim() : '',
            floor: typeof h?.floor === 'string' ? h.floor.trim() : undefined,
            waiterName:
              typeof h?.waiterName === 'string'
                ? h.waiterName.trim()
                : undefined,
            highlightItemKeys: Array.isArray(h?.highlightItemKeys)
              ? h.highlightItemKeys
                  .map((k: unknown) => String(k).trim())
                  .filter((k: string) => k.length > 0)
              : undefined,
            changeSummary:
              typeof h?.changeSummary === 'string'
                ? h.changeSummary.trim()
                : undefined,
            changeKind:
              typeof h?.changeKind === 'string'
                ? h.changeKind.trim()
                : undefined,
          }))
          .filter((h: any) => Number.isFinite(h.posOrderId))
      : [];
    const filteredOrderHints = dedupeOrderHintsByPosOrderId(
      touchedOrderHints.filter(
        (h: { posOrderId: number }) => !isPosEchoSuppressed(h.posOrderId),
      ),
    );
    const hadOrderLineTouch = filteredOrderHints.length > 0;
    if (hadOrderLineTouch) {
      this.gateway.broadcastUpdate('orders_bulk_touch', {
        touches: filteredOrderHints,
        posOrderIds: filteredOrderHints.map(
          (h: { posOrderId: number }) => h.posOrderId,
        ),
        source: 'pos_sync',
      });
    }

    const touchedTableHints = Array.isArray(data.touchedTableHints)
      ? data.touchedTableHints
          .map((h: any) => ({
            tableNumber: String(h?.tableNumber ?? '').trim(),
            floor: String(h?.floor ?? 'first').trim(),
            changeType:
              h?.changeType === 'freed'
                ? ('freed' as const)
                : ('reserved' as const),
            activeOrderId:
              h?.activeOrderId !== undefined && h?.activeOrderId !== null
                ? Number(h.activeOrderId)
                : undefined,
            currentBill:
              h?.currentBill !== undefined && h?.currentBill !== null
                ? Number(h.currentBill)
                : undefined,
            occurredAt:
              typeof h?.occurredAt === 'string' &&
              h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
          }))
          .filter((h) => h.tableNumber.length > 0)
      : [];
    const filteredTableHints = touchedTableHints.filter((h) => {
      if (isTableEchoSuppressed(h.tableNumber, h.floor)) return false;
      if (
        h.activeOrderId !== undefined &&
        isPosEchoSuppressed(h.activeOrderId)
      ) {
        return false;
      }
      return true;
    });
    const hadTableTouch = filteredTableHints.length > 0;
    if (hadTableTouch) {
      const tableSnapshots: Array<Record<string, unknown>> = [];
      for (const hint of filteredTableHints) {
        const row = await (this.prisma as any).table.findFirst({
          where: { tableNumber: hint.tableNumber, floor: hint.floor },
        });
        if (row) {
          const occupied = !!(row.isReserved || row.activeOrderId);
          tableSnapshots.push({
            tableNumber: row.tableNumber,
            floor: row.floor,
            isReserved: occupied,
            isOccupied: occupied,
            activeOrderId: occupied ? row.activeOrderId : null,
            currentBill: occupied ? (row.currentBill ?? 0) : 0,
          });
        }
      }
      this.gateway.broadcastUpdate('tables_bulk_touch', {
        touches: filteredTableHints,
        tables: tableSnapshots,
        source: 'pos_sync',
      });
    }

    // Reservation changes from the POS → notify mobile (skip mobile-originated
    // round-trips, which are already echoed at create time).
    const reservationHints = Array.isArray(data.touchedReservationHints)
      ? data.touchedReservationHints
          .map((h) => ({
            reservationId: String(h?.reservationId ?? '').trim(),
            action: typeof h?.action === 'string' ? h.action : 'updated',
            customerName:
              typeof h?.customerName === 'string'
                ? h.customerName.trim()
                : undefined,
            reservationDate:
              typeof h?.reservationDate === 'string'
                ? h.reservationDate.trim()
                : undefined,
            reservationTime:
              typeof h?.reservationTime === 'string'
                ? h.reservationTime.trim()
                : undefined,
            tableNumbers: Array.isArray(h?.tableNumbers)
              ? h.tableNumbers
              : undefined,
            linkedOrderId:
              typeof h?.linkedOrderId === 'number' &&
              Number.isFinite(h.linkedOrderId)
                ? h.linkedOrderId
                : undefined,
            notes:
              typeof h?.notes === 'string' && h.notes.trim().length > 0
                ? h.notes.trim()
                : undefined,
            walkIn: h?.walkIn === true,
            occurredAt:
              typeof h?.occurredAt === 'string' &&
              h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
          }))
          .filter((h) => h.reservationId.length > 0)
      : [];
    const filteredReservationHints = reservationHints.filter(
      (h) => !isReservationEchoSuppressed(h.reservationId),
    );
    if (filteredReservationHints.length > 0) {
      const latest =
        filteredReservationHints[filteredReservationHints.length - 1];
      const customer = (latest.customerName ?? '').trim().toLowerCase();
      const walkIn =
        latest.walkIn === true ||
        customer === 'walk-in' ||
        customer.includes('walk-in');
      this.gateway.broadcastUpdate('data_updated', {
        type: 'reservations',
        reservationId: latest.reservationId,
        customerName: latest.customerName,
        reservationDate: latest.reservationDate,
        reservationTime: latest.reservationTime,
        tableNumbers: latest.tableNumbers,
        action: latest.action,
        touches: filteredReservationHints,
        source: 'pos_sync',
        ...(latest.linkedOrderId !== undefined
          ? { linkedOrderId: latest.linkedOrderId }
          : {}),
        ...(latest.notes !== undefined ? { notes: latest.notes } : {}),
        ...(walkIn ? { walkIn: true } : {}),
        ...(walkIn && latest.linkedOrderId !== undefined
          ? { posOrderId: latest.linkedOrderId }
          : {}),
      });
    }

    return { hadOrderLineTouch, hadTableTouch };
  }

  /** The coarse "something changed" notifications for the whole snapshot. */
  announceSnapshotApplied({
    orders,
    hadOrderLineTouch,
    hadTableTouch,
    didSyncTables,
    releasedTables,
    changed,
  }: SnapshotAnnouncement): void {
    // Avoid duplicate "სალარო" + "მაგიდები" toasts: line changes use orders_bulk_touch only.
    if (orders && orders.length > 0 && !hadOrderLineTouch && !hadTableTouch) {
      const posOrderIds = filterSuppressedOrderIds(
        orders
          .map((o) => Number(o.posOrderId))
          .filter((id) => Number.isFinite(id)),
      );
      if (posOrderIds.length > 0) {
        this.gateway.broadcastUpdate('order_updated', {
          posOrderIds,
          source: 'pos_sync',
        });
      }
    }
    if (didSyncTables || releasedTables) {
      this.gateway.broadcastUpdate('table_updated', { source: 'pos_sync' });
    }
    if (changed) {
      this.gateway.broadcastUpdate('data_updated', { type: 'all' });
    }
  }

  announceDayClosed(date: string, prevDate: unknown): void {
    this.gateway.broadcastUpdate('day_closed', { date, prevDate });
  }
}
