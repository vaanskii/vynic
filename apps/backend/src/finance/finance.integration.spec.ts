import { MobileUsersService } from '../mobile/services/mobile-users.service';
jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
jest.mock('../pos/pos-command-dispatcher.service', () => ({
  PosCommandDispatcher: class {},
}));
jest.mock('../mobile/services/mobile-mutation-support.service', () => ({
  MobileMutationSupport: class {},
}));
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { PayrollService } from './payroll.service';
import { ObligationsService } from './obligations.service';
import { FinanceController } from './finance.controller';
import { MobileDashboardService } from '../mobile/services/mobile-dashboard.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { MobileAuditLogService } from '../mobile/services/mobile-audit-log.service';
import * as common from './finance-common';
import type { Actor } from './finance-common';
const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Payroll / obligations (disposable PostgreSQL)',
  () => {
    let db: PrismaService,
      payroll: PayrollService,
      obligations: ObligationsService,
      controller: FinanceController;
    let a: Actor, b: Actor, staff: string, daily: string, manual: string;
    let now = new Date('2026-09-15T12:00:00Z');
    const realDates = common.financeDates;
    const pay = (amount: string, businessDate = '2026-09-15') => ({
      id: randomUUID(),
      amount,
      businessDate,
      paymentDate: '2026-09-15',
    });
    const template = (type = 'RENT', monthlyAmount = '3000.00') => ({
      name: type === 'RENT' ? 'ქირა' : 'საქართველოს ბანკი — სესხი',
      type,
      monthlyAmount,
      dueDay: 30,
      startsOn: '2026-09-01',
    });
    const period = async (id: string) =>
      ((await payroll.overview(a)).staff as any[]).find((s) => s.id === id)
        .period;
    beforeAll(async () => {
      if (!url?.includes('vynic_step47_test'))
        throw new Error('Use only vynic_step47_test disposable database');
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const org = randomUUID(),
        va = randomUUID(),
        vb = randomUUID();
      await db.organization.create({
        data: {
          id: org,
          name: 'Finance test',
          venues: {
            create: [va, vb].map((id) => ({
              id,
              name: 'Test',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })),
          },
        },
      });
      a = {
        venueId: va,
        organizationId: org,
        staffId: randomUUID(),
        username: 'Manager A',
      };
      b = { ...a, venueId: vb, staffId: randomUUID(), username: 'Manager B' };
      [staff, daily, manual] = [randomUUID(), randomUUID(), randomUUID()];
      await db.staff.createMany({
        data: [staff, daily, manual].map((id, i) => ({
          id,
          venueId: va,
          username: ['Giorgi', 'Nika', 'Custom'][i],
          pinHash: 'never-return',
        })),
      });
      await db.staff.create({
        data: {
          id: b.staffId,
          venueId: vb,
          username: b.username,
          pinHash: 'private',
        },
      });
      await db.setting.create({
        data: { venueId: va, key: 'currentBusinessDate', value: '2026-09-15' },
      });
      payroll = new PayrollService(db);
      obligations = new ObligationsService(db);
      controller = new FinanceController(payroll, obligations, db);
      jest
        .spyOn(common, 'financeDates')
        .mockImplementation((tx, t) => realDates(tx, t, now));
    });
    afterAll(async () => {
      jest.restoreAllMocks();
      const where = { venueId: { in: [a.venueId, b.venueId] } };
      for (const table of [
        'payrollPayment',
        'payrollAccrual',
        'payrollPeriod',
        'staffCompensation',
        'obligationPayment',
        'obligationReserveEntry',
        'obligationCycle',
        'financialObligation',
        'receiving',
        'supplier',
        'expense',
        'auditEventLog',
        'setting',
        'staff',
      ] as const)
        await (db[table] as any).deleteMany({ where });
      await db.venue.deleteMany({ where: { id: where.venueId } });
      await db.organization.delete({ where: { id: a.organizationId } });
      await db.$disconnect();
    });
    it('monthly salary freezes 1500; two historical payments show 800 paid / 700 remaining', async () => {
      await payroll.setCompensation(a, staff, {
        compensationType: 'MONTHLY_FIXED',
        amount: '1500.00',
        effectiveFrom: '2026-09-01',
      });
      let p = await period(staff);
      expect(p).toMatchObject({
        expected: '1500.00',
        paid: '0.00',
        remaining: '1500.00',
      });
      await payroll.recordPayment(a, p.id, pay('500.00', '2026-09-05'));
      const second = pay('300.00');
      await Promise.all([
        payroll.recordPayment(a, p.id, second),
        payroll.recordPayment(a, p.id, second),
      ]);
      p = await period(staff);
      expect(p).toMatchObject({
        expected: '1500.00',
        paid: '800.00',
        remaining: '700.00',
      });
      expect(p.payments).toHaveLength(2);
      expect(await db.expense.count({ where: { venueId: a.venueId } })).toBe(0);
      expect(JSON.stringify(await payroll.overview(a))).not.toMatch(
        /pinHash|pinCode|never-return/,
      );
      await expect(
        payroll.recordPayment(a, p.id, { ...second, amount: '400.00' }),
      ).rejects.toThrow('გამოყენებულია');
    });
    it('daily rate requires explicit unique worked days; manual requires an exact accrual', async () => {
      await payroll.setCompensation(a, daily, {
        compensationType: 'DAILY_FIXED',
        amount: '60.00',
        effectiveFrom: '2026-09-01',
      });
      const p = await period(daily);
      expect(p.expected).toBe('0.00');
      const entry = { id: randomUUID(), payableDate: '2026-09-03' };
      await payroll.recordAccrual(a, p.id, entry);
      await payroll.recordAccrual(a, p.id, entry);
      await expect(
        payroll.recordAccrual(a, p.id, { ...entry, id: randomUUID() }),
      ).rejects.toThrow('უკვე');
      await expect(
        payroll.recordAccrual(a, p.id, {
          id: randomUUID(),
          payableDate: '2026-08-03',
        }),
      ).rejects.toThrow('არჩეულ თვეს');
      expect((await period(daily)).expected).toBe('60.00');
      await payroll.setCompensation(a, manual, {
        compensationType: 'MANUAL',
        amount: '0.00',
        effectiveFrom: '2026-09-01',
      });
      await payroll.recordAccrual(a, (await period(manual)).id, {
        id: randomUUID(),
        amount: '0.10',
      });
      await payroll.recordAccrual(a, (await period(manual)).id, {
        id: randomUUID(),
        amount: '0.20',
      });
      expect((await period(manual)).expected).toBe('0.30');
      await expect(
        payroll.setCompensation(a, manual, {
          compensationType: 'HOURLY',
          amount: '10',
          effectiveFrom: '2026-10-01',
        }),
      ).rejects.toThrow();
    });
    it('rejects compensation edits that rewrite a frozen month, applies next month rule on rollover', async () => {
      await expect(
        payroll.setCompensation(a, staff, {
          compensationType: 'MONTHLY_FIXED',
          amount: '2000',
          effectiveFrom: '2026-09-01',
        }),
      ).rejects.toThrow('უცვლელია');
      await payroll.setCompensation(a, staff, {
        compensationType: 'MONTHLY_FIXED',
        amount: '2000',
        effectiveFrom: '2026-10-01',
      });
      now = new Date('2026-10-02T12:00:00Z');
      expect((await period(staff)).expected).toBe('2000.00');
      const history = await payroll.history(a, staff);
      expect(
        history.periods.find((p) => p.periodMonth === '2026-09'),
      ).toMatchObject({ expected: '1500.00', paid: '800.00' });
      now = new Date('2026-09-15T12:00:00Z');
    });
    let rent: string, cycleId: string;
    it('rent and bank cycles snapshot independent monthly targets and due dates', async () => {
      rent = (await obligations.create(a, template())).id;
      const bank = await obligations.create(a, {
        ...template('BANK_LOAN', '1500'),
        dueDay: 25,
      });
      const data = await obligations.overview(a);
      const cycle = data.cycles.find((c) => c.obligationId === rent)!;
      cycleId = cycle.id;
      expect(cycle).toMatchObject({
        targetAmount: '3000.00',
        dueDate: '2026-09-30',
        dailyRecommendedReserve: '187.50',
      });
      expect(data.cycles.find((c) => c.obligationId === bank.id)).toMatchObject(
        { targetAmount: '1500.00', dueDate: '2026-09-25' },
      );
    });
    it('reserves are planning only; payments consume reserves and retry once under concurrency', async () => {
      await obligations.record(a, cycleId, pay('600'), false);
      const payment = pay('500');
      await Promise.all([
        obligations.record(a, cycleId, payment, true),
        obligations.record(a, cycleId, payment, true),
      ]);
      const c = (await obligations.history(a, rent)).cycles[0];
      expect(c).toMatchObject({
        reservedAmount: '100.00',
        paidAmount: '500.00',
        coveredAmount: '600.00',
        remainingToCover: '2400.00',
        dailyRecommendedReserve: '150.00',
      });
      expect(c.payments).toHaveLength(1);
      expect(c.payments[0].reserveConsumed).toBe('500.00');
      const competing = await Promise.allSettled([
        obligations.record(a, cycleId, pay('2000'), false),
        obligations.record(a, cycleId, pay('2000'), false),
      ]);
      expect(competing.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(await db.expense.count({ where: { venueId: a.venueId } })).toBe(0);
    });
    it('configuration changes do not rewrite previous cycles and month rollover creates the new target once', async () => {
      await obligations.update(a, rent, {
        ...template(),
        monthlyAmount: '3100',
        dueDay: 31,
      });
      expect((await obligations.history(a, rent)).cycles[0]).toMatchObject({
        targetAmount: '3000.00',
        dueDate: '2026-09-30',
      });
      now = new Date('2026-10-02T12:00:00Z');
      await Promise.all([obligations.overview(a), obligations.overview(a)]);
      expect((await obligations.history(a, rent)).cycles[0]).toMatchObject({
        targetAmount: '3100.00',
        dueDate: '2026-10-31',
      });
      expect(
        await db.obligationCycle.count({ where: { obligationId: rent } }),
      ).toBe(2);
      now = new Date('2026-09-15T12:00:00Z');
    });
    it('disabling preserves open cycles and reactivation does not fabricate cycles in inactive months', async () => {
      const t = await obligations.create(a, {
        ...template(),
        name: 'Internet',
      });
      await obligations.update(a, t.id, {
        ...template(),
        name: 'Internet',
        isActive: false,
      });
      now = new Date('2026-11-02T12:00:00Z');
      await obligations.update(a, t.id, {
        ...template(),
        name: 'Internet',
        isActive: true,
      });
      now = new Date('2026-12-02T12:00:00Z');
      await obligations.overview(a);
      expect(
        (await obligations.history(a, t.id)).cycles.map((c) => c.periodMonth),
      ).toEqual(['2026-12', '2026-09']);
      now = new Date('2026-09-15T12:00:00Z');
    });
    it('Venue B cannot edit A compensation, pay A payroll, reserve A cycle or read A history; database FKs also reject cross-Venue links', async () => {
      await expect(
        payroll.setCompensation(b, staff, {
          compensationType: 'MONTHLY_FIXED',
          amount: '900',
          effectiveFrom: '2027-01-01',
        }),
      ).rejects.toThrow('ვერ მოიძებნა');
      await expect(payroll.history(b, staff)).rejects.toThrow('ვერ მოიძებნა');
      await expect(
        payroll.recordPayment(b, (await period(staff)).id, pay('1')),
      ).rejects.toThrow('ვერ მოიძებნა');
      await expect(
        obligations.record(b, cycleId, pay('1'), false),
      ).rejects.toThrow('ვერ მოიძებნა');
      await expect(obligations.history(b, rent)).rejects.toThrow(
        'ვერ მოიძებნა',
      );
      await expect(obligations.update(b, rent, template())).rejects.toThrow(
        'ვერ მოიძებნა',
      );
      expect((await obligations.overview(b)).cycles).toEqual([]);
      await expect(
        db.payrollPeriod.create({
          data: {
            venueId: b.venueId,
            staffId: staff,
            staffName: 'no',
            periodMonth: '2027-01',
            compensationType: 'MONTHLY_FIXED',
            rate: '1',
            targetAmount: '1',
          },
        }),
      ).rejects.toThrow();
    });
    it('Financials includes Receiving + other Expenses + legacy/new payroll + obligation payments exactly once, excludes reserves', async () => {
      const supplier = await db.supplier.create({
        data: { venueId: a.venueId, name: 'Supplier' },
      });
      await db.receiving.create({
        data: {
          venueId: a.venueId,
          supplierId: supplier.id,
          supplierNameSnapshot: supplier.name,
          receivedAt: now,
          createdById: a.staffId,
          createdByName: a.username,
          documentDate: '2026-09-01',
          businessDate: '2026-09-15',
          documentTotal: '500',
          status: 'POSTED',
        },
      });
      const legacy = await db.expense.create({
        data: {
          venueId: a.venueId,
          description: 'Legacy staff',
          category: 'პერსონალი',
          amount: 75,
          createdAt: new Date('2026-09-15T10:00:00Z'),
        },
      });
      await db.expense.create({
        data: {
          venueId: a.venueId,
          description: 'Taxi',
          category: 'Taxi',
          amount: 25,
          businessDate: '2026-09-15',
          createdAt: new Date('2026-09-16T01:00:00Z'),
        },
      });
      const dashboard = new MobileDashboardService(
        db,
        {} as any,
        {} as any,
        {} as any,
      );
      const financials = await dashboard.getFinancials(a);
      expect(financials).toMatchObject({
        payrollPayments: '300.00',
        legacySalaryPayments: '75.00',
        salaryPayments: '375.00',
        obligationPayments: '500.00',
        otherExpenses: '25.00',
        totalOutflows: '1400.00',
      });
      expect((await controller.legacy(a)).entries).toHaveLength(1);
      await expect(dashboard.deleteExpense(a, legacy.id)).rejects.toThrow(
        'მხოლოდ',
      );
      await expect(
        dashboard.createExpense(a, {
          category: 'salary',
          amount: 10,
          description: 'No',
        }),
      ).rejects.toThrow('ხელფასები');
      await db.setting.update({
        where: {
          venueId_key: { venueId: a.venueId, key: 'currentBusinessDate' },
        },
        data: { value: '2026-09-16' },
      });
      expect((await dashboard.getFinancials(a)).payrollPayments).toBe('0.00');
      expect(
        (await payroll.history(a, staff)).periods.find(
          (p) => p.periodMonth === '2026-09',
        )?.paid,
      ).toBe('800.00');
      expect(
        (await obligations.history(a, rent)).cycles.find(
          (c) => c.periodMonth === '2026-09',
        )?.paidAmount,
      ).toBe('500.00');
    });
    it('important mutations write tenant-scoped Global Audit rows with stable IDs and no credential content; reads add no audit events', async () => {
      const rows = await db.auditEventLog.findMany({
        where: { venueId: a.venueId },
      });
      for (const action of [
        'STAFF_COMPENSATION_CHANGED',
        'PAYROLL_PAYMENT_RECORDED',
        'PAYROLL_ACCRUAL_RECORDED',
        'FINANCIAL_OBLIGATION_CREATED',
        'FINANCIAL_OBLIGATION_UPDATED',
        'FINANCIAL_OBLIGATION_DISABLED',
        'OBLIGATION_RESERVE_RECORDED',
        'OBLIGATION_PAYMENT_RECORDED',
      ])
        expect(rows.some((r) => r.action === action && r.entityId)).toBe(true);
      expect(
        rows.filter((r) => r.action === 'PAYROLL_PAYMENT_RECORDED'),
      ).toHaveLength(2);
      expect(
        rows.filter((r) => r.action === 'OBLIGATION_PAYMENT_RECORDED'),
      ).toHaveLength(1);
      expect(JSON.stringify(rows)).not.toMatch(/pinHash|pinCode|never-return/);
      await controller.planning(a);
      expect(
        await db.auditEventLog.count({ where: { venueId: a.venueId } }),
      ).toBe(rows.length);
      const reader = new MobileAuditLogService(db);
      // Existing feed must accept the new entity filter.
      const feed = await reader.getAuditLog(a, {
        entityType: 'PAYROLL_PAYMENT',
      });
      expect(feed.items).toHaveLength(2);
      expect(
        (await reader.getAuditLog(b, { entityType: 'PAYROLL_PAYMENT' })).items,
      ).toHaveLength(0);
    });
    it('Manager Staff removal preserves referenced identity and allows a later stop rule', async () => {
      const service = new MobileUsersService(
        db,
        { dispatch: async () => ({ delivery: 'queued' }) } as any,
        { read: async () => ({}), write: async () => {} } as any,
      );
      await service.deleteUser(a, 'Nika');
      expect(
        (await db.staff.findUniqueOrThrow({ where: { id: daily } })).isActive,
      ).toBe(false);
      await payroll.setCompensation(a, daily, {
        compensationType: 'DAILY_FIXED',
        amount: '60.00',
        effectiveFrom: '2027-01-01',
        isActive: false,
      });
      expect(
        (await payroll.history(a, daily)).periods.find((p) => p.periodMonth === '2026-09')!.accruals,
      ).toHaveLength(1);
    });
    it('retries obligation creation and compensation without duplicate audit, and permits editing only unopened future rules', async () => {
      const body = { ...template(), id: randomUUID(), name: 'Retry loan' };
      const [one, two] = await Promise.all([
        obligations.create(a, body),
        obligations.create(a, body),
      ]);
      expect(one.id).toBe(two.id);
      expect(
        await db.auditEventLog.count({
          where: { entityId: one.id, action: 'FINANCIAL_OBLIGATION_CREATED' },
        }),
      ).toBe(1);
      const rule = {
        compensationType: 'MONTHLY_FIXED',
        amount: '2100.00',
        effectiveFrom: '2027-02-01',
      };
      const created = await payroll.setCompensation(a, staff, rule);
      expect((await payroll.setCompensation(a, staff, rule)).id).toBe(
        created.id,
      );
      await payroll.setCompensation(a, staff, { ...rule, amount: '2200.00' });
      expect(
        (await payroll.history(a, staff)).periods.find(
          (p) => p.periodMonth === '2026-09',
        )?.expected,
      ).toBe('1500.00');
    });
    it('POS staff removal retains payroll identity and history but revokes active login', async () => {
      const sync = new StaffSyncService(db, {
        read: async () => ({}),
        write: async () => {},
      } as any);
      await sync.sync(a, []);
      expect(
        (await db.staff.findUniqueOrThrow({ where: { id: staff } })).isActive,
      ).toBe(false);
      expect((await payroll.history(a, staff)).periods).toHaveLength(2);
    });
  },
);
