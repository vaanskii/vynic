import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { ids, installApi, renderPlatform, venue } from "./platform-test-utils";

describe("Restaurant Code setup", () => {
  it.each([360, 768, 1280])(
    "Venue code remains copyable with Manager disabled at %ipx",
    async (width) => {
      window.innerWidth = width;
      const user = userEvent.setup();
      const api = installApi();
      renderPlatform(`/admin/venues/${ids.venue}`);
      expect(
        await screen.findByText("მენეჯერის აპლიკაცია გამორთულია"),
      ).toBeVisible();
      expect(screen.getByText(venue.loginCode)).toBeVisible();
      await user.click(screen.getByRole("button", { name: "კოპირება" }));
      expect(await navigator.clipboard.readText()).toBe(venue.loginCode);
      expect(screen.getByRole("status")).toHaveTextContent(
        "კოდი დაკოპირებულია",
      );
      expect(
        screen.queryByRole("button", { name: "Create Manager" }),
      ).not.toBeInTheDocument();
      expect(
        api.requests.some((r) => r.url.pathname.endsWith("/managers")),
      ).toBe(false);
    },
  );
  it("Organization detail shows its Venue's existing code", async () => {
    const user = userEvent.setup();
    installApi();
    renderPlatform(`/admin/organizations/${ids.organization}`);
    expect(
      await screen.findByText("მენეჯერის აპლიკაცია გამორთულია"),
    ).toBeVisible();
    await user.click(screen.getByRole("button", { name: "კოპირება" }));
    expect(await navigator.clipboard.readText()).toBe(venue.loginCode);
  });
});
