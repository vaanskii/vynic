import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { PosSyncGuard } from './auth/pos-sync.guard';
import { MobileController } from './mobile/mobile.controller';
import { MobileUsersService } from './mobile/services/mobile-users.service';
import { MobileReportsService } from './mobile/services/mobile-reports.service';
import { MobileDevicesService } from './mobile/services/mobile-devices.service';
import { MobileMenuService } from './mobile/services/mobile-menu.service';
import { PosCallbackModule } from './pos/pos-callback.module';
import { PosOutboxService } from './pos/pos-outbox.service';
import { PrismaModule } from './shared/prisma/prisma.module';
import { BootstrapModule } from './shared/bootstrap/bootstrap.module';
import { SyncController } from './pos/sync.controller';
import { RealtimeModule } from './realtime/realtime.module';
import { WebsiteModule } from './website/website.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    BootstrapModule,
    AuthModule,
    RealtimeModule,
    PosCallbackModule,
    WebsiteModule,
  ],
  controllers: [AppController, MobileController, SyncController],
  providers: [
    AppService,
    PosSyncGuard,
    PosOutboxService,
    MobileUsersService,
    MobileReportsService,
    MobileDevicesService,
    MobileMenuService,
  ],
})
export class AppModule {}
