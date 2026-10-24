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
  HttpException,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { InstallerDownloadsService } from './installer-downloads.service';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { PlatformActor } from '../platform/platform-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { isSameOriginRequest } from '../website/tenancy/same-origin';
import { randomBytes } from 'node:crypto';
import {
  installerDownloadBridge,
  installerDownloadFailure,
} from './installer-download-bridge';

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

@Controller('customer/downloads/access/:id')
export class InstallerDownloadFileController {
  private readonly logger = new Logger(InstallerDownloadFileController.name);
  constructor(private readonly service: InstallerDownloadsService) {}
  @Get()
  async bridge(
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const nonce = randomBytes(18).toString('base64url');
    res.set({
      'Cache-Control': 'private, no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'X-Robots-Tag': 'noindex, nofollow, noarchive',
      'X-Frame-Options': 'DENY',
      'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`,
    });
    const grant = await this.service.linkContext(id, req.ip ?? 'unknown');
    res.type('html').send(installerDownloadBridge(grant.id, nonce));
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Post('session')
  async open(
    @Param('id') id: string,
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
      id,
    );
    if (body.token)
      res.cookie('vynic-download', body.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        path: '/customer/downloads/access/' + grant.id,
        expires: grant.expiresAt,
      });
    return { expiresAt: grant.expiresAt, ...this.service.status() };
  }
  @Head('file') head(
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    return this.file(id, req, res);
  }
  @Header('Cache-Control', 'private, no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get('file')
  async file(
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    res.set({
      'Cache-Control': 'private, no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy':
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
      'X-Robots-Tag': 'noindex, nofollow, noarchive',
    });
    try {
      await this.service.stream(req.cookies?.['vynic-download'], req, res, id);
    } catch (error) {
      const status = error instanceof HttpException ? error.getStatus() : 500;
      const reasons: Record<string, string> = {
        'Download unavailable or expired': 'link_unavailable',
        'Installer changed. Issue a new download link.': 'artifact_changed',
        'Download limit reached. Issue a new link.': 'transfer_limit',
        'Protected installer storage is awaiting configuration.':
          'storage_unconfigured',
        'Protected installer storage is unavailable. Try again later.':
          'storage_unavailable',
      };
      this.logger.warn({
        event: 'installer_download_unavailable',
        reason:
          error instanceof Error
            ? (reasons[error.message] ?? 'request_unavailable')
            : 'request_unavailable',
        status,
        method: req.method,
      });
      if (res.headersSent || res.destroyed) {
        res.destroy();
        return;
      }
      res.removeHeader('Content-Disposition');
      res.removeHeader('Content-Length');
      res.removeHeader('Content-Range');
      res.status(status).type('html').send(installerDownloadFailure(status));
    }
  }
}
