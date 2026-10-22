import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { HostnameRequestsService } from '../website/core/hostname-requests';
@Controller('platform/venues/:venueId/hostname-requests')
@UseGuards(PlatformAuthGuard)
export class PlatformHostnameController {
  constructor(private readonly requests: HostnameRequestsService) {}
  @Get() list(@Param('venueId') venueId: string) {
    return this.requests.list(venueId);
  }
  @Post(':id/review') review(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.requests.review(venueId, id, actor.platformUserId, body);
  }
}
