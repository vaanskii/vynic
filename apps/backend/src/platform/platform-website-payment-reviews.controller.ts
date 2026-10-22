import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { PlatformAuthGuard } from './platform-auth.guard';
import { requireUuid } from './platform-validation';
import { websitePaymentReviews } from '../website/payment/website-payment-reviews';

@Controller('platform/venues/:venueId/website-payment-reviews')
@UseGuards(PlatformAuthGuard)
export class PlatformWebsitePaymentReviewsController {
  constructor(private readonly db: PrismaService) {}
  @Get()
  read(@Param('venueId') input: string, @Query('offset') offset?: string) {
    return websitePaymentReviews(
      this.db,
      requireUuid(input, 'venueId'),
      offset,
    );
  }
}
