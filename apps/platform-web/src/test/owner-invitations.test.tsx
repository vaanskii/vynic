import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";
import { beforeEach, describe, it, expect, vi } from "vitest";
const api = vi.hoisted(() => ({
  customer: vi.fn(),
  platform: vi.fn(),
  session: vi.fn(() => false),
}));
vi.mock("../customer/api", () => ({
  customerApi: api.customer,
  hasCustomerSession: api.session,
  customerLogout: vi.fn(),
}));
vi.mock("../platform/api", () => ({ platformOnboardingApi: api.platform }));
import { AcceptInvitation } from "../customer/AcceptInvitation";
import { CustomerOnboarding } from "../platform/pages/CustomerOnboarding";
function Landing() {
  const location = useLocation();
  return <p>Existing venue: {location.state.venueId}</p>;
}
function mount() {
  return render(
    <MemoryRouter initialEntries={["/invite"]}>
      <Routes>
        <Route path="/invite" element={<AcceptInvitation />} />
        <Route path="/dashboard" element={<Landing />} />
      </Routes>
    </MemoryRouter>,
  );
}
beforeEach(() => {
  vi.clearAllMocks();
  api.session.mockReturnValue(false);
  window.history.replaceState({}, "", "/invite#token=test-token");
});
describe("Owner invitation journey", () => {
  it("registers through the invitation and lands on the prepared Venue", async () => {
    const user = userEvent.setup();
    api.customer.mockImplementation(async (path: string) =>
      path === "invitations/inspect"
        ? {
            email: "owner@test.invalid",
            organizationName: "Prepared restaurant",
            existingAccount: false,
          }
        : { venueId: "prepared-venue" },
    );
    mount();
    await user.type(await screen.findByLabelText("სახელი"), "Owner");
    await user.type(
      screen.getByLabelText("პაროლი"),
      "Owner-created long password",
    );
    await user.click(screen.getByRole("button", { name: "მოწვევის მიღება" }));
    expect(
      await screen.findByText("Existing venue: prepared-venue"),
    ).toBeInTheDocument();
    expect(api.customer).toHaveBeenCalledWith(
      "invitations/register",
      expect.objectContaining({ token: "test-token" }),
    );
    expect(api.customer).not.toHaveBeenCalledWith(
      "auth/signup",
      expect.anything(),
    );
    expect(window.location.hash).toBe("");
  });
  it("signs an existing owner in before accepting, without creating a second account", async () => {
    const user = userEvent.setup();
    api.customer.mockImplementation(async (path: string) =>
      path === "invitations/inspect"
        ? {
            email: "existing@test.invalid",
            organizationName: "Prepared restaurant",
            existingAccount: true,
          }
        : { venueId: "existing-venue" },
    );
    mount();
    await user.type(
      await screen.findByLabelText("პაროლი"),
      "Existing password",
    );
    expect(screen.queryByLabelText("სახელი")).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "მოწვევის მიღება" }));
    expect(
      await screen.findByText("Existing venue: existing-venue"),
    ).toBeInTheDocument();
    const paths = api.customer.mock.calls.map((c) => c[0]);
    expect(paths).toEqual([
      "invitations/inspect",
      "auth/login",
      "invitations/accept",
    ]);
  });
  it("shows an unusable invitation with a recovery path", async () => {
    api.customer.mockRejectedValue(
      new Error("Invitation is invalid or no longer available"),
    );
    mount();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "no longer available",
    );
    expect(
      screen.queryByRole("button", { name: "მოწვევის მიღება" }),
    ).not.toBeInTheDocument();
    expect(screen.getByText(/მოითხოვეთ ახალი მოწვევა/)).toBeInTheDocument();
  });
  it("provides assisted creation and a copyable one-time link separately from invitation status", async () => {
    const user = userEvent.setup();
    api.platform.mockImplementation(async (path: string) =>
      path === "customers" ? { invitationPath: "/invite#token=new-token" } : [],
    );
    render(
      <MemoryRouter>
        <CustomerOnboarding
          readonly={false}
          plans={[{ id: "plan", name: "Website plan" }]}
        />
      </MemoryRouter>,
    );
    await user.type(screen.getByLabelText("Organization name"), "Organization");
    await user.type(screen.getByLabelText("Restaurant name"), "Restaurant");
    await user.type(screen.getByLabelText("Owner email"), "owner@test.invalid");
    await user.selectOptions(screen.getByLabelText("Plan"), "plan");
    await user.click(
      screen.getByRole("button", { name: "Create restaurant and invitation" }),
    );
    await waitFor(() =>
      expect(
        (screen.getByLabelText("Owner invitation link") as HTMLInputElement)
          .value,
      ).toContain("/invite#token=new-token"),
    );
    await user.click(
      screen.getByRole("button", { name: "Copy invitation link" }),
    );
    expect(await navigator.clipboard.readText()).toContain("#token=new-token");
    expect(api.platform).toHaveBeenCalledWith(
      "customers",
      expect.objectContaining({
        planId: "plan",
        subscriptionStatus: "NO_PLAN",
        trialDays: 14,
      }),
      "POST",
    );
    expect(
      screen.getByRole("heading", { name: "Owner invitations" }),
    ).toBeInTheDocument();
  });
});
