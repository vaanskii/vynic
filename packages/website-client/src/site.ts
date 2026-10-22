import type { CustomSiteBootstrap } from "./types";

/**
 * What a custom frontend should render for the bootstrap it received.
 *
 * `siteKey` is this frontend build's own identity (for example `vankisi-web`).
 * The backend has already decided the restaurant from the Host; comparing the
 * key the operator bound to that restaurant with the build's key only detects a
 * deployment mistake — this build attached to another customer's domain — and
 * refuses to dress that restaurant in the wrong design.
 */
export type SiteGate =
  | { kind: "ready"; bootstrap: CustomSiteBootstrap }
  | { kind: "setup"; bootstrap: CustomSiteBootstrap }
  | { kind: "misattached"; expected: string; bound: string | null };

export function gateSite(
  bootstrap: CustomSiteBootstrap,
  siteKey: string,
): SiteGate {
  // A SAAS Venue has no custom binding: this build does not belong there.
  const bound = bootstrap.site?.key ?? null;
  if (bound !== siteKey) return { kind: "misattached", expected: siteKey, bound };
  if (bootstrap.site?.status === "ACTIVE") return { kind: "ready", bootstrap };
  return { kind: "setup", bootstrap };
}

/** The public name of a menu item in a language, honoring the owner's override. */
export function itemName(
  item: { name: { ka: string; en: string }; displayName: string | null },
  language: "ka" | "en",
): string {
  return item.displayName?.trim() || item.name[language] || item.name.ka;
}

/** A price in the Venue's currency, e.g. `12.50 ₾`. */
export function formatPrice(amount: number, currency: string): string {
  const symbol = currency === "GEL" ? "₾" : currency;
  return `${amount.toFixed(2)} ${symbol}`;
}
