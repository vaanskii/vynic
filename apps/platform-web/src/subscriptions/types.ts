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
  trialEndsAt?: string | null;
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
