import { FileInterceptor } from '@nestjs/platform-express';
import {
  WebsiteLogoService,
  MAX_LOGO_BYTES,
} from '../website/core/website-logo.service';
import {
  Body,
  ForbiddenException,
  UploadedFile,
  UseInterceptors,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { CustomerService } from './customer.service';
import { WebsiteCoreService } from '../website/core/website-core.service';
import { WebsiteMenuService } from '../website/core/website-menu.service';
import { WebsitePreviewTokens } from '../website/core/website-preview';

/**
 * Owner control of the generic SaaS website.
 *
 * Every route proves Venue ownership first, so another owner's restaurant is
 * a 404 here regardless of which id is supplied.
 */
@Controller('customer/venues/:venueId/website')
@UseGuards(CustomerGuard)
export class CustomerWebsiteController {
  constructor(
    private readonly owners: CustomerService,
    private readonly core: WebsiteCoreService,
    private readonly menu: WebsiteMenuService,
    private readonly previews: WebsitePreviewTokens,
    private readonly config: ConfigService,
    private readonly logos: WebsiteLogoService,
  ) {}
  @Post('logo')
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: MAX_LOGO_BYTES, files: 1, fields: 0 },
    }),
  )
  async uploadLogo(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @UploadedFile() file?: { buffer: Buffer; size: number },
  ) {
    await this.owners.venue(actor, id);
    const settings = await this.core.settings(id);
    if (settings.mode !== 'SAAS')
      throw new ForbiddenException(
        'Generic website editing requires SAAS mode',
      );
    return this.logos.upload(id, file);
  }

  @Post('hero')
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: MAX_LOGO_BYTES, files: 1, fields: 0 },
    }),
  )
  async uploadHero(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @UploadedFile() file?: { buffer: Buffer; size: number },
  ) {
    await this.owners.venue(actor, id);
    const settings = await this.core.settings(id);
    if (settings.mode !== 'SAAS')
      throw new ForbiddenException(
        'Generic website editing requires SAAS mode',
      );
    return this.logos.upload(id, file, 'hero');
  }

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async settings(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    return this.core.settings(id);
  }
  /** Advisory check while the owner chooses a website address. */
  @Get('address/:slug')
  @Header('Cache-Control', 'private, no-store')
  async address(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('slug') slug: string,
  ) {
    await this.owners.venue(actor, id);
    return this.core.addressAvailability(id, slug);
  }
  @Put('draft') async save(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: unknown,
  ) {
    await this.owners.venue(actor, id);
    return this.core.save(id, body, actor.customerAccountId);
  }
  @Get('preview')
  @Header('Cache-Control', 'private, no-store')
  async preview(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    return this.core.preview(id);
  }

  /**
   * Authority for the real generic frontend to render this Venue's draft.
   *
   * The token is returned in the response body, never embedded in a link the
   * portal navigates to directly: the portal puts it in the preview URL's
   * fragment, which browsers do not send to any server.
   */
  @Post('preview-session')
  @Header('Cache-Control', 'private, no-store')
  async previewSession(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    // Refuses non-SAAS Venues before a token exists for one.
    await this.core.preview(id);
    const issued = await this.previews.issue(id, actor.customerAccountId);
    return {
      ...issued,
      previewOrigin:
        this.config.get<string>('SAAS_WEBSITE_PREVIEW_ORIGIN') ?? null,
    };
  }
  @Post('publish') async publish(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: unknown,
  ) {
    await this.owners.venue(actor, id);
    return this.core.publish(id, body, actor.customerAccountId);
  }

  /** The operational menu with its website presentation, hidden items included. */
  @Get('menu')
  @Header('Cache-Control', 'private, no-store')
  async menuSettings(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    return this.menu.ownerMenu(id);
  }

  /**
   * Presentation only: visibility, public name, description, image, order.
   *
   * Operational menu authority stays with POS/Cloud, so nothing here creates,
   * renames, reprices or deletes an item.
   */
  @Put('menu') async saveMenu(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: unknown,
  ) {
    await this.owners.venue(actor, id);
    return this.menu.savePresentation(id, body, actor.customerAccountId);
  }
}
