import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../../prisma.service';
import { MonitoringGateway } from '../../../realtime/monitoring.gateway';
import { normalizeAuditEventType } from '../../audit/audit-event-type';
import { isPosAuditBroadcastSuppressed } from '../../sync-echo-guard';
import { AuditEventLogSync } from '../sync-payload';
import type { TenantContext } from '../../../auth/pos-auth-context';

/** One line of an audit report's history, as the POS records it. */
export interface AuditEventSync {
  type?: string;
  itemName?: string;
  previousQty?: number;
  newQty?: number;
  waiterId?: string;
  waiterName?: string;
  timestamp?: string;
  note?: string | null;
}

/** One report the POS says it holds, and the revision of it being offered. */
export interface AuditReportSync {
  reportId?: string;
  /** Content revision computed by the POS. Absent on builds predating Step 6C. */
  revision?: string;
  [field: string]: unknown;
}

export interface AuditReportAcknowledgement {
  reportId: string;
  /** Echoes the revision that was persisted, or null when none was offered. */
  revision: string | null;
}

export interface IngestAuditReportsBody {
  reports?: AuditReportSync[];
  /**
   * Legacy whole-history reconciliation: the payload is the complete set, so
   * anything absent from it is deleted. Only old POS builds send this.
   */
  fullSync?: boolean;
  /**
   * Incremental reconciliation: the complete list of report ids the POS holds,
   * without their contents. Sent occasionally so a restored or pruned POS can
   * still have its deletions reflected without re-uploading every report.
   */
  knownReportIds?: string[];
}

/**
 * How many reports one push may carry before it is worth complaining about.
 *
 * Not a rejection. An unupgraded POS still sends its whole history in one
 * request and must keep working; this only names the size at which the sender
 * is doing something the current contract no longer asks for.
 */
const LARGE_BATCH_WARNING_THRESHOLD = 500;

/**
 * Ingests the two audit streams the POS pushes.
 *
 * ## Reports
 *
 * A report is a full replacement of itself: the POS owns the event list, so its
 * events are deleted and rewritten with `seq` carrying the POS's ordering. That
 * makes any re-push idempotent, which is what lets delivery be retried freely.
 *
 * Since Step 6C the POS sends only the reports whose content changed, each with
 * a `revision`. This service persists the report, stores that revision, and
 * returns it in `acknowledged` — and the POS marks a revision synced only when
 * it appears there. A report whose stored revision already matches what is
 * offered is acknowledged without rewriting its events, which is what makes a
 * redelivered batch cheap instead of merely harmless.
 *
 * Nothing here trusts the payload for ownership. Reports are keyed by
 * `(venueId, reportId)` with `venueId` coming from the authenticated Device or
 * legacy sync principal, so a `reportId` belonging to another Venue addresses a
 * different row rather than that Venue's.
 *
 * ## Reconciliation
 *
 * Removing reports the POS no longer has is a separate question from uploading
 * the ones it does, and conflating them is what made every push carry the whole
 * history. `knownReportIds` answers it with a list of ids and no contents.
 * `fullSync` is the older form, kept because deployed POS builds still send it.
 *
 * Both are ignored when they would empty the Venue: a POS reporting that it
 * holds nothing at all is far more likely to be a store that failed to open
 * than an instruction to delete a restaurant's audit history.
 *
 * ## Event logs
 *
 * Append-only and keyed by the POS's own UUID, so an existing row is left
 * untouched. One bad row is logged and skipped rather than failing the batch:
 * these are diagnostics, and losing the rest would cost more than losing one.
 */
@Injectable()
export class IngestAuditReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
  ) {}

  async ingestReports(body: IngestAuditReportsBody, tenant: TenantContext) {
    const reports = Array.isArray(body?.reports) ? body.reports : [];
    const acknowledged: AuditReportAcknowledgement[] = [];

    if (reports.length > LARGE_BATCH_WARNING_THRESHOLD) {
      console.warn(
        `[SyncAudit] Venue ${tenant.venueId} pushed ${reports.length} reports in one request — ` +
          'this POS build predates incremental audit sync.',
      );
    }
    if (reports.length > 0) {
      console.log(
        `[SyncAudit] Venue ${tenant.venueId}: batch of ${reports.length} report(s)`,
      );
    }

    let upserted = 0;
    let unchanged = 0;
    for (const report of reports) {
      const reportId =
        typeof report?.reportId === 'string' ? report.reportId.trim() : '';
      if (!reportId) continue;

      const revision =
        typeof report.revision === 'string' && report.revision.length > 0
          ? report.revision
          : null;

      try {
        const skipped = await this.persistReport(
          tenant.venueId,
          reportId,
          revision,
          report,
        );
        if (skipped) {
          unchanged += 1;
        } else {
          upserted += 1;
        }
        // Acknowledged means persisted. A report that threw is deliberately
        // absent, so the POS keeps it dirty and offers it again.
        acknowledged.push({ reportId, revision });
      } catch (error) {
        console.warn(
          `[SyncAudit] Report ${reportId} failed: ${(error as Error).message}`,
        );
      }
    }

    await this.reconcile(tenant, body, reports);

    if (upserted > 0 && !isPosAuditBroadcastSuppressed()) {
      this.gateway.broadcastUpdate('audit_updated', { count: upserted });
    }

    return {
      success: true,
      // Kept as the count of reports actually written, which is what the
      // existing POS log line reports.
      upserted,
      unchanged,
      acknowledged,
    };
  }

  /**
   * Writes one report and its events. Returns true when the stored revision
   * already matched and nothing needed rewriting.
   */
  private async persistReport(
    venueId: string,
    reportId: string,
    revision: string | null,
    r: AuditReportSync,
  ): Promise<boolean> {
    const existing = await this.prisma.auditReport.findUnique({
      where: { venueId_reportId: { venueId, reportId } },
      select: { id: true, syncRevision: true },
    });

    // Same content as what is already stored. Acknowledge it without touching
    // the events — this is the path a redelivered batch takes.
    if (
      existing !== null &&
      revision !== null &&
      existing.syncRevision === revision
    ) {
      return true;
    }

    const fields = {
      posOrderId: typeof r.orderId === 'number' ? r.orderId : 0,
      tableNumbers: Array.isArray(r.tableNumbers)
        ? r.tableNumbers.map((entry) => String(entry))
        : [],
      floor: typeof r.floor === 'string' ? r.floor : 'first',
      openedById: typeof r.openedById === 'string' ? r.openedById : '',
      openedByName: typeof r.openedByName === 'string' ? r.openedByName : '',
      openedAt: r.openedAt ? new Date(r.openedAt as string) : new Date(),
      status: (typeof r.status === 'string' ? r.status : 'OPEN').toUpperCase(),
      closedAt: r.closedAt ? new Date(r.closedAt as string) : null,
      closedById: typeof r.closedById === 'string' ? r.closedById : null,
      closedByName: typeof r.closedByName === 'string' ? r.closedByName : null,
      locked: r.locked === true,
      syncRevision: revision,
      updatedAt: r.updatedAt ? new Date(r.updatedAt as string) : new Date(),
    };

    const dbReport = await this.prisma.auditReport.upsert({
      where: { venueId_reportId: { venueId, reportId } },
      update: fields,
      create: { venueId, reportId, ...fields },
    });

    await this.prisma.auditEvent.deleteMany({
      where: { reportId: dbReport.id },
    });

    const events: AuditEventSync[] = Array.isArray(r.events)
      ? (r.events as AuditEventSync[])
      : [];
    if (events.length > 0) {
      await this.prisma.auditEvent.createMany({
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

    return false;
  }

  /**
   * Deletes reports this Venue's POS says it no longer has.
   *
   * `knownReportIds` is the current form and carries ids only. `fullSync` is the
   * legacy form, where the uploaded batch *is* the complete set — which is only
   * true for a POS build that still sends its whole history, so it is honoured
   * exactly as before for those and never inferred for an incremental batch.
   */
  private async reconcile(
    tenant: TenantContext,
    body: IngestAuditReportsBody,
    reports: AuditReportSync[],
  ): Promise<void> {
    let keep: string[] | null = null;

    if (Array.isArray(body?.knownReportIds)) {
      keep = body.knownReportIds
        .map((id: unknown) => (typeof id === 'string' ? id.trim() : ''))
        .filter((id) => id.length > 0);
    } else if (body?.fullSync === true) {
      keep = reports
        .map((r) => (typeof r?.reportId === 'string' ? r.reportId.trim() : ''))
        .filter((id) => id.length > 0);
    }

    if (keep === null) return;

    // An empty set is not a delete-everything instruction. A POS whose audit
    // box failed to open reports exactly this, and honouring it would destroy
    // the server's copy of a restaurant's audit history on a local fault.
    if (keep.length === 0) {
      console.warn(
        `[SyncAudit] Venue ${tenant.venueId} reconciled with an empty report set — ignored.`,
      );
      return;
    }

    const stale = await this.prisma.auditReport.findMany({
      where: { venueId: tenant.venueId, reportId: { notIn: keep } },
      select: { id: true },
    });
    if (stale.length === 0) return;

    const staleIds = stale.map((row) => row.id);
    await this.prisma.auditEvent.deleteMany({
      where: { reportId: { in: staleIds } },
    });
    await this.prisma.auditReport.deleteMany({
      where: { id: { in: staleIds } },
    });
    console.log(
      `[SyncAudit] Venue ${tenant.venueId}: removed ${staleIds.length} report(s) the POS no longer has`,
    );
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
        const existing = await this.prisma.auditEventLog.findFirst({
          where: { id: log.id, venueId: tenant.venueId },
          select: { id: true },
        });
        if (!existing) {
          await this.prisma.auditEventLog.create({
            data: {
              id: log.id,
              venueId: tenant.venueId,
              action: log.action,
              userId: log.userId,
              data: (log.data ?? {}) as Prisma.InputJsonValue,
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
