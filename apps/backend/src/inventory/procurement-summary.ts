import { SupplierPayments } from './supplier-payments';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { settingIdentity } from '../tenancy/tenant-identity';
import type { TenantContext } from '../tenancy/tenant-context';

/** Calendar labels use the Venue's configured timezone.
 * Business-date totals are independent of invoice and posting timestamps. */
export async function procurementSummary(
  prisma: PrismaService,
  tenant: TenantContext,
  now = new Date(),
) {
  const venue = await prisma.venue.findUniqueOrThrow({
    where: { id: tenant.venueId },
    select: { timezone: true },
  });
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: venue.timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  const setting = await prisma.setting.findUnique({
    where: settingIdentity(tenant, 'currentBusinessDate'),
  });
  const businessDate = setting?.value ?? today;
  const month = today.slice(0, 7);
  const sum = async (from: string, to: string) => {
    const result = await prisma.receiving.aggregate({
      where: {
        venueId: tenant.venueId,
        status: 'POSTED',
        businessDate: { gte: from, lte: to },
      },
      _sum: { documentTotal: true },
      _count: true,
    });
    return {
      total: new Prisma.Decimal(result._sum.documentTotal ?? 0).toFixed(2),
      count: result._count,
    };
  };
  const [calendarDay, businessDay, calendarMonth] = await Promise.all([
    sum(today, today),
    sum(businessDate, businessDate),
    sum(`${month}-01`, `${month}-31`),
  ]);
  const payments = async (
    field: 'paymentDate' | 'businessDate',
    from: string,
    to: string,
  ) => {
    const result = await prisma.supplierPayment.aggregate({
      where: { venueId: tenant.venueId, [field]: { gte: from, lte: to } },
      _sum: { amount: true },
    });
    return { total: new Prisma.Decimal(result._sum.amount ?? 0).toFixed(2) };
  };
  const [paidToday, paidBusinessDay, paidMonth, debt] = await Promise.all([
    payments('paymentDate', today, today),
    payments('businessDate', businessDate, businessDate),
    payments('paymentDate', `${month}-01`, `${month}-31`),
    new SupplierPayments(prisma).list(tenant),
  ]);
  return {
    supplierPayments: {
      calendarDay: paidToday,
      businessDay: paidBusinessDay,
      calendarMonth: paidMonth,
    },
    outstanding: debt.outstanding,
    unverified: debt.unverified,
    newUnpaidBalance: debt.receivings
      .filter((r) => r.businessDate === businessDate && r.paymentHistoryKnown)
      .reduce((sum, r) => sum.plus(r.remaining), new Prisma.Decimal(0))
      .toFixed(2),
    today,
    businessDate,
    month,
    calendarDay,
    businessDay,
    calendarMonth,
  };
}
