import { NotFoundException } from '@nestjs/common';
import { FeatureOverrideEffect, WebsiteMode } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { FeatureKeys } from './feature-keys';
import { VenueEntitlementsService } from './venue-entitlements.service';

const { POS, WEBSITE, MANAGER_APP } = FeatureKeys;

interface VenueProductFixture {
  planFeatures?: string[];
  overrides?: { key: string; effect: FeatureOverrideEffect }[];
  websiteMode?: WebsiteMode | null;
}

function makeService(fixture: VenueProductFixture | null) {
  const venue = {
    findUnique: jest.fn(() =>
      Promise.resolve(
        fixture === null
          ? null
          : {
              planAssignment: fixture.planFeatures
                ? {
                    plan: {
                      features: fixture.planFeatures.map((key) => ({
                        feature: { key },
                      })),
                    },
                  }
                : null,
              featureOverrides: (fixture.overrides ?? []).map(
                ({ key, effect }) => ({ effect, feature: { key } }),
              ),
              websiteConfig: fixture.websiteMode
                ? { mode: fixture.websiteMode }
                : null,
            },
      ),
    ),
  };
  const prisma = { venue } as unknown as PrismaService;
  return { service: new VenueEntitlementsService(prisma), venue };
}

describe('VenueEntitlementsService', () => {
  describe('effectiveFeatures', () => {
    it('resolves a Venue plan assignment into its features', async () => {
      const { service, venue } = makeService({
        planFeatures: [POS, MANAGER_APP],
      });

      await expect(service.effectiveFeatures('venue-a')).resolves.toEqual([
        MANAGER_APP,
        POS,
      ]);
      expect(venue.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'venue-a' } }),
      );
    });

    it('applies an ENABLED override over the plan default', async () => {
      const { service } = makeService({
        planFeatures: [POS],
        overrides: [{ key: WEBSITE, effect: FeatureOverrideEffect.ENABLED }],
      });

      await expect(service.effectiveFeatures('venue-a')).resolves.toEqual([
        POS,
        WEBSITE,
      ]);
    });

    it('applies a DISABLED override over the plan default', async () => {
      const { service } = makeService({
        planFeatures: [POS, WEBSITE, MANAGER_APP],
        overrides: [
          { key: MANAGER_APP, effect: FeatureOverrideEffect.DISABLED },
        ],
      });

      await expect(service.effectiveFeatures('venue-a')).resolves.toEqual([
        POS,
        WEBSITE,
      ]);
    });

    it('entitles an unassigned Venue to nothing', async () => {
      const { service } = makeService({});

      await expect(service.effectiveFeatures('venue-a')).resolves.toEqual([]);
    });

    it('reads a Venue whole product in a single query', async () => {
      const { service, venue } = makeService({ planFeatures: [POS] });

      await service.effectiveFeatures('venue-a');

      expect(venue.findUnique).toHaveBeenCalledTimes(1);
    });

    it('reports an unknown Venue instead of answering as if it were unentitled', async () => {
      const { service } = makeService(null);

      await expect(service.effectiveFeatures('gone')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });
  });

  describe('hasFeature', () => {
    it('answers for a feature the Venue holds and one it does not', async () => {
      const { service } = makeService({ planFeatures: [POS, WEBSITE] });

      await expect(service.hasFeature('venue-a', POS)).resolves.toBe(true);
      await expect(service.hasFeature('venue-a', MANAGER_APP)).resolves.toBe(
        false,
      );
    });
  });

  describe('websiteAccess', () => {
    it('separates a CUSTOM website from the entitlement that permits it', async () => {
      const { service } = makeService({
        planFeatures: [POS, WEBSITE],
        websiteMode: WebsiteMode.CUSTOM,
      });

      await expect(service.websiteAccess('venue-a')).resolves.toEqual({
        entitled: true,
        configuredMode: WebsiteMode.CUSTOM,
        effectiveMode: WebsiteMode.CUSTOM,
        consistent: true,
      });
    });

    it('represents a SAAS website the same way', async () => {
      const { service } = makeService({
        planFeatures: [POS, WEBSITE],
        websiteMode: WebsiteMode.SAAS,
      });

      await expect(service.websiteAccess('venue-a')).resolves.toEqual({
        entitled: true,
        configuredMode: WebsiteMode.SAAS,
        effectiveMode: WebsiteMode.SAAS,
        consistent: true,
      });
    });

    it('treats an unentitled Venue with no configuration as consistent', async () => {
      const { service } = makeService({ planFeatures: [POS] });

      await expect(service.websiteAccess('venue-a')).resolves.toEqual({
        entitled: false,
        configuredMode: WebsiteMode.NONE,
        effectiveMode: WebsiteMode.NONE,
        consistent: true,
      });
    });

    it('reports a stored mode that outlived its entitlement without erasing it', async () => {
      const { service } = makeService({
        planFeatures: [POS],
        websiteMode: WebsiteMode.CUSTOM,
      });

      await expect(service.websiteAccess('venue-a')).resolves.toEqual({
        entitled: false,
        // Still CUSTOM on disk: an entitlement lapse must not silently discard
        // which website this restaurant runs.
        configuredMode: WebsiteMode.CUSTOM,
        effectiveMode: WebsiteMode.NONE,
        consistent: false,
      });
    });

    it('reports an entitled Venue that has not been configured yet', async () => {
      const { service } = makeService({ planFeatures: [POS, WEBSITE] });

      await expect(service.websiteAccess('venue-a')).resolves.toEqual({
        entitled: true,
        configuredMode: WebsiteMode.NONE,
        effectiveMode: WebsiteMode.NONE,
        consistent: false,
      });
    });

    it('honours an override when deciding website entitlement', async () => {
      const { service } = makeService({
        planFeatures: [POS],
        overrides: [{ key: WEBSITE, effect: FeatureOverrideEffect.ENABLED }],
        websiteMode: WebsiteMode.SAAS,
      });

      await expect(service.websiteAccess('venue-a')).resolves.toMatchObject({
        entitled: true,
        effectiveMode: WebsiteMode.SAAS,
        consistent: true,
      });
    });
  });
});
