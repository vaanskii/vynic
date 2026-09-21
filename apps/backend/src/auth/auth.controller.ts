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

  @Post('manager-venue')
  @HttpCode(HttpStatus.OK)
  async managerVenue(@Body() body: { venueCode?: string }, @Ip() ip: string) {
    // Separate from PIN failures; successful lookups cannot reset PIN throttling.
    const key = `venue-lookup:${ip}`;
    this.throttle.assertNotLocked(key);
    try {
      const venue = await this.authService.resolveManagerVenue(body?.venueCode);
      this.throttle.recordSuccess(key);
      return venue;
    } catch (error) {
      if (error instanceof UnauthorizedException)
        this.throttle.recordFailure(key);
      throw error;
    }
  }

  /** POST /auth/mobile-login  { venueCode: "vankisi", pin: "1234" } */
  @Post('mobile-login')
  @HttpCode(HttpStatus.OK)
  async mobileLogin(
    @Body() body: { pin?: string; venueCode?: string },
    @Ip() ip: string,
  ) {
    if (!body?.pin) {
      throw new BadRequestException('PIN is required');
    }
    this.throttle.assertNotLocked(ip);
    try {
      const result = await this.authService.mobileLogin(
        body.pin,
        body.venueCode,
      );
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
