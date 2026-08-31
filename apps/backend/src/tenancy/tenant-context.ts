/**
 * The one definition of "which Venue is this request acting inside".
 *
 * Several mechanisms produce it — a POS Device credential, a Manager staff
 * session, a public website host — and they must all agree on its shape, so
 * nothing downstream needs to know which door a request came through.
 *
 *     POS Device auth    ─┐
 *     Manager staff auth  ├─→ TenantContext ─→ tenant-scoped services
 *     Website host        ─┘
 *
 * A tenant is always resolved from server-owned ownership: a Device row, a
 * Staff row, a registered VenueDomain. A venueId or organizationId in a request
 * body, query, or client-chosen header is never authoritative.
 */
export interface TenantContext {
  venueId: string;
  organizationId: string;
}

/**
 * A request carrying whichever tenant its authentication or routing established.
 *
 * `posAuthContext` is written by PosSyncGuard; `websiteTenant` by
 * WebsiteTenantGuard from the registered host; `user` by JwtStrategy for
 * authenticated Manager staff. All three are server-controlled.
 *
 * `user` is checked last and only structurally, because the public website also
 * puts its own customer principal there — a WebsiteUser carries no Venue, so it
 * simply yields no tenant instead of being mistaken for one.
 */
export interface TenantAuthenticatedRequest {
  posAuthContext?: TenantContext;
  websiteTenant?: TenantContext;
  user?: Partial<TenantContext>;
}

/**
 * The authenticated tenant for a request, or null if none was established.
 *
 * Returns null rather than a default: a caller that cannot prove its tenant
 * must be denied, never quietly served the bootstrap Venue's data.
 */
export function requestTenant(
  request: TenantAuthenticatedRequest,
): TenantContext | null {
  if (request.posAuthContext) return request.posAuthContext;
  if (request.websiteTenant) return request.websiteTenant;

  const { venueId, organizationId } = request.user ?? {};
  if (venueId && organizationId) return { venueId, organizationId };

  return null;
}
