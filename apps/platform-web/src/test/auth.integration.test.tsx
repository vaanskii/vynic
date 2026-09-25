import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { platformSession } from "../platform/session";
import { installApi, renderPlatform } from "./platform-test-utils";

describe("platform authentication", () => {
  it("logs in with the real auth contract and redirects to the overview", async () => {
    installApi();
    const user = userEvent.setup();
    renderPlatform("/login", { authenticated: false });

    await user.type(screen.getByLabelText("Email"), "admin@vynic.test");
    await user.type(screen.getByLabelText("Password"), "correct horse battery staple");
    await user.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("heading", { name: "Good control starts with the real state." })).toBeVisible();
    expect(platformSession.read()?.token).toBe("test-token");
  });

  it("shows invalid credentials without creating a session", async () => {
    installApi((request) => request.url.pathname === "/platform/auth/login" ? { status: 401, body: { message: "Invalid credentials" } } : undefined);
    const user = userEvent.setup();
    renderPlatform("/login", { authenticated: false });

    await user.type(screen.getByLabelText("Email"), "wrong@vynic.test");
    await user.type(screen.getByLabelText("Password"), "not-the-password");
    await user.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Invalid credentials");
    expect(platformSession.read()).toBeNull();
  });

  it("restores a stored session only after /platform/auth/me succeeds", async () => {
    const api = installApi();
    renderPlatform("/");
    expect(await screen.findByRole("heading", { name: "Good control starts with the real state." })).toBeVisible();
    expect(api.requests.some((request) => request.url.pathname === "/platform/auth/me")).toBe(true);
  });

  it("protects routes and clears the session when an API read returns 401", async () => {
    let meSucceeded = false;
    installApi((request) => {
      if (request.url.pathname === "/platform/auth/me") { meSucceeded = true; return undefined; }
      if (meSucceeded && request.url.pathname === "/platform/organizations") return { status: 401, body: { message: "Unauthorized" } };
      return undefined;
    });
    renderPlatform("/organizations");
    expect(await screen.findByRole("heading", { name: "Sign in to Platform Admin" })).toBeVisible();
    expect(platformSession.read()).toBeNull();
  });

  it("redirects an anonymous protected route to login", async () => {
    installApi();
    renderPlatform("/venues", { authenticated: false });
    await waitFor(() => expect(screen.getByRole("heading", { name: "Sign in to Platform Admin" })).toBeVisible());
  });
});
