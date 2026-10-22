import type { Language } from "../i18n";
import type { SiteState } from "../api/types";

/**
 * Page metadata for the generic restaurant site.
 *
 * Indexability is decided here and nowhere else, and the safe answer is the
 * default: anything that is not a published public page — a draft preview, a
 * custom-product host, an unpublished or disabled site, a load failure — is
 * marked `noindex, nofollow`. A page becomes indexable only by proving it is
 * published, public content.
 *
 * The canonical URL is always the site's own published address on the current
 * origin. Previous slugs stay registered as aliases, so a visitor who arrives
 * on an old address is still pointed at one canonical page rather than having
 * the same content indexed twice.
 */
const OG_TYPE = "restaurant.restaurant";

function meta(document: Document, key: string, attribute: "name" | "property") {
  const existing = document.head.querySelector<HTMLMetaElement>(
    `meta[${attribute}="${key}"]`,
  );
  if (existing) return existing;
  const created = document.createElement("meta");
  created.setAttribute(attribute, key);
  document.head.appendChild(created);
  return created;
}
function set(
  document: Document,
  key: string,
  attribute: "name" | "property",
  value: string | null,
) {
  const element = meta(document, key, attribute);
  if (value === null) element.remove();
  else element.setAttribute("content", value);
}
function link(document: Document, rel: string, href: string | null) {
  const existing = document.head.querySelector<HTMLLinkElement>(
    `link[rel="${rel}"][data-vynic="1"]`,
  );
  if (!href) {
    existing?.remove();
    return;
  }
  const element = existing ?? document.createElement("link");
  element.rel = rel;
  element.dataset.vynic = "1";
  element.href = href;
  if (!existing) document.head.appendChild(element);
}

export interface HeadOptions {
  document: Document;
  state: SiteState;
  language: Language;
  origin: string;
  fallbackTitle: string;
}

export function applyDocumentHead({
  document,
  state,
  language,
  origin,
  fallbackTitle,
}: HeadOptions) {
  document.documentElement.lang = language;
  const published =
    state.kind === "site" && !state.site.preview && state.site.mode === "SAAS";

  if (state.kind !== "site") {
    document.title = fallbackTitle;
    set(document, "robots", "name", "noindex, nofollow");
    set(document, "description", "name", null);
    for (const key of [
      "og:title",
      "og:description",
      "og:type",
      "og:url",
      "og:image",
      "og:site_name",
    ])
      set(document, key, "property", null);
    link(document, "canonical", null);
    link(document, "icon", null);
    return;
  }

  const { profile, content } = state.site;
  const name = [profile.name, profile.branchName].filter(Boolean).join(" · ");
  const title = content.seoTitle || `${name} — ${content.heroTitle || name}`;
  const description = content.seoDescription || content.heroSubtitle || "";
  document.title = title;
  set(
    document,
    "robots",
    "name",
    published ? "index, follow" : "noindex, nofollow",
  );
  set(document, "description", "name", description || null);
  set(document, "og:title", "property", title);
  set(document, "og:site_name", "property", name);
  set(document, "og:type", "property", OG_TYPE);
  set(document, "og:description", "property", description || null);

  const canonical = published ? `${origin}/` : null;
  set(document, "og:url", "property", canonical);
  link(document, "canonical", canonical);

  const image = absolute(content.heroImageUrl || content.logoUrl, origin);
  set(document, "og:image", "property", published ? image : null);
  link(document, "icon", absolute(content.logoUrl, origin));

  // Address is public restaurant information the owner already publishes.
  set(
    document,
    "og:street_address",
    "property",
    published ? profile.address : null,
  );
  set(document, "og:phone_number", "property", published ? profile.phone : null);
}

/** Managed `/media/...` references resolve against this site's own origin. */
export function absolute(reference: string | null, origin: string) {
  if (!reference) return null;
  return reference.startsWith("/") ? `${origin}${reference}` : reference;
}
