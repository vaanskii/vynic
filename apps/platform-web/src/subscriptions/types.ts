export type BillingQuote = {
  id?: string;
  kind: string;
  planId: string;
  planName: string;
  priceMinor: number;
  currency: string;
  billingPeriod: string;
  amountMinor: number;
  subscriptionVersion?: number;
  effectiveAt?: string;
  expiresAt?: string;
};
export type SubscriptionDetail = {
  features?: string[];
  status: string;
  startedAt?: string | null;
  serverTime?: string;
  trialEndsAt?: string | null;
  trialEndedAt?: string | null;
  suspendedFrom?: string | null;
  suspendedAt?: string | null;
  currentPeriodStart?: string | null;
  currentPeriodEndsAt?: string | null;
  billingAnchorAt?: string | null;
  billingManaged?: boolean;
  paymentState?: string;
  cancelAtPeriodEnd?: boolean;
  pendingPlan?: { id: string; name: string } | null;
  pendingChangeAt?: string | null;
  pendingPriceMinor?: number | null;
  pendingCurrency?: string | null;
  pendingBillingPeriod?: string | null;
  assignment?: {
    planId: string;
    agreedPriceMinor: number | null;
    agreedCurrency: string | null;
    agreedBillingPeriod: string | null;
    plan: { name: string };
  } | null;
  operations?: BillingQuote[];
  history?: {
    id: string;
    action: string;
    createdAt: string;
    metadata?: Record<string, unknown>;
  }[];
};
export const money = (
  amount: number | null | undefined,
  currency?: string | null,
) => (amount == null ? "—" : `${(amount / 100).toFixed(2)} ${currency ?? ""}`);
export const day = (value?: string | null, locale = "en-GB") =>
  value ? new Date(value).toLocaleDateString(locale) : "—";

export const dateTime = (value?: string | null, locale = "en-GB") =>
  value
    ? new Date(value).toLocaleString(locale, {
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        timeZoneName: "short",
      })
    : "—";
export const remaining = (end?: string | null, now = Date.now()) => {
  if (!end) return "—";
  const minutes = Math.max(
    0,
    Math.floor((new Date(end).getTime() - now) / 60000),
  );
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
};
