import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { Button } from "../platform/components/Button";
import { device, ids, installApi, product, renderPlatform } from "./platform-test-utils";

describe("Access action feedback", () => {
  it("announces a busy button and prevents repeated actions", async () => {
    const click = vi.fn();
    const view = render(<Button loading loadingLabel="Saving…" onClick={click}>Save</Button>);
    const button = screen.getByRole("button", { name: "Saving…" });
    expect(button).toHaveAttribute("aria-busy", "true");
    expect(button).toBeDisabled();
    await userEvent.click(button);
    expect(click).not.toHaveBeenCalled();
    view.rerender(<Button onClick={click}>Save</Button>);
    await userEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(click).toHaveBeenCalledTimes(1);
  });

  it("shows pending PIN delivery to the selected Primary, without switching authority", async () => {
    const api = installApi((req) => {
      if (req.url.pathname.endsWith("/product")) return { body: { ...product, effectiveFeatures: ["POS", "MANAGER_APP"] } };
      if (req.url.pathname.endsWith("/subscription")) return { body: { status: "ACTIVE" } };
      if (req.url.pathname.endsWith("/managers")) return { body: [{ id: ids.actor, username: "giorgi", displayName: "Giorgi", role: "MANAGER", isActive: true, delivery: { id: "command", status: "PENDING", resultCode: null } }] };
      if (req.url.pathname.endsWith("/devices")) return { body: [
        { ...device, displayName: "Old POS", isOperationalPrimary: true },
        { ...device, id: ids.actor, displayName: "New POS", isOperationalPrimary: false },
      ] };
    });
    renderPlatform(`/admin/venues/${ids.venue}/commercial`);
    expect(await screen.findByText(/Primary: Old POS/)).toBeVisible();
    expect(screen.getByText("POS: Waiting for Primary POS")).toBeVisible();
    expect(screen.getByRole("link", { name: "Review POS devices" })).toHaveAttribute("href", `/admin/venues/${ids.venue}/devices`);
    expect(api.requests.every((req) => req.method === "GET")).toBe(true);
  });

  it("keeps the Manager save visibly busy, prevents dismissal and permits retry after failure", async () => {
    let finish!: () => void;
    const saving = new Promise<void>((resolve) => { finish = resolve; });
    const api = installApi(async (req) => {
      if (req.url.pathname.endsWith("/product")) return { body: { ...product, effectiveFeatures: ["POS", "MANAGER_APP"] } };
      if (req.url.pathname.endsWith("/subscription")) return { body: { status: "ACTIVE" } };
      if (req.url.pathname.includes("/managers")) {
        if (req.method === "GET") return { body: [] };
        await saving;
        return { status: 503, body: { message: "Service unavailable" } };
      }
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/commercial`);
    await user.click(await screen.findByRole("button", { name: "Create Manager" }));
    const dialog = screen.getByRole("dialog", { name: "Create Manager" });
    await user.type(within(dialog).getByLabelText("Display name"), "Giorgi");
    await user.type(within(dialog).getByLabelText("Username"), "giorgi");
    await user.type(within(dialog).getByLabelText("New PIN"), "483921");
    await user.click(within(dialog).getByRole("button", { name: "Save access" }));
    const pending = await screen.findByRole("button", { name: "Saving access…" });
    expect(pending).toHaveAttribute("aria-busy", "true");
    await user.click(pending);
    await user.keyboard("{Escape}");
    expect(dialog).toBeVisible();
    expect(within(dialog).getByRole("button", { name: "Cancel" })).toBeDisabled();
    expect(api.requests.filter((req) => req.method === "POST")).toHaveLength(1);
    await act(async () => finish());
    expect(await screen.findByText("Service unavailable")).toBeVisible();
    expect(screen.getByRole("button", { name: "Save access" })).toBeEnabled();
  });
});
