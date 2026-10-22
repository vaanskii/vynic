import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
/** Caller owns the Venue lock and audit. Re-selecting the same plan preserves the agreement. */
export async function assignCommercialPlan(
  tx: Prisma.TransactionClient,
  venueId: string,
  planId: string,
) {
  const plan = await tx.plan.findFirst({
    where: { id: planId, status: 'ACTIVE' },
  });
  if (!plan) throw new BadRequestException('Active plan required');
  const old = await tx.venuePlanAssignment.findUnique({ where: { venueId } });
  if (old?.planId === planId) return old;
  const data = {
    planId,
    agreedPriceMinor: plan.priceMinor,
    agreedCurrency: plan.currency,
    agreedBillingPeriod: plan.billingPeriod,
  };
  return tx.venuePlanAssignment.upsert({
    where: { venueId },
    create: { venueId, ...data },
    update: { ...data, assignedAt: new Date() },
  });
}
