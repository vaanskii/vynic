import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { HttpException, HttpStatus } from '@nestjs/common';
import { DeviceStatus, VenueStatus } from '@prisma/client';
import * as argon2 from 'argon2';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { PrismaService } from '../prisma.service';
import {
  PlatformAuditAction,
  PlatformAuditService,
} from '../platform/platform-audit.service';
import { EDGE_COMMAND_CONTRACT_VERSION } from '../shared/contracts/edge-command';
import {
  formatEnrollmentCode,
  generateEnrollmentCode,
  parseEnrollmentCode,
} from './enrollment-code';
import { EnrollmentRateLimiter } from './enrollment-rate-limiter';

/** Long enough to walk to the terminal, short enough not to sit in a chat log. */
export const ENROLLMENT_TTL_MINUTES = 30;
const MAX_SELECTOR_COLLISION_RETRIES = 5;

/** Durable, per-code. Survives a restart, unlike the rate limiter. */
export const ENROLLMENT_MAX_ATTEMPTS = 5;

const IP_LIMIT = 12;
const SELECTOR_LIMIT = 8;
const RATE_WINDOW_MS = 5 * 60 * 1000;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * What an enrollment is, without storing a second copy of the truth.
 *
 * Derived from timestamps in one place so a row can never say `PENDING` while
 * its `redeemedAt` is set. Deliberately no `ONLINE`: this says what happened to
 * an invitation, not whether a terminal is reachable right now.
 */
export type EnrollmentStatus = 'PENDING' | 'ENROLLED' | 'EXPIRED' | 'CANCELLED';

interface EnrollmentTimestamps {
  cancelledAt: Date | null;
  redeemedAt: Date | null;
  expiresAt: Date;
}

export function enrollmentStatus(
  row: EnrollmentTimestamps,
  now = new Date(),
): EnrollmentStatus {
  if (row.cancelledAt) return 'CANCELLED';
  if (row.redeemedAt) return 'ENROLLED';
  if (row.expiresAt.getTime() <= now.getTime()) return 'EXPIRED';
  return 'PENDING';
}

export interface CreateEnrollmentInput {
  displayName: string;
  platform: string;
  ttlMinutes?: number;
}

export interface CreatedEnrollment {
  id: string;
  venueId: string;
  displayName: string;
  platform: string;
  expiresAt: Date;
  status: EnrollmentStatus;
  /**
   * Shown exactly once. Only the Argon2id verifier of its secret half is
   * stored, so this cannot be read back — cancel it and create another.
   */
  code: string;
}

export interface RedeemEnrollmentInput {
  code: string;
  installationId: string;
  platform: string;
  displayName?: string;
  /** For rate limiting only. Never persisted. */
  clientIp?: string;
}

export interface RedeemedEnrollment {
  enrollmentId: string;
  device: {
    id: string;
    installationId: string;
    displayName: string;
    platform: string;
    status: DeviceStatus;
  };
  venue: { id: string; name: string; timezone: string; currency: string };
  /** Issued once, exactly like every other Device credential. */
  credential: string;
  /**
   * Where this fleet should talk to Cloud, when the deployment declares one.
   * Null means "keep the address you reached us on", which is the right answer
   * in local development where the server's own idea of its URL is loopback.
   */
  apiBaseUrl: string | null;
  edgeContractVersion: number;
  /** True when a reinstall rotated an existing Device instead of adding one. */
  reusedExistingDevice: boolean;
  enrolledAt: Date;
}

/** 429 with the shape the rest of the API uses. */
class TooManyRequestsException extends HttpException {
  constructor(message: string) {
    super(message, HttpStatus.TOO_MANY_REQUESTS);
  }
}

/**
 * POS self-enrollment.
 *
 * The problem it replaces: a credential could only reach a terminal by an
 * administrator copying a secret out of a browser and writing it into a file on
 * the machine, with the backend address configured separately through a
 * different screen. Two manual steps, one long-lived secret handled by a human,
 * and no confirmation at either end.
 *
 * Here the human handles one short-lived, single-use, Venue-bound code, and the
 * long-lived credential is minted by the server and never passes through a
 * person. **The POS never supplies a venueId.** Tenant authority comes from the
 * enrollment an authenticated administrator created; a request field could not
 * be allowed to choose a Venue, which is exactly why this is not a general
 * device-creation endpoint.
 *
 * Fails closed everywhere: an unparseable code, an unknown selector, a wrong
 * secret, a spent code, an expired code, a cancelled code, a disabled Venue and
 * an installation already bound to another Venue all refuse, and none of them
 * creates anything.
 */
@Injectable()
export class DeviceEnrollmentService {
  private readonly logger = new Logger(DeviceEnrollmentService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly credentials: DeviceCredentialService,
    private readonly audit: PlatformAuditService,
    private readonly rateLimiter: EnrollmentRateLimiter,
  ) {}

  // ── Control plane ─────────────────────────────────────────────────────────

  /** Mints an invitation for one Venue, and hands back its code once. */
  async create(
    actor: { platformUserId: string },
    venueId: string,
    input: CreateEnrollmentInput,
  ): Promise<CreatedEnrollment> {
    const ttl = Math.min(
      Math.max(input.ttlMinutes ?? ENROLLMENT_TTL_MINUTES, 5),
      24 * 60,
    );
    const expiresAt = new Date(Date.now() + ttl * 60 * 1000);

    // A four-character selector collides occasionally by design; the secret
    // half is where the entropy is. Retry rather than widen what a human types.
    for (let attempt = 0; attempt < MAX_SELECTOR_COLLISION_RETRIES; attempt++) {
      const code = generateEnrollmentCode();
      const codeHash = await argon2.hash(code.secret, {
        type: argon2.argon2id,
      });
      try {
        const row = await this.prisma.deviceEnrollment.create({
          data: {
            venueId,
            codeSelector: code.selector,
            codeHash,
            displayName: input.displayName,
            platform: input.platform,
            expiresAt,
            createdByPlatformUserId: actor.platformUserId,
          },
          select: {
            id: true,
            venueId: true,
            displayName: true,
            platform: true,
            expiresAt: true,
            redeemedAt: true,
            cancelledAt: true,
          },
        });

        await this.audit.record(
          actor,
          PlatformAuditAction.DEVICE_ENROLLMENT_CREATED,
          { type: 'Venue', id: venueId },
          {
            enrollmentId: row.id,
            displayName: input.displayName,
            platform: input.platform,
            expiresAt: expiresAt.toISOString(),
            // The selector alone cannot enroll anything. The secret half is
            // never written here, or anywhere but the verifier.
            codeSelector: code.selector,
          },
        );

        return {
          id: row.id,
          venueId: row.venueId,
          displayName: row.displayName,
          platform: row.platform,
          expiresAt: row.expiresAt,
          status: enrollmentStatus(row),
          code: formatEnrollmentCode(code.normalized),
        };
      } catch (error) {
        if (!isUniqueViolation(error, 'codeSelector')) throw error;
      }
    }
    throw new ConflictException(
      'Could not allocate an enrollment code. Try again.',
    );
  }

  /** Every invitation for a Venue, newest first, with its derived status. */
  async list(venueId: string) {
    const rows = await this.prisma.deviceEnrollment.findMany({
      where: { venueId },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: ENROLLMENT_FIELDS,
    });
    const now = new Date();
    return rows.map((row) => ({ ...row, status: enrollmentStatus(row, now) }));
  }

  /**
   * Ends an invitation early.
   *
   * The reason this exists rather than waiting for the TTL: a code read out
   * over the wrong channel has to be killable now, not in twenty minutes. A
   * spent one is left alone — cancelling it would rewrite what happened.
   */
  async cancel(
    actor: { platformUserId: string },
    venueId: string,
    enrollmentId: string,
  ) {
    const existing = await this.requireEnrollment(venueId, enrollmentId);
    if (existing.redeemedAt) {
      throw new ConflictException(
        'This enrollment was already redeemed. Revoke the device instead.',
      );
    }
    if (existing.cancelledAt) return { ...existing, status: 'CANCELLED' };

    const row = await this.prisma.deviceEnrollment.update({
      where: { id: enrollmentId },
      data: { cancelledAt: new Date() },
      select: ENROLLMENT_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.DEVICE_ENROLLMENT_CANCELLED,
      { type: 'Venue', id: venueId },
      { enrollmentId },
    );
    return { ...row, status: enrollmentStatus(row) };
  }

  // ── Redemption ────────────────────────────────────────────────────────────

  /**
   * Turns a typed code into this terminal's Cloud identity.
   *
   * The only unauthenticated write in the system, so the order of checks is the
   * security boundary: rate limit, shape, selector, secret, then — and only
   * then, once the caller has proved it holds the real code — the specific
   * reasons a valid code will not work. An attacker with a guessed selector
   * learns nothing beyond "no".
   */
  async redeem(input: RedeemEnrollmentInput): Promise<RedeemedEnrollment> {
    const ip = input.clientIp?.trim() || 'unknown';
    if (!this.rateLimiter.consume(`ip:${ip}`, IP_LIMIT, RATE_WINDOW_MS)) {
      throw new TooManyRequestsException(
        'Too many enrollment attempts. Wait a few minutes and try again.',
      );
    }
    if (!UUID_PATTERN.test(input.installationId)) {
      throw new BadRequestException('installationId must be a UUID');
    }
    const platform = input.platform.trim();
    if (!platform || platform.length > 32) {
      throw new BadRequestException('platform is required');
    }

    const parsed = parseEnrollmentCode(input.code);
    if (!parsed) {
      throw new BadRequestException(
        'That is not an enrollment code. It is 12 characters, like 7K2Q-M4XB-9TFR.',
      );
    }
    if (
      !this.rateLimiter.consume(
        `code:${parsed.selector}`,
        SELECTOR_LIMIT,
        RATE_WINDOW_MS,
      )
    ) {
      throw new TooManyRequestsException(
        'Too many attempts against this code. Ask for a new one.',
      );
    }

    const enrollment = await this.prisma.deviceEnrollment.findUnique({
      where: { codeSelector: parsed.selector },
      select: {
        id: true,
        venueId: true,
        codeHash: true,
        displayName: true,
        platform: true,
        expiresAt: true,
        attemptCount: true,
        redeemedAt: true,
        redeemedInstallationId: true,
        deviceId: true,
        cancelledAt: true,
        createdByPlatformUserId: true,
      },
    });

    // An unknown selector has no row, so no administrator to attribute a
    // platform audit event to and no target to hang it on. It is counted by the
    // rate limiter and logged; inventing an actor would be worse than the gap.
    if (!enrollment) {
      this.logger.warn(`Enrollment attempt with an unknown code selector`);
      throw new UnauthorizedException(INVALID_CODE_MESSAGE);
    }

    if (enrollment.attemptCount >= ENROLLMENT_MAX_ATTEMPTS) {
      await this.recordFailure(enrollment, 'attempts_exhausted');
      throw new UnauthorizedException(INVALID_CODE_MESSAGE);
    }

    const secretMatches = await argon2
      .verify(enrollment.codeHash, parsed.secret)
      .catch(() => false);
    if (!secretMatches) {
      await this.prisma.deviceEnrollment.update({
        where: { id: enrollment.id },
        data: { attemptCount: { increment: 1 }, lastAttemptAt: new Date() },
      });
      await this.recordFailure(enrollment, 'secret_mismatch');
      throw new UnauthorizedException(INVALID_CODE_MESSAGE);
    }

    // Past this line the caller holds the real code, so a specific reason is
    // information it is entitled to and an operator badly needs.
    const now = new Date();
    if (enrollment.cancelledAt) {
      await this.recordFailure(enrollment, 'cancelled');
      throw new UnauthorizedException(
        'This enrollment code was cancelled. Ask for a new one.',
      );
    }
    if (enrollment.expiresAt.getTime() <= now.getTime()) {
      await this.recordFailure(enrollment, 'expired');
      throw new UnauthorizedException(
        'This enrollment code has expired. Ask for a new one.',
      );
    }

    const venue = await this.prisma.venue.findUnique({
      where: { id: enrollment.venueId },
      select: {
        id: true,
        name: true,
        status: true,
        timezone: true,
        currency: true,
      },
    });
    if (!venue || venue.status !== VenueStatus.ACTIVE) {
      await this.recordFailure(enrollment, 'venue_not_active');
      throw new UnauthorizedException(
        'This venue is not active. Contact Vynic support.',
      );
    }

    if (enrollment.redeemedAt) {
      return this.retryRedemption(enrollment, venue, input, now);
    }

    return this.firstRedemption(enrollment, venue, input, platform, now);
  }

  // ── Redemption paths ──────────────────────────────────────────────────────

  /**
   * The recovery path for a POS that received a credential and could not keep
   * it.
   *
   * Without this, a failed write to disk after issuance strands the terminal:
   * the code is spent and the secret is unrecoverable by design. Repeating the
   * redemption from the *same installation* rotates the credential and hands
   * back a fresh one, which is safe because the caller still has to prove it
   * holds the code, the Venue binding cannot change, and each rotation kills the
   * previous secret.
   */
  private async retryRedemption(
    enrollment: LoadedEnrollment,
    venue: LoadedVenue,
    input: RedeemEnrollmentInput,
    now: Date,
  ): Promise<RedeemedEnrollment> {
    if (enrollment.redeemedInstallationId !== input.installationId) {
      await this.recordFailure(enrollment, 'already_redeemed');
      throw new ConflictException(
        'This enrollment code has already been used by another terminal. Ask for a new one.',
      );
    }
    if (!enrollment.deviceId) {
      await this.recordFailure(enrollment, 'redeemed_without_device');
      throw new ConflictException(
        'This enrollment is in an inconsistent state. Ask for a new one.',
      );
    }

    const { secret, credentialHash } =
      await this.credentials.mintCredentialMaterial();
    const device = await this.prisma.device.update({
      where: { id: enrollment.deviceId },
      data: { credentialHash, status: DeviceStatus.ACTIVE },
      select: DEVICE_SELECT,
    });

    await this.audit.record(
      { platformUserId: enrollment.createdByPlatformUserId },
      PlatformAuditAction.DEVICE_ENROLLMENT_REDEEMED,
      { type: 'Device', id: device.id },
      {
        venueId: venue.id,
        enrollmentId: enrollment.id,
        redeemedBy: 'device',
        reason: 'retry_same_installation',
      },
    );

    return this.present(enrollment, venue, device, secret, true, now);
  }

  private async firstRedemption(
    enrollment: LoadedEnrollment,
    venue: LoadedVenue,
    input: RedeemEnrollmentInput,
    platform: string,
    now: Date,
  ): Promise<RedeemedEnrollment> {
    const existing = await this.prisma.device.findUnique({
      where: { installationId: input.installationId },
      select: { id: true, venueId: true, status: true },
    });

    // A terminal never changes Venue by typing a code. Moving one is a
    // deliberate platform action against the Device, not a side effect here.
    if (existing && existing.venueId !== enrollment.venueId) {
      await this.recordFailure(enrollment, 'installation_bound_to_other_venue');
      throw new ConflictException(
        'This terminal is already enrolled with a different venue. It must be released by Vynic before it can be moved.',
      );
    }

    const displayName = enrollment.displayName;
    const { secret, credentialHash } =
      await this.credentials.mintCredentialMaterial();

    const device = await this.prisma.$transaction(async (tx) => {
      // The single-use guarantee. Two terminals racing the same code: exactly
      // one update matches, and the loser creates nothing.
      const claimed = await tx.deviceEnrollment.updateMany({
        where: {
          id: enrollment.id,
          redeemedAt: null,
          cancelledAt: null,
          expiresAt: { gt: now },
        },
        data: {
          redeemedAt: now,
          redeemedInstallationId: input.installationId,
          lastAttemptAt: now,
        },
      });
      if (claimed.count !== 1) return null;

      const written = existing
        ? await tx.device.update({
            where: { id: existing.id },
            data: {
              credentialHash,
              displayName,
              platform,
              // The administrator who minted this code authorized the terminal
              // to come back. A previously disabled or revoked machine is
              // reinstated here with a brand-new secret; the old one is dead.
              status: DeviceStatus.ACTIVE,
            },
            select: DEVICE_SELECT,
          })
        : await tx.device.create({
            data: {
              venueId: enrollment.venueId,
              installationId: input.installationId,
              displayName,
              platform,
              credentialHash,
            },
            select: DEVICE_SELECT,
          });

      await tx.deviceEnrollment.update({
        where: { id: enrollment.id },
        data: { deviceId: written.id },
      });
      return written;
    });

    if (!device) {
      await this.recordFailure(enrollment, 'already_redeemed');
      throw new ConflictException(
        'This enrollment code has already been used. Ask for a new one.',
      );
    }

    await this.audit.record(
      { platformUserId: enrollment.createdByPlatformUserId },
      PlatformAuditAction.DEVICE_ENROLLMENT_REDEEMED,
      { type: 'Device', id: device.id },
      {
        venueId: venue.id,
        enrollmentId: enrollment.id,
        redeemedBy: 'device',
        installationId: input.installationId,
        reason: existing ? 're_enrolled_existing_device' : 'new_device',
        previousStatus: existing?.status ?? null,
      },
    );

    return this.present(
      enrollment,
      venue,
      device,
      secret,
      Boolean(existing),
      now,
    );
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  private present(
    enrollment: LoadedEnrollment,
    venue: LoadedVenue,
    device: {
      id: string;
      installationId: string;
      displayName: string;
      platform: string;
      status: DeviceStatus;
    },
    secret: string,
    reused: boolean,
    now: Date,
  ): RedeemedEnrollment {
    return {
      enrollmentId: enrollment.id,
      device: {
        id: device.id,
        installationId: device.installationId,
        displayName: device.displayName,
        platform: device.platform,
        status: device.status,
      },
      venue: {
        id: venue.id,
        name: venue.name,
        timezone: venue.timezone,
        currency: venue.currency,
      },
      credential: this.credentials.formatCredential(device.id, secret),
      apiBaseUrl: canonicalApiBaseUrl(),
      edgeContractVersion: EDGE_COMMAND_CONTRACT_VERSION,
      reusedExistingDevice: reused,
      enrolledAt: now,
    };
  }

  private async recordFailure(enrollment: LoadedEnrollment, reason: string) {
    await this.audit.record(
      { platformUserId: enrollment.createdByPlatformUserId },
      PlatformAuditAction.DEVICE_ENROLLMENT_FAILED,
      { type: 'Venue', id: enrollment.venueId },
      { enrollmentId: enrollment.id, reason, attemptedBy: 'device' },
    );
  }

  private async requireEnrollment(venueId: string, enrollmentId: string) {
    const row = await this.prisma.deviceEnrollment.findUnique({
      where: { id: enrollmentId },
      select: ENROLLMENT_FIELDS,
    });
    if (!row || row.venueId !== venueId) {
      throw new NotFoundException('Enrollment not found for this venue');
    }
    return row;
  }
}

const INVALID_CODE_MESSAGE =
  'That enrollment code is not valid. Check it and try again.';

/**
 * What a read of an enrollment may show.
 *
 * `codeHash` is absent by construction rather than deleted afterwards, exactly
 * like `Device.credentialHash`. `codeSelector` is safe — it is half a code and
 * cannot enroll anything — and it is what lets an administrator tell two live
 * invitations apart on screen.
 */
const ENROLLMENT_FIELDS = {
  id: true,
  venueId: true,
  codeSelector: true,
  displayName: true,
  platform: true,
  expiresAt: true,
  attemptCount: true,
  redeemedAt: true,
  redeemedInstallationId: true,
  deviceId: true,
  cancelledAt: true,
  createdAt: true,
  updatedAt: true,
} as const;

const DEVICE_SELECT = {
  id: true,
  installationId: true,
  displayName: true,
  platform: true,
  status: true,
} as const;

interface LoadedEnrollment {
  id: string;
  venueId: string;
  displayName: string;
  expiresAt: Date;
  redeemedAt: Date | null;
  redeemedInstallationId: string | null;
  deviceId: string | null;
  cancelledAt: Date | null;
  createdByPlatformUserId: string;
}

interface LoadedVenue {
  id: string;
  name: string;
  timezone: string;
  currency: string;
}

/**
 * The address this fleet should use, when the deployment states one.
 *
 * Deliberately its own variable rather than `API_URL`, which exists so payment
 * callbacks can find their way back and is loopback in local development.
 * Handing a terminal on another machine `http://127.0.0.1:3000` would break the
 * connection that just worked, so the safe default is to say nothing and let the
 * POS keep the address it enrolled through.
 */
export function canonicalApiBaseUrl(): string | null {
  const raw = process.env.DEVICE_API_BASE_URL?.trim();
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    return url.origin;
  } catch {
    return null;
  }
}

function isUniqueViolation(error: unknown, field: string): boolean {
  const candidate = error as {
    code?: string;
    meta?: { target?: string[] | string };
  };
  if (candidate?.code !== 'P2002') return false;
  const target = candidate.meta?.target;
  if (Array.isArray(target)) return target.includes(field);
  return typeof target === 'string' ? target.includes(field) : true;
}
