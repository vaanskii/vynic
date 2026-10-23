import { afterEach, describe, expect, it } from "vitest";
import {
  gatewayRequest,
  type WebGateway,
} from "../../../../packages/website-client/server/vercel-gateway";
import platform from "../../proxy";
import restaurant from "../../../restaurant-web/proxy";
import custom from "../../../vankisi-custom-web/proxy";

const secret = "synthetic-private-gateway-key-for-regression-tests-only";
const host = "restaurant.example.invalid";
const visitor = "2001:db8::21";
const original = process.env.VYNIC_WEB_PROXY_SECRET;
afterEach(() => {
  if (original === undefined) delete process.env.VYNIC_WEB_PROXY_SECRET;
  else process.env.VYNIC_WEB_PROXY_SECRET = original;
});
const makeRequest = (
  path = "/api/probe?cursor=a%2Fb&limit=2",
  headers: Record<string, string> = {},
) =>
  new Request(`https://${host}${path}`, {
    method: "POST",
    body: '{"message":"ქართული"}',
    headers: {
      host,
      "x-vercel-forwarded-for": visitor,
      "Content-Type": "application/json",
      Authorization: "Bearer synthetic-user-token",
      Cookie: "csrf_token=synthetic-cookie",
      "X-CSRF-Token": "synthetic-cookie",
      "x-forwarded-host": "attacker.invalid",
      "x-forwarded-proto": "http",
      "x-forwarded-for": "not-an-ip, 203.0.113.99",
      "x-real-ip": "not-an-ip",
      "x-vynic-web-proxy-secret": "attacker-key",
      "x-vynic-web-proxy-host": "attacker.invalid",
      "x-vynic-web-proxy-proto": "http",
      "x-vynic-web-proxy-ip": "203.0.113.99",
      "x-middleware-subrequest": "attacker",
      ...headers,
    },
  });
const upstreamHeaders = (response: Response) => {
  const headers = new Headers();
  for (const key of response.headers
    .get("x-middleware-override-headers")
    ?.split(",") ?? [])
    headers.set(key, response.headers.get(`x-middleware-request-${key}`)!);
  return headers;
};

describe("server-only Vercel gateway authority", () => {
  it("replaces all caller authority from the actual URL and Vercel system IP", async () => {
    const request = makeRequest();
    const result = gatewayRequest(request, secret, "custom");
    if (result instanceof Response) throw new Error("Unexpected rejection");
    expect(result.url.href).toBe(
      "https://api.vynic.ge/api/probe?cursor=a%2Fb&limit=2",
    );
    expect(result.headers.get("x-vynic-web-proxy-host")).toBe(host);
    expect(result.headers.get("x-vynic-web-proxy-proto")).toBe("https");
    expect(result.headers.get("x-vynic-web-proxy-ip")).toBe(visitor);
    expect(result.headers.get("x-vynic-web-proxy-secret")).toBe(secret);
    for (const key of [
      "host",
      "x-forwarded-host",
      "x-forwarded-proto",
      "x-forwarded-for",
      "x-real-ip",
      "x-middleware-subrequest",
    ])
      expect(result.headers.has(key)).toBe(false);
    expect(result.headers.get("Authorization")).toBe(
      "Bearer synthetic-user-token",
    );
    expect(result.headers.get("Cookie")).toBe("csrf_token=synthetic-cookie");
    expect(result.headers.get("X-CSRF-Token")).toBe("synthetic-cookie");
    expect(request.bodyUsed).toBe(false);
    expect(await request.text()).toBe('{"message":"ქართული"}');
  });
  it.each([undefined, "short"])(
    "fails closed without a strong server secret: %s",
    (key) => {
      expect(gatewayRequest(makeRequest(), key, "custom")).toMatchObject({
        status: 503,
      });
    },
  );
  it.each(["", "not-an-ip", "203.0.113.1, 203.0.113.2"])(
    "rejects invalid platform IP metadata %s",
    (ip) => {
      expect(
        gatewayRequest(
          makeRequest(undefined, { "x-vercel-forwarded-for": ip }),
          secret,
          "custom",
        ),
      ).toMatchObject({ status: 400 });
    },
  );
  it("does not fall back to generic XFF when system IP is missing", () => {
    const request = makeRequest();
    request.headers.delete("x-vercel-forwarded-for");
    request.headers.set("x-forwarded-for", "203.0.113.1");
    expect(gatewayRequest(request, secret, "custom")).toMatchObject({
      status: 400,
    });
  });
  it("rejects a Host/URL discrepancy", () => {
    expect(
      gatewayRequest(
        makeRequest(undefined, { host: "attacker.invalid" }),
        secret,
        "custom",
      ),
    ).toMatchObject({ status: 400 });
  });
  it("requires HTTPS", () => {
    const request = new Request(`http://${host}/api/probe`, {
      headers: { "x-vercel-forwarded-for": visitor },
    });
    expect(gatewayRequest(request, secret, "custom")).toMatchObject({
      status: 400,
    });
  });
  it.each(["platform", "saas", "custom"] as WebGateway[])(
    "never forwards native/static routes through %s",
    (scope) => {
      for (const path of [
        "/mobile/probe",
        "/assets/index.js",
        "/healthz",
        "/apiary",
      ])
        expect(gatewayRequest(makeRequest(path), secret, scope)).toMatchObject({
          status: 404,
        });
    },
  );
});

for (const [name, handler, api] of [
  ["platform", platform, "/platform/auth/me"],
  ["saas", restaurant, "/api/website/bootstrap"],
  ["custom", custom, "/api/auth/csrf"],
] as const) {
  describe(`${name} real Vercel rewrite helper`, () => {
    it("sends private credentials only as upstream request metadata", () => {
      process.env.VYNIC_WEB_PROXY_SECRET = secret;
      const response = handler(makeRequest(api + "?cursor=a%2Fb"));
      expect(response.headers.get("x-middleware-rewrite")).toBe(
        `https://api.vynic.ge${api}?cursor=a%2Fb`,
      );
      const headers = upstreamHeaders(response);
      expect(headers.get("x-vynic-web-proxy-host")).toBe(host);
      expect(headers.get("x-vynic-web-proxy-ip")).toBe(visitor);
      expect(headers.get("x-vynic-web-proxy-secret")).toBe(secret);
      expect(response.headers.get("x-vynic-web-proxy-secret")).toBeNull();
      expect(response.headers.get("Cache-Control")).toBe("private, no-store");
      expect(response.headers.get("x-vercel-enable-rewrite-caching")).toBe("0");
      expect(response.body).toBeNull();
    });
    it("retains media handling and blocks credential-free middleware bypass", () => {
      process.env.VYNIC_WEB_PROXY_SECRET = secret;
      const response = handler(
        makeRequest("/media/website-logos/example.webp"),
      );
      expect(response.headers.get("x-middleware-rewrite")).toBe(
        "https://api.vynic.ge/media/website-logos/example.webp",
      );
      expect(response.headers.get("Cache-Control")).toBeNull();
      delete process.env.VYNIC_WEB_PROXY_SECRET;
      expect(handler(makeRequest(api)).status).toBe(503);
    });
  });
}
