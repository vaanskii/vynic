import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';

const url = process.env.UX01_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'UX-01 existing public request persistence / actual HTTP and PostgreSQL',
  () => {
    let db: PrismaService, app: Awaited<ReturnType<typeof onboardingApp>>;
    const previousEnv = { ...process.env };
    const http = () => request(app.getHttpServer() as Server);
    const body = () => ({
      applicantName: 'Synthetic applicant',
      businessName: 'Synthetic restaurant',
      email: `ux01-${randomUUID()}@test.invalid`,
      phone: 'fixture-phone',
      note: 'Synthetic demo application',
    });
    const submit = (data: Record<string, unknown>) =>
      http().post('/customer/access-requests').send(data);
    const counts = () =>
      Promise.all([
        db.customerAccount.count(),
        db.organization.count(),
        db.venue.count(),
        db.venueSubscription.count(),
        db.venueDomain.count(),
        db.device.count(),
        db.deviceEnrollment.count(),
        db.websiteMediaAsset.count(),
        db.customerAuditEvent.count(),
      ]);
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('ux01')
      )
        throw new Error('Use a fresh disposable_ux01 database');
      process.env.JWT_SECRET = 'ux01-synthetic-test-signing-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
    });
    beforeEach(async () => {
      app = await onboardingApp(db);
    });
    afterEach(async () => {
      await app?.close();
    });
    afterAll(async () => {
      await db?.$disconnect();
      process.env = previousEnv;
    });

    it('returns received only after a normalized pending request exists; provisions nothing', async () => {
      const data = body(),
        before = await counts();
      data.email = data.email.toUpperCase();
      const response = await submit(data).expect(201);
      expect(response.body as { received: boolean }).toEqual({
        received: true,
      });
      expect(
        await db.onboardingRequest.findFirstOrThrow({
          where: { email: data.email.toLowerCase() },
        }),
      ).toMatchObject({
        applicantName: data.applicantName,
        businessName: data.businessName,
        phone: data.phone,
        note: data.note,
        status: 'PENDING',
        requestedVenueId: null,
        requestedPlanId: null,
      });
      expect(await counts()).toEqual(before);
    });
    it('invalid contact or unavailable plan fails without persisting an application', async () => {
      const data = body();
      await submit({ ...data, email: 'invalid' }).expect(400);
      await submit({ ...data, requestedPlanId: randomUUID() }).expect(400);
      expect(
        await db.onboardingRequest.count({ where: { email: data.email } }),
      ).toBe(0);
    });
    it('a retry returns the exact pending-request conflict and keeps one request', async () => {
      const data = body();
      await submit(data).expect(201);
      const original = await db.onboardingRequest.findFirstOrThrow({
        where: { email: data.email },
      });
      const repeat = await submit({
        ...data,
        note: 'Changed retry note',
      }).expect(409);
      expect(repeat.body as { message: string }).toMatchObject({
        message: 'A request is already awaiting review',
      });
      expect(
        await db.onboardingRequest.findMany({ where: { email: data.email } }),
      ).toEqual([original]);
    });
    it('concurrent duplicate submissions admit one pending request', async () => {
      const data = body();
      const responses = await Promise.all([submit(data), submit(data)]);
      expect(responses.map((r) => r.status).sort()).toEqual([201, 409]);
      expect(
        await db.onboardingRequest.count({ where: { email: data.email } }),
      ).toBe(1);
    });
    it('email throttle remains authoritative rather than returning a new success', async () => {
      const data = body();
      await submit(data).expect(201);
      await submit(data).expect(409);
      await submit(data).expect(409);
      await submit(data).expect(429);
      expect(
        await db.onboardingRequest.count({ where: { email: data.email } }),
      ).toBe(1);
    });
    it('IP throttle refuses the sixth application without creating its row', async () => {
      for (let i = 0; i < 5; i++) await submit(body()).expect(201);
      const refused = body();
      await submit(refused).expect(429);
      expect(
        await db.onboardingRequest.count({ where: { email: refused.email } }),
      ).toBe(0);
    });
    it('storage failure returns 500, no received success or provisioned data; retry can persist', async () => {
      const data = body(),
        before = await counts();
      await db.$executeRawUnsafe(
        "CREATE FUNCTION pos.ux01_test_storage_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic storage fault'; END $$",
      );
      await db.$executeRawUnsafe(
        'CREATE TRIGGER ux01_test_storage_fault BEFORE INSERT ON pos."OnboardingRequest" FOR EACH ROW EXECUTE FUNCTION pos.ux01_test_storage_fault()',
      );
      try {
        const response = await submit(data).expect(500);
        expect(response.body as Record<string, unknown>).not.toHaveProperty(
          'received',
          true,
        );
        expect(
          await db.onboardingRequest.count({ where: { email: data.email } }),
        ).toBe(0);
        expect(await counts()).toEqual(before);
      } finally {
        await db.$executeRawUnsafe(
          'DROP TRIGGER ux01_test_storage_fault ON pos."OnboardingRequest"',
        );
        await db.$executeRawUnsafe(
          'DROP FUNCTION pos.ux01_test_storage_fault()',
        );
      }
      await submit(data).expect(201);
      expect(
        await db.onboardingRequest.count({ where: { email: data.email } }),
      ).toBe(1);
    });
  },
);
