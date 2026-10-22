import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { WebsitePaymentReviews } from "../customer/WebsitePaymentReviews";
import { WebsitePaymentReviewsPanel } from "../platform/pages/venue/WebsitePaymentReviewsPanel";
import { platformApi } from "../platform/api";
const ownerRead = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: ownerRead }));
const row = {
  bookingId: "synthetic-booking",
  date: "2030-01-01",
  timeSlot: "18:00",
  bookingStatus: "FAILED",
  paymentState: "PAID",
  expectedMinor: "1100",
  grossPaidMinor: "1100",
  refundedMinor: "200",
  currency: "GEL",
  reason: "payment_timing_unproven",
  paymentId: "synthetic-bank",
  holdState: "EXPIRED",
  holdExpiresAt: null,
};
const page = {
  items: [row],
  total: 26,
  offset: 0,
  limit: 25,
  financialDecisionOwner: "RESTAURANT_OWNER" as const,
};
function platform() {
  return render(
    <QueryClientProvider
      client={
        new QueryClient({ defaultOptions: { queries: { retry: false } } })
      }
    >
      <WebsitePaymentReviewsPanel venueId="venue-a" />
    </QueryClientProvider>,
  );
}
describe("WEB-01/04 financial review", () => {
  it("owner sees exact money, booking outcome and decision ownership with read-only GETs", async () => {
    ownerRead.mockResolvedValue(page);
    render(<WebsitePaymentReviews venueId="venue-a" />);
    expect(
      await screen.findByText(/11.00 GEL \/ 11.00 GEL \/ 2.00 GEL/),
    ).toBeVisible();
    expect(screen.getByText(/FAILED · PAID/)).toBeVisible();
    expect(
      screen.getByText(/ფინანსურ გამონაკლისს რესტორნის მფლობელი წყვეტს/),
    ).toBeVisible();
    expect(screen.getByText("გადახდის დრო გადასამოწმებელია")).toBeVisible();
    expect(
      screen.queryByRole("button", { name: /refund|აღდგენა|დაბრუნება/ }),
    ).toBeNull();
    expect(ownerRead).toHaveBeenCalledWith(
      "venues/venue-a/website-payment-reviews?offset=0",
    );
    await userEvent.click(screen.getByRole("button", { name: "შემდეგი" }));
    expect(ownerRead).toHaveBeenLastCalledWith(
      "venues/venue-a/website-payment-reviews?offset=25",
    );
  });
  it("owner read failure is visible and refresh retries evidence", async () => {
    ownerRead
      .mockRejectedValueOnce(new Error("Synthetic read unavailable"))
      .mockResolvedValue({ ...page, items: [], total: 0 });
    render(<WebsitePaymentReviews venueId="venue-a" />);
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Synthetic read unavailable",
    );
    await userEvent.click(screen.getByRole("button", { name: "განახლება" }));
    expect(
      await screen.findByText("გადასამოწმებელი გადახდა არ არის."),
    ).toBeVisible();
  });
  it("owner loading and unknown historical amounts are explicit", async () => {
    ownerRead.mockResolvedValue({
      ...page,
      items: [
        {
          ...row,
          expectedMinor: null,
          grossPaidMinor: null,
          refundedMinor: null,
          currency: null,
          reason: "historical_payment_snapshot_missing",
        },
      ],
    });
    render(<WebsitePaymentReviews venueId="venue-b" />);
    expect(screen.getByRole("status")).toHaveTextContent("იტვირთება");
    expect(
      await screen.findByText("უცნობია / უცნობია / უცნობია"),
    ).toBeVisible();
    expect(
      screen.getByText("ისტორიული გადახდა გადასამოწმებელია"),
    ).toBeVisible();
  });
  it("Platform shows exact currency amounts and only refresh/pagination", async () => {
    const read = vi
      .spyOn(platformApi, "websitePaymentReviews")
      .mockResolvedValue(page);
    platform();
    expect(
      await screen.findByText(/11.00 GEL \/ 11.00 GEL \/ 2.00 GEL/),
    ).toBeVisible();
    expect(
      screen.getByText(/restaurant owner decides financial exceptions/),
    ).toBeVisible();
    expect(screen.queryByText(/minor units/)).toBeNull();
    expect(
      screen.queryByRole("button", { name: /refund|restore/i }),
    ).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(read).toHaveBeenLastCalledWith("venue-a", 25);
  });
  it("Platform empty and loading states are explicit", async () => {
    vi.spyOn(platformApi, "websitePaymentReviews").mockResolvedValue({
      ...page,
      items: [],
      total: 0,
    });
    platform();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeDisabled();
    expect(
      await screen.findByText("No unresolved booking payments"),
    ).toBeVisible();
  });
  it("Platform error and retry cannot become financial mutation", async () => {
    const read = vi
      .spyOn(platformApi, "websitePaymentReviews")
      .mockRejectedValueOnce(new Error("Synthetic review failure"))
      .mockResolvedValue({ ...page, items: [], total: 0 });
    platform();
    expect(await screen.findByText("Synthetic review failure")).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(
      await screen.findByText("No unresolved booking payments"),
    ).toBeVisible();
    expect(read).toHaveBeenCalledTimes(2);
  });
});
