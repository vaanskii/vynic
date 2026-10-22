import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "../App";
import { menuA, siteA, siteB } from "./fixtures";

/**
 * The generic frontend, proved against the contracts it depends on.
 *
 * The central claim under test is that this app carries no restaurant identity
 * of its own: it asks two same-origin paths and renders whatever the host-
 * resolved answer was, so two hosts can never blend into one page.
 */
type Reply = { status?: number; body?: unknown };
const replies = new Map<string, Reply>();
const requests: { url: string; auth: string | null }[] = [];

function mockFetch() {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    requests.push({ url, auth: headers.get("Authorization") });
    const reply = replies.get(url) ?? { status: 404 };
    return {
      ok: (reply.status ?? 200) < 400,
      status: reply.status ?? 200,
      json: async () => reply.body ?? { message: "Website unavailable" },
    } as Response;
  });
}

function publish(site = siteA, menu = menuA) {
  replies.set("/api/website/bootstrap", { body: site });
  replies.set("/api/website/menu", { body: menu });
}

beforeEach(() => {
  replies.clear();
  requests.length = 0;
  localStorage.clear();
  sessionStorage.clear();
  vi.stubGlobal("fetch", mockFetch());
  window.history.replaceState(null, "", "/");
});
afterEach(() => {
  vi.unstubAllGlobals();
  document.head.querySelectorAll("meta,link[data-vynic]").forEach((element) => {
    if (element.getAttribute("charset") === null) element.remove();
  });
});

describe("Published restaurant page", () => {
  it("renders one restaurant's identity, content and live menu", async () => {
    publish();
    render(<App />);

    await screen.findByRole("heading", { level: 1, name: "ტაბლა" });
    expect(screen.getAllByText("Tabla").length).toBeGreaterThan(0);
    expect(screen.getByText("Rustaveli")).toBeInTheDocument();
    expect(
      screen.getByText("12 Rustaveli Avenue, Tbilisi"),
    ).toBeInTheDocument();

    // The owner's public override replaces the operational name.
    expect(screen.getByText("Signature khinkali")).toBeInTheDocument();
    expect(screen.queryByText("ხორცის ხინკალი")).toBeNull();
    expect(screen.getByText("Hand folded")).toBeInTheDocument();

    // A sized product shows its cheapest pour and then every exact price.
    expect(screen.getByText(/0\.15/)).toBeInTheDocument();
    expect(screen.getByText(/0\.75/)).toBeInTheDocument();

    // Hours that run past midnight are marked, not silently reversed.
    expect(screen.getByText(/11:00–01:00/)).toBeInTheDocument();
    expect(screen.getByText(/მეორე დღეს/)).toBeInTheDocument();

    // Nothing from another restaurant, and no client-chosen tenant anywhere.
    expect(screen.queryByText(/Zghva|Batumi/)).toBeNull();
    expect(requests.map((r) => r.url)).toEqual([
      "/api/website/bootstrap",
      "/api/website/menu",
    ]);
    expect(requests.every((r) => r.auth === null)).toBe(true);
  });

  it("publishes public page metadata and allows indexing only when published", async () => {
    publish();
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "ტაბლა" });
    await waitFor(() =>
      expect(document.title).toBe("Tabla — Georgian restaurant"),
    );
    expect(
      document.querySelector('meta[name="robots"]')?.getAttribute("content"),
    ).toBe("index, follow");
    expect(
      document.querySelector('meta[name="description"]')?.getAttribute("content"),
    ).toBe("Khinkali and local wine.");
    expect(
      document.querySelector('meta[property="og:title"]')?.getAttribute("content"),
    ).toBe("Tabla — Georgian restaurant");
    expect(
      document
        .querySelector('link[rel="canonical"]')
        ?.getAttribute("href"),
    ).toBe(`${window.location.origin}/`);
    expect(
      document.querySelector('link[rel="icon"]')?.getAttribute("href"),
    ).toBe(`${window.location.origin}/media/sample/logo-a.svg`);
  });

  it("switches language without refetching or changing the restaurant", async () => {
    publish();
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "ტაბლა" });
    expect(screen.getByRole("heading", { name: "ხინკალი" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /English/ }));
    expect(
      await screen.findByRole("heading", { name: "Khinkali" }),
    ).toBeInTheDocument();
    expect(document.documentElement.lang).toBe("en");
    expect(requests).toHaveLength(2);
  });

  it("renders a second host's restaurant with none of the first's content", async () => {
    publish(siteB, { ...menuA, categories: [] });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "ზღვა" });
    expect(screen.getByText("4 Seaside Road, Batumi")).toBeInTheDocument();
    expect(screen.queryByText(/Tabla|Rustaveli|Signature khinkali/)).toBeNull();
    // A published site with an empty menu says so rather than showing nothing.
    expect(screen.getByText("მენიუ მალე დაემატება.")).toBeInTheDocument();
  });
});

describe("Pages that are not published restaurant content", () => {
  it("does not render a CUSTOM Venue as a generic site, and stays noindex", async () => {
    replies.set("/api/website/bootstrap", {
      body: { schemaVersion: 2, mode: "CUSTOM" },
    });
    render(<App />);
    await screen.findByRole("heading", { name: "ინდივიდუალური ვებსაიტი" });
    expect(screen.queryByRole("navigation")).toBeNull();
    await waitFor(() =>
      expect(
        document.querySelector('meta[name="robots"]')?.getAttribute("content"),
      ).toBe("noindex, nofollow"),
    );
    // A CUSTOM marker must not cause a menu request for that Venue.
    expect(requests.map((r) => r.url)).toEqual(["/api/website/bootstrap"]);
  });

  it("shows an unavailable page for an unknown, disabled or unpublished host", async () => {
    render(<App />);
    await screen.findByRole("heading", {
      name: "გვერდი ხელმისაწვდომი არ არის",
    });
    await waitFor(() =>
      expect(
        document.querySelector('meta[name="robots"]')?.getAttribute("content"),
      ).toBe("noindex, nofollow"),
    );
    expect(document.querySelector('link[rel="canonical"]')).toBeNull();
  });

  it("refuses to render a schema version it does not implement", async () => {
    replies.set("/api/website/bootstrap", {
      body: { ...siteA, schemaVersion: 99 },
    });
    render(<App />);
    await screen.findByRole("heading", { name: "გვერდი ვერ გამოისახა" });
  });

  it("keeps the page usable when only the menu fails", async () => {
    replies.set("/api/website/bootstrap", { body: siteA });
    replies.set("/api/website/menu", { status: 500 });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "ტაბლა" });
    const menu = screen.getByRole("region", { name: "მენიუ" });
    expect(
      within(menu).getByText("მენიუ ამჟამად ვერ ჩაიტვირთა."),
    ).toBeInTheDocument();
  });
});
