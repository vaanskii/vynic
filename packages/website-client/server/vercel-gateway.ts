import { isIP } from "node:net";

export type WebGateway = "platform" | "saas" | "custom";

/** Server-only: derive authority from the actual Vercel request, never XFH/XFF. */
export function gatewayRequest(
  request: Request,
  secret: string | undefined,
  scope: WebGateway,
): { url: URL; headers: Headers; media: boolean } | Response {
  const url = new URL(request.url);
  const media = /^\/media\/website-logos(?:\/|$)/.test(url.pathname);
  const api =
    scope === "platform"
      ? /^\/(?:platform|customer)(?:\/|$)/
      : scope === "saas"
        ? /^\/api\/website(?:\/|$)/
        : /^\/api(?:\/|$)/;
  if (!media && !api.test(url.pathname))
    return Response.json({ message: "Not found" }, { status: 404 });
  if (!secret || secret.length < 32)
    return Response.json(
      { message: "Web gateway unavailable" },
      { status: 503 },
    );

  const host = request.headers.get("host");
  const ip = request.headers.get("x-vercel-forwarded-for");
  if (
    url.protocol !== "https:" ||
    (host !== null && host.toLowerCase() !== url.host.toLowerCase()) ||
    !ip ||
    !isIP(ip)
  )
    return Response.json(
      { message: "Invalid gateway request" },
      { status: 400 },
    );

  const headers = new Headers(request.headers);
  for (const name of [...headers.keys()]) {
    if (
      name.startsWith("x-vynic-web-proxy-") ||
      name.startsWith("x-middleware-") ||
      [
        "host",
        "x-forwarded-host",
        "x-forwarded-proto",
        "x-forwarded-for",
        "x-real-ip",
      ].includes(name)
    )
      headers.delete(name);
  }
  headers.set("x-vynic-web-proxy-secret", secret);
  headers.set("x-vynic-web-proxy-host", url.hostname);
  headers.set("x-vynic-web-proxy-proto", "https");
  headers.set("x-vynic-web-proxy-ip", ip);
  // Keep the complete path/query; callers cannot choose the upstream authority.
  const upstream = new URL("https://api.vynic.ge");
  upstream.pathname = url.pathname;
  upstream.search = url.search;
  return { url: upstream, headers, media };
}
