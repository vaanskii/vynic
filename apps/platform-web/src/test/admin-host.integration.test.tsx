import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { isAdminHost, publicSiteUrl, siteOrigins } from "../site-origins";
import {
  installApi,
  renderPlatform,
  renderPublic,
} from "./platform-test-utils";

describe("admin hostname routing", () => {
  it.each(["admin.localhost", "admin.vynic.localhost", "admin.vynic.ge"])(
    "opens operator login at the root of %s",
    async (hostname) => {
      installApi();
      renderPlatform("/", { hostname, authenticated: false });
      expect(
        await screen.findByRole("heading", {
          name: "Sign in to Platform Admin",
        }),
      ).toBeVisible();
      expect(screen.queryByLabelText("ელფოსტა")).toBeNull();
    },
  );

  it("keeps public login separate even with a stored admin session", async () => {
    const api = installApi();
    renderPublic("/login");
    expect(
      await screen.findByRole("heading", { name: "შესვლა" }),
    ).toBeVisible();
    expect(
      api.requests.some((r) => r.url.pathname.startsWith("/platform/")),
    ).toBe(false);
  });

  it.each(["/admin", "/admin/venues?limit=10#details"])(
    "returns public %s to the public home",
    async (path) => {
      const api = installApi();
      renderPublic(path);
      expect(await screen.findByRole("banner")).toBeVisible();
      expect(
        screen.queryByRole("heading", { name: "Sign in to Platform Admin" }),
      ).toBeNull();
      expect(screen.queryByText("Opening Platform Admin…")).toBeNull();
      expect(api.requests).toEqual([]);
    },
  );

  it.each(["/admin", "/admin/plans"])(
    "returns admin-host %s to its root instead of the old destination",
    async (path) => {
      installApi();
      renderPlatform(path);
      expect(
        await screen.findByRole("heading", {
          name: "Good control starts with the real state.",
        }),
      ).toBeVisible();
      expect(screen.queryByRole("heading", { name: "Plans" })).toBeNull();
    },
  );

  it("returns to the requested admin page after login", async () => {
    installApi();
    const user = userEvent.setup();
    renderPlatform("/plans", { authenticated: false });
    await user.type(await screen.findByLabelText("Email"), "admin@vynic.test");
    await user.type(screen.getByLabelText("Password"), "test-password");
    await user.click(screen.getByRole("button", { name: "Sign in" }));
    expect(await screen.findByRole("heading", { name: "Plans" })).toBeVisible();
  });

  it("sends the site link and owner invitations to the public origin", () => {
    vi.stubGlobal("location", {
      hostname: "admin.localhost",
      protocol: "http:",
      port: "5173",
    });
    expect(publicSiteUrl("/invite#token=test-token")).toBe(
      "http://localhost:5173/invite#token=test-token",
    );
    expect(publicSiteUrl()).toBe("http://localhost:5173/");
  });
});

describe("host and destination policy", () => {
  it.each([
    "vynic.ge",
    "localhost",
    "admin.vynic.ge.evil.test",
    "admin.other.test",
  ])("does not mount admin on %s", (hostname) => {
    expect(isAdminHost(hostname)).toBe(false);
  });
  it("maps local ports and production origins explicitly", () => {
    expect(
      siteOrigins({ hostname: "localhost", protocol: "http:", port: "5173" })
        .admin,
    ).toBe("http://admin.localhost:5173");
    expect(
      siteOrigins({
        hostname: "admin.vynic.localhost",
        protocol: "http:",
        port: "4173",
      }).public,
    ).toBe("http://vynic.localhost:4173");
    expect(
      siteOrigins({ hostname: "admin.vynic.ge", protocol: "https:", port: "" })
        .public,
    ).toBe("https://vynic.ge");
  });
});
