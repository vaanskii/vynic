import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { PlatformActor } from '../platform/platform-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { OwnerInvitationsService } from './owner-invitations.service';

@Controller('platform/onboarding')
@UseGuards(PlatformAuthGuard)
export class PlatformOwnerInvitationsController {
  constructor(private readonly service: OwnerInvitationsService) {}
  @Get('organizations') organizations() {
    return this.service.organizations();
  }
  @Get('invitations') list() {
    return this.service.list();
  }
  @Post('customers')
  @Header('Cache-Control', 'private, no-store')
  provision(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.provision(actor, body);
  }
  @Post('invitations')
  @Header('Cache-Control', 'private, no-store')
  create(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.create(actor, body);
  }
  @Post('invitations/:id/revoke') revoke(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
  ) {
    return this.service.change(actor, id, false);
  }
  @Post('invitations/:id/regenerate')
  @Header('Cache-Control', 'private, no-store')
  regenerate(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
  ) {
    return this.service.change(actor, id, true);
  }
}

@Controller('customer/invitations')
export class CustomerOwnerInvitationsController {
  constructor(private readonly service: OwnerInvitationsService) {}
  @Post('inspect')
  @Header('Cache-Control', 'private, no-store')
  inspect(@Body() body: Record<string, unknown>, @Req() req: { ip: string }) {
    return this.service.inspect(body, req.ip);
  }
  @Post('register')
  @Header('Cache-Control', 'private, no-store')
  register(@Body() body: Record<string, unknown>, @Req() req: { ip: string }) {
    return this.service.accept(body, req.ip);
  }
  @Post('accept')
  @UseGuards(CustomerGuard)
  @Header('Cache-Control', 'private, no-store')
  accept(
    @CustomerActor() actor: CustomerPrincipal,
    @Body() body: Record<string, unknown>,
    @Req() req: { ip: string },
  ) {
    return this.service.accept(body, req.ip, actor);
  }
}
