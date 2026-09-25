import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CustomWebsiteStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteMenuService } from '../core/website-menu.service';
import {
  CUSTOM_WEBSITE_SCHEMA_VERSION,
  CUSTOM_WEBSITE_STATUSES,
  customCapabilities,
  customReadiness,
  paymentStatus,
  readSiteKey,
  requiresReadiness,
} from './custom-website';

/** Platform audit actions owned by CUSTOM website provisioning. */
export const CustomWebsiteAuditAction = {
  SITE_KEY_CHANGED: 'venue.custom_website_site_key_changed',
  STATUS_CHANGED: 'venue.custom_website_status_changed',
} as const;

/** Audit actions an operator reviewing a CUSTOM site needs to see together. */
const CUSTOM_AUDIT_ACTIONS = [
  CustomWebsiteAuditAction.SITE_KEY_CHANGED,
  CustomWebsiteAuditAction.STATUS_CHANGED,
  'venue.website_mode_changed',
  'venue.domain_registered',
  'venue.domain_status_changed',
  'venue.domain_released',
  'venue.feature_override_set',
  'venue.feature_override_removed',
];

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
 * The CUSTOM website product: one shared backend behind any number of bespoke
 * frontends.
 *
 * Every public method takes a Venue that WebsiteTenantGuard already resolved
 * from the request Host and CustomWebsiteGuard already confirmed is CUSTOM.
 * Nothing here accepts a Venue, domain or organization from a browser.
 */
@Injectable()
export class CustomWebsiteService {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
    private readonly menu: WebsiteMenuService,
  ) {}

  private async facts(venueId: string) {
    const [features, access, binding, domains, integration, bookableTables] =
      await Promise.all([
        this.entitlements.effectiveFeatures(venueId),
        this.entitlements.websiteAccess(venueId),
        this.db.customWebsiteBinding.findUnique({ where: { venueId } }),
        this.db.venueDomain.findMany({
          where: { venueId },
          select: { id: true, hostname: true, status: true, createdAt: true },
          orderBy: { hostname: 'asc' },
        }),
        this.db.paymentIntegration.findFirst({
          where: { venueId, provider: 'BOG' },
          select: { enabled: true },
        }),
        this.db.websiteTable.count({ where: { venueId, isActive: true } }),
      ]);
    const payments = paymentStatus(features, integration);
    return {
      features,
      access,
      binding,
      domains,
      payments,
      capabilities: customCapabilities(features, {
        paymentsEnabled: payments === 'ENABLED',
        bookableTables,
      }),
    };
  }

  // ------------------------------------------------------------------ public

  /**
   * What a custom frontend needs to start: which restaurant this is, which
   * frontend is meant to serve it, and which shared capabilities it has.
   *
   * `site.key` lets a frontend detect that it was deployed on the wrong
   * Venue's domain. It is information, never authority: the Venue was already
   * decided by the Host before this ran.
   */
  async publicBootstrap(venueId: string) {
    const [profile, facts] = await Promise.all([
      this.db.venue.findUniqueOrThrow({
        where: { id: venueId },
        select: publicProfile,
      }),
      this.facts(venueId),
    ]);
    return {
      schemaVersion: CUSTOM_WEBSITE_SCHEMA_VERSION,
      mode: 'CUSTOM' as const,
      site: {
        key: facts.binding?.siteKey ?? null,
        status: facts.binding?.status ?? 'NOT_CONFIGURED',
      },
      profile,
      capabilities: facts.capabilities,
    };
  }

  /**
   * The canonical menu with the owner's website presentation applied, in the
   * same shape the generic SaaS site receives. Hidden and disabled items never
   * appear; the Vankisi-only `/api/menu` shape stays separate.
   */
  async publicMenu(venueId: string) {
    const [venue, { categories }] = await Promise.all([
      this.db.venue.findUniqueOrThrow({
        where: { id: venueId },
        select: { currency: true },
      }),
      this.menu.publicMenu(venueId),
    ]);
    return {
      schemaVersion: CUSTOM_WEBSITE_SCHEMA_VERSION,
      currency: venue.currency,
      categories,
    };
  }

  // ---------------------------------------------------------------- platform

  /** Everything an operator needs to provision and verify one CUSTOM site. */
  async platformView(venueId: string) {
    const venue = await this.db.venue.findUnique({
      where: { id: venueId },
      select: { id: true, name: true, organizationId: true },
    });
    if (!venue) throw new NotFoundException('Venue not found');
    const [facts, audit, subscription] = await Promise.all([
      this.facts(venueId),
      this.db.platformAuditEvent.findMany({
        where: {
          targetType: 'Venue',
          targetId: venueId,
          action: { in: CUSTOM_AUDIT_ACTIONS },
        },
        orderBy: { createdAt: 'desc' },
        take: 25,
        select: {
          id: true,
          action: true,
          metadata: true,
          createdAt: true,
          actor: { select: { email: true, displayName: true } },
        },
      }),
      this.db.venueSubscription.findUnique({
        where: { venueId },
        select: { status: true, trialEndsAt: true },
      }),
    ]);
    const activeDomains = facts.domains.filter((d) => d.status === 'ACTIVE');
    const readiness = customReadiness({
      entitled: facts.access.entitled,
      mode: facts.access.configuredMode,
      siteKey: facts.binding?.siteKey ?? null,
      activeDomains: activeDomains.length,
    });
    return {
      venueId,
      mode: facts.access.configuredMode,
      effectiveMode: facts.access.effectiveMode,
      entitled: facts.access.entitled,
      commercialStatus: subscription?.status ?? 'NO_PLAN',
      trialEndsAt: subscription?.trialEndsAt ?? null,
      status: facts.binding?.status ?? 'NOT_CONFIGURED',
      siteKey: facts.binding?.siteKey ?? null,
      statusNote: facts.binding?.statusNote ?? null,
      updatedAt: facts.binding?.updatedAt ?? null,
      domains: facts.domains,
      payments: facts.payments,
      capabilities: facts.capabilities,
      readiness,
      audit: audit.map((event) => ({
        id: event.id,
        action: event.action,
        metadata: event.metadata,
        createdAt: event.createdAt,
        actor: event.actor?.displayName || event.actor?.email || 'system',
      })),
    };
  }

  /**
   * Records the frontend identity and/or setup status of a CUSTOM site.
   *
   * Operator-only (the route is behind PlatformAuthGuard, which also refuses
   * SUPPORT_READONLY writes). Only a Venue whose configured mode is CUSTOM has
   * a custom binding; READY and ACTIVE claim a working site, so they require
   * WEBSITE access, a recorded frontend identity and an active domain.
   * Each changed field is audited in the same transaction as the change.
   */
  async platformUpdate(
    actor: { platformUserId: string },
    venueId: string,
    body: Record<string, unknown>,
  ) {
    const hasKey = 'siteKey' in body;
    const hasStatus = 'status' in body;
    const hasNote = 'statusNote' in body;
    if (!hasKey && !hasStatus && !hasNote)
      throw new BadRequestException('Nothing to change');
    const siteKey = hasKey ? readSiteKey(body.siteKey) : undefined;
    const status = hasStatus ? readStatus(body.status) : undefined;
    const statusNote = hasNote ? readNote(body.statusNote) : undefined;

    await this.db.$transaction(async (tx) => {
      const venue = await tx.$queryRaw<
        { id: string }[]
      >`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      if (!venue.length) throw new NotFoundException('Venue not found');
      const config = await tx.venueWebsiteConfig.findUnique({
        where: { venueId },
        select: { mode: true },
      });
      if (config?.mode !== 'CUSTOM')
        throw new ConflictException(
          'Select CUSTOM as the website implementation first',
        );
      const before = await tx.customWebsiteBinding.findUnique({
        where: { venueId },
      });
      const next = {
        siteKey: siteKey === undefined ? (before?.siteKey ?? null) : siteKey,
        status: status ?? before?.status ?? CustomWebsiteStatus.SETUP_PENDING,
        statusNote:
          statusNote === undefined ? (before?.statusNote ?? null) : statusNote,
      };
      if (requiresReadiness(next.status)) {
        const [access, activeDomains] = await Promise.all([
          this.entitlements.websiteAccess(venueId),
          tx.venueDomain.count({ where: { venueId, status: 'ACTIVE' } }),
        ]);
        const readiness = customReadiness({
          entitled: access.entitled,
          mode: config.mode,
          siteKey: next.siteKey,
          activeDomains,
        });
        if (!readiness.complete)
          throw new ConflictException({
            message: `${next.status} requires Website access, a frontend identity and an active domain`,
            readiness: readiness.checks,
          });
      }
      await tx.customWebsiteBinding.upsert({
        where: { venueId },
        create: { venueId, ...next },
        update: next,
      });
      const events: Prisma.PlatformAuditEventCreateManyInput[] = [];
      if ((before?.siteKey ?? null) !== next.siteKey)
        events.push({
          platformUserId: actor.platformUserId,
          action: CustomWebsiteAuditAction.SITE_KEY_CHANGED,
          targetType: 'Venue',
          targetId: venueId,
          metadata: { from: before?.siteKey ?? null, to: next.siteKey },
        });
      if (
        (before?.status ?? 'NOT_CONFIGURED') !== next.status ||
        (before?.statusNote ?? null) !== next.statusNote
      )
        events.push({
          platformUserId: actor.platformUserId,
          action: CustomWebsiteAuditAction.STATUS_CHANGED,
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            from: before?.status ?? 'NOT_CONFIGURED',
            to: next.status,
            note: next.statusNote,
          },
        });
      if (events.length)
        await tx.platformAuditEvent.createMany({ data: events });
    });
    return this.platformView(venueId);
  }
}

function readStatus(value: unknown): CustomWebsiteStatus {
  const found = CUSTOM_WEBSITE_STATUSES.find((s) => s === value);
  if (!found)
    throw new BadRequestException(
      `status must be one of ${CUSTOM_WEBSITE_STATUSES.join(', ')}`,
    );
  return found;
}

function readNote(value: unknown): string | null {
  if (value === null || value === '') return null;
  if (typeof value !== 'string' || value.length > 500)
    throw new BadRequestException('statusNote must be at most 500 characters');
  return value.trim() || null;
}
