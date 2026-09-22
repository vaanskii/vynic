import {
  Controller,
  Get,
  Req,
  Res,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { WebsiteCoreService } from './website-core.service';
import { WebsitePreviewTokens } from './website-preview';
import { sendPrivateWebsite, sendPublicWebsite } from './website-cache';

/**
 * The public and preview surface of the generic SaaS website.
 *
 * Public routes take their Venue from the request host alone. Preview routes
 * take it from a server-issued preview token alone: no route here accepts a
 * Venue id from a query, body or client header.
 */
@Controller('api/website')
export class WebsiteCoreController {
  constructor(
    private readonly core: WebsiteCoreService,
    private readonly previews: WebsitePreviewTokens,
  ) {}

  @Get('bootstrap')
  async bootstrap(@Req() request: Request, @Res() response: Response) {
    sendPublicWebsite(
      request,
      response,
      await this.core.bootstrap(request.headers),
    );
  }

  @Get('menu')
  async menu(@Req() request: Request, @Res() response: Response) {
    sendPublicWebsite(
      request,
      response,
      await this.core.publicMenu(request.headers),
    );
  }

  @Get('preview/bootstrap')
  async previewBootstrap(@Req() request: Request, @Res() response: Response) {
    const { venueId } = await this.principal(request);
    sendPrivateWebsite(response, await this.core.previewBootstrap(venueId));
  }

  @Get('preview/menu')
  async previewMenu(@Req() request: Request, @Res() response: Response) {
    const { venueId } = await this.principal(request);
    sendPrivateWebsite(response, await this.core.previewMenu(venueId));
  }

  private principal(request: Request) {
    const header = request.headers.authorization;
    if (typeof header !== 'string' || !header.startsWith('Bearer '))
      throw new UnauthorizedException('Website preview authorization required');
    return this.previews.resolve(header.slice(7));
  }
}
