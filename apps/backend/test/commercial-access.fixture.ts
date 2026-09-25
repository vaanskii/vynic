import type { PrismaService } from '../src/prisma.service';

/**
 * The commercial state an operator-approved, dated Trial leaves: an explicit
 * plan assignment and a TRIAL subscription that has not ended.
 *
 * Integration fixtures that exercise product features (POS enrollment,
 * Inventory, …) must hold that product commercially, exactly as a real Venue
 * does; new Venues start NO_PLAN and are refused.
 */
export async function grantTrialPlan(
  db: PrismaService,
  venueId: string,
  planKey: 'POS' | 'POS_MANAGER' | 'POS_WEBSITE' | 'POS_WEBSITE_MANAGER',
) {
  const plan = await db.plan.findUniqueOrThrow({ where: { key: planKey } });
  const trial = {
    status: 'TRIAL' as const,
    startedAt: new Date(),
    trialEndsAt: new Date(Date.now() + 14 * 86_400_000),
  };
  await db.venuePlanAssignment.upsert({
    where: { venueId },
    create: { venueId, planId: plan.id },
    update: { planId: plan.id },
  });
  await db.venueSubscription.upsert({
    where: { venueId },
    create: { venueId, ...trial },
    update: trial,
  });
}
