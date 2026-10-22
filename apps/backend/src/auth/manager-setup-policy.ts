import { ConflictException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomBytes } from 'node:crypto';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import { assertOperationalAuthority } from '../edge/operational-authority';
import type { ControlActor } from '../platform/control-actor';

const managerRoles = ['MANAGER', 'ADMIN'] as const;

/** Matches the existing initial-invitation issuer authority, including revocation. */
export async function requireManagerSetupIssuer(
  tx: Prisma.TransactionClient,
  venueId: string,
  actor: ControlActor,
) {
  const venue = await tx.venue.findUniqueOrThrow({ where: { id: venueId } });
  if (venue.status !== 'ACTIVE')
    throw new ForbiddenException('Restaurant unavailable');
  const allowed = actor.customerAccountId
    ? await tx.customerAccount.count({
        where: {
          id: actor.customerAccountId,
          isActive: true,
          memberships: {
            some: { role: 'OWNER', organizationId: venue.organizationId },
          },
        },
      })
    : actor.platformUserId
      ? await tx.platformUser.count({
          where: {
            id: actor.platformUserId,
            status: 'ACTIVE',
            role: 'SUPER_ADMIN',
          },
        })
      : 0;
  if (!allowed)
    throw new ForbiddenException('Initial Manager setup is unavailable');
  await requireCommercialFeature(tx, venueId, 'POS');
  await requireCommercialFeature(tx, venueId, 'MANAGER_APP');
}

/** Inactive/historical Managers still exclude a new bootstrap. Recovery stays Admin-owned. */
export async function requireNoManagerHistory(
  tx: Prisma.TransactionClient,
  venueId: string,
) {
  const [count, grant] = await Promise.all([
    tx.staff.count({ where: { venueId, role: { in: [...managerRoles] } } }),
    tx.managerActivation.findUnique({
      where: { venueId },
      select: { consumedAt: true },
    }),
  ]);
  if (count || grant?.consumedAt)
    throw new ConflictException(
      'Manager already exists; contact Vynic Platform Admin for recovery',
    );
}

/** Venue lock is held by the caller. A public grant ID never replaces Device authentication. */
export async function createEnrolledManagerGrant(
  tx: Prisma.TransactionClient,
  actor: ControlActor,
  enrollment: { id: string; venueId: string; expiresAt: Date },
) {
  await requireManagerSetupIssuer(tx, enrollment.venueId, actor);
  await requireNoManagerHistory(tx, enrollment.venueId);
  await tx.deviceEnrollment.updateMany({
    where: {
      venueId: enrollment.venueId,
      initialManagerSetup: true,
      id: { not: enrollment.id },
      redeemedAt: null,
      cancelledAt: null,
    },
    data: { cancelledAt: new Date() },
  });
  // This invitation is not redeemable by the legacy secret-code route. No new
  // secret is delivered or persisted on the client; its authority is the bound Device.
  const secretHash = createHash('sha256').update(randomBytes(32)).digest('hex');
  const data = {
    secretHash,
    expiresAt: enrollment.expiresAt,
    issuerId: actor.customerAccountId ?? actor.platformUserId,
    issuerType: actor.customerAccountId ? 'CUSTOMER' : 'PLATFORM',
    setupEnrollmentId: enrollment.id,
    setupDeviceId: null,
    consumedAt: null,
    requestId: null,
    staffId: null,
  };
  await tx.managerActivation.upsert({
    where: { venueId: enrollment.venueId },
    create: { venueId: enrollment.venueId, ...data },
    update: data,
  });
}

export async function bindEnrolledManagerGrant(
  tx: Prisma.TransactionClient,
  enrollment: {
    id: string;
    venueId: string;
    initialManagerSetup?: boolean;
    createdByPlatformUserId: string | null;
    createdByCustomerAccountId?: string | null;
  },
  deviceId: string,
  now: Date,
) {
  if (!enrollment.initialManagerSetup) return;
  const actor = enrollment.createdByCustomerAccountId
    ? { customerAccountId: enrollment.createdByCustomerAccountId }
    : { platformUserId: enrollment.createdByPlatformUserId ?? '' };
  await requireManagerSetupIssuer(tx, enrollment.venueId, actor);
  await assertOperationalAuthority(tx, {
    deviceId,
    venueId: enrollment.venueId,
  });
  const grant = await tx.managerActivation.findUnique({
    where: { venueId: enrollment.venueId },
  });
  if (
    !grant ||
    grant.setupEnrollmentId !== enrollment.id ||
    grant.expiresAt <= now ||
    (grant.setupDeviceId !== null && grant.setupDeviceId !== deviceId)
  )
    throw new ConflictException(
      'This initial setup is no longer available. Ask for a new setup code.',
    );
  if (!grant.consumedAt) await requireNoManagerHistory(tx, enrollment.venueId);
  await tx.managerActivation.update({
    where: { id: grant.id },
    data: { setupDeviceId: deviceId },
  });
}
