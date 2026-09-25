import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { commercialActions } from "../subscriptions/operator-actions";
import { dateTime, remaining } from "../subscriptions/types";
import { HostnameRequest } from "../customer/HostnameRequest";
import type { Website } from "../customer/useWebsite";
const api = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: api }));
describe("commercial ownership UX", () => {
  it("offers only relevant lifecycle actions", () => {
    expect(commercialActions("NO_PLAN", false).map((a) => a[0])).toEqual([
      "TRIAL",
      "GRANT_ACTIVE",
    ]);
    expect(commercialActions("TRIAL", false).map((a) => a[0])).toEqual([
      "EXTEND_TRIAL",
      "END_TRIAL",
      "GRANT_ACTIVE",
      "SUSPEND",
    ]);
    expect(commercialActions("ACTIVE", true).map((a) => a[0])).not.toContain(
      "TRIAL",
    );
    expect(commercialActions("SUSPENDED", true).map((a) => a[0])).toEqual([
      "RESUME",
      "CANCEL_NOW",
    ]);
  });
  it("shows a clock time and calculates duration against server time", () => {
    expect(dateTime("2026-09-26T12:55:00Z")).toMatch(/\d{2}:55/);
    expect(
      remaining("2026-09-26T12:55:00Z", Date.parse("2026-09-25T13:41:00Z")),
    ).toBe("23h 14m");
  });
  it("paid request shows pending status while the current address remains unchanged", async () => {
    api
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce({
        id: "r",
        status: "PENDING",
        hostname: "new.vynic.localhost",
      });
    const website = {
      venueId: "v",
      settings: {
        draft: { slug: "current" },
        baseDomain: "vynic.localhost",
        hostnameChangeAllowed: true,
        commercialStatus: "ACTIVE",
      },
    } as Website;
    render(<HostnameRequest website={website} />);
    const user = userEvent.setup();
    await user.click(
      await screen.findByRole("button", {
        name: "მისამართის შეცვლის მოთხოვნა",
      }),
    );
    await user.type(
      screen.getByRole("textbox", { name: "სასურველი მისამართი" }),
      "new",
    );
    await user.click(
      screen.getByRole("button", { name: "მოთხოვნის გაგზავნა" }),
    );
    expect(await screen.findByRole("status")).toHaveTextContent("PENDING");
    expect(screen.getByText("current.vynic.localhost")).toBeVisible();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(api).toHaveBeenLastCalledWith("venues/v/website/hostname-requests", {
      slug: "new",
    });
  });
});
