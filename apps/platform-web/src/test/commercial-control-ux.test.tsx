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
    api.mockReset().mockImplementation((path: string, body?: unknown) => {
      if (path.includes("/address/"))
        return Promise.resolve({ valid: true, available: true });
      if (body)
        return Promise.resolve({
          id: "r",
          status: "PENDING",
          hostname: "new.vynic.localhost",
          currentHostname: "current.vynic.localhost",
        });
      if (path.endsWith("/website")) return Promise.resolve({});
      return Promise.resolve([
        {
          id: "old",
          status: "REJECTED",
          hostname: "taken.vynic.localhost",
          reason: "Trademark",
        },
      ]);
    });
    const website = {
      venueId: "v",
      dirty: true,
      load: vi.fn(),
      settings: {
        draft: { slug: "stale-draft" },
        hostname: "current.vynic.localhost",
        baseDomain: "vynic.localhost",
        hostnameChangeAllowed: true,
        commercialStatus: "ACTIVE",
      },
    } as unknown as Website;
    render(<HostnameRequest website={website} />);
    const user = userEvent.setup();
    expect(
      await screen.findByText(
        /taken\.vynic\.localhost.*უარყოფილია — Trademark/,
      ),
    ).toBeVisible();
    await user.click(
      await screen.findByRole("button", {
        name: "მისამართის შეცვლის მოთხოვნა",
      }),
    );
    await user.type(
      screen.getByRole("textbox", { name: "სასურველი მისამართი" }),
      "New Name",
    );
    expect(await screen.findByText("ამჟამად თავისუფალია")).toBeVisible();
    await user.click(
      screen.getByRole("button", { name: "მოთხოვნის გაგზავნა" }),
    );
    const status = await screen.findByRole("status");
    expect(status).toHaveTextContent("მისამართის შეცვლის მოთხოვნა გაგზავნილია");
    expect(status).toHaveTextContent(
      "მოთხოვნილი მისამართი: new.vynic.localhost",
    );
    expect(status).toHaveTextContent("სტატუსი: განხილვაშია");
    // The server-owned address is shown, never the draft's copy of it.
    expect(screen.getByText("current.vynic.localhost")).toBeVisible();
    expect(screen.queryByText(/stale-draft/)).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(
      screen.queryByRole("button", { name: "მისამართის შეცვლის მოთხოვნა" }),
    ).toBeNull();
    expect(api).toHaveBeenCalledWith("venues/v/website/hostname-requests", {
      slug: "newname",
    });
    // Unsaved draft edits are not discarded by a settings reload.
    expect(website.load).not.toHaveBeenCalled();
  });
  it("trial shows the assigned address read-only with no change request", async () => {
    api.mockReset();
    const website = {
      venueId: "v",
      settings: {
        draft: { slug: "restaurantvankisi" },
        hostname: "restaurantvankisi.vynic.localhost",
        baseDomain: "vynic.localhost",
        hostnameChangeAllowed: false,
        commercialStatus: "TRIAL",
      },
    } as unknown as Website;
    render(<HostnameRequest website={website} />);
    expect(screen.getByText("თქვენი ვებსაიტის მისამართი")).toBeVisible();
    expect(screen.getByText("restaurantvankisi.vynic.localhost")).toBeVisible();
    expect(
      screen.getByText(
        /საცდელი პერიოდის განმავლობაში მისამართის შეცვლა შეუძლებელია/,
      ),
    ).toBeVisible();
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(api).not.toHaveBeenCalled();
  });
});
