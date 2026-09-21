import { PrismaService } from '../../../prisma.service';
import { forwardRef, Inject, Injectable, Optional } from '@nestjs/common';
import { PosOutboxService } from '../../pos-outbox.service';
import { PosConnectionRegistry } from '../pos-connection.registry';
import { BusinessDaySyncService } from '../snapshot/business-day-sync.service';
import { MenuSyncService } from '../snapshot/menu-sync.service';
import { OrderSyncService } from '../snapshot/order-sync.service';
import { ReservationSyncService } from '../snapshot/reservation-sync.service';
import { StaffSyncService } from '../snapshot/staff-sync.service';
import { SyncBroadcastService } from '../snapshot/sync-broadcast.service';
import { SaleLedgerSyncService } from '../snapshot/sale-ledger-sync.service';
import { TableSyncService } from '../snapshot/table-sync.service';
import { SyncPayload } from '../sync-payload';
import { SyncTimer } from '../sync-timing';
import { PosAuthContext } from '../../../auth/pos-auth-context';
import type { TenantContext } from '../../../auth/pos-auth-context';

export interface SnapshotIngestResult {
  success: boolean;
  syncedAt: string;
  /**
   * Staff the snapshot named that the server holds no credential for. Present
   * only when there are any; the POS answers by carrying their PINs on the next
   * snapshot, which is how a re-provisioned server recollects what it needs.
   */
  staffNeedingPin?: string[];
  /** Revisions durably accepted by the Cloud ledger. */
  saleLedgerAck?: Array<{ posSaleId: string; revision: number }>;
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
 * HTTP ingestion supplies a transaction-bound database under the Venue authority
 * lock. A failed upload rolls back all writes; broadcasts run only after commit.
 * Direct internal calls without a database retain the legacy partial-apply behavior.
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
    private readonly reservations: ReservationSyncService,
    private readonly staff: StaffSyncService,
    private readonly businessDay: BusinessDaySyncService,
    private readonly broadcasts: SyncBroadcastService,
    @Optional() private readonly saleLedger?: SaleLedgerSyncService,
  ) {}

  async execute(
    data: SyncPayload,
    authContext: PosAuthContext,
    database?: PrismaService,
    afterCommit?: Array<() => Promise<void>>,
  ): Promise<SnapshotIngestResult> {
    const menuSync = database ? new MenuSyncService(database) : this.menu;
    const tableSync = database ? new TableSyncService(database) : this.tables;
    const orderSync = database ? new OrderSyncService(database) : this.orders;
    const reservationSync = database
      ? new ReservationSyncService(database)
      : this.reservations;
    const staffSync = database ? this.staff.withDatabase(database) : this.staff;
    const businessDaySync = database
      ? new BusinessDaySyncService(database)
      : this.businessDay;
    const ledgerSync = database
      ? new SaleLedgerSyncService(database)
      : this.saleLedger;
    const tenant: TenantContext = {
      venueId: authContext.venueId,
      organizationId: authContext.organizationId,
    };
    // `quickOrders` is part of the wire format but has never been read here;
    // see the Step 2A report. It is deliberately left unconsumed.
    const { tables, orders, expenses, menu, staff, reservations } = data;

    const timing = new SyncTimer();
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
      database,
    );
    if (!this.posConnection.hasCallbackUrl()) {
      console.warn(
        '[Sync] manager-data received without posCallbackUrl — start Windows POS (ingest on :8081) so mobile edits reach Hive.',
      );
    }

    // Sync Menu
    if (menu && !realtimeOnly) {
      await timing.phase('menu', () =>
        menuSync.sync(tenant, menu, data.menuIdentityVersion),
      );
    }

    // The critical close transaction is already durable in Hive before this
    // asynchronous full snapshot runs. Realtime snapshots intentionally skip
    // financial history work.
    let saleLedgerAck: Array<{ posSaleId: string; revision: number }> = [];
    const saleLedgerService = ledgerSync;
    if (
      saleLedgerService &&
      !realtimeOnly &&
      (data.saleLedger || data.saleLedgerDays)
    ) {
      const result = await timing.phase('sale-ledger', () =>
        saleLedgerService.sync(tenant, data.saleLedger, data.saleLedgerDays),
      );
      saleLedgerAck = result.acknowledgements;
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
    let didSyncTables = await timing.phase('tables', () =>
      tableSync.sync(tenant, tables, realtimeOnly),
    );

    // Sync Orders — last-write-wins against the outbox, table linking, and
    // reconciliation of orders the snapshot no longer carries.
    const orderResult = await timing.phase('orders', () =>
      orderSync.sync(tenant, orders, data.businessDate),
    );
    didSyncTables = didSyncTables || orderResult.didSyncTables;
    const releasedTablesFromClosedOrders = orderResult.releasedTables;

    // Sync Expenses
    if (expenses) {
      await timing.phase('expenses', () =>
        businessDaySync.recordExpenses(tenant, expenses),
      );
    }

    // Sync Staff — identity and role always, a credential only for a member
    // whose PIN the POS has not had acknowledged (and, from an older POS, one
    // whose PIN is already the stored one and so needs no re-derivation).
    let staffNeedingPin: string[] = [];
    let staffPinsHashed = 0;
    if (staff && staff.length > 0 && !realtimeOnly) {
      const staffResult = await timing.phase('staff', () =>
        staffSync.sync(tenant, staff),
      );
      staffNeedingPin = staffResult.needsPin;
      staffPinsHashed = staffResult.pinsHashed;
    }

    // Sync Reservations — the Cloud mirror the manager list and the public
    // website read, so neither has to dial the restaurant to ask. Not on the
    // realtime fast path: that one exists to move tables and orders quickly,
    // and a reservation change already brings a full snapshot with it.
    if (!realtimeOnly) {
      await timing.phase('reservations', () =>
        reservationSync.sync(tenant, reservations, Boolean(database)),
      );
    }

    // Business-day tracking, then the reporting values the POS computed.
    // Order matters: the rollover wipes the floor after the table snapshot was
    // applied, and `openTablesPayable` is stored after that.
    const rollover = await timing.phase('businessDay', () =>
      businessDaySync.trackBusinessDate(tenant, data.businessDate),
    );
    await timing.phase('reporting', () =>
      businessDaySync.persistReportingSnapshot(tenant, data, realtimeOnly),
    );

    const announce = async () => {
      // Realtime side effects. Per-record hints first, then the coarse
      // notifications — every write above has already landed.
      const { hadOrderLineTouch, hadTableTouch } = await timing.phase(
        'hints',
        () => this.broadcasts.relayPosHints(tenant, data),
      );

      const changed =
        didSyncTables || !!orders || !!expenses || !!menu || !!staff;

      this.broadcasts.announceSnapshotApplied(tenant, {
        orders,
        hadOrderLineTouch,
        hadTableTouch,
        didSyncTables,
        releasedTables: releasedTablesFromClosedOrders,
        changed,
      });

      if (rollover) {
        this.broadcasts.announceDayClosed(
          tenant,
          rollover.date,
          rollover.prevDate,
        );
      }
      // POS just pushed (so it's online): flush any held mobile changes to Hive
      // now instead of waiting out the retry backoff. Runs after order sync so
      // this push's stale snapshot is already held, not overwritten.
      void this.posOutbox.kickPending(tenant);
    };
    if (afterCommit) afterCommit.push(announce);
    else await announce();

    timing.note(
      `rows=${tables?.length ?? 0}t/${orders?.length ?? 0}o/` +
        `${menu?.length ?? 0}c/${reservations?.length ?? 0}r/` +
        `${expenses?.length ?? 0}e`,
    );
    // The staff phase is bcrypt or it is nothing, so the hash count is what
    // that phase's duration means. A routine snapshot reports zero.
    if (staff && staff.length > 0 && !realtimeOnly) {
      timing.note(`staff=${staff.length}/${staffPinsHashed}hashed`);
    }
    timing.log(realtimeOnly ? 'Backend/realtime' : 'Backend');

    return {
      success: true,
      syncedAt: new Date().toISOString(),
      ...(staffNeedingPin.length > 0 ? { staffNeedingPin } : {}),
      ...(saleLedgerAck.length > 0 ? { saleLedgerAck } : {}),
    };
  }
}
