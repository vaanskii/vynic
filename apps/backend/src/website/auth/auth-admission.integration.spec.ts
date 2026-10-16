import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import * as argon from 'argon2';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { PrismaService } from '../../prisma.service';
import { CryptoService } from '../common/crypto.service';
import { CsrfService } from '../common/csrf.service';
import { emptyWebsiteContent } from '../core/website-content';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteAuthController } from './auth.controller';
import { WebsiteAuthService } from './auth.service';
import { websiteAuthBodyParsers } from './auth-body-parsers';

const url = process.env.SEC03_TEST_DATABASE_URL;

(url ? describe : describe.skip)(
  'SEC-03 real PostgreSQL / HTTP authentication admission',
  () => {
    let db: PrismaService;
    let app: INestApplication;
    let auth: WebsiteAuthService;
    const tag = randomUUID();
    const fixtures: { venueId: string; host: string }[] = [];
    const csrf = 'ab'.repeat(32);
    const password = 'SEC03-synthetic-password';
    const email = `known-${tag}@example.invalid`;
    const phone = `sec03-${tag}`;
    let userId: string;
    const originalCookieKey = process.env.COOKIE_ENCRYPTION_KEY;
    const http = () => request(app.getHttpServer() as Server);
    const post = (route: string, body: object, i = 0) =>
      http()
        .post(`/api/auth/${route}`)
        .set('Host', fixtures[i].host)
        .set('Cookie', `csrf_token=${csrf}`)
        .set('X-CSRF-Token', csrf)
        .send(body);
    const signin = (identifier: string, secret = password, i = 0) =>
      post('signin', { identifier, password: secret }, i);
    const syntheticRegistration = () => ({
      email: `signup-${randomUUID()}@example.invalid`,
      phone: `sec03-${randomUUID()}`,
      password,
    });

    beforeAll(async () => {
      const parsed = new URL(url!);
      if (
        !isFreshDisposableDatabase(parsed) ||
        !/^\/disposable_sec03_[a-z0-9_]+$/.test(parsed.pathname)
      )
        throw new Error(
          'SEC-03 requires a fresh verification-owned disposable_sec03_* database on 127.0.0.1',
        );
      process.env.COOKIE_ENCRYPTION_KEY = 'SEC03-synthetic-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'WEBSITE' },
      });
      const plan = await db.plan.create({
        data: {
          key: `sec03-${tag}`,
          name: 'SEC03 synthetic',
          features: { create: { featureId: feature.id } },
        },
      });
      for (const mode of ['SAAS', 'CUSTOM'] as const) {
        const org = await db.organization.create({
          data: { name: `SEC03 ${mode} ${tag}` },
        });
        const host = `sec03-${mode.toLowerCase()}-${tag}.localhost`;
        const venue = await db.venue.create({
          data: {
            organizationId: org.id,
            name: `SEC03 ${mode}`,
            currency: 'GEL',
            timezone: 'Asia/Tbilisi',
            domains: { create: { hostname: host } },
            planAssignment: { create: { planId: plan.id } },
            subscription: { create: { status: 'ACTIVE' } },
            websiteConfig: {
              create:
                mode === 'CUSTOM'
                  ? { mode }
                  : {
                      mode,
                      status: 'PUBLISHED',
                      slug: `sec03-${tag}`,
                      revision: 1,
                      publishedRevision: 1,
                      publishedAt: new Date(),
                      published: {
                        ...emptyWebsiteContent,
                        slug: `sec03-${tag}`,
                      },
                    },
            },
          },
        });
        fixtures.push({ venueId: venue.id, host });
      }
      const user = await db.websiteUser.create({
        data: { phone, email, password: await argon.hash(password) },
      });
      userId = user.id;
    });

    beforeEach(async () => {
      const entitlements = new VenueEntitlementsService(db);
      const crypto = new CryptoService();
      auth = new WebsiteAuthService(
        db,
        new JwtService(),
        new ConfigService({
          JWT_SECRET: 'SEC03-synthetic-access-key',
          JWT_REFRESH_SECRET: 'SEC03-synthetic-refresh-key',
        }),
        crypto,
      );
      const module = await Test.createTestingModule({
        controllers: [WebsiteAuthController],
        providers: [
          { provide: PrismaService, useValue: db },
          { provide: WebsiteAuthService, useValue: auth },
          { provide: CryptoService, useValue: crypto },
          CsrfService,
          EnrollmentRateLimiter,
          { provide: VenueEntitlementsService, useValue: entitlements },
          {
            provide: WebsiteCapabilitiesService,
            useValue: new WebsiteCapabilitiesService(db, entitlements),
          },
          {
            provide: WebsiteTenantService,
            useValue: new WebsiteTenantService(
              db,
              new ConfigService({ NODE_ENV: 'production' }),
            ),
          },
        ],
      }).compile();
      app = module.createNestApplication();
      app.use('/api/auth', ...websiteAuthBodyParsers());
      app.use(cookieParser());
      app.useGlobalPipes(
        new ValidationPipe({
          whitelist: true,
          forbidNonWhitelisted: true,
          transform: true,
        }),
      );
      await app.listen(0, '127.0.0.1');
    });

    afterEach(async () => {
      await app?.close();
      jest.restoreAllMocks();
    });
    afterAll(async () => {
      await db?.$disconnect();
      if (originalCookieKey === undefined)
        delete process.env.COOKIE_ENCRYPTION_KEY;
      else process.env.COOKIE_ENCRYPTION_KEY = originalCookieKey;
    });

    it('preserves six-character signup, encrypted HttpOnly cookies, verification and cross-Host global sign-in', async () => {
      const body = {
        ...syntheticRegistration(),
        password: 'six123',
        firstName: 'Synthetic',
      };
      const created = await post('signup', body).expect(201);
      const cookies = created.headers['set-cookie'] as unknown as string[];
      expect(
        cookies.filter((cookie) => cookie.includes('HttpOnly')),
      ).toHaveLength(2);
      expect(JSON.stringify(created.body)).not.toContain(body.password);
      const stored = await db.websiteUser.findUniqueOrThrow({
        where: { email: body.email },
      });
      expect(await argon.verify(stored.password, body.password)).toBe(true);
      const verified = await http()
        .get('/api/auth/verify')
        .set('Cookie', cookies.map((cookie) => cookie.split(';')[0]).join('; '))
        .expect(200);
      expect(verified.body).toMatchObject({
        isAuthenticated: true,
        user: { id: stored.id },
      });
      await signin(body.email, body.password, 1).expect(201);
    });

    it('stops the eleventh known-account guess before service/hash work without changing credentials', async () => {
      const before = await db.websiteUser.findUniqueOrThrow({
        where: { id: userId },
      });
      const called = jest.spyOn(auth, 'signin');
      for (let n = 0; n < 10; n++)
        await signin(email, 'synthetic-wrong').expect(403);
      await signin(` ${email.toUpperCase()} `, password, 1).expect(429);
      expect(called).toHaveBeenCalledTimes(10);
      const after = await db.websiteUser.findUniqueOrThrow({
        where: { id: userId },
      });
      expect(after.password).toBe(before.password);
      expect(after.hashedRefreshToken).toBe(before.hashedRefreshToken);
    });

    it('gives unknown accounts the same normalized cross-Host throttle', async () => {
      const unknown = `missing-${tag}@example.invalid`;
      const called = jest.spyOn(auth, 'signin');
      for (let n = 0; n < 10; n++)
        await signin(unknown, password, n % 2).expect(403);
      await signin(` ${unknown.toUpperCase()} `).expect(429);
      expect(called).toHaveBeenCalledTimes(10);
      expect(
        await db.websiteUser.findUnique({ where: { email: unknown } }),
      ).toBeNull();
    });

    it('caps rotating identifiers at twenty per actual peer, even with spoofed forwarding headers', async () => {
      const called = jest.spyOn(auth, 'signin');
      for (let n = 0; n < 20; n++)
        await signin(`missing-${n}-${tag}@example.invalid`).expect(403);
      await signin(email)
        .set('X-Forwarded-For', '198.51.100.8')
        .set('X-Real-IP', '198.51.100.8')
        .expect(429);
      expect(called).toHaveBeenCalledTimes(20);
    });

    it('shares successful and duplicate signup attempts with sign-in; duplicates do not create extra users', async () => {
      const body = syntheticRegistration();
      const called = jest.spyOn(auth, 'signup');
      await post('signup', body).expect(201);
      for (let n = 0; n < 9; n++) await post('signup', body, n % 2).expect(403);
      await post('signup', body).expect(429);
      await signin(body.email, body.password, 1).expect(429);
      await signin(` ${body.phone} `, body.password, 1).expect(429);
      expect(called).toHaveBeenCalledTimes(10);
      expect(await db.websiteUser.count({ where: { email: body.email } })).toBe(
        1,
      );
    });

    it('rejects missing/mismatched CSRF, malformed fields and oversized bodies without persistence/service calls', async () => {
      const body = syntheticRegistration();
      const called = jest.spyOn(auth, 'signup');
      await http()
        .post('/api/auth/signup')
        .set('Host', fixtures[0].host)
        .send(body)
        .expect(403);
      await post('signup', body)
        .set('X-CSRF-Token', 'cd'.repeat(32))
        .expect(403);
      await post('signup', { ...body, password: 123456 }).expect(400);
      await post('signup', { ...body, firstName: 'x'.repeat(121) }).expect(400);
      await post('signup', { ...body, password: 'x'.repeat(9000) }).expect(413);
      expect(called).not.toHaveBeenCalled();
      expect(
        await db.websiteUser.findUnique({ where: { email: body.email } }),
      ).toBeNull();
    });

    it('keeps Host, active Venue and CUSTOMER_ACCOUNTS capability gates ahead of authentication', async () => {
      const called = jest.spyOn(auth, 'signin');
      await signin(email).set('Host', 'unknown-sec03.localhost').expect(404);
      await db.venueWebsiteCapability.create({
        data: {
          venueId: fixtures[0].venueId,
          capability: 'CUSTOMER_ACCOUNTS',
          enabled: false,
        },
      });
      try {
        await signin(email).expect(404);
      } finally {
        await db.venueWebsiteCapability.delete({
          where: {
            venueId_capability: {
              venueId: fixtures[0].venueId,
              capability: 'CUSTOMER_ACCOUNTS',
            },
          },
        });
      }
      await db.venue.update({
        where: { id: fixtures[1].venueId },
        data: { status: 'DISABLED' },
      });
      try {
        await signin(email, password, 1).expect(404);
      } finally {
        await db.venue.update({
          where: { id: fixtures[1].venueId },
          data: { status: 'ACTIVE' },
        });
      }
      expect(called).not.toHaveBeenCalled();
    });

    it('bounds password-change guesses using the real cookie guard and retains the existing credential', async () => {
      const signedIn = await signin(email).expect(201);
      const cookie = (signedIn.headers['set-cookie'] as unknown as string[])
        .map((entry) => entry.split(';')[0])
        .join('; ');
      const before = await db.websiteUser.findUniqueOrThrow({
        where: { id: userId },
      });
      const called = jest.spyOn(auth, 'changePassword');
      const attempt = (oldPassword: string) =>
        post('change-password', {
          oldPassword,
          newPassword: 'synthetic-new-password',
        }).set('Cookie', `${cookie}; csrf_token=${csrf}`);
      await attempt('wrong').set('X-CSRF-Token', 'cd'.repeat(32)).expect(403);
      await attempt('x'.repeat(513)).expect(400);
      for (let n = 0; n < 10; n++) await attempt('wrong').expect(403);
      await attempt(password).expect(429);
      expect(called).toHaveBeenCalledTimes(10);
      const after = await db.websiteUser.findUniqueOrThrow({
        where: { id: userId },
      });
      expect(after.password).toBe(before.password);
    });

    it('preserves a valid authenticated password change and exact secret bytes', async () => {
      const body = syntheticRegistration();
      const created = await post('signup', body).expect(201);
      const cookie = (created.headers['set-cookie'] as unknown as string[])
        .map((entry) => entry.split(';')[0])
        .join('; ');
      const newPassword = ' six-character-minimum-with-spaces ';
      await post('change-password', { oldPassword: body.password, newPassword })
        .set('Cookie', `${cookie}; csrf_token=${csrf}`)
        .expect(201);
      await signin(body.email, body.password).expect(403);
      await signin(body.email, newPassword).expect(201);
      const stored = await db.websiteUser.findUniqueOrThrow({
        where: { email: body.email },
      });
      expect(await argon.verify(stored.password, newPassword)).toBe(true);
    });
  },
);
