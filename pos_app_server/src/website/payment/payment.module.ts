import { Module, forwardRef } from '@nestjs/common';
import { WebsiteMenuModule } from '../menu/menu.module';
import { WebsiteReservationModule } from '../reservation/reservation.module';
import { BogController } from './payment.controller';
import { BogService } from './payment.service';

@Module({
  imports: [WebsiteMenuModule, forwardRef(() => WebsiteReservationModule)],
  controllers: [BogController],
  providers: [BogService],
  exports: [BogService],
})
export class WebsitePaymentModule {}
