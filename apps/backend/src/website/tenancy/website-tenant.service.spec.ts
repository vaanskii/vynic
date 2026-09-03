import { VenueDomainStatus, VenueStatus, WebsiteMode } from '@prisma/client';
import { WebsiteTenantService } from './website-tenant.service';

type DomainRow = {
  hostname: string;
  status: VenueDomainStatus;
  venue: {
    id: string;
    organizationId: string;
    status: VenueStatus;
    websiteConfig: { mode: WebsiteMode } | null;
  };
};

function makeService(
  rows: Record<string, DomainRow>,
  env: Record<string, string | undefined> = {},
) {
  const findUnique = jest.fn(
    ({ where }: { where: { hostname: string } }) =>
      Promise.resolve(
        rows[where.hostname] ?? null,
      ) as Promise<DomainRow | null>,
  );
  const prisma = { venueDomain: { findUnique } } as never;
  const config = { get: (key: string) => env[key] } as never;
  return { service: new WebsiteTenantService(prisma, config), findUnique };
}

function domain(
  hostname: string,
  venueId: string,
  overrides: Partial<DomainRow> = {},
): DomainRow {
  return {
    hostname,
    status: VenueDomainStatus.ACTIVE,
    venue: {
      id: venueId,
      organizationId: 'org-1',
      status: VenueStatus.ACTIVE,
      websiteConfig: { mode: WebsiteMode.CUSTOM },
    },
    ...overrides,
  };
}

describe('WebsiteTenantService.resolveByHostname', () => {
  it('resolves a registered host to its venue and organization', async () => {
    const { service } = makeService({ 'a.test': domain('a.test', 'venue-a') });

    await expect(service.resolveByHostname('A.test:443')).resolves.toEqual({
      tenant: { venueId: 'venue-a', organizationId: 'org-1' },
      hostname: 'a.test',
      configuredMode: WebsiteMode.CUSTOM,
    });
  });

  it('resolves nothing for an unregistered host', async () => {
    const { service } = makeService({ 'a.test': domain('a.test', 'venue-a') });
    await expect(service.resolveByHostname('b.test')).resolves.toBeNull();
  });

  it('never queries for a malformed host', async () => {
    const { service, findUnique } = makeService({});
    await expect(
      service.resolveByHostname('https://a.test'),
    ).resolves.toBeNull();
    expect(findUnique).not.toHaveBeenCalled();
  });

  it('stops serving a disabled domain while keeping the name reserved', async () => {
    const { service } = makeService({
      'a.test': domain('a.test', 'venue-a', {
        status: VenueDomainStatus.DISABLED,
      }),
    });
    await expect(service.resolveByHostname('a.test')).resolves.toBeNull();
  });

  it('stops serving a disabled venue', async () => {
    const row = domain('a.test', 'venue-a');
    row.venue.status = VenueStatus.DISABLED;
    const { service } = makeService({ 'a.test': row });
    await expect(service.resolveByHostname('a.test')).resolves.toBeNull();
  });

  it('reports NONE when the venue has no website configuration', async () => {
    const row = domain('a.test', 'venue-a');
    row.venue.websiteConfig = null;
    const { service } = makeService({ 'a.test': row });
    await expect(service.resolveByHostname('a.test')).resolves.toMatchObject({
      configuredMode: WebsiteMode.NONE,
    });
  });
});

describe('WebsiteTenantService.resolveRequest', () => {
  const rows = {
    'a.test': domain('a.test', 'venue-a'),
    'vankisi.localhost': domain('vankisi.localhost', 'venue-bootstrap'),
  };

  it('resolves the venue that owns the Host header', async () => {
    const { service } = makeService(rows, { NODE_ENV: 'production' });
    await expect(
      service.resolveRequest({ headers: { host: 'a.test' } }),
    ).resolves.toMatchObject({ tenant: { venueId: 'venue-a' } });
  });

  it('ignores X-Forwarded-Host unless a proxy is trusted', async () => {
    const { service } = makeService(rows, { NODE_ENV: 'production' });
    await expect(
      service.resolveRequest({
        headers: { host: 'b.test', 'x-forwarded-host': 'a.test' },
      }),
    ).resolves.toBeNull();

    const trusted = makeService(rows, {
      NODE_ENV: 'production',
      TRUST_PROXY_HOST: 'true',
    });
    await expect(
      trusted.service.resolveRequest({
        headers: { host: 'b.test', 'x-forwarded-host': 'a.test' },
      }),
    ).resolves.toMatchObject({ tenant: { venueId: 'venue-a' } });
  });

  it('fails closed on an unknown host in production, localhost included', async () => {
    const { service } = makeService(rows, { NODE_ENV: 'production' });
    await expect(
      service.resolveRequest({ headers: { host: 'unknown.test' } }),
    ).resolves.toBeNull();
    await expect(
      service.resolveRequest({ headers: { host: 'localhost:3000' } }),
    ).resolves.toBeNull();
  });

  it('falls back to the bootstrap host for local development only', async () => {
    const { service } = makeService(rows, { NODE_ENV: 'development' });
    await expect(
      service.resolveRequest({ headers: { host: 'localhost:5173' } }),
    ).resolves.toMatchObject({ tenant: { venueId: 'venue-bootstrap' } });
    await expect(
      service.resolveRequest({ headers: { host: '192.168.1.20:5173' } }),
    ).resolves.toMatchObject({ tenant: { venueId: 'venue-bootstrap' } });
  });

  it('does not apply the development fallback to a public host', async () => {
    const { service } = makeService(rows, { NODE_ENV: 'development' });
    await expect(
      service.resolveRequest({ headers: { host: 'unknown.test' } }),
    ).resolves.toBeNull();
  });

  it('lets the development fallback host be configured', async () => {
    const { service } = makeService(rows, {
      NODE_ENV: 'development',
      WEBSITE_DEV_HOST: 'a.test',
    });
    await expect(
      service.resolveRequest({ headers: { host: 'localhost' } }),
    ).resolves.toMatchObject({ tenant: { venueId: 'venue-a' } });
  });
});
