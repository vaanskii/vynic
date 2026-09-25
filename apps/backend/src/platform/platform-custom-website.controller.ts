import { Body, Controller, Get, Param, Put, UseGuards } from '@nestjs/common';
import { CustomWebsiteService } from '../website/custom/custom-website.service';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { requireUuid } from './platform-validation';

/**
 * Operator provisioning of a CUSTOM website: frontend identity, setup status
 * and the checklist that gates READY/ACTIVE. Domains stay on the Venue domain
 * routes and WebsiteMode on the Venue website route; this view joins them.
 */
@Controller('platform/venues/:venueId/custom-website')
@UseGuards(PlatformAuthGuard)
export class PlatformCustomWebsiteController {
  constructor(private readonly custom: CustomWebsiteService) {}

  @Get()
  read(@Param('venueId') venueId: string) {
    return this.custom.platformView(requireUuid(venueId, 'venueId'));
  }

  @Put()
  update(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.custom.platformUpdate(
      actor,
      requireUuid(venueId, 'venueId'),
      body ?? {},
    );
  }
}
