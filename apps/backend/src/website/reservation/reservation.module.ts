import { Module, forwardRef } from '@nestjs/common';
import { WebsiteAuthModule } from '../auth/auth.module';
import { WebsiteMenuModule } from '../menu/menu.module';
import { WebsitePaymentModule } from '../payment/payment.module';
import { WebsiteTenancyModule } from '../tenancy/website-tenancy.module';
import { TableController } from './reservation.controller';
import { ReservationService } from './reservation.service';
import { WebsitePosReservationBridgeService } from './website-pos-reservation-bridge.service';

@Module({
  imports: [
    WebsiteAuthModule,
    WebsiteMenuModule,
    WebsiteTenancyModule,
    forwardRef(() => WebsitePaymentModule),
  ],
  controllers: [TableController],
  providers: [ReservationService, WebsitePosReservationBridgeService],
  exports: [ReservationService],
})
export class WebsiteReservationModule {}
