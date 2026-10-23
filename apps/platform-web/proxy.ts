import { rewrite } from "@vercel/functions";
import { gatewayRequest } from "../../packages/website-client/server/vercel-gateway";

export default function proxy(request: Request) {
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
