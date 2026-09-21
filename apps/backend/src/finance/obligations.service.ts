import { inputObject } from './finance-rules';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { FinancialObligationType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { Actor, actorData, audit, financeDates, Tx } from './finance-common';
import {
  day,
  dueDate,
  entryId,
  money,
  month,
  months,
  note,
  reservePlan,
  sum,
  zero,
} from './finance-rules';
import type { PaymentInput } from './payroll.service';
export interface ObligationInput {
  id?: string;
  name: string;
  type: string;
  monthlyAmount: string;
  dueDay: number;
  startsOn: string;
  endsOn?: string | null;
  isActive?: boolean;
  notes?: string;
}
const include = {
  reserves: { orderBy: { createdAt: 'desc' as const } },
  payments: { orderBy: { createdAt: 'desc' as const } },
};
@Injectable()
export class ObligationsService {
  constructor(private readonly db: PrismaService) {}
  private validate(input: ObligationInput) {
    inputObject(input);
    if (
      typeof input.name !== 'string' ||
      !input.name.trim() ||
      input.name.trim().length > 160
    )
      throw new BadRequestException('დასახელება: 1–160 სიმბოლო');
    if (
      !Object.values(FinancialObligationType).includes(
        input.type as FinancialObligationType,
      )
    )
      throw new BadRequestException('ვალდებულების უცნობი ტიპი');
    if (
      !Number.isInteger(input.dueDay) ||
      input.dueDay < 1 ||
      input.dueDay > 31
    )
      throw new BadRequestException('გადახდის რიცხვი: 1–31');
    const startsOn = day(input.startsOn),
      endsOn = input.endsOn ? day(input.endsOn) : null;
    if (endsOn && endsOn < startsOn)
      throw new BadRequestException('დასრულება დაწყებაზე ადრეა');
    if (input.isActive !== undefined && typeof input.isActive !== 'boolean')
      throw new BadRequestException('isActive must be boolean');
    return {
      name: input.name.trim(),
      type: input.type as FinancialObligationType,
      monthlyAmount: money(input.monthlyAmount),
      dueDay: input.dueDay,
      startsOn,
      endsOn,
      isActive: input.isActive ?? true,
      notes: note(input.notes),
    };
  }
  private async materialize(
    tx: Tx,
    tenant: TenantContext,
    id: string,
    through: string,
  ) {
    await tx.$queryRaw`SELECT id FROM pos."FinancialObligation" WHERE id = ${id} AND "venueId" = ${tenant.venueId} FOR UPDATE`;
    const obligation = await tx.financialObligation.findFirst({
      where: { id, venueId: tenant.venueId },
    });
    if (!obligation) throw new NotFoundException('ვალდებულება ვერ მოიძებნა');
    if (
      obligation.materializedThrough &&
      obligation.materializedThrough >= through
    )
      return obligation;
    for (const periodMonth of months(
      obligation.startsOn.slice(0, 7),
      through,
    )) {
      if (
        obligation.materializedThrough &&
        periodMonth <= obligation.materializedThrough
      )
        continue;
      const due = dueDate(periodMonth, obligation.dueDay);
      if (
        !obligation.isActive ||
        due < obligation.startsOn ||
        (obligation.endsOn && due > obligation.endsOn)
      )
        continue;
      await tx.obligationCycle.upsert({
        where: {
          venueId_obligationId_periodMonth: {
            venueId: tenant.venueId,
            obligationId: id,
            periodMonth,
          },
        },
        update: {},
        create: {
          venueId: tenant.venueId,
          obligationId: id,
          periodMonth,
          name: obligation.name,
          type: obligation.type,
          targetAmount: obligation.monthlyAmount,
          dueDate: due,
        },
      });
    }
    return tx.financialObligation.update({
      where: { id },
      data: { materializedThrough: through },
    });
  }
  async create(actor: Actor, input: ObligationInput) {
    const data = this.validate(input);
    return this.db.$transaction(
      async (tx) => {
        const id = input.id === undefined ? undefined : entryId(input.id);
        // Serialize creation/retries per Venue before checking a supplied UUID.
        await tx.$queryRaw`SELECT id FROM pos."Venue" WHERE id = ${actor.venueId} FOR UPDATE`;
        if (id) {
          const existing = await tx.financialObligation.findUnique({
            where: { id },
          });
          if (existing) {
            if (
              existing.venueId !== actor.venueId ||
              !Object.entries(data).every(([key, value]) =>
                key === 'monthlyAmount'
                  ? existing.monthlyAmount.eq(data.monthlyAmount)
                  : existing[key] === value,
              )
            )
              throw new ConflictException(
                'ვალდებულების იდენტიფიკატორი უკვე გამოყენებულია',
              );
            return existing;
          }
        }
        const created = await tx.financialObligation.create({
          data: { ...data, id, venueId: actor.venueId },
        });
        await audit(
          tx,
          actor,
          'FINANCIAL_OBLIGATION_CREATED',
          'FINANCIAL_OBLIGATION',
          created.id,
          {
            name: created.name,
            monthlyAmount: data.monthlyAmount.toFixed(2),
            dueDay: data.dueDay,
          },
        );
        await this.materialize(
          tx,
          actor,
          created.id,
          (await financeDates(tx, actor)).periodMonth,
        );
        return created;
      },
      { timeout: 30000 },
    );
  }
  async update(actor: Actor, id: string, input: ObligationInput) {
    const data = this.validate(input);
    return this.db.$transaction(
      async (tx) => {
        const current = await this.materialize(
          tx,
          actor,
          id,
          (await financeDates(tx, actor)).periodMonth,
        );
        if (current.startsOn !== data.startsOn)
          throw new BadRequestException('დაწყების თარიღი უცვლელია');
        if (
          Object.entries(data).every(([key, value]) =>
            key === 'monthlyAmount'
              ? current.monthlyAmount.eq(data.monthlyAmount)
              : current[key] === value,
          )
        )
          return current;
        const updated = await tx.financialObligation.update({
          where: { id },
          data,
        });
        await audit(
          tx,
          actor,
          current.isActive && !updated.isActive
            ? 'FINANCIAL_OBLIGATION_DISABLED'
            : 'FINANCIAL_OBLIGATION_UPDATED',
          'FINANCIAL_OBLIGATION',
          id,
          {
            name: updated.name,
            monthlyAmount: data.monthlyAmount.toFixed(2),
            dueDay: data.dueDay,
            isActive: updated.isActive,
            appliesAfterMonth: current.materializedThrough,
          },
        );
        return updated;
      },
      { timeout: 30000 },
    );
  }
  present(
    c: Prisma.ObligationCycleGetPayload<{ include: typeof include }>,
    today: string,
  ) {
    return {
      ...c,
      targetAmount: c.targetAmount.toFixed(2),
      ...reservePlan(
        c.targetAmount,
        sum(c.reserves),
        sum(c.payments),
        c.payments.reduce((s, p) => s.plus(p.reserveConsumed), zero()),
        c.dueDate,
        today,
      ),
      reserves: c.reserves.map((e) => ({ ...e, amount: e.amount.toFixed(2) })),
      payments: c.payments.map((e) => ({
        ...e,
        amount: e.amount.toFixed(2),
        reserveConsumed: e.reserveConsumed.toFixed(2),
      })),
    };
  }
  async overview(tenant: TenantContext, selectedMonth?: string) {
    return this.db.$transaction(
      async (tx) => {
        const dates = await financeDates(tx, tenant);
        const periodMonth = month(selectedMonth ?? dates.periodMonth);
        if (periodMonth > dates.periodMonth)
          throw new BadRequestException('მომავალი პერიოდი ჯერ არ გახსნილა');
        const templates = await tx.financialObligation.findMany({
          where: { venueId: tenant.venueId },
          orderBy: { name: 'asc' },
        });
        for (const template of templates)
          await this.materialize(tx, tenant, template.id, dates.periodMonth);
        const cycles = await tx.obligationCycle.findMany({
          where: { venueId: tenant.venueId, periodMonth },
          include,
          orderBy: { dueDate: 'asc' },
        });
        return {
          ...dates,
          periodMonth,
          obligations: templates.map((t) => ({
            ...t,
            monthlyAmount: t.monthlyAmount.toFixed(2),
          })),
          cycles: cycles.map((c) => this.present(c, dates.today)),
        };
      },
      { timeout: 30000 },
    );
  }
  async history(tenant: TenantContext, id: string) {
    const template = await this.db.financialObligation.findFirst({
      where: { id, venueId: tenant.venueId },
    });
    if (!template) throw new NotFoundException('ვალდებულება ვერ მოიძებნა');
    const dates = await financeDates(this.db, tenant);
    const cycles = await this.db.obligationCycle.findMany({
      where: { obligationId: id, venueId: tenant.venueId },
      include,
      orderBy: { periodMonth: 'desc' },
    });
    return { cycles: cycles.map((c) => this.present(c, dates.today)) };
  }
  async record(
    actor: Actor,
    cycleId: string,
    input: Omit<PaymentInput, 'paymentDate'> & { paymentDate?: string },
    payment: boolean,
  ) {
    inputObject(input);
    const data = {
      id: entryId(input.id),
      amount: money(input.amount),
      businessDate: day(input.businessDate),
      notes: note(input.notes),
    };
    const paymentDate = payment ? day(input.paymentDate) : null;
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."ObligationCycle" WHERE id = ${cycleId} AND "venueId" = ${actor.venueId} FOR UPDATE`;
      const cycle = await tx.obligationCycle.findFirst({
        where: { id: cycleId, venueId: actor.venueId },
        include,
      });
      if (!cycle)
        throw new NotFoundException('ვალდებულების პერიოდი ვერ მოიძებნა');
      const existing = payment
        ? await tx.obligationPayment.findUnique({ where: { id: data.id } })
        : await tx.obligationReserveEntry.findUnique({
            where: { id: data.id },
          });
      if (existing) {
        if (
          existing.venueId !== actor.venueId ||
          existing.obligationCycleId !== cycleId ||
          !existing.amount.eq(data.amount) ||
          existing.businessDate !== data.businessDate ||
          existing.notes !== data.notes ||
          (payment && existing['paymentDate'] !== paymentDate)
        )
          throw new ConflictException(
            'ჩანაწერის იდენტიფიკატორი უკვე გამოყენებულია',
          );
        return existing;
      }
      const plan = this.present(cycle, (await financeDates(tx, actor)).today);
      if (data.amount.gt(payment ? plan.remainingToPay : plan.remainingToCover))
        throw new BadRequestException('თანხა აჭარბებს დარჩენილს');
      const entry = payment
        ? await tx.obligationPayment.create({
            data: {
              ...data,
              ...actorData(actor),
              obligationCycleId: cycleId,
              paymentDate: paymentDate!,
              reserveConsumed: Prisma.Decimal.min(
                data.amount,
                plan.reservedAmount,
              ),
            },
          })
        : await tx.obligationReserveEntry.create({
            data: { ...data, ...actorData(actor), obligationCycleId: cycleId },
          });
      await audit(
        tx,
        actor,
        payment ? 'OBLIGATION_PAYMENT_RECORDED' : 'OBLIGATION_RESERVE_RECORDED',
        'OBLIGATION_CYCLE',
        cycleId,
        {
          entryId: data.id,
          obligationId: cycle.obligationId,
          amount: data.amount.toFixed(2),
          businessDate: data.businessDate,
        },
      );
      return entry;
    });
  }
}
