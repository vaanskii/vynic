import {
  CanActivate,
  ExecutionContext,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { WebsiteMode } from '@prisma/client';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import type { WebsiteTenantRequest } from './website-tenant-context';

/**
 * Restricts a public route to Venues whose website is served by a CUSTOM
 * frontend.
 *
 * The shared custom-site surface (bookings, payments, the legacy menu shape,
 * the custom bootstrap) is what a bespoke frontend consumes. A SAAS Venue's
 * host is served by the generic renderer and must not be consumable through it,
 * and an unentitled Venue has no website at all.
 *
 * Must run after WebsiteTenantGuard, which establishes the Venue from the Host.
 * A mismatch is a 404 for the same reason an unknown host is: there is no
 * custom website at that name.
 */
@Injectable()
export class CustomWebsiteGuard implements CanActivate {
  constructor(private readonly entitlements: VenueEntitlementsService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<WebsiteTenantRequest>();
    const venueId = request.websiteContext?.tenant.venueId;
    if (!venueId) {
      throw new Error('CustomWebsiteGuard requires WebsiteTenantGuard first');
    }
    const access = await this.entitlements.websiteAccess(venueId);
    if (access.effectiveMode !== WebsiteMode.CUSTOM) {
      throw new NotFoundException(
        'No custom website is configured for this host',
      );
    }
    return true;
  }
}
