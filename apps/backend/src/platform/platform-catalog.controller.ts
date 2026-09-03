import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuditService } from './platform-audit.service';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { readPage, requireUuid } from './platform-validation';

/** The product catalogue and the platform's own audit trail. */
@Controller('platform')
@UseGuards(PlatformAuthGuard)
export class PlatformCatalogController {
  constructor(
    private readonly config: PlatformVenueConfigService,
    private readonly audit: PlatformAuditService,
  ) {}

  @Get('plans')
  async plans() {
    return this.config.listPlans();
  }

  @Get('features')
  async features() {
    return this.config.listFeatures();
  }

  @Get('audit')
  async auditTrail(
    @Query()
    query: {
      limit?: string;
      offset?: string;
      targetId?: string;
      venueId?: string;
    },
  ) {
    const page = readPage(query);
    return this.audit.recent(
      page.limit,
      page.offset,
      query.targetId ? requireUuid(query.targetId, 'targetId') : undefined,
      query.venueId ? requireUuid(query.venueId, 'venueId') : undefined,
    );
  }
}
