import { Prisma } from '@prisma/client';
import { day, dueDate, money, months, reservePlan } from './finance-rules';
const d = (v: string) => new Prisma.Decimal(v);
describe('exact finance rules', () => {
  it('keeps cents exact and refuses float truth and excess precision', () => {
    expect(money('0.10').plus(money('0.20')).toFixed(2)).toBe('0.30');
    for (const value of [0.1, '1.001', 'NaN', 'Infinity', '-5', '0', '1e4'])
      expect(() => money(value)).toThrow();
  });
  it('clamps due days for short months and handles rollover and leap years', () => {
    expect(dueDate('2026-02', 31)).toBe('2026-02-28');
    expect(dueDate('2028-02', 31)).toBe('2028-02-29');
    expect(months('2026-12', '2027-02')).toEqual([
      '2026-12',
      '2027-01',
      '2027-02',
    ]);
    expect(() => day('2026-02-30')).toThrow();
  });
  it('includes today and due day: 2400 / 20 = 120, due/overdue uses one', () => {
    const plan = (today: string) =>
      reservePlan(d('3000'), d('600'), d('0'), d('0'), '2026-09-30', today);
    expect(plan('2026-09-11')).toMatchObject({
      daysRemainingUntilDue: 20,
      dailyRecommendedReserve: '120.00',
      remainingToCover: '2400.00',
    });
    expect(plan('2026-09-30').dailyRecommendedReserve).toBe('2400.00');
    expect(plan('2026-10-01')).toMatchObject({
      status: 'OVERDUE',
      daysRemainingUntilDue: 1,
    });
  });
  it('consumed reserves cannot cover a target twice, and rounds a daily recommendation upward to cents', () => {
    expect(
      reservePlan(
        d('3000'),
        d('600'),
        d('500'),
        d('500'),
        '2026-09-30',
        '2026-09-11',
      ),
    ).toMatchObject({
      reservedAmount: '100.00',
      paidAmount: '500.00',
      coveredAmount: '600.00',
      remainingToCover: '2400.00',
    });
    expect(
      reservePlan(d('1'), d('0'), d('0'), d('0'), '2026-09-03', '2026-09-01')
        .dailyRecommendedReserve,
    ).toBe('0.34');
  });
});
