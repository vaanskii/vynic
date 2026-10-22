import { createHash } from 'node:crypto';

/** Public correlation only. Host authority still comes from VenueDomain. */
export function websiteVenueIdentity(venueId: string): string {
  return createHash('sha256')
    .update('vynic-public-venue-v1\0')
    .update(venueId)
    .digest('hex');
}
