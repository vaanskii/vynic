import { Module } from '@nestjs/common';
import { FeatureGuard } from './feature.guard';
import { VenueEntitlementsService } from './venue-entitlements.service';

/**
 * The commercial product layer. It reads Plan, Feature, and Venue overrides;
 * it owns no operational data and no synchronization path depends on it.
 */
@Module({
  providers: [VenueEntitlementsService, FeatureGuard],
  exports: [VenueEntitlementsService, FeatureGuard],
})
export class EntitlementsModule {}
