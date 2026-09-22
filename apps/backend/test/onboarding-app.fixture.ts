import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../src/prisma.service';
import { CustomerAuth } from '../src/customer/customer-auth';
import { CustomerService } from '../src/customer/customer.service';
import {
  CustomerAuthController,
  CustomerController,
  PlatformOnboardingController,
} from '../src/customer/customer.controller';
import { OwnerInvitationsService } from '../src/customer/owner-invitations.service';
import {
  CustomerOwnerInvitationsController,
  PlatformOwnerInvitationsController,
} from '../src/customer/owner-invitations.controller';
import { CustomerWebsiteController } from '../src/customer/customer-website.controller';
import {
  CustomerPaymentsController,
  PlatformPaymentsController,
} from '../src/customer/customer-payments.controller';
import { PaymentIntegrationsService } from '../src/payment-integrations/payment-integrations.service';
import { PlatformAuthService } from '../src/platform/platform-auth.service';
import { PlatformAuthController } from '../src/platform/platform-auth.controller';
import { PlatformCatalogController } from '../src/platform/platform-catalog.controller';
import { PlatformOrganizationsController } from '../src/platform/platform-organizations.controller';
import { PlatformVenuesController } from '../src/platform/platform-venues.controller';
import { PlatformCommercialController } from '../src/platform/platform-commercial.controller';
import { PlatformDirectoryService } from '../src/platform/platform-directory.service';
import { PlatformVenueConfigService } from '../src/platform/platform-venue-config.service';
import { PlatformDeviceService } from '../src/platform/platform-device.service';
import { PlatformCommercialService } from '../src/platform/platform-commercial.service';
import { PlatformAuditService } from '../src/platform/platform-audit.service';
import { StaffPinVault } from '../src/auth/staff-pin-vault.service';
import { DeviceCredentialService } from '../src/auth/device-credential.service';
import { DeviceEnrollmentService } from '../src/edge/device-enrollment.service';
import { EdgeCommandService } from '../src/edge/edge-command.service';
import { EnrollmentRateLimiter } from '../src/edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../src/entitlements/venue-entitlements.service';
import { WebsiteCoreService } from '../src/website/core/website-core.service';
import { WebsiteCoreController } from '../src/website/core/website-core.controller';
import { WebsiteMenuService } from '../src/website/core/website-menu.service';
import { WebsitePreviewTokens } from '../src/website/core/website-preview';
import { WebsiteTenantService } from '../src/website/tenancy/website-tenant.service';

// Explicit dependency graph: real services, no operational workers, LAN calls or bank clients.
export async function onboardingApp(db: PrismaService) {
  const config = new ConfigService({
    PLATFORM_JWT_SECRET: process.env.JWT_SECRET,
    SAAS_WEBSITE_BASE_DOMAIN: 'vynic.localhost',
    SAAS_WEBSITE_PREVIEW_ORIGIN: 'http://preview.vynic.localhost:5175',
    TRUST_PROXY_HOST: 'false',
  });
  const module = await Test.createTestingModule({
    controllers: [
      CustomerAuthController,
      CustomerController,
      PlatformOnboardingController,
      CustomerOwnerInvitationsController,
      PlatformOwnerInvitationsController,
      CustomerWebsiteController,
      WebsiteCoreController,
      CustomerPaymentsController,
      PlatformAuthController,
      PlatformCatalogController,
      PlatformOrganizationsController,
      PlatformVenuesController,
      PlatformCommercialController,
      PlatformPaymentsController,
    ],
    providers: [
      { provide: PrismaService, useValue: db },
      { provide: ConfigService, useValue: config },
      JwtService,
      CustomerAuth,
      CustomerService,
      OwnerInvitationsService,
      PlatformAuthService,
      PlatformAuditService,
      PlatformDirectoryService,
      PlatformVenueConfigService,
      PlatformDeviceService,
      PlatformCommercialService,
      StaffPinVault,
      DeviceCredentialService,
      DeviceEnrollmentService,
      EdgeCommandService,
      EnrollmentRateLimiter,
      VenueEntitlementsService,
      WebsiteCoreService,
      WebsiteMenuService,
      WebsitePreviewTokens,
      WebsiteTenantService,
      PaymentIntegrationsService,
    ],
  }).compile();
  const app = module.createNestApplication({ logger: false });
  await app.init();
  return app;
}
