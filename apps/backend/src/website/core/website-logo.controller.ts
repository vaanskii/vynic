import { Controller, Get, Header, Param, StreamableFile } from '@nestjs/common';
import { WebsiteLogoService } from './website-logo.service';

/** Logo bytes are public media, like external image references, not website/tenant data. */
@Controller('media/website-logos')
export class WebsiteLogoController {
  constructor(private readonly logos: WebsiteLogoService) {}
  @Get(':name')
  @Header('Cache-Control', 'public, max-age=31536000, immutable')
  @Header('X-Content-Type-Options', 'nosniff')
  async read(@Param('name') name: string) {
    return new StreamableFile(await this.logos.read(name), {
      type: 'image/webp',
    });
  }
}
