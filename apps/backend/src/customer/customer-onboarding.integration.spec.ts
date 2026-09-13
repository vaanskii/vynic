import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import request from 'supertest';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { CustomerAuth, CustomerGuard } from './customer-auth';
import { CustomerService } from './customer.service';
import {
  CustomerAuthController,
  CustomerController,
  PlatformOnboardingController,
  DeviceRuntimeConfigController,
} from './customer.controller';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { PlatformAuthService } from '../platform/platform-auth.service';
import { PlatformAuditService } from '../platform/platform-audit.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { DeviceEnrollmentService } from '../edge/device-enrollment.service';
import { DeviceEnrollmentController } from '../edge/device-enrollment.controller';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { AuthController } from '../auth/auth.controller';
import { AuthService } from '../auth/auth.service';
import { LoginThrottleService } from '../auth/login-throttle.service';
import { JwtStrategy } from '../auth/jwt.strategy';
import { ManagerTenantService } from '../auth/manager-tenant.service';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Customer onboarding: two isolated owners, real HTTP and PostgreSQL',
  () => {
    let db: PrismaService, app: any, operator: string;
    const tag = randomUUID();
    const owners: any[] = [];
    const http = () => request(app.getHttpServer());
    const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
    beforeAll(async () => {
      if (!url?.includes('phase3') || url.includes('vankisi_database'))
        throw Error('Use disposable phase3 DB');
      process.env.JWT_SECRET = 'phase3-test-only-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'phase3-test-only-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const jwt = new JwtService({ secret: process.env.JWT_SECRET });
      const vault = new StaffPinVault(db);
      const credentials = new DeviceCredentialService(db);
      const audit = new PlatformAuditService(db);
      const limiter = new EnrollmentRateLimiter();
      const enrollment = new DeviceEnrollmentService(
        db,
        credentials,
        audit,
        limiter,
      );
      const entitlements = new VenueEntitlementsService(db);
      const commercial = new PlatformCommercialService(db, vault);
      const auth = new CustomerAuth(db, jwt, limiter);
      const service = new CustomerService(
        db,
        entitlements,
        commercial,
        enrollment,
      );
      const platformAuth = new PlatformAuthService(
        db,
        jwt,
        new ConfigService(),
      );
      const admin = await db.platformUser.create({
        data: {
          email: `operator-${tag}@test.invalid`,
          displayName: 'Test operator',
          passwordHash: await argon2.hash('test-only-operator-password'),
        },
      });
      operator = (
        await platformAuth.login(admin.email, 'test-only-operator-password')
      ).access_token;
      const providers: any[] = [
        [PrismaService, db],
        [JwtService, jwt],
        [CustomerAuth, auth],
        [CustomerService, service],
        [PlatformAuthService, platformAuth],
        [DeviceEnrollmentService, enrollment],
        [DeviceCredentialService, credentials],
        [VenueEntitlementsService, entitlements],
        [AuthService, new AuthService(db, jwt)],
        [LoginThrottleService, new LoginThrottleService()],
        [ManagerTenantService, new ManagerTenantService(db)],
      ];
      const module = await Test.createTestingModule({
        imports: [PassportModule],
        controllers: [
          CustomerAuthController,
          CustomerController,
          PlatformOnboardingController,
          DeviceRuntimeConfigController,
          DeviceEnrollmentController,
          AuthController,
        ],
        providers: [
          ...providers.map(([provide, useValue]) => ({ provide, useValue })),
          CustomerGuard,
          JwtStrategy,
        ],
      }).compile();
      app = module.createNestApplication();
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });
    it('requires an operator-selected trial plan and leaves existing Venues unclaimed', async () => {
      const existing = await db.venue.findFirst({
        where: { loginCode: 'vankisi' },
      });
      if (existing)
        expect(
          await db.customerAccount.count({
            where: { organizationId: existing.organizationId },
          }),
        ).toBe(0);
      await db.onboardingPolicy.upsert({
        where: { id: 'default' },
        create: { enabled: false },
        update: { enabled: false },
      });
      await http()
        .post('/customer/auth/signup')
        .send({
          email: `closed-${tag}@test.invalid`,
          displayName: 'Closed',
          password: 'a sufficiently long password',
        })
        .expect(503);
      const plan = await db.plan.create({
        data: {
          key: `pilot-${tag}`,
          name: 'Test trial',
          features: {
            create: [
              { feature: { connect: { key: 'POS' } } },
              { feature: { connect: { key: 'MANAGER_APP' } } },
              { feature: { connect: { key: 'INVENTORY' } } },
            ],
          },
        },
      });
      await http()
        .put('/platform/onboarding/policy')
        .set(bearer(operator))
        .send({
          enabled: true,
          trialPlanId: plan.id,
          trialDays: 14,
          releaseLinks: {},
        })
        .expect(200);
    });
    it('signs up, creates restaurants, Managers, enrollment codes and independent Device credentials', async () => {
      for (const letter of ['a', 'b']) {
        const credentials = {
          displayName: `Owner ${letter}`,
          email: `${letter}-${tag}@test.invalid`,
          password: 'long customer test passphrase',
        };
        const registered = (
          await http()
            .post('/customer/auth/signup')
            .send(credentials)
            .expect(201)
        ).body;
        expect(registered.account.emailVerifiedAt).toBeNull();
        expect(JSON.stringify(registered)).not.toContain('passwordHash');
        const token = registered.access_token;
        const venue = (
          await http()
            .post('/customer/venues')
            .set(bearer(token))
            .send({
              name: `Restaurant ${letter}`,
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })
            .expect(201)
        ).body;
        const retry = (
          await http()
            .post('/customer/venues')
            .set(bearer(token))
            .send({ name: `Restaurant ${letter}` })
            .expect(201)
        ).body;
        expect(retry.id).toBe(venue.id);
        const manager = (
          await http()
            .post(`/customer/venues/${venue.id}/managers`)
            .set(bearer(token))
            .send({
              requestId: randomUUID(),
              displayName: 'First Manager',
              username: 'manager',
              role: 'MANAGER',
              pin: '481259',
            })
            .expect(201)
        ).body;
        expect(manager.staff.venueId).toBe(venue.id);
        const code = (
          await http()
            .post(`/customer/venues/${venue.id}/enrollments`)
            .set(bearer(token))
            .send({})
            .expect(201)
        ).body;
        const installationId = randomUUID();
        const enrolled = (
          await http()
            .post('/edge/enroll')
            .send({
              enrollmentCode: code.code,
              installationId,
              platform: 'WINDOWS',
            })
            .expect(201)
        ).body;
        expect(enrolled.venue.id).toBe(venue.id);
        expect(enrolled.device.status).toBe('ACTIVE');
        await http()
          .post('/edge/enroll')
          .send({
            enrollmentCode: code.code,
            installationId: randomUUID(),
            platform: 'WINDOWS',
          })
          .expect(409);
        const login = (
          await http()
            .post('/auth/mobile-login')
            .send({ venueCode: venue.loginCode, pin: '481259' })
            .expect(200)
        ).body;
        owners.push({
          token,
          venue,
          manager,
          device: enrolled.device,
          credential: enrolled.credential,
          managerToken: login.access_token,
        });
        const portal = (
          await http().get('/customer/portal').set(bearer(token)).expect(200)
        ).body;
        expect(portal.venues).toHaveLength(1);
        expect(portal.venues[0].subscription.status).toBe('TRIAL');
        expect(portal.venues[0].ready).toBe(false);
      }
      expect(owners[0].venue.loginCode).not.toBe(owners[1].venue.loginCode);
    });
    it('rejects cross-tenant portal, access, enrollment and printer requests and principal substitution', async () => {
      const [a, b] = owners;
      const portal = (await http().get('/customer/portal').set(bearer(a.token)).expect(200)).body;
      expect(portal.venues.map((entry: any) => entry.venue.loginCode)).toEqual([a.venue.loginCode]);
      expect(JSON.stringify(portal)).not.toContain(b.venue.loginCode);
      await http()
        .get(`/customer/venues/${b.venue.id}`)
        .set(bearer(a.token))
        .expect(404);
      await http()
        .post(`/customer/venues/${b.venue.id}/enrollments`)
        .set(bearer(a.token))
        .send({})
        .expect(404);
      await http()
        .post(
          `/customer/venues/${b.venue.id}/managers/${b.manager.staff.id}/reset`,
        )
        .set(bearer(a.token))
        .send({ requestId: randomUUID(), pin: '123456' })
        .expect(404);
      await http()
        .put(`/customer/venues/${a.venue.id}/devices/${b.device.id}/printers`)
        .set(bearer(a.token))
        .send({
          kitchen: { enabled: true, host: '192.168.1.10', port: 9100 },
          receipt: { enabled: false, host: '', port: 9100 },
        })
        .expect(404);
      await http()
        .get('/platform/onboarding/policy')
        .set(bearer(a.token))
        .expect(401);
      await http().get('/customer/portal').set(bearer(operator)).expect(401);
      await http()
        .get('/customer/portal')
        .set(bearer(a.managerToken))
        .expect(401);
    });
    it('delivers only the authenticated Device configuration, with no LAN call or secret readback', async () => {
      const [a, b] = owners;
      const printers = {
        kitchen: { enabled: true, host: '192.168.1.10', port: 9200 },
        receipt: { enabled: false, host: '', port: 9100 },
      };
      await http()
        .put(`/customer/venues/${a.venue.id}/devices/${a.device.id}/printers`)
        .set(bearer(a.token))
        .send(printers)
        .expect(200);
      const read = async (o: any) =>
        (
          await http()
            .get('/edge/runtime-config')
            .set('X-POS-Sync-Key', o.credential)
            .expect(200)
        ).body;
      expect((await read(a)).device.runtimeConfig.printers).toEqual(printers);
      expect((await read(b)).device.runtimeConfig).toBeNull();
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'INVENTORY' },
      });
      await db.venueFeatureOverride.create({
        data: {
          venueId: b.venue.id,
          featureId: feature.id,
          effect: 'DISABLED',
        },
      });
      expect((await read(a)).features).toContain('INVENTORY');
      expect((await read(b)).features).not.toContain('INVENTORY');
      const events = await db.customerAuditEvent.findMany({
        where: { targetId: a.device.id, action: 'device.printers_changed' },
      });
      expect(events).toHaveLength(1);
      expect(JSON.stringify(events)).not.toContain('481259');
    });
    it('cancels codes and re-resolves disabled owners, with bounded login attempts', async () => {
      const [a, b] = owners;
      const code = (
        await http()
          .post(`/customer/venues/${a.venue.id}/enrollments`)
          .set(bearer(a.token))
          .send({})
          .expect(201)
      ).body;
      await http()
        .post(`/customer/venues/${a.venue.id}/enrollments/${code.id}/cancel`)
        .set(bearer(a.token))
        .send({})
        .expect(201);
      await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: code.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        })
        .expect(401);
      const owner = await db.customerAccount.findFirstOrThrow({
        where: { organizationId: b.venue.organizationId },
      });
      await db.customerAccount.update({
        where: { id: owner.id },
        data: { isActive: false },
      });
      await http().get('/customer/portal').set(bearer(b.token)).expect(401);
      let last = 0;
      for (let i = 0; i < 12; i++)
        last = (
          await http()
            .post('/customer/auth/login')
            .send({
              email: 'unknown@test.invalid',
              password: 'incorrect password',
            })
        ).status;
      expect(last).toBe(429);
    });
  },
);
