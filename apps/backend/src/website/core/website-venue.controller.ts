import { Controller, Get, Req, Res, UseGuards } from '@nestjs/common';
import type { Request, Response } from 'express';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import {
  RequiresWebsiteCapability,
  WebsiteCapabilityGuard,
} from '../tenancy/website-capability.guard';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { sendPublicWebsite } from './website-cache';
import { WebsiteVenueService } from './website-venue.service';

/**
 * The shared public website contract, identical for SAAS and CUSTOM Venues.
 *
 * Host -> VenueDomain -> Venue decides the restaurant; WEBSITE must be
 * effective and the site launched. Bookings, payments and customer accounts
 * are the existing shared routes (`/api/tables`, `/api/bog`, `/api/auth`,
 * `/api/user`), each gated by its own capability.
 */
@Controller('api/website/venue')
@UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
export class WebsiteVenueController {
  constructor(private readonly venues: WebsiteVenueService) {}

  @Get()
  async site(
    @WebsiteTenant() tenant: TenantContext,
    @Req() request: Request,
    @Res() response: Response,
  ) {
    sendPublicWebsite(
      request,
      response,
      await this.venues.site(tenant.venueId),
    );
  }

  @Get('menu')
  @RequiresWebsiteCapability('MENU')
  async menu(
    @WebsiteTenant() tenant: TenantContext,
    @Req() request: Request,
    @Res() response: Response,
  ) {
    sendPublicWebsite(
      request,
      response,
      await this.venues.menuPayload(tenant.venueId),
    );
  }
}
