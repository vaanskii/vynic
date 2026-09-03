import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  FeatureOverrideEffect,
  Prisma,
  VenueDomainStatus,
  WebsiteMode,
} from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { normalizeHostname } from '../website/tenancy/website-host';
import type { PlatformPrincipal } from './platform-auth-context';
import {
  PlatformAuditAction,
  PlatformAuditService,
} from './platform-audit.service';
import { PlatformDirectoryService } from './platform-directory.service';

const DOMAIN_FIELDS = {
  id: true,
  venueId: true,
  hostname: true,
  status: true,
  createdAt: true,
  updatedAt: true,
} as const;

/**
 * What a Venue has bought and how it is configured.
 *
 * Product access is never recomputed here. Every answer about entitlement comes
 * from `VenueEntitlementsService`, the same resolver `FeatureGuard` uses in
 * production — a second implementation inside the control plane would be a
 * second truth, and the one the admin sees would be the one nobody enforces.
 */
@Injectable()
export class PlatformVenueConfigService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
    private readonly directory: PlatformDirectoryService,
    private readonly audit: PlatformAuditService,
  ) {}

  async listPlans() {
    return this.prisma.plan.findMany({
      orderBy: { key: 'asc' },
      select: {
        id: true,
        key: true,
        name: true,
        status: true,
        features: {
          select: { feature: { select: { key: true, name: true } } },
        },
      },
    });
  }

  async listFeatures() {
    return this.prisma.feature.findMany({
      orderBy: { key: 'asc' },
      select: { id: true, key: true, name: true },
    });
  }

  /** Plan, overrides, resolved features and website access in one answer. */
  async readProduct(venueId: string) {
    await this.directory.requireVenue(venueId);

    const [assignment, overrides, effectiveFeatures, website] =
      await Promise.all([
        this.prisma.venuePlanAssignment.findUnique({
          where: { venueId },
          select: {
            assignedAt: true,
            plan: { select: { id: true, key: true, name: true, status: true } },
          },
        }),
        this.prisma.venueFeatureOverride.findMany({
          where: { venueId },
          select: {
            effect: true,
            note: true,
            updatedAt: true,
            feature: { select: { key: true, name: true } },
          },
          orderBy: { feature: { key: 'asc' } },
        }),
        this.entitlements.effectiveFeatures(venueId),
        this.entitlements.websiteAccess(venueId),
      ]);

    return {
      venueId,
      plan: assignment?.plan ?? null,
      planAssignedAt: assignment?.assignedAt ?? null,
      overrides: overrides.map((row) => ({
        featureKey: row.feature.key,
        featureName: row.feature.name,
        effect: row.effect,
        note: row.note,
        updatedAt: row.updatedAt,
      })),
      effectiveFeatures,
      website,
    };
  }

  async assignPlan(actor: PlatformPrincipal, venueId: string, planId: string) {
    await this.directory.requireVenue(venueId);
    const plan = await this.prisma.plan.findUnique({
      where: { id: planId },
      select: { id: true, key: true },
    });
    if (!plan) throw new NotFoundException('Plan not found');

    const previous = await this.prisma.venuePlanAssignment.findUnique({
      where: { venueId },
      select: { plan: { select: { key: true } } },
    });

    await this.prisma.venuePlanAssignment.upsert({
      where: { venueId },
      create: { venueId, planId: plan.id },
      update: { planId: plan.id, assignedAt: new Date() },
    });

    await this.audit.record(
      actor,
      PlatformAuditAction.PLAN_ASSIGNED,
      { type: 'Venue', id: venueId },
      { from: previous?.plan.key ?? null, to: plan.key },
    );
    return this.readProduct(venueId);
  }

  /**
   * Sets a per-Venue exception to its plan.
   *
   * Always wins over the plan default, which is the whole reason overrides
   * exist: a special agreement or a trial should not require inventing a fifth
   * plan that then has to be maintained forever.
   */
  async setFeatureOverride(
    actor: PlatformPrincipal,
    venueId: string,
    featureKey: string,
    effect: FeatureOverrideEffect,
    note?: string,
  ) {
    await this.directory.requireVenue(venueId);
    const feature = await this.requireFeature(featureKey);

    await this.prisma.venueFeatureOverride.upsert({
      where: { venueId_featureId: { venueId, featureId: feature.id } },
      create: { venueId, featureId: feature.id, effect, note: note ?? null },
      update: { effect, note: note ?? null },
    });

    await this.audit.record(
      actor,
      PlatformAuditAction.FEATURE_OVERRIDE_SET,
      { type: 'Venue', id: venueId },
      { featureKey: feature.key, effect, note: note ?? null },
    );
    return this.readProduct(venueId);
  }

  /** Removing the row is the third state: defer to whatever the plan says. */
  async clearFeatureOverride(
    actor: PlatformPrincipal,
    venueId: string,
    featureKey: string,
  ) {
    await this.directory.requireVenue(venueId);
    const feature = await this.requireFeature(featureKey);

    const deleted = await this.prisma.venueFeatureOverride.deleteMany({
      where: { venueId, featureId: feature.id },
    });
    if (deleted.count > 0) {
      await this.audit.record(
        actor,
        PlatformAuditAction.FEATURE_OVERRIDE_REMOVED,
        { type: 'Venue', id: venueId },
        { featureKey: feature.key },
      );
    }
    return this.readProduct(venueId);
  }

  /**
   * Sets how an entitled Venue's website is served.
   *
   * Mode and entitlement stay independent. Setting CUSTOM on a Venue without
   * WEBSITE is allowed and recorded as inconsistent rather than refused or
   * silently rewritten — the admin is told what they have, not corrected.
   */
  async setWebsiteMode(
    actor: PlatformPrincipal,
    venueId: string,
    mode: WebsiteMode,
  ) {
    await this.directory.requireVenue(venueId);
    const previous = await this.prisma.venueWebsiteConfig.findUnique({
      where: { venueId },
      select: { mode: true },
    });

    await this.prisma.venueWebsiteConfig.upsert({
      where: { venueId },
      create: { venueId, mode },
      update: { mode },
    });

    await this.audit.record(
      actor,
      PlatformAuditAction.WEBSITE_MODE_CHANGED,
      { type: 'Venue', id: venueId },
      { from: previous?.mode ?? WebsiteMode.NONE, to: mode },
    );
    return this.entitlements.websiteAccess(venueId);
  }

  async listDomains(venueId: string) {
    await this.directory.requireVenue(venueId);
    return this.prisma.venueDomain.findMany({
      where: { venueId },
      select: DOMAIN_FIELDS,
      orderBy: { hostname: 'asc' },
    });
  }

  /**
   * Registers a hostname for a Venue.
   *
   * Normalized by the same function the public request path uses, so what is
   * stored is exactly what an incoming Host will be compared against. A second
   * normalizer here would eventually disagree with that one, and the disagreement
   * would look like a domain that simply does not work.
   */
  async registerDomain(
    actor: PlatformPrincipal,
    venueId: string,
    rawHostname: string,
  ) {
    await this.directory.requireVenue(venueId);
    const hostname = normalizeHostname(rawHostname);
    if (!hostname) {
      throw new BadRequestException('hostname is not a valid host');
    }

    try {
      const domain = await this.prisma.venueDomain.create({
        data: { venueId, hostname },
        select: DOMAIN_FIELDS,
      });
      await this.audit.record(
        actor,
        PlatformAuditAction.DOMAIN_REGISTERED,
        { type: 'Venue', id: venueId },
        { hostname: domain.hostname, domainId: domain.id },
      );
      return domain;
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        // Globally unique on purpose: silently re-pointing a live domain at
        // another restaurant is the failure the constraint exists to prevent.
        throw new ConflictException(
          `${hostname} is already registered to a venue`,
        );
      }
      throw error;
    }
  }

  async setDomainStatus(
    actor: PlatformPrincipal,
    venueId: string,
    domainId: string,
    status: VenueDomainStatus,
  ) {
    const existing = await this.requireDomain(venueId, domainId);
    const domain = await this.prisma.venueDomain.update({
      where: { id: domainId },
      data: { status },
      select: DOMAIN_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.DOMAIN_STATUS_CHANGED,
      { type: 'Venue', id: venueId },
      { hostname: domain.hostname, from: existing.status, to: domain.status },
    );
    return domain;
  }

  /** Releases the hostname so it can be registered again, by anyone. */
  async releaseDomain(
    actor: PlatformPrincipal,
    venueId: string,
    domainId: string,
  ) {
    const existing = await this.requireDomain(venueId, domainId);
    await this.prisma.venueDomain.delete({ where: { id: domainId } });
    await this.audit.record(
      actor,
      PlatformAuditAction.DOMAIN_RELEASED,
      { type: 'Venue', id: venueId },
      { hostname: existing.hostname },
    );
    return { released: existing.hostname };
  }

  private async requireFeature(featureKey: string) {
    const feature = await this.prisma.feature.findUnique({
      where: { key: featureKey },
      select: { id: true, key: true },
    });
    if (!feature)
      throw new NotFoundException(`Feature ${featureKey} not found`);
    return feature;
  }

  private async requireDomain(venueId: string, domainId: string) {
    const domain = await this.prisma.venueDomain.findUnique({
      where: { id: domainId },
      select: DOMAIN_FIELDS,
    });
    // Reported as missing rather than forbidden: a domain of another Venue is
    // not this Venue's business to know about.
    if (!domain || domain.venueId !== venueId) {
      throw new NotFoundException('Domain not found for this venue');
    }
    return domain;
  }
}
