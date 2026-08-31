import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { ids, installApi, plans, product, renderPlatform } from "./platform-test-utils";

describe("venue product and website controls", () => {
  it("shows plan inheritance, explicit overrides, and refetches after a plan mutation", async () => {
    let productReads = 0;
    const starterPlan = { ...plans[0], id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", key: "STARTER", name: "Starter" };
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/product")) productReads += 1;
      if (request.url.pathname === "/platform/plans") return { body: [...plans, starterPlan] };
      if (request.url.pathname.endsWith("/plan") && request.method === "PUT") return { body: product };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/product`);

    expect((await screen.findAllByText("Included by plan")).length).toBe(2);
    expect(screen.getByText("Explicitly disabled")).toBeVisible();
    await user.selectOptions(screen.getByLabelText("Plan"), starterPlan.id);
    await user.click(screen.getByRole("button", { name: "Change plan" }));
    await user.click(await screen.findByRole("button", { name: "Assign plan" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "PUT" && request.url.pathname.endsWith("/plan"))).toBe(true));

    const managerRow = screen.getAllByText("Manager App")
      .map((element) => element.closest("article"))
      .find((element): element is HTMLElement => element !== null);
    expect(managerRow).not.toBeNull();
    await user.click(within(managerRow as HTMLElement).getByRole("button", { name: "Inherit" }));
    await user.click(await screen.findByRole("button", { name: "Use plan value" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "DELETE" && request.url.pathname.endsWith("/features/MANAGER_APP"))).toBe(true));
    await waitFor(() => expect(productReads).toBeGreaterThan(1));
  });

  it("surfaces a WebsiteMode inconsistency without silently correcting it", async () => {
    installApi((request) => request.url.pathname.endsWith("/product") ? { body: { ...product, effectiveFeatures: ["POS"], website: { entitled: false, configuredMode: "SAAS", effectiveMode: "NONE", consistent: false } } } : undefined);
    renderPlatform(`/admin/venues/${ids.venue}/website`);
    expect(await screen.findByText("Website entitlement and configuration disagree")).toBeVisible();
    expect(screen.getByText(/review the two settings before publishing a hostname/i)).toBeVisible();
    expect(screen.getByText("INCONSISTENT")).toBeVisible();
  });

  it("registers, changes status, and releases domains through guarded UI", async () => {
    const domain = { id: ids.domain, venueId: ids.venue, hostname: "vankisi.example", status: "ACTIVE", createdAt: "2026-08-31T10:00:00.000Z", updatedAt: "2026-08-31T10:00:00.000Z" };
    let domains = [domain];
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/domains") && request.method === "GET") return { body: domains };
      if (request.url.pathname.endsWith("/domains") && request.method === "POST") { domains = [...domains, { ...domain, id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", hostname: String(request.body?.hostname) }]; return { body: domains[1] }; }
      if (request.url.pathname.endsWith(`/domains/${ids.domain}/status`)) { domains = domains.map((item) => item.id === ids.domain ? { ...item, status: "DISABLED" } : item); return { body: domains[0] }; }
      if (request.url.pathname.endsWith(`/domains/${ids.domain}`) && request.method === "DELETE") { domains = domains.filter((item) => item.id !== ids.domain); return { body: { released: domain.hostname } }; }
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/website`);
    expect(await screen.findByText("vankisi.example")).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Register domain" }));
    const registerDialog = await screen.findByRole("dialog", { name: "Register domain" });
    await user.type(within(registerDialog).getByRole("textbox"), "new.example");
    await user.click(screen.getByRole("button", { name: "Register" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "POST" && request.url.pathname.endsWith("/domains"))).toBe(true));

    const activeDomainRow = screen.getByText("vankisi.example").closest("tr");
    expect(activeDomainRow).not.toBeNull();
    await user.click(within(activeDomainRow as HTMLElement).getByRole("button", { name: "Disable" }));
    await user.click(await screen.findByRole("button", { name: "Change status" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "PUT" && request.url.pathname.endsWith("/status"))).toBe(true));

    const disabledDomainRow = screen.getByText("vankisi.example").closest("tr");
    expect(disabledDomainRow).not.toBeNull();
    await user.click(within(disabledDomainRow as HTMLElement).getByRole("button", { name: "Release" }));
    await user.click(await screen.findByRole("button", { name: "Release domain" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "DELETE" && request.url.pathname.endsWith(ids.domain))).toBe(true));
  });
});
