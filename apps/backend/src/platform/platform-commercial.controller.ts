import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformCommercialService } from './platform-commercial.service';
import { requireUuid } from './platform-validation';

@Controller('platform')
@UseGuards(PlatformAuthGuard)
export class PlatformCommercialController {
  constructor(private readonly service: PlatformCommercialService) {}
  @Get('venues/:venueId/subscription') subscription(
    @Param('venueId') id: string,
  ) {
    return this.service.subscription(requireUuid(id, 'venueId'));
  }
  @Put('venues/:venueId/subscription') setSubscription(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.setSubscription(
      actor,
      requireUuid(id, 'venueId'),
      body,
    );
  }
  @Get('venues/:venueId/managers') managers(@Param('venueId') id: string) {
    return this.service.managers(requireUuid(id, 'venueId'));
  }
  @Post('venues/:venueId/managers') create(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.managerAccess(
      actor,
      requireUuid(id, 'venueId'),
      'create',
      body,
    );
  }
  @Post('venues/:venueId/managers/:staffId/reset') reset(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') id: string,
    @Param('staffId') staffId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.managerAccess(
      actor,
      requireUuid(id, 'venueId'),
      'reset',
      body,
      requireUuid(staffId, 'staffId'),
    );
  }
  @Post('venues/:venueId/managers/:staffId/disable') disable(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') id: string,
    @Param('staffId') staffId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.managerAccess(
      actor,
      requireUuid(id, 'venueId'),
      'disable',
      body,
      requireUuid(staffId, 'staffId'),
    );
  }
  @Get('users') users() {
    return this.service.users();
  }
  @Post('users') createUser(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.createUser(actor, body);
  }
  @Post('users/:id/disable') disableUser(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
  ) {
    return this.service.disableUser(actor, requireUuid(id, 'id'));
  }
}
