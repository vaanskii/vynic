import { requestTenant } from './tenant-context';

describe('requestTenant', () => {
  it('reads the tenant a POS Device credential established', () => {
    expect(
      requestTenant({
        posAuthContext: { venueId: 'venue-a', organizationId: 'org-1' },
      }),
    ).toEqual({ venueId: 'venue-a', organizationId: 'org-1' });
  });

  it('reads the tenant an authenticated Manager session established', () => {
    expect(
      requestTenant({
        user: { venueId: 'venue-b', organizationId: 'org-2' },
      }),
    ).toEqual({ venueId: 'venue-b', organizationId: 'org-2' });
  });

  it('has no tenant for an unauthenticated request', () => {
    expect(requestTenant({})).toBeNull();
  });

  it('refuses a half-resolved principal rather than inventing the other half', () => {
    expect(requestTenant({ user: { venueId: 'venue-b' } })).toBeNull();
    expect(requestTenant({ user: { organizationId: 'org-2' } })).toBeNull();
  });
});
