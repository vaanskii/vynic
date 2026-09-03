import { VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import {
  BOOTSTRAP_ORGANIZATION_ID,
  BOOTSTRAP_VENUE_ID,
  LegacyPosTenantService,
} from './legacy-pos-tenant.service';

describe('LegacyPosTenantService', () => {
  function makeService() {
    const venue = { findUnique: jest.fn() };
    const prisma = { venue } as unknown as PrismaService;
    return { service: new LegacyPosTenantService(prisma), venue };
  }

  it('resolves the shared key only to the deterministic bootstrap ownership', async () => {
    const { service, venue } = makeService();
    venue.findUnique.mockResolvedValue({
      id: BOOTSTRAP_VENUE_ID,
      organizationId: BOOTSTRAP_ORGANIZATION_ID,
      status: VenueStatus.ACTIVE,
    });

    await expect(service.resolveContext()).resolves.toEqual({
      authenticationMode: 'legacy_shared_key',
      deviceId: null,
      venueId: BOOTSTRAP_VENUE_ID,
      organizationId: BOOTSTRAP_ORGANIZATION_ID,
    });
    expect(venue.findUnique).toHaveBeenCalledWith({
      where: { id: BOOTSTRAP_VENUE_ID },
      select: { id: true, organizationId: true, status: true },
    });
  });

  it.each([null, { status: VenueStatus.DISABLED }])(
    'does not authorize an unavailable bootstrap Venue: %p',
    async (row) => {
      const { service, venue } = makeService();
      venue.findUnique.mockResolvedValue(
        row === null
          ? null
          : {
              id: BOOTSTRAP_VENUE_ID,
              organizationId: BOOTSTRAP_ORGANIZATION_ID,
              ...row,
            },
      );

      await expect(service.resolveContext()).resolves.toBeNull();
    },
  );
});
