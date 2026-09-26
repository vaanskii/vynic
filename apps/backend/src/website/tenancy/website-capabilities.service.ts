import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, WebsiteCapabilityKey } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import {
  CapabilityFacts,
  CapabilityState,
  publicCapabilities,
  readCapabilityKey,
  websiteCapabilities,
} from './website-capabilities';

export const WEBSITE_CAPABILITY_CHANGED = 'venue.website_capability_changed';

/**
 * The one answer to "can this Venue's website offer X": Platform, the owner
 * Dashboard, public routes and both frontend kinds all read it here.
 */
@Injectable()
export class WebsiteCapabilitiesService {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
  ) {}

  private async facts(venueId: string): Promise<CapabilityFacts> {
    const [features, policy, menuItems, profile, bookableTables, payment] =
      await Promise.all([
        this.entitlements.effectiveFeatures(venueId),
        this.db.venueWebsiteCapability.findMany({ where: { venueId } }),
        this.db.menuItem.count({ where: { venueId, enabled: true } }),
        this.db.venuePublicProfile.findUnique({
          where: { venueId },
          select: { workingHours: true, gallery: true },
        }),
        this.db.websiteTable.count({ where: { venueId, isActive: true } }),
        this.db.paymentIntegration.findFirst({
          where: { venueId, provider: 'BOG' },
          select: { enabled: true },
        }),
      ]);
    const size = (value: Prisma.JsonValue | undefined) =>
      Array.isArray(value) ? value.length : 0;
    return {
      features,
      policy: Object.fromEntries(policy.map((p) => [p.capability, p.enabled])),
      menuItems,
      hours: size(profile?.workingHours),
      galleryPhotos: size(profile?.gallery),
      bookableTables,
      payment,
    };
  }

  /** Every capability with its commercial, policy, readiness and renderer state. */
  async states(venueId: string): Promise<CapabilityState[]> {
    const [facts, config] = await Promise.all([
      this.facts(venueId),
      this.db.venueWebsiteConfig.findUnique({
        where: { venueId },
        select: { mode: true },
      }),
    ]);
    return websiteCapabilities(facts, config?.mode ?? 'NONE');
  }

  /**
   * Whether the Venue's website is public yet. Launching is the renderer's
   * lifecycle, not a capability: a SAAS site launches when the owner
   * publishes it, a CUSTOM site once the operator has provisioned it. Before
   * that, no shared public route answers for the host, so an unpublished SAAS
   * restaurant's catalog, hours or bookings are not reachable early.
   */
  async launched(venueId: string) {
    const [access, config] = await Promise.all([
      this.entitlements.websiteAccess(venueId),
      this.db.venueWebsiteConfig.findUnique({
        where: { venueId },
        select: { status: true },
      }),
    ]);
    if (access.effectiveMode === 'CUSTOM') return true;
    return access.effectiveMode === 'SAAS' && config?.status === 'PUBLISHED';
  }

  /** Platform read: 404 for an unknown Venue instead of an empty answer. */
  async platformStates(venueId: string) {
    const venue = await this.db.venue.findUnique({
      where: { id: venueId },
      select: { id: true },
    });
    if (!venue) throw new NotFoundException('Venue not found');
    return this.states(venueId);
  }

  async publicCapabilities(venueId: string) {
    return publicCapabilities(await this.states(venueId));
  }

  /** Commercial and enabled: the condition public routes and owner writes enforce. */
  async isAvailable(venueId: string, key: WebsiteCapabilityKey) {
    return (await this.states(venueId)).some(
      (s) => s.key === key && s.available,
    );
  }

  /**
   * Operator policy for one capability. Switching off is always allowed;
   * switching on needs the commercial entitlement, so Platform never offers a
   * switch the package cannot honour. Audited with the change.
   */
  async setEnabled(
    actor: { platformUserId: string },
    venueId: string,
    rawKey: unknown,
    enabled: unknown,
  ) {
    const key = readCapabilityKey(rawKey);
    if (!key)
      throw new BadRequestException(
        'Unknown or unavailable website capability',
      );
    if (typeof enabled !== 'boolean')
      throw new BadRequestException('enabled must be a boolean');
    const venue = await this.db.venue.findUnique({
      where: { id: venueId },
      select: { id: true },
    });
    if (!venue) throw new NotFoundException('Venue not found');
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const before = await tx.venueWebsiteCapability.findUnique({
        where: { venueId_capability: { venueId, capability: key } },
      });
      const from = before?.enabled ?? true;
      if (from === enabled) return;
      if (enabled) {
        const state = (await this.states(venueId)).find((s) => s.key === key)!;
        if (!state.commercial)
          throw new ConflictException(
            `${state.label} is not included in this Venue's package`,
          );
      }
      await tx.venueWebsiteCapability.upsert({
        where: { venueId_capability: { venueId, capability: key } },
        create: { venueId, capability: key, enabled },
        update: { enabled },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: WEBSITE_CAPABILITY_CHANGED,
          targetType: 'Venue',
          targetId: venueId,
          metadata: { capability: key, from, to: enabled },
        },
      });
    });
    return this.states(venueId);
  }
}
