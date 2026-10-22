import { websiteCookieSecure } from '../../shared/deployment-config';
import {
  Body,
  Controller,
  Post,
  Get,
  Res,
  Req,
  ForbiddenException,
  HttpException,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { CryptoService } from '../common/crypto.service';
import { CsrfService } from '../common/csrf.service';
import { WebsiteAuthService } from './auth.service';
import { AuthDto, ChangePasswordDto, RegisterDto } from './dto';
import { WebsiteAuthGuard } from './website-auth.guard';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import {
  RequiresWebsiteCapability,
  WebsiteCapabilityGuard,
} from '../tenancy/website-capability.guard';

@Controller('api/auth')
export class WebsiteAuthController {
  constructor(
    private readonly authService: WebsiteAuthService,
    private readonly cryptoService: CryptoService,
    private readonly csrfService: CsrfService,
    private readonly limiter: EnrollmentRateLimiter,
  ) {}

  // Accounts are global, but a website offers sign-up and sign-in only where
  // the CUSTOMER_ACCOUNTS capability is available for the Host's Venue.
  @Post('signup')
  @UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
  @RequiresFeature(FeatureKeys.WEBSITE)
  @RequiresWebsiteCapability('CUSTOMER_ACCOUNTS')
  async signup(
    @Body() dto: RegisterDto,
    @Res({ passthrough: true }) res: Response,
    @Req() req: Request,
  ) {
    this.assertCsrf(req);
    this.admitAttempt(req, [dto.email, dto.phone]);
    const tokens = await this.authService.signup(dto);
    this.setAuthCookies(res, tokens, req.headers.host);
    return { message: 'Signup successful' };
  }

  @Post('signin')
  @UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
  @RequiresFeature(FeatureKeys.WEBSITE)
  @RequiresWebsiteCapability('CUSTOMER_ACCOUNTS')
  async signin(
    @Body() dto: AuthDto,
    @Res({ passthrough: true }) res: Response,
    @Req() req: Request,
  ) {
    this.assertCsrf(req);
    this.admitAttempt(req, [dto.identifier]);
    const tokens = await this.authService.signin(dto);
    this.setAuthCookies(res, tokens, req.headers.host);
    return { message: 'Signin successful' };
  }

  @Post('logout')
  logout(@Res({ passthrough: true }) res: Response) {
    res.clearCookie('access_token');
    res.clearCookie('refresh_token');
    return { message: 'Logout successful' };
  }

  @Get('csrf')
  getCsrfToken(@Res({ passthrough: true }) res: Response, @Req() req: Request) {
    const token = this.csrfService.generateToken();
    res.cookie('csrf_token', token, {
      httpOnly: false,
      secure: websiteCookieSecure(req.headers.host),
      sameSite: 'strict',
      maxAge: 24 * 60 * 60 * 1000,
    });
    return { csrfToken: token };
  }

  @Get('verify')
  async verify(@Req() req: Request) {
    try {
      const encryptedAccessToken: unknown = req.cookies?.['access_token'];
      if (typeof encryptedAccessToken !== 'string' || !encryptedAccessToken)
        return { isAuthenticated: false };

      const accessToken = this.cryptoService.decrypt(encryptedAccessToken);
      const user = await this.authService.verifyToken(accessToken);
      return {
        isAuthenticated: true,
        user: {
          id: user.id,
          phone: user.phone,
          firstName: user.firstName,
          lastName: user.lastName,
          email: user.email,
          role: user.role,
        },
      };
    } catch {
      return { isAuthenticated: false };
    }
  }

  @UseGuards(WebsiteAuthGuard)
  @Post('change-password')
  async changePassword(@Body() dto: ChangePasswordDto, @Req() req: Request) {
    this.assertCsrf(req);
    const user = (req as Request & { user: { id: string } }).user;
    this.admitAttempt(req, [], user.id);
    return this.authService.changePassword(user.id, dto);
  }

  private admitAttempt(req: Request, identifiers: string[], userId?: string) {
    // Website accounts are global: Host changes must not create fresh windows.
    // Every valid attempt counts, including successes. No account lookup is
    // needed to normalize an identifier, and unknown accounts get the same 429.
    const keys = [`website-auth-ip:${req.ip ?? 'unknown'}`];
    for (const identifier of identifiers) {
      const trimmed = identifier.trim();
      keys.push(
        `website-auth-identifier:${trimmed.includes('@') ? trimmed.toLowerCase() : trimmed}`,
      );
    }
    if (userId) keys.push(`website-auth-user:${userId}`);
    for (const [index, key] of keys.entries()) {
      if (!this.limiter.consume(key, index === 0 ? 20 : 10, 900000)) {
        throw new HttpException('Too many attempts. Try again later.', 429);
      }
    }
  }

  private assertCsrf(req: Request) {
    const csrfToken = req.headers['x-csrf-token'];
    const csrfCookie: unknown = req.cookies?.['csrf_token'];
    if (!this.csrfService.validateToken(csrfToken, csrfCookie)) {
      throw new ForbiddenException('Invalid CSRF token');
    }
  }

  private setAuthCookies(
    res: Response,
    tokens: { access_token: string; refresh_token: string },
    host: string | undefined,
  ) {
    const secure = websiteCookieSecure(host);
    res.cookie(
      'access_token',
      this.cryptoService.encrypt(tokens.access_token),
      {
        httpOnly: true,
        secure,
        sameSite: 'strict',
        maxAge: 15 * 60 * 1000,
      },
    );
    res.cookie(
      'refresh_token',
      this.cryptoService.encrypt(tokens.refresh_token),
      {
        httpOnly: true,
        secure,
        sameSite: 'strict',
        maxAge: 7 * 24 * 60 * 60 * 1000,
      },
    );
  }
}
