import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { customerApi, customerLogout, hasCustomerSession } from "../customer/api";
import { LOCALE_STORAGE_KEY } from "../lib/i18n";
import { platformSession } from "../platform/session";
import { installApi, renderPlatform, type MockRequest } from "./platform-test-utils";

/**
 * The Vynic site, owner sign-in and the owner dashboard are one route tree;
 * Platform Admin stays beside it with its own principal. These tests drive the
 * real App routes and both real API clients against a stubbed fetch.
 */
const portal = (venues: unknown[] = []) => ({
  account: { email: "owner@test.invalid", displayName: "Nino" },
  releaseLinks: {},
  websiteBaseDomain: "vynic.localhost",
  venues,
});
const prepared = {
  venue: { id: "prepared-venue", name: "Prepared Table", loginCode: "prepared" },
  organization: { name: "Prepared LLC" },
  plan: { name: "Starter" },
  features: ["POS", "MANAGER_APP"],
  subscription: { status: "TRIAL" },
  managers: [],
  devices: [],
  enrollments: [],
  checklist: {},
  ready: false,
};
function customerBackend(venues: unknown[] = [prepared]) {
  return (request: MockRequest) => {
    const path = request.url.pathname;
    if (!path.startsWith("/customer/")) return undefined;
    if (path === "/customer/auth/login" || path === "/customer/auth/signup")
      return { body: { access_token: "customer-token" } };
    if (path === "/customer/portal") return { body: portal(venues) };
    if (path === "/customer/invitations/inspect")
      return {
        body: {
          email: "owner@test.invalid",
          organizationName: "Prepared LLC",
          existingAccount: false,
        },
      };
    if (path === "/customer/invitations/register")
      return { body: { access_token: "customer-token", venueId: "prepared-venue" } };
    if (path.endsWith("/website"))
      return { body: { mode: "NONE", entitled: false, revision: 0, draft: {} } };
    return { status: 404, body: { message: `unexpected ${path}` } };
  };
}
/** The Authorization header sent with each request to `prefix`. */
function bearers(fetchMock: ReturnType<typeof installApi>["fetchMock"], prefix: string) {
  return fetchMock.mock.calls
    .filter(([input]) => new URL(String(input), "http://vynic.test").pathname.startsWith(prefix))
    .map(([, init]) => new Headers(init?.headers).get("Authorization"));
}
async function signInCustomer() {
  await customerApi("auth/login", { email: "owner@test.invalid", password: "x" });
}

beforeEach(() => {
  customerLogout();
  localStorage.setItem(LOCALE_STORAGE_KEY, "ka");
  vi.stubGlobal("scrollTo", vi.fn());
});

describe("Vynic site to dashboard", () => {
  it("takes a visitor from the site through sign-up to first-time setup", async () => {
    const api = installApi(customerBackend([]));
    const user = userEvent.setup();
    renderPlatform("/", { authenticated: false });

    const banner = await screen.findByRole("banner");
    expect(within(banner).getByRole("link", { name: "შესვლა" })).toHaveAttribute("href", "/login");
    await user.click(within(banner).getByRole("link", { name: /დაწყება/ }));

    expect(await screen.findByRole("heading", { name: "ანგარიშის შექმნა" })).toBeVisible();
    await user.type(screen.getByLabelText("სახელი"), "Nino");
    await user.type(screen.getByLabelText("ელფოსტა"), "owner@test.invalid");
    await user.type(screen.getByLabelText("პაროლი"), "a long test passphrase");
    await user.click(screen.getByRole("button", { name: "ანგარიშის შექმნა" }));

    expect(await screen.findByLabelText("რესტორნის სახელი")).toBeVisible();
    expect(screen.getByText("მართვის პანელი")).toBeVisible();
    expect(bearers(api.fetchMock, "/customer/portal")).toEqual(["Bearer customer-token"]);
  });

  it("signs an existing owner in and opens the dashboard", async () => {
    installApi(customerBackend());
    const user = userEvent.setup();
    renderPlatform("/login", { authenticated: false });

    await user.type(await screen.findByLabelText("ელფოსტა"), "owner@test.invalid");
    await user.type(screen.getByLabelText("პაროლი"), "secret");
    await user.click(screen.getByRole("button", { name: "შესვლა" }));

    expect(await screen.findByRole("heading", { name: "გამარჯობა, Prepared Table" })).toBeVisible();
  });

  it("returns to the requested dashboard page after sign-in", async () => {
    installApi(customerBackend());
    const user = userEvent.setup();
    renderPlatform("/dashboard/subscription", { authenticated: false });

    await user.type(await screen.findByLabelText("ელფოსტა"), "owner@test.invalid");
    await user.type(screen.getByLabelText("პაროლი"), "secret");
    await user.click(screen.getByRole("button", { name: "შესვლა" }));

    expect(await screen.findByRole("heading", { name: "გამოწერა" })).toBeVisible();
  });

  it("shows a signed-in owner the way back to the dashboard", async () => {
    installApi(customerBackend());
    await signInCustomer();
    renderPlatform("/ka", { authenticated: false });

    const banner = await screen.findByRole("banner");
    expect(within(banner).getByRole("link", { name: /მართვის პანელი/ })).toHaveAttribute("href", "/dashboard");
    expect(within(banner).queryByRole("link", { name: "შესვლა" })).toBeNull();
  });

  it("accepts an invitation and opens the restaurant prepared for the owner", async () => {
    const api = installApi(customerBackend());
    const user = userEvent.setup();
    renderPlatform("/invite#token=invite-secret", { authenticated: false });

    expect(await screen.findByRole("heading", { name: "Prepared LLC" })).toBeVisible();
    await user.type(screen.getByLabelText("სახელი"), "Nino");
    await user.type(screen.getByLabelText("პაროლი"), "a long test passphrase");
    await user.click(screen.getByRole("button", { name: "მოწვევის მიღება" }));

    expect(await screen.findByRole("heading", { name: "გამარჯობა, Prepared Table" })).toBeVisible();
    // The prepared restaurant is used as is; nothing asks to create one.
    expect(screen.queryByLabelText("რესტორნის სახელი")).toBeNull();
    expect(api.requests.some((r) => r.url.pathname === "/customer/venues")).toBe(false);
    expect(api.requests.find((r) => r.url.pathname === "/customer/invitations/register")?.body)
      .toMatchObject({ token: "invite-secret" });
  });
});

describe("Owner and Platform Admin sessions stay separate", () => {
  it("does not let a Platform Admin session open the owner dashboard", async () => {
    const api = installApi(customerBackend());
    renderPlatform("/dashboard");

    expect(await screen.findByRole("heading", { name: "შესვლა" })).toBeVisible();
    expect(platformSession.read()).not.toBeNull();
    expect(hasCustomerSession()).toBe(false);
    expect(bearers(api.fetchMock, "/customer/")).toEqual([]);
  });

  it("signs owners in against the customer API only", async () => {
    const api = installApi(customerBackend());
    const user = userEvent.setup();
    renderPlatform("/login", { authenticated: false });

    await user.type(await screen.findByLabelText("ელფოსტა"), "admin@vynic.test");
    await user.type(screen.getByLabelText("პაროლი"), "secret");
    await user.click(screen.getByRole("button", { name: "შესვლა" }));

    await screen.findByRole("heading", { name: "გამარჯობა, Prepared Table" });
    expect(api.requests.some((r) => r.url.pathname.startsWith("/platform/auth"))).toBe(false);
    expect(platformSession.read()).toBeNull();
  });

  it("does not let an owner session open Platform Admin", async () => {
    const api = installApi(customerBackend());
    await signInCustomer();
    renderPlatform("/admin", { authenticated: false });

    expect(await screen.findByRole("heading", { name: "Sign in to Platform Admin" })).toBeVisible();
    expect(bearers(api.fetchMock, "/platform/")).toEqual([]);
  });
});

describe("Old portal addresses", () => {
  it.each([
    ["/portal", "შესვლა"],
    ["/portal/login", "შესვლა"],
    ["/portal/signup", "ანგარიშის შექმნა"],
    ["/start", "ანგარიშის შექმნა"],
  ])("sends %s to the matching page", async (from, heading) => {
    installApi(customerBackend());
    renderPlatform(from, { authenticated: false });
    expect(await screen.findByRole("heading", { name: heading })).toBeVisible();
  });

  it.each([
    ["/portal", "გამარჯობა, Prepared Table"],
    ["/portal?section=menu", "მენიუ"],
    ["/portal?section=profile", "რესტორნის პროფილი"],
    ["/portal?section=unknown", "გამარჯობა, Prepared Table"],
  ])("opens %s in the dashboard for a signed-in owner", async (from, heading) => {
    installApi(customerBackend());
    await signInCustomer();
    renderPlatform(from, { authenticated: false });
    expect(await screen.findByRole("heading", { name: heading })).toBeVisible();
  });

  it("keeps the invitation secret when an old invitation link is opened", async () => {
    const api = installApi(customerBackend());
    renderPlatform("/portal/invite#token=old-link", { authenticated: false });

    expect(await screen.findByRole("heading", { name: "Prepared LLC" })).toBeVisible();
    await waitFor(() =>
      expect(api.requests.find((r) => r.url.pathname === "/customer/invitations/inspect")?.body)
        .toEqual({ token: "old-link" }),
    );
  });

  it("opens product pages as sections of the site", async () => {
    installApi();
    const scrolled: string[] = [];
    Element.prototype.scrollIntoView = function (this: Element) {
      scrolled.push(this.id);
    };
    renderPlatform("/features", { authenticated: false });
    expect(await screen.findByRole("heading", { name: "რესტორნის POS — დარბაზის მართვა" })).toBeInTheDocument();
    await waitFor(() => expect(scrolled).toContain("product"));
  });
});
