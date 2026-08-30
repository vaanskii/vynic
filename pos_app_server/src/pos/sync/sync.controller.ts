import {
  Body,
  Controller,
  Get,
  OnModuleInit,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { PosSyncGuard } from '../../auth/pos-sync.guard';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { RolesGuard } from '../../auth/roles.guard';
import { Roles } from '../../auth/roles.decorator';
import { StaffRole } from '../../staff/staff-role';
import { normalizeAuditEventType } from '../audit/audit-event-type';
import { isPosAuditBroadcastSuppressed } from '../sync-echo-guard';
import { IngestPosSnapshotService } from './application/ingest-pos-snapshot.service';
import { PosConnectionRegistry } from './pos-connection.registry';
// `import type`: interfaces named in a decorated signature must not be value
// imports while isolatedModules + emitDecoratorMetadata are both on.
import type { AuditEventLogSync, SyncPayload } from './sync-payload';

/**
 * HTTP surface of POS → server synchronization.
 *
 * Routes, guards and payload hand-off only. The work of applying a snapshot
 * belongs to `IngestPosSnapshotService`; the durable POS handshake belongs to
 * `PosConnectionRegistry`. Route paths, guards and response shapes are the
 * Flutter POS's contract and must not change here.
 */
@Controller('sync')
export class SyncController implements OnModuleInit {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly ingestSnapshot: IngestPosSnapshotService,
    private readonly posConnection: PosConnectionRegistry,
  ) {}

  /**
   * Restore the POS callback address on boot. Kept as a controller hook so it
   * still runs at the same point in the Nest lifecycle as before the split.
   */
  async onModuleInit(): Promise<void> {
    await this.posConnection.restore();
  }

  @Get('ping')
  ping() {
    return {
      ok: true,
      serverTime: new Date().toISOString(),
    };
  }

  /**
   * GET /sync/diff?since=2024-01-01T00:00:00.000Z
   * Returns only records updated after `since`.
   * Mobile clients call this after reconnection instead of full reload.
   * Manager-only (mobile JWT) — exposes live table/order deltas, so it must
   * not be reachable unauthenticated.
   */
  @Get('diff')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(StaffRole.MANAGER)
  async getDiff(@Query('since') since?: string) {
    const sinceDate = since ? new Date(since) : new Date(0);

    const [tables, orders] = await Promise.all([
      (this.prisma as any).table.findMany({
        where: { updatedAt: { gt: sinceDate } },
      }),
      this.prisma.order.findMany({
        where: { updatedAt: { gt: sinceDate } },
        select: {
          posOrderId: true,
          status: true,
          totalAmount: true,
          waiterName: true,
          updatedAt: true,
        },
      }),
    ]);

    return {
      tables,
      orders,
      serverTime: new Date().toISOString(),
    };
  }

  @Post('manager-data')
  @UseGuards(PosSyncGuard)
  async syncManagerData(@Body() data: SyncPayload) {
    return this.ingestSnapshot.execute(data);
  }

  /**
   * POST /sync/audit-reports
   * Windows POS pushes full AuditReport list (with events) here on every change.
   * Uses upsert-by-reportId so re-pushes are idempotent.
   */
  @Post('audit-reports')
  @UseGuards(PosSyncGuard)
  async syncAuditReports(
    @Body() body: { reports?: any[]; fullSync?: boolean },
  ) {
    const reports = body?.reports;
    const fullSync = body?.fullSync === true;
    if (!Array.isArray(reports)) {
      console.log('[SyncAudit] Invalid reports payload');
      return { success: true, upserted: 0 };
    }

    console.log(`[SyncAudit] Processing batch of ${reports.length} reports...`);

    let upserted = 0;
    for (const r of reports) {
      const reportId = r.reportId as string | undefined;
      if (!reportId) continue;

      const syncedUpdatedAt = r.updatedAt ? new Date(r.updatedAt) : new Date();

      // Upsert the AuditReport row
      const dbReport = await (this.prisma as any).auditReport.upsert({
        where: { reportId },
        update: {
          posOrderId: r.orderId ?? 0,
          tableNumbers: Array.isArray(r.tableNumbers) ? r.tableNumbers : [],
          floor: r.floor ?? 'first',
          openedById: r.openedById ?? '',
          openedByName: r.openedByName ?? '',
          openedAt: r.openedAt ? new Date(r.openedAt) : new Date(),
          status: (r.status ?? 'OPEN').toUpperCase(),
          closedAt: r.closedAt ? new Date(r.closedAt) : null,
          closedById: r.closedById ?? null,
          closedByName: r.closedByName ?? null,
          locked: r.locked ?? false,
          updatedAt: syncedUpdatedAt,
        },
        create: {
          reportId,
          posOrderId: r.orderId ?? 0,
          tableNumbers: Array.isArray(r.tableNumbers) ? r.tableNumbers : [],
          floor: r.floor ?? 'first',
          openedById: r.openedById ?? '',
          openedByName: r.openedByName ?? '',
          openedAt: r.openedAt ? new Date(r.openedAt) : new Date(),
          status: (r.status ?? 'OPEN').toUpperCase(),
          closedAt: r.closedAt ? new Date(r.closedAt) : null,
          closedById: r.closedById ?? null,
          closedByName: r.closedByName ?? null,
          locked: r.locked ?? false,
          updatedAt: syncedUpdatedAt,
        },
      });

      // Optimized event sync: Delete and createMany
      await (this.prisma as any).auditEvent.deleteMany({
        where: { reportId: dbReport.id },
      });

      const events: any[] = Array.isArray(r.events) ? r.events : [];
      if (events.length > 0) {
        console.log(`  Report ${reportId}: syncing ${events.length} events...`);
        await (this.prisma as any).auditEvent.createMany({
          data: events.map((ev, seq) => ({
            reportId: dbReport.id,
            type: normalizeAuditEventType(ev.type, ev.previousQty, ev.newQty),
            itemName: ev.itemName ?? '',
            previousQty: ev.previousQty ?? 0,
            newQty: ev.newQty ?? 0,
            waiterId: ev.waiterId ?? '',
            waiterName: ev.waiterName ?? '',
            eventTime: ev.timestamp ? new Date(ev.timestamp) : new Date(),
            note: ev.note ?? null,
            seq,
          })),
        });
      }
      upserted++;
    }

    // Full reconciliation mode: remove stale backend reports not present in
    // current Windows snapshot (important after backup restore/import).
    if (fullSync) {
      const incomingReportIds = reports
        .map((r) => r?.reportId as string | undefined)
        .filter((id): id is string => !!id);

      const staleReports = await (this.prisma as any).auditReport.findMany({
        where:
          incomingReportIds.length > 0
            ? { reportId: { notIn: incomingReportIds } }
            : {},
        select: { id: true },
      });

      if (staleReports.length > 0) {
        const staleIds = staleReports.map((r: any) => r.id as string);
        await (this.prisma as any).auditEvent.deleteMany({
          where: { reportId: { in: staleIds } },
        });
        await (this.prisma as any).auditReport.deleteMany({
          where: { id: { in: staleIds } },
        });
      }
    }

    if (upserted > 0 && !isPosAuditBroadcastSuppressed()) {
      this.gateway.broadcastUpdate('audit_updated', { count: upserted });
    }
    return { success: true, upserted };
  }

  /**
   * POST /sync/audit-logs
   * Syncs generic audit event logs (append-only).
   * Idempotent based on UUID.
   */
  @Post('audit-logs')
  @UseGuards(PosSyncGuard)
  async syncAuditEventLogs(@Body() body: { logs?: AuditEventLogSync[] }) {
    const logs = body?.logs;
    if (!Array.isArray(logs) || logs.length === 0) {
      return { success: true, count: 0 };
    }

    let count = 0;
    for (const log of logs) {
      try {
        await (this.prisma as any).auditEventLog.upsert({
          where: { id: log.id },
          update: {}, // Immutable: do nothing if exists
          create: {
            id: log.id,
            action: log.action,
            userId: log.userId,
            data: log.data ?? {},
            deviceType: log.deviceType,
            createdAt: log.createdAt ? new Date(log.createdAt) : new Date(),
          },
        });
        count++;
      } catch (e) {
        // Log error but continue with other logs
        console.warn(
          `[Sync] Error upserting audit log ${log.id}:`,
          (e as Error).message,
        );
      }
    }

    return { success: true, count };
  }
}
