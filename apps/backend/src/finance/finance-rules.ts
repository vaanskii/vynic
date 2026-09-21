import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

export const zero = () => new Prisma.Decimal(0);
export const sum = (rows: { amount: Prisma.Decimal }[]) =>
  rows.reduce((total, row) => total.plus(row.amount), zero());
export function money(value: unknown, allowZero = false): Prisma.Decimal {
  if (typeof value !== 'string' || !/^\d{1,16}(\.\d{1,2})?$/.test(value))
    throw new BadRequestException(
      'თანხა ჩაწერეთ ათწილადის სახით (მაგ: 1500.00)',
    );
  const result = new Prisma.Decimal(value);
  if (allowZero ? result.lt(0) : result.lte(0))
    throw new BadRequestException('თანხა უნდა იყოს დადებითი');
  return result;
}
export function day(value: unknown): string {
  if (
    typeof value !== 'string' ||
    !/^20\d{2}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(Date.parse(`${value}T00:00:00Z`)) ||
    new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) !== value
  )
    throw new BadRequestException('თარიღის ფორმატი: YYYY-MM-DD (2000–2099)');
  return value;
}
export function month(value: unknown): string {
  day(`${value}-01`);
  return value as string;
}
export function months(from: string, through: string): string[] {
  const result: string[] = [];
  let cursor = month(from);
  month(through);
  while (cursor <= through) {
    result.push(cursor);
    const d = new Date(`${cursor}-01T00:00:00Z`);
    d.setUTCMonth(d.getUTCMonth() + 1);
    cursor = d.toISOString().slice(0, 7);
  }
  return result;
}
export function dueDate(period: string, dueDay: number): string {
  month(period);
  const date = new Date(`${period}-01T00:00:00Z`);
  date.setUTCMonth(date.getUTCMonth() + 1, 0);
  return `${period}-${String(Math.min(dueDay, date.getUTCDate())).padStart(2, '0')}`;
}
export function reservePlan(
  target: Prisma.Decimal,
  reserves: Prisma.Decimal,
  paid: Prisma.Decimal,
  consumed: Prisma.Decimal,
  due: string,
  today: string,
) {
  const reserved = reserves.minus(consumed);
  const remaining = Prisma.Decimal.max(0, target.minus(paid).minus(reserved));
  // Include today AND the due day. Due/overdue cycles use one day, never zero.
  const daysRemaining = Math.max(
    1,
    Math.round((Date.parse(day(due)) - Date.parse(day(today))) / 86400000) + 1,
  );
  return {
    reservedAmount: reserved.toFixed(2),
    paidAmount: paid.toFixed(2),
    coveredAmount: paid.plus(reserved).toFixed(2),
    remainingToCover: remaining.toFixed(2),
    remainingToPay: Prisma.Decimal.max(0, target.minus(paid)).toFixed(2),
    daysRemainingUntilDue: daysRemaining,
    dailyRecommendedReserve: remaining
      .div(daysRemaining)
      .toDecimalPlaces(2, Prisma.Decimal.ROUND_UP)
      .toFixed(2),
    status: paid.gte(target) ? 'PAID' : due < today ? 'OVERDUE' : 'OPEN',
  };
}
export function note(value: unknown): string | null {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || value.length > 1000)
    throw new BadRequestException('შენიშვნა: მაქსიმუმ 1000 სიმბოლო');
  return value.trim() || null;
}
export function entryId(value: unknown): string {
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  )
    throw new BadRequestException('id must be a UUID v4 retry key');
  return value;
}

export function inputObject(value: unknown): void {
  if (value === null || typeof value !== 'object' || Array.isArray(value))
    throw new BadRequestException('მოთხოვნა უნდა იყოს ობიექტი');
}
