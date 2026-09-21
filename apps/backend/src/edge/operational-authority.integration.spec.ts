import 'reflect-metadata';
jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
import { randomUUID } from 'node:crypto';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import {
  LegacyPosTenantService,
  BOOTSTRAP_VENUE_ID,
} from '../auth/legacy-pos-tenant.service';
import { PosSyncGuard } from '../auth/pos-sync.guard';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { SyncController } from '../pos/sync/sync.controller';
import { IngestPosSnapshotService } from '../pos/sync/application/ingest-pos-snapshot.service';
import { IngestAuditReportsService } from '../pos/sync/application/ingest-audit-reports.service';
import { PosConnectionRegistry } from '../pos/sync/pos-connection.registry';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';
import { OrderSyncService } from '../pos/sync/snapshot/order-sync.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { BusinessDaySyncService } from '../pos/sync/snapshot/business-day-sync.service';
import { ReservationSyncService } from '../pos/sync/snapshot/reservation-sync.service';
import { SaleLedgerSyncService } from '../pos/sync/snapshot/sale-ledger-sync.service';
import { SyncBroadcastService } from '../pos/sync/snapshot/sync-broadcast.service';
import { EdgeCommandService } from './edge-command.service';
import { EdgeTransportController } from './edge-transport.controller';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { InventoryService } from '../inventory/inventory.service';
import { SaleConsumptionService } from '../inventory/sale-consumption.service';
import { PlatformVenuesController } from '../platform/platform-venues.controller';
import { PlatformDeviceService } from '../platform/platform-device.service';
import { PlatformDirectoryService } from '../platform/platform-directory.service';
import { PlatformVenueConfigService } from '../platform/platform-venue-config.service';
import { PlatformAuthService } from '../platform/platform-auth.service';
import { PlatformAuditService } from '../platform/platform-audit.service';
import { DeviceEnrollmentService } from './device-enrollment.service';
import { EnrollmentRateLimiter } from './enrollment-rate-limiter';
import { PosOutboxService } from '../pos/pos-outbox.service';
import { withOperationalAuthority } from './operational-authority';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Phase 0 primary authority — HTTP/PostgreSQL',
  () => {
    let db: PrismaService,
      app: any,
      credentials: DeviceCredentialService,
      commands: EdgeCommandService;
    let a: any, secondary: any, b: any, org: any, admin: any, token: string;
    let venueA: string, venueB: string, emptyVenue: string;
    const tag = randomUUID();
    const gateway = { broadcastUpdate: jest.fn() };
    const http = () => request(app.getHttpServer());
    const sync = (device: any, body: any) =>
      http()
        .post('/sync/manager-data')
        .set('x-pos-sync-key', device.credential)
        .send(body);
    const claim = (device: any) =>
      http()
        .post('/edge/commands/claim')
        .set('x-pos-sync-key', device.credential)
        .send({});
    const select = (id: string, expectedDeviceId: string | null, extra = {}) =>
      http()
        .put(`/platform/venues/${venueA}/operational-primary`)
        .set('Authorization', `Bearer ${token}`)
        .send({
          deviceId: id,
          expectedDeviceId,
          reason: 'Replacement data restored and checked',
          previousPosStopped: true,
          ...extra,
        });
    const snapshot = (total = 20) => ({
      businessDate: '2026-09-19',
      tables: [
        {
          tableId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          tableNumber: '1',
          floor: 'first',
          isReserved: true,
          activeOrderId: 1,
          currentBill: total,
        },
      ],
      orders: [
        {
          posOrderId: 1,
          tableNumber: '1',
          floor: 'first',
          status: 'pending',
          totalAmount: total,
          items: [],
        },
      ],
      reservations: [],
    });
    beforeAll(async () => {
      if (!url?.includes('phase0') || url.includes('vankisi_database'))
        throw Error('Disposable phase0 database required');
      process.env.COOKIE_ENCRYPTION_KEY = 'phase0-test-only-cookie-key';
      process.env.JWT_SECRET = 'phase0-test-only-jwt-key';
      process.env.POS_SYNC_API_KEY = 'phase0-legacy-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      org = await db.organization.create({
        data: {
          name: tag,
          venues: {
            create: ['A', 'B', 'Empty'].map((name) => ({
              name,
              currency: 'GEL',
              timezone: 'Asia/Tbilisi',
            })),
          },
        },
        include: { venues: true },
      });
      [venueA, venueB, emptyVenue] = ['A', 'B', 'Empty'].map(
        (name) => org.venues.find((v: any) => v.name === name).id,
      );
      credentials = new DeviceCredentialService(db);
      const issue = (venueId: string, displayName: string) =>
        credentials.issueCredential({
          venueId,
          displayName,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        });
      a = await issue(venueA, 'A primary');
      secondary = await issue(venueA, 'A secondary');
      b = await issue(venueB, 'B primary');
      commands = new EdgeCommandService(db);
      const audit = new PlatformAuditService(db),
        directory = new PlatformDirectoryService(db, audit);
      const enrollment = new DeviceEnrollmentService(
        db,
        credentials,
        audit,
        new EnrollmentRateLimiter(),
      );
      const devices = new PlatformDeviceService(
        db,
        credentials,
        commands,
        enrollment,
        directory,
        audit,
      );
      const auth = new PlatformAuthService(
        db,
        new JwtService({ secret: process.env.JWT_SECRET }),
        new ConfigService(),
      );
      admin = await db.platformUser.create({
        data: {
          email: `phase0-${tag}@test.invalid`,
          displayName: 'Operator',
          passwordHash: await argon2.hash('phase0-test-password'),
        },
      });
      token = (await auth.login(admin.email, 'phase0-test-password'))
        .access_token;
      const registry = new PosConnectionRegistry(db, {
        setCallbackUrl() {},
        setConnectionKey() {},
        hasCallbackUrl: () => false,
      } as never);
      const ingest = new IngestPosSnapshotService(
        { kickPending: jest.fn() } as never,
        registry,
        new MenuSyncService(db),
        new TableSyncService(db),
        new OrderSyncService(db),
        new ReservationSyncService(db),
        new StaffSyncService(db, new StaffPinVault(db)),
        new BusinessDaySyncService(db),
        new SyncBroadcastService(db, gateway as never),
        new SaleLedgerSyncService(db),
      );
      const providers: any[] = [
        [PrismaService, db],
        [DeviceCredentialService, credentials],
        [LegacyPosTenantService, new LegacyPosTenantService(db)],
        [IngestPosSnapshotService, ingest],
        [
          IngestAuditReportsService,
          new IngestAuditReportsService(db, gateway as never),
        ],
        [PosConnectionRegistry, registry],
        [EdgeCommandService, commands],
        [VenueEntitlementsService, new VenueEntitlementsService(db)],
        [InventoryService, {}],
        [SaleConsumptionService, new SaleConsumptionService(db)],
        [PlatformDeviceService, devices],
        [PlatformDirectoryService, directory],
        [PlatformVenueConfigService, {}],
        [PlatformAuthService, auth],
      ];
      const module = await Test.createTestingModule({
        controllers: [
          SyncController,
          EdgeTransportController,
          PlatformVenuesController,
        ],
        providers: [
          ...providers.map(([provide, useValue]) => ({ provide, useValue })),
          PosSyncGuard,
        ],
      }).compile();
      app = module.createNestApplication();
      await app.init();
    });
    beforeEach(async () => {
      await db.venue.update({
        where: { id: venueA },
        data: { activeOperationalDeviceId: a.deviceId },
      });
      await db.edgeCommand.deleteMany({
        where: { venueId: { in: [venueA, venueB] } },
      });
      gateway.broadcastUpdate.mockClear();
    });
    afterAll(async () => {
      if (app) await app.close();
      if (!db) return;
      const ids = [venueA, venueB, emptyVenue].filter(Boolean);
      await db.edgeCommand.deleteMany({ where: { venueId: { in: ids } } });
      await db.orderItem.deleteMany({
        where: { order: { venueId: { in: ids } } },
      });
      await db.order.deleteMany({ where: { venueId: { in: ids } } });
      await db.table.deleteMany({ where: { venueId: { in: ids } } });
      await db.posReservation.deleteMany({ where: { venueId: { in: ids } } });
      await db.setting.deleteMany({ where: { venueId: { in: ids } } });
      await db.staff.deleteMany({ where: { venueId: { in: ids } } });
      await db.menuCategory.deleteMany({ where: { venueId: { in: ids } } });
      await db.deviceEnrollment.deleteMany({ where: { venueId: { in: ids } } });
      await db.device.deleteMany({ where: { venueId: { in: ids } } });
      await db.venue.deleteMany({ where: { id: { in: ids } } });
      if (org) await db.organization.delete({ where: { id: org.id } });
      if (admin) {
        await db.platformAuditEvent.deleteMany({
          where: { platformUserId: admin.id },
        });
        await db.platformUser.delete({ where: { id: admin.id } });
      }
      await db.$disconnect();
    });
    it('keeps zero-Device Venue valid and automatically selects only the first Device', async () => {
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: emptyVenue } }))
          .activeOperationalDeviceId,
      ).toBeNull();
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: venueB } }))
          .activeOperationalDeviceId,
      ).toBe(b.deviceId);
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: venueA } }))
          .activeOperationalDeviceId,
      ).toBe(a.deviceId);
    });
    it('accepts primary sync; rejects secondary overwrite, omission delete, realtime and rollover', async () => {
      await sync(a, snapshot()).expect(201);
      const original = await db.order.findFirstOrThrow({
        where: { venueId: venueA, posOrderId: 1 },
      });
      await sync(secondary, snapshot(999)).expect(403);
      await sync(secondary, {
        businessDate: '2026-09-20',
        orders: [],
        tables: [],
        reservations: [],
      }).expect(403);
      await sync(secondary, { ...snapshot(0), realtimeOnly: true }).expect(403);
      expect(await db.order.findUnique({ where: { id: original.id } })).toEqual(
        original,
      );
      expect(
        (await db.table.findFirstOrThrow({ where: { venueId: venueA } }))
          .isReserved,
      ).toBe(true);
      expect(
        (
          await db.device.findUniqueOrThrow({
            where: { id: secondary.deviceId },
          })
        ).firstSyncAt,
      ).toBeNull();
    });
    it('preserves primary menu, Staff and reservation reconciliation', async () => {
      const reservation = {
        id: randomUUID(),
        customerName: 'Fixture booking',
        customerPhone: '555000000',
        reservationDate: '2026-09-19',
        reservationTime: '18:00',
        guestCount: 2,
        tableNumbers: ['1'],
        status: 'pending',
      };
      await sync(a, {
        ...snapshot(),
        menu: [{ slug: 'phase0-drinks', nameKa: 'სასმელი', nameEn: 'Drinks' }],
        staff: [{ username: 'phase0-waiter', role: 'WAITER', pin: '1234' }],
        reservations: [reservation],
      }).expect(201);
      expect(
        await db.menuCategory.count({
          where: { venueId: venueA, slug: 'phase0-drinks' },
        }),
      ).toBe(1);
      expect(
        await db.staff.count({
          where: { venueId: venueA, username: 'phase0-waiter' },
        }),
      ).toBe(1);
      expect(
        await db.posReservation.count({ where: { venueId: venueA } }),
      ).toBe(1);
      await sync(secondary, { reservations: [] }).expect(403);
      expect(
        await db.posReservation.count({ where: { venueId: venueA } }),
      ).toBe(1);
      await sync(a, { reservations: [] }).expect(201);
      expect(
        await db.posReservation.count({ where: { venueId: venueA } }),
      ).toBe(0);
    });
    it('allows safe targeted NOOP; secondary cannot claim untargeted or business work', async () => {
      for (const [key, deviceId, type] of [
        ['wide', null, 'NOOP'],
        ['target', secondary.deviceId, 'NOOP'],
        ['business', secondary.deviceId, 'ORDER_CANCEL'],
      ] as const)
        await commands.enqueue(
          { venueId: venueA },
          { idempotencyKey: key, deviceId, type, payload: {} },
        );
      const response = await claim(secondary).expect(201);
      expect(response.body.commands.map((c: any) => c.idempotencyKey)).toEqual([
        'target',
      ]);
      await http()
        .post('/edge/commands/ack')
        .set('x-pos-sync-key', secondary.credential)
        .send({
          commandId: response.body.commands[0].commandId,
          status: 'SUCCEEDED',
        })
        .expect(201);
      expect(
        (await claim(a).expect(201)).body.commands.map(
          (c: any) => c.idempotencyKey,
        ),
      ).toEqual(['wide']);
    });
    it('replaces A with B through HTTP, audits it, fences A and holds uncertain work', async () => {
      const queued = await commands.enqueue(
        { venueId: venueA },
        { type: 'NOOP', payload: {}, idempotencyKey: 'inflight' },
      );
      await claim(a).expect(201);
      await select(secondary.deviceId, a.deviceId).expect(200);
      await sync(a, snapshot(999)).expect(403);
      await sync(secondary, snapshot(30)).expect(201);
      expect((await claim(a).expect(201)).body.commands).toEqual([]);
      await http()
        .post('/edge/commands/ack')
        .set('x-pos-sync-key', a.credential)
        .send({ commandId: queued.id, status: 'SUCCEEDED' })
        .expect(403);
      expect(
        (await db.edgeCommand.findUniqueOrThrow({ where: { id: queued.id } }))
          .resultCode,
      ).toBe('primary_replaced_outcome_unknown');
      expect(await db.device.count({ where: { id: a.deviceId } })).toBe(1);
      expect(
        await db.platformAuditEvent.findFirst({
          where: {
            targetId: venueA,
            action: 'venue.operational_primary_changed',
          },
        }),
      ).toMatchObject({
        metadata: expect.objectContaining({
          from: a.deviceId,
          to: secondary.deviceId,
        }),
      });
    });
    it('rejects stale selection, unconfirmed replacement and other-Venue target', async () => {
      await select(secondary.deviceId, null).expect(409);
      await select(secondary.deviceId, a.deviceId, {
        previousPosStopped: false,
      }).expect(400);
      await select(b.deviceId, a.deviceId).expect(404);
      await http()
        .put(`/platform/venues/${venueA}/operational-primary`)
        .send({})
        .expect(401);
    });
    it('isolates another Venue and ignores forged payload tenant identity', async () => {
      await sync(b, { ...snapshot(55), tables: [], venueId: venueA }).expect(
        201,
      );
      expect(
        (
          await db.order.findFirstOrThrow({
            where: { venueId: venueB, posOrderId: 1 },
          })
        ).totalAmount,
      ).toBe(55);
      await commands.enqueue(
        { venueId: venueA },
        { type: 'NOOP', payload: {}, idempotencyKey: 'only-A' },
      );
      expect((await claim(b).expect(201)).body.commands).toEqual([]);
    });
    it('rejects secondary audit and stock intent writes before processing payloads', async () => {
      for (const path of [
        '/sync/audit-reports',
        '/sync/audit-logs',
        '/edge/inventory/consumption',
      ])
        await http()
          .post(path)
          .set('x-pos-sync-key', secondary.credential)
          .send({})
          .expect(403);
    });
    it('requires explicit selection when authority is null; polling never elects a device', async () => {
      await db.venue.update({
        where: { id: venueA },
        data: { activeOperationalDeviceId: null },
      });
      await sync(a, {}).expect(403);
      await sync(secondary, {}).expect(403);
      await commands.enqueue(
        { venueId: venueA },
        { type: 'NOOP', payload: {}, idempotencyKey: 'ambiguous' },
      );
      expect((await claim(a).expect(201)).body.commands).toEqual([]);
      await select(a.deviceId, null).expect(200);
      expect((await claim(a).expect(201)).body.commands).toHaveLength(1);
    });
    it('waits for admitted upload before replacing primary', async () => {
      let admit!: () => void, release!: () => void;
      const admitted = new Promise<void>((resolve) => {
        admit = resolve;
      });
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      const upload = withOperationalAuthority(
        db,
        { venueId: venueA, deviceId: a.deviceId },
        async (tx) => {
          admit();
          await released;
          await tx.setting.upsert({
            where: { venueId_key: { venueId: venueA, key: 'phase0-race' } },
            create: {
              venueId: venueA,
              key: 'phase0-race',
              value: 'before switch',
            },
            update: { value: 'before switch' },
          });
        },
      );
      await admitted;
      let switched = false;
      const replacement = select(secondary.deviceId, a.deviceId).then(
        (response) => {
          switched = true;
          return response;
        },
      );
      await new Promise((resolve) => setTimeout(resolve, 100));
      expect(switched).toBe(false);
      release();
      await upload;
      expect((await replacement).status).toBe(200);
      await sync(a, {}).expect(403);
    });
    it('rolls back earlier writes on failed ingestion without success broadcast', async () => {
      const before = await db.order.findFirstOrThrow({
        where: { venueId: venueA, posOrderId: 1 },
      });
      await sync(a, {
        ...snapshot(777),
        expenses: [{ id: randomUUID(), amount: 'invalid-number' }],
      }).expect(500);
      expect(await db.order.findUnique({ where: { id: before.id } })).toEqual(
        before,
      );
      expect(gateway.broadcastUpdate).not.toHaveBeenCalled();
    });
    it('does not deliver old legacy outbox work to an enrolled Venue', async () => {
      const callback = { hasCallbackUrl: () => true, deliverToPos: jest.fn() };
      const row = await db.posCallbackOutbox.create({
        data: {
          venueId: venueA,
          endpoint: '/order-cancel',
          payload: { posOrderId: 1 },
        },
      });
      try {
        await new PosOutboxService(db, callback as never).processDue({
          venueId: venueA,
        });
        expect(callback.deliverToPos).not.toHaveBeenCalled();
        expect(
          (
            await db.posCallbackOutbox.findUniqueOrThrow({
              where: { id: row.id },
            })
          ).lastError,
        ).toBe('primary_pos_enrolled_reconcile_legacy_work');
      } finally {
        await db.posCallbackOutbox.delete({ where: { id: row.id } });
      }
    });
    it('preserves legacy zero-Device sync and fences the shared key after enrollment', async () => {
      expect(
        await db.device.count({ where: { venueId: BOOTSTRAP_VENUE_ID } }),
      ).toBe(0);
      await http()
        .post('/sync/manager-data')
        .set('x-pos-sync-key', 'phase0-legacy-key')
        .send({})
        .expect(201);
      const d = await credentials.issueCredential({
        venueId: BOOTSTRAP_VENUE_ID,
        displayName: 'legacy fixture',
        platform: 'WINDOWS',
        installationId: randomUUID(),
      });
      try {
        await http()
          .post('/sync/manager-data')
          .set('x-pos-sync-key', 'phase0-legacy-key')
          .send({})
          .expect(403);
      } finally {
        await db.device.delete({ where: { id: d.deviceId } });
      }
    });
  },
);
