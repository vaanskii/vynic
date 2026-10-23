import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "../App";
import { siteA, menuA } from "./fixtures";

/**
 * Owner preview renders the real frontend against the draft.
 *
 * The properties that matter are that the draft never reaches a public route,
 * that the token leaves the address bar, and that a preview is never
 * indexable — not merely that something appears on screen.
 */
const requests: { url: string; auth: string | null }[] = [];
const draft = {
  ...siteA,
  preview: true,
  revision: 7,
  publishedAt: null,
  content: { ...siteA.content, heroTitle: "მონახაზი" },
};

function mockFetch(authorized = true) {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const auth = new Headers(init?.headers).get("Authorization");
    requests.push({ url, auth });
    const ok = authorized && auth === "Bearer preview-token";
    if (!ok) return { ok: false, status: 401, json: async () => ({}) } as Response;
    const body =
      url === "/api/website/preview/bootstrap"
        ? draft
        : url === "/api/website/preview/menu"
          ? menuA
          : null;
    if (!body) return { ok: false, status: 404, json: async () => ({}) } as Response;
    return { ok: true, status: 200, json: async () => body } as Response;
  });
}

beforeEach(() => {
  requests.length = 0;
  localStorage.clear();
  sessionStorage.clear();
});
afterEach(() => {
  vi.unstubAllGlobals();
  window.history.replaceState(null, "", "/");
});

describe("Draft preview", () => {
  it.each(["#token=", "#unknown=private", "#token=preview-token&token=other", "#token=preview-token&next=other"])(
    "clears malformed fragments without using a previous preview: %s",
    async (hash) => {
      vi.stubGlobal("fetch", mockFetch());
      sessionStorage.setItem("vynic-website-preview-token", "preview-token");
      window.history.replaceState(null, "", `/preview${hash}`);
      render(<App />);
      await screen.findByRole("heading", { name: "გვერდი ხელმისაწვდომი არ არის" });
      expect(requests).toHaveLength(0);
      expect(window.location.hash).toBe("");
      expect(sessionStorage.getItem("vynic-website-preview-token")).toBeNull();
    },
  );
  it("reloads a valid stored preview on the trailing-slash entry", async () => {
    vi.stubGlobal("fetch", mockFetch());
    sessionStorage.setItem("vynic-website-preview-token", "preview-token");
    window.history.replaceState(null, "", "/preview/");
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "მონახაზი" });
    expect(requests.every((r) => r.auth === "Bearer preview-token")).toBe(true);
  });
  it("renders the draft through preview routes and drops the token from the URL", async () => {
    vi.stubGlobal("fetch", mockFetch());
    window.history.replaceState(null, "", "/preview#token=preview-token");
    render(<App />);

    await screen.findByRole("heading", { level: 1, name: "მონახაზი" });
    expect(screen.getByText(/მონახაზის წინასწარი ნახვა/)).toBeInTheDocument();

    // Only preview routes are called, and each one carries the preview token.
    expect(requests.map((r) => r.url)).toEqual([
      "/api/website/preview/bootstrap",
      "/api/website/preview/menu",
    ]);
    expect(requests.every((r) => r.auth === "Bearer preview-token")).toBe(true);

    // The token is out of the address bar but still usable on a reload.
    expect(window.location.hash).toBe("");
    expect(window.location.pathname).toBe("/preview");
    expect(sessionStorage.getItem("vynic-website-preview-token")).toBe(
      "preview-token",
    );
  });

  it.each(["/preview/nested", "/preview?token=preview-token", "/preview/?next=other"]) (
    "rejects malformed entry %s even with a stored valid token",
    async (path) => {
      vi.stubGlobal("fetch", mockFetch());
      sessionStorage.setItem("vynic-website-preview-token", "preview-token");
      window.history.replaceState(null, "", path);
      render(<App />);
      await screen.findByRole("heading", { name: "გვერდი ხელმისაწვდომი არ არის" });
      expect(requests).toHaveLength(0);
    },
  );

  it("is never indexable and publishes no canonical address", async () => {
    vi.stubGlobal("fetch", mockFetch());
    window.history.replaceState(null, "", "/preview#token=preview-token");
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "მონახაზი" });
    await waitFor(() =>
      expect(
        document.querySelector('meta[name="robots"]')?.getAttribute("content"),
      ).toBe("noindex, nofollow"),
    );
    expect(document.querySelector('link[rel="canonical"]')).toBeNull();
    expect(document.querySelector('meta[property="og:image"]')).toBeNull();
  });

  it("shows the unavailable page when preview authorization is missing or refused", async () => {
    vi.stubGlobal("fetch", mockFetch());
    window.history.replaceState(null, "", "/preview");
    const view = render(<App />);
    await screen.findByRole("heading", {
      name: "გვერდი ხელმისაწვდომი არ არის",
    });
    // With no token, nothing is requested at all.
    expect(requests).toHaveLength(0);
    view.unmount();

    vi.stubGlobal("fetch", mockFetch(false));
    window.history.replaceState(null, "", "/preview#token=expired-token");
    render(<App />);
    await screen.findByRole("heading", {
      name: "გვერდი ხელმისაწვდომი არ არის",
    });
  });
});
