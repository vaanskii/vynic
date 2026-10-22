import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { platformApi } from "../platform/api";
import { WebsiteDeliveriesPanel } from "../platform/pages/venue/WebsiteDeliveriesPanel";
import type { WebsiteDeliveryPage } from "../platform/types";

const page = (states: string[]): WebsiteDeliveryPage => ({
  offset: 0,
  limit: 25,
  total: states.length,
  primarySelected: true,
  items: states.map((status, i) => ({
    id: `booking-${i}`,
    date: "2035-01-01",
    timeSlot: "18:00",
    bookingStatus: "CONFIRMED",
    posReservationId: `pos-${i}`,
    tracking: status === "UNTRACKED" ? "UNTRACKED" : "TRACKED",
    deliveries:
      status === "UNTRACKED"
        ? []
        : [
            {
              kind: "CREATE",
              status,
              code: null,
              attempts: 1,
              posReservationId: `pos-${i}`,
              commandId: `command-${i}`,
              transport: "edge",
            },
          ],
  })),
});
function show(venueId = "venue-a") {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <WebsiteDeliveriesPanel venueId={venueId} />
    </QueryClientProvider>,
  );
}

describe("read-only Website POS delivery evidence", () => {
  it("distinguishes queue, lease, ACK, failure, unknown and historical evidence without a replay action", async () => {
    vi.spyOn(platformApi, "websiteDeliveries").mockResolvedValue(
      page([
        "PENDING",
        "QUEUED",
        "CLAIMED",
        "SUCCEEDED",
        "FAILED",
        "UNKNOWN",
        "ATTENTION",
        "DELIVERED_LEGACY",
        "UNTRACKED",
      ]),
    );
    show();
    for (const label of [
      "Waiting for queue",
      "Queued · awaiting POS",
      "Claimed · awaiting POS result",
      "POS acknowledged",
      "Failed · reconcile with POS",
      "Outcome unknown · reconcile with POS",
      "Needs operator review",
      "Accepted by legacy POS",
      "Historical creation untracked",
    ])
      expect(await screen.findByText(new RegExp(label))).toBeVisible();
    expect(
      screen.queryByRole("button", {
        name: /retry booking|replay|refund|cancel|send/i,
      }),
    ).toBeNull();
    expect(screen.getByRole("table")).toBeVisible();
  });
  it("shows loading before the first result", () => {
    vi.spyOn(platformApi, "websiteDeliveries").mockReturnValue(
      new Promise(() => {}),
    );
    show();
    expect(screen.getByText(/Loading POS deliveries/)).toBeVisible();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeDisabled();
  });
  it("shows the empty state and disabled page controls", async () => {
    vi.spyOn(platformApi, "websiteDeliveries").mockResolvedValue(page([]));
    show();
    expect(await screen.findByText("No website deliveries")).toBeVisible();
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();
  });
  it("makes read failures visible and Retry only refreshes evidence", async () => {
    const read = vi
      .spyOn(platformApi, "websiteDeliveries")
      .mockRejectedValueOnce(new Error("Read unavailable"))
      .mockResolvedValue(page([]));
    show();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Read unavailable",
    );
    await userEvent
      .setup()
      .click(screen.getByRole("button", { name: "Retry" }));
    expect(await screen.findByText("No website deliveries")).toBeVisible();
    expect(read).toHaveBeenCalledTimes(2);
  });
  it("uses venue-scoped pagination and refresh without any write", async () => {
    const read = vi
      .spyOn(platformApi, "websiteDeliveries")
      .mockImplementation((_, offset = 0) =>
        Promise.resolve({ ...page(["QUEUED"]), total: 26, offset }),
      );
    show("venue-b");
    await screen.findByText(/Queued · awaiting POS/);
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "Next" }));
    await waitFor(() => expect(read).toHaveBeenCalledWith("venue-b", 25));
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Refresh" })).toBeEnabled(),
    );
    await user.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() => expect(read).toHaveBeenCalledTimes(3));
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();
  });
  it("explains queued work when no Primary POS is selected", async () => {
    vi.spyOn(platformApi, "websiteDeliveries").mockResolvedValue({
      ...page(["QUEUED"]),
      primarySelected: false,
    });
    show();
    expect(await screen.findByText(/No Primary POS selected/)).toBeVisible();
    expect(screen.getByText(/Queued · awaiting POS/)).toBeVisible();
  });
});
