import {
  BOOTSTRAP_ORGANIZATION_ID,
  BOOTSTRAP_VENUE_ID,
} from '../auth/legacy-pos-tenant.service';
import type { TenantContext } from '../auth/pos-auth-context';

/**
 * Transitional server-side tenant for Manager/mobile and website reads.
 * These clients do not yet carry authoritative Venue identity, so Step 4B1
 * preserves the existing restaurant by pinning them to the bootstrap Venue.
 */
export const LEGACY_MANAGER_TENANT: TenantContext = Object.freeze({
  venueId: BOOTSTRAP_VENUE_ID,
  organizationId: BOOTSTRAP_ORGANIZATION_ID,
});

export function legacySettingIdentity(key: string) {
  return {
    venueId_key: { venueId: LEGACY_MANAGER_TENANT.venueId, key },
  };
}

export function legacyOrderIdentity(posOrderId: number) {
  return {
    venueId_posOrderId: {
      venueId: LEGACY_MANAGER_TENANT.venueId,
      posOrderId,
    },
  };
}

export function legacyStaffIdentity(username: string) {
  return {
    venueId_username: {
      venueId: LEGACY_MANAGER_TENANT.venueId,
      username,
    },
  };
}
