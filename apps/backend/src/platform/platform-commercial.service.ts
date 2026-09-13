import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  SubscriptionStatus,
  StaffRole,
  PlatformRole,
} from '@prisma/client';
import * as bcrypt from 'bcrypt';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import {
  EDGE_COMMAND_CONTRACT_VERSION,
  EdgeCommandTypes,
} from '../shared/contracts/edge-command';
import type { PlatformPrincipal } from './platform-auth-context';
import {
  requireEnumValue,
  requireText,
  requireUuid,
} from './platform-validation';

const staffFields = {
  id: true,
  venueId: true,
  username: true,
  displayName: true,
  role: true,
  isActive: true,
  platformManaged: true,
  updatedAt: true,
} as const;
const userFields = {
  id: true,
  email: true,
  displayName: true,
  role: true,
  status: true,
  createdAt: true,
} as const;
function audit(
  tx: Prisma.TransactionClient,
  actor: PlatformPrincipal,
  venueId: string,
  action: string,
  metadata: Prisma.InputJsonObject,
) {
  return tx.platformAuditEvent.create({
    data: {
      platformUserId: actor.platformUserId,
      action,
      targetType: 'Venue',
      targetId: venueId,
      metadata,
    },
  });
}
function date(value: unknown): Date | null {
  if (value == null || value === '') return null;
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(value) ||
    !Number.isFinite(Date.parse(value))
  )
    throw new BadRequestException('Invalid subscription date');
  return new Date(value);
}

@Injectable()
export class PlatformCommercialService {
  constructor(
    private readonly db: PrismaService,
    private readonly vault: StaffPinVault,
  ) {}

  async subscription(venueId: string) {
    await this.db.venue.findUniqueOrThrow({ where: { id: venueId } });
    return this.db.venueSubscription.findUnique({ where: { venueId } });
  }

  async setSubscription(
    actor: PlatformPrincipal,
    venueId: string,
    body: Record<string, unknown>,
  ) {
    const status = requireEnumValue(
      body.status,
      Object.values(SubscriptionStatus),
      'status',
    );
    const note = body.note
      ? requireText(body.note, 'note', { max: 1000 })
      : null;
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      if (
        !(await tx.venue.findUnique({
          where: { id: venueId },
          select: { id: true },
        }))
      )
        throw new NotFoundException('Venue not found');
      const before = await tx.venueSubscription.findUnique({
        where: { venueId },
      });
      const row = await tx.venueSubscription.upsert({
        where: { venueId },
        create: {
          venueId,
          status,
          note,
          updatedBy: actor.platformUserId,
          startedAt: new Date(),
          suspendedAt: status === 'SUSPENDED' ? new Date() : null,
          cancelledAt: status === 'CANCELLED' ? new Date() : null,
          trialEndsAt: date(body.trialEndsAt),
          currentPeriodEndsAt: date(body.currentPeriodEndsAt),
        },
        update: {
          status,
          note,
          updatedBy: actor.platformUserId,
          ...(body.trialEndsAt !== undefined
            ? { trialEndsAt: date(body.trialEndsAt) }
            : {}),
          ...(body.currentPeriodEndsAt !== undefined
            ? { currentPeriodEndsAt: date(body.currentPeriodEndsAt) }
            : {}),
          suspendedAt: status === 'SUSPENDED' ? new Date() : null,
          cancelledAt: status === 'CANCELLED' ? new Date() : null,
        },
      });
      await audit(tx, actor, venueId, 'venue.subscription_changed', {
        from: before?.status ?? null,
        to: status,
        note,
        trialEndsAt: row.trialEndsAt?.toISOString() ?? null,
        currentPeriodEndsAt: row.currentPeriodEndsAt?.toISOString() ?? null,
      });
      return row;
    });
  }

  async managers(venueId: string) {
    const staff = await this.db.staff.findMany({
      where: { venueId, role: { in: ['MANAGER', 'ADMIN'] } },
      select: staffFields,
      orderBy: { username: 'asc' },
    });
    return Promise.all(
      staff.map(async (member) => {
        const delivery = await this.db.edgeCommand.findFirst({
          where: {
            venueId,
            idempotencyKey: { startsWith: 'platform-staff:' },
            payload: { path: ['staffId'], equals: member.id },
          },
          orderBy: { createdAt: 'desc' },
          select: { id: true, status: true, resultCode: true },
        });
        return { ...member, delivery };
      }),
    );
  }

  async managerAccess(
    actor: PlatformPrincipal,
    venueId: string,
    action: 'create' | 'reset' | 'disable',
    body: Record<string, unknown>,
    staffId?: string,
  ) {
    const requestId = requireUuid(body.requestId, 'requestId');
    const pin = action === 'disable' ? undefined : requireText(body.pin, 'PIN');
    if (pin && !/^\d{4,6}$/.test(pin))
      throw new BadRequestException('PIN must contain 4–6 digits');
    const username =
      action === 'create'
        ? requireText(body.username, 'username', { max: 80 })
        : undefined;
    const displayName =
      action === 'create'
        ? requireText(body.displayName, 'displayName')
        : undefined;
    const role =
      action === 'create'
        ? requireEnumValue(
            body.role,
            [StaffRole.MANAGER, StaffRole.ADMIN],
            'role',
          )
        : undefined;
    // Serialize identity, vault and queue writes per Venue; no Cloud-to-LAN fallback.
    return this.db.$transaction(
      async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        if (
          !(await tx.venue.findUnique({
            where: { id: venueId },
            select: { id: true },
          }))
        )
          throw new NotFoundException('Venue not found');
        const idempotencyKey = `platform-staff:${requestId}`;
        const previous = await tx.edgeCommand.findUnique({
          where: { venueId_idempotencyKey: { venueId, idempotencyKey } },
        });
        if (previous) {
          const payload = previous.payload as Record<string, unknown>;
          if (
            payload.platformAction !== action ||
            (staffId && payload.staffId !== staffId) ||
            (username && payload.username !== username) ||
            (pin && payload.pinCode !== pin) ||
            (role && payload.role !== role.toLowerCase()) ||
            (displayName && payload.platformDisplayName !== displayName)
          )
            throw new ConflictException(
              'Retry key belongs to a different access change',
            );
          return {
            staff: await tx.staff.findFirstOrThrow({
              where: { id: String(payload.staffId), venueId },
              select: staffFields,
            }),
            delivery: { commandId: previous.id, status: previous.status },
          };
        }
        const before =
          action === 'create'
            ? null
            : await tx.staff.findFirst({
                where: {
                  id: staffId,
                  venueId,
                  role: { in: ['MANAGER', 'ADMIN'] },
                },
              });
        if (action !== 'create' && !before)
          throw new NotFoundException('Manager not found for this Venue');
        if (
          action === 'create' &&
          (await tx.staff.findUnique({
            where: { venueId_username: { venueId, username: username! } },
          }))
        )
          throw new ConflictException('Username already exists');
        if (pin) {
          const others = await tx.staff.findMany({
            where: {
              venueId,
              isActive: true,
              ...(staffId ? { id: { not: staffId } } : {}),
            },
            select: { pinHash: true },
          });
          for (const other of others)
            if (await bcrypt.compare(pin, other.pinHash))
              throw new ConflictException(
                'PIN is already in use in this Venue',
              );
        }
        const pinHash = pin ? await bcrypt.hash(pin, 12) : undefined;
        const revision = Math.max(
          Date.now(),
          (before?.updatedAt.getTime() ?? 0) + 1,
        );
        const staff =
          action === 'create'
            ? await tx.staff.create({
                data: {
                  venueId,
                  username: username!,
                  displayName,
                  role,
                  pinHash: pinHash!,
                  platformManaged: true,
                  updatedAt: new Date(revision),
                },
                select: staffFields,
              })
            : await tx.staff.update({
                where: { id: before!.id },
                data: {
                  platformManaged: true,
                  updatedAt: new Date(revision),
                  isActive: action !== 'disable',
                  ...(pinHash ? { pinHash } : {}),
                },
                select: staffFields,
              });
        if (pin) {
          const map = await this.vault.read({ venueId }, tx);
          map[staff.username] = pin;
          await this.vault.write(map, { venueId }, tx);
        }
        const command = await tx.edgeCommand.create({
          data: {
            venueId,
            idempotencyKey,
            contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
            type:
              action === 'disable'
                ? EdgeCommandTypes.STAFF_DELETE
                : EdgeCommandTypes.STAFF_CREATE,
            payload: {
              username: staff.username,
              ...(pin ? { pinCode: pin } : {}),
              role: staff.role.toLowerCase(),
              staffId: staff.id,
              platformAction: action,
              platformRevision: revision,
              ...(displayName ? { platformDisplayName: displayName } : {}),
            },
          },
        });
        await audit(tx, actor, venueId, `venue.manager_${action}`, {
          staffId: staff.id,
          username: staff.username,
          from: before ? { role: before.role, active: before.isActive } : null,
          to: { role: staff.role, active: staff.isActive },
          commandId: command.id,
        });
        return {
          staff,
          delivery: { commandId: command.id, status: command.status },
        };
      },
      { timeout: 15000 },
    );
  }

  users() {
    return this.db.platformUser.findMany({
      select: userFields,
      orderBy: { email: 'asc' },
    });
  }
  async createUser(actor: PlatformPrincipal, body: Record<string, unknown>) {
    const email = requireText(body.email, 'email').toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new BadRequestException('Invalid email');
    const displayName = requireText(body.displayName, 'displayName');
    const role = requireEnumValue(
      body.role,
      Object.values(PlatformRole),
      'role',
    );
    const passwordHash = await argon2.hash(
      requireText(body.password, 'password', { min: 12, max: 200 }),
    );
    return this.db.$transaction(async (tx) => {
      const user = await tx.platformUser.create({
        data: { email, displayName, role, passwordHash },
        select: userFields,
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'platform_user.created',
          targetType: 'PlatformUser',
          targetId: user.id,
          metadata: { email, role, status: user.status },
        },
      });
      return user;
    });
  }
  async disableUser(actor: PlatformPrincipal, id: string) {
    if (id === actor.platformUserId)
      throw new ConflictException('Cannot disable your own Platform account');
    return this.db.$transaction(async (tx) => {
      const before = await tx.platformUser.findUniqueOrThrow({
        where: { id },
        select: userFields,
      });
      const user = await tx.platformUser.update({
        where: { id },
        data: { status: 'DISABLED' },
        select: userFields,
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'platform_user.disabled',
          targetType: 'PlatformUser',
          targetId: id,
          metadata: { from: before.status, to: user.status },
        },
      });
      return user;
    });
  }
}
