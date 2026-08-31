import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { WebsiteMode } from '@prisma/client';
import type { TenantContext } from '../../tenancy/tenant-context';

/**
 * Which restaurant a public website request is acting inside, and how that
 * restaurant's website is configured.
 *
 * Deliberately not PosAuthContext or ManagerAuthContext: a public visitor is
 * not authenticated staff and has no principal at all. What it shares with
 * them is the one thing that must be shared — the same `TenantContext` — so
 * nothing downstream has to know which door a request came through.
 *
 * `configuredMode` is what the Venue has stored. It is not permission: whether
 * the Venue may serve a website at all is the WEBSITE entitlement, enforced by
 * FeatureGuard, and the two are resolved together by
 * `VenueEntitlementsService.websiteAccess`.
 */
export interface WebsiteTenantContext {
  tenant: TenantContext;
  /** The normalized hostname that resolved this Venue. */
  hostname: string;
  configuredMode: WebsiteMode;
}

/**
 * A request whose Venue was resolved from its host by WebsiteTenantGuard.
 *
 * Written by the guard, never by a client: there is no body, query or header
 * field a caller can set to become another restaurant.
 */
export interface WebsiteTenantRequest {
  websiteTenant?: TenantContext;
  websiteContext?: WebsiteTenantContext;
}

function readWebsiteContext(context: ExecutionContext): WebsiteTenantContext {
  const request = context.switchToHttp().getRequest<WebsiteTenantRequest>();
  if (!request.websiteContext) {
    throw new Error('WebsiteTenantGuard did not resolve a venue for this host');
  }
  return request.websiteContext;
}

/** The Venue this public request resolved to. */
export const WebsiteTenant = createParamDecorator(
  (_data: unknown, context: ExecutionContext): TenantContext =>
    readWebsiteContext(context).tenant,
);

/** The full resolved website context, when a handler needs the host or mode. */
export const WebsiteContext = createParamDecorator(
  (_data: unknown, context: ExecutionContext): WebsiteTenantContext =>
    readWebsiteContext(context),
);
