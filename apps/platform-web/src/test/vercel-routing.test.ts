import { describe, expect, it } from "vitest";
import config from "../../vercel.json";

const fallback = config.rewrites.find(
  (rewrite) => rewrite.destination === "/index.html",
);
if (!fallback) throw new Error("Vercel SPA fallback is missing");
const matchesFallback = (url: string) =>
  new RegExp(`^${fallback.source}$`).test(
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
