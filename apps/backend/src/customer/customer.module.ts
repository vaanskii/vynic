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
    AuthModule,
    PlatformModule,
    EdgeTransportModule,
    EntitlementsModule,
  ],
  providers: [
    CustomerAuth,
    CustomerGuard,
    CustomerService,
    EnrollmentRateLimiter,
    EdgeDeviceGuard,
  ],
  controllers: [
    CustomerAuthController,
    CustomerController,
    PlatformOnboardingController,
    DeviceRuntimeConfigController,
  ],
})
export class CustomerModule {}
