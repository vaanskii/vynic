import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { MenuService } from './menu.service';

/**
 * The public menu of whichever restaurant owns the requested host.
 *
 * WebsiteTenantGuard must precede FeatureGuard: it establishes the Venue the
 * entitlement is then checked against.
 */
@Controller('api/menu')
@UseGuards(WebsiteTenantGuard, FeatureGuard)
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
