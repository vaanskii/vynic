import { MemoryRouter } from "react-router-dom";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, it, expect, vi } from "vitest";
const api = vi.hoisted(() => ({ call: vi.fn(), session: vi.fn(() => false) }));
vi.mock("../customer/api", () => ({
  customerApi: api.call,
  hasCustomerSession: api.session,
  customerLogout: vi.fn(),
}));
import { CustomerPortal, PrinterForm } from "../customer/CustomerPortal";
beforeEach(() => {
  api.call.mockReset();
  api.session.mockReturnValue(false);
});
describe("Customer onboarding", () => {
  it.each([360, 768, 1280])(
    "signup, three-field restaurant setup and manager access at %ipx",
    async (width) => {
      window.innerWidth = width;
      vi.stubGlobal("scrollTo", vi.fn());
      const user = userEvent.setup();
      let hasVenue = false;
      api.call.mockImplementation(async (path: string, body?: any) => {
        if (path === "auth/signup") return { access_token: "test" };
        if (path === "venues") {
          hasVenue = true;
          return { id: "venue-a" };
        }
        if (path === "venues/venue-a/website")
          return { mode: "NONE", entitled: false, revision: 0, draft: {} };
        if (path === "venues/venue-a/managers") return { id: "m", ...body };
        if (path !== "portal") throw new Error(`unexpected ${path}`);
        return {
          account: { email: "owner@test.invalid" },
          releaseLinks: {},
          websiteBaseDomain: "vynic.localhost",
          venues: hasVenue
            ? [
                {
                  venue: {
                    id: "venue-a",
                    name: "My restaurant",
                    loginCode: "venue-a",
                  },
                  features: ["POS", "MANAGER_APP"],
                  subscription: { status: "TRIAL" },
                  managers: [],
                  devices: [],
                  enrollments: [],
                  checklist: { restaurant: true },
                  ready: false,
                },
              ]
            : [],
        };
      });
      render(<MemoryRouter><CustomerPortal /></MemoryRouter>);
      await user.type(screen.getByLabelText("სახელი"), "Owner");
      await user.type(screen.getByLabelText("ელფოსტა"), "owner@test.invalid");
      await user.type(
        screen.getByLabelText("პაროლი"),
        "a long test passphrase",
      );
      await user.click(
        screen.getByRole("button", { name: "ანგარიშის შექმნა" }),
      );
      await user.type(
        await screen.findByLabelText("რესტორნის სახელი"),
        "My restaurant",
      );
      expect(screen.getByText("my-restaurant.vynic.localhost")).toBeVisible();
      await user.upload(
        screen.getByLabelText("ლოგოს ატვირთვა"),
        new File(["png"], "logo.png", { type: "image/png" }),
      );
      await user.click(screen.getByRole("button", { name: "გაგრძელება" }));
      expect(
        await screen.findByRole("heading", { name: "გამარჯობა, My restaurant" }),
      ).toBeVisible();
      expect(screen.queryByText("venue-a")).not.toBeInTheDocument();
      expect(api.call).not.toHaveBeenCalledWith("venues/venue-a/payments/bog");
      await user.click(screen.getByRole("button", { name: "მენეჯერები" }));
      await user.click(screen.getByRole("button", { name: "კოდის კოპირება" }));
      expect(await navigator.clipboard.readText()).toBe("venue-a");
      expect(screen.queryByLabelText("პაროლი")).not.toBeInTheDocument();
      await user.type(screen.getByLabelText("მენეჯერის სახელი"), "Manager");
      await user.type(screen.getByLabelText("მომხმარებლის სახელი"), "manager");
      await user.type(screen.getByLabelText("PIN"), "482915");
      await user.click(
        screen.getByRole("button", { name: "მენეჯერის შექმნა" }),
      );
      await waitFor(() =>
        expect(api.call).toHaveBeenCalledWith(
          "venues/venue-a/managers",
          expect.objectContaining({ pin: "482915", role: "MANAGER" }),
        ),
      );
      expect(screen.getByText(/Vynic Manager · macOS —/)).toBeInTheDocument();
      await user.click(
        screen.getByRole("button", { name: "მოწყობილობები / POS" }),
      );
      expect(screen.getByText(/Vynic POS · Windows —/)).toBeInTheDocument();
    },
  );
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
