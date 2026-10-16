import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { enrollment, ids, installApi, renderPlatform } from "./platform-test-utils";

describe("single-code first Manager setup", () => {
  it.each([
    { eligible: true, additional: false, granted: true },
    { eligible: true, additional: true, granted: false },
    { eligible: false, additional: false, granted: false },
  ])("enrollment privilege follows eligibility and the operator's choice ($eligible/$additional)", async ({ eligible, additional, granted }) => {
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/initial-manager-setup"))
        return { body: { eligible } };
      if (request.url.pathname.endsWith("/enrollments") && request.method === "POST")
        return { body: { ...enrollment, code: "synthetic-once", initialManagerSetup: granted } };
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/devices`);
    await user.click(await screen.findByRole("button", { name: "Enrol a POS" }));
    const dialog = await screen.findByRole("dialog", { name: "Enrol a POS" });
    await user.type(within(dialog).getByRole("textbox", { name: /^Terminal name/ }), "Front POS");
    if (eligible) {
      const checkbox = await within(dialog).findByRole("checkbox", { name: /Include first Manager/ });
      expect(checkbox).toBeChecked();
      if (additional) await user.click(checkbox);
    } else {
      expect(within(dialog).queryByRole("checkbox")).not.toBeInTheDocument();
    }
    const submit = within(dialog).getByRole("button", { name: "Create enrollment code" });
    await waitFor(() => expect(submit).toBeEnabled());
    await user.click(submit);
    const codeDialog = await screen.findByRole("dialog", { name: "Enrollment code" });
    const created = api.requests.find((r) => r.method === "POST" && r.url.pathname.endsWith("/enrollments"));
    expect(created?.body).toEqual({ displayName: "Front POS", platform: "WINDOWS", ttlMinutes: 30, initialManagerSetup: granted });
    if (granted) expect(within(codeDialog).getByText(/No second activation code is needed/)).toBeVisible();
    else expect(within(codeDialog).queryByText(/No second activation code is needed/)).not.toBeInTheDocument();
    expect(api.requests.some((r) => r.method === "POST" && r.url.pathname.endsWith("/manager-activation"))).toBe(false);
  });

  it("does not issue an ordinary code while eligibility has failed; retry restores the explicit choice", async () => {
    let available = false;
    const api = installApi((request) => request.url.pathname.endsWith("/initial-manager-setup")
      ? available ? { body: { eligible: true } } : { status: 503, body: { message: "Setup eligibility unavailable" } }
      : undefined);
    const user = userEvent.setup();
    renderPlatform(`/venues/${ids.venue}/devices`);
    await user.click(await screen.findByRole("button", { name: "Enrol a POS" }));
    const dialog = await screen.findByRole("dialog", { name: "Enrol a POS" });
    expect(await within(dialog).findByText("Setup eligibility unavailable")).toBeVisible();
    expect(within(dialog).getByRole("button", { name: "Create enrollment code" })).toBeDisabled();
    expect(api.requests.some((r) => r.method === "POST" && r.url.pathname.endsWith("/enrollments"))).toBe(false);
    available = true;
    await user.click(within(dialog).getByRole("button", { name: /Retry/ }));
    expect(await within(dialog).findByRole("checkbox", { name: /Include first Manager/ })).toBeChecked();
    expect(within(dialog).getByRole("button", { name: "Create enrollment code" })).toBeEnabled();
  });
});
