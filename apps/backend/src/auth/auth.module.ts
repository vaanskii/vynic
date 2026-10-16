import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { ManagerVenueLinkController } from './manager-venue-link.controller';
import { ManagerVenueLinkService } from './manager-venue-link.service';
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { LoginThrottleService } from './login-throttle.service';
import { StaffPinVault } from './staff-pin-vault.service';
import { requireEnv } from '../shared/require-env';
import { DeviceCredentialService } from './device-credential.service';
import { LegacyPosTenantService } from './legacy-pos-tenant.service';
import { ManagerTenantService } from './manager-tenant.service';
import { ManagerActivationService } from './manager-activation.service';
import { ManagerActivationController } from './manager-activation.controller';

@Module({
  imports: [
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.register({
      secret: requireEnv('JWT_SECRET'),
      signOptions: { expiresIn: '24h' },
    }),
  ],
  controllers: [
    AuthController,
    ManagerActivationController,
    ManagerVenueLinkController,
  ],
  providers: [
    EdgeDeviceGuard,
    ManagerActivationService,
    ManagerVenueLinkService,
    AuthService,
    DeviceCredentialService,
    LegacyPosTenantService,
    ManagerTenantService,
    JwtStrategy,
    LoginThrottleService,
    StaffPinVault,
  ],
  exports: [
    ManagerVenueLinkService,
    ManagerActivationService,
    JwtModule,
    AuthService,
    DeviceCredentialService,
    LegacyPosTenantService,
    ManagerTenantService,
    StaffPinVault,
  ],
})
export class AuthModule {}
