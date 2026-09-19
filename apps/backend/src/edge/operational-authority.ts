import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { PosAuthContext } from '../auth/pos-auth-context';
import type { ControlActor } from '../platform/control-actor';

/** Same Venue row lock for ingestion, claims, enrollment and operator replacement. */
export async function lockOperationalVenue(
  tx: Prisma.TransactionClient,
  venueId: string,
) {
  await tx.$queryRaw`SELECT id FROM pos."Venue" WHERE id=${venueId} FOR UPDATE`;
  const venue = await tx.venue.findUnique({ where: { id: venueId } });
  if (!venue) throw new NotFoundException('Venue not found');
  return venue;
}

/** Only the first-ever Device is selected automatically, never the first poller. */
export async function selectFirstOperationalDevice(
  tx: Prisma.TransactionClient,
  venueId: string,
  deviceId: string,
) {
  if ((await tx.device.count({ where: { venueId } })) === 1) {
    await tx.venue.updateMany({
      where: { id: venueId, activeOperationalDeviceId: null },
      data: { activeOperationalDeviceId: deviceId },
    });
  }
}

export async function assertOperationalAuthority(
  tx: Prisma.TransactionClient,
  auth: Pick<PosAuthContext, 'venueId' | 'deviceId'>,
) {
  const venue = await lockOperationalVenue(tx, auth.venueId);
  if (auth.deviceId) {
    const active = await tx.device.count({
      where: { id: auth.deviceId, venueId: auth.venueId, status: 'ACTIVE' },
    });
    if (active && venue.activeOperationalDeviceId === auth.deviceId) return;
  } else if (
    !venue.activeOperationalDeviceId &&
    (await tx.device.count({ where: { venueId: auth.venueId } })) === 0
  ) {
    // Frozen legacy compatibility only before this Venue has any Device identity.
    return;
  }
  throw new ForbiddenException({
    code: 'PRIMARY_POS_REQUIRED',
    message:
      'Only the selected Primary POS may publish restaurant operations. Ask an operator to select the primary.',
  });
}

/** Bind existing ingestion services to ONE transaction; nested callbacks join it. */
export function operationalDatabase(
  tx: Prisma.TransactionClient,
): PrismaService {
  return new Proxy(tx, {
    get(target, property) {
      if (property === '$transaction')
        return (work: unknown) => {
          if (typeof work !== 'function')
            throw new TypeError('Operational transactions require a callback');
          return work(tx);
        };
      const value = Reflect.get(target, property);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  }) as PrismaService;
}

export async function withOperationalAuthority<T>(
  db: PrismaService,
  auth: Pick<PosAuthContext, 'venueId' | 'deviceId'>,
  work: (tx: PrismaService) => Promise<T>,
) {
  return db.$transaction(
    async (tx) => {
      await assertOperationalAuthority(tx, auth);
      return work(operationalDatabase(tx));
    },
    { maxWait: 10000, timeout: 120000 },
  );
}

export async function replaceOperationalDevice(
  db: PrismaService,
  actor: ControlActor,
  venueId: string,
  deviceId: string,
  expectedDeviceId: string | null,
  reason: string,
) {
  return db.$transaction(async (tx) => {
    const venue = await lockOperationalVenue(tx, venueId);
    if (venue.activeOperationalDeviceId !== expectedDeviceId)
      throw new ConflictException(
        'Primary POS changed. Refresh before selecting again.',
      );
    const device = await tx.device.findFirst({
      where: { id: deviceId, venueId, status: 'ACTIVE' },
    });
    if (!device)
      throw new NotFoundException('Active Device not found for this Venue');
    if (deviceId === expectedDeviceId)
      return { activeOperationalDeviceId: deviceId };
    // A claimed command may already have executed in the old Hive database.
    // Never redeliver that uncertain outcome to a different installation.
    const held = await tx.edgeCommand.updateMany({
      where: {
        venueId,
        status: { in: ['CLAIMED', 'PENDING'] },
        attemptCount: { gt: 0 },
        OR: [{ deviceId: null }, { type: { not: 'NOOP' } }],
      },
      data: {
        status: 'FAILED',
        resultCode: 'primary_replaced_outcome_unknown',
        resultDetail:
          'Reconcile the previous POS journal before issuing new work.',
        acknowledgedAt: new Date(),
        claimExpiresAt: null,
      },
    });
    await tx.venue.update({
      where: { id: venueId },
      data: { activeOperationalDeviceId: deviceId },
    });
    const audit = {
      action: 'venue.operational_primary_changed',
      targetType: 'Venue',
      targetId: venueId,
      metadata: {
        venueId,
        from: expectedDeviceId,
        to: deviceId,
        reason,
        uncertainCommands: held.count,
      },
    };
    if (actor.customerAccountId)
      await tx.customerAuditEvent.create({
        data: { ...audit, customerAccountId: actor.customerAccountId },
      });
    else
      await tx.platformAuditEvent.create({
        data: { ...audit, platformUserId: actor.platformUserId! },
      });
    return { activeOperationalDeviceId: deviceId };
  });
}
