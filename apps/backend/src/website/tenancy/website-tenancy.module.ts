import { Module } from '@nestjs/common';
import { EntitlementsModule } from '../../entitlements/entitlements.module';
import { WebsiteCapabilitiesService } from './website-capabilities.service';
import { WebsiteCapabilityGuard } from './website-capability.guard';
import { WebsiteTenantGuard } from './website-tenant.guard';
import { WebsiteTenantService } from './website-tenant.service';

/**
 * The public tenant boundary. Every website module that reads restaurant data
 * imports this and puts WebsiteTenantGuard in front of its routes, followed by
 * WebsiteCapabilityGuard for the shared capability the route serves.
 */
@Module({
  imports: [EntitlementsModule],
  providers: [
    WebsiteTenantService,
    WebsiteTenantGuard,
    WebsiteCapabilitiesService,
    WebsiteCapabilityGuard,
  ],
  exports: [
    WebsiteTenantService,
    WebsiteTenantGuard,
    WebsiteCapabilitiesService,
    WebsiteCapabilityGuard,
    EntitlementsModule,
  ],
})
export class WebsiteTenancyModule {}
