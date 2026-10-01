import { randomUUID } from 'node:crypto';
import { PrismaService } from '../src/prisma.service';
import { onboardingApp } from './onboarding-app.fixture';
import { isFreshDisposableDatabase } from './disposable-database';
import { seedMenu03 } from './menu03.fixture';
import { SyncController } from '../src/pos/sync/sync.controller';
import { IngestPosSnapshotService } from '../src/pos/sync/application/ingest-pos-snapshot.service';
import { IngestAuditReportsService } from '../src/pos/sync/application/ingest-audit-reports.service';
import { PosConnectionRegistry } from '../src/pos/sync/pos-connection.registry';
import { PosCallbackClient } from '../src/pos/pos-callback.client';
import { PosOutboxService } from '../src/pos/pos-outbox.service';
import { MonitoringGateway } from '../src/realtime/monitoring.gateway';
import { LegacyPosTenantService } from '../src/auth/legacy-pos-tenant.service';
import { MenuSyncService } from '../src/pos/sync/snapshot/menu-sync.service';
import { TableSyncService } from '../src/pos/sync/snapshot/table-sync.service';
import { OrderSyncService } from '../src/pos/sync/snapshot/order-sync.service';
import { ReservationSyncService } from '../src/pos/sync/snapshot/reservation-sync.service';
import { StaffSyncService } from '../src/pos/sync/snapshot/staff-sync.service';
import { BusinessDaySyncService } from '../src/pos/sync/snapshot/business-day-sync.service';
import { SyncBroadcastService } from '../src/pos/sync/snapshot/sync-broadcast.service';
import { SaleLedgerSyncService } from '../src/pos/sync/snapshot/sale-ledger-sync.service';
import { DeviceRuntimeConfigController } from '../src/customer/customer.controller';

/** Real guards and persistence; notification sinks have no external workers. */
export async function menu09App(url: string) {
  if (!isFreshDisposableDatabase(url))
    throw Error('Disposable database required');
  process.env.JWT_SECRET = 'menu09-disposable-only';
  process.env.COOKIE_ENCRYPTION_KEY = 'menu09-disposable-only';
  const db = new PrismaService({ datasourceUrl: url });
  const app = await onboardingApp(db, undefined, {
    controllers: [SyncController, DeviceRuntimeConfigController],
    providers: [
      IngestPosSnapshotService,
      IngestAuditReportsService,
      PosConnectionRegistry,
      PosCallbackClient,
      LegacyPosTenantService,
      MenuSyncService,
      TableSyncService,
      OrderSyncService,
      ReservationSyncService,
      StaffSyncService,
      BusinessDaySyncService,
      SyncBroadcastService,
      SaleLedgerSyncService,
      {
        provide: PosOutboxService,
        useValue: { kickPending: () => Promise.resolve() },
      },
      {
        provide: MonitoringGateway,
        useValue: { broadcastUpdate: () => undefined },
      },
    ],
  });
  await app.listen(0, '127.0.0.1');
  return { db, app, base: await app.getUrl() };
}

export async function seedMenu09(live: Awaited<ReturnType<typeof menu09App>>) {
  const seeded = await seedMenu03(live.db, live.app);
  for (const venue of seeded.venues) {
    const assignment = await live.db.venuePlanAssignment.findUniqueOrThrow({
      where: { venueId: venue.venueId },
    });
    const feature = await live.db.feature.upsert({
      where: { key: 'POS' },
      create: { key: 'POS', name: 'POS' },
      update: {},
    });
    await live.db.planFeature.upsert({
      where: {
        planId_featureId: { planId: assignment.planId, featureId: feature.id },
      },
      create: { planId: assignment.planId, featureId: feature.id },
      update: {},
    });
  }
  await live.db.venue.update({
    where: { id: seeded.venues[1].venueId },
    data: { menuAuthority: 'POS' },
  });
  return seeded;
}

export async function menu09Http(
  base: string,
  path: string,
  credential?: string,
  body?: unknown,
  owner = false,
  client?: unknown,
) {
  const response = await fetch(base + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(credential
        ? owner
          ? { Authorization: `Bearer ${credential}` }
          : { 'X-POS-Sync-Key': credential }
        : {}),
      ...(client ? { 'X-Vynic-Menu-Client': JSON.stringify(client) } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return {
    status: response.status,
    body: (await response.json()) as Record<string, unknown>,
  };
}

export function menu09Snapshot(price = 10) {
  return [
    {
      id: randomUUID(),
      slug: 'synthetic',
      nameKa: 'Synthetic',
      nameEn: 'Synthetic',
      items: [
        {
          id: randomUUID(),
          nameKa: 'Synthetic dish',
          nameEn: 'Synthetic dish',
          price,
        },
      ],
    },
  ];
}
