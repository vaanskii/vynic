import {
  CanActivate,
  ExecutionContext,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Request } from 'express';
import type { TenantAuthenticatedRequest } from '../../tenancy/tenant-context';
import type { WebsiteTenantRequest } from './website-tenant-context';
import { WebsiteTenantService } from './website-tenant.service';

/**
 * Establishes the Venue for a public website request before anything reads
 * restaurant data.
 *
 * It writes the tenant onto the request so FeatureGuard — which asks the same
 * `requestTenant()` question for every authentication path — can then check the
 * WEBSITE entitlement. Order matters: this guard must be listed first.
 *
 * An unresolvable host is a 404, not a 403: there is no website at that name,
 * and saying anything more would let a caller probe which hostnames are
 * registered.
 */
@Injectable()
export class WebsiteTenantGuard implements CanActivate {
  constructor(private readonly websiteTenant: WebsiteTenantService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<
        Request & WebsiteTenantRequest & TenantAuthenticatedRequest
      >();

    const resolved = await this.websiteTenant.resolveRequest(request);
    if (!resolved) {
      throw new NotFoundException('No website is configured for this host');
    }

    request.websiteContext = resolved;
    request.websiteTenant = resolved.tenant;
    return true;
  }
}
