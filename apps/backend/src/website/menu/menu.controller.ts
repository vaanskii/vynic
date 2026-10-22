import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import {
  RequiresWebsiteCapability,
  WebsiteCapabilityGuard,
} from '../tenancy/website-capability.guard';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { MenuService } from './menu.service';

/**
 * The public menu of whichever restaurant owns the requested host.
 *
 * WebsiteTenantGuard must precede FeatureGuard: it establishes the Venue the
 * entitlement is then checked against. This is Vankisi's original menu shape
 * (`apps/vankisi-custom-web`) over the same canonical catalog every website
 * reads; it is served wherever the MENU capability is, in either mode.
 */
@Controller('api/menu')
@UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
@RequiresWebsiteCapability('MENU')
export class MenuController {
  constructor(private readonly menuService: MenuService) {}

  @Get()
  async getAllCategories(@WebsiteTenant() tenant: TenantContext) {
    return this.menuService.getAllCategories(tenant);
  }

  @Get(':slug')
  async getCategoryBySlug(
    @WebsiteTenant() tenant: TenantContext,
    @Param('slug') slug: string,
  ) {
    return this.menuService.getCategoryBySlug(tenant, slug);
  }
}
