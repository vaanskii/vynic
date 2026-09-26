import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  NotFoundException,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { WebsiteCapabilityKey } from '@prisma/client';
import { WebsiteCapabilitiesService } from './website-capabilities.service';
import type { WebsiteTenantRequest } from './website-tenant-context';

const CAPABILITIES = 'website:capabilities';

/** The shared website capabilities a public route serves. */
export const RequiresWebsiteCapability = (...keys: WebsiteCapabilityKey[]) =>
  SetMetadata(CAPABILITIES, keys);

/**
 * Admits a public route only when the Venue the Host resolved to has a
 * launched website and every named capability is available: commercially
 * included and not switched off by the operator. WebsiteMode is not consulted
 * beyond launch (published SAAS, provisioned CUSTOM) — launched SAAS and
 * CUSTOM Venues with the same capabilities get the same answer.
 *
 * Must run after WebsiteTenantGuard. A package without the capability is 403
 * (like FeatureGuard); an operator-disabled one is 404, since the website
 * simply does not offer it.
 */
@Injectable()
export class WebsiteCapabilityGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly capabilities: WebsiteCapabilitiesService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const keys =
      this.reflector.getAllAndOverride<WebsiteCapabilityKey[]>(CAPABILITIES, [
        context.getHandler(),
        context.getClass(),
      ]) ?? [];
    const request = context.switchToHttp().getRequest<WebsiteTenantRequest>();
    const venueId = request.websiteContext?.tenant.venueId;
    if (!venueId)
      throw new Error(
        'WebsiteCapabilityGuard requires WebsiteTenantGuard first',
      );
    if (!(await this.capabilities.launched(venueId)))
      throw new NotFoundException('No website is live for this host');
    if (!keys.length) return true;
    const states = await this.capabilities.states(venueId);
    for (const key of keys) {
      const state = states.find((s) => s.key === key)!;
      if (!state.commercial)
        throw new ForbiddenException(`${state.label} is not included`);
      if (!state.enabled)
        throw new NotFoundException(
          `${state.label} is not offered by this website`,
        );
    }
    return true;
  }
}
