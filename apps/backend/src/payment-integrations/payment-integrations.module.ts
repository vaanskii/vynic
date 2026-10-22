import { Module } from '@nestjs/common';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { PaymentIntegrationsService } from './payment-integrations.service';
@Module({
  imports: [EntitlementsModule],
  providers: [PaymentIntegrationsService],
  exports: [PaymentIntegrationsService],
})
export class PaymentIntegrationsModule {}
