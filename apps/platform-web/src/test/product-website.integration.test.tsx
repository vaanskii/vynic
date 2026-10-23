import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import {
  ids,
  websiteCapabilities,
  installApi,
  plans,
  product,
  renderPlatform,
} from "./platform-test-utils";

describe("venue product and website controls", () => {
  it("shows capabilities and overrides while commercial plan assignment stays out of Product", async () => {
    let productReads = 0;
    const starterPlan = {
      ...plans[0],
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      key: "STARTER",
      name: "Starter",
    };
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/product")) productReads += 1;
      if (request.url.pathname === "/platform/plans")
        return { body: [...plans, starterPlan] };
      if (request.url.pathname.endsWith("/plan") && request.method === "PUT")
        return { body: product };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/product`);

    expect((await screen.findAllByText("პაკეტში შედის")).length).toBe(2);
    expect(screen.getByText("ინდივიდუალურად გამორთულია")).toBeVisible();
    expect(screen.queryByLabelText("პაკეტი")).toBeNull();
    expect(screen.queryByRole("button", { name: "პაკეტის შეცვლა" })).toBeNull();

    const managerRow = screen
      .getAllByText("მენეჯერის აპლიკაცია")
      .map((element) => element.closest("article"))
      .find((element): element is HTMLElement => element !== null);
    expect(managerRow).not.toBeNull();
    await user.click(
      within(managerRow as HTMLElement).getByRole("button", {
        name: "პაკეტის მიხედვით",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "პაკეტის მიხედვით",
      }),
    );
    await waitFor(() =>
      expect(
        api.requests.some(
          (request) =>
            request.method === "DELETE" &&
            request.url.pathname.endsWith("/features/MANAGER_APP"),
        ),
      ).toBe(true),
    );
    await waitFor(() => expect(productReads).toBeGreaterThan(1));
  });

  it("shows the exact assigned SaaS address separately from same-prefix external aliases", async () => {
    installApi((request) => {
      if (request.url.pathname.endsWith("/product"))
        return {
          body: {
            ...product,
            website: {
              ...product.website,
              hostname: "tabla.vynic.localhost",
              provisioning: {
                status: "PUBLISHED",
                assignedSlug: "tabla",
                publishedAt: null,
              },
            },
          },
        };
      if (request.url.pathname.endsWith("/domains"))
        return {
          body: ["tabla.example", "tabla.vynic.localhost"].map(
            (hostname, i) => ({
              id: i === 0 ? ids.domain : ids.plan,
              venueId: ids.venue,
              hostname,
              status: "ACTIVE",
              createdAt: "2026-08-31T10:00:00.000Z",
              updatedAt: "2026-08-31T10:00:00.000Z",
            }),
          ),
        };
      return undefined;
    });
    renderPlatform(`/venues/${ids.venue}/website`);
    expect(
      await screen.findByText("Current SaaS address: tabla.vynic.localhost"),
    ).toBeVisible();
    expect(screen.getByText("Additional hostnames: tabla.example")).toBeVisible();
  });

  it("retains the old domain and error when the displayed hostname is stale", async () => {
    installApi((request) => {
      if (request.url.pathname.endsWith("/domains"))
        return {
          body: [
            {
              id: ids.domain,
              venueId: ids.venue,
              hostname: "current.vynic.localhost",
              status: "ACTIVE",
              createdAt: "2026-08-31T10:00:00.000Z",
              updatedAt: "2026-08-31T10:00:00.000Z",
            },
          ],
        };
      if (request.method === "PATCH")
        return {
          status: 409,
          body: { message: "Hostname changed. Refresh before editing." },
        };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/website`);
    await user.click(
      await screen.findByRole("button", { name: "Change hostname" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Change hostname",
    });
    const field = within(dialog).getByRole("textbox", {
      name: /^New hostname/,
    });
    await user.clear(field);
    await user.type(field, "new.vynic.localhost");
    await user.type(
      within(dialog).getByRole("textbox", { name: "Change reason" }),
      "Support request",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Save hostname" }),
    );
    expect(
      await within(dialog).findByText(
        "Hostname changed. Refresh before editing.",
      ),
    ).toBeVisible();
    expect(
      within(dialog).getByRole("textbox", { name: /^New hostname/ }),
    ).toHaveValue("new.vynic.localhost");
    expect(screen.queryByText(/Hostname changed. Check DNS/)).toBeNull();
  });

  it("surfaces a WebsiteMode inconsistency without silently correcting it", async () => {
    installApi((request) =>
      request.url.pathname.endsWith("/product")
        ? {
            body: {
              ...product,
              effectiveFeatures: ["POS"],
              website: {
                entitled: false,
                configuredMode: "SAAS",
                effectiveMode: "NONE",
                consistent: false,
              },
            },
          }
        : undefined,
    );
    renderPlatform(`/venues/${ids.venue}/website`);
    expect(
      await screen.findByText("Website entitlement and configuration disagree"),
    ).toBeVisible();
    expect(
      screen.getByText(/review the two settings before publishing a hostname/i),
    ).toBeVisible();
    expect(screen.getAllByText("DRAFT").length).toBeGreaterThan(0);
  });

  it("registers, changes status, and releases domains through guarded UI", async () => {
    const domain = {
      id: ids.domain,
      venueId: ids.venue,
      hostname: "vankisi.example",
      status: "ACTIVE",
      createdAt: "2026-08-31T10:00:00.000Z",
      updatedAt: "2026-08-31T10:00:00.000Z",
    };
    let domains = [domain];
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/domains") && request.method === "GET")
        return { body: domains };
      if (
        request.url.pathname.endsWith("/domains") &&
        request.method === "POST"
      ) {
        domains = [
          ...domains,
          {
            ...domain,
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            hostname: String(request.body?.hostname),
            status: "PENDING",
          },
        ];
        return { body: domains[1] };
      }
      if (
        request.url.pathname.endsWith(`/domains/${ids.domain}`) &&
        request.method === "PATCH"
      ) {
        domains = domains.map((item) =>
          item.id === ids.domain
            ? { ...item, hostname: String(request.body?.hostname) }
            : item,
        );
        return { body: domains[0] };
      }
      if (request.url.pathname.endsWith(`/domains/${ids.domain}/status`)) {
        domains = domains.map((item) =>
          item.id === ids.domain ? { ...item, status: "DISABLED" } : item,
        );
        return { body: domains[0] };
      }
      if (
        request.url.pathname.endsWith(`/domains/${ids.domain}`) &&
        request.method === "DELETE"
      ) {
        domains = domains.filter((item) => item.id !== ids.domain);
        return { body: { released: domain.hostname } };
      }
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/website`);
    expect(await screen.findByText("vankisi.example")).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Register domain" }));
    const registerDialog = await screen.findByRole("dialog", {
      name: "Register domain",
    });
    await user.type(within(registerDialog).getByRole("textbox"), "new.example");
    await user.click(screen.getByRole("button", { name: "Register" }));
    await waitFor(() =>
      expect(
        api.requests.some(
          (request) =>
            request.method === "POST" &&
            request.url.pathname.endsWith("/domains"),
        ),
      ).toBe(true),
    );

    expect(await screen.findByText("Pending connection")).toBeVisible();
    expect(screen.getByText(/Saving here updates the database only/)).toBeVisible();
    expect(screen.getByRole("button", { name: "Activate binding" })).toBeVisible();

    const originalRow = screen.getByText("vankisi.example").closest("tr");
    await user.click(
      within(originalRow as HTMLElement).getByRole("button", {
        name: "Change hostname",
      }),
    );
    const renameDialog = await screen.findByRole("dialog", {
      name: "Change hostname",
    });
    const hostnameField = within(renameDialog).getByRole("textbox", {
      name: /^New hostname/,
    });
    await user.clear(hostnameField);
    await user.type(hostnameField, "restaurant.vynic.localhost");
    await user.type(
      within(renameDialog).getByRole("textbox", { name: "Change reason" }),
      "Customer contacted support",
    );
    await user.click(
      within(renameDialog).getByRole("button", { name: "Save hostname" }),
    );
    await waitFor(() =>
      expect(
        api.requests.find(
          (request) =>
            request.method === "PATCH" &&
            request.url.pathname.endsWith(`/domains/${ids.domain}`),
        )?.body,
      ).toEqual({
        hostname: "restaurant.vynic.localhost",
        expectedHostname: "vankisi.example",
        reason: "Customer contacted support",
      }),
    );
    expect(await screen.findByText("restaurant.vynic.localhost")).toBeVisible();
    const activeDomainRow = screen
      .getByText("restaurant.vynic.localhost")
      .closest("tr");
    expect(activeDomainRow).not.toBeNull();
    await user.click(
      within(activeDomainRow as HTMLElement).getByRole("button", {
        name: "Disable",
      }),
    );
    await user.click(
      await screen.findByRole("button", { name: "Change status" }),
    );
    await waitFor(() =>
      expect(
        api.requests.some(
          (request) =>
            request.method === "PUT" &&
            request.url.pathname.endsWith("/status"),
        ),
      ).toBe(true),
    );

    const disabledDomainRow = screen
      .getByText("restaurant.vynic.localhost")
      .closest("tr");
    expect(disabledDomainRow).not.toBeNull();
    await user.click(
      within(disabledDomainRow as HTMLElement).getByRole("button", {
        name: "Release",
      }),
    );
    await user.click(
      await screen.findByRole("button", { name: "Release domain" }),
    );
    await waitFor(() =>
      expect(
        api.requests.some(
          (request) =>
            request.method === "DELETE" &&
            request.url.pathname.endsWith(ids.domain),
        ),
      ).toBe(true),
    );
  });
});

describe("Website capabilities", () => {
  it("shows every shared capability and offers only possible switches", async () => {
    const api = installApi((request) => {
      const path = request.url.pathname;
      if (path.endsWith("/product"))
        return {
          body: {
            ...product,
            website: {
              entitled: true,
              configuredMode: "SAAS",
              effectiveMode: "SAAS",
              consistent: true,
            },
          },
        };
      if (
        path.endsWith("/website-capabilities/HOURS") &&
        request.method === "PUT"
      )
        return {
          body: websiteCapabilities.map((c) =>
            c.key === "HOURS"
              ? { ...c, enabled: false, available: false, live: false }
              : c,
          ),
        };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/website`);
    await screen.findByRole("heading", { name: "Website capabilities" });
    await waitFor(() =>
      expect(
        document.querySelector('tr[data-capability="MENU"]'),
      ).not.toBeNull(),
    );
    const row = (key: string) =>
      within(
        document.querySelector<HTMLElement>(`tr[data-capability="${key}"]`)!,
      );
    expect(row("MENU").getByText("Included")).toBeVisible();
    // Not in the package: visible, but never switchable on.
    expect(row("ONLINE_PAYMENTS").getByText("Not included")).toBeVisible();
    expect(
      row("ONLINE_PAYMENTS").getByRole("button", { name: /Turn on/ }),
    ).toBeDisabled();
    // Not built: no switch at all.
    expect(row("EVENTS").getByText("Not built")).toBeVisible();
    expect(row("EVENTS").queryByRole("button")).toBeNull();
    expect(
      row("RESERVATIONS").getByText(/online payments are not live/),
    ).toBeVisible();
    await user.click(
      row("HOURS").getByRole("button", { name: "Turn off Hours" }),
    );
    await waitFor(() =>
      expect(
        api.requests.find(
          (r) => r.method === "PUT" && r.url.pathname.endsWith("/HOURS"),
        )?.body,
      ).toEqual({ enabled: false }),
    );
    expect(
      await row("HOURS").findByRole("button", { name: "Turn on Hours" }),
    ).toBeEnabled();
  });
});

describe("CUSTOM website provisioning", () => {
  const customView = (patch: Record<string, unknown> = {}) => ({
    venueId: ids.venue,
    mode: "CUSTOM",
    effectiveMode: "CUSTOM",
    entitled: true,
    commercialStatus: "TRIAL",
    trialEndsAt: "2026-10-09T10:00:00.000Z",
    status: "NOT_CONFIGURED",
    siteKey: null,
    statusNote: null,
    updatedAt: null,
    domains: [],
    primaryDomain: null,
    publicUrl: null,
    menu: {
      authority: "CLOUD",
      editingEnabled: true,
      posIncluded: false,
      needsCloudAuthority: false,
    },
    payments: "NOT_CONFIGURED",
    readiness: {
      complete: false,
      checks: {
        entitled: true,
        customMode: true,
        siteKey: false,
        activeDomain: false,
      },
    },
    audit: [],
    ...patch,
  });

  it("records the frontend identity and shows the server's readiness refusal", async () => {
    const api = installApi((request) => {
      const path = request.url.pathname;
      if (path.endsWith("/product"))
        return {
          body: {
            ...product,
            website: {
              entitled: true,
              configuredMode: "CUSTOM",
              effectiveMode: "CUSTOM",
              consistent: true,
            },
          },
        };
      if (path.endsWith("/domains")) return { body: [] };
      if (path.endsWith("/custom-website") && request.method === "GET")
        return { body: customView() };
      if (path.endsWith("/custom-website") && request.method === "PUT")
        return request.body?.status === "ACTIVE"
          ? {
              status: 409,
              body: {
                message:
                  "ACTIVE requires Website access, a frontend identity and an active domain",
              },
            }
          : {
              body: customView({
                status: "SETUP_PENDING",
                siteKey: request.body?.siteKey,
                readiness: {
                  complete: false,
                  checks: {
                    entitled: true,
                    customMode: true,
                    siteKey: true,
                    activeDomain: false,
                  },
                },
                audit: [
                  {
                    id: "e1",
                    action: "venue.custom_website_site_key_changed",
                    metadata: { from: null, to: request.body?.siteKey },
                    createdAt: "2026-09-25T10:00:00.000Z",
                    actor: "Operator",
                  },
                ],
              }),
            };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/website`);

    expect(
      await screen.findByText("Custom frontend identity recorded"),
    ).toBeVisible();
    expect(screen.getByText("Not recorded")).toBeVisible();
    await user.type(
      screen.getByLabelText(/^Custom frontend identity/),
      "restaurant-x-web",
    );
    await user.click(screen.getByRole("button", { name: "Save custom setup" }));
    await waitFor(() =>
      expect(
        api.requests.find(
          (r) =>
            r.method === "PUT" && r.url.pathname.endsWith("/custom-website"),
        )?.body,
      ).toEqual({ siteKey: "restaurant-x-web", status: "SETUP_PENDING" }),
    );
    expect(await screen.findByText("Frontend identity changed")).toBeVisible();

    await user.selectOptions(screen.getByLabelText(/^Setup status/), "ACTIVE");
    await user.click(screen.getByRole("button", { name: "Save custom setup" }));
    expect(
      await screen.findByText(/ACTIVE requires Website access/),
    ).toBeVisible();
  });

  it("opens and checks the local frontend without treating ACTIVE as reachable", async () => {
    const url = "http://vankisi.localhost:5174/";
    const api = installApi((request) => {
      const path = request.url.pathname;
      if (path.endsWith("/product"))
        return {
          body: {
            ...product,
            website: {
              entitled: true,
              configuredMode: "CUSTOM",
              effectiveMode: "CUSTOM",
              consistent: true,
            },
          },
        };
      if (path.endsWith("/domains")) return { body: [] };
      if (path.endsWith("/custom-website/check"))
        return {
          body: {
            availability: "UNREACHABLE",
            checkedAt: "2026-09-26T09:00:00.000Z",
            hostname: "vankisi.localhost",
            url,
            frontend: { status: null, detail: "Connection refused" },
            api: {
              state: "FAILED",
              status: null,
              detail: "Connection refused",
            },
          },
        };
      if (path.endsWith("/custom-website"))
        return {
          body: customView({
            status: "ACTIVE",
            siteKey: "vankisi-web",
            primaryDomain: "vankisi.localhost",
            publicUrl: null,
            localFrontend: {
              state: "CONFIGURED",
              siteKey: "vankisi-web",
              hostname: "vankisi.localhost",
              port: 5174,
              url,
              source: "CUSTOM_WEBSITE_LOCAL_FRONTENDS",
              detail: "vankisi-web=5174 in CUSTOM_WEBSITE_LOCAL_FRONTENDS",
              problems: [],
            },
            menu: {
              authority: "POS",
              editingEnabled: false,
              posIncluded: false,
              needsCloudAuthority: true,
            },
          }),
        };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/website`);

    const live = within(
      (await screen.findByRole("heading", { name: "Live site" })).closest(
        "section",
      )!,
    );
    expect(live.getByText("UNKNOWN")).toBeVisible();
    expect(live.getByText("Not checked yet")).toBeVisible();
    expect(live.getByText(url)).toBeVisible();
    expect(live.getByText("No public domain")).toBeVisible();
    expect(
      live.getByText("vankisi-web=5174 in CUSTOM_WEBSITE_LOCAL_FRONTENDS"),
    ).toBeVisible();
    expect(live.queryByText("Configure local development")).toBeNull();
    expect(live.getByRole("link", { name: /Open website/ })).toHaveAttribute(
      "href",
      url,
    );
    await user.click(live.getByRole("button", { name: "Check now" }));
    expect(await live.findByText("UNREACHABLE")).toBeVisible();
    expect(live.getByText("Connection refused")).toBeVisible();
    expect(
      api.requests.filter((r) => r.url.pathname.endsWith("/check")),
    ).toHaveLength(1);
    // Configured ACTIVE stays ACTIVE: availability is reported apart.
    expect(screen.getAllByText("ACTIVE").length).toBeGreaterThan(0);

    const menu = within(
      screen.getByRole("heading", { name: "Menu" }).closest("section")!,
    );
    expect(menu.getByRole("alert")).toHaveTextContent(/still on POS authority/);
  });

  const liveSite = async (view: Record<string, unknown>) => {
    const api = installApi((request) => {
      const path = request.url.pathname;
      if (path.endsWith("/product"))
        return {
          body: {
            ...product,
            website: {
              entitled: true,
              configuredMode: "CUSTOM",
              effectiveMode: "CUSTOM",
              consistent: true,
            },
          },
        };
      if (path.endsWith("/domains")) return { body: [] };
      if (path.endsWith("/custom-website")) return { body: customView(view) };
      return undefined;
    });
    renderPlatform(`/venues/${ids.venue}/website`);
    const live = within(
      (await screen.findByRole("heading", { name: "Live site" })).closest(
        "section",
      )!,
    );
    return { api, live };
  };

  it("says a missing local frontend is not configured instead of guessing a port", async () => {
    const { api, live } = await liveSite({
      status: "ACTIVE",
      siteKey: "restaurant-x-web",
      primaryDomain: "restaurant-x.localhost",
      publicUrl: null,
      localFrontend: {
        state: "NOT_CONFIGURED",
        siteKey: "restaurant-x-web",
        hostname: "restaurant-x.localhost",
        port: null,
        url: null,
        source: "CUSTOM_WEBSITE_LOCAL_FRONTENDS",
        detail:
          "Local frontend for restaurant-x-web is not configured: add restaurant-x-web=<port> to CUSTOM_WEBSITE_LOCAL_FRONTENDS in the backend environment and restart it",
        problems: [
          "CUSTOM_WEBSITE_DEV_PORT is no longer read; map each frontend in CUSTOM_WEBSITE_LOCAL_FRONTENDS",
        ],
      },
    });
    expect(live.getByText("Not configured")).toBeVisible();
    expect(
      live.getByText(/CUSTOM_WEBSITE_DEV_PORT is no longer read/),
    ).toBeVisible();
    expect(live.getByText("Configure local development")).toBeVisible();
    expect(
      live.getByText("CUSTOM_WEBSITE_LOCAL_FRONTENDS=restaurant-x-web=<port>"),
    ).toBeInTheDocument();
    expect(live.getByRole("button", { name: "Check now" })).toBeDisabled();
    expect(live.getByRole("button", { name: "Open website" })).toBeDisabled();
    expect(live.queryByText(/5176/)).toBeNull();
    expect(api.requests.some((r) => r.url.pathname.endsWith("/check"))).toBe(
      false,
    );
  });

  it("shows only the public URL in production", async () => {
    const { live } = await liveSite({
      status: "ACTIVE",
      siteKey: "vankisi-web",
      primaryDomain: "vankisi.ge",
      publicUrl: "https://vankisi.ge/",
    });
    expect(live.queryByText("Local frontend")).toBeNull();
    expect(live.queryByText("Configure local development")).toBeNull();
    expect(live.getByText("https://vankisi.ge/")).toBeVisible();
    expect(live.getByRole("link", { name: /Open website/ })).toHaveAttribute(
      "href",
      "https://vankisi.ge/",
    );
    expect(live.getByRole("button", { name: "Check now" })).toBeEnabled();
    expect(live.queryByText(/localhost|5174|5176/)).toBeNull();
  });
});
