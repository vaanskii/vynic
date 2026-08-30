import { Module } from '@nestjs/common';
import { WebsiteAuthModule } from './auth/auth.module';
import { WebsiteMenuModule } from './menu/menu.module';
import { WebsitePaymentModule } from './payment/payment.module';
import { WebsiteReservationModule } from './reservation/reservation.module';
import { WebsiteUserModule } from './user/user.module';

@Module({
  imports: [
    WebsiteAuthModule,
    WebsiteUserModule,
    WebsiteMenuModule,
    WebsiteReservationModule,
    WebsitePaymentModule,
  ],
})
export class WebsiteModule {}
