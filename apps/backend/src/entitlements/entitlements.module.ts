import { CommercialProjectionInterceptor } from './commercial-projection.interceptor';
import { Module } from '@nestjs/common';
import { FeatureGuard } from './feature.guard';
import { VenueEntitlementsService } from './venue-entitlements.service';

/**
 * The commercial product layer. It reads Plan, Feature, and Venue overrides;
 * it owns no operational data and no synchronization path depends on it.
 */
@Module({
  providers: [
    CommercialProjectionInterceptor,
    VenueEntitlementsService,
    FeatureGuard,
  ],
  exports: [
    CommercialProjectionInterceptor,
    VenueEntitlementsService,
    FeatureGuard,
  ],
})
export class EntitlementsModule {}
