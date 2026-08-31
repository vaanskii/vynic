import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { EdgeCommandStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import type { EdgeDeviceContext } from './edge-device-context';
import {
  EDGE_COMMAND_CLAIM_LEASE_SECONDS,
  EDGE_COMMAND_CONTRACT_VERSION,
  EDGE_COMMAND_DEFAULT_BATCH_SIZE,
  EDGE_COMMAND_MAX_ATTEMPTS,
  EDGE_COMMAND_MAX_BATCH_SIZE,
  EDGE_IDEMPOTENT_COMMAND_TYPES,
  type EdgeCommandEnvelope,
  type EdgeCommandResultStatus,
} from '../shared/contracts/edge-command';

export interface EnqueueEdgeCommand {
  /** Null targets the Venue's Edge installation; set targets one Device. */
  deviceId?: string | null;
  type: string;
  payload: Record<string, unknown>;
  /** Stable per Venue. The same intent enqueued twice is one command. */
  idempotencyKey: string;
  contractVersion?: number;
  availableAt?: Date;
  maxAttempts?: number;
}

export interface ClaimEdgeCommands {
  limit?: number;
  /** Contract versions this Edge build understands. Omitted means "any". */
  acceptedContractVersions?: number[];
}

export interface AcknowledgeEdgeCommand {
  commandId: string;
  status: EdgeCommandResultStatus;
  code?: string | null;
  detail?: string | null;
}

export interface AcknowledgeResult {
  commandId: string;
  status: EdgeCommandStatus;
  /** True when this acknowledgment found the command already terminal. */
  alreadyAcknowledged: boolean;
}

/** Deterministic: two Edges asking at the same instant see the same order. */
const CLAIM_ORDER: Prisma.EdgeCommandOrderByWithRelationInput[] = [
  { availableAt: 'asc' },
  { createdAt: 'asc' },
  { id: 'asc' },
];

/**
 * The Cloud → Edge work queue.
 *
 * Cloud cannot dial a restaurant's LAN, so it never delivers: it holds work
 * until an Edge asks for it. A claim is a lease, not a completion — the Edge
 * executes locally and reports the outcome, and a lease that expires without one
 * is offered again. That makes delivery at-least-once, which is why every
 * command type has to be safe to run twice.
 *
 * Tenancy comes from the Device credential the caller authenticated with.
 * Nothing here reads a venueId or deviceId from a request body.
 */
@Injectable()
export class EdgeCommandService {
  private readonly logger = new Logger(EdgeCommandService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Record work for a Venue's Edge.
   *
   * Internal only — there is no HTTP route for it. Enqueueing is a control-plane
   * action and the platform-admin boundary that would authorize one does not
   * exist yet, so exposing it would be a hole rather than a feature.
   *
   * Keyed by (venueId, idempotencyKey), so a repeated enqueue updates the one
   * command instead of creating a second. A command that already ended is
   * revived with a fresh attempt budget — that is how a terminal failure is
   * deliberately re-issued. A command currently leased to an Edge keeps its
   * lease; the refreshed payload reaches it on the next delivery.
   */
  async enqueue(
    tenant: Pick<TenantContext, 'venueId'>,
    command: EnqueueEdgeCommand,
  ): Promise<{ id: string; status: EdgeCommandStatus }> {
    if (!command.idempotencyKey.trim()) {
      throw new BadRequestException('idempotencyKey is required');
    }
    if (!EDGE_IDEMPOTENT_COMMAND_TYPES.has(command.type)) {
      // At-least-once delivery will eventually hand a command over twice. A type
      // whose Edge handler cannot absorb that must not be queued at all.
      throw new BadRequestException(
        `Command type ${command.type} is not declared idempotent and cannot be queued`,
      );
    }
    if (command.deviceId) {
      await this.assertDeviceBelongsToVenue(tenant.venueId, command.deviceId);
    }

    const existing = await this.prisma.edgeCommand.findUnique({
      where: {
        venueId_idempotencyKey: {
          venueId: tenant.venueId,
          idempotencyKey: command.idempotencyKey,
        },
      },
      select: { id: true, status: true },
    });

    const shared = {
      deviceId: command.deviceId ?? null,
      type: command.type,
      contractVersion: command.contractVersion ?? EDGE_COMMAND_CONTRACT_VERSION,
      payload: command.payload as Prisma.InputJsonValue,
      availableAt: command.availableAt ?? new Date(),
      maxAttempts: command.maxAttempts ?? EDGE_COMMAND_MAX_ATTEMPTS,
    };

    if (!existing) {
      const created = await this.prisma.edgeCommand.create({
        data: {
          venueId: tenant.venueId,
          idempotencyKey: command.idempotencyKey,
          ...shared,
        },
        select: { id: true, status: true },
      });
      return created;
    }

    const revive = existing.status !== EdgeCommandStatus.CLAIMED;
    const updated = await this.prisma.edgeCommand.update({
      where: { id: existing.id },
      data: {
        ...shared,
        ...(revive
          ? {
              status: EdgeCommandStatus.PENDING,
              attemptCount: 0,
              claimedAt: null,
              claimedByDeviceId: null,
              claimExpiresAt: null,
              acknowledgedAt: null,
              resultCode: null,
              resultDetail: null,
            }
          : {}),
      },
      select: { id: true, status: true },
    });
    return updated;
  }

  /**
   * Hand an Edge the work waiting for it.
   *
   * Eligible work is this Venue's, either unaddressed or addressed to this
   * Device. Another Venue's queue is not reachable: the filter is built from the
   * authenticated Device, and there is no parameter that could widen it.
   */
  async claim(
    device: EdgeDeviceContext,
    request: ClaimEdgeCommands = {},
  ): Promise<EdgeCommandEnvelope[]> {
    const limit = this.resolveLimit(request.limit);
    const now = new Date();

    await this.releaseExpiredClaims(device.venueId, now);

    const versions = request.acceptedContractVersions?.filter((v) =>
      Number.isInteger(v),
    );
    const eligible = await this.prisma.edgeCommand.findMany({
      where: {
        venueId: device.venueId,
        status: EdgeCommandStatus.PENDING,
        availableAt: { lte: now },
        OR: [{ deviceId: null }, { deviceId: device.deviceId }],
        ...(versions?.length ? { contractVersion: { in: versions } } : {}),
      },
      orderBy: CLAIM_ORDER,
      take: limit,
      select: { id: true },
    });
    if (eligible.length === 0) return [];

    const ids = eligible.map((row) => row.id);
    const leaseExpiresAt = new Date(
      now.getTime() + EDGE_COMMAND_CLAIM_LEASE_SECONDS * 1000,
    );

    // The status guard is what makes this safe against a second Edge polling at
    // the same instant: whoever writes first wins, and the loser simply claims
    // fewer rows. A multi-Device Venue under real contention would be better
    // served by SELECT ... FOR UPDATE SKIP LOCKED; today a Venue runs one Edge.
    await this.prisma.edgeCommand.updateMany({
      where: { id: { in: ids }, status: EdgeCommandStatus.PENDING },
      data: {
        status: EdgeCommandStatus.CLAIMED,
        claimedAt: now,
        claimedByDeviceId: device.deviceId,
        claimExpiresAt: leaseExpiresAt,
        attemptCount: { increment: 1 },
      },
    });

    const claimed = await this.prisma.edgeCommand.findMany({
      where: {
        id: { in: ids },
        status: EdgeCommandStatus.CLAIMED,
        claimedByDeviceId: device.deviceId,
        claimedAt: now,
      },
      orderBy: CLAIM_ORDER,
    });

    return claimed.map((row) => ({
      contractVersion: row.contractVersion,
      commandId: row.id,
      type: row.type,
      payload: row.payload,
      idempotencyKey: row.idempotencyKey,
      attempt: row.attemptCount,
      issuedAt: now.toISOString(),
      leaseExpiresAt: leaseExpiresAt.toISOString(),
    }));
  }

  /**
   * Record what happened to a command.
   *
   * Idempotent by construction: a command that already ended keeps the outcome
   * it ended with, and the repeat acknowledgment says so rather than rewriting
   * history. An explicit failure is terminal — the Edge ran it and it failed, so
   * repeating it automatically would just repeat the failure. Silence is what
   * gets retried, through lease expiry.
   */
  async acknowledge(
    device: EdgeDeviceContext,
    ack: AcknowledgeEdgeCommand,
  ): Promise<AcknowledgeResult> {
    const command = await this.prisma.edgeCommand.findUnique({
      where: { id: ack.commandId },
      select: {
        id: true,
        venueId: true,
        deviceId: true,
        status: true,
        claimedByDeviceId: true,
      },
    });

    // Another Venue's command is reported as missing, not as forbidden: an
    // acknowledgment must not become a way to probe which ids exist elsewhere.
    if (!command || command.venueId !== device.venueId) {
      throw new NotFoundException('Command not found');
    }
    if (
      command.claimedByDeviceId !== null &&
      command.claimedByDeviceId !== device.deviceId
    ) {
      throw new ForbiddenException('This command is leased to another device');
    }
    if (command.deviceId !== null && command.deviceId !== device.deviceId) {
      throw new ForbiddenException(
        'This command is addressed to another device',
      );
    }

    if (
      command.status === EdgeCommandStatus.SUCCEEDED ||
      command.status === EdgeCommandStatus.FAILED
    ) {
      return {
        commandId: command.id,
        status: command.status,
        alreadyAcknowledged: true,
      };
    }

    const status =
      ack.status === 'SUCCEEDED'
        ? EdgeCommandStatus.SUCCEEDED
        : EdgeCommandStatus.FAILED;

    const updated = await this.prisma.edgeCommand.update({
      where: { id: command.id },
      data: {
        status,
        acknowledgedAt: new Date(),
        claimExpiresAt: null,
        resultCode: ack.code?.slice(0, 200) ?? null,
        resultDetail: ack.detail?.slice(0, 2000) ?? null,
      },
      select: { id: true, status: true },
    });

    return {
      commandId: updated.id,
      status: updated.status,
      alreadyAcknowledged: false,
    };
  }

  /**
   * Return leases nobody came back for.
   *
   * This is the answer to "what happens when an Edge crashes between receiving a
   * command and acknowledging it": nothing is lost, the lease simply runs out
   * and the command is offered again. Swept lazily at claim time rather than by
   * a background timer, so there is one less thing running on a schedule.
   */
  async releaseExpiredClaims(venueId: string, now = new Date()): Promise<void> {
    // Read first, because the attempt budget is a per-row column and a single
    // updateMany cannot compare two columns to each other.
    const expired = await this.prisma.edgeCommand.findMany({
      where: {
        venueId,
        status: EdgeCommandStatus.CLAIMED,
        claimExpiresAt: { lte: now },
      },
      select: { id: true, attemptCount: true, maxAttempts: true },
    });
    if (expired.length === 0) return;

    const exhausted = expired
      .filter((row) => row.attemptCount >= row.maxAttempts)
      .map((row) => row.id);
    const retryable = expired
      .filter((row) => row.attemptCount < row.maxAttempts)
      .map((row) => row.id);

    // A command that has used its whole attempt budget stops being offered, but
    // is kept with the reason recorded — history is never deleted to make room.
    if (exhausted.length > 0) {
      await this.prisma.edgeCommand.updateMany({
        where: { id: { in: exhausted }, status: EdgeCommandStatus.CLAIMED },
        data: {
          status: EdgeCommandStatus.FAILED,
          acknowledgedAt: now,
          claimExpiresAt: null,
          resultCode: 'lease_expired_attempts_exhausted',
        },
      });
      this.logger.warn(
        `${exhausted.length} edge command(s) for venue ${venueId} exhausted their attempts`,
      );
    }

    if (retryable.length > 0) {
      await this.prisma.edgeCommand.updateMany({
        where: { id: { in: retryable }, status: EdgeCommandStatus.CLAIMED },
        data: {
          status: EdgeCommandStatus.PENDING,
          availableAt: now,
          claimedAt: null,
          claimedByDeviceId: null,
          claimExpiresAt: null,
        },
      });
    }
  }

  private resolveLimit(requested?: number): number {
    if (requested === undefined) return EDGE_COMMAND_DEFAULT_BATCH_SIZE;
    if (!Number.isInteger(requested) || requested < 1) {
      throw new BadRequestException('limit must be a positive integer');
    }
    return Math.min(requested, EDGE_COMMAND_MAX_BATCH_SIZE);
  }

  private async assertDeviceBelongsToVenue(
    venueId: string,
    deviceId: string,
  ): Promise<void> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { venueId: true },
    });
    if (!device || device.venueId !== venueId) {
      throw new BadRequestException(
        'Target device does not belong to this venue',
      );
    }
  }
}
