import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { LoginThrottleService } from './login-throttle.service';
import { ManagerVenueLinkService } from './manager-venue-link.service';
import {
  ManagerVenueLinkController,
  PlatformManagerVenueLinkController,
} from './manager-venue-link.controller';

const url = process.env.MANAGER_LINK_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Manager one-use linking / real HTTP and PostgreSQL',
  () => {
    let db: PrismaService, app: Awaited<ReturnType<typeof onboardingApp>>;
    let venueId: string,
      adminId: string,
      admin: string,
      readonly: string,
      owner: string,
      staffId: string,
      venueCode: string;
    const original = { ...process.env };
    const http = () => request(app.getHttpServer() as Server);
    const auth = (token = admin) => ({ Authorization: `Bearer ${token}` });
    const root = () => `/platform/venues/${venueId}/manager-links`;
    type Issued = { id: string; code: string };
    const redeem = (
      code: string,
      installationId: string = randomUUID(),
      extra: Record<string, unknown> = {},
    ) =>
      http()
        .post('/auth/manager-link')
        .send({ code, installationId, ...extra });
    async function issue() {
      return (await http().post(root()).set(auth()).expect(201)).body as Issued;
    }
    async function makeApp() {
      return onboardingApp(db, undefined, {
        controllers: [
          AuthController,
          ManagerVenueLinkController,
          PlatformManagerVenueLinkController,
        ],
        providers: [
          ManagerVenueLinkService,
          LoginThrottleService,
          {
            provide: AuthService,
            useValue: new AuthService(
              db,
              new JwtService({ secret: process.env.JWT_SECRET }),
            ),
          },
        ],
      });
    }
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('manager_link')
      )
        throw new Error('Use a fresh disposable_manager_link database');
      process.env.JWT_SECRET = 'isolated-manager-link-jwt-only';
      process.env.COOKIE_ENCRYPTION_KEY = 'isolated-manager-link-cookie-only';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
    });
    beforeEach(async () => {
      const org = await db.organization.create({
        data: { name: 'Synthetic linking organization' },
      });
      const venue = await db.venue.create({
        data: {
          organizationId: org.id,
          name: 'Synthetic linked restaurant',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          subscription: {
            create: {
              status: 'TRIAL',
              trialEndsAt: new Date(Date.now() + 86_400_000),
            },
          },
        },
      });
      venueId = venue.id;
      const plan = await db.plan.findUniqueOrThrow({ where: { key: 'POS' } });
      await db.venuePlanAssignment.create({
        data: { venueId: venue.id, planId: plan.id },
      });
      venueCode = venue.loginCode;
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'MANAGER_APP' },
      });
      await db.venueFeatureOverride.create({
        data: { venueId, featureId: feature.id, effect: 'ENABLED' },
      });
      staffId = (
        await db.staff.create({
          data: {
            venueId,
            username: 'synthetic-manager',
            role: 'MANAGER',
            pinHash: await bcrypt.hash('481259', 4),
          },
        })
      ).id;
      const user = await db.platformUser.create({
        data: {
          email: `${randomUUID()}@link.test.invalid`,
          displayName: 'Synthetic Admin',
          passwordHash: 'unused-fixture',
          role: 'SUPER_ADMIN',
        },
      });
      adminId = user.id;
      const reader = await db.platformUser.create({
        data: {
          email: `${randomUUID()}@link.test.invalid`,
          displayName: 'Synthetic reader',
          passwordHash: 'unused-fixture',
          role: 'SUPPORT_READONLY',
        },
      });
      const jwt = new JwtService();
      const platformToken = (id: string) =>
        jwt.signAsync(
          { sub: id, typ: 'PLATFORM' },
          {
            secret: process.env.JWT_SECRET,
            audience: 'vynic-platform',
            issuer: 'vynic',
          },
        );
      admin = await platformToken(adminId);
      readonly = await platformToken(reader.id);
      owner = await jwt.signAsync(
        { sub: randomUUID(), typ: 'CUSTOMER' },
        {
          secret: process.env.JWT_SECRET,
          audience: 'vynic-customer',
          issuer: 'vynic',
        },
      );
      app = await makeApp();
    });
    afterEach(async () => {
      await app.close();
    });
    afterAll(async () => {
      await db.$disconnect();
      process.env = original;
    });

    it('links once, returns only Venue metadata, preserves Staff and never creates a session', async () => {
      const before = await db.staff.findUniqueOrThrow({
        where: { id: staffId },
      });
      const link = await issue();
      const result = await redeem(link.code).expect(200);
      const body = result.body as { id: string; code: string };
      expect(body.id === venueId && body.code === venueCode).toBe(true);
      expect(JSON.stringify(body)).not.toMatch(
        /access_token|pin|Hash|secret|credential/i,
      );
      const after = await db.staff.findUniqueOrThrow({
        where: { id: staffId },
      });
      expect(after.pinHash === before.pinHash).toBe(true);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
      expect(await db.edgeCommand.count({ where: { venueId } })).toBe(0);
      await redeem(link.code).expect(401);
    });
    it('same installation retries after lost reply and concurrent requests produce one consumption audit', async () => {
      const link = await issue(),
        installationId = randomUUID();
      const results = await Promise.all([
        redeem(link.code, installationId),
        redeem(link.code, installationId),
      ]);
      expect(results.map((r) => r.status)).toEqual([200, 200]);
      await redeem(link.code, installationId).expect(200);
      expect(
        await db.platformAuditEvent.count({
          where: { action: 'manager.link_consumed', targetId: venueId },
        }),
      ).toBe(1);
    });
    it('two different installations racing have exactly one winner', async () => {
      const link = await issue();
      expect(
        (await Promise.all([redeem(link.code), redeem(link.code)]))
          .map((r) => r.status)
          .sort(),
      ).toEqual([200, 401]);
      expect(
        await db.platformAuditEvent.count({
          where: { action: 'manager.link_consumed', targetId: venueId },
        }),
      ).toBe(1);
    });
    it('client Venue/Organization IDs cannot redirect a linking code', async () => {
      const link = await issue();
      const body = (
        await redeem(link.code, randomUUID(), {
          venueId: randomUUID(),
          organizationId: randomUUID(),
          pin: '592841',
        }).expect(200)
      ).body as { id: string };
      expect(body.id === venueId).toBe(true);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
    });
    it('expiry and cancellation deny consumption without deleting the retained invitation', async () => {
      const expired = await issue();
      await db.managerVenueLink.update({
        where: { id: expired.id },
        data: { expiresAt: new Date(Date.now() - 1000) },
      });
      await redeem(expired.code).expect(401);
      const cancelled = await issue();
      await http()
        .post(`${root()}/${cancelled.id}/cancel`)
        .set(auth())
        .expect(201);
      await redeem(cancelled.code).expect(401);
      expect(await db.managerVenueLink.count({ where: { venueId } })).toBe(2);
    });
    it('reissue cancels unused codes but does not revoke already linked installations', async () => {
      const consumed = await issue(),
        installationId = randomUUID();
      await redeem(consumed.code, installationId).expect(200);
      const old = await issue(),
        fresh = await issue();
      await redeem(old.code).expect(401);
      await redeem(consumed.code, installationId).expect(200);
      await redeem(fresh.code).expect(200);
    });
    it('inactive issuer or downgraded issuer cannot redeem an outstanding code', async () => {
      const first = await issue();
      await db.platformUser.update({
        where: { id: adminId },
        data: { status: 'DISABLED' },
      });
      await redeem(first.code).expect(403);
      await db.platformUser.update({
        where: { id: adminId },
        data: { status: 'ACTIVE', role: 'SUPPORT_READONLY' },
      });
      await redeem(first.code).expect(403);
      expect(
        (
          await db.managerVenueLink.findUniqueOrThrow({
            where: { id: first.id },
          })
        ).consumedAt,
      ).toBeNull();
    });
    it('Venue suspension, feature loss and disabled Manager still gate linking', async () => {
      const link = await issue();
      await db.venue.update({
        where: { id: venueId },
        data: { status: 'DISABLED' },
      });
      await redeem(link.code).expect(403);
      await db.venue.update({
        where: { id: venueId },
        data: { status: 'ACTIVE' },
      });
      await db.venueFeatureOverride.updateMany({
        where: { venueId },
        data: { effect: 'DISABLED' },
      });
      await redeem(link.code).expect(403);
      await db.venueFeatureOverride.updateMany({
        where: { venueId },
        data: { effect: 'ENABLED' },
      });
      await db.staff.update({
        where: { id: staffId },
        data: { isActive: false },
      });
      await redeem(link.code).expect(409);
    });
    it('anonymous, owner and read-only principals cannot issue/cancel; reads omit verifier/code', async () => {
      await http().post(root()).expect(401);
      await http().post(root()).set(auth(owner)).expect(401);
      await http().post(root()).set(auth(readonly)).expect(403);
      const link = await issue();
      await http()
        .post(`${root()}/${link.id}/cancel`)
        .set(auth(readonly))
        .expect(403);
      const rows = (await http().get(root()).set(auth(readonly)).expect(200))
        .body as unknown;
      expect(JSON.stringify(rows)).not.toContain(link.code);
      expect(JSON.stringify(rows)).not.toMatch(/codeHash|pinHash|secret/i);
      await http()
        .post(`/customer/venues/${venueId}/manager-links`)
        .set(auth(owner))
        .expect(404);
    });
    it('cannot cancel another Venue invitation through a client path', async () => {
      const link = await issue();
      await http()
        .post(
          `/platform/venues/${randomUUID()}/manager-links/${link.id}/cancel`,
        )
        .set(auth())
        .expect(404);
      await redeem(link.code).expect(200);
    });
    it('requires completed active Manager history and never bootstraps Staff through linking', async () => {
      await db.staff.delete({ where: { id: staffId } });
      await http().post(root()).set(auth()).expect(409);
      expect(await db.managerVenueLink.count({ where: { venueId } })).toBe(0);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('wrong guesses are durably exhausted across a controller restart', async () => {
      const link = await issue();
      const wrong =
        link.code.slice(0, -1) + (link.code.endsWith('0') ? '2' : '0');
      for (let i = 0; i < 5; i++) await redeem(wrong).expect(401);
      expect(
        (
          await db.managerVenueLink.findUniqueOrThrow({
            where: { id: link.id },
          })
        ).attemptCount,
      ).toBe(5);
      await app.close();
      app = await makeApp();
      await redeem(link.code).expect(401);
    });
    it('linking success cannot reset failed PIN login throttling', async () => {
      const link = await issue();
      for (let i = 0; i < 5; i++)
        await http()
          .post('/auth/mobile-login')
          .send({ venueCode, pin: '592841' })
          .expect(401);
      await redeem(link.code).expect(200);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode, pin: '481259' })
        .expect(429);
    });
    it('a linking code cannot replace PIN; correct PIN still creates only the existing Staff session', async () => {
      const link = await issue();
      await redeem(link.code).expect(200);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode, pin: link.code })
        .expect(401);
      const body = (
        await http()
          .post('/auth/mobile-login')
          .send({ venueCode, pin: '481259' })
          .expect(200)
      ).body as { access_token: string };
      const decoded = new JwtService().decode<{ sub: string }>(
        body.access_token,
      );
      expect(decoded.sub === staffId).toBe(true);
    });
    it('legacy duplicated active PINs still fail closed even after successful linking', async () => {
      await db.staff.create({
        data: {
          venueId,
          username: 'synthetic-conflict',
          role: 'MANAGER',
          pinHash: await bcrypt.hash('481259', 4),
        },
      });
      const link = await issue();
      await redeem(link.code).expect(200);
      await http()
        .post('/auth/mobile-login')
        .send({ venueCode, pin: '481259' })
        .expect(401);
    });
    it('audit failure rolls back issuance, cancellation and consumption', async () => {
      const link = await issue();
      await db.$executeRawUnsafe(
        `CREATE FUNCTION pos.fail_link_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action LIKE 'manager.link_%' THEN RAISE EXCEPTION 'Synthetic link audit failure'; END IF; RETURN NEW; END $$`,
      );
      await db.$executeRawUnsafe(
        `CREATE TRIGGER fail_link_audit BEFORE INSERT ON pos."PlatformAuditEvent" FOR EACH ROW EXECUTE FUNCTION pos.fail_link_audit()`,
      );
      try {
        await http().post(root()).set(auth()).expect(500);
        expect(await db.managerVenueLink.count({ where: { venueId } })).toBe(1);
        await http()
          .post(`${root()}/${link.id}/cancel`)
          .set(auth())
          .expect(500);
        await redeem(link.code).expect(500);
        const row = await db.managerVenueLink.findUniqueOrThrow({
          where: { id: link.id },
        });
        expect(row.cancelledAt).toBeNull();
        expect(row.consumedAt).toBeNull();
      } finally {
        await db.$executeRawUnsafe(
          'DROP TRIGGER fail_link_audit ON pos."PlatformAuditEvent"',
        );
        await db.$executeRawUnsafe('DROP FUNCTION pos.fail_link_audit()');
      }
    });
    it('rejects malformed code/installation and retains the invitation', async () => {
      const link = await issue();
      await redeem(link.code, 'not-an-installation').expect(400);
      await redeem('not-a-link').expect(401);
      expect(
        (
          await db.managerVenueLink.findUniqueOrThrow({
            where: { id: link.id },
          })
        ).consumedAt,
      ).toBeNull();
    });
  },
);
