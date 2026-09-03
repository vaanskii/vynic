import { Module, forwardRef } from '@nestjs/common';
import { WebsiteMenuModule } from '../menu/menu.module';
import { WebsiteReservationModule } from '../reservation/reservation.module';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { BogController } from './payment.controller';
import { BogService } from './payment.service';

@Module({
  imports: [
    WebsiteMenuModule,
    WebsiteTenancyModule,
    forwardRef(() => WebsiteReservationModule),
  ],
  controllers: [BogController],
  providers: [BogService],
  exports: [BogService],
})
export class WebsitePaymentModule {}
