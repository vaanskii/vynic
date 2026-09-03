import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformDirectoryService } from './platform-directory.service';
import {
  optionalText,
  readPage,
  requireText,
  requireUuid,
} from './platform-validation';

interface OrganizationBody {
  name?: unknown;
}

/**
 * Organizations, from above every tenant.
 *
 * No delete. An Organization is referenced by Venues under a restrictive
 * foreign key, and everything a restaurant has hangs off those — deleting one
 * would either fail or have to erase a business's history. Disabling its Venues
 * is the reversible operation that answers the real need.
 */
@Controller('platform/organizations')
@UseGuards(PlatformAuthGuard)
export class PlatformOrganizationsController {
  constructor(private readonly directory: PlatformDirectoryService) {}

  @Get()
  async list(@Query() query: { limit?: string; offset?: string }) {
    return this.directory.listOrganizations(readPage(query));
  }

  @Get(':organizationId')
  async read(@Param('organizationId') organizationId: string) {
    return this.directory.getOrganization(
      requireUuid(organizationId, 'organizationId'),
    );
  }

  @Post()
  async create(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: OrganizationBody,
  ) {
    return this.directory.createOrganization(actor, {
      name: requireText(body.name, 'name'),
    });
  }

  @Patch(':organizationId')
  async update(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('organizationId') organizationId: string,
    @Body() body: OrganizationBody,
  ) {
    return this.directory.updateOrganization(
      actor,
      requireUuid(organizationId, 'organizationId'),
      { name: optionalText(body.name, 'name') },
    );
  }
}
