import { Global, Module } from '@nestjs/common';
import { AuthModule } from '../../auth/auth.module';
import { HybridNotificationService } from '../../hybrid-notification.service';
import { MonitoringGateway } from '../../monitoring.gateway';
import { PresenceService } from '../../presence.service';

@Global()
@Module({
  imports: [AuthModule],
  providers: [PresenceService, HybridNotificationService, MonitoringGateway],
  exports: [MonitoringGateway, HybridNotificationService, PresenceService],
})
export class RealtimeModule {}
