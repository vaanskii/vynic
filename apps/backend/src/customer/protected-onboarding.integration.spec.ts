import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { CustomerAuth, CustomerGuard } from './customer-auth';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { OwnerInvitationsService } from './owner-invitations.service';
import {
  CustomerOwnerInvitationsController,
  PlatformOwnerInvitationsController,
} from './owner-invitations.controller';
import { InstallerDownloadsService } from './installer-downloads.service';
import {
  CustomerInstallerDownloadsController,
  PlatformInstallerDownloadsController,
  InstallerDownloadFileController,
} from './installer-downloads.controller';
import { PlatformAuthService } from '../platform/platform-auth.service';
import { admit, secretHash } from './security-admission';

const url = process.env.PROTECTED_ONBOARDING_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Protected onboarding — disposable PostgreSQL / HTTP',
  () => {
    let db: PrismaService,
      app: any,
      service: OwnerInvitationsService,
      downloads: InstallerDownloadsService,
      actor: any,
      auth: CustomerAuth,
      owner: any,
      foreign: any,
      venue: any;
    const http = () => request(app.getHttpServer());
    const headers = {
      'X-CSRF-Token': 'vynic-invitation',
      Origin: 'http://127.0.0.1',
      Host: '127.0.0.1',
    };
    const cookie = (r: any) =>
      (r.headers['set-cookie'] as string[])
        .map((s) => s.split(';')[0])
        .join('; ');
    const issue = async (email = `pending-${randomUUID()}@test.invalid`) =>
      db.$transaction((tx) =>
        service.issue(tx, actor, venue.organizationId, email),
      );
    const open = (token: string) =>
      http().post('/customer/invitations/session').set(headers).send({ token });
    const syntheticStorage = () => {
      process.env.VYNIC_RELEASE_GITHUB_TOKEN =
        'synthetic-only-not-a-real-credential';
      process.env.VYNIC_INSTALLER_ASSET_ID = '999';
      process.env.VYNIC_INSTALLER_BYTES = '10';
      process.env.VYNIC_INSTALLER_SHA256 = 'a'.repeat(64);
    };
    beforeAll(async () => {
      if (!isFreshDisposableDatabase(url!))
        throw new Error('Disposable loopback database required');
      process.env.JWT_SECRET = 'synthetic-onboarding-jwt-secret';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      await db.securityAdmission.deleteMany();
      const admin = await db.platformUser.create({
        data: {
          email: `admin-${randomUUID()}@test.invalid`,
          displayName: 'Test admin',
          passwordHash: 'unused',
        },
      });
      actor = { platformUserId: admin.id, role: 'SUPER_ADMIN' };
      auth = new CustomerAuth(
        db,
        new JwtService(),
        new EnrollmentRateLimiter(),
      );
      service = new OwnerInvitationsService(
        db,
        auth,
        new EnrollmentRateLimiter(),
      );
      downloads = new InstallerDownloadsService(db);
      const org = await db.organization.create({
        data: { name: 'Synthetic owner organization' },
      });
      venue = await db.venue.create({
        data: {
          organizationId: org.id,
          name: 'Synthetic venue',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
        },
      });
      owner = await db.customerAccount.create({
        data: {
          email: `owner-${randomUUID()}@test.invalid`,
          displayName: 'Test owner',
          passwordHash: 'unused',
          memberships: { create: { organizationId: org.id } },
        },
      });
      foreign = await db.customerAccount.create({
        data: {
          email: `foreign-${randomUUID()}@test.invalid`,
          displayName: 'Foreign owner',
          passwordHash: 'unused',
        },
      });
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'POS' },
      });
      const plan = await db.plan.create({
        data: {
          key: `protected-${randomUUID()}`,
          name: 'Synthetic POS',
          features: { create: { featureId: feature.id } },
        },
      });
      await db.venuePlanAssignment.create({
        data: { venueId: venue.id, planId: plan.id },
      });
      await db.venueSubscription.create({
        data: { venueId: venue.id, status: 'ACTIVE' },
      });
      const module = await Test.createTestingModule({
        controllers: [
          CustomerOwnerInvitationsController,
          PlatformOwnerInvitationsController,
          CustomerInstallerDownloadsController,
          PlatformInstallerDownloadsController,
          InstallerDownloadFileController,
        ],
        providers: [
          CustomerGuard,
          { provide: PrismaService, useValue: db },
          { provide: OwnerInvitationsService, useValue: service },
          { provide: InstallerDownloadsService, useValue: downloads },
          { provide: CustomerAuth, useValue: auth },
          {
            provide: PlatformAuthService,
            useValue: {
              resolve: async (t: string) =>
                t === 'synthetic-admin'
                  ? actor
                  : t === 'synthetic-support'
                    ? { ...actor, role: 'SUPPORT_READONLY' }
                    : null,
            },
          },
        ],
      }).compile();
      app = module.createNestApplication();
      app.use(cookieParser());
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      delete process.env.VYNIC_RELEASE_GITHUB_TOKEN;
      delete process.env.VYNIC_INSTALLER_ASSET_ID;
      delete process.env.VYNIC_INSTALLER_BYTES;
      delete process.env.VYNIC_INSTALLER_SHA256;
    });
    it('exchanges the fragment once, survives refresh/direct navigation and registers using only its opaque cookie', async () => {
      const issued = await issue();
      const token = issued.invitationPath.split('=')[1];
      const first = await open(token).expect(201);
      const c = cookie(first);
      expect(first.headers['set-cookie'][0]).toContain('HttpOnly');
      expect(first.headers['set-cookie'][0]).toContain('SameSite=Strict');
      expect(first.headers['set-cookie'][0]).toContain(
        'Path=/customer/invitations',
      );
      expect(first.headers['set-cookie'][0]).not.toContain('Domain=');
      expect(JSON.stringify(first.body)).not.toContain(token);
      await http()
        .post('/customer/invitations/session/resume')
        .set(headers)
        .set('Cookie', c)
        .send({})
        .expect(201);
      const result = await http()
        .post('/customer/invitations/register')
        .set(headers)
        .set('Cookie', c)
        .send({
          displayName: 'Synthetic invited owner',
          password: 'synthetic-password-123',
        })
        .expect(201);
      expect(result.body.access_token).toBeTruthy();
      await http()
        .post('/customer/invitations/register')
        .set(headers)
        .set('Cookie', c)
        .send({ displayName: 'Other', password: 'synthetic-password-123' })
        .expect(400);
      await open(token).expect(400);
      expect(
        await db.organizationMembership.count({
          where: {
            customerAccountId: result.body.account.id,
            organizationId: venue.organizationId,
          },
        }),
      ).toBe(1);
    });
    it('rejects absent, expired, superseded and revoked sessions and keeps recovery enumeration-safe', async () => {
      await http()
        .post('/customer/invitations/session/resume')
        .set(headers)
        .send({})
        .expect(400);
      const issued = await issue();
      const token = issued.invitationPath.split('=')[1];
      const first = await open(token).expect(201);
      const a = await service.requestRecovery(
        { email: issued.invitation.email },
        'recovery-one',
      );
      const b = await service.requestRecovery(
        { email: 'absent@test.invalid' },
        'recovery-two',
      );
      expect(a).toEqual(b);
      expect(
        (
          await db.ownerInvitation.findUniqueOrThrow({
            where: { id: issued.invitation.id },
          })
        ).recoveryRequestedAt,
      ).toBeTruthy();
      const next = (await service.change(
        actor,
        issued.invitation.id,
        true,
      )) as any;
      await http()
        .post('/customer/invitations/session/resume')
        .set(headers)
        .set('Cookie', cookie(first))
        .send({})
        .expect(400);
      await open(token).expect(400);
      const second = await open(next.invitationPath.split('=')[1]).expect(201);
      await db.ownerInvitation.update({
        where: { id: next.invitation.id },
        data: { expiresAt: new Date(0) },
      });
      await http()
        .post('/customer/invitations/session/resume')
        .set(headers)
        .set('Cookie', cookie(second))
        .send({})
        .expect(400);
      // The request itself did not revoke the initial valid token.
      expect(
        (
          await db.ownerInvitation.findUniqueOrThrow({
            where: { id: issued.invitation.id },
          })
        ).revokedAt,
      ).toBeTruthy();
    });
    it('rejects cross-origin and missing CSRF exchange and an existing account with the wrong invited identity', async () => {
      const issued = await issue(owner.email);
      const token = issued.invitationPath.split('=')[1];
      await http()
        .post('/customer/invitations/session')
        .send({ token })
        .expect(403);
      await http()
        .post('/customer/invitations/session')
        .set({
          ...headers,
          Host: 'www.vynic.ge',
          Origin: 'https://admin.vynic.ge',
        })
        .send({ token })
        .expect(403);
      await http()
        .post('/customer/invitations/session')
        .set({
          ...headers,
          Host: 'admin.vynic.ge',
          Origin: 'https://www.vynic.ge',
        })
        .send({ token })
        .expect(403);
      await http()
        .post('/customer/invitations/session')
        .set({ ...headers, Origin: 'https://attacker.invalid' })
        .send({ token })
        .expect(403);
      const opened = await open(token).expect(201);
      const foreignToken = (await auth.session(foreign)).access_token;
      await http()
        .post('/customer/invitations/accept')
        .set(headers)
        .set('Cookie', cookie(opened))
        .set('Authorization', `Bearer ${foreignToken}`)
        .send({})
        .expect(403);
      expect(
        (
          await db.ownerInvitation.findUniqueOrThrow({
            where: { id: issued.invitation.id },
          })
        ).acceptedAt,
      ).toBeNull();
    });
    it('serializes concurrent acceptance so exactly one membership is granted', async () => {
      const issued = await issue();
      const token = issued.invitationPath.split('=')[1];
      const results = await Promise.allSettled(
        [1, 2].map(() =>
          service.accept(
            {
              token,
              displayName: 'Concurrent synthetic',
              password: 'synthetic-password-123',
            },
            'concurrent',
          ),
        ),
      );
      expect(results.filter((x) => x.status === 'fulfilled')).toHaveLength(1);
    });
    it('requires authentication, ownership and POS entitlement before issuing download links', async () => {
      syntheticStorage();
      const path = `/customer/venues/${venue.id}/downloads`;
      await http().post(path).send({}).expect(401);
      await http()
        .post(path)
        .set(
          'Authorization',
          `Bearer ${(await auth.session(foreign)).access_token}`,
        )
        .send({})
        .expect(404);
      await http()
        .post('/platform/onboarding/downloads')
        .set('Authorization', 'Bearer synthetic-support')
        .send({})
        .expect(403);
      await db.venueSubscription.update({
        where: { venueId: venue.id },
        data: { status: 'SUSPENDED' },
      });
      await expect(
        downloads.issue(
          { customerAccountId: owner.id, venueId: venue.id },
          'owner-ip',
        ),
      ).rejects.toMatchObject({ status: 403 });
      await db.venueSubscription.update({
        where: { venueId: venue.id },
        data: { status: 'ACTIVE' },
      });
      delete process.env.VYNIC_RELEASE_GITHUB_TOKEN;
      await expect(
        downloads.issue(
          { customerAccountId: owner.id, venueId: venue.id },
          'owner-ip',
        ),
      ).rejects.toMatchObject({ status: 503 });
    });
    it('stores only capability hashes, supports revocation, expiry and authority loss', async () => {
      syntheticStorage();
      const result = await downloads.issue(
        { customerAccountId: owner.id, venueId: venue.id },
        'grant-owner-ip',
      );
      const token = result.downloadPath.split('=')[1];
      const row = await db.installerDownloadGrant.findUniqueOrThrow({
        where: { id: result.grant.id },
      });
      expect(row.tokenHash).toBe(secretHash(token));
      expect(JSON.stringify(result.grant)).not.toContain(row.tokenHash);
      const list = await downloads.listCustomer(
        { customerAccountId: owner.id },
        venue.id,
      );
      expect(JSON.stringify(list)).not.toContain(token);
      await expect(
        downloads.revoke(row.id, { customerAccountId: foreign.id }),
      ).rejects.toMatchObject({ status: 404 });
      await downloads.resolve(token, 'resolve-ip');
      await db.venueSubscription.update({
        where: { venueId: venue.id },
        data: { status: 'SUSPENDED' },
      });
      await expect(
        downloads.resolve(token, 'resolve-ip'),
      ).rejects.toMatchObject({ status: 403 });
      await db.venueSubscription.update({
        where: { venueId: venue.id },
        data: { status: 'ACTIVE' },
      });
      await downloads.revoke(row.id, { customerAccountId: owner.id });
      await expect(
        downloads.resolve(token, 'resolve-ip'),
      ).rejects.toMatchObject({ status: 404 });
      const expired = await downloads.issue(
        { platformUserId: actor.platformUserId },
        'admin-ip',
      );
      await db.installerDownloadGrant.update({
        where: { id: expired.grant.id },
        data: { expiresAt: new Date(0) },
      });
      await expect(
        downloads.resolve(expired.downloadPath.split('=')[1], 'expired-ip'),
      ).rejects.toMatchObject({ status: 404 });
    });
    it('provides HEAD and Range without a public redirect and never sends storage credentials to the asset host', async () => {
      syntheticStorage();
      const issued = await downloads.issue(
        { platformUserId: actor.platformUserId },
        'stream-admin',
      );
      const token = issued.downloadPath.split('=')[1];
      const opened = await http()
        .post('/customer/downloads/open')
        .set({
          'X-CSRF-Token': 'vynic-download',
          Origin: 'http://127.0.0.1',
          Host: '127.0.0.1',
        })
        .send({ token })
        .expect(201);
      const spy = jest
        .spyOn(globalThis, 'fetch')
        .mockImplementation(async (url: any, init: any) =>
          String(url).startsWith('https://api.github.com')
            ? new Response(null, {
                status: 302,
                headers: {
                  location:
                    'https://release-assets.githubusercontent.com/synthetic',
                },
              })
            : new Response(
                init.method === 'HEAD'
                  ? null
                  : init.headers.Range
                    ? '012'
                    : '0123456789',
                {
                  status: init.headers.Range ? 206 : 200,
                  headers: {
                    'content-length': init.headers.Range ? '3' : '10',
                    ...(init.headers.Range
                      ? { 'content-range': 'bytes 0-2/10' }
                      : {}),
                  },
                },
              ),
        );
      try {
        const r = await http()
          .get('/customer/downloads/file')
          .set('Cookie', cookie(opened))
          .expect(200);
        expect(r.headers.location).toBeUndefined();
        expect(r.headers['cache-control']).toContain('no-store');
        await http()
          .head('/customer/downloads/file')
          .set('Cookie', cookie(opened))
          .expect(200);
        await http()
          .get('/customer/downloads/file')
          .set('Cookie', cookie(opened))
          .set('Range', 'bytes=0-2')
          .expect(206);
        await http()
          .get('/customer/downloads/file')
          .set('Cookie', cookie(opened))
          .set('Range', 'bytes=99-')
          .expect(416);
        expect(
          spy.mock.calls
            .filter((c) => String(c[0]).includes('release-assets'))
            .every((c) => !(c[1]!.headers as any).Authorization),
        ).toBe(true);
      } finally {
        spy.mockRestore();
      }
    });
    it('enforces durable concurrent rate limits across callers', async () => {
      const identity = randomUUID();
      const outcomes = await Promise.allSettled(
        Array.from({ length: 8 }, () =>
          admit(db, 'test-concurrent', identity, 3, 3600000),
        ),
      );
      expect(outcomes.filter((x) => x.status === 'fulfilled')).toHaveLength(3);
    });
  },
);
