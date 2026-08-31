import type { TenantContext } from './tenant-context';

/**
 * Prisma composite-key builders for the identities Step 4B1 made Venue-local.
 *
 * These replace the fixed-tenant helpers in legacy-manager-tenant.ts for every
 * caller that has an authenticated tenant. Taking the tenant as an argument is
 * the point: a call site physically cannot forget to scope itself.
 */
export function settingIdentity(tenant: TenantContext, key: string) {
  return { venueId_key: { venueId: tenant.venueId, key } };
}

export function orderIdentity(tenant: TenantContext, posOrderId: number) {
  return { venueId_posOrderId: { venueId: tenant.venueId, posOrderId } };
}

export function staffIdentity(tenant: TenantContext, username: string) {
  return { venueId_username: { venueId: tenant.venueId, username } };
}

export function quickOrderDraftIdentity(
  tenant: TenantContext,
  draftId: string,
) {
  return { venueId_draftId: { venueId: tenant.venueId, draftId } };
}
