import { Prisma } from '@prisma/client';

export const WEBSITE_PAYMENT_WINDOW_MS = 10 * 60 * 1000;
export const WEBSITE_PAYMENT_TTL_MINUTES = 10;

export interface BogPaymentFacts {
  orderId: string | null;
  reservationId: string | null;
  status: string;
  capture: string | null;
  currency: string | null;
  requestedMinor: string | null;
  remainingMinor: string | null;
  refundedMinor: string | null;
  createdAt: string | null;
  expiresAt: string | null;
}
export interface WebsitePaymentEvidence {
  source: 'CALLBACK' | 'POLL' | 'RECONCILE';
  observedAt: Date;
  receipt: unknown;
  /** Set only after verification of the exact signed callback bytes. */
  signedCallback?: { fingerprint: string; sentAt: unknown; receipt: unknown };
}
const object = (v: unknown): Record<string, unknown> =>
  v !== null && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
const text = (v: unknown): string | null =>
  typeof v === 'string' && v.length > 0 && v.length <= 200 ? v : null;
export function providerDate(v: unknown): string | null {
  if (
    typeof v !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(v)
  )
    return null;
  const date = new Date(v);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}
/** Exact cents, never round a provider's settled amount into a valid payment. */
export function providerMinor(v: unknown): string | null {
  if (
    (typeof v !== 'string' && typeof v !== 'number') ||
    String(v).length > 32 ||
    !/^\d+(?:\.\d+)?$/.test(String(v))
  )
    return null;
  const minor = new Prisma.Decimal(String(v)).mul(100);
  return minor.isInteger() &&
    minor.greaterThanOrEqualTo(0) &&
    minor.lessThanOrEqualTo(Number.MAX_SAFE_INTEGER)
    ? minor.toFixed(0)
    : null;
}
export function bogPaymentFacts(raw: unknown): BogPaymentFacts {
  const row = object(raw),
    units = object(row.purchase_units);
  return {
    orderId: text(row.order_id),
    reservationId: text(row.external_order_id),
    status: (text(object(row.order_status).key) ?? 'unknown').toLowerCase(),
    capture: text(row.capture),
    currency: text(units.currency_code),
    requestedMinor: providerMinor(units.request_amount),
    remainingMinor: providerMinor(units.transfer_amount),
    refundedMinor: providerMinor(units.refund_amount),
    createdAt: providerDate(row.zoned_create_date),
    expiresAt: providerDate(row.zoned_expire_date),
  };
}
