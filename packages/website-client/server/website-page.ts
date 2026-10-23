import { gatewayRequest, type WebGateway } from "./vercel-gateway.js";

export const genericSaasHost = "vynic-restaurant-web.vercel.app";
export const isPreviewPath = (path: string) =>
  path === "/preview" || path.startsWith("/preview/");
export const isWebsitePage = (path: string) =>
  path === "/index.html" ||
  (!/^\/(?:api|customer|platform|media|assets)(?:\/|$)/.test(path) &&
    !/\.[^/]+$/.test(path));

type State = "address" | "missing" | "pending" | "unavailable" | "error";
const copy: Record<State, [string, string, string]> = {
  address: [
    "გახსენით რესტორნის მისამართი",
    "რესტორნის სანახავად გამოიყენეთ მისი პირადი ვებმისამართი. ეს Vynic-ის საერთო მისამართია.",
    "Use the restaurant’s own web address to visit its website.",
  ],
  missing: [
    "მითითებული რესტორანი ვერ მოიძებნა",
    "გადაამოწმეთ მისამართი. ამ მისამართზე ხელმისაწვდომი რესტორნის გვერდი არ არის.",
    "No restaurant website is available at this address. Please check the address.",
  ],
  pending: [
    "გვერდი ჯერ არ გამოქვეყნებულა",
    "რესტორნის გვერდი მზადდება. გთხოვთ, მოგვიანებით სცადოთ.",
    "This restaurant website has not been published yet. Please check back later.",
  ],
  unavailable: [
    "გვერდი ხელმისაწვდომი არ არის",
    "ამ მისამართზე რესტორნის გვერდი ამჟამად ხელმისაწვდომი არ არის.",
    "This restaurant website is currently unavailable.",
  ],
  error: [
    "სერვისი დროებით მიუწვდომელია",
    "გვერდი ვერ ჩაიტვირთა. გთხოვთ, ხელახლა სცადოთ.",
    "The service is temporarily unavailable. Please try again.",
  ],
};

/** Self-contained error document: works without JS or a second API request. No request data is interpolated. */
export function websitePage(
  state: State,
  status: number,
  head = false,
): Response {
  const [title, body, english] = copy[state];
  return new Response(
    head
      ? null
      : `<!doctype html><html lang="ka"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${title} | Vynic</title><style>
*{box-sizing:border-box}body{margin:0;background:#fbf8f3;color:#1b1815;font-family:"Noto Sans Georgian",Sylfaen,system-ui,sans-serif;line-height:1.7}main{min-height:100dvh;width:min(100%,760px);margin:auto;padding:clamp(24px,6vw,64px);display:flex;flex-direction:column;justify-content:center;align-items:flex-start}.brand{font:700 28px system-ui;color:#1b1815;text-decoration:none;margin-bottom:64px}h1{font-size:clamp(26px,4vw,40px);line-height:1.4;letter-spacing:-.02em;text-wrap:balance;margin:0 0 20px}p{margin:0 0 16px;color:#554c42;max-width:52ch}.english{font-size:15px;color:#665d54}nav{display:flex;flex-wrap:wrap;gap:12px;margin-top:24px}nav a{display:inline-flex;align-items:center;min-height:48px;padding:12px 20px;border:1px solid #7d5b2e;border-radius:4px;color:#5b4020;text-decoration:none}nav a.primary{background:#1b1815;color:#fbf8f3;border-color:#1b1815}a:focus-visible{outline:3px solid #7d5b2e;outline-offset:5px}nav a:hover{background:#eee5d8}nav a.primary:hover{background:#39312b}
</style></head><body><main><a class="brand" href="https://vynic.ge">Vynic</a><h1>${title}</h1><p>${body}</p><p class="english" lang="en">${english}</p><nav aria-label="შემდეგი ნაბიჯი">${state === "error" ? '<a class="primary" href="">ხელახლა ცდა · Retry</a>' : ""}<a ${state !== "error" ? 'class="primary"' : ""} href="https://vynic.ge">Vynic-ზე გადასვლა</a></nav></main></body></html>`,
    {
      status,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "private, no-store",
        "X-Robots-Tag": "noindex, nofollow",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy":
          "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        ...(status === 503 ? { "Retry-After": "30" } : {}),
      },
    },
  );
}

/** Page admission uses the same authenticated Host boundary as APIs; never a client tenant selector. */
export async function websitePageResponse(
  request: Request,
  secret: string | undefined,
  scope: Exclude<WebGateway, "platform">,
  siteKey?: string,
): Promise<Response | null> {
  const url = new URL(request.url);
  const head = request.method === "HEAD";
  if (request.method !== "GET" && !head)
    return websitePage("unavailable", 405, head);
  // Tokens live in fragments and only the authenticated preview API can read drafts.
  if (scope === "saas" && isPreviewPath(url.pathname)) return null;
  const upstream = new URL(
    scope === "saas" ? "/api/website/bootstrap" : "/api/website/venue",
    url,
  );
  const gateway = gatewayRequest(
    new Request(upstream, { headers: request.headers }),
    secret,
    scope,
  );
  if (gateway instanceof Response)
    return websitePage("error", gateway.status, head);
  if (scope === "saas" && url.hostname === genericSaasHost)
    return websitePage("address", 200, head);
  // Forward only server-derived authority. A public page probe must not inherit conditional
  // requests, cookies, authorization, caller headers or middleware controls.
  const headers = new Headers({ Accept: "application/json" });
  for (const key of ["host", "proto", "ip", "secret"])
    headers.set(
      `x-vynic-web-proxy-${key}`,
      gateway.headers.get(`x-vynic-web-proxy-${key}`)!,
    );
  try {
    const response = await fetch(gateway.url, {
      headers,
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(8000),
    });
    if (response.status === 404) {
      const body = (await response.json().catch(() => null)) as {
        code?: string;
      } | null;
      return websitePage(
        body?.code === "WEBSITE_NOT_PUBLISHED" ? "pending" : "missing",
        404,
        head,
      );
    }
    if (response.status === 401 || response.status === 403)
      return websitePage("unavailable", response.status, head);
    if (!response.ok)
      return websitePage("error", response.status === 429 ? 429 : 503, head);
    const body = (await response.json()) as {
      mode?: string;
      schemaVersion?: number;
      site?: { key?: string; status?: string };
    };
    if (scope === "saas") {
      if (body.mode === "CUSTOM") return websitePage("unavailable", 421, head);
      if (body.mode !== "SAAS" || body.schemaVersion !== 2)
        return websitePage("error", 502, head);
    } else {
      if (body.mode !== "CUSTOM" || body.site?.key !== siteKey)
        return websitePage("unavailable", 421, head);
      if (body.schemaVersion !== 1) return websitePage("error", 502, head);
      if (body.site?.status !== "ACTIVE")
        return websitePage("pending", 503, head);
    }
    return null;
  } catch {
    // An outage, timeout, redirect or invalid payload is never evidence of tenant absence.
    return websitePage("error", 503, head);
  }
}
