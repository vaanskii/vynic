import { Prisma, OnboardingWebsiteMode } from '@prisma/client';
import { resolveEffectiveFeatures } from '../entitlements/effective-features';

// Run after assignment, inside the same provisioning transaction.
export async function initializeWebsite(
  tx: Prisma.TransactionClient,
  venueId: string,
  mode: OnboardingWebsiteMode,
) {
  if (mode !== 'SAAS') return;
  const venue = await tx.venue.findUniqueOrThrow({
    where: { id: venueId },
    include: {
      planAssignment: {
        include: {
          plan: { include: { features: { include: { feature: true } } } },
        },
      },
      featureOverrides: { include: { feature: true } },
    },
  });
  const effective = resolveEffectiveFeatures(
    venue.planAssignment?.plan.features.map((f) => f.feature.key) ?? [],
    venue.featureOverrides.map((f) => ({
      key: f.feature.key,
      effect: f.effect,
    })),
  );
  if (effective.includes('WEBSITE'))
    await tx.venueWebsiteConfig.create({
      data: { venueId, mode: 'SAAS', status: 'DRAFT' },
    });
}
