import {
  Controller,
  Post,
  Body,
  Ip,
  HttpCode,
  HttpStatus,
  BadRequestException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginThrottleService } from './login-throttle.service';

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly throttle: LoginThrottleService,
  ) {}

  /** POST /auth/mobile-login  { pin: "1234" } */
  @Post('mobile-login')
  @HttpCode(HttpStatus.OK)
  async mobileLogin(@Body() body: { pin?: string }, @Ip() ip: string) {
    if (!body?.pin) {
      throw new BadRequestException('PIN is required');
    }
    this.throttle.assertNotLocked(ip);
    try {
      const result = await this.authService.mobileLogin(body.pin);
      this.throttle.recordSuccess(ip);
      return result;
    } catch (e) {
      if (e instanceof UnauthorizedException) {
        this.throttle.recordFailure(ip);
      }
      throw e;
    }
  }
}
