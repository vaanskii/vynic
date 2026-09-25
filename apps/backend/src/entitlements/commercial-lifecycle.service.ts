import { reconcileSubscription } from '../subscriptions/subscription-reconciliation';
import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { PrismaService } from '../prisma.service';
import { commercialState } from './commercial-state';
export const DOMAIN_GRACE_MS = 30 * 86400000;

@Injectable()
export class CommercialLifecycleService {
  private readonly logger = new Logger(CommercialLifecycleService.name);
  constructor(private readonly db: PrismaService) {}
  /** Locks make timer/read/retry/multiple backend workers converge to one audit. */
  async reconcile(venueId: string, now = new Date()) {
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      await reconcileSubscription(tx, venueId, now);
      const state = await commercialState(tx, venueId, now);
      const eligible = state.features.includes('WEBSITE');
      for (const domain of await tx.venueDomain.findMany({
        where: { venueId },
      })) {
        if (eligible && domain.releaseAfter) {
          await tx.venueDomain.update({
            where: { id: domain.id },
            data: { releaseAfter: null },
          });
          await tx.platformAuditEvent.create({
            data: {
              action: 'domain.retention_cancelled',
              targetType: 'Venue',
              targetId: venueId,
              metadata: { hostname: domain.hostname, source: 'SYSTEM' },
            },
          });
        } else if (!eligible && !domain.releaseAfter) {
          const releaseAfter = new Date(now.getTime() + DOMAIN_GRACE_MS);
          await tx.venueDomain.update({
            where: { id: domain.id },
            data: { releaseAfter },
          });
          await tx.platformAuditEvent.create({
            data: {
              action: 'domain.retention_started',
              targetType: 'Venue',
              targetId: venueId,
              metadata: {
                hostname: domain.hostname,
                releaseAfter: releaseAfter.toISOString(),
                source: 'SYSTEM',
              },
            },
          });
        } else if (!eligible && domain.releaseAfter! <= now) {
          await tx.venueDomain.delete({ where: { id: domain.id } });
          await tx.platformAuditEvent.create({
            data: {
              action: 'domain.released_after_grace',
              targetType: 'Venue',
              targetId: venueId,
              metadata: { hostname: domain.hostname, source: 'SYSTEM' },
            },
          });
        }
      }
    });
  }
  async sweep(now = new Date()) {
    const rows = await this.db.venue.findMany({
      where: {
        OR: [
          {
            subscription: {
              status: 'TRIAL',
              OR: [{ trialEndsAt: { lte: now } }, { trialEndsAt: null }],
            },
          },
          {
            subscription: {
              billingManaged: true,
              currentPeriodEndsAt: { lte: now },
              status: { not: 'CANCELLED' },
            },
          },
          { domains: { some: {} } },
        ],
      },
      select: { id: true },
    });
    for (const row of rows) await this.reconcile(row.id, now);
  }
  @Interval(60000)
  async scheduledSweep() {
    try {
      await this.sweep();
    } catch (error) {
      this.logger.error(
        'Commercial lifecycle sweep failed',
        error instanceof Error ? error.stack : String(error),
      );
    }
  }
}
