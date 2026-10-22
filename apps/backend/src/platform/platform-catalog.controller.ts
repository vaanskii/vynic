import { PlanCatalogService } from './plan-catalog.service';
import { PlatformActor } from './platform-auth-context';
import type { PlatformPrincipal } from './platform-auth-context';
import {
  Body,
  Param,
  Put,
  Controller,
  Get,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuditService } from './platform-audit.service';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { readPage, requireUuid } from './platform-validation';

/** The product catalogue and the platform's own audit trail. */
@Controller('platform')
@UseGuards(PlatformAuthGuard)
export class PlatformCatalogController {
  constructor(
    private readonly catalog: PlanCatalogService,
    private readonly config: PlatformVenueConfigService,
    private readonly audit: PlatformAuditService,
  ) {}

  @Post('plans') createPlan(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    return this.catalog.save(actor, undefined, body);
  }
  @Put('plans/:id') updatePlan(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.catalog.save(actor, id, body);
  }

  @Get('plans')
  async plans() {
    return this.config.listPlans();
  }

  @Post('plans/website-only')
  ensureWebsitePlan(@PlatformActor() actor: PlatformPrincipal) {
    return this.config.ensureWebsitePlan(actor);
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
