import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DeviceStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import {
  DeviceEnrollmentService,
  type CreateEnrollmentInput,
} from '../edge/device-enrollment.service';
import { EdgeCommandService } from '../edge/edge-command.service';
import { EdgeCommandTypes } from '../shared/contracts/edge-command';
import type { PlatformPrincipal } from './platform-auth-context';
import {
  PlatformAuditAction,
  PlatformAuditService,
} from './platform-audit.service';
import { PlatformDirectoryService } from './platform-directory.service';

/**
 * What a read of a Device may show.
 *
 * `credentialHash` is absent by construction rather than deleted afterwards: it
 * is never selected, so no serialization mistake can leak it. `lastSeenAt` is
 * returned raw — deriving an ONLINE flag from it would require picking a
 * freshness window, and an unstated window is a claim the API cannot back up.
 */
const DEVICE_FIELDS = {
  id: true,
  venueId: true,
  installationId: true,
  displayName: true,
  platform: true,
  status: true,
  lastSeenAt: true,
  createdAt: true,
  updatedAt: true,
} as const;

export interface IssuedDeviceResponse {
  device: { id: string; venueId: string; installationId: string };
  /**
   * Shown exactly once. Only the Argon2id verifier is stored, so this cannot be
   * read back later — a lost credential is rotated, not recovered.
   */
  credential: string;
}

/**
 * Device enrollment and lifecycle, from the control plane.
 *
 * Step 6B needed a shell on the server to issue a credential because no trusted
 * write boundary existed. It does now, and the script stays as the way to
 * bootstrap before the first administrator exists. Since Phase 1C the normal
 * path is an enrollment code rather than a credential copied by hand.
 */
@Injectable()
export class PlatformDeviceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly credentials: DeviceCredentialService,
    private readonly edgeCommands: EdgeCommandService,
    private readonly enrollments: DeviceEnrollmentService,
    private readonly directory: PlatformDirectoryService,
    private readonly audit: PlatformAuditService,
  ) {}

  // ── Enrollment ────────────────────────────────────────────────────────────

  /**
   * Mints the one-time code an operator types into a new terminal.
   *
   * This is the onboarding path. `createDevice` below remains for the case it
   * was built for — an administrator provisioning a machine they are sitting at
   * — but it hands a long-lived secret to a human, which is what enrollment
   * exists to stop doing.
   */
  async createEnrollment(
    actor: PlatformPrincipal,
    venueId: string,
    input: CreateEnrollmentInput,
  ) {
    await this.directory.requireVenue(venueId);
    return this.enrollments.create(actor, venueId, input);
  }

  async listEnrollments(venueId: string) {
    await this.directory.requireVenue(venueId);
    return this.enrollments.list(venueId);
  }

  async cancelEnrollment(
    actor: PlatformPrincipal,
    venueId: string,
    enrollmentId: string,
  ) {
    await this.directory.requireVenue(venueId);
    return this.enrollments.cancel(actor, venueId, enrollmentId);
  }

  async listDevices(venueId: string) {
    await this.directory.requireVenue(venueId);
    return this.prisma.device.findMany({
      where: { venueId },
      select: DEVICE_FIELDS,
      orderBy: [{ displayName: 'asc' }, { id: 'asc' }],
    });
  }

  async getDevice(venueId: string, deviceId: string) {
    return this.requireDevice(venueId, deviceId);
  }

  /** Creates a Device and hands back its credential for the only time. */
  async createDevice(
    actor: PlatformPrincipal,
    venueId: string,
    input: { displayName: string; platform: string; installationId?: string },
  ): Promise<IssuedDeviceResponse> {
    await this.directory.requireVenue(venueId);

    const installationId = input.installationId ?? randomUUID();
    const issued = await this.credentials.issueCredential({
      venueId,
      installationId,
      displayName: input.displayName,
      platform: input.platform,
    });

    await this.audit.record(
      actor,
      PlatformAuditAction.DEVICE_CREATED,
      { type: 'Device', id: issued.deviceId },
      { venueId, displayName: input.displayName, platform: input.platform },
    );
    // Recorded separately from creation so a later rotation reads as the same
    // kind of event as the first issuance. Never the credential itself.
    await this.audit.record(
      actor,
      PlatformAuditAction.DEVICE_CREDENTIAL_ISSUED,
      { type: 'Device', id: issued.deviceId },
      { venueId, reason: 'initial' },
    );

    return {
      device: { id: issued.deviceId, venueId, installationId },
      credential: issued.credential,
    };
  }

  /**
   * Issues a replacement secret for an existing Device.
   *
   * The old one stops working the moment this returns. That is the point: a
   * credential believed to be exposed has to be dead immediately, not after a
   * grace period during which both work.
   */
  async rotateCredential(
    actor: PlatformPrincipal,
    venueId: string,
    deviceId: string,
  ): Promise<IssuedDeviceResponse> {
    const device = await this.requireDevice(venueId, deviceId);
    const issued = await this.credentials.rotateCredential(device.id);

    await this.audit.record(
      actor,
      PlatformAuditAction.DEVICE_CREDENTIAL_ISSUED,
      { type: 'Device', id: device.id },
      { venueId, reason: 'rotation' },
    );

    return {
      device: {
        id: device.id,
        venueId: device.venueId,
        installationId: device.installationId,
      },
      credential: issued.credential,
    };
  }

  /**
   * Disables or revokes a Device, or brings it back.
   *
   * Both DISABLED and REVOKED stop `verifyCredential` immediately, so either
   * ends that machine's access on its next request. The distinction is
   * intent — a terminal taken out of service versus a credential believed
   * compromised — and it is kept because an audit trail that cannot tell them
   * apart is worth less.
   */
  async setDeviceStatus(
    actor: PlatformPrincipal,
    venueId: string,
    deviceId: string,
    status: DeviceStatus,
  ) {
    const existing = await this.requireDevice(venueId, deviceId);
    if (existing.status === status) return existing;

    const device = await this.prisma.device.update({
      where: { id: deviceId },
      data: { status },
      select: DEVICE_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.DEVICE_STATUS_CHANGED,
      { type: 'Device', id: device.id },
      { venueId, from: existing.status, to: device.status },
    );
    return device;
  }

  /**
   * Queues the one command that does nothing, to prove a machine is reachable.
   *
   * There is deliberately no way to name a type or a payload here. Arbitrary
   * command creation would route straight around the declared registry and the
   * idempotency rule the queue depends on; this route *is* the NOOP, so there is
   * nothing to bypass.
   */
  async enqueueTestCommand(
    actor: PlatformPrincipal,
    venueId: string,
    deviceId?: string,
  ) {
    await this.directory.requireVenue(venueId);
    if (deviceId) await this.requireDevice(venueId, deviceId);

    const idempotencyKey = `platform-noop-${randomUUID()}`;
    const command = await this.edgeCommands.enqueue(
      { venueId },
      {
        deviceId: deviceId ?? null,
        type: EdgeCommandTypes.NOOP,
        payload: { requestedBy: actor.platformUserId },
        idempotencyKey,
      },
    );

    await this.audit.record(
      actor,
      PlatformAuditAction.EDGE_TEST_COMMAND_ENQUEUED,
      { type: 'Venue', id: venueId },
      { deviceId: deviceId ?? null, commandId: command.id },
    );
    return { commandId: command.id, status: command.status, idempotencyKey };
  }

  async readTestCommand(venueId: string, commandId: string) {
    await this.directory.requireVenue(venueId);
    const command = await this.prisma.edgeCommand.findFirst({
      where: { id: commandId, venueId, type: EdgeCommandTypes.NOOP },
      select: {
        id: true,
        type: true,
        status: true,
        attemptCount: true,
        maxAttempts: true,
        claimedAt: true,
        acknowledgedAt: true,
        resultCode: true,
        resultDetail: true,
        createdAt: true,
        updatedAt: true,
        claimedBy: { select: { id: true, displayName: true } },
        device: { select: { id: true, displayName: true } },
      },
    });
    if (!command) throw new NotFoundException('Test command not found');
    // Named `commandId` to match what enqueueTestCommand returned, so the
    // caller polls with the field it was handed back.
    const { id, ...rest } = command;
    return { commandId: id, ...rest };
  }

  private async requireDevice(venueId: string, deviceId: string) {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: DEVICE_FIELDS,
    });
    if (!device || device.venueId !== venueId) {
      throw new NotFoundException('Device not found for this venue');
    }
    return device;
  }
}
