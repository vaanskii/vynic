import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { VenueDomainStatus, VenueStatus, WebsiteMode } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service';
import type { WebsiteTenantContext } from './website-tenant-context';
import {
  isLocalDevelopmentHost,
  normalizeHostname,
  requestHostnames,
} from './website-host';

/**
 * The hostname the bootstrap Venue is registered under by the Step 4B2B
 * migration. `.localhost` is reserved (RFC 6761), so this can never collide
 * with a real domain, and the repository holds no evidence of the production
 * hostname — registering that is a deployment step.
 */
export const BOOTSTRAP_WEBSITE_HOST = 'vankisi.localhost';

/**
 * Resolves a public request to the restaurant that owns the host it arrived on.
 *
 *     Host / X-Forwarded-Host → VenueDomain → Venue → Organization
 *
 * Both website implementations share this boundary. The custom Vankisi site and
 * a future generic SaaS frontend differ in how they are *built and served*, not
 * in how their Venue is established: neither may pick a tenant, and neither is
 * special-cased here.
 *
 * Unknown, disabled and malformed hosts all resolve to nothing. There is no
 * default Venue in production — a request that cannot prove which restaurant it
 * belongs to is served none.
 */
@Injectable()
export class WebsiteTenantService {
  private readonly logger = new Logger(WebsiteTenantService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** True when this process sits behind a proxy allowed to rewrite the host. */
  private get trustsForwardedHost(): boolean {
    const raw = (this.config.get<string>('TRUST_PROXY_HOST') ?? '')
      .trim()
      .toLowerCase();
    return raw === '1' || raw === 'true';
  }

  private get isProduction(): boolean {
    return this.config.get<string>('NODE_ENV') === 'production';
  }

  /**
   * The Venue registered for a hostname, or null.
   *
   * A DISABLED domain resolves to nothing while keeping the hostname reserved,
   * and a DISABLED Venue stops serving its site without the domain having to be
   * unregistered.
   */
  async resolveByHostname(
    rawHostname: string,
  ): Promise<WebsiteTenantContext | null> {
    const hostname = normalizeHostname(rawHostname);
    if (!hostname) return null;

    const domain = await this.prisma.venueDomain.findUnique({
      where: { hostname },
      select: {
        hostname: true,
        status: true,
        venue: {
          select: {
            id: true,
            organizationId: true,
            status: true,
            websiteConfig: { select: { mode: true } },
          },
        },
      },
    });

    if (!domain || domain.status !== VenueDomainStatus.ACTIVE) return null;
    if (domain.venue.status !== VenueStatus.ACTIVE) return null;

    return {
      tenant: {
        venueId: domain.venue.id,
        organizationId: domain.venue.organizationId,
      },
      hostname: domain.hostname,
      configuredMode: domain.venue.websiteConfig?.mode ?? WebsiteMode.NONE,
    };
  }

  /**
   * The Venue for an incoming request, from its host alone.
   *
   * The development fallback below exists because local work happens on
   * `localhost`, a LAN address or a loopback literal, none of which is a
   * registered domain. It is transitional, it is gated on NODE_ENV, and it
   * applies only to addresses that cannot exist as public hostnames — so
   * production still fails closed on an unknown host.
   */
  async resolveRequest(request: {
    headers: Record<string, string | string[] | undefined>;
  }): Promise<WebsiteTenantContext | null> {
    const candidates = requestHostnames(request.headers, {
      trustForwardedHost: this.trustsForwardedHost,
    });

    for (const hostname of candidates) {
      const resolved = await this.resolveByHostname(hostname);
      if (resolved) return resolved;
    }

    if (this.isProduction) return null;
    if (!candidates.some(isLocalDevelopmentHost)) return null;

    const developmentHost =
      normalizeHostname(this.config.get<string>('WEBSITE_DEV_HOST')) ??
      BOOTSTRAP_WEBSITE_HOST;
    const resolved = await this.resolveByHostname(developmentHost);
    if (resolved) {
      this.logger.debug(
        `Development host ${candidates[0]} resolved via ${developmentHost}`,
      );
    }
    return resolved;
  }
}
