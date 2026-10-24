import {
  Body,
  Controller,
  Get,
  Header,
  Head,
  Param,
  Post,
  Req,
  Res,
  UseGuards,
  ForbiddenException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { InstallerDownloadsService } from './installer-downloads.service';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { PlatformActor } from '../platform/platform-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { isSameOriginRequest } from '../website/tenancy/same-origin';

@Controller('platform/onboarding/downloads')
@UseGuards(PlatformAuthGuard)
export class PlatformInstallerDownloadsController {
  constructor(private readonly service: InstallerDownloadsService) {}
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get()
  list() {
    return this.service.listAdmin();
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post()
  issue(@PlatformActor() actor: PlatformPrincipal, @Req() req: Request) {
    return this.service.issue(
      { platformUserId: actor.platformUserId },
      req.ip ?? 'unknown',
    );
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post(':id/revoke')
  revoke(@Param('id') id: string, @PlatformActor() actor: PlatformPrincipal) {
    return this.service.revoke(id, actor);
  }
}

@Controller('customer/venues/:venueId/downloads')
@UseGuards(CustomerGuard)
export class CustomerInstallerDownloadsController {
  constructor(private readonly service: InstallerDownloadsService) {}
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get()
  list(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
  ) {
    return this.service.listCustomer(actor, venueId);
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post()
  issue(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
    @Req() req: Request,
  ) {
    return this.service.issue({ ...actor, venueId }, req.ip ?? 'unknown');
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post(':id/revoke')
  async revoke(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
    @Param('id') id: string,
  ) {
    await this.service.listCustomer(actor, venueId);
    return this.service.revoke(id, actor);
  }
}

@Controller('customer/downloads')
export class InstallerDownloadFileController {
  constructor(private readonly service: InstallerDownloadsService) {}
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post('open')
  async open(
    @Body() body: Record<string, unknown>,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    if (
      req.headers['x-csrf-token'] !== 'vynic-download' ||
      (req.headers.origin &&
        !isSameOriginRequest(req.headers.origin, req.headers, {
          trustForwardedHost: false,
        })) ||
      (process.env.NODE_ENV === 'production' && !req.headers.origin)
    )
      throw new ForbiddenException('Open this link on the Vynic website');
    const grant = await this.service.resolve(
      body.token ?? req.cookies?.['vynic-download'],
      req.ip ?? 'unknown',
    );
    if (body.token)
      res.cookie('vynic-download', body.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        path: '/customer/downloads',
        expires: grant.expiresAt,
      });
    return { expiresAt: grant.expiresAt, ...this.service.status() };
  }
  @Head('file') head(@Req() req: Request, @Res() res: Response) {
    return this.file(req, res);
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get('file')
  file(@Req() req: Request, @Res() res: Response) {
    res.set({
      'Cache-Control': 'private, no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
    });
    return this.service.stream(req.cookies?.['vynic-download'], req, res);
  }
}
