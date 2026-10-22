import { ConfigService } from '@nestjs/config';
import { WebsiteCoreService } from './website-core.service';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteMenuService } from './website-menu.service';

describe('Website address availability', () => {
  const findUnique = jest.fn();
  const assigned = jest.fn();
  const core = new WebsiteCoreService(
    {
      venueDomain: { findUnique },
      venueWebsiteConfig: { findUnique: assigned },
    } as unknown as PrismaService,
    {} as VenueEntitlementsService,
    {} as WebsiteTenantService,
    new ConfigService({ SAAS_WEBSITE_BASE_DOMAIN: 'vynic.localhost' }),
    {} as WebsiteMenuService,
  );
  beforeEach(() => {
    findUnique.mockReset();
    assigned.mockReset().mockResolvedValue(null);
  });

  it('reports a free address under the configured base domain', async () => {
    findUnique.mockResolvedValue(null);
    await expect(core.addressAvailability('venue-a', 'tabla')).resolves.toEqual(
      { valid: true, hostname: 'tabla.vynic.localhost', available: true },
    );
    expect(findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { hostname: 'tabla.vynic.localhost' } }),
    );
  });

  it("treats the Venue's own active address as available", async () => {
    findUnique.mockResolvedValue({ venueId: 'venue-a', status: 'ACTIVE' });
    await expect(core.addressAvailability('venue-a', 'tabla')).resolves.toEqual(
      { valid: true, hostname: 'tabla.vynic.localhost', available: true },
    );
  });

  it('refuses a name another Venue retains as its assigned identity', async () => {
    findUnique.mockResolvedValue(null);
    assigned.mockResolvedValue({ venueId: 'venue-b' });
    await expect(core.addressAvailability('venue-a', 'tabla')).resolves.toEqual(
      { valid: true, hostname: 'tabla.vynic.localhost', available: false },
    );
  });

  it.each([
    { venueId: 'venue-b', status: 'ACTIVE' },
    { venueId: 'venue-a', status: 'DISABLED' },
  ])('refuses an address held elsewhere or disabled (%o)', async (domain) => {
    findUnique.mockResolvedValue(domain);
    await expect(core.addressAvailability('venue-a', 'tabla')).resolves.toEqual(
      { valid: true, hostname: 'tabla.vynic.localhost', available: false },
    );
  });

  it.each([
    'Tabla',
    '-tabla',
    'admin',
    'vynic',
    'dashboard',
    'a'.repeat(49),
    'ტაბლა',
  ])('rejects %s without querying domains', async (slug) => {
    await expect(core.addressAvailability('venue-a', slug)).resolves.toEqual({
      valid: false,
      available: false,
    });
    expect(findUnique).not.toHaveBeenCalled();
  });
});
