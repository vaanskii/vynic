import { screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { actor, ids, installApi, renderPlatform } from "./platform-test-utils";

describe("Phase 2 commercial controls", () => {
  it("creates a Manager, hides PIN after save, resets and disables; subscription requires confirmation", async () => {
    let managers: any[] = [];
    let status = "ACTIVE";
    const api = installApi((req) => {
      if (req.url.pathname.endsWith("/subscription")) {
        if (req.method === "PUT") status = String(req.body?.status);
        return {
          body: {
            status,
            startedAt: null,
            trialEndsAt: null,
            currentPeriodEndsAt: null,
            note: null,
          },
        };
      }
      if (req.url.pathname.includes("/managers")) {
        if (req.method === "GET") return { body: managers };
        managers = [
          {
            id: ids.actor,
            username: "manager",
            displayName: "Nino",
            role: "MANAGER",
            isActive: !req.url.pathname.endsWith("/disable"),
          },
        ];
        return {
          body: {
            staff: managers[0],
            delivery: { commandId: "queued", status: "PENDING" },
          },
        };
      }
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/commercial`);
    await user.click(
      await screen.findByRole("button", { name: "Create Manager" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Create Manager",
    });
    await user.type(within(dialog).getByLabelText("Display name"), "Nino");
    await user.type(within(dialog).getByLabelText("Username"), "manager");
    await user.type(within(dialog).getByLabelText("New PIN"), "483921");
    await user.click(
      within(dialog).getByRole("button", { name: "Save access" }),
    );
    expect(await screen.findByText("Nino")).toBeVisible();
    expect(screen.queryByDisplayValue("483921")).not.toBeInTheDocument();
    await user.click(
      screen.getByRole("button", { name: "Reset PIN / Reactivate" }),
    );
    await user.type(await screen.findByLabelText("New PIN"), "692481");
    await user.click(screen.getByRole("button", { name: "Save access" }));
    await waitFor(() =>
      expect(screen.queryByLabelText("New PIN")).not.toBeInTheDocument(),
    );
    await user.click(screen.getByRole("button", { name: "Disable access" }));
    await user.click(
      await screen.findByRole("button", { name: "Save access" }),
    );
    await waitFor(() =>
      expect(
        api.requests.some((r) => r.url.pathname.endsWith("/disable")),
      ).toBe(true),
    );
    await user.click(screen.getByRole("button", { name: "Suspend" }));
    expect(api.requests.filter((r) => r.method === "PUT")).toHaveLength(0);
    await user.click(
      await screen.findByRole("button", { name: "Update subscription" }),
    );
    expect(await screen.findByText("SUSPENDED")).toBeVisible();
  });
  it("shows support read access without commercial mutation controls", async () => {
    installApi((req) => {
      if (req.url.pathname.endsWith("/auth/me"))
        return { body: { ...actor, role: "SUPPORT_READONLY" } };
      if (req.url.pathname.endsWith("/subscription"))
        return { body: { status: "ACTIVE" } };
      if (req.url.pathname.endsWith("/managers")) return { body: [] };
      return undefined;
    });
    renderPlatform(`/admin/venues/${ids.venue}/commercial`);
    expect(await screen.findByText("No Manager accounts yet.")).toBeVisible();
    expect(
      screen.queryByRole("button", { name: "Create Manager" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Suspend" }),
    ).not.toBeInTheDocument();
  });
});
