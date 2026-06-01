import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaService } from './prisma.service';
import { MobileController } from './mobile.controller';
import { SyncController } from './sync.controller';
import { MonitoringGateway } from './monitoring.gateway';
import { AuthModule } from './auth/auth.module';
import { PresenceService } from './presence.service';
import { HybridNotificationService } from './hybrid-notification.service';
import { PosSyncGuard } from './auth/pos-sync.guard';
import { PosOutboxService } from './pos-outbox.service';

@Module({
  imports: [AuthModule],
  controllers: [AppController, MobileController, SyncController],
  providers: [
    AppService,
    PrismaService,
    PresenceService,
    HybridNotificationService,
    MonitoringGateway,
    PosSyncGuard,
    PosOutboxService,
  ],
})
export class AppModule {}

