import { FeatureOverrideEffect } from '@prisma/client';

export interface VenueFeatureOverrideInput {
  key: string;
  effect: FeatureOverrideEffect;
}

/**
 * The one place plan features and Venue overrides are combined.
 *
 * Precedence: an override always wins over the plan default. The absence of an
 * override row is a third state — defer to the plan — so ENABLED grants a
 * feature the plan lacks and DISABLED withholds one the plan includes.
 *
 * Pure on purpose: the ordering rule is the part worth testing exhaustively,
 * and it should not need a database to do it.
 */
export function resolveEffectiveFeatures(
  planFeatureKeys: readonly string[],
  overrides: readonly VenueFeatureOverrideInput[],
): string[] {
  const effective = new Set(planFeatureKeys);

  for (const override of overrides) {
    if (override.effect === FeatureOverrideEffect.ENABLED) {
      effective.add(override.key);
    } else {
      effective.delete(override.key);
    }
  }

  return [...effective].sort();
}
