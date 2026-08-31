/**
 * The one definition of "which Venue is this request acting inside".
 *
 * Several authentication mechanisms produce it — a POS Device credential, a
 * Manager staff session — and they must all agree on its shape, so nothing
 * downstream needs to know which door a request came through.
 *
 *     POS Device auth   ─┐
 *                        ├─→ TenantContext ─→ tenant-scoped services
 *     Manager staff auth ─┘
 *
 * A tenant is always resolved from server-owned ownership. A venueId or
 * organizationId in a request body, query, or header is never authoritative.
 */
export interface TenantContext {
  venueId: string;
  organizationId: string;
}

/**
 * A request carrying whichever tenant its authentication established.
 *
 * `posAuthContext` is written by PosSyncGuard; `user` is written by
 * JwtStrategy for authenticated Manager staff. Both are server-controlled.
 */
export interface TenantAuthenticatedRequest {
  posAuthContext?: TenantContext;
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

  const { venueId, organizationId } = request.user ?? {};
  if (venueId && organizationId) return { venueId, organizationId };

  return null;
}
