import { nextRenewal } from '../subscriptions/billing-policy';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, OwnerInvitation, CustomerAccount } from '@prisma/client';
import { createHash, randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { requireText } from '../platform/platform-validation';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import {
  CustomerAuth,
  CustomerPrincipal,
  customerPassword,
} from './customer-auth';
import { PlatformPrincipal } from '../platform/platform-auth-context';
import { initializeWebsite } from './onboarding-website';
import { profileInput } from '../venue-profile/venue-profile';

const hash = (token: string) =>
  createHash('sha256').update(token).digest('hex');
const invitationFields = {
  id: true,
  organizationId: true,
  email: true,
  role: true,
  expiresAt: true,
  acceptedAt: true,
  revokedAt: true,
  createdAt: true,
  createdBy: true,
  acceptedById: true,
  revokedBy: true,
  organization: { select: { name: true } },
} as const;

@Injectable()
export class OwnerInvitationsService {
  constructor(
    private readonly db: PrismaService,
    private readonly auth: CustomerAuth,
    private readonly limiter: EnrollmentRateLimiter,
  ) {}

  private email(value: unknown) {
    const email = requireText(value, 'email', { max: 254 }).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new BadRequestException('Invalid email');
    return email;
  }
  private token(value: unknown) {
    if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value))
      throw new BadRequestException(
        'Invitation is invalid or no longer available',
      );
    return value;
  }
  private valid(row: OwnerInvitation | null): asserts row is OwnerInvitation {
    if (!row || row.acceptedAt || row.revokedAt || row.expiresAt <= new Date())
      throw new BadRequestException(
        'Invitation is invalid or no longer available',
      );
  }
  private throttle(ip: string) {
    if (!this.limiter.consume('owner-invitation:' + ip, 30, 900000))
      throw new HttpException('Too many attempts. Try again later.', 429);
  }
  private async audit(
    tx: Prisma.TransactionClient,
    actor: PlatformPrincipal,
    action: string,
    id: string,
  ) {
    await tx.platformAuditEvent.create({
      data: {
        platformUserId: actor.platformUserId,
        action,
        targetType: 'OwnerInvitation',
        targetId: id,
      },
    });
  }
  async issue(
    tx: Prisma.TransactionClient,
    actor: PlatformPrincipal,
    organizationId: string,
    email: string,
  ) {
    // Serialize issuance/acceptance/revocation on the Organization, including new rows.
    const org = await tx.organization.findUnique({
      where: { id: organizationId },
    });
    if (!org) throw new NotFoundException('Organization not found');
    await tx.$queryRaw`SELECT "id" FROM "pos"."Organization" WHERE "id"=${organizationId} FOR UPDATE`;
    const pending = await tx.ownerInvitation.findMany({
      where: { organizationId, email, acceptedAt: null, revokedAt: null },
    });
    for (const old of pending) {
      await tx.ownerInvitation.update({
        where: { id: old.id },
        data: { revokedAt: new Date(), revokedBy: actor.platformUserId },
      });
      await this.audit(tx, actor, 'owner_invitation.revoked', old.id);
    }
    const token = randomBytes(32).toString('base64url');
    const invitation = await tx.ownerInvitation.create({
      data: {
        organizationId,
        email,
        tokenHash: hash(token),
        expiresAt: new Date(Date.now() + 7 * 86400000),
        createdBy: actor.platformUserId,
      },
      select: invitationFields,
    });
    await this.audit(tx, actor, 'owner_invitation.created', invitation.id);
    // Only issuance returns the secret. Fragments never reach HTTP access logs.
    return { invitation, invitationPath: '/invite#token=' + token };
  }

  list() {
    return this.db.ownerInvitation.findMany({
      select: invitationFields,
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }
  organizations() {
    return this.db.organization.findMany({
      select: {
        id: true,
        name: true,
        venues: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }
  create(actor: PlatformPrincipal, body: Record<string, unknown>) {
    const organizationId = requireText(body.organizationId, 'Organization');
    const email = this.email(body.email);
    return this.db.$transaction((tx) =>
      this.issue(tx, actor, organizationId, email),
    );
  }
  async change(actor: PlatformPrincipal, id: string, regenerate: boolean) {
    return this.db.$transaction(async (tx) => {
      const row = await tx.ownerInvitation.findUnique({ where: { id } });
      if (!row) throw new NotFoundException('Invitation not found');
      await tx.$queryRaw`SELECT "id" FROM "pos"."Organization" WHERE "id"=${row.organizationId} FOR UPDATE`;
      const current = await tx.ownerInvitation.findUniqueOrThrow({
        where: { id },
      });
      if (current.acceptedAt)
        throw new ConflictException('Accepted invitations cannot be changed');
      if (regenerate)
        return this.issue(tx, actor, row.organizationId, row.email);
      if (!current.revokedAt) {
        await tx.ownerInvitation.update({
          where: { id },
          data: { revokedAt: new Date(), revokedBy: actor.platformUserId },
        });
        await this.audit(tx, actor, 'owner_invitation.revoked', id);
      }
      return { revoked: true };
    });
  }
  async provision(
    actor: PlatformPrincipal,
    body: Record<string, unknown>,
    existingTx?: Prisma.TransactionClient,
  ) {
    const name = requireText(body.organizationName, 'Organization name', {
      max: 100,
    });
    const profile = profileInput(body);
    const email = this.email(body.email);
    const planId = body.planId ? requireText(body.planId, 'Plan') : null;
    const trialDays = Number(body.trialDays ?? 14);
    if (!Number.isInteger(trialDays) || trialDays < 1 || trialDays > 90)
      throw new BadRequestException('Trial must be 1–90 days');
    const status = body.subscriptionStatus ?? 'NO_PLAN';
    if (!['NO_PLAN', 'TRIAL', 'ACTIVE'].includes(String(status)))
      throw new BadRequestException('Choose No plan, Trial or Active');
    if (status !== 'NO_PLAN' && !planId)
      throw new BadRequestException('Choose a plan explicitly');
    const run = async (tx: Prisma.TransactionClient) => {
      const plan = await tx.plan.findFirst({
        where: { id: planId ?? undefined, status: 'ACTIVE' },
      });
      if (planId && !plan)
        throw new BadRequestException('Active plan required');
      const org = await tx.organization.create({ data: { name } });
      const venue = await tx.venue.create({
        data: {
          organizationId: org.id,
          ...profile,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          profileUpdatedAt: new Date(),
          ...(planId && plan
            ? {
                planAssignment: {
                  create: {
                    planId,
                    agreedPriceMinor: plan.priceMinor,
                    agreedCurrency: plan.currency,
                    agreedBillingPeriod: plan.billingPeriod,
                  },
                },
              }
            : {}),
          subscription: {
            create: {
              status: status as 'NO_PLAN' | 'TRIAL' | 'ACTIVE',
              startedAt: new Date(),
              updatedBy: actor.platformUserId,
              ...(status === 'ACTIVE'
                ? {
                    billingManaged: true,
                    billingAnchorAt: new Date(),
                    currentPeriodStart: new Date(),
                    currentPeriodEndsAt: nextRenewal(
                      new Date(),
                      plan!.billingPeriod,
                      new Date(),
                    ),
                    paymentState: 'MANUAL',
                  }
                : {}),
              trialEndsAt:
                status === 'TRIAL'
                  ? new Date(Date.now() + trialDays * 86400000)
                  : null,
            },
          },
        },
      });
      const policy = await tx.onboardingPolicy.findUnique({
        where: { id: 'default' },
      });
      await initializeWebsite(
        tx,
        venue.id,
        policy?.defaultWebsiteMode ?? 'NONE',
      );
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'onboarding.customer_prepared',
          targetType: 'Venue',
          targetId: venue.id,
          metadata: {
            organizationId: org.id,
            planId,
            subscriptionStatus: status,
          },
        },
      });
      return {
        organization: org,
        venue,
        ...(await this.issue(tx, actor, org.id, email)),
      };
    };
    return existingTx ? run(existingTx) : this.db.$transaction(run);
  }
  async inspect(body: Record<string, unknown>, ip: string) {
    this.throttle(ip);
    const row = await this.db.ownerInvitation.findUnique({
      where: { tokenHash: hash(this.token(body.token)) },
      include: { organization: true },
    });
    this.valid(row);
    const account = await this.db.customerAccount.findUnique({
      where: { email: row.email },
      select: { id: true },
    });
    return {
      email: row.email,
      organizationName: row.organization.name,
      expiresAt: row.expiresAt,
      existingAccount: !!account,
    };
  }
  async accept(
    body: Record<string, unknown>,
    ip: string,
    actor?: CustomerPrincipal,
  ) {
    this.throttle(ip);
    const tokenHash = hash(this.token(body.token));
    // No password handling for existing accounts: only normal Customer JWT authentication.
    let passwordHash: string | undefined;
    let displayName: string | undefined;
    if (!actor) {
      displayName = requireText(body.displayName, 'name', { max: 100 });
      passwordHash = await argon2.hash(customerPassword(body.password, true), {
        type: argon2.argon2id,
      });
    }
    try {
      const result = await this.db.$transaction(async (tx) => {
        const initial = await tx.ownerInvitation.findUnique({
          where: { tokenHash },
        });
        this.valid(initial);
        await tx.$queryRaw`SELECT "id" FROM "pos"."Organization" WHERE "id"=${initial.organizationId} FOR UPDATE`;
        const row = await tx.ownerInvitation.findUnique({
          where: { tokenHash },
        });
        this.valid(row);
        let account: CustomerAccount | null;
        if (actor) {
          account = await tx.customerAccount.findUnique({
            where: { id: actor.customerAccountId },
          });
          if (!account?.isActive || account.email !== row.email)
            throw new ForbiddenException(
              'Sign in with the invited email address',
            );
        } else {
          if (
            await tx.customerAccount.findUnique({ where: { email: row.email } })
          )
            throw new ConflictException(
              'This account already exists. Sign in to accept the invitation.',
            );
          account = await tx.customerAccount.create({
            data: {
              email: row.email,
              displayName: displayName!,
              passwordHash: passwordHash!,
            },
          });
        }
        await tx.organizationMembership.upsert({
          where: {
            customerAccountId_organizationId: {
              customerAccountId: account.id,
              organizationId: row.organizationId,
            },
          },
          create: {
            customerAccountId: account.id,
            organizationId: row.organizationId,
            role: 'OWNER',
          },
          update: {},
        });
        await tx.ownerInvitation.update({
          where: { id: row.id },
          data: { acceptedAt: new Date(), acceptedById: account.id },
        });
        await tx.customerAuditEvent.create({
          data: {
            customerAccountId: account.id,
            action: 'owner_invitation.accepted',
            targetType: 'Organization',
            targetId: row.organizationId,
            metadata: { invitationId: row.id },
          },
        });
        const venue = await tx.venue.findFirst({
          where: { organizationId: row.organizationId },
          orderBy: { createdAt: 'asc' },
          select: { id: true },
        });
        return {
          account: {
            id: account.id,
            email: account.email,
            displayName: account.displayName,
          },
          organizationId: row.organizationId,
          venueId: venue?.id ?? null,
        };
      });
      return {
        ...(await this.auth.session(result.account)),
        organizationId: result.organizationId,
        venueId: result.venueId,
      };
    } catch (error) {
      if ((error as { code?: string }).code === 'P2002')
        throw new ConflictException(
          'This account already exists. Sign in to accept the invitation.',
        );
      throw error;
    }
  }
}
