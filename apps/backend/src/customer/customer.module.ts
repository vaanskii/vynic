import { RestaurantFoundationService } from './restaurant-foundation.service';
import {
  CustomerCatalogController,
  DeviceFoundationController,
} from './restaurant-foundation.controller';
import { OwnerInvitationsService } from './owner-invitations.service';
import {
  PlatformOwnerInvitationsController,
  CustomerOwnerInvitationsController,
} from './owner-invitations.controller';
import { WebsiteCoreModule } from '../website/core/website-core.module';
import { CustomerWebsiteController } from './customer-website.controller';
import { PaymentIntegrationsModule } from '../payment-integrations/payment-integrations.module';
import {
  CustomerPaymentsController,
  PlatformPaymentsController,
} from './customer-payments.controller';
import {
  ManagerVenueProfileController,
  DeviceVenueProfileController,
} from '../venue-profile/venue-profile.controller';
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PlatformModule } from '../platform/platform.module';
import { EdgeTransportModule } from '../edge/edge-transport.module';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { CustomerAuth, CustomerGuard } from './customer-auth';
import { CustomerService } from './customer.service';
import {
  CustomerAuthController,
  CustomerController,
  PlatformOnboardingController,
  DeviceRuntimeConfigController,
} from './customer.controller';
@Module({
  imports: [
    WebsiteCoreModule,
    PaymentIntegrationsModule,
    AuthModule,
    PlatformModule,
    EdgeTransportModule,
    EntitlementsModule,
  ],
  providers: [
    RestaurantFoundationService,
    OwnerInvitationsService,
    CustomerAuth,
    CustomerGuard,
    CustomerService,
    EnrollmentRateLimiter,
    EdgeDeviceGuard,
  ],
  controllers: [
    CustomerCatalogController,
    DeviceFoundationController,
    PlatformOwnerInvitationsController,
    CustomerOwnerInvitationsController,
    CustomerWebsiteController,
    CustomerPaymentsController,
    PlatformPaymentsController,
    ManagerVenueProfileController,
    DeviceVenueProfileController,
    CustomerAuthController,
    CustomerController,
    PlatformOnboardingController,
    DeviceRuntimeConfigController,
  ],
})
export class CustomerModule {}
