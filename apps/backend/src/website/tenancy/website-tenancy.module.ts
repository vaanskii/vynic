import { Module } from '@nestjs/common';
import { EntitlementsModule } from '../../entitlements/entitlements.module';
import { WebsiteTenantGuard } from './website-tenant.guard';
import { WebsiteTenantService } from './website-tenant.service';

/**
 * The public tenant boundary. Every website module that reads restaurant data
 * imports this and puts WebsiteTenantGuard in front of its routes.
 */
@Module({
  imports: [EntitlementsModule],
  providers: [WebsiteTenantService, WebsiteTenantGuard],
  exports: [WebsiteTenantService, WebsiteTenantGuard, EntitlementsModule],
})
export class WebsiteTenancyModule {}
