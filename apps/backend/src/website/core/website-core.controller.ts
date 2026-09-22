import { Controller, Get, Header, Req } from '@nestjs/common';
import type { Request } from 'express';
import { WebsiteCoreService } from './website-core.service';
@Controller('api/website')
export class WebsiteCoreController {
  constructor(private readonly core: WebsiteCoreService) {}
  @Get('bootstrap')
  @Header('Cache-Control', 'private, no-store')
  bootstrap(@Req() request: Request) {
    return this.core.bootstrap(request.headers);
  }
}
