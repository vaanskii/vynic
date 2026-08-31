import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import { MonitoringGateway } from '../../../realtime/monitoring.gateway';
import { normalizeAuditEventType } from '../../audit/audit-event-type';
import { isPosAuditBroadcastSuppressed } from '../../sync-echo-guard';
import { AuditEventLogSync } from '../sync-payload';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * Ingests the two audit streams the POS pushes.
 *
 * Audit reports are a full replacement per report: the POS owns the event
 * list, so its events are deleted and rewritten with `seq` carrying the POS's
 * ordering. That makes a re-push idempotent, which matters because the POS
 * re-pushes the whole batch on every change.
 *
 * `fullSync` additionally removes reports the POS no longer has. The case that
 * motivates it is a backup restore, after which the server would otherwise
 * keep reports the restored POS has never heard of.
 *
 * Audit event logs are append-only and keyed by the POS's own UUID, so an
 * existing row is left untouched. One bad row is logged and skipped rather
 * than failing the batch: these are diagnostics, and losing the rest of the
 * batch would cost more than losing one entry.
 */
@Injectable()
export class IngestAuditReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
  ) {}

  async ingestReports(
    body: { reports?: any[]; fullSync?: boolean },
    tenant: TenantContext,
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
        where: {
          venueId_reportId: { venueId: tenant.venueId, reportId },
        },
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
          venueId: tenant.venueId,
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
        where: {
          venueId: tenant.venueId,
          ...(incomingReportIds.length > 0
            ? { reportId: { notIn: incomingReportIds } }
            : {}),
        },
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

  async ingestEventLogs(
    body: { logs?: AuditEventLogSync[] },
    tenant: TenantContext,
  ) {
    const logs = body?.logs;
    if (!Array.isArray(logs) || logs.length === 0) {
      return { success: true, count: 0 };
    }

    let count = 0;
    for (const log of logs) {
      try {
        const existing = await (this.prisma as any).auditEventLog.findFirst({
          where: { id: log.id, venueId: tenant.venueId },
          select: { id: true },
        });
        if (!existing) {
          await (this.prisma as any).auditEventLog.create({
            data: {
              id: log.id,
              venueId: tenant.venueId,
              action: log.action,
              userId: log.userId,
              data: log.data ?? {},
              deviceType: log.deviceType,
              createdAt: log.createdAt ? new Date(log.createdAt) : new Date(),
            },
          });
        }
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
