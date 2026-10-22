import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
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
    expect(
      commercialActions("SUSPENDED", false, {
        from: "TRIAL",
        trialExpired: true,
      }).map((a) => a[0]),
    ).toEqual(["EXTEND_TRIAL", "TRIAL", "GRANT_ACTIVE", "CANCEL_NOW"]);
    expect(
      commercialActions("SUSPENDED", false, {
        from: "TRIAL",
        trialExpired: false,
      }).map((a) => a[0]),
    ).toEqual(["RESUME", "TRIAL", "GRANT_ACTIVE", "CANCEL_NOW"]);
    expect(commercialActions("CANCELLED", false).map((a) => a[0])).toEqual([
      "TRIAL",
      "GRANT_ACTIVE",
    ]);
  });
  it("shows a clock time and calculates duration against server time", () => {
    expect(dateTime("2026-09-26T12:55:00Z")).toMatch(/\d{2}:55/);
    expect(
      remaining("2026-09-26T12:55:00Z", Date.parse("2026-09-25T13:41:00Z")),
    ).toBe("23h 14m");
  });
  it.each(["ACTIVE", "TRIAL", "SUSPENDED"])(
    "%s owner contacts support and cannot edit even with an old allowed flag",
    (commercialStatus) => {
      api.mockReset();
      const website = {
        venueId: "v",
        settings: {
          draft: { slug: "stale-draft" },
          hostname: "current.vynic.localhost",
          baseDomain: "vynic.localhost",
          hostnameChangeAllowed: true,
          commercialStatus,
        },
      } as unknown as Website;
      render(<HostnameRequest website={website} />);
      expect(screen.getByText("current.vynic.localhost")).toBeVisible();
      expect(
        screen.getByText(/დაუკავშირდით Vynic-ის მხარდაჭერას/),
      ).toBeVisible();
      expect(screen.queryByText(/stale-draft/)).toBeNull();
      expect(screen.queryByRole("button")).toBeNull();
      expect(screen.queryByRole("textbox")).toBeNull();
      expect(api).not.toHaveBeenCalled();
    },
  );
  it("retains a previous pending request as read-only status", () => {
    api.mockReset();
    const website = {
      settings: {
        hostname: "current.vynic.localhost",
        pendingHostnameRequest: { hostname: "pending.vynic.localhost" },
      },
    } as unknown as Website;
    render(<HostnameRequest website={website} />);
    expect(screen.getByRole("status")).toHaveTextContent(
      "წინა მოთხოვნა განხილვაშია",
    );
    expect(screen.getByRole("status")).toHaveTextContent(
      "pending.vynic.localhost",
    );
    expect(screen.queryByRole("button")).toBeNull();
    expect(api).not.toHaveBeenCalled();
  });
});
