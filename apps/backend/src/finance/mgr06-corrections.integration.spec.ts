import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';
import { FinanceController } from './finance.controller';
import { PayrollService } from './payroll.service';
import { ObligationsService } from './obligations.service';
import { financialPayments } from './financial-summary';
import * as common from './finance-common';
import { JwtStrategy } from '../auth/jwt.strategy';
import { ManagerTenantService } from '../auth/manager-tenant.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { seedMenu03 } from '../../test/menu03.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { MobileAuditLogService } from '../mobile/services/mobile-audit-log.service';

const url = process.env.MGR06_TEST_DATABASE_URL;
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw Error('Expected object');
  return value as Record<string, unknown>;
}
function rows(value: unknown) {
  if (!Array.isArray(value)) throw Error('Expected rows');
  return value.map(record);
}
(url ? describe : describe.skip)(
  'MGR06 actual HTTP/PG immutable financial corrections',
  () => {
    let db: PrismaService,
      app: Awaited<ReturnType<typeof onboardingApp>>,
      base: string;
    let seeded: Awaited<ReturnType<typeof seedMenu03>>,
      venueId: string,
      organizationId: string,
      managerId: string,
      token: string,
      foreign: string,
      waiter: string;
    const historical = '2026-09-15',
      correctionDay = '2026-10-07';
    const input = (reason = 'Synthetic correction') => ({
      id: randomUUID(),
      reason,
    });
    async function request(path: string, body?: unknown, auth = token) {
      const response = await fetch(base + '/mobile/finance/' + path, {
        method: body === undefined ? 'GET' : 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(auth ? { Authorization: 'Bearer ' + auth } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      return { status: response.status, body: record(await response.json()) };
    }
    async function start() {
      app = await onboardingApp(db, undefined, {
        controllers: [FinanceController],
        providers: [
          PayrollService,
          ObligationsService,
          JwtStrategy,
          ManagerTenantService,
        ],
      });
      await app.listen(0, '127.0.0.1');
      base = await app.getUrl();
    }
    async function period() {
      const employee = await db.staff.create({
        data: {
          venueId,
          username: 'mgr06-employee-' + randomUUID(),
          pinHash: 'synthetic-unused',
          role: 'WAITER',
        },
      });
      const p = await db.payrollPeriod.create({
        data: {
          venueId,
          staffId: employee.id,
          staffName: employee.username,
          periodMonth: '2026-09',
          compensationType: 'MONTHLY_FIXED',
          rate: '1500.00',
          targetAmount: '1500.00',
        },
      });
      return { ...p, staffId: employee.id };
    }
    async function cycle() {
      const obligation = await db.financialObligation.create({
        data: {
          venueId,
          name: 'Synthetic rent ' + randomUUID(),
          type: 'RENT',
          monthlyAmount: '3000',
          dueDay: 30,
          startsOn: '2026-09-01',
        },
      });
      return db.obligationCycle.create({
        data: {
          venueId,
          obligationId: obligation.id,
          name: obligation.name,
          type: 'RENT',
          periodMonth: '2026-09',
          targetAmount: '3000',
          dueDate: '2026-09-30',
        },
      });
    }
    async function original(path: string, amount = '100.00') {
      const result = await request(path, {
        id: randomUUID(),
        amount,
        businessDate: historical,
        ...(path.endsWith('payments') ? { paymentDate: historical } : {}),
      });
      expect(result.status).toBe(201);
      return result.body;
    }
    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url))
        throw Error('Fresh disposable MGR06 database required');
      process.env.JWT_SECRET = 'mgr06-synthetic-only-signing';
      process.env.COOKIE_ENCRYPTION_KEY = 'mgr06-synthetic-only-cookie';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      await start();
      seeded = await seedMenu03(db, app);
      venueId = seeded.venues[0].venueId;
      organizationId = (
        await db.venue.findUniqueOrThrow({ where: { id: venueId } })
      ).organizationId;
      const assignment = await db.venuePlanAssignment.findUniqueOrThrow({
        where: { venueId },
      });
      for (const key of ['MANAGER_APP', 'PAYROLL', 'FINANCIAL_PLANNING']) {
        const f = await db.feature.upsert({
          where: { key },
          update: {},
          create: { key, name: 'Synthetic ' + key },
        });
        await db.planFeature.upsert({
          where: {
            planId_featureId: { planId: assignment.planId, featureId: f.id },
          },
          update: {},
          create: { planId: assignment.planId, featureId: f.id },
        });
      }
      const signer = new JwtService();
      const issue = async (venue: string, role: 'MANAGER' | 'WAITER') => {
        const s = await db.staff.create({
          data: {
            venueId: venue,
            username: 'mgr06-' + randomUUID(),
            role,
            pinHash: 'synthetic-unused',
          },
        });
        return {
          id: s.id,
          token: signer.sign(
            { sub: s.id, venueId: seeded.venues[1].venueId, role: 'MANAGER' },
            { secret: process.env.JWT_SECRET },
          ),
        };
      };
      const a = await issue(venueId, 'MANAGER');
      managerId = a.id;
      token = a.token;
      foreign = (await issue(seeded.venues[1].venueId, 'MANAGER')).token;
      waiter = (await issue(venueId, 'WAITER')).token;
      await db.setting.create({
        data: { venueId, key: 'currentBusinessDate', value: correctionDay },
      });
    }, 60000);
    afterAll(async () => {
      jest.restoreAllMocks();
      await app?.close();
      await db?.$disconnect();
    });
    beforeEach(async () => {
      await db.setting.update({
        where: { venueId_key: { venueId, key: 'currentBusinessDate' } },
        data: { value: correctionDay },
      });
    });
    it('corrects wrong payroll without delete, retains actor/reason/chronology and nets historical outflows', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`, '120.34');
      const path = `payroll/${p.id}/payments/${String(source.id)}/reversal`,
        body = input();
      const result = await request(path, body);
      expect(result.status).toBe(201);
      expect(result.body).toMatchObject({
        id: body.id,
        reversalOfId: source.id,
        amount: '-120.34',
        businessDate: historical,
        paymentDate: historical,
        correctionBusinessDate: correctionDay,
        actorId: managerId,
        notes: body.reason,
      });
      expect(
        JSON.parse(
          JSON.stringify(
            await db.payrollPayment.findUnique({
              where: { id: String(source.id) },
            }),
          ),
        ),
      ).toEqual(source);
      const history = await request(`staff/${p.staffId}/history`),
        presentation = rows(history.body.periods)[0];
      expect(presentation).toMatchObject({
        paid: '0.00',
        remaining: '1500.00',
        overpaid: '0.00',
      });
      expect(rows(presentation.payments)).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            id: source.id,
            reversedById: body.id,
            canReverse: false,
          }),
          expect.objectContaining({
            id: body.id,
            reversalOfId: source.id,
            canReverse: false,
          }),
        ]),
      );
      expect(
        (await financialPayments(db, { venueId, organizationId }, historical))
          .payrollPayments,
      ).toBe('0.00');
      const audit = await db.auditEventLog.findMany({
        where: {
          venueId,
          action: 'PAYROLL_PAYMENT_REVERSED',
          entityId: body.id,
        },
      });
      expect(audit).toHaveLength(1);
      expect(audit[0].userId).toBe(managerId);
      const feed = await new MobileAuditLogService(db).getAuditLog(
        { venueId, organizationId },
        { entityType: 'PAYROLL_PAYMENT', entityId: body.id },
      );
      expect(feed.items).toHaveLength(1);
      await original(`payroll/${p.id}/payments`, '20.30');
      expect(
        (await financialPayments(db, { venueId, organizationId }, historical))
          .payrollPayments,
      ).toBe('20.30');
    });
    it('parallel identical UUID, lost response and reopened server replay one immutable result/audit', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        body = input(),
        path = `payroll/${p.id}/payments/${String(source.id)}/reversal`;
      const results = await Promise.all(
        Array.from({ length: 6 }, () => request(path, body)),
      );
      expect(results.every((r) => r.status === 201)).toBe(true);
      results.forEach((r) => expect(r.body).toEqual(results[0].body));
      await db.setting.update({
        where: { venueId_key: { venueId, key: 'currentBusinessDate' } },
        data: { value: '2026-10-08' },
      });
      await app.close();
      await db.$disconnect();
      await db.$connect();
      await start();
      expect((await request(path, body)).body).toEqual(results[0].body);
      expect(
        await db.payrollPayment.count({ where: { payrollPeriodId: p.id } }),
      ).toBe(2);
      expect(
        await db.auditEventLog.count({
          where: {
            venueId,
            action: 'PAYROLL_PAYMENT_REVERSED',
            entityId: body.id,
          },
        }),
      ).toBe(1);
    });
    it('different concurrent reversal IDs admit one; changed retry reason and reversing reversal conflict', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        path = `payroll/${p.id}/payments/${String(source.id)}/reversal`,
        a = input(),
        b = input();
      const results = await Promise.all([request(path, a), request(path, b)]);
      expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
      const accepted = results.find((r) => r.status === 201)!;
      expect(
        (
          await request(path, {
            id: accepted.body.id,
            reason: 'Different reason',
          })
        ).status,
      ).toBe(409);
      expect(
        (
          await request(
            `payroll/${p.id}/payments/${String(accepted.body.id)}/reversal`,
            input(),
          )
        ).status,
      ).toBe(409);
      expect(
        await db.payrollPayment.count({ where: { payrollPeriodId: p.id } }),
      ).toBe(2);
    });
    it('cross-period key collision returns explicit conflict and cannot change either original', async () => {
      const a = await period(),
        b = await period(),
        x = await original(`payroll/${a.id}/payments`),
        y = await original(`payroll/${b.id}/payments`),
        body = input();
      const results = await Promise.all([
        request(`payroll/${a.id}/payments/${String(x.id)}/reversal`, body),
        request(`payroll/${b.id}/payments/${String(y.id)}/reversal`, body),
      ]);
      expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
      expect(
        await db.payrollPayment.count({
          where: { reversalOfId: { in: [String(x.id), String(y.id)] } },
        }),
      ).toBe(1);
    });
    it('authentication, current role, feature and Staff-derived Venue guard fresh and retained mutations', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        body = input(),
        path = `payroll/${p.id}/payments/${String(source.id)}/reversal`;
      expect((await request(path, body, '')).status).toBe(401);
      expect((await request(path, body, waiter)).status).toBe(401);
      expect((await request(path, body, foreign)).status).toBe(404);
      expect(
        (await request(path, { ...body, venueId: seeded.venues[1].venueId }))
          .status,
      ).toBe(400);
      expect((await request(path, body)).status).toBe(201);
      await db.staff.update({
        where: { id: managerId },
        data: { role: 'WAITER' },
      });
      expect((await request(path, body)).status).toBe(401);
      await db.staff.update({
        where: { id: managerId },
        data: { role: 'MANAGER' },
      });
      await db.venueSubscription.update({
        where: { venueId },
        data: { status: 'SUSPENDED' },
      });
      expect((await request(path, body)).status).toBe(401);
      await db.venueSubscription.update({
        where: { venueId },
        data: { status: 'ACTIVE' },
      });
      expect(
        await db.auditEventLog.count({
          where: { entityId: body.id, action: 'PAYROLL_PAYMENT_REVERSED' },
        }),
      ).toBe(1);
    });
    it('requires exact correction input and target ownership', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        path = `payroll/${p.id}/payments/${String(source.id)}/reversal`;
      for (const body of [
        null,
        [],
        {},
        { id: randomUUID(), reason: ' ' },
        { id: randomUUID(), reason: 12 },
        { id: 'bad', reason: 'bad' },
        { ...input(), amount: '-100' },
        { ...input(), businessDate: historical },
      ])
        expect((await request(path, body)).status).toBe(400);
      expect(
        (
          await request(
            `payroll/${randomUUID()}/payments/${String(source.id)}/reversal`,
            input(),
          )
        ).status,
      ).toBe(404);
    });
    it('atomic audit failure rolls back the reversal and retry succeeds', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        body = input();
      const failure = jest
        .spyOn(common, 'audit')
        .mockRejectedValueOnce(new Error('synthetic audit fault'));
      await expect(
        new PayrollService(db).reversePayment(
          {
            venueId,
            organizationId,
            staffId: managerId,
            username: 'Synthetic',
          },
          p.id,
          String(source.id),
          body,
        ),
      ).rejects.toThrow('synthetic audit fault');
      failure.mockRestore();
      expect(
        await db.payrollPayment.findUnique({ where: { id: body.id } }),
      ).toBeNull();
      expect(
        (
          await request(
            `payroll/${p.id}/payments/${String(source.id)}/reversal`,
            body,
          )
        ).status,
      ).toBe(201);
    });
    it('consumed reserves cannot be reversed or silently reallocated even when pool covers the amount', async () => {
      const c = await cycle(),
        reserve = await original(`cycles/${c.id}/reserves`),
        payment = await original(`cycles/${c.id}/payments`, '80.00');
      await original(`cycles/${c.id}/reserves`);
      expect(
        (
          await request(
            `cycles/${c.id}/reserves/${String(reserve.id)}/reversal`,
            input(),
          )
        ).status,
      ).toBe(409);
      const history = await request(`obligations/${c.obligationId}/history`),
        view = rows(history.body.cycles)[0];
      expect(view.reservedAmount).toBe('120.00');
      expect(rows(view.reserves).every((r) => r.canReverse === false)).toBe(
        true,
      );
      const correction = await request(
        `cycles/${c.id}/payments/${String(payment.id)}/reversal`,
        input(),
      );
      expect(correction.status).toBe(201);
      expect(correction.body).toMatchObject({
        amount: '-80',
        reserveConsumed: '-80',
        businessDate: historical,
        paymentDate: historical,
      });
      expect(
        (
          await request(
            `cycles/${c.id}/reserves/${String(reserve.id)}/reversal`,
            input(),
          )
        ).status,
      ).toBe(201);
      expect(
        (await financialPayments(db, { venueId, organizationId }, historical))
          .obligationPayments,
      ).toBe('0.00');
    });
    it('reserve retry precedes later consumption guards and retains its old correction date', async () => {
      const c = await cycle(),
        source = await original(`cycles/${c.id}/reserves`),
        body = input(),
        path = `cycles/${c.id}/reserves/${String(source.id)}/reversal`;
      const result = await request(path, body);
      expect(result.status).toBe(201);
      await original(`cycles/${c.id}/reserves`);
      await original(`cycles/${c.id}/payments`, '80.00');
      await db.setting.update({
        where: { venueId_key: { venueId, key: 'currentBusinessDate' } },
        data: { value: '2026-10-08' },
      });
      expect((await request(path, body)).body).toEqual(result.body);
    });
    it('payment reversal reopens PAID cycle and restores exact signed reserve consumption', async () => {
      const c = await cycle();
      await original(`cycles/${c.id}/reserves`, '3000.00');
      const payment = await original(`cycles/${c.id}/payments`, '3000.00');
      const before = rows(
        (await request(`obligations/${c.obligationId}/history`)).body.cycles,
      )[0];
      expect(before.status).toBe('PAID');
      const result = await request(
        `cycles/${c.id}/payments/${String(payment.id)}/reversal`,
        input(),
      );
      expect(result.status).toBe(201);
      const after = rows(
        (await request(`obligations/${c.obligationId}/history`)).body.cycles,
      )[0];
      expect(after).toMatchObject({
        paidAmount: '0.00',
        reservedAmount: '3000.00',
        remainingToPay: '3000.00',
        status: 'OVERDUE',
      });
    });
    it('both obligation correction routes enforce current feature, role and Venue for replay too', async () => {
      const c = await cycle(),
        reserve = await original(`cycles/${c.id}/reserves`),
        payment = await original(`cycles/${c.id}/payments`, '80.00');
      for (const [group, source] of [
        ['payments', payment],
        ['reserves', reserve],
      ] as const) {
        const path = `cycles/${c.id}/${group}/${String(source.id)}/reversal`,
          body = input();
        expect((await request(path, body, '')).status).toBe(401);
        expect((await request(path, body, waiter)).status).toBe(401);
        expect((await request(path, body, foreign)).status).toBe(404);
        expect((await request(path, body)).status).toBe(201);
        const feature = await db.feature.findUniqueOrThrow({
          where: { key: 'FINANCIAL_PLANNING' },
        });
        await db.venueFeatureOverride.create({
          data: { venueId, featureId: feature.id, effect: 'DISABLED' },
        });
        try {
          expect((await request(path, body)).status).toBe(403);
        } finally {
          await db.venueFeatureOverride.delete({
            where: { venueId_featureId: { venueId, featureId: feature.id } },
          });
        }
        expect((await request(path, body)).status).toBe(201);
      }
    });
    it('reserve reversal races safely with payment consumption under the same cycle lock', async () => {
      const c = await cycle(),
        reserve = await original(`cycles/${c.id}/reserves`);
      const [reversed, paid] = await Promise.all([
        request(
          `cycles/${c.id}/reserves/${String(reserve.id)}/reversal`,
          input(),
        ),
        request(`cycles/${c.id}/payments`, {
          id: randomUUID(),
          amount: '80.00',
          businessDate: historical,
          paymentDate: historical,
        }),
      ]);
      expect(paid.status).toBe(201);
      expect([201, 409]).toContain(reversed.status);
      const payments = await db.obligationPayment.findMany({
          where: { obligationCycleId: c.id },
        }),
        reserves = await db.obligationReserveEntry.findMany({
          where: { obligationCycleId: c.id },
        });
      const consumption = payments.reduce(
          (n, p) => n + Number(p.reserveConsumed),
          0,
        ),
        reserved =
          reserves.reduce((n, p) => n + Number(p.amount), 0) - consumption;
      expect(reserved).toBeGreaterThanOrEqual(0);
      if (reversed.status === 201) expect(consumption).toBe(0);
      else expect(consumption).toBe(80);
    });
    it('database sign/link constraints refuse wrong amount, foreign parent and reversal chains', async () => {
      const p = await period(),
        source = await original(`payroll/${p.id}/payments`),
        other = await period();
      const baseData = {
        id: randomUUID(),
        venueId,
        payrollPeriodId: p.id,
        amount: '-100',
        businessDate: historical,
        paymentDate: historical,
        correctionBusinessDate: correctionDay,
        notes: 'Synthetic raw constraint proof',
        actorId: managerId,
        actorName: 'Synthetic',
        reversalOfId: String(source.id),
      };
      await expect(
        db.payrollPayment.create({ data: { ...baseData, amount: '-1' } }),
      ).rejects.toThrow();
      await expect(
        db.payrollPayment.create({
          data: { ...baseData, payrollPeriodId: other.id },
        }),
      ).rejects.toThrow();
      await expect(
        db.payrollPayment.create({
          data: { ...baseData, paymentDate: correctionDay },
        }),
      ).rejects.toThrow();
      const accepted = await request(
        `payroll/${p.id}/payments/${String(source.id)}/reversal`,
        input(),
      );
      expect(accepted.status).toBe(201);
      await expect(
        db.payrollPayment.create({
          data: {
            ...baseData,
            id: randomUUID(),
            reversalOfId: String(accepted.body.id),
            amount: '100',
          },
        }),
      ).rejects.toThrow();
    });
  },
);
