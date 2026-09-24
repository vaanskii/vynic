import { MemoryRouter, Route, Routes } from "react-router-dom";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, it, expect, vi } from "vitest";
const api = vi.hoisted(() => ({ call: vi.fn(), session: vi.fn(() => false) }));
vi.mock("../customer/api", () => ({
  customerApi: api.call,
  hasCustomerSession: api.session,
  customerLogout: vi.fn(),
}));
import { CustomerAuthPage } from "../customer/CustomerAuthPage";
import { CustomerDashboard, PrinterForm } from "../customer/CustomerDashboard";
beforeEach(() => {
  api.call.mockReset();
  api.session.mockReturnValue(false);
});
describe("Customer onboarding", () => {
  it.each([360, 768, 1280])(
    "requests access without a password or automatic session at %ipx",
    async (width) => {
      window.innerWidth = width;
      const user = userEvent.setup();
      api.call.mockImplementation(async (path: string) =>
        path === "access-requests/plans" ? [] : { received: true },
      );
      render(
        <MemoryRouter>
          <CustomerAuthPage mode="signup" />
        </MemoryRouter>,
      );
      await user.type(screen.getByLabelText("თქვენი სახელი"), "Owner");
      await user.type(
        screen.getByLabelText("რესტორნის / ბიზნესის სახელი"),
        "Restaurant",
      );
      await user.type(screen.getByLabelText("ელფოსტა"), "owner@test.invalid");
      await user.type(screen.getByLabelText("ტელეფონი"), "555123456");
      expect(screen.queryByLabelText("პაროლი")).toBeNull();
      await user.click(
        screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
      );
      expect(await screen.findByText("განაცხადი მიღებულია")).toBeVisible();
      expect(api.call).toHaveBeenCalledWith(
        "access-requests",
        expect.objectContaining({
          applicantName: "Owner",
          businessName: "Restaurant",
        }),
      );
      expect(
        api.call.mock.calls.some(
          (c) => c[0] === "auth/signup" || c[0] === "venues",
        ),
      ).toBe(false);
    },
  );
  it.each([
    "website",
    "menu",
    "photos",
    "hours",
    "payments",
    "managers",
    "devices",
  ])("NO_PLAN hides paid forms on direct %s routes", async (section) => {
    api.session.mockReturnValue(true);
    api.call.mockImplementation(async (path: string) => {
      if (path !== "portal")
        throw new Error("Unexpected paid request: " + path);
      return {
        account: { email: "owner@test.invalid" },
        releaseLinks: {},
        venues: [
          {
            venue: { id: "a", name: "Restaurant", loginCode: null },
            features: [],
            subscription: { status: "NO_PLAN" },
            plan: null,
            managers: [],
            devices: [],
            enrollments: [],
            checklist: {},
          },
        ],
      };
    });
    render(
      <MemoryRouter initialEntries={["/dashboard/" + section]}>
        <Routes>
          <Route path="/dashboard/:section" element={<CustomerDashboard />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(
      await screen.findByText("ამ პროდუქტის დასამატებლად განაახლეთ პაკეტი."),
    ).toBeVisible();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(api.call.mock.calls.every((c) => c[0] === "portal")).toBe(true);
  });
  it("saves enabled flags and per-printer ports and reports delivery honestly", async () => {
    const save = vi.fn().mockResolvedValue({});
    const user = userEvent.setup();
    render(<PrinterForm save={save} />);
    const hosts = screen.getAllByLabelText("IP / ჰოსტი");
    await user.type(hosts[0], "192.168.8.2");
    await user.type(hosts[1], "192.168.8.3");
    const ports = screen.getAllByLabelText("პორტი");
    await user.clear(ports[0]);
    await user.type(ports[0], "9200");
    await user.click(
      screen.getByRole("button", { name: "პრინტერების შენახვა" }),
    );
    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        kitchen: { enabled: true, host: "192.168.8.2", port: 9200 },
      }),
    );
    expect(
      await screen.findByText(/POS მიიღებს პარამეტრებს/),
    ).toBeInTheDocument();
  });
});
