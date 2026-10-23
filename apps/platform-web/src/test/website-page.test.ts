import { afterEach, describe, expect, it, vi } from "vitest";
import {
  isPreviewPath,
  isWebsitePage,
  websitePageResponse,
} from "../../../../packages/website-client/server/website-page";
const secret = "synthetic-page-gateway-key-with-no-live-access";
const request = (path = "/", host = "one.example.invalid", headers = {}) =>
  new Request(`https://${host}${path}`, {
    headers: { host, "x-vercel-forwarded-for": "203.0.113.5", ...headers },
  });
afterEach(() => vi.unstubAllGlobals());
const mock = (status: number, body: unknown) =>
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => Response.json(body, { status })),
  );
describe("public HTML page admission", () => {
  it("also admits direct index documents", () =>
    expect(isWebsitePage("/index.html")).toBe(true));
  it("shows shared-host guidance without looking up or disclosing a tenant", async () => {
    mock(500, {});
    const result = await websitePageResponse(
      request("/", "vynic-restaurant-web.vercel.app"),
      secret,
      "saas",
    );
    expect(result?.status).toBe(200);
    expect(await result?.text()).toContain("გახსენით რესტორნის მისამართი");
    expect(fetch).not.toHaveBeenCalled();
  });
  it.each(["/preview", "/preview/"])(
    "preserves authenticated fragment preview at %s",
    async (path) => {
      mock(500, {});
      expect(
        await websitePageResponse(request(path), secret, "saas"),
      ).toBeNull();
      expect(fetch).not.toHaveBeenCalled();
      expect(isPreviewPath("/preview-attacker")).toBe(false);
    },
  );
  it.each([
    "/api/auth/csrf",
    "/platform/auth/me",
    "/media/website-logos/logo.webp",
    "/assets/a.js",
    "/.well-known/vynic-site.json",
    "/favicon.svg",
  ])("keeps API/static routing outside page admission: %s", (path) =>
    expect(isWebsitePage(path)).toBe(false),
  );
  it("keeps the URL and returns a real private 404 with no restaurant data", async () => {
    mock(404, {
      code: "WEBSITE_NOT_FOUND",
      profile: { name: "Never disclose this" },
    });
    const result = await websitePageResponse(
      request("/en/menu?venueId=foreign"),
      secret,
      "saas",
    );
    expect(result?.status).toBe(404);
    expect(result?.headers.get("Location")).toBeNull();
    expect(result?.headers.get("Cache-Control")).toBe("private, no-store");
    expect(result?.headers.get("X-Robots-Tag")).toBe("noindex, nofollow");
    const html = await result!.text();
    expect(html).toContain("მითითებული რესტორანი ვერ მოიძებნა");
    expect(html).toContain('href="https://vynic.ge"');
    expect(html).not.toContain("Never disclose this");
    expect(html).not.toContain(secret);
  });
  it("distinguishes an unpublished site without disclosing its draft", async () => {
    mock(404, { code: "WEBSITE_NOT_PUBLISHED", draft: "private" });
    const result = await websitePageResponse(request(), secret, "saas");
    expect(result?.status).toBe(404);
    expect(await result!.text()).toContain("გვერდი ჯერ არ გამოქვეყნებულა");
  });
  it.each([500, 502, 503, 429, 401, 403])(
    "does not turn upstream %s into missing tenant",
    async (status) => {
      mock(status, {});
      const result = await websitePageResponse(request(), secret, "saas");
      expect(result!.status).not.toBe(404);
      if (status >= 500) expect(await result!.text()).toContain("ხელახლა ცდა");
    },
  );
  it("handles timeout, network failure, malformed JSON and retry recovery", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockRejectedValueOnce(new Error("timeout"))
        .mockResolvedValueOnce(new Response("broken json"))
        .mockResolvedValueOnce(
          Response.json({ mode: "SAAS", schemaVersion: 2 }),
        ),
    );
    expect((await websitePageResponse(request(), secret, "saas"))?.status).toBe(
      503,
    );
    expect((await websitePageResponse(request(), secret, "saas"))?.status).toBe(
      503,
    );
    expect(await websitePageResponse(request(), secret, "saas")).toBeNull();
  });
  it("uses authenticated actual host/IP only, with no query, cookie, auth or conditional reuse", async () => {
    mock(200, { mode: "SAAS", schemaVersion: 2 });
    await websitePageResponse(
      request("/?venueId=other", undefined, {
        "x-vynic-web-proxy-host": "other.invalid",
        "x-forwarded-host": "other.invalid",
        Authorization: "Bearer caller",
        Cookie: "session=caller",
        "If-None-Match": "caller",
        "x-middleware-subrequest": "caller",
      }),
      secret,
      "saas",
    );
    const [url, init] = vi.mocked(fetch).mock.calls[0];
    expect(String(url)).toBe("https://api.vynic.ge/api/website/bootstrap");
    const h = new Headers(init?.headers);
    expect(h.get("x-vynic-web-proxy-host")).toBe("one.example.invalid");
    expect(h.get("x-vynic-web-proxy-ip")).toBe("203.0.113.5");
    expect([...h.keys()].sort()).toEqual([
      "accept",
      "x-vynic-web-proxy-host",
      "x-vynic-web-proxy-ip",
      "x-vynic-web-proxy-proto",
      "x-vynic-web-proxy-secret",
    ]);
    expect(init).toMatchObject({ redirect: "error", cache: "no-store" });
  });
  it("fails closed on missing gateway configuration or inconsistent hostname", async () => {
    mock(200, {});
    expect(
      (await websitePageResponse(request(), undefined, "saas"))?.status,
    ).toBe(503);
    expect(
      (
        await websitePageResponse(
          request("/", undefined, { host: "other.invalid" }),
          secret,
          "saas",
        )
      )?.status,
    ).toBe(400);
    expect(fetch).not.toHaveBeenCalled();
  });
  it("enforces CUSTOM renderer identity and setup state before serving its static page", async () => {
    mock(200, {
      mode: "CUSTOM",
      schemaVersion: 1,
      site: { key: "other", status: "ACTIVE" },
    });
    expect(
      (await websitePageResponse(request(), secret, "custom", "vankisi-web"))
        ?.status,
    ).toBe(421);
    mock(200, {
      mode: "CUSTOM",
      schemaVersion: 1,
      site: { key: "vankisi-web", status: "READY" },
    });
    expect(
      (await websitePageResponse(request(), secret, "custom", "vankisi-web"))
        ?.status,
    ).toBe(503);
    mock(200, {
      mode: "CUSTOM",
      schemaVersion: 1,
      site: { key: "vankisi-web", status: "ACTIVE" },
    });
    expect(
      await websitePageResponse(request(), secret, "custom", "vankisi-web"),
    ).toBeNull();
    expect((await websitePageResponse(request(), secret, "saas"))?.status).toBe(
      421,
    );
  });
  it("uses HEAD semantics without an error body", async () => {
    mock(404, { code: "WEBSITE_NOT_FOUND" });
    const req = new Request(request(), { method: "HEAD" });
    const result = await websitePageResponse(req, secret, "saas");
    expect(result?.status).toBe(404);
    expect(await result!.text()).toBe("");
  });
});
