import { forwardRef, Inject, Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../../prisma.service';
import { MonitoringGateway } from '../../../realtime/monitoring.gateway';
import { StaffPinVault } from '../../../auth/staff-pin-vault.service';
import { normalizeStaffRole } from '../../../staff/staff-role';
import { PosOutboxService } from '../../pos-outbox.service';
import {
  filterSuppressedOrderIds,
  isPosEchoSuppressed,
  isReservationEchoSuppressed,
  isTableEchoSuppressed,
} from '../../sync-echo-guard';
import { pendingStaffUsernames, posWinsOrderConflict } from '../sync-conflict';
import { PosConnectionRegistry } from '../pos-connection.registry';
import { MenuSyncService } from '../snapshot/menu-sync.service';
import { OrderSyncService } from '../snapshot/order-sync.service';
import { TableSyncService } from '../snapshot/table-sync.service';
import { SyncPayload } from '../sync-payload';

export interface SnapshotIngestResult {
  success: boolean;
  syncedAt: string;
}

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

/**
 * Applies one POS snapshot to the server.
 *
 * This is the whole of what `POST /sync/manager-data` used to do inline in the
 * controller. It is deliberately still one ordered method: the POS relies on
 * this exact sequence — tables before orders, every write before the aggregate
 * broadcasts, the business-day rollover after the table snapshot — and the
 * sequence is easier to protect while it reads top to bottom.
 *
 * There is no enclosing transaction, and adding one would change failure
 * behaviour: today a throw part-way leaves earlier sections applied and skips
 * the rest. See `sync-manager-data.characterization.spec.ts`.
 */
@Injectable()
export class IngestPosSnapshotService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    @Inject(forwardRef(() => PosOutboxService))
    private readonly posOutbox: PosOutboxService,
    private readonly pinVault: StaffPinVault,
    private readonly posConnection: PosConnectionRegistry,
    private readonly menu: MenuSyncService,
    private readonly tables: TableSyncService,
    private readonly orders: OrderSyncService,
  ) {}

  async execute(data: SyncPayload): Promise<SnapshotIngestResult> {
    const {
      tables,
      orders,
      expenses,
      menu,
      staff,
      quickOrders,
      salesSummary,
      salesAllTimeSummary,
      salesHistoryByDate,
    } = data;

    const realtimeOnly = data.realtimeOnly === true;
    if (realtimeOnly) {
      console.log(
        `[SYNC] Realtime snapshot: ${tables?.length ?? 0} tables, ${orders?.length ?? 0} orders`,
      );
    }

    // Store POS callback URL for reverse-push (mobile → POS)
    await this.posConnection.register(
      data.posCallbackUrl,
      data.posConnectionKey,
    );
    if (!this.posConnection.hasCallbackUrl()) {
      console.warn(
        '[Sync] manager-data received without posCallbackUrl — start Windows POS (ingest on :8081) so mobile edits reach Hive.',
      );
    }

    // Sync Menu
    if (menu && !realtimeOnly) {
      await this.menu.sync(menu);
    }

    console.log(
      '[Sync][MoneyDebug][IN] businessDate=%s dailySalesTotal=%s openTablesPayable=%s salesSummary.totalRevenue=%s orders=%s tables=%s',
      data.businessDate ?? '',
      data.dailySalesTotal ?? 'null',
      data.openTablesPayable ?? 'null',
      data.salesSummary?.totalRevenue ?? 'null',
      data.orders?.length ?? 0,
      data.tables?.length ?? 0,
    );

    // Sync Tables — the POS is the source of truth, except for the cold-boot
    // all-free snapshot the service guards against.
    let didSyncTables = await this.tables.sync(tables, realtimeOnly);

    // Sync Orders — last-write-wins against the outbox, table linking, and
    // reconciliation of orders the snapshot no longer carries.
    const orderResult = await this.orders.sync(orders, data.businessDate);
    didSyncTables = didSyncTables || orderResult.didSyncTables;
    const releasedTablesFromClosedOrders = orderResult.releasedTables;

    // Sync Expenses
    if (expenses) {
      for (const expense of expenses) {
        await (this.prisma.expense.create as any)({
          data: {
            description: expense.description,
            amount: expense.amount,
            category: expense.category,
            paymentType: expense.paymentType ?? 'cash',
            createdAt: expense.createdAt
              ? new Date(expense.createdAt)
              : new Date(),
          },
        });
      }
    }

    // Sync Staff — username/role only unless pin explicitly provided (legacy).
    if (staff && staff.length > 0 && !realtimeOnly) {
      const plainPinsByUsername = await this.pinVault.read();
      let pinsMapChanged = false;
      const incomingUsernames = new Set<string>();
      for (const member of staff) {
        incomingUsernames.add(member.username);
        const pin = typeof member.pin === 'string' ? member.pin.trim() : '';
        const hasPin = pin.length > 0;

        if (hasPin) {
          const pinHash = await bcrypt.hash(pin, 12);
          await (this.prisma as any).staff.upsert({
            where: { username: member.username },
            update: {
              pinHash,
              role: normalizeStaffRole(member.role),
              isActive: true,
            },
            create: {
              username: member.username,
              pinHash,
              role: normalizeStaffRole(member.role),
              isActive: true,
            },
          });
          plainPinsByUsername[member.username] = pin;
          pinsMapChanged = true;
        } else {
          const existing = await (this.prisma as any).staff.findUnique({
            where: { username: member.username },
          });
          if (existing) {
            await (this.prisma as any).staff.update({
              where: { username: member.username },
              data: { role: normalizeStaffRole(member.role), isActive: true },
            });
          } else {
            console.warn(
              `[SYNC] Skipping new staff "${member.username}" without PIN (use mobile user create).`,
            );
          }
        }
      }
      if (pinsMapChanged) {
        await this.pinVault.write(plainPinsByUsername);
      }

      // Reconcile deletions: if user disappeared from Windows POS list,
      // remove it from backend too so mobile and Windows stay 1:1.
      //
      // But never delete a user that has an in-flight queued mobile change
      // (create/rename/pin/role): the POS simply hasn't applied it yet, so its
      // current snapshot legitimately predates the user. Deleting here would
      // wrongly remove a manager-created user until the POS catches up.
      const pendingUserRows = await (
        this.prisma as any
      ).posCallbackOutbox.findMany({
        where: { status: 'pending', endpoint: { startsWith: '/mobile-user-' } },
        select: { endpoint: true, payload: true },
      });
      const protectedUsernames = pendingStaffUsernames(pendingUserRows);
      const existing = await (this.prisma as any).staff.findMany({
        select: { username: true },
      });
      const stale = existing
        .map((u: any) => String(u.username ?? ''))
        .filter(
          (username: string) =>
            username.length > 0 &&
            !incomingUsernames.has(username) &&
            !protectedUsernames.has(username),
        );
      if (stale.length > 0) {
        await (this.prisma as any).staff.deleteMany({
          where: { username: { in: stale } },
        });
      }
    }

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

    const changed =
      didSyncTables || !!orders || !!expenses || !!menu || !!staff;

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
    if (didSyncTables || releasedTablesFromClosedOrders) {
      this.gateway.broadcastUpdate('table_updated', { source: 'pos_sync' });
    }
    if (changed) {
      this.gateway.broadcastUpdate('data_updated', { type: 'all' });
    }

    // ── Business date tracking ──────────────────────────────────────────────
    // The POS sends its current business date (YYYY-MM-DD). Store it so the
    // mobile dashboard queries the correct date range instead of calendar-day.
    if (data.businessDate) {
      const newDate = data.businessDate; // e.g. "2026-04-30"
      const existing = await (this.prisma as any).setting.findUnique({
        where: { key: 'currentBusinessDate' },
      });
      const prevDate = existing?.value ?? null;

      await (this.prisma as any).setting.upsert({
        where: { key: 'currentBusinessDate' },
        update: { value: newDate },
        create: { key: 'currentBusinessDate', value: newDate },
      });

      const openedAtKey = `businessDayOpenedAt:${newDate}`;
      const openedAtExisting = await (this.prisma as any).setting.findUnique({
        where: { key: openedAtKey },
      });
      const dayAdvanced = prevDate !== null && prevDate !== newDate;
      if (dayAdvanced || !openedAtExisting?.value) {
        const openedAt = new Date().toISOString();
        await (this.prisma as any).setting.upsert({
          where: { key: openedAtKey },
          update: { value: openedAt },
          create: { key: openedAtKey, value: openedAt },
        });
      }

      // If the date actually advanced, the manager closed the day → notify mobile
      if (dayAdvanced) {
        console.log(
          `[Sync] Business date advanced: ${prevDate} → ${newDate}. Clearing all table reservations.`,
        );
        // Reset every table to free so ghost tables from the previous business
        // day cannot persist. The stale-data protection in the table sync below
        // would otherwise block the next "all tables free" push from the POS.
        await (this.prisma as any).table.updateMany({
          data: { isReserved: false, activeOrderId: null, currentBill: 0 },
        });
        this.gateway.broadcastUpdate('day_closed', { date: newDate, prevDate });
      }
    }

    // Persist POS day sales summary (payment methods + totals) so mobile reads
    // exactly what Windows saved locally after table close.
    if (salesSummary?.date) {
      const summaryValue = JSON.stringify({
        date: salesSummary.date,
        totalRevenue: salesSummary.totalRevenue ?? 0,
        orderCount: salesSummary.orderCount ?? 0,
        cashRevenue: salesSummary.cashRevenue ?? 0,
        cardRevenue: salesSummary.cardRevenue ?? 0,
        paymentBreakdown: salesSummary.paymentBreakdown ?? {},
        totalExpenses: salesSummary.totalExpenses ?? 0,
        profit: salesSummary.profit ?? 0,
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: `salesSummary:${salesSummary.date}` },
        update: { value: summaryValue },
        create: {
          key: `salesSummary:${salesSummary.date}`,
          value: summaryValue,
        },
      });
    }

    if (salesAllTimeSummary && !realtimeOnly) {
      const allTimeValue = JSON.stringify({
        totalRevenue: salesAllTimeSummary.totalRevenue ?? 0,
        orderCount: salesAllTimeSummary.orderCount ?? 0,
        cashRevenue: salesAllTimeSummary.cashRevenue ?? 0,
        cardRevenue: salesAllTimeSummary.cardRevenue ?? 0,
        paymentBreakdown: salesAllTimeSummary.paymentBreakdown ?? {},
        topItems: salesAllTimeSummary.topItems ?? [],
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:all_time' },
        update: { value: allTimeValue },
        create: { key: 'salesSummary:all_time', value: allTimeValue },
      });
    }

    if (
      salesHistoryByDate &&
      typeof salesHistoryByDate === 'object' &&
      !realtimeOnly
    ) {
      for (const [date, summary] of Object.entries(salesHistoryByDate)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
        const summaryValue = JSON.stringify({
          date,
          totalRevenue: summary.totalRevenue ?? 0,
          orderCount: summary.orderCount ?? 0,
          totalOrders: summary.totalOrders ?? 0,
          cancelledOrders: summary.cancelledOrders ?? 0,
          cashRevenue: summary.cashRevenue ?? 0,
          cardRevenue: summary.cardRevenue ?? 0,
          paymentBreakdown: summary.paymentBreakdown ?? {},
          totalExpenses: summary.totalExpenses ?? 0,
          profit: summary.profit ?? 0,
          topItems: summary.topItems ?? [],
          closedTables: summary.closedTables ?? [],
        });
        await (this.prisma as any).setting.upsert({
          where: { key: `salesSummary:${date}` },
          update: { value: summaryValue },
          create: { key: `salesSummary:${date}`, value: summaryValue },
        });
      }
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:history_index' },
        update: {
          value: JSON.stringify(Object.keys(salesHistoryByDate).sort()),
        },
        create: {
          key: 'salesSummary:history_index',
          value: JSON.stringify(Object.keys(salesHistoryByDate).sort()),
        },
      });
    }

    if (data.settings) {
      const percent = Number(data.settings.serviceFeePercent ?? 10);
      const enabled = data.settings.serviceFeeEnabled === true;
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeePercent' },
        update: { value: String(percent) },
        create: { key: 'restaurant:serviceFeePercent', value: String(percent) },
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeeEnabled' },
        update: { value: enabled ? 'true' : 'false' },
        create: {
          key: 'restaurant:serviceFeeEnabled',
          value: enabled ? 'true' : 'false',
        },
      });
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      await (this.prisma as any).setting.upsert({
        where: { key: `dailySalesTotal:${data.businessDate}` },
        update: { value: String(data.dailySalesTotal ?? 0) },
        create: {
          key: `dailySalesTotal:${data.businessDate}`,
          value: String(data.dailySalesTotal ?? 0),
        },
      });
    }

    if (data.businessDate) {
      const fromOccupiedTables = (tables ?? [])
        .filter(
          (t) =>
            t.isReserved ||
            (t.activeOrderId !== undefined && t.activeOrderId !== null),
        )
        .reduce((sum, t) => sum + Number(t.currentBill ?? 0), 0);

      const openTablesPayableToStore = fromOccupiedTables;

      await (this.prisma as any).setting.upsert({
        where: { key: `openTablesPayable:${data.businessDate}` },
        update: { value: String(openTablesPayableToStore) },
        create: {
          key: `openTablesPayable:${data.businessDate}`,
          value: String(openTablesPayableToStore),
        },
      });
      console.log(
        '[Sync][MoneyDebug][STORE] key=openTablesPayable:%s value=%s',
        data.businessDate,
        openTablesPayableToStore,
      );
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      console.log(
        '[Sync][MoneyDebug][STORE] key=dailySalesTotal:%s value=%s',
        data.businessDate,
        data.dailySalesTotal ?? 0,
      );
    }

    // POS just pushed (so it's online): flush any held mobile changes to Hive
    // now instead of waiting out the retry backoff. Runs after order sync so
    // this push's stale snapshot is already held, not overwritten.
    void this.posOutbox.kickPending();

    return { success: true, syncedAt: new Date().toISOString() };
  }
}
