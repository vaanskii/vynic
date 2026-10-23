import { describe, expect, it } from "vitest";
import config from "../../vercel.json";
import restaurant from "../../../restaurant-web/vercel.json";
import custom from "../../../vankisi-custom-web/vercel.json";

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
  it("runs server-only authority middleware for the API and media families", () => {
    expect(config.proxy.entrypoint).toBe("proxy.ts");
    const matches = (path: string) =>
      config.proxy.matcher.some((matcher) => {
        if (matcher.startsWith("/(("))
          return new RegExp(`^${matcher}$`).test(path);
        const prefix = matcher.replace("/:path*", "");
        return path === prefix || path.startsWith(prefix + "/");
      });
    expect(matches(api)).toBe(true);
    expect(matches("/media/website-logos/example.webp")).toBe(true);
    expect(matches(local)).toBe(true);
    expect(matches("/index.html")).toBe(true);
    expect(matches("/assets/probe.js")).toBe(false);
  });
  it("has no static rewrite that could attach credentials without server verification", () => {
    expect(routeFor(api)).toBeUndefined();
    expect(JSON.stringify(config)).not.toContain("VYNIC_WEB_PROXY_SECRET");
    expect(JSON.stringify(config)).not.toContain("https://api.vynic.ge");
  });
  it.each([
    "/",
    "/en",
    "/en/pos",
    "/en/pos/",
    "/ka/reservations",
    "/login",
    "/request-access",
    "/invite/accept",
    "/dashboard/website",
    "/venues/qa-venue/website",
  ])("serves the SPA for direct navigation to %s", (path) => {
    expect(routeFor(path)).toMatchObject({ dest: "/index.html" });
  });
  it.each([
    "/api",
    "/api/unknown",
    "/customer",
    "/customer/portal",
    "/platform",
    "/platform/auth/me",
    "/media/website-logos/missing",
    "/assets",
    "/assets/missing.js",
    "/assets/missing",
    "/favicon.svg",
    "/robots.txt",
    "/fonts/missing.woff2",
    "/missing.json",
  ])("never serves the SPA for API/static failure %s", (path) => {
    expect(routeFor(path)).not.toMatchObject({ dest: "/index.html" });
  });
  it("keeps static files before the SPA fallback", () => {
    const index = config.routes.findIndex(
      (route) => "handle" in route && route.handle === "filesystem",
    );
    const spa = config.routes.findIndex(
      (route) => "dest" in route && route.dest === "/index.html",
    );
    expect(index).toBeGreaterThanOrEqual(0);
    expect(spa).toBeGreaterThan(index);
    expect(routeFor(local)).toMatchObject({ dest: "/index.html" });
  });
});
