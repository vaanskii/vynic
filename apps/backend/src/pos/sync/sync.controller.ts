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
import { PosSyncGuard } from '../../auth/pos-sync.guard';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { RolesGuard } from '../../auth/roles.guard';
import { Roles } from '../../auth/roles.decorator';
import { StaffRole } from '../../staff/staff-role';
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
    return this.ingestAudit.ingestReports(body);
  }

  /**
   * POST /sync/audit-logs
   * Syncs generic audit event logs (append-only).
   * Idempotent based on UUID.
   */
  @Post('audit-logs')
  @UseGuards(PosSyncGuard)
  async syncAuditEventLogs(@Body() body: { logs?: AuditEventLogSync[] }) {
    return this.ingestAudit.ingestEventLogs(body);
  }
}
