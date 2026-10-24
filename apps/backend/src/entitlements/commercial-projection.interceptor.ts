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
import { withoutNonFiscal } from './non-fiscal-projection';
@Injectable()
export class CommercialProjectionInterceptor implements NestInterceptor {
  constructor(private readonly entitlements: VenueEntitlementsService) {}
  async intercept(context: ExecutionContext, next: CallHandler) {
    const tenant = requestTenant(context.switchToHttp().getRequest());
    const features = tenant
      ? await this.entitlements.effectiveFeatures(tenant.venueId)
      : [];
    return next.handle().pipe(
      map((value) => {
        const visible = features.includes(FeatureKeys.NON_FISCAL_CLOSE)
          ? value
          : withoutNonFiscal(value);
        return features.includes(FeatureKeys.PROFITABILITY)
          ? visible
          : withoutProfitability(visible);
      }),
    );
  }
}
