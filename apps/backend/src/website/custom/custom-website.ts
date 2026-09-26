import { BadRequestException } from '@nestjs/common';
import { CustomWebsiteStatus } from '@prisma/client';

/**
 * Rules for CUSTOM websites that do not need a database.
 *
 * A CUSTOM website is a bespoke frontend over the shared Vynic backend. The
 * backend already knows which Venue a request is for (Host -> VenueDomain ->
 * Venue); what it additionally records here is which frontend implementation is
 * meant to serve that Venue and how far operator setup has got. Capabilities
 * are shared with SAAS (`website/tenancy/website-capabilities.ts`).
 */

/**
 * A custom frontend identity such as `vankisi-web` or `restaurant-x-web`.
 *
 * Lowercase letters, digits and inner hyphens, 2–64 characters: the same shape
 * as an app directory name, so the key and `apps/<key>` can match.
 */
const SITE_KEY_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/;

/** `null` clears the key; anything else must be a valid key. */
export function readSiteKey(value: unknown): string | null {
  if (value === null || value === '') return null;
  if (typeof value !== 'string' || !SITE_KEY_PATTERN.test(value.trim()))
    throw new BadRequestException(
      'siteKey must be 2-64 lowercase letters, digits or hyphens',
    );
  return value.trim();
}

export const CUSTOM_WEBSITE_STATUSES = [
  CustomWebsiteStatus.SETUP_PENDING,
  CustomWebsiteStatus.READY,
  CustomWebsiteStatus.ACTIVE,
  CustomWebsiteStatus.ERROR,
] as const;

/** A CUSTOM Venue without a binding row has not been configured at all. */
export type CustomWebsiteState = CustomWebsiteStatus | 'NOT_CONFIGURED';

/** Online-payment setup as an operator needs to see it. */
export type CustomPaymentStatus =
  | 'NOT_INCLUDED'
  | 'NOT_CONFIGURED'
  | 'DISABLED'
  | 'ENABLED';

export function paymentStatus(
  features: readonly string[],
  integration: { enabled: boolean } | null,
): CustomPaymentStatus {
  if (!features.includes('ONLINE_PAYMENTS')) return 'NOT_INCLUDED';
  if (!integration) return 'NOT_CONFIGURED';
  return integration.enabled ? 'ENABLED' : 'DISABLED';
}

/** What must be true before an operator may mark a CUSTOM site READY or ACTIVE. */
export function customReadiness(facts: {
  entitled: boolean;
  mode: string;
  siteKey: string | null;
  activeDomains: number;
}) {
  const checks = {
    entitled: facts.entitled,
    customMode: facts.mode === 'CUSTOM',
    siteKey: !!facts.siteKey,
    activeDomain: facts.activeDomains > 0,
  };
  return { checks, complete: Object.values(checks).every(Boolean) };
}

/** Statuses that claim a working site and therefore require readiness. */
export function requiresReadiness(status: CustomWebsiteStatus) {
  return (
    status === CustomWebsiteStatus.READY ||
    status === CustomWebsiteStatus.ACTIVE
  );
}
