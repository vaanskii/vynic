import { BadRequestException } from '@nestjs/common';

/** Millisecond fraction, positive differences only, round half up in minor units. */
export function prorateUpgrade(
  currentMinor: number,
  nextMinor: number,
  start: Date,
  end: Date,
  at: Date,
): number {
  if (
    ![currentMinor, nextMinor].every(
      (n) => Number.isSafeInteger(n) && n >= 0,
    ) ||
    ![start, end, at].every((d) => Number.isFinite(d.getTime())) ||
    end <= start ||
    at < start ||
    at >= end
  )
    throw new BadRequestException(
      'A valid current billing period and prices are required',
    );
  const duration = BigInt(end.getTime() - start.getTime());
  const remaining = BigInt(end.getTime() - at.getTime());
  const numerator = BigInt(Math.max(0, nextMinor - currentMinor)) * remaining;
  return Number((numerator * 2n + duration) / (2n * duration));
}

/** UTC calendar periods, retaining the anchor day/time across short months/leap years. */
export function nextRenewal(anchor: Date, period: string, after: Date): Date {
  if (
    !['MONTH', 'YEAR'].includes(period) ||
    !Number.isFinite(anchor.getTime()) ||
    after < anchor
  )
    throw new BadRequestException('Monthly or yearly billing anchor required');
  const step = period === 'YEAR' ? 12 : 1;
  const months =
    (after.getUTCFullYear() - anchor.getUTCFullYear()) * 12 +
    after.getUTCMonth() -
    anchor.getUTCMonth();
  let count = Math.max(1, Math.floor(months / step));
  for (;;) {
    const month = anchor.getUTCMonth() + count * step;
    const date = new Date(
      Date.UTC(
        anchor.getUTCFullYear(),
        month,
        1,
        anchor.getUTCHours(),
        anchor.getUTCMinutes(),
        anchor.getUTCSeconds(),
        anchor.getUTCMilliseconds(),
      ),
    );
    const last = new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0),
    ).getUTCDate();
    date.setUTCDate(Math.min(anchor.getUTCDate(), last));
    if (date > after) return date;
    count++;
  }
}

type Terms = {
  priceMinor: number;
  currency: string;
  billingPeriod: string;
  features: string[];
};
export function classifyPlanChange(
  current: Terms,
  next: Terms,
): 'UPGRADE' | 'DOWNGRADE' | 'RENEWAL_CHANGE' | 'REVIEW' {
  const oldKeys = new Set(
    current.features.filter((k) => k !== 'NON_FISCAL_CLOSE'),
  );
  const nextKeys = new Set(
    next.features.filter((k) => k !== 'NON_FISCAL_CLOSE'),
  );
  const adds = [...nextKeys].some((k) => !oldKeys.has(k));
  const removes = [...oldKeys].some((k) => !nextKeys.has(k));
  // Mixed swaps and a billing/currency change that adds features need explicit operator review.
  if (
    (adds && removes) ||
    (adds &&
      (current.currency !== next.currency ||
        current.billingPeriod !== next.billingPeriod))
  )
    return 'REVIEW';
  if (
    current.currency !== next.currency ||
    current.billingPeriod !== next.billingPeriod
  )
    return 'RENEWAL_CHANGE';
  if (adds) return 'UPGRADE';
  if (removes)
    return next.priceMinor <= current.priceMinor ? 'DOWNGRADE' : 'REVIEW';
  return next.priceMinor > current.priceMinor ? 'UPGRADE' : 'DOWNGRADE';
}
