import { MailModule } from '../mail/mail.module';
import { InstallerWorkerGatewayController } from './installer-worker-gateway.controller';
import { CustomerWebsitePaymentReviewsController } from './customer-website-payment-reviews.controller';
import { InstallerDownloadsService } from './installer-downloads.service';
import {
  PlatformInstallerDownloadsController,
  CustomerInstallerDownloadsController,
  InstallerDownloadFileController,
} from './installer-downloads.controller';
import { MenuClientGuard } from '../menu-catalog/menu-client.guard';
import { MenuRolloutService } from '../menu-catalog/menu-rollout.service';
import {
  CustomerMenuRolloutController,
  DeviceMenuClientController,
} from '../menu-catalog/menu-rollout.controller';
import {
  OnboardingRequestsService,
  PublicAccessRequestsController,
  PlatformAccessRequestsController,
  CustomerTrialRequestsController,
} from './onboarding-requests';
import { RestaurantFoundationService } from './restaurant-foundation.service';
import {
  CustomerCatalogController,
  DeviceFoundationController,
  DeviceMenuController,
} from './restaurant-foundation.controller';
import { MenuCatalogService } from '../menu-catalog/menu-catalog.service';
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
    MailModule,
    WebsiteCoreModule,
    PaymentIntegrationsModule,
    AuthModule,
    PlatformModule,
    EdgeTransportModule,
    EntitlementsModule,
  ],
  providers: [
    InstallerDownloadsService,
    OnboardingRequestsService,
    RestaurantFoundationService,
    MenuClientGuard,
    MenuRolloutService,
    MenuCatalogService,
    OwnerInvitationsService,
    CustomerAuth,
    CustomerGuard,
    CustomerService,
    EnrollmentRateLimiter,
    EdgeDeviceGuard,
  ],
  controllers: [
    InstallerWorkerGatewayController,
    PlatformInstallerDownloadsController,
    CustomerInstallerDownloadsController,
    InstallerDownloadFileController,
    CustomerWebsitePaymentReviewsController,
    PublicAccessRequestsController,
    PlatformAccessRequestsController,
    CustomerTrialRequestsController,
    CustomerMenuRolloutController,
    DeviceMenuClientController,
    CustomerCatalogController,
    DeviceFoundationController,
    DeviceMenuController,
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
