import { withOperationalAuthority } from '../../edge/operational-authority';
import {
  Body,
  Controller,
  Get,
  OnModuleInit,
  Post,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { PosSyncGuard } from '../../auth/pos-sync.guard';
import { PosAuth } from '../../auth/pos-auth-context';
import type { PosAuthContext } from '../../auth/pos-auth-context';
import { IngestAuditReportsService } from './application/ingest-audit-reports.service';
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
    private readonly ingestSnapshot: IngestPosSnapshotService,
    private readonly ingestAudit: IngestAuditReportsService,
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

  @Post('manager-data')
  @UseGuards(PosSyncGuard)
  async syncManagerData(
    @Body() data: SyncPayload,
    @PosAuth() authContext: PosAuthContext,
  ) {
    const afterCommit: Array<() => Promise<void>> = [];
    const result = await withOperationalAuthority(
      this.prisma,
      authContext,
      async (db) => {
        const result = await this.ingestSnapshot.execute(
          data,
          authContext,
          db,
          afterCommit,
        );
        if (result.success && !data.realtimeOnly && authContext.deviceId) {
          await db.device.updateMany({
            where: {
              id: authContext.deviceId,
              venueId: authContext.venueId,
              firstSyncAt: null,
            },
            data: { firstSyncAt: new Date() },
          });
        }
        return result;
      },
    );
    for (const notify of afterCommit) await notify();
    return result;
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
    @PosAuth() authContext: PosAuthContext,
  ) {
    const afterCommit: Array<() => Promise<void>> = [];
    const result = await withOperationalAuthority(
      this.prisma,
      authContext,
      (db) =>
        this.ingestAudit
          .withDatabase(db, afterCommit)
          .ingestReports(body, authContext),
    );
    for (const notify of afterCommit) await notify();
    return result;
  }

  /**
   * POST /sync/audit-logs
   * Syncs generic audit event logs (append-only).
   * Idempotent based on UUID.
   */
  @Post('audit-logs')
  @UseGuards(PosSyncGuard)
  async syncAuditEventLogs(
    @Body() body: { logs?: AuditEventLogSync[] },
    @PosAuth() authContext: PosAuthContext,
  ) {
    const afterCommit: Array<() => Promise<void>> = [];
    const result = await withOperationalAuthority(
      this.prisma,
      authContext,
      (db) =>
        this.ingestAudit
          .withDatabase(db, afterCommit)
          .ingestEventLogs(body, authContext),
    );
    for (const notify of afterCommit) await notify();
    return result;
  }
}
