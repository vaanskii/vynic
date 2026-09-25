import {
  Body,
  Controller,
  Get,
  HttpException,
  Ip,
  Post,
  UseGuards,
} from '@nestjs/common';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuthService, normalizeEmail } from './platform-auth.service';
import { requireText } from './platform-validation';

interface LoginBody {
  email?: string;
  password?: string;
}

/** Sign-in for Vynic administrators. */
@Controller('platform/auth')
export class PlatformAuthController {
  constructor(
    private readonly auth: PlatformAuthService,
    private readonly limiter: EnrollmentRateLimiter,
  ) {}

  @Post('login')
  async login(@Body() body: LoginBody, @Ip() ip: string) {
    // Length-checked, not format-checked: a wrong address must fail exactly the
    // way a wrong password does, so the response cannot enumerate accounts.
    const email = requireText(body.email, 'email', { max: 320 });
    const password = requireText(body.password, 'password', { max: 512 });
    // Same windows as Customer sign-in: every attempt counts, so a caller who
    // guesses the password on the last try still spends the window. Per-email
    // keys use the same normalized form the account lookup does.
    if (
      !this.limiter.consume(`platform-ip:${ip}`, 20, 900000) ||
      !this.limiter.consume(
        `platform-email:${normalizeEmail(email)}`,
        10,
        900000,
      )
    )
      throw new HttpException('Too many attempts. Try again later.', 429);
    return this.auth.login(email, password);
  }

  @Get('me')
  @UseGuards(PlatformAuthGuard)
  me(@PlatformActor() actor: PlatformPrincipal) {
    return actor;
  }
}
