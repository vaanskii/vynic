import { Injectable, NotFoundException } from '@nestjs/common';
import { WebsiteMode } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { resolveEffectiveFeatures } from './effective-features';
import { FeatureKeys } from './feature-keys';

/**
 * What a Venue's website entitlement and configuration resolve to together.
 *
 * `configuredMode` is what is stored; `effectiveMode` is what the Venue may
 * actually be served. They differ only when configuration and entitlement have
 * drifted apart, which is reported rather than repaired.
 */
export interface VenueWebsiteAccess {
  /** Does the Venue hold the WEBSITE feature at all? */
  entitled: boolean;
  /** The persisted mode, returned untouched even when it contradicts entitlement. */
  configuredMode: WebsiteMode;
  /** The mode that applies: NONE unless the Venue is entitled. */
  effectiveMode: WebsiteMode;
  /** Whether entitlement and configured mode agree. */
  consistent: boolean;
}

/**
 * The authoritative answer to "what has this Venue bought?".
 *
 * Nothing else may re-derive product access — no controller may branch on a
 * plan key, and no service may keep its own copy of the precedence rule. This
 * class sits strictly above POS → Cloud synchronization: Device
 * authentication, sync ingestion, and the operational mirror never consult it,
 * so no commercial feature can switch infrastructure off.
 *
 * Reads only. Plan assignment and override writes need a platform-admin
 * authorization boundary that does not exist yet, so they are deferred to the
 * control plane rather than exposed without one.
 */
@Injectable()
export class VenueEntitlementsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Every feature key the Venue may use, plan and overrides combined.
   *
   * Plan status is deliberately ignored: retiring a package must stop it being
   * sold without revoking the Venues already on it.
   */
  async effectiveFeatures(venueId: string): Promise<string[]> {
    const venue = await this.loadVenueProduct(venueId);

    const planFeatureKeys =
      venue.planAssignment?.plan.features.map(({ feature }) => feature.key) ??
      [];
    const overrides = venue.featureOverrides.map(({ feature, effect }) => ({
      key: feature.key,
      effect,
    }));

    return resolveEffectiveFeatures(planFeatureKeys, overrides);
  }

  async hasFeature(venueId: string, featureKey: string): Promise<boolean> {
    return (await this.effectiveFeatures(venueId)).includes(featureKey);
  }

  async websiteAccess(venueId: string): Promise<VenueWebsiteAccess> {
    const venue = await this.loadVenueProduct(venueId);

    const planFeatureKeys =
      venue.planAssignment?.plan.features.map(({ feature }) => feature.key) ??
      [];
    const entitled = resolveEffectiveFeatures(
      planFeatureKeys,
      venue.featureOverrides.map(({ feature, effect }) => ({
        key: feature.key,
        effect,
      })),
    ).includes(FeatureKeys.WEBSITE);

    const configuredMode = venue.websiteConfig?.mode ?? WebsiteMode.NONE;

    return {
      entitled,
      configuredMode,
      effectiveMode: entitled ? configuredMode : WebsiteMode.NONE,
      consistent: entitled === (configuredMode !== WebsiteMode.NONE),
    };
  }

  /**
   * One query for a Venue's whole commercial picture.
   *
   * An unknown Venue is not silently treated as an unentitled one: callers
   * hold an authenticated tenant, so a missing row means it was removed, and
   * saying so is better than returning an empty feature set that reads like a
   * legitimate answer.
   */
  private async loadVenueProduct(venueId: string) {
    const venue = await this.prisma.venue.findUnique({
      where: { id: venueId },
      select: {
        planAssignment: {
          select: {
            plan: {
              select: {
                features: { select: { feature: { select: { key: true } } } },
              },
            },
          },
        },
        featureOverrides: {
          select: { effect: true, feature: { select: { key: true } } },
        },
        websiteConfig: { select: { mode: true } },
      },
    });

    if (!venue) {
      throw new NotFoundException(`Venue ${venueId} does not exist`);
    }
    return venue;
  }
}
