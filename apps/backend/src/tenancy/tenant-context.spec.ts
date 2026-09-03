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

  it('reads the tenant a website host resolved', () => {
    expect(
      requestTenant({
        websiteTenant: { venueId: 'venue-c', organizationId: 'org-3' },
      }),
    ).toEqual({ venueId: 'venue-c', organizationId: 'org-3' });
  });

  it('ignores a website customer principal, which owns no venue', () => {
    // WebsiteAuthGuard puts a WebsiteUser on `user`; it is a global customer
    // identity and must never be mistaken for a tenant.
    expect(
      requestTenant({
        user: { id: 'customer-1', email: 'guest@example.com' } as never,
      }),
    ).toBeNull();
  });

  it('has no tenant for an unauthenticated request', () => {
    expect(requestTenant({})).toBeNull();
  });

  it('refuses a half-resolved principal rather than inventing the other half', () => {
    expect(requestTenant({ user: { venueId: 'venue-b' } })).toBeNull();
    expect(requestTenant({ user: { organizationId: 'org-2' } })).toBeNull();
  });
});
