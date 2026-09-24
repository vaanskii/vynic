import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { resolveEffectiveFeatures } from './effective-features';
import { commercialAccessAllowed } from './subscription-policy';

/** Shared by reads and mutations under the Venue lock. */
export async function commercialState(
  tx: Prisma.TransactionClient,
  venueId: string,
  now = new Date(),
) {
  const venue = await tx.venue.findUnique({
    where: { id: venueId },
    include: {
      subscription: true,
      planAssignment: {
        include: {
          plan: { include: { features: { include: { feature: true } } } },
        },
      },
      featureOverrides: { include: { feature: true } },
      websiteConfig: true,
    },
  });
  if (!venue) throw new NotFoundException('Venue not found');
  const planFeatures = resolveEffectiveFeatures(
    venue.planAssignment?.plan.features.map((f) => f.feature.key) ?? [],
    venue.featureOverrides.map((f) => ({
      key: f.feature.key,
      effect: f.effect,
    })),
  );
  const legacy = venue.legacyCommercialAccess && !venue.subscription;
  const allowed =
    (legacy || !!venue.planAssignment) &&
    commercialAccessAllowed(
      venue.subscription?.status,
      venue.subscription?.trialEndsAt,
      legacy,
      now,
    );
  return {
    venue,
    planFeatures,
    allowed,
    features: allowed ? planFeatures : [],
  };
}
export async function requireCommercialFeature(
  tx: Prisma.TransactionClient,
  venueId: string,
  feature: string,
) {
  const state = await commercialState(tx, venueId);
  if (!state.features.includes(feature))
    throw new ForbiddenException(`${feature} access is disabled`);
  return state;
}
