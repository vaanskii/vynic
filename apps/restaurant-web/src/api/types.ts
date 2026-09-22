/**
 * The published public model, exactly as `GET /api/website/bootstrap` sends it.
 *
 * This app holds no Venue identity of its own: everything below arrives already
 * resolved from the request host, and nothing here may be supplied by the page,
 * a query string or the visitor.
 */
export const SUPPORTED_SCHEMA_VERSION = 2;

export interface WebsiteProfile {
  name: string;
  branchName: string | null;
  address: string | null;
  phone: string | null;
  timezone: string;
  currency: string;
}
export interface WebsiteMediaRef {
  url: string;
  alt: string;
}
export interface WebsiteHours {
  day: number;
  opens: string;
  closes: string;
}
export interface WebsiteContent {
  slug: string;
  themeKey: string;
  logoUrl: string;
  heroTitle: string;
  heroSubtitle: string;
  heroImageUrl: string;
  about: string;
  aboutImageUrl: string;
  showMenu: boolean;
  menuHeading: string;
  menuIntro: string;
  seoTitle: string;
  seoDescription: string;
  contactEmail: string;
  mapUrl: string;
  showMap?: boolean;
  footerNote: string;
  workingHours: WebsiteHours[];
  socials: { label: string; url: string }[];
  gallery: WebsiteMediaRef[];
}
export interface WebsiteSite {
  schemaVersion: number;
  mode: "SAAS";
  preview: boolean;
  revision: number | null;
  publishedAt: string | null;
  profile: WebsiteProfile;
  content: WebsiteContent;
}
export interface WebsiteCustomMarker {
  schemaVersion: number;
  mode: "CUSTOM";
}
export type WebsiteBootstrap = WebsiteSite | WebsiteCustomMarker;

export interface MenuItem {
  id: string;
  name: { ka: string; en: string };
  displayName: string | null;
  description: string | null;
  imageUrl: string | null;
  price: number;
  variants: { id: string; size: number; price: number }[];
}
export interface MenuGroup {
  id: string;
  slug: string;
  name: { ka: string; en: string };
  items: MenuItem[];
}
export interface MenuCategory extends MenuGroup {
  subcategories: MenuGroup[];
}
export interface WebsiteMenu {
  schemaVersion: number;
  currency: string;
  enabled: boolean;
  categories: MenuCategory[];
}

/**
 * Why a site is not being rendered.
 *
 * `custom` and `unavailable` are different answers and are kept apart: a Venue
 * on the custom product is not a broken generic site, and neither may be shown
 * as if it were published content.
 */
export type SiteState =
  | { kind: "loading" }
  | { kind: "site"; site: WebsiteSite; menu: WebsiteMenu | null }
  | { kind: "custom" }
  | { kind: "unavailable" }
  | { kind: "unsupported" }
  | { kind: "error" };
