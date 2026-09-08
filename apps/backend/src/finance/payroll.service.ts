import { inputObject } from './finance-rules';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CompensationType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { actorData, Actor, audit, financeDates, Tx } from './finance-common';
import { day, entryId, money, month, months, note, sum } from './finance-rules';

export interface CompensationInput {
  compensationType: string;
  amount: string;
  effectiveFrom: string;
  isActive?: boolean;
  notes?: string;
}
export interface PaymentInput {
  id: string;
  amount: string;
  businessDate: string;
  paymentDate: string;
  notes?: string;
}
export interface AccrualInput {
  id: string;
  payableDate?: string;
  amount?: string;
  notes?: string;
}
const include = {
  payments: { orderBy: { createdAt: 'desc' as const } },
  accruals: { orderBy: { createdAt: 'desc' as const } },
};
@Injectable()
export class PayrollService {
  constructor(private readonly db: PrismaService) {}
  private async lockStaff(tx: Tx, tenant: TenantContext, staffId: string) {
    await tx.$queryRaw`SELECT id FROM pos."Staff" WHERE id = ${staffId} AND "venueId" = ${tenant.venueId} FOR UPDATE`;
    const staff = await tx.staff.findFirst({
      where: { id: staffId, venueId: tenant.venueId },
      select: { id: true, username: true, isActive: true },
    });
    if (!staff) throw new NotFoundException('თანამშრომელი ვერ მოიძებნა');
    return staff;
  }
  private async materialize(
    tx: Tx,
    tenant: TenantContext,
    staffId: string,
    through: string,
  ) {
    const staff = await this.lockStaff(tx, tenant, staffId);
    const rules = await tx.staffCompensation.findMany({
      where: { venueId: tenant.venueId, staffId },
      orderBy: { effectiveFrom: 'asc' },
    });
    if (!rules.length) return;
    for (const periodMonth of months(
      rules[0].effectiveFrom.slice(0, 7),
      through,
    )) {
      const rule = [...rules]
        .reverse()
        .find((r) => r.effectiveFrom <= `${periodMonth}-01`);
      if (!rule?.isActive) continue;
      await tx.payrollPeriod.upsert({
        where: {
          venueId_staffId_periodMonth: {
            venueId: tenant.venueId,
            staffId,
            periodMonth,
          },
        },
        update: {},
        create: {
          venueId: tenant.venueId,
          staffId,
          staffName: staff.username,
          periodMonth,
          compensationType: rule.compensationType,
          rate: rule.amount,
          targetAmount:
            rule.compensationType === 'MONTHLY_FIXED' ? rule.amount : '0',
        },
      });
    }
  }
  async setCompensation(
    actor: Actor,
    staffId: string,
    input: CompensationInput,
  ) {
    inputObject(input);
    const amount = money(input.amount, input.compensationType === 'MANUAL');
    if (
      !Object.values(CompensationType).includes(
        input.compensationType as CompensationType,
      )
    )
      throw new BadRequestException('ხელფასის უცნობი წესი');
    const effectiveFrom = day(input.effectiveFrom);
    if (!effectiveFrom.endsWith('-01'))
      throw new BadRequestException('წესი მოქმედებს თვის პირველი რიცხვიდან');
    if (input.isActive !== undefined && typeof input.isActive !== 'boolean')
      throw new BadRequestException('isActive must be boolean');
    return this.db.$transaction(
      async (tx) => {
        await this.lockStaff(tx, actor, staffId);
        const dates = await financeDates(tx, actor);
        await this.materialize(tx, actor, staffId, dates.periodMonth);
        const latest = await tx.staffCompensation.findFirst({
          where: { venueId: actor.venueId, staffId },
          orderBy: { effectiveFrom: 'desc' },
        });
        const frozen = await tx.payrollPeriod.findFirst({
          where: {
            venueId: actor.venueId,
            staffId,
            periodMonth: { gte: effectiveFrom.slice(0, 7) },
          },
        });
        const notes = note(input.notes);
        const existing = await tx.staffCompensation.findUnique({
          where: {
            venueId_staffId_effectiveFrom: {
              venueId: actor.venueId,
              staffId,
              effectiveFrom,
            },
          },
        });
        // Identical retry is harmless even after the month has been frozen.
        if (
          existing &&
          existing.amount.eq(amount) &&
          existing.compensationType === input.compensationType &&
          existing.isActive === (input.isActive ?? true) &&
          existing.notes === notes
        )
          return existing;
        if (
          frozen ||
          (latest && latest.effectiveFrom > effectiveFrom) ||
          (existing && effectiveFrom.slice(0, 7) <= dates.periodMonth)
        )
          throw new ConflictException(
            'არსებული პერიოდი უცვლელია. აირჩიეთ შემდეგი თავისუფალი თვე.',
          );
        const data = {
          ...actorData(actor),
          staffId,
          amount,
          effectiveFrom,
          compensationType: input.compensationType as CompensationType,
          isActive: input.isActive ?? true,
          notes,
        };
        // Only an as-yet unopened future rule can be edited; its previous
        // value remains in Global Audit. Period snapshots are never updated.
        const rule = existing
          ? await tx.staffCompensation.update({
              where: { id: existing.id },
              data,
            })
          : await tx.staffCompensation.create({ data });
        await audit(tx, actor, 'STAFF_COMPENSATION_CHANGED', 'STAFF', staffId, {
          compensationId: rule.id,
          compensationType: rule.compensationType,
          amount: amount.toFixed(2),
          effectiveFrom,
          isActive: rule.isActive,
          previousAmount: existing?.amount.toFixed(2) ?? null,
        });
        await this.materialize(tx, actor, staffId, dates.periodMonth);
        return rule;
      },
      { timeout: 30000 },
    );
  }
  async overview(tenant: TenantContext, selectedMonth?: string) {
    return this.db.$transaction(
      async (tx) => {
        const dates = await financeDates(tx, tenant);
        const periodMonth = month(selectedMonth ?? dates.periodMonth);
        if (periodMonth > dates.periodMonth)
          throw new BadRequestException('მომავალი პერიოდი ჯერ არ გახსნილა');
        const staff = await tx.staff.findMany({
          where: {
            venueId: tenant.venueId,
            OR: [
              { isActive: true },
              { payrollPeriods: { some: {} } },
              { compensations: { some: {} } },
            ],
          },
          select: { id: true, username: true, isActive: true },
          orderBy: { username: 'asc' },
        });
        const result: unknown[] = [];
        for (const member of staff) {
          await this.materialize(tx, tenant, member.id, dates.periodMonth);
          const periods = await tx.payrollPeriod.findMany({
            where: { venueId: tenant.venueId, staffId: member.id, periodMonth },
            include,
          });
          const compensation = await tx.staffCompensation.findMany({
            where: { venueId: tenant.venueId, staffId: member.id },
            orderBy: { effectiveFrom: 'desc' },
          });
          result.push({
            ...member,
            compensation,
            period: periods[0] ? this.present(periods[0]) : null,
          });
        }
        return { ...dates, periodMonth, staff: result };
      },
      { timeout: 30000 },
    );
  }
  async history(tenant: TenantContext, staffId: string) {
    return this.db.$transaction(async (tx) => {
      await this.lockStaff(tx, tenant, staffId);
      const periods = await tx.payrollPeriod.findMany({
        where: { venueId: tenant.venueId, staffId },
        include,
        orderBy: { periodMonth: 'desc' },
      });
      return { periods: periods.map((p) => this.present(p)) };
    });
  }
  private present(
    p: Prisma.PayrollPeriodGetPayload<{ include: typeof include }>,
  ) {
    const expected = p.targetAmount.plus(sum(p.accruals));
    const paid = sum(p.payments);
    return {
      ...p,
      rate: p.rate.toFixed(2),
      targetAmount: p.targetAmount.toFixed(2),
      expected: expected.toFixed(2),
      paid: paid.toFixed(2),
      remaining: Prisma.Decimal.max(0, expected.minus(paid)).toFixed(2),
      overpaid: Prisma.Decimal.max(0, paid.minus(expected)).toFixed(2),
      payments: p.payments.map((e) => ({ ...e, amount: e.amount.toFixed(2) })),
      accruals: p.accruals.map((e) => ({ ...e, amount: e.amount.toFixed(2) })),
    };
  }
  private async lockPeriod(tx: Tx, tenant: TenantContext, id: string) {
    await tx.$queryRaw`SELECT id FROM pos."PayrollPeriod" WHERE id = ${id} AND "venueId" = ${tenant.venueId} FOR UPDATE`;
    const p = await tx.payrollPeriod.findFirst({
      where: { id, venueId: tenant.venueId },
    });
    if (!p) throw new NotFoundException('ხელფასის პერიოდი ვერ მოიძებნა');
    return p;
  }
  async recordPayment(actor: Actor, periodId: string, input: PaymentInput) {
    inputObject(input);
    const data = {
      id: entryId(input.id),
      amount: money(input.amount),
      businessDate: day(input.businessDate),
      paymentDate: day(input.paymentDate),
      notes: note(input.notes),
    };
    return this.db.$transaction(async (tx) => {
      const period = await this.lockPeriod(tx, actor, periodId);
      const existing = await tx.payrollPayment.findUnique({
        where: { id: data.id },
      });
      if (existing) {
        if (
          existing.venueId !== actor.venueId ||
          existing.payrollPeriodId !== periodId ||
          !existing.amount.eq(data.amount) ||
          existing.businessDate !== data.businessDate ||
          existing.paymentDate !== data.paymentDate ||
          existing.notes !== data.notes
        )
          throw new ConflictException(
            'გადახდის იდენტიფიკატორი უკვე გამოყენებულია',
          );
        return existing;
      }
      const payment = await tx.payrollPayment.create({
        data: { ...data, ...actorData(actor), payrollPeriodId: periodId },
      });
      await audit(
        tx,
        actor,
        'PAYROLL_PAYMENT_RECORDED',
        'PAYROLL_PAYMENT',
        payment.id,
        {
          staffId: period.staffId,
          periodMonth: period.periodMonth,
          amount: data.amount.toFixed(2),
          businessDate: data.businessDate,
        },
      );
      return payment;
    });
  }
  async recordAccrual(actor: Actor, periodId: string, input: AccrualInput) {
    inputObject(input);
    const id = entryId(input.id),
      notes = note(input.notes);
    return this.db.$transaction(async (tx) => {
      const period = await this.lockPeriod(tx, actor, periodId);
      if (period.compensationType === 'MONTHLY_FIXED')
        throw new BadRequestException('თვიურ წესს სამუშაო დღეები არ ემატება');
      const payableDate =
        period.compensationType === 'DAILY_FIXED'
          ? day(input.payableDate)
          : null;
      if (payableDate && payableDate.slice(0, 7) !== period.periodMonth)
        throw new BadRequestException(
          'სამუშაო დღე უნდა ეკუთვნოდეს არჩეულ თვეს',
        );
      const amount = payableDate ? period.rate : money(input.amount);
      const existing = await tx.payrollAccrual.findUnique({ where: { id } });
      if (existing) {
        if (
          existing.venueId !== actor.venueId ||
          existing.payrollPeriodId !== periodId ||
          existing.payableDate !== payableDate ||
          !existing.amount.eq(amount) ||
          existing.notes !== notes
        )
          throw new ConflictException(
            'ჩანაწერის იდენტიფიკატორი უკვე გამოყენებულია',
          );
        return existing;
      }
      if (
        payableDate &&
        (await tx.payrollAccrual.findFirst({
          where: { payrollPeriodId: periodId, payableDate },
        }))
      )
        throw new ConflictException('ეს სამუშაო დღე უკვე დამატებულია');
      const entry = await tx.payrollAccrual.create({
        data: {
          id,
          ...actorData(actor),
          payrollPeriodId: periodId,
          payableDate,
          amount,
          notes,
        },
      });
      await audit(
        tx,
        actor,
        'PAYROLL_ACCRUAL_RECORDED',
        'PAYROLL_PERIOD',
        periodId,
        {
          entryId: id,
          staffId: period.staffId,
          amount: amount.toFixed(2),
          payableDate,
        },
      );
      return entry;
    });
  }
}
