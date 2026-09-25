import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { CustomWebsiteGuard } from '../tenancy/custom-website.guard';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { MenuService } from './menu.service';

/**
 * The public menu of whichever restaurant owns the requested host.
 *
 * WebsiteTenantGuard must precede FeatureGuard: it establishes the Venue the
 * entitlement is then checked against. This is the custom-site menu shape
 * (Vankisi's `apps/vankisi-custom-web`), so only a CUSTOM Venue's host is served.
 */
@Controller('api/menu')
@UseGuards(WebsiteTenantGuard, FeatureGuard, CustomWebsiteGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
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
