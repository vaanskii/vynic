import { commercialState } from '../entitlements/commercial-state';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, VenueSubscription } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { ControlActor } from '../platform/control-actor';
import { requireText } from '../platform/platform-validation';
import { assignCommercialPlan } from '../platform/plan-assignment';
import {
  classifyPlanChange,
  nextRenewal,
  prorateUpgrade,
} from './billing-policy';
import {
  clearPendingPlan,
  reconcileSubscription,
} from './subscription-reconciliation';

export type BillingResult = {
  provider: string;
  eventId: string;
  operationId: string;
  type:
    | 'payment_succeeded'
    | 'payment_failed'
    | 'renewal_succeeded'
    | 'renewal_failed'
    | 'refund'
    | 'credit';
  amountMinor: number;
  currency: string;
};
const planInclude = { features: { include: { feature: true } } } as const;
@Injectable()
export class SubscriptionService {
  constructor(private readonly db: PrismaService) {}
  private async lock(
    tx: Prisma.TransactionClient,
    venueId: string,
    actor?: ControlActor,
  ) {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
    const venue = await tx.venue.findUnique({ where: { id: venueId } });
    if (!venue) throw new NotFoundException('Venue not found');
    if (
      actor?.customerAccountId &&
      !(await tx.organizationMembership.findUnique({
        where: {
          customerAccountId_organizationId: {
            customerAccountId: actor.customerAccountId,
            organizationId: venue.organizationId,
          },
        },
      }))
    )
      throw new ForbiddenException('Owner access required');
  }
  private audit(
    tx: Prisma.TransactionClient,
    venueId: string,
    actor: ControlActor | undefined,
    action: string,
    metadata: Prisma.InputJsonObject,
  ) {
    const data = { action, targetType: 'Venue', targetId: venueId, metadata };
    return actor?.customerAccountId
      ? tx.customerAuditEvent.create({
          data: { ...data, customerAccountId: actor.customerAccountId },
        })
      : tx.platformAuditEvent.create({
          data: { ...data, platformUserId: actor?.platformUserId },
        });
  }
  async snapshot(venueId: string, actor?: ControlActor) {
    return this.db.$transaction(async (tx) => {
      await this.lock(tx, venueId, actor);
      await reconcileSubscription(tx, venueId, new Date());
      const subscription = await tx.venueSubscription.findUnique({
        where: { venueId },
        include: { pendingPlan: { select: { id: true, name: true } } },
      });
      const assignment = await tx.venuePlanAssignment.findUnique({
        where: { venueId },
        include: { plan: { include: planInclude } },
      });
      const history = actor?.customerAccountId
        ? undefined
        : await tx.platformAuditEvent.findMany({
            where: {
              targetId: venueId,
              OR: [
                { action: { startsWith: 'subscription.' } },
                { action: { startsWith: 'venue.subscription' } },
                { action: { startsWith: 'venue.trial' } },
              ],
            },
            orderBy: { createdAt: 'desc' },
            take: 40,
          });
      const operations = await tx.subscriptionBillingOperation.findMany({
        where: { venueId, state: 'PENDING', expiresAt: { gt: new Date() } },
        orderBy: { createdAt: 'desc' },
        take: 10,
      });
      const effective = await commercialState(tx, venueId);
      return {
        ...subscription,
        status:
          subscription?.status ?? (effective.allowed ? 'LEGACY' : 'NO_PLAN'),
        assignment,
        history,
        operations,
        features: effective.features,
      };
    });
  }
  private async current(tx: Prisma.TransactionClient, venueId: string) {
    const sub = await tx.venueSubscription.findUnique({ where: { venueId } });
    if (!sub)
      throw new BadRequestException('Subscription has no commercial state');
    return sub;
  }
  private requirePaidPeriod(sub: VenueSubscription, now: Date) {
    if (
      sub.status !== 'ACTIVE' ||
      !sub.billingManaged ||
      !sub.currentPeriodStart ||
      !sub.currentPeriodEndsAt ||
      sub.currentPeriodEndsAt <= now
    )
      throw new BadRequestException(
        'A current paid billing period is required',
      );
  }
  /** Owner-safe actions and privileged operator actions share the same serialized lifecycle. */
  async action(
    actor: ControlActor,
    venueId: string,
    body: Record<string, unknown>,
    existingTx?: Prisma.TransactionClient,
    at?: Date,
  ) {
    const now = at ?? new Date();
    const action = requireText(body.action, 'Action');
    const operator = !!actor.platformUserId;
    const ownerActions = [
      'SCHEDULE_CHANGE',
      'CANCEL_CHANGE',
      'SCHEDULE_CANCEL',
      'UNDO_CANCEL',
    ];
    if (!operator && !ownerActions.includes(action))
      throw new ForbiddenException('Operator action required');
    const reason = operator
      ? requireText(body.reason ?? body.note, 'Operator reason', { max: 1000 })
      : null;
    const run = async (tx: Prisma.TransactionClient) => {
      await this.lock(tx, venueId, actor);
      await reconcileSubscription(tx, venueId, now);
      if (['TRIAL', 'GRANT_ACTIVE'].includes(action))
        await tx.venueSubscription.upsert({
          where: { venueId },
          create: { venueId, status: 'NO_PLAN' },
          update: {},
        });
      const sub = await this.current(tx, venueId);
      let data: Prisma.VenueSubscriptionUncheckedUpdateInput = {};
      let detail: Prisma.InputJsonObject = {};
      switch (action) {
        case 'GRANT_ACTIVE': {
          if (sub.billingManaged && sub.status !== 'CANCELLED')
            throw new ConflictException(
              'Use upgrade or renewal confirmation for an existing billing agreement',
            );
          if (body.confirm !== true)
            throw new BadRequestException(
              'Confirm manual commercial activation',
            );
          const planId = requireText(body.planId, 'Plan');
          const plan = await tx.plan.findFirst({
            where: { id: planId, status: 'ACTIVE' },
          });
          if (!plan) throw new BadRequestException('Active plan required');
          await tx.venuePlanAssignment.upsert({
            where: { venueId },
            create: {
              venueId,
              planId,
              agreedPriceMinor: plan.priceMinor,
              agreedCurrency: plan.currency,
              agreedBillingPeriod: plan.billingPeriod,
            },
            update: {
              planId,
              agreedPriceMinor: plan.priceMinor,
              agreedCurrency: plan.currency,
              agreedBillingPeriod: plan.billingPeriod,
              assignedAt: now,
            },
          });
          data = {
            status: 'ACTIVE',
            billingManaged: true,
            billingAnchorAt: now,
            currentPeriodStart: now,
            currentPeriodEndsAt: nextRenewal(now, plan.billingPeriod, now),
            paymentState: 'MANUAL',
            trialEndedAt: sub.status === 'TRIAL' ? now : sub.trialEndedAt,
            trialEndsAt: sub.status === 'TRIAL' ? now : sub.trialEndsAt,
            suspendedAt: null,
            suspendedFrom: null,
            cancelledAt: null,
            cancelAtPeriodEnd: false,
            ...clearPendingPlan,
          };
          detail = {
            planId,
            priceMinor: plan.priceMinor,
            currency: plan.currency,
            source: 'MANUAL_AGREEMENT',
          };
          break;
        }

        case 'TRIAL': {
          if (
            sub.billingManaged &&
            ['ACTIVE', 'PAST_DUE', 'SUSPENDED'].includes(sub.status)
          )
            throw new ConflictException(
              'End the paid agreement before starting a trial',
            );
          const end = new Date(String(body.trialEndsAt));
          if (!Number.isFinite(end.getTime()) || end <= now)
            throw new BadRequestException('Trial requires a future end date');
          const planId = requireText(body.planId, 'Plan');
          await assignCommercialPlan(tx, venueId, planId);
          data = {
            status: 'TRIAL',
            billingManaged: false,
            currentPeriodStart: null,
            currentPeriodEndsAt: null,
            billingAnchorAt: null,
            paymentState: 'NONE',
            trialEndsAt: end,
            trialEndedAt: null,
            suspendedAt: null,
            suspendedFrom: null,
            cancelledAt: null,
            cancelAtPeriodEnd: false,
            ...clearPendingPlan,
          };
          detail = { planId, trialEndsAt: end.toISOString() };
          break;
        }
        case 'SUSPEND':
          if (!['ACTIVE', 'TRIAL', 'PAST_DUE'].includes(sub.status))
            throw new ConflictException('Only current access can be suspended');
          data = {
            status: 'SUSPENDED',
            suspendedFrom: sub.status,
            suspendedAt: now,
          };
          break;
        case 'RESUME': {
          if (sub.status !== 'SUSPENDED' || !sub.suspendedFrom)
            throw new ConflictException('No suspended agreement to resume');
          if (
            sub.suspendedFrom === 'TRIAL' &&
            (!sub.trialEndsAt || sub.trialEndsAt <= now)
          )
            throw new ConflictException(
              'Extend the expired trial before resuming',
            );
          if (
            sub.billingManaged &&
            (!sub.currentPeriodEndsAt || sub.currentPeriodEndsAt <= now)
          )
            throw new ConflictException('Confirm a renewal before resuming');
          data = {
            status: sub.suspendedFrom,
            suspendedFrom: null,
            suspendedAt: null,
          };
          break;
        }
        case 'CANCEL_NOW':
          if (body.confirm !== true)
            throw new BadRequestException('Confirm immediate cancellation');
          data = {
            status: 'CANCELLED',
            cancelledAt: now,
            cancelAtPeriodEnd: false,
            suspendedFrom: null,
            ...clearPendingPlan,
          };
          break;
        case 'SCHEDULE_CANCEL':
          this.requirePaidPeriod(sub, now);
          data = { cancelAtPeriodEnd: true, ...clearPendingPlan };
          break;
        case 'UNDO_CANCEL':
          this.requirePaidPeriod(sub, now);
          data = { cancelAtPeriodEnd: false };
          break;
        case 'CANCEL_CHANGE':
          this.requirePaidPeriod(sub, now);
          data = clearPendingPlan;
          break;
        case 'SCHEDULE_CHANGE': {
          this.requirePaidPeriod(sub, now);
          const next = await tx.plan.findFirst({
            where: { id: requireText(body.planId, 'Plan'), status: 'ACTIVE' },
            include: planInclude,
          });
          const old = await tx.venuePlanAssignment.findUniqueOrThrow({
            where: { venueId },
            include: { plan: { include: planInclude } },
          });
          if (
            !next ||
            old.agreedPriceMinor == null ||
            !old.agreedCurrency ||
            !old.agreedBillingPeriod
          )
            throw new BadRequestException(
              'Known agreement and active plan required',
            );
          nextRenewal(now, next.billingPeriod, now);
          if (old.planId === next.id)
            throw new BadRequestException('Plan already assigned');
          if (
            body.expectedPriceMinor !== undefined &&
            (body.expectedPriceMinor !== next.priceMinor ||
              body.expectedCurrency !== next.currency ||
              body.expectedBillingPeriod !== next.billingPeriod)
          )
            throw new ConflictException(
              'Plan terms changed; review the new price before confirming',
            );
          if (
            body.expectedVersion !== undefined &&
            body.expectedVersion !== sub.version
          )
            throw new ConflictException('Subscription changed; review again');
          const classification = classifyPlanChange(
            {
              priceMinor: old.agreedPriceMinor,
              currency: old.agreedCurrency,
              billingPeriod: old.agreedBillingPeriod,
              features: old.plan.features.map((f) => f.feature.key),
            },
            { ...next, features: next.features.map((f) => f.feature.key) },
          );
          if (
            classification === 'UPGRADE' ||
            (classification === 'REVIEW' &&
              !(operator && body.classification === 'RENEWAL_CHANGE'))
          )
            throw new BadRequestException(
              'Added capabilities require an immediate upgrade or explicit operator review',
            );
          data = {
            pendingPlanId: next.id,
            pendingPriceMinor: next.priceMinor,
            pendingCurrency: next.currency,
            pendingBillingPeriod: next.billingPeriod,
            pendingChangeAt: sub.currentPeriodEndsAt,
            cancelAtPeriodEnd: false,
          };
          detail = {
            planId: next.id,
            classification,
            override: body.classification === 'RENEWAL_CHANGE',
            priceMinor: next.priceMinor,
            effectiveAt: sub.currentPeriodEndsAt!.toISOString(),
          };
          break;
        }
        default:
          throw new BadRequestException('Unknown subscription action');
      }
      const result = await tx.venueSubscription.update({
        where: { venueId },
        data: {
          ...data,
          version: { increment: 1 },
          note: reason ?? sub.note,
          updatedBy: actor.platformUserId ?? null,
        },
      });
      await this.audit(
        tx,
        venueId,
        actor,
        'subscription.' + action.toLowerCase(),
        { from: sub.status, to: result.status, reason, ...detail },
      );
      return result;
    };
    return existingTx ? run(existingTx) : this.db.$transaction(run);
  }
  /** Quotes never grant features or record a payment. A quote expires after 15 minutes. */
  async quote(
    actor: ControlActor,
    venueId: string,
    body: Record<string, unknown>,
    at?: Date,
  ) {
    const now = at ?? new Date();
    return this.db.$transaction(async (tx) => {
      await this.lock(tx, venueId, actor);
      await reconcileSubscription(tx, venueId, now);
      const sub = await this.current(tx, venueId);
      const old = await tx.venuePlanAssignment.findUnique({
        where: { venueId },
        include: { plan: { include: planInclude } },
      });
      let kind = 'PURCHASE';
      const plan = await tx.plan.findUnique({
        where: { id: requireText(body.planId, 'Plan') },
        include: planInclude,
      });
      const renewing =
        sub.billingManaged &&
        sub.currentPeriodEndsAt &&
        sub.currentPeriodEndsAt <= now &&
        sub.status !== 'CANCELLED';
      if (
        !plan ||
        (plan.status !== 'ACTIVE' && !(renewing && old?.planId === plan.id))
      )
        throw new BadRequestException('Active plan required');
      let price = plan.priceMinor,
        currency = plan.currency,
        period = plan.billingPeriod;
      if (!renewing) nextRenewal(now, period, now);
      let amount = price;
      if (
        sub.billingManaged &&
        sub.currentPeriodEndsAt &&
        sub.currentPeriodEndsAt <= now &&
        sub.status !== 'CANCELLED'
      ) {
        if (
          !old ||
          old.planId !== plan.id ||
          old.agreedPriceMinor == null ||
          !old.agreedCurrency ||
          !old.agreedBillingPeriod
        )
          throw new ConflictException('Renew the current agreement first');
        kind = 'RENEWAL';
        price = old.agreedPriceMinor;
        currency = old.agreedCurrency;
        period = old.agreedBillingPeriod;
        amount = price;
      } else if (
        sub.status === 'ACTIVE' ||
        sub.status === 'PAST_DUE' ||
        sub.status === 'SUSPENDED'
      ) {
        this.requirePaidPeriod(sub, now);
        if (
          !old ||
          old.agreedPriceMinor == null ||
          !old.agreedCurrency ||
          !old.agreedBillingPeriod
        )
          throw new BadRequestException('Known agreed price required');
        if (old.planId === plan.id)
          throw new BadRequestException('Plan already assigned');
        const classification = classifyPlanChange(
          {
            priceMinor: old.agreedPriceMinor,
            currency: old.agreedCurrency,
            billingPeriod: old.agreedBillingPeriod,
            features: old.plan.features.map((f) => f.feature.key),
          },
          { ...plan, features: plan.features.map((f) => f.feature.key) },
        );
        const override =
          actor.platformUserId &&
          body.classification === 'UPGRADE' &&
          body.reason;
        if (
          classification === 'DOWNGRADE' ||
          classification === 'RENEWAL_CHANGE'
        )
          return {
            kind: 'SCHEDULE_CHANGE',
            planId: plan.id,
            planName: plan.name,
            priceMinor: price,
            currency,
            billingPeriod: period,
            amountMinor: 0,
            effectiveAt: sub.currentPeriodEndsAt!.toISOString(),
            classification,
            subscriptionVersion: sub.version,
          };
        if (
          old.agreedCurrency !== currency ||
          old.agreedBillingPeriod !== period ||
          (classification !== 'UPGRADE' &&
            !(classification === 'REVIEW' && override))
        )
          throw new BadRequestException(
            'Mixed capability changes require operator review',
          );
        kind = 'UPGRADE';
        amount = prorateUpgrade(
          old.agreedPriceMinor,
          price,
          sub.currentPeriodStart!,
          sub.currentPeriodEndsAt!,
          now,
        );
      }
      nextRenewal(now, period, now); // Reject unsupported periods before money is accepted.
      await tx.subscriptionBillingOperation.updateMany({
        where: { venueId, state: 'PENDING' },
        data: { state: 'SUPERSEDED' },
      });
      const operation = await tx.subscriptionBillingOperation.create({
        data: {
          venueId,
          kind,
          subscriptionVersion: sub.version,
          planId: plan.id,
          planName: plan.name,
          priceMinor: price,
          currency,
          billingPeriod: period,
          amountMinor: amount,
          quotedAt: now,
          expiresAt: new Date(
            Math.min(
              now.getTime() + 15 * 60000,
              kind === 'UPGRADE'
                ? sub.currentPeriodEndsAt!.getTime()
                : Infinity,
            ),
          ),
          periodStart: sub.currentPeriodStart,
          periodEnd: sub.currentPeriodEndsAt,
          source: actor.platformUserId ? 'OPERATOR' : 'CUSTOMER',
          reason: body.reason
            ? requireText(body.reason, 'Reason', { max: 1000 })
            : null,
        },
      });
      await this.audit(tx, venueId, actor, 'subscription.quoted', {
        operationId: operation.id,
        kind,
        amountMinor: amount,
        currency,
        planId: plan.id,
        classificationOverride: actor.platformUserId
          ? String(body.classification ?? '')
          : null,
      });
      return operation;
    });
  }
  async manualSuccess(
    actor: ControlActor,
    venueId: string,
    body: Record<string, unknown>,
  ) {
    if (!actor.platformUserId)
      throw new ForbiddenException('Operator required');
    const reason = requireText(body.reason, 'Payment confirmation reason', {
      max: 1000,
    });
    const reference = requireText(
      body.reference,
      'External payment reference',
      { max: 200 },
    );
    if (body.confirm !== true)
      throw new BadRequestException('Confirm the externally verified payment');
    const op = await this.db.subscriptionBillingOperation.findFirst({
      where: { id: requireText(body.operationId, 'Operation'), venueId },
    });
    if (!op) throw new NotFoundException('Billing operation not found');
    return this.applyTrustedResult(
      {
        provider: 'MANUAL',
        eventId: reference,
        operationId: op.id,
        type: op.kind === 'RENEWAL' ? 'renewal_succeeded' : 'payment_succeeded',
        amountMinor: op.amountMinor,
        currency: op.currency,
      },
      actor,
      reason,
    );
  }
  /** Internal boundary only: future adapters verify signatures/merchant identity before calling.
   * No customer HTTP endpoint can submit this event or choose authoritative timestamps. */
  async applyTrustedResult(
    event: BillingResult,
    actor?: ControlActor,
    reason?: string,
    at?: Date,
  ) {
    const now = at ?? new Date();
    requireText(event.provider, 'Provider', { max: 100 });
    requireText(event.eventId, 'Event identity', { max: 200 });
    if (
      ![
        'payment_succeeded',
        'payment_failed',
        'renewal_succeeded',
        'renewal_failed',
        'refund',
        'credit',
      ].includes(event.type)
    )
      throw new BadRequestException('Unsupported billing event');
    return this.db.$transaction(async (tx) => {
      const initial = await tx.subscriptionBillingOperation.findUnique({
        where: { id: event.operationId },
      });
      if (!initial) throw new NotFoundException('Billing operation not found');
      await this.lock(tx, initial.venueId);
      const op = await tx.subscriptionBillingOperation.findUniqueOrThrow({
        where: { id: initial.id },
      });
      const existing = await tx.subscriptionBillingEvent.findUnique({
        where: {
          provider_eventId: {
            provider: event.provider,
            eventId: event.eventId,
          },
        },
      });
      if (existing) {
        if (
          existing.operationId !== op.id ||
          existing.type !== event.type ||
          existing.amountMinor !== event.amountMinor ||
          existing.currency !== event.currency
        )
          throw new ConflictException('Payment event identity reused');
        return this.current(tx, op.venueId);
      }
      if (
        !Number.isSafeInteger(event.amountMinor) ||
        event.amountMinor < 0 ||
        event.currency !== op.currency
      )
        throw new BadRequestException('Payment amount/currency mismatch');
      const adjustment = ['refund', 'credit'].includes(event.type);
      if (adjustment) {
        if (op.state !== 'SUCCEEDED' || event.amountMinor > op.amountMinor)
          throw new ConflictException('Adjustment needs a settled payment');
        const prior = await tx.subscriptionBillingEvent.aggregate({
          where: { operationId: op.id, type: { in: ['refund', 'credit'] } },
          _sum: { amountMinor: true },
        });
        if ((prior._sum.amountMinor ?? 0) + event.amountMinor > op.amountMinor)
          throw new ConflictException('Adjustments exceed the settled amount');
        await tx.subscriptionBillingEvent.create({ data: event });
        await this.audit(tx, op.venueId, actor, 'subscription.' + event.type, {
          operationId: op.id,
          amountMinor: event.amountMinor,
          reason: reason ?? null,
        });
        return this.current(tx, op.venueId); // Recording an adjustment never silently changes access.
      }
      await reconcileSubscription(tx, op.venueId, now);
      const sub = await this.current(tx, op.venueId);
      if (
        op.state !== 'PENDING' ||
        op.expiresAt <= now ||
        op.subscriptionVersion !== sub.version
      )
        throw new ConflictException(
          'Stale billing operation; reconcile payment before creating a new quote',
        );
      if (
        event.amountMinor !== op.amountMinor ||
        event.type.startsWith('renewal_') !== (op.kind === 'RENEWAL')
      )
        throw new BadRequestException(
          'Payment does not match the quoted operation',
        );
      const success = event.type.endsWith('_succeeded');
      await tx.subscriptionBillingEvent.create({ data: event });
      await tx.subscriptionBillingOperation.update({
        where: { id: op.id },
        data: { state: success ? 'SUCCEEDED' : 'FAILED' },
      });
      if (!success) {
        await tx.venueSubscription.update({
          where: { venueId: op.venueId },
          data: { paymentState: 'FAILED' },
        });
        await this.audit(tx, op.venueId, actor, 'subscription.' + event.type, {
          operationId: op.id,
          reason: reason ?? null,
        });
        return this.current(tx, op.venueId);
      }
      let start = now,
        anchor = now,
        end = nextRenewal(now, op.billingPeriod, now);
      if (op.kind === 'UPGRADE') {
        this.requirePaidPeriod(sub, now);
        start = sub.currentPeriodStart!;
        anchor = sub.billingAnchorAt!;
        end = sub.currentPeriodEndsAt!;
      } else if (op.kind === 'RENEWAL') {
        start = sub.currentPeriodEndsAt!;
        // Period changes begin at the existing renewal boundary, never at selection time.
        anchor = sub.billingAnchorAt!;
        end = nextRenewal(anchor, op.billingPeriod, start);
        if (end <= now)
          throw new ConflictException(
            'Overdue multiple periods require operator reconciliation',
          );
      }
      await tx.venuePlanAssignment.upsert({
        where: { venueId: op.venueId },
        create: {
          venueId: op.venueId,
          planId: op.planId,
          agreedPriceMinor: op.priceMinor,
          agreedCurrency: op.currency,
          agreedBillingPeriod: op.billingPeriod,
        },
        update: {
          planId: op.planId,
          agreedPriceMinor: op.priceMinor,
          agreedCurrency: op.currency,
          agreedBillingPeriod: op.billingPeriod,
          assignedAt: now,
        },
      });
      const row = await tx.venueSubscription.update({
        where: { venueId: op.venueId },
        data: {
          status: sub.status === 'SUSPENDED' ? 'SUSPENDED' : 'ACTIVE',
          suspendedFrom: sub.status === 'SUSPENDED' ? 'ACTIVE' : null,
          billingManaged: true,
          startedAt: sub.startedAt ?? now,
          currentPeriodStart: start,
          currentPeriodEndsAt: end,
          billingAnchorAt: anchor,
          trialEndedAt: sub.status === 'TRIAL' ? now : sub.trialEndedAt,
          trialEndsAt: sub.status === 'TRIAL' ? now : sub.trialEndsAt,
          cancelledAt: null,
          paymentState: 'PAID',
          cancelAtPeriodEnd: false,
          ...clearPendingPlan,
          version: { increment: 1 },
          updatedBy: actor?.platformUserId ?? null,
        },
      });
      await this.audit(tx, op.venueId, actor, 'subscription.' + event.type, {
        operationId: op.id,
        kind: op.kind,
        provider: event.provider,
        eventId: event.eventId,
        amountMinor: op.amountMinor,
        currency: op.currency,
        from: sub.status,
        to: row.status,
        planId: op.planId,
        renewalAt: end.toISOString(),
        reason: reason ?? null,
      });
      return row;
    });
  }
}
