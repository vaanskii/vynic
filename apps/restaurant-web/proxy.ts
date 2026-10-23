import { next, rewrite } from "@vercel/functions";
import { gatewayRequest } from "../../packages/website-client/server/vercel-gateway.js";
import { canonicalPageResponse } from "../../packages/website-client/server/canonical-page.js";

import {
  isWebsitePage,
  websitePageResponse,
} from "../../packages/website-client/server/website-page.js";

export default function proxy(request: Request) {
  const canonical = canonicalPageResponse(request, "saas", [
    process.env.VERCEL_URL,
    process.env.VERCEL_BRANCH_URL,
    process.env.VERCEL_PROJECT_PRODUCTION_URL,
  ]);
  if (canonical) return canonical;
  if (isWebsitePage(new URL(request.url).pathname))
    return websitePageResponse(
      request,
      process.env.VYNIC_WEB_PROXY_SECRET,
      "saas",
    ).then(
      (response) =>
        response ?? next({ headers: { "Cache-Control": "private, no-store" } }),
    );
  const gateway = gatewayRequest(
    request,
    process.env.VYNIC_WEB_PROXY_SECRET,
    "saas",
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
