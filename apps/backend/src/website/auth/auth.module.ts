import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { WebsiteAuthController } from './auth.controller';
import { WebsiteAuthService } from './auth.service';
import { WebsiteAuthGuard } from './website-auth.guard';
import { WebsiteRolesGuard } from './website-roles.guard';
import { CryptoService } from '../common/crypto.service';
import { CsrfService } from '../common/csrf.service';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';

@Module({
  imports: [JwtModule.register({}), WebsiteTenancyModule],
  controllers: [WebsiteAuthController],
  providers: [
    WebsiteAuthService,
    WebsiteAuthGuard,
    WebsiteRolesGuard,
    CryptoService,
    CsrfService,
    EnrollmentRateLimiter,
  ],
  exports: [
    WebsiteAuthService,
    WebsiteAuthGuard,
    WebsiteRolesGuard,
    CryptoService,
    CsrfService,
  ],
})
export class WebsiteAuthModule {}
