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
  websiteSlug,
  websiteThemeKeys,
} from './website-content';
import { WebsiteMenuService } from './website-menu.service';
import { websiteState } from '../provisioning/website-provisioning';

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
    const [row, access, domains] = await Promise.all([
      this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
      this.access.websiteAccess(venueId),
      this.db.venueDomain.findMany({
        where: { venueId, status: 'ACTIVE' },
        select: { hostname: true },
      }),
    ]);
    return {
      mediaUploadAllowed:
        (await this.db.venueSubscription.findUnique({ where: { venueId } }))
          ?.status === 'ACTIVE',
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
    };
  }
  /**
   * Whether an address can be published for this Venue right now.
   *
   * Advisory only: the address is claimed atomically at publication, which
   * remains the authority if two restaurants race for the same name.
   */
  async addressAvailability(venueId: string, value: unknown) {
    let slug: string;
    try {
      slug = websiteSlug(value);
    } catch {
      return { valid: false, available: false };
    }
    const domain = await this.db.venueDomain.findUnique({
      where: { hostname: `${slug}.${this.baseDomain()}` },
      select: { venueId: true, status: true },
    });
    return {
      valid: true,
      available:
        !domain || (domain.venueId === venueId && domain.status === 'ACTIVE'),
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
        if (!content.heroTitle)
          throw new ConflictException('A hero title is required to publish');
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
    if (!resolved) throw new NotFoundException('Website unavailable');
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
      throw new NotFoundException('Website unavailable');
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

  private async payload(
    venueId: string,
    content: ReturnType<typeof readWebsiteContent>,
    state: {
      preview: boolean;
      revision: number | null;
      publishedAt: Date | null;
    },
  ) {
    return {
      schemaVersion: WEBSITE_SCHEMA_VERSION,
      mode: 'SAAS',
      preview: state.preview,
      revision: state.revision,
      publishedAt: state.publishedAt,
      profile: await this.profile(venueId),
      content,
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
    const venue = await this.profile(venueId);
    if (!content.showMenu)
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
