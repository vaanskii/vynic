import type { WebGateway } from "./vercel-gateway.js";
import { isPreviewAttempt, isWebsitePage } from "./website-page.js";

const projects: Record<WebGateway, { project: string; origin: string }> = {
  platform: { project: "vynic-platform-web", origin: "https://vynic.ge" },
  saas: { project: "vynic-restaurant-web", origin: "https://vynic.ge" },
  custom: {
    project: "vynic-vankisi-custom-web",
    origin: "https://vankisi.vynic.ge",
  },
};

/** Exact project aliases only. Deployment hosts come from Vercel's server env, never headers. */
export function canonicalPageResponse(
  request: Request,
  scope: WebGateway,
  deploymentHosts: readonly (string | undefined)[] = [],
): Response | null {
  const url = new URL(request.url);
  if (
    !["GET", "HEAD"].includes(request.method) ||
    !isWebsitePage(url.pathname)
  ) return null;
  // Until an owned preview origin is approved, preserve authenticated previews.
  // Malformed preview attempts are rejected by page admission, never redirected.
  if (scope === "saas" && isPreviewAttempt(url.pathname)) return null;
  const { project, origin } = projects[scope];
  const hosts = new Set([
    `${project}.vercel.app`,
    `${project}-vaanskiis-projects.vercel.app`,
    `${project}-git-main-vaanskiis-projects.vercel.app`,
    ...deploymentHosts.filter(
      (host): host is string => !!host && /^[a-z0-9-]+\.vercel\.app$/.test(host),
    ),
  ]);
  if (!hosts.has(url.hostname)) return null;
  const headers = {
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
  };
  const host = request.headers.get("host");
  if (url.protocol !== "https:" || (host && host.toLowerCase() !== url.host))
    return new Response(null, { status: 400, headers });
  const destination = new URL(origin);
  if (scope !== "saas" && url.pathname !== "/index.html")
    destination.pathname = url.pathname;
  // Never forward query credentials. An explicit empty fragment also prevents
  // browsers inheriting the source #token through an HTTP redirect.
  return new Response(null, {
    status: 307,
    headers: { ...headers, Location: `${destination.href}#` },
  });
}
