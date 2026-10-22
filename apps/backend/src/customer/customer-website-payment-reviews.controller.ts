import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { CustomerService } from './customer.service';
import {
  CustomerActor,
  CustomerGuard,
  type CustomerPrincipal,
} from './customer-auth';
import { requireUuid } from '../platform/platform-validation';
import { websitePaymentReviews } from '../website/payment/website-payment-reviews';

@Controller('customer/venues/:venueId/website-payment-reviews')
@UseGuards(CustomerGuard)
export class CustomerWebsitePaymentReviewsController {
  constructor(
    private readonly db: PrismaService,
    private readonly owners: CustomerService,
  ) {}
  @Get()
  async read(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') input: string,
    @Query('offset') offset?: string,
  ) {
    const venueId = requireUuid(input, 'venueId');
    await this.owners.venue(actor, venueId);
    // History/reconciliation stays readable after commercial payment access ends.
    return websitePaymentReviews(this.db, venueId, offset);
  }
}
