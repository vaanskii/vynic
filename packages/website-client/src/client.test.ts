import { describe, expect, it, vi } from "vitest";
import {
  createWebsiteClient,
  SiteUnavailableError,
  WebsiteApiError,
} from "./client";
import { formatPrice, gateSite, itemName } from "./site";
import type { CustomSiteBootstrap } from "./types";

function fakeFetch(
  routes: Record<string, { status?: number; body?: unknown }>,
) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fn = vi.fn(async (url: string, init: RequestInit = {}) => {
    calls.push({ url, init });
    const route = routes[`${init.method ?? "GET"} ${url}`] ?? { status: 404 };
    return new Response(JSON.stringify(route.body ?? {}), {
      status: route.status ?? 200,
      headers: { "Content-Type": "application/json" },
    });
  });
  return { fn: fn as unknown as typeof fetch, calls };
}

const bootstrap = (patch: Partial<CustomSiteBootstrap["site"]> = {}) =>
  ({
    schemaVersion: 1,
    mode: "CUSTOM",
    site: { key: "restaurant-x-web", status: "ACTIVE", ...patch },
    profile: {
      name: "Restaurant X",
      branchName: null,
      address: null,
      phone: null,
      timezone: "Asia/Tbilisi",
      currency: "GEL",
    },
    capabilities: {
      profile: true,
      menu: true,
      customerAccounts: true,
      onlinePayments: false,
      reservations: false,
    },
  }) satisfies CustomSiteBootstrap;

describe("createWebsiteClient", () => {
  it("calls same-origin paths only and never sends a Venue identity", async () => {
    const { fn, calls } = fakeFetch({
      "GET /api/website/custom/bootstrap": { body: bootstrap() },
      "GET /api/website/custom/menu": { body: { categories: [] } },
      "GET /api/tables/availability?date=2026-11-02": { body: [] },
    });
    const client = createWebsiteClient({ fetch: fn });
    await client.bootstrap();
    await client.menu();
    await client.availability("2026-11-02");
    for (const call of calls) {
      expect(call.url.startsWith("/api/")).toBe(true);
      expect(call.url).not.toMatch(/venue|domain|organization/i);
      expect(call.init.credentials).toBe("same-origin");
      expect([...new Headers(call.init.headers).keys()]).not.toContain(
        "x-venue-id",
      );
    }
  });

  it("reports a host without a custom website as unavailable", async () => {
    const missing = createWebsiteClient({ fetch: fakeFetch({}).fn });
    await expect(missing.bootstrap()).rejects.toBeInstanceOf(
      SiteUnavailableError,
    );
    const ended = createWebsiteClient({
      fetch: fakeFetch({
        "GET /api/website/custom/bootstrap": { status: 403 },
      }).fn,
    });
    await expect(ended.bootstrap()).rejects.toMatchObject({ status: 403 });
  });

  it("keeps a capability refusal distinct from a missing site", async () => {
    const client = createWebsiteClient({
      fetch: fakeFetch({
        "POST /api/bog/create-order": {
          status: 403,
          body: { message: "Online payments unavailable" },
        },
      }).fn,
    });
    const error = await client
      .bookAndPay({
        selectedTables: ["table1"],
        selectedDate: "2026-11-02",
        selectedTime: "19:00",
      })
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(WebsiteApiError);
    expect(error).toMatchObject({
      status: 403,
      message: "Online payments unavailable",
    });
  });

  it("fetches a CSRF token before signing in and sends it", async () => {
    const { fn, calls } = fakeFetch({
      "GET /api/auth/csrf": { body: { csrfToken: "t-1" } },
      "POST /api/auth/signin": { body: { message: "ok" } },
    });
    await createWebsiteClient({ fetch: fn }).signIn("a@b.ge", "secret");
    const signin = calls.find((c) => c.url === "/api/auth/signin")!;
    expect(new Headers(signin.init.headers).get("X-CSRF-Token")).toBe("t-1");
    expect(JSON.parse(String(signin.init.body))).toEqual({
      identifier: "a@b.ge",
      password: "secret",
    });
  });
});

describe("gateSite", () => {
  it("renders only when the build matches the Venue's bound frontend", () => {
    expect(gateSite(bootstrap(), "restaurant-x-web").kind).toBe("ready");
    expect(gateSite(bootstrap(), "vankisi-web")).toEqual({
      kind: "misattached",
      expected: "vankisi-web",
      bound: "restaurant-x-web",
    });
    expect(gateSite(bootstrap({ key: null }), "restaurant-x-web").kind).toBe(
      "misattached",
    );
    expect(
      gateSite(bootstrap({ status: "SETUP_PENDING" }), "restaurant-x-web")
        .kind,
    ).toBe("setup");
  });

  it("formats names and prices", () => {
    expect(
      itemName({ name: { ka: "ხინკალი", en: "Khinkali" }, displayName: null }, "en"),
    ).toBe("Khinkali");
    expect(
      itemName({ name: { ka: "ხინკალი", en: "" }, displayName: " Special " }, "en"),
    ).toBe("Special");
    expect(formatPrice(12.5, "GEL")).toBe("12.50 ₾");
  });
});
