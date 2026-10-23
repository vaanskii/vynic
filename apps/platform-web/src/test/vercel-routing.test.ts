import { describe, expect, it } from "vitest";
import config from "../../vercel.json";
import restaurant from "../../../restaurant-web/vercel.json";
import custom from "../../../vankisi-custom-web/vercel.json";

const fallback = config.routes.find(
  (route) => "dest" in route && route.dest === "/index.html",
);
if (!fallback || !("src" in fallback))
  throw new Error("Vercel SPA fallback is missing");
const matchesFallback = (url: string) =>
  new RegExp(`^${fallback.src}$`).test(
    new URL(url, "https://preview.test.invalid").pathname,
  );

describe("Vercel SPA fallback", () => {
  it.each([
    "/",
    "/en",
    "/en/pos",
    "/en/pos/?from=refresh",
    "/ka/reservations",
    "/login",
    "/request-access",
    "/invite/accept",
    "/dashboard/website",
    "/venues/qa-venue/website",
  ])("serves the app for direct navigation to %s", (url) => {
    expect(matchesFallback(url)).toBe(true);
  });

  it.each([
    "/api",
    "/api/health",
    "/customer",
    "/customer/session",
    "/platform",
    "/platform/auth/me",
    "/media/website-logos/missing",
    "/assets",
    "/assets/index.js",
    "/assets/missing",
    "/favicon.svg",
    "/robots.txt",
    "/fonts/missing.woff2",
    "/missing.json",
  ])("keeps API and asset requests outside the fallback: %s", (url) => {
    expect(matchesFallback(url)).toBe(false);
  });
});

const projects = [
  {
    name: "platform",
    config,
    api: "/platform/auth/me",
    local: "/dashboard/website",
  },
  {
    name: "restaurant",
    config: restaurant,
    api: "/api/website/preview/bootstrap",
    local: "/en/menu",
  },
  {
    name: "custom",
    config: custom,
    api: "/api/auth/csrf",
    local: "/en/reservations",
  },
];

describe.each(projects)("$name Vercel transport", ({ config, api, local }) => {
  const routeFor = (path: string) =>
    config.routes.find(
      (route) => "src" in route && new RegExp(`^${route.src}$`).test(path),
    );

  it.each([api, "/media/website-logos/example.webp"])(
    "preserves the complete upstream path %s",
    (path) => {
      const route = routeFor(path);
      if (!route || !("src" in route) || !("dest" in route))
        throw new Error("Missing proxy");
      expect(path.replace(new RegExp(`^${route.src}$`), route.dest!)).toBe(
        `https://api.vynic.ge${path}`,
      );
    },
  );

  it("replaces caller credentials with a server-only environment reference", () => {
    const route = routeFor(api);
    if (!route || !("transforms" in route))
      throw new Error("Missing proxy transforms");
    expect(route.transforms).toEqual([
      {
        type: "request.headers",
        op: "delete",
        target: { key: "x-vynic-web-proxy-secret" },
      },
      {
        type: "request.headers",
        op: "set",
        target: { key: "x-vynic-web-proxy-secret" },
        args: "$VYNIC_WEB_PROXY_SECRET",
        env: ["VYNIC_WEB_PROXY_SECRET"],
      },
    ]);
    expect(
      route.transforms.some(
        (transform) => transform.target.key === "authorization",
      ),
    ).toBe(false);
  });

  it("does not cache API responses or restrict body-carrying methods", () => {
    const route = routeFor(api);
    expect(route).toMatchObject({
      headers: {
        "Cache-Control": "private, no-store",
        "x-vercel-enable-rewrite-caching": "0",
      },
    });
    expect(route).not.toHaveProperty("methods");
  });

  it.each([
    "/assets/missing.js",
    "/assets/missing",
    "/missing.json",
    "/api/unknown",
    "/customer/unknown",
    "/platform/unknown",
  ])("never serves the SPA for API/static failure %s", (path) => {
    expect(routeFor(path)).not.toMatchObject({ dest: "/index.html" });
  });

  it("keeps the filesystem before the SPA fallback", () => {
    const index = config.routes.findIndex(
      (route) => "handle" in route && route.handle === "filesystem",
    );
    const spa = config.routes.findIndex(
      (route) => "dest" in route && route.dest === "/index.html",
    );
    expect(index).toBeGreaterThan(0);
    expect(spa).toBeGreaterThan(index);
    expect(routeFor(local)).toMatchObject({ dest: "/index.html" });
  });
});
