import { Controller, Get, Req, Res, UseGuards } from '@nestjs/common';
import type { Request, Response } from 'express';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { sendPublicWebsite } from '../core/website-cache';
import { CustomWebsiteGuard } from '../tenancy/custom-website.guard';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { CustomWebsiteService } from './custom-website.service';

/**
 * The shared public surface for CUSTOM frontends.
 *
 * Host -> VenueDomain -> Venue decides the restaurant, WEBSITE must be
 * effective and the Venue must be CUSTOM. Bookings, payments and customer
 * accounts are the existing shared routes (`/api/tables`, `/api/bog`,
 * `/api/auth`, `/api/user`); this adds the parts a new custom site should not
 * have to re-derive: identity, capabilities and the presentation-aware menu.
 */
@Controller('api/website/custom')
@UseGuards(WebsiteTenantGuard, FeatureGuard, CustomWebsiteGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
export class CustomWebsiteController {
  constructor(private readonly custom: CustomWebsiteService) {}

  @Get('bootstrap')
  async bootstrap(
    @WebsiteTenant() tenant: TenantContext,
    @Req() request: Request,
    @Res() response: Response,
  ) {
    sendPublicWebsite(
      request,
      response,
      await this.custom.publicBootstrap(tenant.venueId),
    );
  }

  @Get('menu')
  async menu(
    @WebsiteTenant() tenant: TenantContext,
    @Req() request: Request,
    @Res() response: Response,
  ) {
    sendPublicWebsite(
      request,
      response,
      await this.custom.publicMenu(tenant.venueId),
    );
  }
}
