import { Module } from '@nestjs/common';
import { WebsiteAuthModule } from './auth/auth.module';
import { CustomWebsiteModule } from './custom/custom-website.module';
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
    CustomWebsiteModule,
  ],
})
export class WebsiteModule {}
