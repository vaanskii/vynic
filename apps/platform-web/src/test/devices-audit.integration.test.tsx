import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { device, ids, installApi, renderPlatform } from "./platform-test-utils";

const initialCredential = `vynic-device-v1.${ids.device}.${"a".repeat(40)}`;
const rotatedCredential = `vynic-device-v1.${ids.device}.${"b".repeat(40)}`;

describe("device lifecycle and audit", () => {
  it("handles manual credential issuance, one-time dismissal, rotation, revoke, and NOOP queueing", async () => {
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/devices") && request.method === "POST") return { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: initialCredential } };
      if (request.url.pathname.endsWith(`/devices/${ids.device}/credential`)) return { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: rotatedCredential } };
      if (request.url.pathname.endsWith(`/devices/${ids.device}/status`)) return { body: { ...device, status: request.body?.status } };
      if (request.url.pathname.endsWith("/test-command")) return { body: { commandId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", status: "PENDING", idempotencyKey: "safe-key" } };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);
    expect((await screen.findAllByText("Front POS")).length).toBeGreaterThan(0);

    await user.click(screen.getByRole("button", { name: "Issue credential manually" }));
    const createDialog = await screen.findByRole("dialog", { name: "Issue a credential manually" });
    await user.type(within(createDialog).getAllByRole("textbox")[0], "Bar POS");
    await user.click(screen.getByRole("button", { name: "Issue credential" }));
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
    expect((await screen.findAllByText(/This is not a delete/i)).length).toBeGreaterThan(0);
    await user.click(screen.getByRole("button", { name: "Change device status" }));
    await waitFor(() => expect(api.requests.some((request) => request.url.pathname.endsWith("/status") && request.body?.status === "REVOKED")).toBe(true));

    await user.click(screen.getByRole("button", { name: "Send connection test" }));
    expect(await screen.findByText("Command queued")).toBeVisible();
    expect(screen.getByText(/Execution is not proven/i)).toBeVisible();
    await waitFor(() => expect(api.requests.some((request) => request.url.pathname.includes("/test-command/") && request.method === "GET")).toBe(true));
  });

  it("downloads the exact one-line POS provisioning file", async () => {
    const createObjectURL = vi.fn<(blob: Blob) => string>(() => "blob:test");
    const revokeObjectURL = vi.fn();
    vi.stubGlobal("URL", Object.assign(URL, { createObjectURL, revokeObjectURL }));
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => undefined);
    installApi((request) => request.url.pathname.endsWith("/devices") && request.method === "POST" ? { body: { device: { id: ids.device, venueId: ids.venue, installationId: device.installationId }, credential: initialCredential } } : undefined);
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);
    await screen.findAllByText("Front POS");
    await user.click(screen.getByRole("button", { name: "Issue credential manually" }));
    const createDialog = await screen.findByRole("dialog", { name: "Issue a credential manually" });
    await user.type(within(createDialog).getAllByRole("textbox")[0], "Bar POS");
    await user.click(screen.getByRole("button", { name: "Issue credential" }));
    await user.click(await screen.findByRole("button", { name: "Download provisioning file" }));
    expect(createObjectURL).toHaveBeenCalledTimes(1);
    const blob = createObjectURL.mock.calls[0][0] as Blob;
    expect(await blob.text()).toBe(`${initialCredential}\n`);
    expect(click).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:test");
  });

  it("loads the platform audit trail", async () => {
    installApi();
    renderPlatform("/admin/audit");
    expect(await screen.findByText("Venue Plan Assigned")).toBeVisible();
    expect(screen.getAllByText("Platform Admin").length).toBeGreaterThan(0);
    expect(screen.getByText(/FULL/)).toBeVisible();
  });
});

describe("Primary POS containment", () => {
  it("labels secondary devices and confirms replacement with the observed primary", async () => {
    const primary = {
      ...device,
      isOperationalPrimary: true,
      activeOperationalDeviceId: ids.device,
    };
    const secondary = {
      ...device,
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      displayName: "Replacement POS",
      isOperationalPrimary: false,
      activeOperationalDeviceId: ids.device,
    };
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/devices") && request.method === "GET")
        return { body: [primary, secondary] };
      if (request.url.pathname.endsWith("/operational-primary"))
        return { body: { activeOperationalDeviceId: secondary.id } };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);
    expect(
      await screen.findByText("Primary POS", { selector: "small" }),
    ).toBeVisible();
    expect(
      screen.getByText("Secondary — operational sync inactive"),
    ).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Make Primary POS" }));
    const dialog = await screen.findByRole("dialog", {
      name: "Make Replacement POS the Primary POS?",
    });
    expect(
      within(dialog).getAllByText(/previous POS has stopped/)[0],
    ).toBeVisible();
    expect(
      api.requests.filter((r) =>
        r.url.pathname.endsWith("/operational-primary"),
      ),
    ).toHaveLength(0);
    await user.click(
      within(dialog).getByRole("button", {
        name: "Previous POS stopped — switch primary",
      }),
    );
    await waitFor(() =>
      expect(
        api.requests.find((r) =>
          r.url.pathname.endsWith("/operational-primary"),
        )?.body,
      ).toMatchObject({
        deviceId: secondary.id,
        expectedDeviceId: ids.device,
        previousPosStopped: true,
      }),
    );
  });
  it("shows that an ambiguous venue needs a primary selection", async () => {
    installApi((request) =>
      request.url.pathname.endsWith("/devices")
        ? {
            body: [
              {
                ...device,
                isOperationalPrimary: false,
                activeOperationalDeviceId: null,
              },
            ],
          }
        : undefined,
    );
    renderPlatform(`/admin/venues/${ids.venue}/devices`);
    expect(await screen.findByText(/Primary POS not selected/)).toBeVisible();
  });
});
