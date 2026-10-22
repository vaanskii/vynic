import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { cleanupCustomers } from '../local-tools/customer-cleanup';
import { localDockerEnabled } from '../local-tools/local-docker-guard';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { requireUuid } from './platform-validation';

@Controller('platform/developer-tools')
@UseGuards(PlatformAuthGuard)
export class PlatformLocalToolsCapabilityController {
  @Get()
  capability() {
    return { enabled: localDockerEnabled() };
  }
}

/** Not registered outside local Docker; rechecks the complete guard on every call. */
@Controller('platform/developer-tools')
@UseGuards(PlatformAuthGuard)
export class PlatformLocalToolsController {
  constructor(private readonly db: PrismaService) {}
  @Post('venues/:id/delete')
  venue(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
    @Body() body: { confirmation?: unknown },
  ) {
    return this.remove('venue', actor, id, body);
  }
  @Post('organizations/:id/delete')
  organization(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
    @Body() body: { confirmation?: unknown },
  ) {
    return this.remove('organization', actor, id, body);
  }
  private remove(
    kind: 'venue' | 'organization',
    actor: PlatformPrincipal,
    id: string,
    body: { confirmation?: unknown },
  ) {
    if (!localDockerEnabled()) throw new NotFoundException();
    return cleanupCustomers(this.db, {
      kind,
      id: requireUuid(id, 'id'),
      actorId: actor.platformUserId,
      confirmation:
        typeof body?.confirmation === 'string' ? body.confirmation : '',
    });
  }
}
export const localDeletionControllers = () =>
  localDockerEnabled() ? [PlatformLocalToolsController] : [];
