import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import { TableSync } from '../sync-payload';
import { upsertTableRecord } from './table-record-identity';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * Applies the POS's table snapshot.
 *
 * The one real policy here is the cold-boot guard: a POS that has just started
 * can push every table as free before it has loaded Hive. Accepting that would
 * wipe the floor, so on the full-sync path an all-free snapshot is ignored
 * while the server still holds reserved tables. Realtime pushes always apply —
 * "manager closed the last table on Windows" is exactly an all-free snapshot.
 */
@Injectable()
export class TableSyncService {
  constructor(private readonly prisma: PrismaService) {}

  /** Returns whether the snapshot was actually applied. */
  async sync(
    tenant: TenantContext,
    tables: TableSync[] | undefined,
    realtimeOnly: boolean,
  ): Promise<boolean> {
    let didSync = false;
    // Strategy: The POS is the source of truth.
    // We only process a full table sync if the POS payload contains at least
    // one reserved table OR an explicit activeOrderId. If the POS sends ALL
    // tables as free (e.g., on a cold/uninitialized boot), we preserve the
    // existing cloud state to prevent data loss.
    if (tables && tables.length > 0) {
      const hasAnyReserved = tables.some(
        (t) =>
          t.isReserved ||
          (t.activeOrderId !== undefined && t.activeOrderId !== null),
      );

      // Get existing reserved count in DB to detect if POS data seems stale
      const existingReservedCount = await (this.prisma as any).table.count({
        where: { venueId: tenant.venueId, isReserved: true },
      });

      // If the DB has reserved tables but POS is saying all are free, it's
      // a stale push (POS just booted). Skip the "free all" to preserve state.
      // Only skip "all free" snapshot on cold full sync (POS boot). Realtime pushes
      // must always apply — e.g. manager closes a table on Windows.
      const isPosDataStale =
        !realtimeOnly && existingReservedCount > 0 && !hasAnyReserved;

      if (isPosDataStale) {
        console.log(
          `Skipping table sync: DB has ${existingReservedCount} reserved tables but POS sent 0. POS may be initializing.`,
        );
      } else {
        didSync = true;
        console.log(
          `Syncing ${tables.length} tables (hasAnyReserved=${hasAnyReserved}, realtimeOnly=${!!realtimeOnly})...`,
        );
        for (const table of tables) {
          const isActuallyReserved =
            table.isReserved ||
            (table.activeOrderId !== undefined && table.activeOrderId !== null);

          if (isActuallyReserved) {
            console.log(
              `  Table ${table.tableNumber}/${table.floor} → reserved (orderId=${table.activeOrderId})`,
            );
          }

          await upsertTableRecord(
            this.prisma,
            tenant,
            {
              tableId: table.tableId,
              tableNumber: table.tableNumber,
              floor: table.floor,
            },
            {
              isReserved: isActuallyReserved,
              activeOrderId: isActuallyReserved
                ? (table.activeOrderId ?? null)
                : null,
              currentBill: isActuallyReserved ? (table.currentBill ?? 0) : 0,
            },
          );
        }
      }
    } else if (tables && tables.length === 0) {
      console.log(
        'Skipping table sync: empty tables array received (POS may be initializing)',
      );
    }
    return didSync;
  }
}
