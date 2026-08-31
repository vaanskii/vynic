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

@Module({
  imports: [
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.register({
      secret: requireEnv('JWT_SECRET'),
      signOptions: { expiresIn: '24h' },
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    DeviceCredentialService,
    LegacyPosTenantService,
    JwtStrategy,
    LoginThrottleService,
    StaffPinVault,
  ],
  exports: [
    JwtModule,
    AuthService,
    DeviceCredentialService,
    LegacyPosTenantService,
    StaffPinVault,
  ],
})
export class AuthModule {}
