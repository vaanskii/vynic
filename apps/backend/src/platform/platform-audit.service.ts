import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { PlatformPrincipal } from './platform-auth-context';

/** The actions worth being able to answer "who did this?" about. */
export const PlatformAuditAction = {
  ORGANIZATION_CREATED: 'organization.created',
  ORGANIZATION_UPDATED: 'organization.updated',
  VENUE_CREATED: 'venue.created',
  VENUE_UPDATED: 'venue.updated',
  VENUE_STATUS_CHANGED: 'venue.status_changed',
  PLAN_ASSIGNED: 'venue.plan_assigned',
  FEATURE_OVERRIDE_SET: 'venue.feature_override_set',
  FEATURE_OVERRIDE_REMOVED: 'venue.feature_override_removed',
  WEBSITE_MODE_CHANGED: 'venue.website_mode_changed',
  DOMAIN_REGISTERED: 'venue.domain_registered',
  DOMAIN_STATUS_CHANGED: 'venue.domain_status_changed',
  DOMAIN_RELEASED: 'venue.domain_released',
  DEVICE_CREATED: 'device.created',
  DEVICE_STATUS_CHANGED: 'device.status_changed',
  DEVICE_CREDENTIAL_ISSUED: 'device.credential_issued',
  DEVICE_ENROLLMENT_CREATED: 'device.enrollment_created',
  DEVICE_ENROLLMENT_CANCELLED: 'device.enrollment_cancelled',
  DEVICE_ENROLLMENT_REDEEMED: 'device.enrollment_redeemed',
  DEVICE_ENROLLMENT_FAILED: 'device.enrollment_failed',
  EDGE_TEST_COMMAND_ENQUEUED: 'device.edge_test_command_enqueued',
} as const;

export type PlatformAuditActionValue =
  (typeof PlatformAuditAction)[keyof typeof PlatformAuditAction];

/**
 * The platform's own audit trail.
 *
 * Kept apart from `AuditEventLog`, which records what restaurant staff did
 * inside a Venue. Writing a platform action there would claim an employee
 * changed a plan or revoked a device — precisely the wrong answer.
 *
 * Recording never blocks the action it describes. A control-plane mutation that
 * succeeded must not be reported as failed because its audit row could not be
 * written; the failure is logged loudly instead.
 *
 * The actor is a `PlatformUser` because every action here was authorized by
 * one. Enrollment redemption is performed by a terminal rather than a person,
 * and is attributed to the administrator whose enrollment code authorized it —
 * with the metadata saying so, so nobody reads it as an administrator having
 * created a device by hand.
 */
@Injectable()
export class PlatformAuditService {
  private readonly logger = new Logger(PlatformAuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(
    actor: Pick<PlatformPrincipal, 'platformUserId'>,
    action: PlatformAuditActionValue,
    target: { type: string; id: string },
    metadata?: Record<string, unknown>,
  ): Promise<void> {
    try {
      await this.prisma.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action,
          targetType: target.type,
          targetId: target.id,
          // Callers pass only what is safe to keep. Nothing here ever receives
          // a password, a credential or a hash.
          metadata: (metadata ?? undefined) as Prisma.InputJsonValue,
        },
      });
    } catch (error) {
      this.logger.error(
        `Failed to audit ${action} on ${target.type} ${target.id}: ${(error as Error).message}`,
      );
    }
  }

  /** Most recent first, with bounded offset pagination for the admin panel. */
  async recent(
    limit: number,
    offset: number,
    targetId?: string,
    venueId?: string,
  ) {
    const deviceIds = venueId
      ? (
          await this.prisma.device.findMany({
            where: { venueId },
            select: { id: true },
          })
        ).map((device) => device.id)
      : [];

    return this.prisma.platformAuditEvent.findMany({
      where: venueId
        ? {
            OR: [
              { targetType: 'Venue', targetId: venueId },
              ...(deviceIds.length
                ? [{ targetType: 'Device', targetId: { in: deviceIds } }]
                : []),
            ],
          }
        : targetId
          ? { targetId }
          : undefined,
      orderBy: { createdAt: 'desc' },
      take: limit,
      skip: offset,
      select: {
        id: true,
        action: true,
        targetType: true,
        targetId: true,
        metadata: true,
        createdAt: true,
        actor: { select: { id: true, email: true, displayName: true } },
      },
    });
  }
}
