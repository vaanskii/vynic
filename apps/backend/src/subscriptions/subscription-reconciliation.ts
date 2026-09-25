import { Prisma } from '@prisma/client';

export const clearPendingPlan = {
  pendingPlanId: null,
  pendingPriceMinor: null,
  pendingCurrency: null,
  pendingBillingPeriod: null,
  pendingChangeAt: null,
};

/** Caller holds the Venue lock. No charging: an unpaid new period is PAST_DUE. */
export async function reconcileSubscription(
  tx: Prisma.TransactionClient,
  venueId: string,
  now: Date,
) {
  const sub = await tx.venueSubscription.findUnique({ where: { venueId } });
  if (!sub) return;
  let action: string | undefined;
  let data: Prisma.VenueSubscriptionUncheckedUpdateInput = {};
  if (sub.status === 'TRIAL' && (!sub.trialEndsAt || sub.trialEndsAt <= now)) {
    action = 'venue.trial_expired';
    data = {
      status: 'SUSPENDED',
      suspendedFrom: 'TRIAL',
      suspendedAt: now,
      trialEndedAt: sub.trialEndsAt ?? now,
    };
  } else if (
    sub.billingManaged &&
    sub.currentPeriodEndsAt &&
    sub.currentPeriodEndsAt <= now &&
    sub.status !== 'CANCELLED'
  ) {
    if (sub.cancelAtPeriodEnd) {
      action = 'subscription.cancellation_effective';
      data = {
        status: 'CANCELLED',
        cancelledAt: sub.currentPeriodEndsAt,
        cancelAtPeriodEnd: false,
        ...clearPendingPlan,
      };
    } else {
      if (
        sub.pendingPlanId &&
        sub.pendingChangeAt &&
        sub.pendingChangeAt <= now
      ) {
        const agreement = await tx.venuePlanAssignment.findUniqueOrThrow({
          where: { venueId },
        });
        if (agreement.agreedBillingPeriod !== sub.pendingBillingPeriod)
          data.billingAnchorAt = sub.currentPeriodEndsAt;
        await tx.venuePlanAssignment.update({
          where: { venueId },
          data: {
            planId: sub.pendingPlanId,
            agreedPriceMinor: sub.pendingPriceMinor,
            agreedCurrency: sub.pendingCurrency,
            agreedBillingPeriod: sub.pendingBillingPeriod,
            assignedAt: sub.pendingChangeAt,
          },
        });
        action = 'subscription.plan_change_effective';
        data = { ...data, ...clearPendingPlan };
      }
      if (sub.status === 'ACTIVE' || sub.status === 'PAST_DUE') {
        if (sub.status !== 'PAST_DUE') {
          action ??= 'subscription.renewal_due';
          data.status = 'PAST_DUE';
          data.paymentState = 'DUE';
        }
      }
    }
  }
  if (!action) return;
  await tx.venueSubscription.update({
    where: { venueId },
    data: { ...data, version: { increment: 1 }, updatedBy: null },
  });
  await tx.platformAuditEvent.create({
    data: {
      action,
      targetType: 'Venue',
      targetId: venueId,
      metadata: {
        source: 'SYSTEM',
        from: sub.status,
        to: data.status ?? sub.status,
        trialEndsAt: sub.trialEndsAt?.toISOString() ?? null,
        planId: sub.pendingPlanId,
        effectiveAt: (
          sub.currentPeriodEndsAt ??
          sub.trialEndsAt ??
          now
        ).toISOString(),
      },
    },
  });
}
