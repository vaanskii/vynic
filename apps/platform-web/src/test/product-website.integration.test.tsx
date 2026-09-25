import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import {
  ids,
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
          },
        ];
        return { body: domains[1] };
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

    const activeDomainRow = screen.getByText("vankisi.example").closest("tr");
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

    const disabledDomainRow = screen.getByText("vankisi.example").closest("tr");
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
    payments: "NOT_CONFIGURED",
    capabilities: {
      profile: true,
      menu: true,
      customerAccounts: true,
      onlinePayments: false,
      reservations: false,
    },
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
          (r) => r.method === "PUT" && r.url.pathname.endsWith("/custom-website"),
        )?.body,
      ).toEqual({ siteKey: "restaurant-x-web", status: "SETUP_PENDING" }),
    );
    expect(await screen.findByText("Frontend identity changed")).toBeVisible();

    await user.selectOptions(
      screen.getByLabelText(/^Setup status/),
      "ACTIVE",
    );
    await user.click(screen.getByRole("button", { name: "Save custom setup" }));
    expect(
      await screen.findByText(/ACTIVE requires Website access/),
    ).toBeVisible();
  });
});
