import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Req,
  UseGuards,
  Res,
  ForbiddenException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { isSameOriginRequest } from '../website/tenancy/same-origin';
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
  private continuation(req: Request) {
    if (
      req.headers['x-csrf-token'] !== 'vynic-invitation' ||
      (req.headers.origin &&
        !isSameOriginRequest(req.headers.origin, req.headers, {
          trustForwardedHost: false,
        })) ||
      (process.env.NODE_ENV === 'production' && !req.headers.origin)
    )
      throw new ForbiddenException('Open the invitation on this website');
    return req.cookies?.['vynic-invitation'] as string | undefined;
  }
  @Post('session')
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  async session(
    @Body() body: Record<string, unknown>,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    this.continuation(req);
    const result = await this.service.startSession(body, req.ip ?? 'unknown');
    res.cookie('vynic-invitation', result.sessionId, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/customer/invitations',
      expires: result.expiresAt,
    });
    return result.details;
  }
  @Post('session/resume')
  @Header('Cache-Control', 'private, no-store')
  resume(@Req() req: Request) {
    return this.service.resume(this.continuation(req), req.ip ?? 'unknown');
  }
  @Post('request-new')
  @Header('Cache-Control', 'private, no-store')
  requestNew(@Body() body: Record<string, unknown>, @Req() req: Request) {
    return this.service.requestRecovery(body, req.ip ?? 'unknown');
  }
  @Post('inspect')
  @Header('Cache-Control', 'private, no-store')
  inspect(@Body() body: Record<string, unknown>, @Req() req: { ip: string }) {
    return this.service.inspect(body, req.ip);
  }
  @Post('register')
  @Header('Cache-Control', 'private, no-store')
  register(@Body() body: Record<string, unknown>, @Req() req: Request) {
    return this.service.accept(
      body,
      req.ip ?? 'unknown',
      undefined,
      body.token ? undefined : this.continuation(req),
    );
  }
  @Post('accept')
  @UseGuards(CustomerGuard)
  @Header('Cache-Control', 'private, no-store')
  accept(
    @CustomerActor() actor: CustomerPrincipal,
    @Body() body: Record<string, unknown>,
    @Req() req: Request,
  ) {
    return this.service.accept(
      body,
      req.ip ?? 'unknown',
      actor,
      body.token ? undefined : this.continuation(req),
    );
  }
}
