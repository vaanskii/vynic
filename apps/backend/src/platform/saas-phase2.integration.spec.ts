import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import request from 'supertest';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { PlatformCommercialController } from './platform-commercial.controller';
import { PlatformCommercialService } from './platform-commercial.service';
import { PlatformVenuesController } from './platform-venues.controller';
import { PlatformOrganizationsController } from './platform-organizations.controller';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { PlatformDeviceService } from './platform-device.service';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformAuditService } from './platform-audit.service';
import { AuthService } from '../auth/auth.service';
import { AuthController } from '../auth/auth.controller';
import { JwtStrategy } from '../auth/jwt.strategy';
import { ManagerTenantService } from '../auth/manager-tenant.service';
import { LoginThrottleService } from '../auth/login-throttle.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { MobileController } from '../mobile/mobile.controller';
import { InventoryService } from '../inventory/inventory.service';
import { RecipeService } from '../inventory/recipe.service';
import { SaleConsumptionService } from '../inventory/sale-consumption.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { FeatureKeys } from '../entitlements/feature-keys';
import { EdgeCommandService } from '../edge/edge-command.service';
import { EdgeTransportController } from '../edge/edge-transport.controller';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { FinanceController } from '../finance/finance.controller';
import { PayrollService } from '../finance/payroll.service';
import { ObligationsService } from '../finance/obligations.service';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'SaaS Phase 2: real HTTP, PostgreSQL and Edge queue',
  () => {
    let db: PrismaService,
      app: any,
      platformAuth: PlatformAuthService,
      entitlements: VenueEntitlementsService;
    let adminToken: string,
      supportToken: string,
      org: any,
      a: any,
      b: any,
      managerA: any,
      managerB: any;
    let tokenA: string, tokenB: string, credential: string, device: any;
    const suffix = randomUUID();
    const pinA = '483921',
      pinB = '571234',
      resetPin = '692481';
    const http = () => request(app.getHttpServer());
    const bearer = (token = adminToken) => ({
      Authorization: `Bearer ${token}`,
    });
    beforeAll(async () => {
      if (!url?.includes('saas_phase2') || url.includes('vankisi_database'))
        throw new Error('Disposable saas_phase2 DB required');
      process.env.JWT_SECRET = 'saas-phase2-disposable-secret';
      process.env.COOKIE_ENCRYPTION_KEY = 'saas-phase2-disposable-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const jwt = new JwtService({ secret: process.env.JWT_SECRET });
      platformAuth = new PlatformAuthService(db, jwt, new ConfigService());
      const audit = new PlatformAuditService(db);
      const directory = new PlatformDirectoryService(db, audit);
      entitlements = new VenueEntitlementsService(db);
      const config = new PlatformVenueConfigService(
        db,
        entitlements,
        directory,
        audit,
      );
      const vault = new StaffPinVault(db);
      const inventory = new InventoryService(db, new RecipeService(db));
      const admin = await db.platformUser.create({
        data: {
          email: `${suffix}@phase2.test`,
          displayName: 'Phase 2 operator',
          passwordHash: await argon2.hash('phase2-disposable-password'),
        },
      });
      adminToken = (
        await platformAuth.login(admin.email, 'phase2-disposable-password')
      ).access_token;
      const providers = new Map<any, any>(
        (
          Reflect.getMetadata('design:paramtypes', MobileController) as any[]
        ).map((type) => [type, {}]),
      );
      for (const [type, value] of [
        [PrismaService, db],
        [JwtService, jwt],
        [PlatformAuthService, platformAuth],
        [PlatformDirectoryService, directory],
        [PlatformVenueConfigService, config],
        [PlatformDeviceService, {}],
        [PlatformCommercialService, new PlatformCommercialService(db, vault)],
        [AuthService, new AuthService(db, jwt)],
        [ManagerTenantService, new ManagerTenantService(db)],
        [LoginThrottleService, new LoginThrottleService()],
        [VenueEntitlementsService, entitlements],
        [InventoryService, inventory],
        [RecipeService, new RecipeService(db)],
        [SaleConsumptionService, new SaleConsumptionService(db)],
        [EdgeCommandService, new EdgeCommandService(db)],
        [DeviceCredentialService, new DeviceCredentialService(db)],
        [PayrollService, new PayrollService(db)],
        [ObligationsService, new ObligationsService(db)],
      ])
        providers.set(type, value);
      const module = await Test.createTestingModule({
        imports: [PassportModule],
        controllers: [
          PlatformCommercialController,
          PlatformVenuesController,
          PlatformOrganizationsController,
          AuthController,
          MobileController,
          EdgeTransportController,
          FinanceController,
        ],
        providers: [...providers]
          .map(([provide, useValue]) => ({ provide, useValue }))
          .concat([{ provide: JwtStrategy, useClass: JwtStrategy } as any]),
      }).compile();
      app = module.createNestApplication();
      await app.init();
      org = (
        await http()
          .post('/platform/organizations')
          .set(bearer())
          .send({ name: `Phase 2 ${suffix}` })
          .expect(201)
      ).body;
      for (const name of ['A', 'B']) {
        const venue = (
          await http()
            .post('/platform/venues')
            .set(bearer())
            .send({
              organizationId: org.id,
              name,
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })
            .expect(201)
        ).body;
        const keys =
          name === 'A'
            ? Object.values(FeatureKeys)
            : [FeatureKeys.POS, FeatureKeys.MANAGER_APP];
        const features = await db.feature.findMany({
          where: { key: { in: keys } },
        });
        const plan = await db.plan.create({
          data: {
            key: `${suffix}-${name}`,
            name: `Phase 2 ${name}`,
            features: { create: features.map((f) => ({ featureId: f.id })) },
          },
        });
        await http()
          .put(`/platform/venues/${venue.id}/plan`)
          .set(bearer())
          .send({ planId: plan.id })
          .expect(200);
        const result = (
          await http()
            .post(`/platform/venues/${venue.id}/managers`)
            .set(bearer())
            .send({
              requestId: randomUUID(),
              displayName: 'First manager',
              username: 'manager',
              role: 'MANAGER',
              pin: name === 'A' ? pinA : pinB,
            })
            .expect(201)
        ).body;
        const login = (
          await http()
            .post('/auth/mobile-login')
            .send({
              venueCode: venue.loginCode,
              pin: name === 'A' ? pinA : pinB,
            })
            .expect(200)
        ).body;
        if (name === 'A') {
          a = venue;
          managerA = result.staff;
          tokenA = login.access_token;
        } else {
          b = venue;
          managerB = result.staff;
          tokenB = login.access_token;
        }
      }
      const issued = await new DeviceCredentialService(db).issueCredential({
        venueId: a.id,
        installationId: randomUUID(),
        displayName: 'Disposable POS',
        platform: 'windows',
      });
      credential = issued.credential;
      device = await new DeviceCredentialService(db).verifyCredential(
        credential,
      );
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it('creates Staff through Platform only, durably queues while no POS exists, claims/applies/acks and logs in', async () => {
      expect(managerA.venueId).toBe(a.id);
      expect(managerA).not.toHaveProperty('pinHash');
      expect(managerA).not.toHaveProperty('pin');
      const claimed = (
        await http()
          .post('/edge/commands/claim')
          .set('X-POS-Sync-Key', credential)
          .send({})
          .expect(201)
      ).body.commands;
      expect(claimed).toHaveLength(1);
      expect(claimed[0]).toMatchObject({
        type: 'STAFF_CREATE',
        payload: { username: 'manager', pinCode: pinA },
      });
      // Simulated POS state; the real Hive applier/redelivery is tested in Flutter.
      const posStaff = new Map();
      posStaff.set(claimed[0].payload.username, claimed[0].payload);
      expect(posStaff.get('manager').pinCode).toBe(pinA);
      await http()
        .post('/edge/commands/ack')
        .set('X-POS-Sync-Key', credential)
        .send({ commandId: claimed[0].commandId, status: 'SUCCEEDED' })
        .expect(201);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode: a.loginCode, pin: posStaff.get('manager').pinCode })
        .expect(200);
    });
    it('enforces two-Venue modules and override precedence through real Manager routes', async () => {
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenA))
        .expect(200);
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenB))
        .expect(403);
      await http()
        .get('/mobile/finance/payroll')
        .set(bearer(tokenA))
        .expect(200);
      await http()
        .get('/mobile/finance/payroll')
        .set(bearer(tokenB))
        .expect(403);
      await http()
        .put(`/platform/venues/${b.id}/features/INVENTORY`)
        .set(bearer())
        .send({ effect: 'ENABLED' })
        .expect(200);
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenB))
        .expect(200);
      await http()
        .put(`/platform/venues/${a.id}/features/INVENTORY`)
        .set(bearer())
        .send({ effect: 'DISABLED' })
        .expect(200);
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenA))
        .expect(403);
      await http()
        .delete(`/platform/venues/${a.id}/features/INVENTORY`)
        .set(bearer())
        .expect(200);
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenA))
        .expect(200);
      await http()
        .put(`/platform/venues/${b.id}/features/MANAGER_APP`)
        .set(bearer())
        .send({ effect: 'DISABLED' })
        .expect(200);
      await http()
        .get('/mobile/inventory/stock-items')
        .set(bearer(tokenB))
        .expect(403);
      await http()
        .delete(`/platform/venues/${b.id}/features/MANAGER_APP`)
        .set(bearer())
        .expect(200);
    });
    it('keeps every subscription status explicit and POS authentication independent', async () => {
      for (const status of [
        'TRIAL',
        'ACTIVE',
        'PAST_DUE',
        'SUSPENDED',
        'CANCELLED',
        'ACTIVE',
      ]) {
        await http()
          .put(`/platform/venues/${a.id}/subscription`)
          .set(bearer())
          .send({ status, note: 'Disposable policy proof' })
          .expect(200);
        const allowed = ['TRIAL', 'ACTIVE', 'PAST_DUE'].includes(status);
        await http()
          .get('/mobile/entitlements')
          .set(bearer(tokenA))
          .expect(allowed ? 200 : 401);
        expect(await entitlements.hasFeature(a.id, FeatureKeys.WEBSITE)).toBe(
          allowed,
        );
        expect(await entitlements.hasFeature(a.id, FeatureKeys.POS)).toBe(true);
        expect(
          await new DeviceCredentialService(db).verifyCredential(credential),
        ).toMatchObject({ venueId: a.id });
      }
    });
    it('reset retries converge, stale POS cannot undo credentials, disable keeps identity and rejects current JWT', async () => {
      const requestId = randomUUID();
      const path = `/platform/venues/${a.id}/managers/${managerA.id}/reset`;
      const first = (
        await http()
          .post(path)
          .set(bearer())
          .send({ requestId, pin: resetPin })
          .expect(201)
      ).body;
      const retry = (
        await http()
          .post(path)
          .set(bearer())
          .send({ requestId, pin: resetPin })
          .expect(201)
      ).body;
      expect(retry.delivery.commandId).toBe(first.delivery.commandId);
      await http()
        .post(path)
        .set(bearer())
        .send({ requestId, pin: pinB })
        .expect(409);
      const sync = new StaffSyncService(db, new StaffPinVault(db));
      await sync.sync({ venueId: a.id, organizationId: org.id }, [
        { username: 'manager', role: 'MANAGER', pin: pinA } as any,
      ]);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode: a.loginCode, pin: pinA })
        .expect(401);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode: a.loginCode, pin: resetPin })
        .expect(200);
      await http()
        .post(`/platform/venues/${a.id}/managers/${managerA.id}/disable`)
        .set(bearer())
        .send({ requestId: randomUUID() })
        .expect(201);
      await sync.sync({ venueId: a.id, organizationId: org.id }, [
        { username: 'manager', role: 'MANAGER', pin: resetPin } as any,
      ]);
      await sync.sync({ venueId: a.id, organizationId: org.id }, []);
      expect(
        await db.staff.findUnique({ where: { id: managerA.id } }),
      ).toMatchObject({ isActive: false });
      await http().get('/mobile/entitlements').set(bearer(tokenA)).expect(401);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode: a.loginCode, pin: resetPin })
        .expect(401);
      const queued = await db.edgeCommand.findMany({
        where: { venueId: a.id, status: 'PENDING' },
        orderBy: { createdAt: 'asc' },
      });
      expect(queued.map((c) => c.type)).toEqual([
        'STAFF_CREATE',
        'STAFF_DELETE',
      ]);
      const events = await db.platformAuditEvent.findMany({
        where: { targetId: a.id },
      });
      expect(JSON.stringify(events)).not.toContain(resetPin);
      expect(JSON.stringify(events)).not.toContain(pinA);
      expect(events.map((e) => e.action)).toEqual(
        expect.arrayContaining([
          'venue.manager_create',
          'venue.manager_reset',
          'venue.manager_disable',
          'venue.subscription_changed',
        ]),
      );
    });
    it('rejects tenant token control-plane access and foreign Staff targets; support cannot mutate', async () => {
      await http()
        .put(`/platform/venues/${a.id}/subscription`)
        .set(bearer(tokenB))
        .send({ status: 'ACTIVE' })
        .expect(401);
      await http()
        .post(`/platform/venues/${b.id}/managers/${managerA.id}/disable`)
        .set(bearer())
        .send({ requestId: randomUUID() })
        .expect(404);
      const support = (
        await http()
          .post('/platform/users')
          .set(bearer())
          .send({
            email: `support-${suffix}@phase2.test`,
            displayName: 'Support',
            password: 'support-disposable-password',
            role: 'SUPPORT_READONLY',
          })
          .expect(201)
      ).body;
      expect(support).not.toHaveProperty('passwordHash');
      supportToken = (
        await platformAuth.login(support.email, 'support-disposable-password')
      ).access_token;
      await http()
        .get(`/platform/venues/${b.id}/managers`)
        .set(bearer(supportToken))
        .expect(200);
      await http()
        .put(`/platform/venues/${b.id}/subscription`)
        .set(bearer(supportToken))
        .send({ status: 'CANCELLED' })
        .expect(403);
      await http()
        .put(`/platform/venues/${b.id}/features/INVENTORY`)
        .set(bearer(supportToken))
        .send({ effect: 'DISABLED' })
        .expect(403);
      await http()
        .post(`/platform/venues/${b.id}/managers`)
        .set(bearer(supportToken))
        .send({})
        .expect(403);
      await http()
        .post(`/platform/users/${support.id}/disable`)
        .set(bearer())
        .expect(201);
      await http().get('/platform/users').set(bearer(supportToken)).expect(401);
    });
  },
);
