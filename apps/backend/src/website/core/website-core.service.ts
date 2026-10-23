import {
  assignHostname,
  lockHostnames,
  requestableSlug,
  saasNameTaken,
} from '../provisioning/hostname';
import { validateMediaReferences } from './website-media';
import { requireCommercialFeature } from '../../entitlements/commercial-state';
import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, VenueWebsiteConfig } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { normalizeHostname, requestHostnames } from '../tenancy/website-host';
import {
  WEBSITE_SCHEMA_VERSION,
  emptyWebsiteContent,
  readWebsiteContent,
  websiteContent,
  websiteMutation,
  websiteThemeKeys,
} from './website-content';
import { WebsiteMenuService } from './website-menu.service';
import { websiteState } from '../provisioning/website-provisioning';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { VenuePublicProfileService } from './venue-public-profile.service';

// Public identity is live Venue profile data, without legal/account fields.
const publicProfile = {
  name: true,
  branchName: true,
  address: true,
  phone: true,
  timezone: true,
  currency: true,
} as const;
@Injectable()
export class WebsiteCoreService {
  constructor(
    private readonly db: PrismaService,
    private readonly access: VenueEntitlementsService,
    private readonly hosts: WebsiteTenantService,
    private readonly config: ConfigService,
    private readonly menu: WebsiteMenuService,
    // Injected by Nest; hand-built instances (scripts, specs) get the same
    // implementations over the same database.
    private readonly capabilities: WebsiteCapabilitiesService = new WebsiteCapabilitiesService(
      db,
      access,
    ),
    private readonly publicInfo: VenuePublicProfileService = new VenuePublicProfileService(
      db,
      capabilities,
    ),
  ) {}
  private baseDomain() {
    const raw = this.config.get<string>('SAAS_WEBSITE_BASE_DOMAIN');
    const host = normalizeHostname(raw);
    if (!raw || !host || raw !== host || !host.includes('.'))
      throw new ServiceUnavailableException(
        'SaaS website domain is not configured',
      );
    return host;
  }
  private async profile(venueId: string) {
    return this.db.venue.findUniqueOrThrow({
      where: { id: venueId },
      select: publicProfile,
    });
  }
  async settings(venueId: string) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    // Upgrade previously unassigned SaaS configurations once, under the same locks.
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      await requireCommercialFeature(tx, venueId, 'WEBSITE');
      await tx.$queryRaw`SELECT "venueId" FROM "pos"."VenueWebsiteConfig" WHERE "venueId"=${venueId} FOR UPDATE`;
      const current = await tx.venueWebsiteConfig.findUnique({
        where: { venueId },
      });
      if (current?.mode === 'SAAS' && !current.assignedSlug)
        await assignHostname(tx, venueId);
    });
    const [
      row,
      access,
      domains,
      subscription,
      pendingHostname,
      custom,
      shared,
      capabilities,
    ] = await Promise.all([
      this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
      this.access.websiteAccess(venueId),
      this.db.venueDomain.findMany({
        where: { venueId, status: 'ACTIVE' },
        select: { hostname: true },
      }),
      this.db.venueSubscription.findUnique({ where: { venueId } }),
      this.db.websiteHostnameRequest.findFirst({
        where: { venueId, status: 'PENDING' },
        select: { hostname: true, createdAt: true },
      }),
      this.db.customWebsiteBinding.findUnique({
        where: { venueId },
        select: { status: true },
      }),
      this.publicInfo.read(venueId),
      this.capabilities.states(venueId),
    ]);
    const base = this.config.get<string>('SAAS_WEBSITE_BASE_DOMAIN');
    return {
      // The server-owned SaaS address; the draft never chooses it.
      hostname:
        access.configuredMode === 'SAAS' && row?.assignedSlug && base
          ? `${row.assignedSlug}.${base}`
          : null,
      pendingHostnameRequest: pendingHostname,
      hostnameChangeAllowed: false,
      commercialStatus: subscription?.status ?? 'NO_PLAN',
      mediaUploadAllowed: subscription?.status === 'ACTIVE',
      schemaVersion: WEBSITE_SCHEMA_VERSION,
      themeKeys: [...websiteThemeKeys],
      mode: access.configuredMode,
      state: websiteState(access.entitled ? ['WEBSITE'] : [], {
        mode: access.configuredMode,
      }),
      entitled: access.entitled,
      status: row?.status ?? 'DRAFT',
      revision: row?.revision ?? 0,
      publishedRevision: row?.publishedRevision ?? null,
      publishedAt: row?.publishedAt ?? null,
      hasUnpublishedChanges:
        (row?.revision ?? 0) !== (row?.publishedRevision ?? 0),
      draft: row?.draft ? readWebsiteContent(row.draft) : emptyWebsiteContent,
      publishedSlug: row?.slug ?? null,
      baseDomain: this.config.get<string>('SAAS_WEBSITE_BASE_DOMAIN') ?? null,
      domains: domains.map((d) => d.hostname),
      // Read-only for owners: implementation, frontend and domains are
      // operator-managed for a CUSTOM site.
      custom:
        access.configuredMode === 'CUSTOM'
          ? { status: custom?.status ?? 'NOT_CONFIGURED' }
          : null,
      // Venue-owned and live in either mode: hours, contact, socials, gallery.
      shared,
      // The same capability answer Platform and the public routes use; the
      // Dashboard shows management pages from it, not from the mode.
      capabilities: capabilities.map((c) => ({
        key: c.key,
        label: c.label,
        built: c.built,
        available: c.available,
        ready: c.ready,
        live: c.live,
      })),
    };
  }

  /** Owner edit of the Venue's public information; live in either mode. */
  async saveShared(venueId: string, body: unknown, customerAccountId: string) {
    await this.publicInfo.save(venueId, body, customerAccountId);
    return this.settings(venueId);
  }
  /**
   * Whether an address could be requested for this Venue right now.
   *
   * Advisory only: Platform approval re-checks availability under the
   * hostname lock, which remains the authority if two restaurants race.
   */
  async addressAvailability(venueId: string, value: unknown) {
    let slug: string;
    try {
      slug = requestableSlug(value);
    } catch {
      return { valid: false, available: false };
    }
    const hostname = `${slug}.${this.baseDomain()}`;
    const [taken, own] = await Promise.all([
      saasNameTaken(this.db, slug, hostname, venueId),
      this.db.venueDomain.findUnique({
        where: { hostname },
        select: { venueId: true, status: true },
      }),
    ]);
    return {
      valid: true,
      hostname,
      available:
        !taken &&
        (!own || (own.venueId === venueId && own.status === 'ACTIVE')),
    };
  }
  private requireSaas(row: VenueWebsiteConfig | null) {
    if (!row || row.mode !== 'SAAS')
      throw new ForbiddenException(
        'Generic website editing requires SAAS mode',
      );
    return row;
  }
  private async locked(
    tx: Prisma.TransactionClient,
    venueId: string,
    expected: number,
  ) {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
    await requireCommercialFeature(tx, venueId, 'WEBSITE');
    // Also serializes with Platform mode changes.
    await tx.$queryRaw`SELECT "venueId" FROM "pos"."VenueWebsiteConfig" WHERE "venueId" = ${venueId} FOR UPDATE`;
    const row = this.requireSaas(
      await tx.venueWebsiteConfig.findUnique({ where: { venueId } }),
    );
    if (row.revision !== expected)
      throw new ConflictException(
        'Website changed. Reload before saving or publishing.',
      );
    return row;
  }
  async save(venueId: string, body: unknown, customerAccountId: string) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const input = websiteMutation(body, true);
    await this.db.$transaction(async (tx) => {
      const row = await this.locked(tx, venueId, input.expectedRevision);
      if (!row.assignedSlug || input.content?.slug !== row.assignedSlug)
        throw new ForbiddenException(
          'Website address changes require Platform approval',
        );
      await validateMediaReferences(tx, venueId, input.content, [
        row.draft,
        row.published,
      ]);
      await tx.venueWebsiteConfig.update({
        where: { venueId },
        data: {
          draft: input.content as unknown as Prisma.InputJsonValue,
          revision: row.revision + 1,
        },
      });
      await this.audit(
        tx,
        venueId,
        customerAccountId,
        'website.draft_saved',
        row.revision + 1,
      );
    });
    return this.settings(venueId);
  }

  /**
   * The draft rendered exactly as publication would render it.
   *
   * Same builder as the public payload, so owner preview cannot drift into a
   * flattering approximation of what Publish will actually produce.
   */
  async preview(venueId: string) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const row = this.requireSaas(
      await this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
    );
    return this.payload(venueId, readWebsiteContent(row.draft), {
      preview: true,
      revision: row.revision,
      publishedAt: null,
    });
  }

  /** Draft preview redeemed through a preview token rather than a session. */
  async previewBootstrap(venueId: string) {
    const venue = await this.db.venue.findUnique({
      where: { id: venueId },
      select: { status: true },
    });
    if (venue?.status !== 'ACTIVE')
      throw new NotFoundException('Website unavailable');
    return this.preview(venueId);
  }

  /** The menu belonging to a draft preview, hidden items already removed. */
  async previewMenu(venueId: string) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const row = this.requireSaas(
      await this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
    );
    return this.menuPayload(venueId, readWebsiteContent(row.draft));
  }
  async publish(venueId: string, body: unknown, customerAccountId: string) {
    const { expectedRevision } = websiteMutation(body, false);
    if (!(await this.access.hasFeature(venueId, 'WEBSITE')))
      throw new ForbiddenException('Website access is disabled');
    try {
      await this.db.$transaction(async (tx) => {
        const row = await this.locked(tx, venueId, expectedRevision);
        const venue = await tx.venue.findUniqueOrThrow({
          where: { id: venueId },
          select: { status: true },
        });
        if (venue.status !== 'ACTIVE')
          throw new ForbiddenException('Restaurant is inactive');
        if (!row.draft || !row.revision)
          throw new ConflictException('Save a draft before publishing');
        const content = websiteContent(readWebsiteContent(row.draft));
        if (!row.assignedSlug || content.slug !== row.assignedSlug)
          throw new ForbiddenException(
            'Website address changes require Platform approval',
          );
        if (!content.heroTitle)
          throw new ConflictException('A hero title is required to publish');
        await lockHostnames(tx);
        const hostname = `${content.slug}.${this.baseDomain()}`;
        const domain = await tx.venueDomain.findUnique({ where: { hostname } });
        if (
          domain &&
          (domain.venueId !== venueId || domain.status !== 'ACTIVE')
        )
          throw new ConflictException('Website address is unavailable');
        if (domain && row.publishedRevision === row.revision) return;
        if (!domain)
          await tx.venueDomain.create({ data: { venueId, hostname } });
        await tx.venueWebsiteConfig.update({
          where: { venueId },
          data: {
            published: content as unknown as Prisma.InputJsonValue,
            publishedRevision: row.revision,
            publishedAt: new Date(),
            status: 'PUBLISHED',
            slug: content.slug,
          },
        });
        await this.audit(
          tx,
          venueId,
          customerAccountId,
          'website.published',
          row.revision,
        );
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      )
        throw new ConflictException('Website address is unavailable');
      throw error;
    }
    return this.settings(venueId);
  }
  private async audit(
    tx: Prisma.TransactionClient,
    venueId: string,
    customerAccountId: string,
    action: string,
    revision: number,
  ) {
    await tx.customerAuditEvent.create({
      data: {
        customerAccountId,
        action,
        targetType: 'VenueWebsiteConfig',
        targetId: venueId,
        metadata: { revision },
      },
    });
  }

  /**
   * The Venue a public request belongs to, from its host alone.
   *
   * Shared by every public generic route so bootstrap and menu can never
   * disagree about which restaurant is being served, and so a client-supplied
   * Venue id has nowhere to enter.
   */
  private async resolvePublicVenue(
    headers: Record<string, string | string[] | undefined>,
  ) {
    const trusted = ['1', 'true'].includes(
      (this.config.get<string>('TRUST_PROXY_HOST') ?? '').trim().toLowerCase(),
    );
    // No local default Venue or fallback to another registered header.
    const authoritative =
      trusted && headers['x-forwarded-host'] !== undefined
        ? headers['x-forwarded-host']
        : headers.host;
    const host = requestHostnames(
      { host: authoritative },
      { trustForwardedHost: false },
    )[0];
    const resolved = host ? await this.hosts.resolveByHostname(host) : null;
    if (!resolved)
      throw new NotFoundException({
        code: 'WEBSITE_NOT_FOUND',
        message: 'Website unavailable',
      });
    const venueId = resolved.tenant.venueId;
    const access = await this.access.websiteAccess(venueId);
    if (!access.entitled || access.effectiveMode === 'NONE')
      throw new NotFoundException('Website unavailable');
    return { venueId, mode: access.effectiveMode };
  }

  /**
   * The published row, or nothing at all.
   *
   * Only published columns are selected, so a draft has no path into a public
   * response even if a future caller forgets to check the status itself.
   */
  private async publishedRow(venueId: string) {
    const row = await this.db.venueWebsiteConfig.findUnique({
      where: { venueId },
      select: {
        mode: true,
        status: true,
        published: true,
        publishedRevision: true,
        publishedAt: true,
      },
    });
    if (row?.mode !== 'SAAS' || row.status !== 'PUBLISHED' || !row.published)
      throw new NotFoundException({
        code: 'WEBSITE_NOT_PUBLISHED',
        message: 'Website unavailable',
      });
    return row;
  }
  async bootstrap(headers: Record<string, string | string[] | undefined>) {
    const { venueId, mode } = await this.resolvePublicVenue(headers);
    if (mode === 'CUSTOM')
      return { schemaVersion: WEBSITE_SCHEMA_VERSION, mode: 'CUSTOM' };
    const row = await this.publishedRow(venueId);
    return this.payload(venueId, readWebsiteContent(row.published), {
      preview: false,
      revision: row.publishedRevision,
      publishedAt: row.publishedAt,
    });
  }

  /** The published menu for whichever restaurant owns the requested host. */
  async publicMenu(headers: Record<string, string | string[] | undefined>) {
    const { venueId, mode } = await this.resolvePublicVenue(headers);
    if (mode === 'CUSTOM') throw new NotFoundException('Website unavailable');
    const row = await this.publishedRow(venueId);
    return this.menuPayload(venueId, readWebsiteContent(row.published));
  }

  /**
   * The generic renderer's payload. Its `content` keeps the shape it has
   * always had: the page document plus the Venue's public information
   * (hours, contact, socials, gallery), projected live from the shared rows.
   */
  private async payload(
    venueId: string,
    content: ReturnType<typeof readWebsiteContent>,
    state: {
      preview: boolean;
      revision: number | null;
      publishedAt: Date | null;
    },
  ) {
    const [profile, info] = await Promise.all([
      this.profile(venueId),
      this.publicInfo.publicInfo(venueId),
    ]);
    return {
      schemaVersion: WEBSITE_SCHEMA_VERSION,
      mode: 'SAAS',
      preview: state.preview,
      revision: state.revision,
      publishedAt: state.publishedAt,
      profile,
      content: { ...content, ...info },
    };
  }

  /**
   * A menu response, including the owner's decision not to show one.
   *
   * `showMenu: false` answers with an explicitly empty menu instead of 404, so
   * the frontend can tell "this restaurant does not publish a menu" apart from
   * "this host has no website".
   */
  private async menuPayload(
    venueId: string,
    content: ReturnType<typeof readWebsiteContent>,
  ) {
    const [venue, menuAvailable] = await Promise.all([
      this.profile(venueId),
      this.capabilities.isAvailable(venueId, 'MENU'),
    ]);
    if (!content.showMenu || !menuAvailable)
      return {
        schemaVersion: WEBSITE_SCHEMA_VERSION,
        currency: venue.currency,
        enabled: false,
        categories: [],
      };
    const { categories } = await this.menu.publicMenu(venueId);
    return {
      schemaVersion: WEBSITE_SCHEMA_VERSION,
      currency: venue.currency,
      enabled: true,
      categories,
    };
  }
}
