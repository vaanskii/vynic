import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import {
  requestTenant,
  type TenantAuthenticatedRequest,
} from '../tenancy/tenant-context';
import { REQUIRED_FEATURE_KEY } from './requires-feature.decorator';
import { VenueEntitlementsService } from './venue-entitlements.service';

/**
 * Denies a route when the authenticated Venue lacks the required feature.
 *
 * The tenant comes from whichever mechanism established one — a POS Device
 * credential, an authenticated Manager staff session, or the registered host a
 * public website request arrived on. Step 4B2A attached this to the Manager
 * product API and Step 4B2B to the public website product API; both now carry
 * an authoritative Venue.
 *
 * It has no business being on a sync route: entitlement must never gate
 * POS → Cloud synchronization. It is also absent from Device authentication and
 * from the payment provider's callback, which resolves its Venue from the
 * booking record rather than from a request header.
 *
 * A route with no @RequiresFeature passes through untouched, so adding the
 * guard to a controller cannot change the behavior of its other handlers.
 * Where a feature *is* required, it fails closed: no authenticated tenant
 * means denied, never allowed by default.
 */
@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly entitlements: VenueEntitlementsService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredFeature = this.reflector.getAllAndOverride<string>(
      REQUIRED_FEATURE_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!requiredFeature) return true;

    const request = context
      .switchToHttp()
      .getRequest<TenantAuthenticatedRequest>();
    const tenant = requestTenant(request);
    if (!tenant) {
      throw new UnauthorizedException(
        'Feature access requires an authenticated venue',
      );
    }

    if (
      !(await this.entitlements.hasFeature(tenant.venueId, requiredFeature))
    ) {
      throw new ForbiddenException(
        `This venue is not entitled to ${requiredFeature}`,
      );
    }
    return true;
  }
}
