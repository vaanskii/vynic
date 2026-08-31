import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { PosAuthenticatedRequest } from '../auth/pos-auth-context';
import { REQUIRED_FEATURE_KEY } from './requires-feature.decorator';
import { VenueEntitlementsService } from './venue-entitlements.service';

/**
 * Denies a route when the authenticated Venue lacks the required feature.
 *
 * Deliberately applied to nothing in Step 5A. Manager and website requests do
 * not yet carry authoritative Venue identity, so enforcing there would either
 * be unsafe or would switch off parts of the live product before Manager Cloud
 * tenancy exists. This is the tested primitive that later phase will attach.
 *
 * It also has no business being on a sync route: entitlement must never gate
 * POS → Cloud synchronization.
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
      .getRequest<PosAuthenticatedRequest>();
    const venueId = request.posAuthContext?.venueId;
    if (!venueId) {
      throw new UnauthorizedException(
        'Feature access requires an authenticated venue',
      );
    }

    if (!(await this.entitlements.hasFeature(venueId, requiredFeature))) {
      throw new ForbiddenException(
        `This venue is not entitled to ${requiredFeature}`,
      );
    }
    return true;
  }
}
