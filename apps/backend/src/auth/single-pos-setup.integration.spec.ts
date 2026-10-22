import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import * as bcrypt from 'bcrypt';
import type { Server } from 'node:http';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { ManagerActivationController } from './manager-activation.controller';
import { ManagerActivationService } from './manager-activation.service';
import { LoginThrottleService } from './login-throttle.service';

const url = process.env.SINGLE_POS_SETUP_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'single POS setup / actual isolated PostgreSQL and HTTP',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      admin: string,
      owner: string,
      ownerId: string,
      venueId: string;
    const originalEnv = { ...process.env };
    const http = () => request(app.getHttpServer() as Server);
    const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });
    type Enrollment = {
      id: string;
      code: string;
      initialManagerSetup: boolean;
    };
    type DeviceReply = {
      credential: string;
      device: { id: string };
      venue: { id: string };
    };
    type Setup = { state: string; setupId: string | null };
    const deviceHeader = (d: DeviceReply) => ({
      'X-POS-Sync-Key': d.credential,
    });
    async function code(
      initialManagerSetup = true,
      token = admin,
      target = venueId,
    ) {
      const response = await http()
        .post(`/platform/venues/${target}/enrollments`)
        .set(bearer(token))
        .send({
          displayName: 'Synthetic POS',
          platform: 'WINDOWS',
          initialManagerSetup,
        })
        .expect(201);
      return response.body as Enrollment;
    }
    async function redeem(
      enrollment: Enrollment,
      installationId = randomUUID(),
      version: number | undefined = 1,
    ) {
      const response = await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: enrollment.code,
          installationId,
          platform: 'WINDOWS',
          managerSetupVersion: version,
        })
        .expect(201);
      return response.body as DeviceReply;
    }
    async function status(device: DeviceReply) {
      return (
        await http()
          .get('/edge/manager-setup')
          .set(deviceHeader(device))
          .expect(200)
      ).body as Setup;
    }
    function finish(
      device: DeviceReply,
      setupId: string,
      fields: Record<string, unknown> = {},
    ) {
      return http()
        .post('/edge/manager-setup')
        .set(deviceHeader(device))
        .send({
          setupId,
          requestId: setupId,
          name: 'Synthetic manager',
          pin: '482951',
          ...fields,
        });
    }
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('single_setup')
      )
        throw new Error(
          'Only a fresh disposable_single_setup database is permitted',
        );
      process.env.JWT_SECRET = 'single-setup-isolated-test-only';
      process.env.COOKIE_ENCRYPTION_KEY = 'single-setup-isolated-cookie-only';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
    });
    beforeEach(async () => {
      const org = await db.organization.create({
        data: { name: 'Synthetic setup organization' },
      });
      const venue = await db.venue.create({
        data: {
          organizationId: org.id,
          name: 'Synthetic setup venue',
          timezone: 'UTC',
          currency: 'GEL',
          menuAuthority: 'POS',
          legacyCommercialAccess: true,
        },
      });
      venueId = venue.id;
      for (const key of ['POS', 'MANAGER_APP'])
        await db.venueFeatureOverride.create({
          data: {
            venueId,
            featureId: (await db.feature.findUniqueOrThrow({ where: { key } }))
              .id,
            effect: 'ENABLED',
          },
        });
      const operator = await db.platformUser.create({
        data: {
          email: `${randomUUID()}@setup.test.invalid`,
          displayName: 'Synthetic operator',
          passwordHash: 'unused',
        },
      });
      const account = await db.customerAccount.create({
        data: {
          email: `${randomUUID()}@setup.test.invalid`,
          displayName: 'Synthetic owner',
          passwordHash: 'unused',
          memberships: { create: { organizationId: org.id, role: 'OWNER' } },
        },
      });
      ownerId = account.id;
      const jwt = new JwtService();
      admin = await jwt.signAsync(
        { sub: operator.id, typ: 'PLATFORM' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-platform',
          issuer: 'vynic',
        },
      );
      owner = await jwt.signAsync(
        { sub: account.id, typ: 'CUSTOMER' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-customer',
          issuer: 'vynic',
        },
      );
      app = await onboardingApp(db, undefined, {
        controllers: [ManagerActivationController],
        providers: [ManagerActivationService, LoginThrottleService],
      });
    });
    afterEach(async () => {
      await app?.close();
    });
    afterAll(async () => {
      await db?.$disconnect();
      process.env = originalEnv;
    });

    it('one setup code binds Venue/Primary and registers name/PIN without a second activation code', async () => {
      const enrollment = await code();
      const device = await redeem(enrollment);
      expect(device.venue.id === venueId).toBe(true);
      expect(enrollment.initialManagerSetup).toBe(true);
      const setup = await status(device);
      expect(setup.state).toBe('READY');
      expect(JSON.stringify(setup)).not.toMatch(
        /secret|credential|pinHash|codeHash/,
      );
      await finish(device, setup.setupId!).expect(200);
      expect((await status(device)).state).toBe('COMPLETED');
      expect(
        await db.staff.count({ where: { venueId, role: 'MANAGER' } }),
      ).toBe(1);
      expect(
        await db.edgeCommand.count({
          where: { venueId, type: 'STAFF_CREATE' },
        }),
      ).toBe(1);
      await finish(device, setup.setupId!).expect(200);
      await finish(device, setup.setupId!, { pin: '592841' }).expect(409);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
    });
    it('ordinary enrollment cannot acquire bootstrap permission from redemption body fields', async () => {
      const enrollment = await code(false);
      const response = await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: enrollment.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
          managerSetupVersion: 1,
          initialManagerSetup: true,
          venueId: randomUUID(),
        })
        .expect(201);
      const device = response.body as DeviceReply;
      expect((await status(device)).state).toBe('LEGACY_INVITATION');
      await finish(device, randomUUID()).expect(401);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
      expect(await db.managerActivation.count({ where: { venueId } })).toBe(0);
    });
    it('an additional POS waits for the Primary setup and never asks for a second invitation', async () => {
      const first = await redeem(await code());
      const setup = await status(first);
      const additional = await redeem(await code(false));
      const waiting = await status(additional);
      expect(waiting).toEqual({ state: 'WAITING_PRIMARY', setupId: null });
      await finish(additional, setup.setupId!).expect(403);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
      expect((await status(first)).state).toBe('READY');
    });
    it('additional POS enrollment reuses the restaurant and cannot create another Manager', async () => {
      const first = await redeem(await code());
      const setup = await status(first);
      await finish(first, setup.setupId!).expect(200);
      const additional = await redeem(await code(false));
      expect(additional.venue.id === venueId).toBe(true);
      expect((await status(additional)).state).toBe('EXISTING_MANAGER');
      await finish(additional, setup.setupId!).expect(403);
      await http()
        .post(`/platform/venues/${venueId}/enrollments`)
        .set(bearer(admin))
        .send({
          displayName: 'Another POS',
          platform: 'WINDOWS',
          initialManagerSetup: true,
        })
        .expect(409);
      expect(
        await db.staff.count({ where: { venueId, role: 'MANAGER' } }),
      ).toBe(1);
    });
    it('rejects unsupported setup clients before spending the code or creating a Device', async () => {
      const enrollment = await code();
      await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: enrollment.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        })
        .expect(426);
      expect(await db.device.count({ where: { venueId } })).toBe(0);
      expect(
        (
          await db.deviceEnrollment.findUniqueOrThrow({
            where: { id: enrollment.id },
            select: { redeemedAt: true },
          })
        ).redeemedAt,
      ).toBeNull();
    });
    it('same-installation code retry retains one Device and one scoped setup identity', async () => {
      const enrollment = await code();
      const installationId = randomUUID();
      const first = await redeem(enrollment, installationId);
      const setup = await status(first);
      const retry = await redeem(enrollment, installationId);
      expect(first.device.id === retry.device.id).toBe(true);
      expect((await status(retry)).setupId === setup.setupId).toBe(true);
      expect(await db.device.count({ where: { venueId } })).toBe(1);
      await http()
        .get('/edge/manager-setup')
        .set(deviceHeader(first))
        .expect(401);
    });
    it('concurrent retries create one Manager and one delivery intent', async () => {
      const device = await redeem(await code());
      const setup = await status(device);
      const responses = await Promise.all([
        finish(device, setup.setupId!),
        finish(device, setup.setupId!),
      ]);
      expect(responses.map((r) => r.status)).toEqual([200, 200]);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
      expect(
        await db.edgeCommand.count({
          where: { venueId, type: 'STAFF_CREATE' },
        }),
      ).toBe(1);
    });
    it('a grant is scoped to the bound Device and Venue despite public grant IDs', async () => {
      const primary = await redeem(await code());
      const setup = await status(primary);
      const otherOrg = await db.organization.create({
        data: { name: 'Synthetic other' },
      });
      const other = await db.venue.create({
        data: {
          organizationId: otherOrg.id,
          name: 'Other venue',
          menuAuthority: 'POS',
          timezone: 'UTC',
          currency: 'GEL',
          legacyCommercialAccess: true,
        },
      });
      for (const key of ['POS', 'MANAGER_APP'])
        await db.venueFeatureOverride.create({
          data: {
            venueId: other.id,
            featureId: (await db.feature.findUniqueOrThrow({ where: { key } }))
              .id,
            effect: 'ENABLED',
          },
        });
      const foreign = await redeem(await code(false, admin, other.id));
      await finish(foreign, setup.setupId!, { venueId }).expect(401);
      expect(await db.staff.count({ where: { venueId: other.id } })).toBe(0);
      await expect(
        db.managerActivation.update({
          where: { venueId },
          data: { setupDeviceId: foreign.device.id },
        }),
      ).rejects.toHaveProperty('code', 'P2003');
    });
    it('keeps owner initial setup authority but denies it after issuer revocation', async () => {
      const response = await http()
        .post(`/customer/venues/${venueId}/enrollments`)
        .set(bearer(owner))
        .send({ initialManagerSetup: true })
        .expect(201);
      const device = await redeem(response.body as Enrollment);
      const setup = await status(device);
      await db.customerAccount.update({
        where: { id: ownerId },
        data: { isActive: false },
      });
      await finish(device, setup.setupId!).expect(401);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('expiration, device revocation and entitlement removal still deny setup', async () => {
      const device = await redeem(await code());
      const setup = await status(device);
      await db.managerActivation.update({
        where: { venueId },
        data: { expiresAt: new Date(0) },
      });
      expect((await status(device)).state).toBe('EXPIRED');
      await finish(device, setup.setupId!).expect(401);
      await db.managerActivation.update({
        where: { venueId },
        data: { expiresAt: new Date(Date.now() + 60000) },
      });
      await db.venueFeatureOverride.updateMany({
        where: { venueId, feature: { key: 'MANAGER_APP' } },
        data: { effect: 'DISABLED' },
      });
      await finish(device, setup.setupId!).expect(403);
      await db.device.update({
        where: { id: device.device.id },
        data: { status: 'REVOKED' },
      });
      await http()
        .get('/edge/manager-setup')
        .set(deviceHeader(device))
        .expect(401);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('historical/inactive Managers exclude new initial setup and remain unchanged', async () => {
      const staff = await db.staff.create({
        data: {
          venueId,
          username: 'Historical manager',
          role: 'MANAGER',
          isActive: false,
          pinHash: 'unused-fixture-verifier',
        },
      });
      await http()
        .post(`/platform/venues/${venueId}/enrollments`)
        .set(bearer(admin))
        .send({
          displayName: 'Main',
          platform: 'WINDOWS',
          initialManagerSetup: true,
        })
        .expect(409);
      expect(
        (await db.staff.findUniqueOrThrow({ where: { id: staff.id } }))
          .isActive,
      ).toBe(false);
      expect(await db.deviceEnrollment.count({ where: { venueId } })).toBe(0);
    });
    it('duplicate active staff PIN prevention is preserved in the shared registration transaction', async () => {
      const device = await redeem(await code());
      const setup = await status(device);
      await db.staff.create({
        data: {
          venueId,
          username: 'Synthetic waiter',
          role: 'WAITER',
          pinHash: await bcrypt.hash('482951', 4),
        },
      });
      await finish(device, setup.setupId!).expect(409);
      expect(
        await db.staff.count({ where: { venueId, role: 'MANAGER' } }),
      ).toBe(0);
    });
    it('new setup issuance supersedes old unredeemed setup codes, without granting ordinary codes rights', async () => {
      const previous = await code();
      const current = await code();
      const old = await db.deviceEnrollment.findUniqueOrThrow({
        where: { id: previous.id },
        select: { cancelledAt: true },
      });
      expect(old.cancelledAt !== null).toBe(true);
      const device = await redeem(current);
      expect((await status(device)).state).toBe('READY');
    });
    it('unauthenticated and wrong-principal requests cannot read or complete Device setup', async () => {
      await http().get('/edge/manager-setup').expect(401);
      await http().get('/edge/manager-setup').set(bearer(owner)).expect(401);
      await http()
        .post('/edge/manager-setup')
        .set(bearer(admin))
        .send({
          setupId: randomUUID(),
          name: 'Synthetic',
          pin: '482951',
          requestId: randomUUID(),
        })
        .expect(401);
      await http()
        .post(`/platform/venues/${venueId}/enrollments`)
        .set(bearer(admin))
        .send({
          displayName: 'Main',
          platform: 'WINDOWS',
          initialManagerSetup: 'true',
        })
        .expect(400);
    });
    it('failed Primary binding rolls back code redemption and Device creation atomically', async () => {
      await redeem(await code(false));
      const special = await code();
      await http()
        .post('/edge/enroll')
        .send({
          enrollmentCode: special.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
          managerSetupVersion: 1,
        })
        .expect(403);
      expect(await db.device.count({ where: { venueId } })).toBe(1);
      const record = await db.deviceEnrollment.findUniqueOrThrow({
        where: { id: special.id },
        select: { redeemedAt: true, deviceId: true },
      });
      expect(record.redeemedAt).toBeNull();
      expect(record.deviceId).toBeNull();
      expect(
        (
          await db.managerActivation.findUniqueOrThrow({
            where: { venueId },
            select: { setupDeviceId: true },
          })
        ).setupDeviceId,
      ).toBeNull();
    });
    it('legacy invitation route cannot redeem a Device-bound setup grant', async () => {
      const device = await redeem(await code());
      const setup = await status(device);
      await http()
        .post('/edge/manager-activation')
        .set(deviceHeader(device))
        .send({
          code: `${setup.setupId}.${'a'.repeat(43)}`,
          requestId: randomUUID(),
          name: 'Synthetic manager',
          pin: '482951',
        })
        .expect(401);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
  },
);
