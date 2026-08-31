import { forwardRef, Inject, Injectable } from '@nestjs/common';
import { PosOutboxService } from '../../pos-outbox.service';
import { PosConnectionRegistry } from '../pos-connection.registry';
import { BusinessDaySyncService } from '../snapshot/business-day-sync.service';
import { MenuSyncService } from '../snapshot/menu-sync.service';
import { OrderSyncService } from '../snapshot/order-sync.service';
import { StaffSyncService } from '../snapshot/staff-sync.service';
import { SyncBroadcastService } from '../snapshot/sync-broadcast.service';
import { TableSyncService } from '../snapshot/table-sync.service';
import { SyncPayload } from '../sync-payload';
import { PosAuthContext } from '../../../auth/pos-auth-context';
import type { TenantContext } from '../../../auth/pos-auth-context';

export interface SnapshotIngestResult {
  success: boolean;
  syncedAt: string;
}

/**
 * Applies one POS snapshot to the server.
 *
 * This owns the order of the sync, and nothing else — each step belongs to a
 * focused service. The order is not incidental: tables are applied before
 * orders so an active order can still claim a table the snapshot skipped;
 * every write lands before the aggregate broadcasts so a manager app that
 * reacts to one reads settled state; and the business-day rollover runs after
 * the table snapshot, because it wipes the floor and an earlier wipe would be
 * undone by the very snapshot it is meant to clear.
 *
 * There is no enclosing transaction, here or in the services below, and adding
 * one would change failure behaviour: today a throw part-way leaves earlier
 * steps applied and skips the rest, and the POS retries the whole snapshot.
 * `ingest-pos-snapshot.characterization.spec.ts` pins both the order and that
 * partial-application behaviour.
 */
@Injectable()
export class IngestPosSnapshotService {
  constructor(
    @Inject(forwardRef(() => PosOutboxService))
    private readonly posOutbox: PosOutboxService,
    private readonly posConnection: PosConnectionRegistry,
    private readonly menu: MenuSyncService,
    private readonly tables: TableSyncService,
    private readonly orders: OrderSyncService,
    private readonly staff: StaffSyncService,
    private readonly businessDay: BusinessDaySyncService,
    private readonly broadcasts: SyncBroadcastService,
  ) {}

  async execute(
    data: SyncPayload,
    authContext: PosAuthContext,
  ): Promise<SnapshotIngestResult> {
    const tenant: TenantContext = {
      venueId: authContext.venueId,
      organizationId: authContext.organizationId,
    };
    // `quickOrders` is part of the wire format but has never been read here;
    // see the Step 2A report. It is deliberately left unconsumed.
    const { tables, orders, expenses, menu, staff } = data;

    const realtimeOnly = data.realtimeOnly === true;
    if (realtimeOnly) {
      console.log(
        `[SYNC] Realtime snapshot: ${tables?.length ?? 0} tables, ${orders?.length ?? 0} orders`,
      );
    }

    // Store POS callback URL for reverse-push (mobile → POS)
    await this.posConnection.register(
      tenant,
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
      await this.menu.sync(tenant, menu);
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
    let didSyncTables = await this.tables.sync(tenant, tables, realtimeOnly);

    // Sync Orders — last-write-wins against the outbox, table linking, and
    // reconciliation of orders the snapshot no longer carries.
    const orderResult = await this.orders.sync(
      tenant,
      orders,
      data.businessDate,
    );
    didSyncTables = didSyncTables || orderResult.didSyncTables;
    const releasedTablesFromClosedOrders = orderResult.releasedTables;

    // Sync Expenses
    if (expenses) {
      await this.businessDay.recordExpenses(tenant, expenses);
    }

    // Sync Staff — username/role only unless pin explicitly provided (legacy).
    if (staff && staff.length > 0 && !realtimeOnly) {
      await this.staff.sync(tenant, staff);
    }

    // Realtime side effects. Per-record hints first, then the coarse
    // notifications — every write above has already landed.
    const { hadOrderLineTouch, hadTableTouch } =
      await this.broadcasts.relayPosHints(tenant, data);

    const changed =
      didSyncTables || !!orders || !!expenses || !!menu || !!staff;

    this.broadcasts.announceSnapshotApplied({
      orders,
      hadOrderLineTouch,
      hadTableTouch,
      didSyncTables,
      releasedTables: releasedTablesFromClosedOrders,
      changed,
    });

    // Business-day tracking, then the reporting values the POS computed.
    // Order matters: the rollover wipes the floor after the table snapshot was
    // applied, and `openTablesPayable` is stored after that.
    const rollover = await this.businessDay.trackBusinessDate(
      tenant,
      data.businessDate,
    );
    if (rollover) {
      this.broadcasts.announceDayClosed(rollover.date, rollover.prevDate);
    }
    await this.businessDay.persistReportingSnapshot(tenant, data, realtimeOnly);

    // POS just pushed (so it's online): flush any held mobile changes to Hive
    // now instead of waiting out the retry backoff. Runs after order sync so
    // this push's stale snapshot is already held, not overwritten.
    void this.posOutbox.kickPending(tenant);

    return { success: true, syncedAt: new Date().toISOString() };
  }
}
