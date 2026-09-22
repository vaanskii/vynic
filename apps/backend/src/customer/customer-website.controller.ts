import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { CustomerService } from './customer.service';
import { WebsiteCoreService } from '../website/core/website-core.service';
@Controller('customer/venues/:venueId/website')
@UseGuards(CustomerGuard)
export class CustomerWebsiteController {
  constructor(
    private readonly owners: CustomerService,
    private readonly core: WebsiteCoreService,
  ) {}
  @Get()
  @Header('Cache-Control', 'private, no-store')
  async settings(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    return this.core.settings(id);
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
  @Post('publish') async publish(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: unknown,
  ) {
    await this.owners.venue(actor, id);
    return this.core.publish(id, body, actor.customerAccountId);
  }
}
