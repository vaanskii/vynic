import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { sum, zero } from './finance-rules';
import { Prisma } from '@prisma/client';
/** Actual payments only. Reserves and salary configuration never enter outflows. */
export async function financialPayments(
  db: PrismaService,
  tenant: TenantContext,
  businessDate: string,
) {
  const where = { venueId: tenant.venueId, businessDate };
  const [payroll, obligations] = await Promise.all([
    db.payrollPayment.aggregate({ where, _sum: { amount: true } }),
    db.obligationPayment.aggregate({ where, _sum: { amount: true } }),
  ]);
  return {
    payrollPayments: (payroll._sum.amount ?? zero()).toFixed(2),
    obligationPayments: (obligations._sum.amount ?? zero()).toFixed(2),
  };
}
export async function payrollRemaining(
  db: PrismaService,
  tenant: TenantContext,
  through: string,
) {
  const periods = await db.payrollPeriod.findMany({
    where: { venueId: tenant.venueId, periodMonth: { lte: through } },
    include: { payments: true, accruals: true },
  });
  return periods
    .reduce(
      (total, p) =>
        total.plus(
          Prisma.Decimal.max(
            0,
            p.targetAmount.plus(sum(p.accruals)).minus(sum(p.payments)),
          ),
        ),
      zero(),
    )
    .toFixed(2);
}
