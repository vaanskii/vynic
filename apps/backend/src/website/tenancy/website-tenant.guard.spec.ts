import { ExecutionContext, NotFoundException } from '@nestjs/common';
import { WebsiteMode } from '@prisma/client';
import { WebsiteTenantGuard } from './website-tenant.guard';
import type { WebsiteTenantService } from './website-tenant.service';

function contextFor(request: Record<string, unknown>): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('WebsiteTenantGuard', () => {
  const resolved = {
    tenant: { venueId: 'venue-a', organizationId: 'org-1' },
    hostname: 'a.test',
    configuredMode: WebsiteMode.CUSTOM,
  };

  it('puts the resolved venue on the request for the entitlement check', async () => {
    const guard = new WebsiteTenantGuard({
      resolveRequest: () => Promise.resolve(resolved),
    } as unknown as WebsiteTenantService);
    const request: Record<string, unknown> = { headers: { host: 'a.test' } };

    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
    expect(request.websiteTenant).toEqual(resolved.tenant);
    expect(request.websiteContext).toEqual(resolved);
  });

  it('refuses a host that belongs to no venue', async () => {
    const guard = new WebsiteTenantGuard({
      resolveRequest: () => Promise.resolve(null),
    } as unknown as WebsiteTenantService);

    await expect(
      guard.canActivate(contextFor({ headers: { host: 'nobody.test' } })),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('never lets a request name its own venue', async () => {
    const guard = new WebsiteTenantGuard({
      resolveRequest: () => Promise.resolve(resolved),
    } as unknown as WebsiteTenantService);
    // A caller supplying venueId in the body, query or a header changes nothing:
    // the guard overwrites the request tenant with what the host resolved to.
    const request: Record<string, unknown> = {
      headers: { host: 'a.test', 'x-venue-id': 'venue-b' },
      body: { venueId: 'venue-b' },
      query: { venueId: 'venue-b' },
      websiteTenant: { venueId: 'venue-b', organizationId: 'org-2' },
    };

    await guard.canActivate(contextFor(request));
    expect(request.websiteTenant).toEqual(resolved.tenant);
  });
});
