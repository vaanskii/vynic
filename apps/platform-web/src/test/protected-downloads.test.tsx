import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import { configurePlatformApi } from "../platform/api";
import { ProtectedInstallerDownloads } from "../customer/ProtectedInstallerDownloads";

beforeEach(() => {
  configurePlatformApi({
    token: () => "synthetic-admin-only",
    onUnauthorized: vi.fn(),
  });
});

it("issues and revokes an Admin link through the POST endpoints", async () => {
  const user = userEvent.setup();
  const requests: Array<{ path: string; method: string }> = [];
  const grant = {
    id: "synthetic-grant",
    expiresAt: new Date(Date.now() + 900000).toISOString(),
    revokedAt: null,
  };
  let active = false;
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? "GET";
      requests.push({ path: url, method });
      let body: unknown = { available: true, grants: active ? [grant] : [] };
      let status = 200;
      if (method === "POST" && url.endsWith("/downloads")) {
        active = true;
        body = {
          grant,
          downloadUrl:
            "https://releases.vynic.ge/windows/access/synthetic-grant#token=synthetic-download-capability",
        };
      } else if (method === "POST" && url.endsWith("/synthetic-grant/revoke")) {
        active = false;
        body = { revoked: true };
      } else if (method !== "GET") {
        status = 405;
        body = { message: "Unsupported method" };
      }
      return new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    }),
  );
  render(<ProtectedInstallerDownloads admin />);
  await waitFor(() =>
    expect(
      screen.getByRole("button", { name: "Create download link" }),
    ).toBeEnabled(),
  );
  await user.click(
    screen.getByRole("button", { name: "Create download link" }),
  );
  expect(
    await screen.findByRole("link", { name: "Open download" }),
  ).toHaveAttribute(
    "href",
    expect.stringContaining(
      "https://releases.vynic.ge/windows/access/synthetic-grant#token=synthetic-download-capability",
    ),
  );
  await user.click(screen.getByRole("button", { name: "Revoke link" }));
  await waitFor(() =>
    expect(screen.queryByRole("link", { name: "Open download" })).toBeNull(),
  );
  expect(requests).toContainEqual({
    path: "/platform/onboarding/downloads",
    method: "POST",
  });
  expect(requests).toContainEqual({
    path: "/platform/onboarding/downloads/synthetic-grant/revoke",
    method: "POST",
  });
});

it("keeps read-only Admin users from issuing or revoking capabilities", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn(
      async () =>
        new Response(JSON.stringify({ available: true, grants: [] }), {
          status: 200,
        }),
    ),
  );
  render(<ProtectedInstallerDownloads admin readonly />);
  await screen.findByRole("heading", { name: "Protected Windows installer" });
  expect(
    screen.queryByRole("button", { name: "Create download link" }),
  ).toBeNull();
});
