import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { EdgeTransportModule } from '../edge/edge-transport.module';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { PlatformAuditService } from './platform-audit.service';
import { PlatformAuthController } from './platform-auth.controller';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformCatalogController } from './platform-catalog.controller';
import { PlatformDeviceService } from './platform-device.service';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformOrganizationsController } from './platform-organizations.controller';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { PlatformVenuesController } from './platform-venues.controller';

/**
 * The Vynic control plane.
 *
 * Sits above every tenant and shares nothing with tenant authentication except
 * the primitives it would be wrong to duplicate: the JWT signer, the Argon2id
 * hashing, the entitlement resolver, the device credential service, the edge
 * queue. Everything that decides *who may do this* is its own.
 */
@Module({
  imports: [AuthModule, EntitlementsModule, EdgeTransportModule],
  controllers: [
    PlatformAuthController,
    PlatformOrganizationsController,
    PlatformVenuesController,
    PlatformCatalogController,
  ],
  providers: [
    PlatformAuthService,
    PlatformAuthGuard,
    PlatformAuditService,
    PlatformDirectoryService,
    PlatformVenueConfigService,
    PlatformDeviceService,
  ],
  exports: [PlatformAuthService],
})
export class PlatformModule {}
