import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { map } from 'rxjs';
import { requestTenant } from '../tenancy/tenant-context';
import { VenueEntitlementsService } from './venue-entitlements.service';
import { FeatureKeys } from './feature-keys';
import { withoutProfitability } from './commercial-projection';
@Injectable()
export class CommercialProjectionInterceptor implements NestInterceptor {
  constructor(private readonly entitlements: VenueEntitlementsService) {}
  async intercept(context: ExecutionContext, next: CallHandler) {
    const tenant = requestTenant(context.switchToHttp().getRequest());
    const features = tenant
      ? await this.entitlements.effectiveFeatures(tenant.venueId)
      : [];
    return next
      .handle()
      .pipe(
        map((value) =>
          features.includes(FeatureKeys.PROFITABILITY)
            ? value
            : withoutProfitability(value),
        ),
      );
  }
}
