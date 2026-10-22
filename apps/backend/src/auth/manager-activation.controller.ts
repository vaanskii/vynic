import {
  Body,
  Get,
  Controller,
  HttpCode,
  Ip,
  Post,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ManagerActivationService } from './manager-activation.service';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { PosAuth } from './pos-auth-context';
import type { PosAuthContext } from './pos-auth-context';
import { LoginThrottleService } from './login-throttle.service';

@Controller('edge')
@UseGuards(EdgeDeviceGuard)
export class ManagerActivationController {
  constructor(
    private readonly activation: ManagerActivationService,
    private readonly throttle: LoginThrottleService,
  ) {}

  @Get('manager-setup')
  setupStatus(@PosAuth() auth: PosAuthContext) {
    return this.activation.setupStatus(auth);
  }

  @Post('manager-setup')
  @HttpCode(200)
  async setup(
    @PosAuth() auth: PosAuthContext,
    @Body() body: Record<string, unknown>,
    @Ip() ip: string,
  ) {
    const key = `manager-activation:${auth.deviceId}:${ip}`;
    this.throttle.assertNotLocked(key);
    try {
      const result = await this.activation.completeSetup(auth, body);
      this.throttle.recordSuccess(key);
      return result;
    } catch (error) {
      if (error instanceof UnauthorizedException)
        this.throttle.recordFailure(key);
      throw error;
    }
  }

  @Post('manager-activation')
  @HttpCode(200)
  async complete(
    @PosAuth() auth: PosAuthContext,
    @Body() body: Record<string, unknown>,
    @Ip() ip: string,
  ) {
    const key = `manager-activation:${auth.deviceId}:${ip}`;
    this.throttle.assertNotLocked(key);
    try {
      const result = await this.activation.complete(auth, body);
      this.throttle.recordSuccess(key);
      return result;
    } catch (error) {
      if (error instanceof UnauthorizedException)
        this.throttle.recordFailure(key);
      throw error;
    }
  }
}
