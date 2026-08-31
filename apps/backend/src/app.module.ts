import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { PosSyncGuard } from './auth/pos-sync.guard';
import { EntitlementsModule } from './entitlements/entitlements.module';
import { MobileController } from './mobile/mobile.controller';
import { MobileUsersService } from './mobile/services/mobile-users.service';
import { MobileReportsService } from './mobile/services/mobile-reports.service';
import { MobileDevicesService } from './mobile/services/mobile-devices.service';
import { MobileMenuService } from './mobile/services/mobile-menu.service';
import { MobileMutationSupport } from './mobile/services/mobile-mutation-support.service';
import { MobileReservationsService } from './mobile/services/mobile-reservations.service';
import { MobileDashboardService } from './mobile/services/mobile-dashboard.service';
import { MobileOrdersService } from './mobile/services/mobile-orders.service';
import { PosCallbackModule } from './pos/pos-callback.module';
import { PosOutboxService } from './pos/pos-outbox.service';
import { PrismaModule } from './shared/prisma/prisma.module';
import { BootstrapModule } from './shared/bootstrap/bootstrap.module';
import { SyncController } from './pos/sync/sync.controller';
import { IngestAuditReportsService } from './pos/sync/application/ingest-audit-reports.service';
import { IngestPosSnapshotService } from './pos/sync/application/ingest-pos-snapshot.service';
import { PosConnectionRegistry } from './pos/sync/pos-connection.registry';
import { BusinessDaySyncService } from './pos/sync/snapshot/business-day-sync.service';
import { MenuSyncService } from './pos/sync/snapshot/menu-sync.service';
import { OrderSyncService } from './pos/sync/snapshot/order-sync.service';
import { StaffSyncService } from './pos/sync/snapshot/staff-sync.service';
import { SyncBroadcastService } from './pos/sync/snapshot/sync-broadcast.service';
import { TableSyncService } from './pos/sync/snapshot/table-sync.service';
import { RealtimeModule } from './realtime/realtime.module';
import { WebsiteModule } from './website/website.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    BootstrapModule,
    AuthModule,
    EntitlementsModule,
    RealtimeModule,
    PosCallbackModule,
    WebsiteModule,
  ],
  controllers: [AppController, MobileController, SyncController],
  providers: [
    AppService,
    PosSyncGuard,
    PosOutboxService,
    PosConnectionRegistry,
    IngestPosSnapshotService,
    IngestAuditReportsService,
    MenuSyncService,
    TableSyncService,
    OrderSyncService,
    StaffSyncService,
    BusinessDaySyncService,
    SyncBroadcastService,
    MobileUsersService,
    MobileReportsService,
    MobileDevicesService,
    MobileMenuService,
    MobileMutationSupport,
    MobileReservationsService,
    MobileDashboardService,
    MobileOrdersService,
  ],
})
export class AppModule {}
