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
  emptyWebsiteContent,
  websiteContent,
  websiteMutation,
} from './website-content';

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
    const [row, access, domains] = await Promise.all([
      this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
      this.access.websiteAccess(venueId),
      this.db.venueDomain.findMany({
        where: { venueId, status: 'ACTIVE' },
        select: { hostname: true },
      }),
    ]);
    return {
      mode: access.configuredMode,
      entitled: access.entitled,
      status: row?.status ?? 'DRAFT',
      revision: row?.revision ?? 0,
      publishedRevision: row?.publishedRevision ?? null,
      publishedAt: row?.publishedAt ?? null,
      hasUnpublishedChanges:
        (row?.revision ?? 0) !== (row?.publishedRevision ?? 0),
      draft: row?.draft ?? emptyWebsiteContent,
      publishedSlug: row?.slug ?? null,
      baseDomain: this.config.get<string>('SAAS_WEBSITE_BASE_DOMAIN') ?? null,
      domains: domains.map((d) => d.hostname),
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
    const input = websiteMutation(body, true);
    await this.db.$transaction(async (tx) => {
      const row = await this.locked(tx, venueId, input.expectedRevision);
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
  async preview(venueId: string) {
    const row = this.requireSaas(
      await this.db.venueWebsiteConfig.findUnique({ where: { venueId } }),
    );
    return {
      schemaVersion: 1,
      mode: 'SAAS',
      preview: true,
      revision: row.revision,
      publishedAt: null,
      profile: await this.profile(venueId),
      content: row.draft ?? emptyWebsiteContent,
    };
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
        if (row.publishedRevision === row.revision) return;
        const content = websiteContent(row.draft);
        if (!content.heroTitle)
          throw new ConflictException('A hero title is required to publish');
        const hostname = `${content.slug}.${this.baseDomain()}`;
        const domain = await tx.venueDomain.findUnique({ where: { hostname } });
        if (
          domain &&
          (domain.venueId !== venueId || domain.status !== 'ACTIVE')
        )
          throw new ConflictException('Website address is unavailable');
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
  async bootstrap(headers: Record<string, string | string[] | undefined>) {
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
    const unavailable = () => new NotFoundException('Website unavailable');
    if (!resolved) throw unavailable();
    const venueId = resolved.tenant.venueId;
    const access = await this.access.websiteAccess(venueId);
    if (!access.entitled || access.effectiveMode === 'NONE')
      throw unavailable();
    if (access.effectiveMode === 'CUSTOM')
      return { schemaVersion: 1, mode: 'CUSTOM' };
    // Only published fields are selected: draft cannot enter this response.
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
      throw unavailable();
    return {
      schemaVersion: 1,
      mode: 'SAAS',
      preview: false,
      revision: row.publishedRevision,
      publishedAt: row.publishedAt,
      profile: await this.profile(venueId),
      content: row.published,
    };
  }
}
