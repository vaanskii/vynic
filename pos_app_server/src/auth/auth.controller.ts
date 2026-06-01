import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /** POST /auth/mobile-login  { pin: "1234" } */
  @Post('mobile-login')
  @HttpCode(HttpStatus.OK)
  async mobileLogin(@Body() body: { pin?: string }) {
    if (!body?.pin) {
      throw new BadRequestException('PIN is required');
    }
    return this.authService.mobileLogin(body.pin);
  }
}
