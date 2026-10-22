import { Body, Controller, Get, Param, Put, UseGuards } from '@nestjs/common';
import { WebsiteCapabilitiesService } from '../website/tenancy/website-capabilities.service';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { requireUuid } from './platform-validation';

/**
 * Per-Venue shared website capabilities, for SAAS and CUSTOM alike: whether
 * each is commercially available, switched on, configured, and shown by the
 * current renderer. Only the on/off policy is writable here; entitlement stays
 * in Product and configuration with its owner. SUPPORT_READONLY may read.
 */
@Controller('platform/venues/:venueId/website-capabilities')
@UseGuards(PlatformAuthGuard)
export class PlatformWebsiteCapabilitiesController {
  constructor(private readonly capabilities: WebsiteCapabilitiesService) {}

  @Get()
  read(@Param('venueId') venueId: string) {
    return this.capabilities.platformStates(requireUuid(venueId, 'venueId'));
  }

  @Put(':capability')
  set(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('capability') capability: string,
    @Body() body: { enabled?: unknown },
  ) {
    return this.capabilities.setEnabled(
      actor,
      requireUuid(venueId, 'venueId'),
      capability,
      body?.enabled,
    );
  }
}
