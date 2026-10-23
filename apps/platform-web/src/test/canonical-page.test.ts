import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalPageResponse } from "../../../../packages/website-client/server/canonical-page";
import platformProxy from "../../proxy";
import saasProxy from "../../../restaurant-web/proxy";
import customProxy from "../../../vankisi-custom-web/proxy";

const projects = [
  { scope: "platform", project: "vynic-platform-web", origin: "https://vynic.ge", proxy: platformProxy },
  { scope: "saas", project: "vynic-restaurant-web", origin: "https://vynic.ge", proxy: saasProxy },
  { scope: "custom", project: "vynic-vankisi-custom-web", origin: "https://vankisi.vynic.ge", proxy: customProxy },
] as const;
const request = (host: string, path = "/", method = "GET", headers = {}) =>
  new Request(`https://${host}${path}`, { method, headers: { host, "x-vercel-forwarded-for": "203.0.113.5", ...headers } });
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

describe.each(projects)("$scope owned-domain navigation", ({ scope, project, origin, proxy }) => {
  it.each(["", "-vaanskiis-projects", "-git-main-vaanskiis-projects"])("redirects exact alias %s with no upstream lookup", async (suffix) => {
    vi.stubGlobal("fetch", vi.fn());
    const result = await proxy(request(`${project}${suffix}.vercel.app`, "/"));
    expect(result.status).toBe(307);
    expect(result.headers.get("Location")).toBe(`${origin}/#`);
    expect(fetch).not.toHaveBeenCalled();
  });
  it.each(["/en/menu", "/login", "/dashboard/website", "/index.html", "//attacker.invalid/path"])("preserves only appropriate safe paths: %s", (path) => {
    const result = canonicalPageResponse(request(`${project}.vercel.app`, `${path}?token=private&next=https://attacker.invalid#token=private`), scope)!;
    expect(result.status).toBe(307);
    const destination = new URL(result.headers.get("Location")!);
    expect(destination.origin).toBe(origin);
    expect(destination.pathname).toBe(scope === "saas" || path === "/index.html" ? "/" : path);
    expect(destination.search).toBe("");
    expect(result.headers.get("Location")).toMatch(/#$/);
    expect(result.headers.get("Location")).not.toContain("private");
    expect(result.headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(result.headers.get("Cache-Control")).toBe("private, no-store");
  });
  it("recognizes exact server-supplied deployment hosts, not caller forwarding headers", async () => {
    const deployment = `${project}-build-test.vercel.app`;
    vi.stubEnv("VERCEL_URL", deployment);
    expect((await proxy(request(deployment))).headers.get("Location")).toBe(`${origin}/#`);
    expect(canonicalPageResponse(request("unrelated.vercel.app", "/", "GET", {
      "x-forwarded-host": `${project}.vercel.app`, "x-vynic-web-proxy-host": `${project}.vercel.app`,
    }), scope, [deployment])).toBeNull();
    expect(canonicalPageResponse(request(`${project}.vercel.app.attacker.invalid`), scope)).toBeNull();
    expect(canonicalPageResponse(request("owned.vynic.ge"), scope)).toBeNull();
  });
  it.each(["/api/website/bootstrap", "/api/website/preview/bootstrap", "/platform/auth/me", "/customer/portal", "/assets/app.js", "/media/website-logos/a.webp", "/vynic-site-manifest.json", "/favicon.svg"])("never canonicalizes API/assets: %s", (path) => {
    expect(canonicalPageResponse(request(`${project}.vercel.app`, path), scope)).toBeNull();
  });
  it("does not redirect writes and returns an empty HEAD redirect", async () => {
    expect(canonicalPageResponse(request(`${project}.vercel.app`, "/", "POST"), scope)).toBeNull();
    const result = await proxy(request(`${project}.vercel.app`, "/", "HEAD"));
    expect(result.status).toBe(307);
    expect(await result.text()).toBe("");
  });
  it("rejects mismatched actual Host rather than trusting forwarded metadata", () => {
    expect(canonicalPageResponse(request(`${project}.vercel.app`, "/", "GET", { host: "other.invalid" }), scope)?.status).toBe(400);
  });
});

describe("SaaS preview exception", () => {
  it.each(["/preview", "/preview/"])("keeps fragment and stored-token preview entry %s on the original origin", async (path) => {
    const result = await saasProxy(request("vynic-restaurant-web.vercel.app", `${path}#token=synthetic`));
    expect(result.headers.get("Location")).toBeNull();
    expect(result.headers.get("x-middleware-next")).toBe("1");
  });
  it.each(["/preview/nested", "/preview?token=synthetic", "/preview/?next=foreign"])("rejects malformed entry %s without redirect", async (path) => {
    const result = await saasProxy(request("vynic-restaurant-web.vercel.app", path));
    expect(result.status).toBe(400);
    expect(result.headers.get("Location")).toBeNull();
    expect(await result.text()).not.toContain("synthetic");
  });
  it("does not treat a similar prefix as preview", async () => {
    expect((await saasProxy(request("vynic-restaurant-web.vercel.app", "/preview-other?token=synthetic"))).headers.get("Location")).toBe("https://vynic.ge/#");
  });
});
