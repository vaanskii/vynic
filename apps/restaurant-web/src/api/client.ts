import {
  SUPPORTED_SCHEMA_VERSION,
  type SiteState,
  type WebsiteBootstrap,
  type WebsiteMenu,
} from "./types";

/**
 * Same-origin requests only.
 *
 * The backend is reached through a host-preserving proxy on this app's own
 * origin, so the browser's Host — the restaurant the visitor actually typed —
 * is what resolves the Venue. An absolute API base would replace that host with
 * the backend's own and serve every restaurant the same site.
 */
const PREVIEW_TOKEN_KEY = "vynic-website-preview-token";

export class WebsiteUnavailable extends Error {}

async function get<T>(path: string, token?: string): Promise<T> {
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
    credentials: "omit",
  });
  if (response.status === 404 || response.status === 401)
    throw new WebsiteUnavailable(String(response.status));
  if (!response.ok) throw new Error(`Website request failed: ${response.status}`);
  return (await response.json()) as T;
}

/**
 * The preview token, taken from the URL fragment and then removed from it.
 *
 * A fragment is never sent to a server, so the owner's preview authority does
 * not travel through proxy or access logs. It is moved into session storage so
 * that a reload of the preview keeps working without the token staying visible
 * in the address bar.
 */
export function readPreviewToken(location: Location, storage: Storage) {
  const fragment = new URLSearchParams(location.hash.replace(/^#/, ""));
  const fromFragment = fragment.get("token");
  if (fromFragment) {
    try {
      storage.setItem(PREVIEW_TOKEN_KEY, fromFragment);
    } catch {
      // Private browsing can refuse storage; the token still works this once.
    }
    history.replaceState(null, "", location.pathname + location.search);
    return fromFragment;
  }
  try {
    return storage.getItem(PREVIEW_TOKEN_KEY);
  } catch {
    return null;
  }
}

export function clearPreviewToken(storage: Storage) {
  try {
    storage.removeItem(PREVIEW_TOKEN_KEY);
  } catch {
    // Nothing to clear when storage is unavailable.
  }
}

/**
 * Load the whole page model: the site, and its menu when it publishes one.
 *
 * A failing menu never takes the site down with it — a restaurant page without
 * its menu section is still a usable page, while a blank screen is not.
 */
export async function loadSite(
  preview: boolean,
  token: string | null,
): Promise<SiteState> {
  const base = preview ? "/api/website/preview" : "/api/website";
  if (preview && !token) return { kind: "unavailable" };
  let bootstrap: WebsiteBootstrap;
  try {
    bootstrap = await get<WebsiteBootstrap>(
      `${base}/bootstrap`,
      token ?? undefined,
    );
  } catch (error) {
    return {
      kind: error instanceof WebsiteUnavailable ? "unavailable" : "error",
    };
  }
  if (bootstrap.mode === "CUSTOM") return { kind: "custom" };
  if (bootstrap.schemaVersion !== SUPPORTED_SCHEMA_VERSION)
    return { kind: "unsupported" };
  let menu: WebsiteMenu | null = null;
  if (bootstrap.content.showMenu)
    try {
      menu = await get<WebsiteMenu>(`${base}/menu`, token ?? undefined);
    } catch {
      menu = null;
    }
  return { kind: "site", site: bootstrap, menu };
}
