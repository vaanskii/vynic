import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect } from "vitest";
import { actor, ids, installApi, product, renderPlatform } from "./platform-test-utils";

describe("Admin Manager one-use linking", () => {
  function api(readonly = false, failed = false) {
    return installApi((r) => {
      if (r.url.pathname.endsWith("/auth/me") && readonly) return { body: { ...actor, role: "SUPPORT_READONLY" } };
      if (r.url.pathname.endsWith("/product")) return { body: { ...product, effectiveFeatures: ["MANAGER_APP", "POS"] } };
      if (r.url.pathname.endsWith("/managers")) return { body: [{ id: "manager", username: "synthetic", role: "MANAGER", isActive: true }] };
      if (r.url.pathname.endsWith("/manager-links") && r.method === "POST") return failed ? { status: 503, body: { message: "Link issuance unavailable" } } : { body: { id: ids.device, code: "synthetic-once", expiresAt: "2099-01-01T00:00:00Z" } };
      return undefined;
    });
  }
  it("issues a code only by explicit Admin action, shows it once and clears it on close", async () => {
    const mock = api(), user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/product`);
    await user.click(await screen.findByRole("button", { name: "Create Manager linking code" }));
    const dialog = await screen.findByRole("dialog", { name: "Manager linking code" });
    expect(within(dialog).getByText("synthetic-once")).toBeVisible();
    expect(within(dialog).getByText(/still require PIN/)).toBeVisible();
    expect(mock.requests.filter((r) => r.method === "POST" && r.url.pathname.endsWith("/manager-links"))).toHaveLength(1);
    await user.click(within(dialog).getByRole("button", { name: "Done" }));
    expect(screen.queryByText("synthetic-once")).not.toBeInTheDocument();
    expect(mock.requests.some((r) => r.method === "POST" && r.url.pathname.endsWith("/managers"))).toBe(false);
  });
  it("read-only support has no issuance control", async () => {
    api(true); renderPlatform(`/venues/${ids.venue}/product`);
    await screen.findByText("Manager app connection");
    expect(screen.queryByRole("button", { name: "Create Manager linking code" })).not.toBeInTheDocument();
  });
  it("server refusal stays visible and does not claim a code was issued", async () => {
    const mock = api(false, true), user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/product`);
    await user.click(await screen.findByRole("button", { name: "Create Manager linking code" }));
    await waitFor(() => expect(screen.getByText("Link issuance unavailable")).toBeVisible());
    expect(screen.queryByRole("dialog", { name: "Manager linking code" })).not.toBeInTheDocument();
    expect(mock.requests.filter((r) => r.method === "POST" && r.url.pathname.endsWith("/manager-links"))).toHaveLength(1);
  });
});
