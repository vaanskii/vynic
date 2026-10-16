import type { CustomSiteBootstrap } from "../../../../packages/website-client/src/types";
import { gateSite } from "../../../../packages/website-client/src/site";
import buildIdentity from "../config/siteIdentity.json";

export type WebsiteInfoState =
  | { kind: "loading" }
  | { kind: "ready"; site: CustomSiteBootstrap }
  | { kind: "unavailable" | "misattached" | "setup" };
const object = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const text = (value: unknown): value is string => typeof value === "string";
const nullableText = (value: unknown) => value === null || text(value);
const webUrl = (value: unknown) => {
  if (!text(value)) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch {
    return false;
  }
};
const mediaUrl = (value: unknown) =>
  text(value) &&
  ((/^\/media\/[a-z0-9][a-z0-9._/-]{0,180}$/.test(value) &&
    !value.includes("..")) ||
    webUrl(value));

/** Validate the existing public contract; the build key never selects a tenant. */
export function readWebsiteInfo(raw: unknown): WebsiteInfoState {
  if (!object(raw) || raw.schemaVersion !== 1) return { kind: "unavailable" };
  if (
    raw.mode !== "CUSTOM" ||
    !object(raw.site) ||
    raw.site.key !== buildIdentity.siteKey
  )
    return { kind: "misattached" };
  if (raw.site.status !== "ACTIVE") return { kind: "setup" };
  const profile = raw.profile,
    info = raw.info,
    caps = raw.capabilities;
  if (
    !object(profile) ||
    !object(info) ||
    !object(caps) ||
    !text(profile.name) ||
    !nullableText(profile.branchName) ||
    !nullableText(profile.address) ||
    !nullableText(profile.phone) ||
    !text(profile.timezone) ||
    !text(profile.currency) ||
    !text(info.contactEmail) ||
    !text(info.mapUrl) ||
    (info.mapUrl !== "" && !webUrl(info.mapUrl)) ||
    !Array.isArray(info.workingHours) ||
    info.workingHours.length > 7 ||
    !Array.isArray(info.gallery) ||
    info.gallery.length > 20 ||
    !Array.isArray(info.socials) ||
    info.socials.length > 8 ||
    ![
      "profile",
      "menu",
      "hours",
      "gallery",
      "customerAccounts",
      "onlinePayments",
      "reservations",
    ].every((key) => typeof caps[key] === "boolean")
  )
    return { kind: "unavailable" };
  if (
    info.workingHours.some(
      (row: unknown) =>
        !object(row) ||
        !Number.isInteger(row.day) ||
        Number(row.day) < 1 ||
        Number(row.day) > 7 ||
        ![row.opens, row.closes].every(
          (v) => text(v) && /^([01]\d|2[0-3]):[0-5]\d$/.test(v),
        ) ||
        row.opens === row.closes,
    ) ||
    new Set(
      info.workingHours.map((row: unknown) => (object(row) ? row.day : null)),
    ).size !== info.workingHours.length ||
    info.gallery.some(
      (row: unknown) => !object(row) || !mediaUrl(row.url) || !text(row.alt),
    ) ||
    info.socials.some(
      (row: unknown) => !object(row) || !text(row.label) || !webUrl(row.url),
    )
  )
    return { kind: "unavailable" };
  const site = raw as unknown as CustomSiteBootstrap;
  const gate = gateSite(site, buildIdentity.siteKey);
  return gate.kind === "ready"
    ? { kind: "ready", site }
    : { kind: "misattached" };
}

export function websitePhoneHref(phone: string | null): string | undefined {
  const digits = phone?.replace(/[\s().-]/g, "") ?? "";
  return /^\+?\d{4,20}$/.test(digits) ? `tel:${digits}` : undefined;
}
export function websiteMapHref(site: CustomSiteBootstrap): string | undefined {
  return (
    site.info.mapUrl ||
    (site.profile.address
      ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(site.profile.address)}`
      : undefined)
  );
}

/** Encode address data, preserving its @ separator without introducing headers. */
export function websiteEmailHref(email: string): string | undefined {
  return email
    ? `mailto:${encodeURIComponent(email).replaceAll("%40", "@")}`
    : undefined;
}
