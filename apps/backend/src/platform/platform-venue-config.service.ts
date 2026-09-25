import { requireCommercialFeature } from '../entitlements/commercial-state';
import { assignCommercialPlan } from './plan-assignment';
import { CommercialLifecycleService } from '../entitlements/commercial-lifecycle.service';
import { cloudMenuAdmission } from './cloud-menu-admission';
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
  releaseAfter: true,
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
        description: true,
        priceMinor: true,
        currency: true,
        billingPeriod: true,
        mediaQuotaBytes: true,
        mediaQuotaFiles: true,
        status: true,
        features: {
          select: { feature: { select: { key: true, name: true } } },
        },
      },
    });
  }

  async ensureWebsitePlan(actor: PlatformPrincipal) {
    await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('vynic-website-only-plan'))`;
      const existing = await tx.plan.findUnique({
        where: { key: 'WEBSITE_ONLY' },
      });
      if (existing) return;
      const feature = await tx.feature.findUniqueOrThrow({
        where: { key: 'WEBSITE' },
      });
      const plan = await tx.plan.create({
        data: {
          key: 'WEBSITE_ONLY',
          name: 'Website only',
          features: { create: { featureId: feature.id } },
        },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'plan.website_only_created',
          targetType: 'Plan',
          targetId: plan.id,
        },
      });
    });
    return this.listPlans();
  }

  async enableCloudMenu(
    actor: PlatformPrincipal,
    venueId: string,
    enabled: unknown,
  ) {
    await this.directory.requireVenue(venueId);
    if (typeof enabled !== 'boolean')
      throw new BadRequestException('enabled must be a boolean');
    await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      if (enabled) await requireCommercialFeature(tx, venueId, 'WEBSITE');
      const admission = await cloudMenuAdmission(tx, venueId);
      if (admission.enabled === enabled) return;
      if (enabled && !admission.canEnableCloud)
        throw new ConflictException(admission.reason!);
      await tx.venue.update({
        where: { id: venueId },
        data: {
          ...(enabled ? { menuAuthority: 'CLOUD' as const } : {}),
          cloudMenuEditingEnabled: enabled,
        },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: enabled
            ? 'venue.cloud_menu_enabled'
            : 'venue.cloud_menu_disabled',
          targetType: 'Venue',
          targetId: venueId,
          metadata: { from: admission.authority, enabled },
        },
      });
    });
    return this.readProduct(venueId);
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
            agreedPriceMinor: true,
            agreedCurrency: true,
            agreedBillingPeriod: true,
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
      menuManagement: await cloudMenuAdmission(this.prisma, venueId),
      plan: assignment?.plan ?? null,
      planAssignedAt: assignment?.assignedAt ?? null,
      agreedPrice: assignment
        ? {
            priceMinor: assignment.agreedPriceMinor,
            currency: assignment.agreedCurrency,
            billingPeriod: assignment.agreedBillingPeriod,
          }
        : null,
      planFeatures: await this.entitlements.planFeatures(venueId),
      overrides: overrides.map((row) => ({
        featureKey: row.feature.key,
        featureName: row.feature.name,
        effect: row.effect,
        note: row.note,
        updatedAt: row.updatedAt,
      })),
      effectiveFeatures,
      commercialAccess: await this.entitlements.commercialAccess(venueId),
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

    await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const subscription = await tx.venueSubscription.findUnique({
        where: { venueId },
      });
      if (subscription?.billingManaged)
        throw new BadRequestException(
          'Use subscription plan-change controls for a billing agreement',
        );
      await assignCommercialPlan(tx, venueId, planId);
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: PlatformAuditAction.PLAN_ASSIGNED,
          targetType: 'Venue',
          targetId: venueId,
          metadata: { from: previous?.plan.key ?? null, to: plan.key },
        },
      });
    });
    await new CommercialLifecycleService(this.prisma).reconcile(venueId);
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

    await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const before = await tx.venueFeatureOverride.findUnique({
        where: { venueId_featureId: { venueId, featureId: feature.id } },
      });
      await tx.venueFeatureOverride.upsert({
        where: { venueId_featureId: { venueId, featureId: feature.id } },
        create: { venueId, featureId: feature.id, effect, note: note ?? null },
        update: { effect, note: note ?? null },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: PlatformAuditAction.FEATURE_OVERRIDE_SET,
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            featureKey: feature.key,
            from: before?.effect ?? 'INHERIT',
            to: effect,
            note: note ?? null,
          },
        },
      });
    });
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

    await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const before = await tx.venueFeatureOverride.findUnique({
        where: { venueId_featureId: { venueId, featureId: feature.id } },
      });
      await tx.venueFeatureOverride.deleteMany({
        where: { venueId, featureId: feature.id },
      });
      if (before)
        await tx.platformAuditEvent.create({
          data: {
            platformUserId: actor.platformUserId,
            action: PlatformAuditAction.FEATURE_OVERRIDE_REMOVED,
            targetType: 'Venue',
            targetId: venueId,
            metadata: {
              featureKey: feature.key,
              from: before.effect,
              to: 'INHERIT',
            },
          },
        });
    });
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
    await requireCommercialFeature(this.prisma, venueId, 'WEBSITE');
    const hostname = normalizeHostname(rawHostname);
    if (!hostname) {
      throw new BadRequestException('hostname is not a valid host');
    }

    try {
      return await this.prisma.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        await requireCommercialFeature(tx, venueId, 'WEBSITE');
        const domain = await tx.venueDomain.create({
          data: { venueId, hostname },
          select: DOMAIN_FIELDS,
        });
        await tx.platformAuditEvent.create({
          data: {
            platformUserId: actor.platformUserId,
            action: PlatformAuditAction.DOMAIN_REGISTERED,
            targetType: 'Venue',
            targetId: venueId,
            metadata: { hostname, domainId: domain.id },
          },
        });
        return domain;
      });
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
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      if (status === 'ACTIVE')
        await requireCommercialFeature(tx, venueId, 'WEBSITE');
      const existing = await tx.venueDomain.findFirst({
        where: { id: domainId, venueId },
      });
      if (!existing)
        throw new NotFoundException('Domain not found for this venue');
      const domain = await tx.venueDomain.update({
        where: { id: domainId },
        data: { status },
        select: DOMAIN_FIELDS,
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: PlatformAuditAction.DOMAIN_STATUS_CHANGED,
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            hostname: domain.hostname,
            from: existing.status,
            to: status,
          },
        },
      });
      return domain;
    });
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
