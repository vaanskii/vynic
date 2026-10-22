import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { publicCapabilities } from '../tenancy/website-capabilities';
import { VenuePublicProfileService } from './venue-public-profile.service';
import { WebsiteMenuService } from './website-menu.service';
import { websiteVenueIdentity } from './website-identity';

/** Version of the shared `/api/website/venue` contract. */
export const SHARED_WEBSITE_SCHEMA_VERSION = 1;

// Public identity is live Venue profile data, without legal/account fields.
const publicProfile = {
  name: true,
  branchName: true,
  address: true,
  phone: true,
  timezone: true,
  currency: true,
} as const;

/**
 * The Venue-level website contract every frontend reads, SAAS or CUSTOM.
 *
 * Takes only a Venue that WebsiteTenantGuard resolved from the Host and that
 * WebsiteCapabilityGuard confirmed is launched. The answer does not depend on
 * the mode except for `site`, which names the CUSTOM frontend build meant to
 * serve the Venue (information for misattachment checks, never authority).
 */
@Injectable()
export class WebsiteVenueService {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
    private readonly capabilities: WebsiteCapabilitiesService,
    private readonly info: VenuePublicProfileService,
    private readonly menu: WebsiteMenuService,
  ) {}

  async site(venueId: string) {
    const [profile, access, binding, states] = await Promise.all([
      this.db.venue.findUniqueOrThrow({
        where: { id: venueId },
        select: publicProfile,
      }),
      this.entitlements.websiteAccess(venueId),
      this.db.customWebsiteBinding.findUnique({
        where: { venueId },
        select: { siteKey: true, status: true },
      }),
      this.capabilities.states(venueId),
    ]);
    return {
      schemaVersion: SHARED_WEBSITE_SCHEMA_VERSION,
      identity: { venue: websiteVenueIdentity(venueId) },
      mode: access.effectiveMode,
      site:
        access.effectiveMode === 'CUSTOM'
          ? {
              key: binding?.siteKey ?? null,
              status: binding?.status ?? 'NOT_CONFIGURED',
            }
          : null,
      profile,
      info: await this.info.publicInfo(venueId, states),
      capabilities: publicCapabilities(states),
    };
  }

  /**
   * The canonical catalog with the owner's website presentation applied:
   * hidden and disabled items never appear. Vankisi's original `/api/menu`
   * shape reads the same catalog.
   */
  async menuPayload(venueId: string) {
    const [venue, { categories }] = await Promise.all([
      this.db.venue.findUniqueOrThrow({
        where: { id: venueId },
        select: { currency: true },
      }),
      this.menu.publicMenu(venueId),
    ]);
    return {
      schemaVersion: SHARED_WEBSITE_SCHEMA_VERSION,
      currency: venue.currency,
      categories,
    };
  }
}
