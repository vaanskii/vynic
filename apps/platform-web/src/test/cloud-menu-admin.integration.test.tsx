import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { ids, installApi, plans, product, renderPlatform } from "./platform-test-utils";

describe("Cloud menu Admin setup", () => {
  it("toggles editing directly in both directions without acknowledgement", async () => {
    let enabled = false;
    const api = installApi(request => {
      if (request.url.pathname.endsWith("/menu-management/cloud")) { enabled = (request.body as { enabled: boolean }).enabled; return { body: product }; }
      if (request.url.pathname.endsWith("/product")) return { body: { ...product, menuManagement: { authority: "CLOUD", enabled, canEnableCloud: true, reason: null } } };
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/product`);
    const heading = await screen.findByRole("heading", { name: "მენიუს მართვა Dashboard-ში" });
    const panel = within(heading.closest("section")!);
    expect(screen.queryByRole("checkbox")).toBeNull();
    await user.click(panel.getByRole("button", { name: "ჩართვა" }));
    await waitFor(() => expect(panel.getByRole("button", { name: "გამორთვა" })).toBeEnabled());
    expect(screen.queryByRole("dialog")).toBeNull();
    await user.click(panel.getByRole("button", { name: "გამორთვა" }));
    await waitFor(() => expect(panel.getByRole("button", { name: "ჩართვა" })).toBeEnabled());
    expect(api.requests.filter(r => r.url.pathname.endsWith("/menu-management/cloud")).map(r => r.body)).toEqual([{ enabled: true }, { enabled: false }]);
  });
  it("explains why a venue with POS history cannot switch", async () => {
    installApi(request => request.url.pathname.endsWith("/product") ? { body: { ...product, menuManagement: { authority: "POS", canEnableCloud: false, reason: "Existing POS devices." } } } : undefined);
    renderPlatform(`/venues/${ids.venue}/product`);
    expect(await screen.findByText(/Existing POS devices/)).toBeVisible();
    expect(screen.queryByRole("checkbox")).toBeNull();
  });
  it("warns when a Website-only venue is left on POS authority and offers the repair", async () => {
    installApi(request => request.url.pathname.endsWith("/product") ? { body: { ...product, menuManagement: { authority: "POS", enabled: false, canEnableCloud: true, reason: null, posIncluded: false, needsCloudAuthority: true } } } : undefined);
    renderPlatform(`/venues/${ids.venue}/product`);
    const heading = await screen.findByRole("heading", { name: "მენიუს მართვა Dashboard-ში" });
    const panel = within(heading.closest("section")!);
    expect(panel.getByRole("alert")).toHaveTextContent(/POS-ზეა მიბმული/);
    expect(panel.getByText(/მენიუს წყარო/)).toHaveTextContent("POS");
    expect(panel.getByRole("button", { name: "ჩართვა" })).toBeEnabled();
  });
  it("adds the Website-only plan and refreshes the plan list", async () => {
    let added = false;
    installApi(request => {
      if (request.url.pathname === "/platform/plans/website-only") { added = true; return { body: [] }; }
      if (request.url.pathname === "/platform/plans") return { body: added ? [...plans, { ...plans[0], id: "website", key: "WEBSITE_ONLY", name: "Website only" }] : plans };
    });
    const user = userEvent.setup();
    renderPlatform("/plans");
    await user.click(await screen.findByRole("button", { name: "Add Website-only plan" }));
    await waitFor(() => expect(screen.getByText("WEBSITE_ONLY")).toBeVisible());
    expect(screen.queryByRole("button", { name: "Add Website-only plan" })).toBeNull();
  });
});
