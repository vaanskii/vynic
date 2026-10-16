import { provisionWebsite } from '../website/provisioning/website-provisioning';
import { SubscriptionService } from '../subscriptions/subscription.service';
import { nextRenewal } from '../subscriptions/billing-policy';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import { CommercialLifecycleService } from '../entitlements/commercial-lifecycle.service';
import { assignCommercialPlan } from './plan-assignment';
import type { ControlActor } from './control-actor';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
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
import { assertStaffPinAvailable } from '../staff/staff-pin-policy';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { ManagerActivationService } from '../auth/manager-activation.service';
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
  actor: ControlActor,
  venueId: string,
  action: string,
  metadata: Prisma.InputJsonObject,
) {
  if (actor.customerAccountId)
    return tx.customerAuditEvent.create({
      data: {
        customerAccountId: actor.customerAccountId,
        action,
        targetType: 'Venue',
        targetId: venueId,
        metadata,
      },
    });
  return tx.platformAuditEvent.create({
    data: {
      platformUserId: actor.platformUserId!,
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
    await new CommercialLifecycleService(this.db).reconcile(venueId);
    return new SubscriptionService(this.db).snapshot(venueId);
  }

  async setSubscription(
    actor: PlatformPrincipal,
    venueId: string,
    body: Record<string, unknown>,
    existingTx?: Prisma.TransactionClient,
  ) {
    const status = requireEnumValue(
      body.status,
      Object.values(SubscriptionStatus),
      'status',
    );
    const note = body.note
      ? requireText(body.note, 'note', { max: 1000 })
      : null;
    const run = async (tx: Prisma.TransactionClient) => {
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
      if (before?.billingManaged)
        throw new ConflictException(
          'Use lifecycle actions for a billing agreement',
        );
      if (['SUSPENDED', 'CANCELLED'].includes(status)) {
        requireText(body.note, 'Operator reason', { max: 1000 });
        if (body.confirm !== true)
          throw new BadRequestException('Confirm immediate access change');
      }
      if (body.planId)
        await assignCommercialPlan(
          tx,
          venueId,
          requireText(body.planId, 'Plan'),
        );
      const assignment = await tx.venuePlanAssignment.findUnique({
        where: { venueId },
      });
      if (['TRIAL', 'ACTIVE', 'PAST_DUE'].includes(status) && !assignment)
        throw new BadRequestException('Assign a plan before activating access');
      // Assigning a package that opens access provisions its website too.
      if (
        (body.planId || body.websiteMode) &&
        ['TRIAL', 'ACTIVE'].includes(status)
      )
        await provisionWebsite(
          tx,
          venueId,
          body.websiteMode,
          actor,
          'subscription.status_set',
        );
      const trialEndsAt =
        body.trialEndsAt !== undefined
          ? date(body.trialEndsAt)
          : before?.trialEndsAt;
      if (status === 'TRIAL' && (!trialEndsAt || trialEndsAt <= new Date()))
        throw new BadRequestException('Trial requires a future end date');
      const now = new Date();
      const paid =
        status === 'ACTIVE'
          ? {
              billingManaged: true,
              billingAnchorAt: now,
              currentPeriodStart: now,
              currentPeriodEndsAt: nextRenewal(
                now,
                assignment!.agreedBillingPeriod ?? 'MONTH',
                now,
              ),
              paymentState: 'MANUAL',
              trialEndedAt:
                before?.status === 'TRIAL' ? now : before?.trialEndedAt,
            }
          : {};
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
          ...paid,
        },
        update: {
          status,
          ...(status === 'TRIAL' && before?.status !== 'TRIAL'
            ? { startedAt: now }
            : {}),
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
          suspendedFrom: status === 'SUSPENDED' ? before?.status : null,
          version: { increment: 1 },
          ...(status === 'CANCELLED' && before?.status === 'TRIAL'
            ? { trialEndedAt: now, trialEndsAt: now }
            : {}),
          ...paid,
        },
      });
      await audit(tx, actor, venueId, 'venue.subscription_changed', {
        planId: assignment?.planId ?? null,
        from: before?.status ?? null,
        to: status,
        note,
        previousTrialEndsAt: before?.trialEndsAt?.toISOString() ?? null,
        trialEndsAt: row.trialEndsAt?.toISOString() ?? null,
        currentPeriodEndsAt: row.currentPeriodEndsAt?.toISOString() ?? null,
      });
      return row;
    };
    if (existingTx) return run(existingTx);
    const result = await this.db.$transaction(run);
    await new CommercialLifecycleService(this.db).reconcile(venueId);
    return result;
  }

  activation(actor: ControlActor, venueId: string) {
    return new ManagerActivationService(this.db, this.vault).issue(
      actor,
      venueId,
    );
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
            OR: [
              { idempotencyKey: { startsWith: 'platform-staff:' } },
              { idempotencyKey: { startsWith: 'manager-activation:' } },
            ],
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
    actor: ControlActor,
    venueId: string,
    action: 'create' | 'reset' | 'disable',
    body: Record<string, unknown>,
    staffId?: string,
  ) {
    if (actor.customerAccountId || !actor.platformUserId)
      throw new ForbiddenException(
        'Only Vynic Platform Admin can manage existing Manager access',
      );
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
        if (action !== 'disable')
          await requireCommercialFeature(tx, venueId, 'MANAGER_APP');
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
        if (
          action === 'create' &&
          !(await tx.staff.count({
            where: { venueId, role: { in: ['MANAGER', 'ADMIN'] } },
          })) &&
          !(await tx.managerActivation.findUnique({ where: { venueId } }))
            ?.consumedAt
        )
          throw new ConflictException(
            'Complete first registration in the enrolled POS',
          );
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
          await assertStaffPinAvailable(tx, venueId, pin, before?.username);
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
      requireText(body.password, 'password', { min: 8, max: 200 }),
    );
    return this.db.$transaction(async (tx) => {
      const user = await tx.platformUser.create({
        data: { email, displayName, role, passwordHash },
        select: userFields,
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId!,
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
          platformUserId: actor.platformUserId!,
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
