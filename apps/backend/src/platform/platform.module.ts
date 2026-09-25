import { WebsiteCoreModule } from '../website/core/website-core.module';
import { CustomWebsiteModule } from '../website/custom/custom-website.module';
import { PlatformCustomWebsiteController } from './platform-custom-website.controller';
import { PlatformHostnameController } from './platform-hostname.controller';
import { PlanCatalogService } from './plan-catalog.service';
import {
  EdgeFoundationController,
  EdgeFoundationService,
} from '../edge-foundation/edge-foundation';
import { PlatformCommercialController } from './platform-commercial.controller';
import { PlatformCommercialService } from './platform-commercial.service';
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { EdgeTransportModule } from '../edge/edge-transport.module';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { PlatformAuditModule } from './platform-audit.module';
import { PlatformAuthController } from './platform-auth.controller';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformCatalogController } from './platform-catalog.controller';
import { PlatformDeviceService } from './platform-device.service';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformOrganizationsController } from './platform-organizations.controller';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { PlatformVenuesController } from './platform-venues.controller';

/**
 * The Vynic control plane.
 *
 * Sits above every tenant and shares nothing with tenant authentication except
 * the primitives it would be wrong to duplicate: the JWT signer, the Argon2id
 * hashing, the entitlement resolver, the device credential service, the edge
 * queue. Everything that decides *who may do this* is its own.
 */
@Module({
  imports: [
    WebsiteCoreModule,
    CustomWebsiteModule,
    AuthModule,
    EntitlementsModule,
    EdgeTransportModule,
    PlatformAuditModule,
  ],
  controllers: [
    PlatformHostnameController,
    PlatformCustomWebsiteController,
    EdgeFoundationController,
    PlatformCommercialController,
    PlatformAuthController,
    PlatformOrganizationsController,
    PlatformVenuesController,
    PlatformCatalogController,
  ],
  providers: [
    PlanCatalogService,
    EdgeFoundationService,
    // Module-local like Customer's: Platform sign-in windows never share state
    // with enrollment or owner sign-in.
    EnrollmentRateLimiter,
    PlatformCommercialService,
    PlatformAuthService,
    PlatformAuthGuard,
    PlatformDirectoryService,
    PlatformVenueConfigService,
    PlatformDeviceService,
  ],
  exports: [PlatformAuthService, PlatformAuthGuard, PlatformCommercialService],
})
export class PlatformModule {}
