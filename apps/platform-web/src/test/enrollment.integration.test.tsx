import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { enrollment, ids, installApi, renderPlatform } from "./platform-test-utils";

const code = "7K2Q-M4XB-9TFR";

describe("POS enrollment", () => {
  it("issues a one-time code, shows it once, and drops it on dismissal", async () => {
    const api = installApi((request) => {
      if (request.url.pathname.endsWith("/enrollments") && request.method === "POST") {
        return { body: { id: enrollment.id, venueId: ids.venue, displayName: "Bar POS", platform: "WINDOWS", expiresAt: enrollment.expiresAt, status: "PENDING", code } };
      }
      return undefined;
    });
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);

    await user.click(await screen.findByRole("button", { name: "Enrol a POS" }));
    const dialog = await screen.findByRole("dialog", { name: "Enrol a POS" });
    await user.type(within(dialog).getAllByRole("textbox")[0], "Bar POS");
    await user.click(screen.getByRole("button", { name: "Create enrollment code" }));

    expect(await screen.findByRole("heading", { name: "Enrollment code" })).toBeVisible();
    expect(screen.getByText(code)).toBeVisible();
    expect(screen.getByText(/Shown once, single use/)).toBeVisible();

    // The POS never supplies a venue — the request body carries no venueId.
    const created = api.requests.find((request) => request.method === "POST" && request.url.pathname.endsWith("/enrollments"));
    expect(created?.body).toMatchObject({ displayName: "Bar POS", platform: "WINDOWS", ttlMinutes: 30 });

    await user.click(screen.getByRole("button", { name: "Done" }));
    expect(screen.queryByText(code)).not.toBeInTheDocument();
  });

  it("shows what happened to each invitation without inventing an online state", async () => {
    installApi((request) => request.url.pathname.endsWith("/enrollments") && request.method === "GET"
      ? { body: [
          { ...enrollment, status: "PENDING" },
          { ...enrollment, id: "bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb", codeSelector: "M4XB", displayName: "Front POS", status: "ENROLLED", redeemedAt: "2026-08-31T10:05:00.000Z", deviceId: ids.device },
          { ...enrollment, id: "cccc3333-cccc-4ccc-8ccc-cccccccccccc", codeSelector: "9TFR", displayName: "Kitchen POS", status: "EXPIRED" },
        ] }
      : undefined);
    renderPlatform(`/admin/venues/${ids.venue}/devices`);

    expect(await screen.findByText("Waiting for enrollment")).toBeVisible();
    expect(screen.getByText("Enrolled")).toBeVisible();
    expect(screen.getByText("Expired")).toBeVisible();
    // Half a code is shown so two live invitations can be told apart; the
    // secret half is not in the payload at all.
    expect(screen.getByText(/7K2Q·····/)).toBeVisible();
  });

  it("cancels an outstanding code and says it is not a delete", async () => {
    const api = installApi((request) => request.url.pathname.endsWith("/enrollments") && request.method === "GET"
      ? { body: [enrollment] }
      : undefined);
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);

    await user.click(await screen.findByRole("button", { name: "Cancel code" }));
    expect((await screen.findAllByText(/Nothing is removed/)).length).toBeGreaterThan(0);
    await user.click(screen.getByRole("button", { name: "Cancel this code" }));
    await waitFor(() => expect(api.requests.some((request) => request.method === "DELETE" && request.url.pathname.endsWith(`/enrollments/${enrollment.id}`))).toBe(true));
  });

  it("polls only while an invitation is outstanding", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      const api = installApi((request) => request.url.pathname.endsWith("/enrollments") && request.method === "GET"
        ? { body: [{ ...enrollment, status: "ENROLLED", redeemedAt: "2026-08-31T10:05:00.000Z" }] }
        : undefined);
      renderPlatform(`/admin/venues/${ids.venue}/devices`);
      await screen.findByText("Enrolled");
      const after = api.requests.filter((request) => request.url.pathname.endsWith("/enrollments")).length;
      await vi.advanceTimersByTimeAsync(20_000);
      expect(api.requests.filter((request) => request.url.pathname.endsWith("/enrollments")).length).toBe(after);
    } finally {
      vi.useRealTimers();
    }
  });

  it("frames revoke as a permanent credential invalidation, not a delete", async () => {
    installApi();
    const user = userEvent.setup();
    renderPlatform(`/admin/venues/${ids.venue}/devices`);
    await screen.findAllByText("Front POS");
    await user.click(screen.getByRole("button", { name: "Revoke" }));
    expect((await screen.findAllByText(/This is not a delete/)).length).toBeGreaterThan(0);
  });
});
