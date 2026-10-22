import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { CustomerService } from './customer.service';
import { PaymentIntegrationsService } from '../payment-integrations/payment-integrations.service';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';

@Controller('customer/venues/:venueId/payments/bog')
@UseGuards(CustomerGuard)
export class CustomerPaymentsController {
  constructor(
    private readonly owners: CustomerService,
    private readonly payments: PaymentIntegrationsService,
  ) {}
  @Get() async status(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    await this.owners.requireFeature(id, 'ONLINE_PAYMENTS');
    return this.payments.status(id);
  }
  @Put() async save(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    await this.owners.venue(actor, id);
    return this.payments.save(id, body, actor);
  }
  @Post('disable') async disable(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.owners.venue(actor, id);
    return this.payments.disable(id, actor);
  }
}
@Controller('platform/venues/:venueId/payments/bog')
@UseGuards(PlatformAuthGuard)
export class PlatformPaymentsController {
  constructor(private readonly payments: PaymentIntegrationsService) {}
  @Get() status(@Param('venueId') id: string) {
    return this.payments.status(id);
  }
}
