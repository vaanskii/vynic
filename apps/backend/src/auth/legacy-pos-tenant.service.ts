import { Injectable } from '@nestjs/common';
import { VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { PosAuthContext } from './pos-auth-context';

export const BOOTSTRAP_ORGANIZATION_ID = '00000000-0000-4000-8000-000000000001';
export const BOOTSTRAP_VENUE_ID = '00000000-0000-4000-8000-000000000002';

/**
 * Transitional tenant resolution for the shared POS_SYNC_API_KEY.
 *
 * A shared key cannot identify a Device, so it may resolve only to the
 * deterministic single-installation Venue created by the Step 4A migration.
 */
@Injectable()
export class LegacyPosTenantService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveContext(): Promise<PosAuthContext | null> {
    const venue = await this.prisma.venue.findUnique({
      where: { id: BOOTSTRAP_VENUE_ID },
      select: { id: true, organizationId: true, status: true },
    });
    if (!venue || venue.status !== VenueStatus.ACTIVE) return null;

    return {
      authenticationMode: 'legacy_shared_key',
      deviceId: null,
      venueId: venue.id,
      organizationId: venue.organizationId,
    };
  }
}
