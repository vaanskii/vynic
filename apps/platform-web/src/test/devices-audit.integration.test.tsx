import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { device, ids, installApi, renderPlatform } from "./platform-test-utils";

const initialCredential = `vynic-device-v1.${ids.device}.${"a".repeat(40)}`;
const rotatedCredential = `vynic-device-v1.${ids.device}.${"b".repeat(40)}`;

describe("device lifecycle and audit", () => {
  it("handles create, one-time dismissal, rotation, revoke, and NOOP queueing", async () => {
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/devices") && request.method === "POST") return { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: initialCredential } };
      if (request.url.pathname.endsWith(`/devices/${ids.device}/credential`)) return { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: rotatedCredential } };
      if (request.url.pathname.endsWith(`/devices/${ids.device}/status`)) return { body: { ...device, status: request.body?.status } };
      if (request.url.pathname.endsWith("/test-command")) return { body: { commandId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", status: "PENDING", idempotencyKey: "safe-key" } };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/devices`);
    expect((await screen.findAllByText("Front POS")).length).toBeGreaterThan(0);

    await user.click(screen.getByRole("button", { name: "Add POS device" }));
    const createDialog = await screen.findByRole("dialog", { name: "Add POS device" });
    await user.type(within(createDialog).getAllByRole("textbox")[0], "Bar POS");
    await user.click(screen.getByRole("button", { name: "Create device" }));
    expect(await screen.findByRole("heading", { name: "Device credential issued" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Reveal credential" }));
    expect(screen.getByText(initialCredential)).toBeVisible();
    await user.click(screen.getByRole("button", { name: "I saved the credential" }));
    expect(screen.queryByText(initialCredential)).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Rotate credential" }));
    expect((await screen.findAllByText(/current POS credential will immediately stop working/i)).length).toBeGreaterThan(0);
    await user.click(screen.getByRole("button", { name: "Rotate and issue new credential" }));
    expect(await screen.findByRole("heading", { name: "Device credential issued" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Reveal credential" }));
    expect(screen.getByText(rotatedCredential)).toBeVisible();
    await user.click(screen.getByRole("button", { name: "I saved the credential" }));

    await user.click(screen.getByRole("button", { name: "Revoke" }));
    expect((await screen.findAllByText(/credential will stop authenticating immediately/i)).length).toBeGreaterThan(0);
    await user.click(screen.getByRole("button", { name: "Change device status" }));
    await waitFor(() => expect(api.requests.some((request) => request.url.pathname.endsWith("/status") && request.body?.status === "REVOKED")).toBe(true));

    await user.click(screen.getByRole("button", { name: "Send connection test" }));
    expect(await screen.findByText("Command queued")).toBeVisible();
    expect(screen.getByText(/Execution is not proven/i)).toBeVisible();
  });

  it("downloads the exact one-line POS provisioning file", async () => {
    const createObjectURL = vi.fn<(blob: Blob) => string>(() => "blob:test");
    const revokeObjectURL = vi.fn();
    vi.stubGlobal("URL", Object.assign(URL, { createObjectURL, revokeObjectURL }));
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => undefined);
    installApi((request) => request.url.pathname.endsWith("/devices") && request.method === "POST" ? { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: initialCredential } } : undefined);
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/devices`);
    await screen.findAllByText("Front POS");
    await user.click(screen.getByRole("button", { name: "Add POS device" }));
    const createDialog = await screen.findByRole("dialog", { name: "Add POS device" });
    await user.type(within(createDialog).getAllByRole("textbox")[0], "Bar POS");
    await user.click(screen.getByRole("button", { name: "Create device" }));
    await user.click(await screen.findByRole("button", { name: "Download provisioning file" }));
    expect(createObjectURL).toHaveBeenCalledTimes(1);
    const blob = createObjectURL.mock.calls[0][0] as Blob;
    expect(await blob.text()).toBe(`${initialCredential}\n`);
    expect(click).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:test");
  });

  it("loads the platform audit trail", async () => {
    installApi();
    renderPlatform("/audit");
    expect(await screen.findByText("Venue Plan Assigned")).toBeVisible();
    expect(screen.getAllByText("Platform Admin").length).toBeGreaterThan(0);
    expect(screen.getByText(/FULL/)).toBeVisible();
  });
});
