import { next, rewrite } from "@vercel/functions";
import { gatewayRequest } from "../../packages/website-client/server/vercel-gateway.js";
import { canonicalPageResponse } from "../../packages/website-client/server/canonical-page.js";
import { isWebsitePage } from "../../packages/website-client/server/website-page.js";

export default function proxy(request: Request) {
  if (/^\/download\/?$/.test(new URL(request.url).pathname))
    return new Response(null, {
      status: ["GET", "HEAD"].includes(request.method) ? 308 : 404,
      headers: {
        ...(["GET", "HEAD"].includes(request.method)
          ? { Location: "https://www.vynic.ge/#" }
          : {}),
        "Cache-Control": "private, no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  const canonical = canonicalPageResponse(request, "platform", [
    process.env.VERCEL_URL,
    process.env.VERCEL_BRANCH_URL,
    process.env.VERCEL_PROJECT_PRODUCTION_URL,
  ]);
  if (canonical) return canonical;
  if (isWebsitePage(new URL(request.url).pathname)) return next();
  const gateway = gatewayRequest(
    request,
    process.env.VYNIC_WEB_PROXY_SECRET,
    "platform",
  );
  if (gateway instanceof Response) return gateway;
  return rewrite(gateway.url, {
    request: { headers: gateway.headers },
    headers: gateway.media
      ? undefined
      : {
          "Cache-Control": "private, no-store",
          "x-vercel-enable-rewrite-caching": "0",
        },
  });
}
