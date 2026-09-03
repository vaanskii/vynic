import { SetMetadata } from '@nestjs/common';

export const REQUIRED_FEATURE_KEY = 'requiredFeature';

/**
 * Marks a route as needing a product feature, e.g.
 * `@RequiresFeature(FeatureKeys.MANAGER_APP)`.
 *
 * Takes effect only where FeatureGuard is applied. Step 5A attaches it to no
 * production route — see FeatureGuard for why.
 */
export const RequiresFeature = (featureKey: string) =>
  SetMetadata(REQUIRED_FEATURE_KEY, featureKey);
