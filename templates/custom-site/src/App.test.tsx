import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";

const bootstrap = (site: Record<string, unknown>) => ({
  schemaVersion: 1,
  mode: "CUSTOM",
  site: { key: "custom-site-template", status: "ACTIVE", ...site },
  profile: {
    name: "Restaurant X",
    branchName: null,
    address: "1 Test Street",
    phone: "+995 555 000 000",
    timezone: "Asia/Tbilisi",
    currency: "GEL",
  },
  info: {
    workingHours: [],
    contactEmail: "",
    mapUrl: "",
    socials: [],
    gallery: [],
  },
  capabilities: {
    profile: true,
    menu: true,
    hours: false,
    gallery: false,
    customerAccounts: true,
    onlinePayments: false,
    reservations: false,
  },
});

function serve(routes: Record<string, { status?: number; body?: unknown }>) {
  const fetchMock = vi.fn(async (url: string) => {
    const route = routes[url] ?? { status: 404 };
    return new Response(JSON.stringify(route.body ?? {}), {
      status: route.status ?? 200,
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

afterEach(() => vi.unstubAllGlobals());

describe("custom site template", () => {
  it("renders the Host's restaurant and its menu", async () => {
    serve({
      "/api/website/venue": { body: bootstrap({}) },
      "/api/website/venue/menu": {
        body: {
          schemaVersion: 1,
          currency: "GEL",
          categories: [
            {
              id: "c1",
              slug: "mains",
              name: { ka: "ძირითადი", en: "Mains" },
              items: [
                {
                  id: "i1",
                  name: { ka: "ხინკალი", en: "Khinkali" },
                  displayName: null,
                  description: null,
                  imageUrl: null,
                  price: 12,
                  variants: [],
                },
              ],
              subcategories: [],
            },
          ],
        },
      },
    });
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Restaurant X" })).toBeVisible();
    expect(await screen.findByText("ხინკალი")).toBeVisible();
    expect(screen.getByText("12.00 ₾")).toBeVisible();
    // Reservations are not a capability of this Venue: no booking form.
    expect(screen.queryByRole("heading", { name: "დაჯავშნა" })).toBeNull();
  });

  it("refuses to dress another restaurant's domain in this design", async () => {
    const fetchMock = serve({
      "/api/website/venue": { body: bootstrap({ key: "vankisi-web" }) },
    });
    render(<App />);
    expect(
      await screen.findByText("This website is temporarily unavailable."),
    ).toHaveAttribute("data-bound", "vankisi-web");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("shows coming-soon while setup is pending and nothing on an unknown host", async () => {
    serve({
      "/api/website/venue": {
        body: bootstrap({ status: "SETUP_PENDING" }),
      },
    });
    const { unmount } = render(<App />);
    expect(await screen.findByText("Our new website is coming soon.")).toBeVisible();
    unmount();
    serve({});
    render(<App />);
    expect(await screen.findByText("This website is not available.")).toBeVisible();
  });
});
