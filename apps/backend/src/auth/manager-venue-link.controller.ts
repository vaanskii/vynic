import {
  Body,
  Controller,
  Get,
  HttpCode,
  Ip,
  Param,
  Post,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ManagerVenueLinkService } from './manager-venue-link.service';
import { LoginThrottleService } from './login-throttle.service';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import {
  PlatformActor,
  type PlatformPrincipal,
} from '../platform/platform-auth-context';
import { requireUuid } from '../platform/platform-validation';

@Controller('auth')
export class ManagerVenueLinkController {
  constructor(
    private readonly links: ManagerVenueLinkService,
    private readonly throttle: LoginThrottleService,
  ) {}
  @Post('manager-link')
  @HttpCode(200)
  async redeem(@Body() body: Record<string, unknown>, @Ip() ip: string) {
    const key = `venue-lookup:${ip}`; // Shared with legacy lookup; never resets PIN throttling.
    this.throttle.assertNotLocked(key);
    try {
      const result = await this.links.redeem(body);
      this.throttle.recordSuccess(key);
      return result;
    } catch (error) {
      if (error instanceof UnauthorizedException)
        this.throttle.recordFailure(key);
      throw error;
    }
  }
}

@Controller('platform/venues/:venueId/manager-links')
@UseGuards(PlatformAuthGuard)
export class PlatformManagerVenueLinkController {
  constructor(private readonly links: ManagerVenueLinkService) {}
  @Get()
  list(@Param('venueId') venueId: string) {
    return this.links.list(requireUuid(venueId, 'venueId'));
  }
  @Post()
  issue(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
  ) {
    return this.links.issue(actor, requireUuid(venueId, 'venueId'));
  }
  @Post(':linkId/cancel')
  cancel(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('linkId') id: string,
  ) {
    return this.links.cancel(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(id, 'linkId'),
    );
  }
}
