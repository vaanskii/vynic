import { randomBytes, randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { DeviceStatus, VenueStatus } from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { PosAuthContext } from './pos-auth-context';

const DEVICE_CREDENTIAL_PREFIX = 'vynic-device-v1';
const LAST_SEEN_WRITE_INTERVAL_MS = 5 * 60 * 1000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SECRET_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export interface IssueDeviceCredentialInput {
  venueId: string;
  installationId: string;
  displayName: string;
  platform: string;
}

export interface IssuedDeviceCredential {
  deviceId: string;
  credential: string;
}

/**
 * Issues and verifies versioned Device credentials.
 *
 * The raw secret is returned once and never persisted or logged — only its
 * Argon2id verifier reaches the database, so a lost credential is replaced
 * rather than recovered. Since Step 7A the callers are the platform control
 * plane and the operator provisioning script; there is still no unauthenticated
 * route that issues one.
 */
@Injectable()
export class DeviceCredentialService {
  constructor(private readonly prisma: PrismaService) {}

  isDeviceCredential(value: string | undefined): boolean {
    return value?.startsWith(`${DEVICE_CREDENTIAL_PREFIX}.`) === true;
  }

  async issueCredential(
    input: IssueDeviceCredentialInput,
  ): Promise<IssuedDeviceCredential> {
    if (!UUID_PATTERN.test(input.venueId)) {
      throw new TypeError('venueId must be a UUID');
    }
    if (!UUID_PATTERN.test(input.installationId)) {
      throw new TypeError('installationId must be a UUID');
    }
    const deviceId = randomUUID();
    const secret = randomBytes(32).toString('base64url');
    const credentialHash = await argon2.hash(secret, { type: argon2.argon2id });

    await this.prisma.device.create({
      data: {
        id: deviceId,
        venueId: input.venueId,
        installationId: input.installationId,
        displayName: input.displayName,
        platform: input.platform,
        credentialHash,
      },
    });

    return {
      deviceId,
      credential: `${DEVICE_CREDENTIAL_PREFIX}.${deviceId}.${secret}`,
    };
  }

  /**
   * Replaces an existing Device's secret, keeping its identity.
   *
   * Rotation rather than recovery: the old verifier is overwritten in the same
   * write that returns the new secret, so the previous credential stops working
   * immediately and there is never a window where two are valid. The Device id,
   * its installation id and its Venue are untouched, so nothing that references
   * the Device has to change.
   */
  async rotateCredential(deviceId: string): Promise<IssuedDeviceCredential> {
    if (!UUID_PATTERN.test(deviceId)) {
      throw new TypeError('deviceId must be a UUID');
    }
    const secret = randomBytes(32).toString('base64url');
    const credentialHash = await argon2.hash(secret, { type: argon2.argon2id });

    await this.prisma.device.update({
      where: { id: deviceId },
      data: { credentialHash },
    });

    return {
      deviceId,
      credential: `${DEVICE_CREDENTIAL_PREFIX}.${deviceId}.${secret}`,
    };
  }

  async verifyCredential(
    rawCredential: string,
  ): Promise<PosAuthContext | null> {
    const parsed = this.parseCredential(rawCredential);
    if (!parsed) return null;

    const device = await this.prisma.device.findUnique({
      where: { id: parsed.deviceId },
      select: {
        id: true,
        credentialHash: true,
        status: true,
        lastSeenAt: true,
        venue: {
          select: { id: true, organizationId: true, status: true },
        },
      },
    });
    if (
      !device ||
      device.status !== DeviceStatus.ACTIVE ||
      device.venue.status !== VenueStatus.ACTIVE
    ) {
      return null;
    }

    const valid = await argon2.verify(device.credentialHash, parsed.secret);
    if (!valid) return null;

    const now = new Date();
    if (
      device.lastSeenAt === null ||
      now.getTime() - device.lastSeenAt.getTime() >= LAST_SEEN_WRITE_INTERVAL_MS
    ) {
      await this.prisma.device.update({
        where: { id: device.id },
        data: { lastSeenAt: now },
      });
    }

    return {
      authenticationMode: 'device',
      deviceId: device.id,
      venueId: device.venue.id,
      organizationId: device.venue.organizationId,
    };
  }

  private parseCredential(
    rawCredential: string,
  ): { deviceId: string; secret: string } | null {
    const parts = rawCredential.split('.');
    if (
      parts.length !== 3 ||
      parts[0] !== DEVICE_CREDENTIAL_PREFIX ||
      !UUID_PATTERN.test(parts[1]) ||
      !SECRET_PATTERN.test(parts[2])
    ) {
      return null;
    }
    return { deviceId: parts[1], secret: parts[2] };
  }
}
