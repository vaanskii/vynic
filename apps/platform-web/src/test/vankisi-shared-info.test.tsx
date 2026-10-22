import {
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { MemoryRouter, useNavigate } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import Footer from "../../../vankisi-custom-web/src/components/Footer";
import Contact from "../../../vankisi-custom-web/src/pages/Contact";
import Atmosphere from "../../../vankisi-custom-web/src/pages/Atmosphere";
import PaymentSuccess from "../../../vankisi-custom-web/src/pages/PaymentSuccess";
import { LanguageProvider } from "../../../vankisi-custom-web/src/contexts/LanguageContext";
import { WebsiteInfoProvider } from "../../../vankisi-custom-web/src/contexts/WebsiteInfoProvider";
import { vankisiSite } from "./vankisi-shared-info.fixture";
const get = vi.hoisted(() => vi.fn());
const clearCart = vi.hoisted(() => vi.fn());
vi.mock("../../../vankisi-custom-web/src/services/api", () => ({
  default: { get },
}));
vi.mock("../../../vankisi-custom-web/src/contexts/CartContext", () => ({
  useCart: () => ({ clearCart }),
}));
function RouteChange() {
  const navigate = useNavigate();
  return (
    <button onClick={() => navigate("/en/contact")}>Test route change</button>
  );
}
function show(children: ReactNode = <Footer />, path = "/ka") {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <LanguageProvider>
        <WebsiteInfoProvider>{children}</WebsiteInfoProvider>
      </LanguageProvider>
    </MemoryRouter>,
  );
}
beforeEach(() => {
  get.mockReset();
  clearCart.mockReset();
});

describe("WEB-07 real bespoke components consume Host-bound public information", () => {
  it.each(["ready", "unavailable", "empty"])(
    "confirmed payment uses shared contact; %s info never changes verified money status",
    async (kind) => {
      const site = vankisiSite();
      if (kind === "empty") site.info.contactEmail = "";
      get.mockImplementation((path: string) => {
        if (path === "/website/venue")
          return kind === "unavailable"
            ? Promise.reject(new Error("Synthetic info outage"))
            : Promise.resolve({ data: site });
        return Promise.resolve({
          data: { success: true, status: "CONFIRMED" },
        });
      });
      show(
        <PaymentSuccess />,
        "/ka/payment-success?reservation_id=synthetic-booking",
      );
      await waitFor(() => expect(clearCart).toHaveBeenCalledTimes(1));
      expect(get).toHaveBeenCalledWith(
        "/bog/check-reservation-status/synthetic-booking",
      );
      expect(screen.queryByText("restaurantvankisi@gmail.com")).toBeNull();
      if (kind === "ready")
        expect(
          await screen.findByRole("link", { name: "owner@test.invalid" }),
        ).toHaveAttribute("href", "mailto:owner@test.invalid");
      else if (kind === "unavailable")
        expect(await screen.findByRole("alert")).toBeVisible();
      else
        expect(
          screen.queryByRole("link", { name: "owner@test.invalid" }),
        ).toBeNull();
    },
  );
  it("renders owner-saved contact, map, seven-day hours and social links", async () => {
    get.mockResolvedValue({ data: vankisiSite() });
    show(<Contact />);
    const footer = within(screen.getByRole("contentinfo"));
    expect(
      await footer.findByRole("link", { name: "+995 599 98 93 76" }),
    ).toHaveAttribute("href", "tel:+995599989376");
    expect(
      footer.getByRole("link", { name: "Synthetic Street 1" }),
    ).toHaveAttribute("href", "https://maps.test.invalid/owner");
    expect(footer.getByRole("link", { name: "Instagram" })).toHaveAttribute(
      "href",
      "https://social.test.invalid/owner",
    );
    expect(
      footer.getByRole("link", { name: "owner@test.invalid" }),
    ).toHaveAttribute("href", "mailto:owner@test.invalid");
    expect(footer.getByText("10:00 – 01:00")).toBeVisible();
    expect(footer.getAllByText("დაკეტილია")).toHaveLength(5);
    expect(screen.getByRole("link", { name: "რუკის გახსნა" })).toHaveAttribute(
      "href",
      "https://maps.test.invalid/owner",
    );
    expect(document.querySelector("iframe")).toBeNull();
    expect(get).toHaveBeenCalledWith("/website/venue", {
      signal: expect.any(AbortSignal),
      adapter: "fetch",
      fetchOptions: { cache: "no-cache" },
    });
    expect(get).toHaveBeenCalledTimes(1);
  });
  it.each([
    ["ka", "ორშაბათი"],
    ["en", "Monday"],
    ["ru", "Понедельник"],
  ])(
    "weekday labels stay localized for %s even if browser Intl falls back to English",
    async (lang, monday) => {
      const english = new Intl.DateTimeFormat("en", {
        weekday: "long",
        timeZone: "UTC",
      });
      vi.spyOn(Intl, "DateTimeFormat").mockImplementation(() => english);
      get.mockResolvedValue({ data: vankisiSite() });
      show(<Footer />, `/${lang}`);
      await screen.findByRole("link", { name: "+995 599 98 93 76" });
      expect(screen.getByText(monday)).toBeVisible();
    },
  );
  it("email address characters cannot inject mail headers", async () => {
    const site = vankisiSite();
    site.info.contactEmail = "local?subject=trap@test.invalid";
    get.mockResolvedValue({ data: site });
    show();
    const email = await screen.findByRole("link", {
      name: "local?subject=trap@test.invalid",
    });
    expect(email).toHaveAttribute(
      "href",
      "mailto:local%3Fsubject%3Dtrap@test.invalid",
    );
    expect(new URL(email.getAttribute("href")!).search).toBe("");
  });
  it("owner edits become visible on the next focus refresh without a build or frontend IDs", async () => {
    const after = vankisiSite();
    after.profile.phone = "+995 555 12 34 56";
    after.profile.address = "Updated public address";
    after.info.contactEmail = "updated@test.invalid";
    after.info.workingHours = [{ day: 2, opens: "09:00", closes: "18:00" }];
    get
      .mockResolvedValueOnce({ data: vankisiSite() })
      .mockResolvedValue({ data: after });
    show();
    await screen.findByRole("link", { name: "+995 599 98 93 76" });
    fireEvent(window, new Event("focus"));
    expect(
      await screen.findByRole("link", { name: "+995 555 12 34 56" }),
    ).toHaveAttribute("href", "tel:+995555123456");
    expect(screen.getByText("09:00 – 18:00")).toBeVisible();
    expect(screen.queryByText("10:00 – 01:00")).toBeNull();
    expect(screen.queryByText("+995 599 98 93 76")).toBeNull();
    expect(screen.getByText("Updated public address")).toBeVisible();
    expect(get).toHaveBeenCalledTimes(2);
  });
  it("actual Atmosphere gallery uses owner URLs/alt instead of its old static teaser", async () => {
    get.mockResolvedValue({ data: vankisiSite() });
    show(<Atmosphere />);
    const photo = await screen.findByRole("img", { name: "Owner photo one" });
    expect(photo).toHaveAttribute("src", "/media/synthetic-one.jpg");
    expect(screen.queryByRole("img", { name: "Detail 1" })).toBeNull();
    expect(screen.queryByRole("img", { name: "Detail 4" })).toBeNull();
    expect(
      screen.getByRole("img", { name: "Main Dining Room" }),
    ).toBeInTheDocument();
  });
  it("capability-off hours and gallery never fall back to static promises/photos", async () => {
    const site = vankisiSite();
    site.capabilities.hours = false;
    site.capabilities.gallery = false;
    get.mockResolvedValue({ data: site });
    show(<Atmosphere />);
    await screen.findByRole("link", { name: "+995 599 98 93 76" });
    expect(screen.queryByText("10:00 – 01:00")).toBeNull();
    expect(screen.queryByText("11:00 – 00:00")).toBeNull();
    expect(screen.queryByRole("img", { name: "Owner photo one" })).toBeNull();
    expect(screen.queryByRole("img", { name: "Detail 1" })).toBeNull();
  });
  it("an intentional empty profile is not replaced with the old phone/address/map", async () => {
    const site = vankisiSite();
    site.profile.phone = null;
    site.profile.address = null;
    site.info.contactEmail = "";
    site.info.mapUrl = "";
    site.info.socials = [];
    site.info.workingHours = [];
    site.capabilities.hours = false;
    get.mockResolvedValue({ data: site });
    show(<Contact />);
    await waitFor(() => expect(screen.queryByRole("status")).toBeNull());
    expect(screen.queryByText("+995 599 98 93 76")).toBeNull();
    expect(screen.queryByText("restaurantvankisi@gmail.com")).toBeNull();
    expect(screen.queryByRole("link", { name: "რუკის გახსნა" })).toBeNull();
    expect(document.querySelector("iframe")).toBeNull();
  });
  it("network failure is visible, clears public fields, and retry reads the API", async () => {
    get
      .mockRejectedValueOnce(new Error("Synthetic unavailable"))
      .mockResolvedValue({ data: vankisiSite() });
    show();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "რესტორნის მიმდინარე ინფორმაცია ვერ ჩაიტვირთა.",
    );
    expect(screen.queryByText("+995 599 98 93 76")).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "ხელახლა ცდა" }));
    expect(
      await screen.findByRole("link", { name: "+995 599 98 93 76" }),
    ).toBeVisible();
  });
  it.each(["foreign", "SAAS", "SETUP_PENDING", "schema2"])(
    "%s cannot disclose another binding or substitute static business data",
    async (kind) => {
      const site = vankisiSite();
      const data: unknown =
        kind === "foreign"
          ? { ...site, site: { key: "other-client-web", status: "ACTIVE" } }
          : kind === "SAAS"
            ? { ...site, mode: "SAAS", site: null }
            : kind === "SETUP_PENDING"
              ? {
                  ...site,
                  site: { key: "vankisi-web", status: "SETUP_PENDING" },
                }
              : { ...site, schemaVersion: 2 };
      get.mockResolvedValue({ data });
      show();
      await screen.findByRole("alert");
      expect(screen.queryByText("Synthetic Street 1")).toBeNull();
      expect(screen.queryByText("+995 599 98 93 76")).toBeNull();
      expect(screen.queryByText("10:00 – 01:00")).toBeNull();
    },
  );
  it.each(["map", "social", "gallery", "duplicate-day"])(
    "malformed %s is an explicit read error without unsafe links/images",
    async (kind) => {
      const site = vankisiSite();
      if (kind === "map") site.info.mapUrl = "javascript:alert(1)";
      if (kind === "social") site.info.socials[0].url = "javascript:alert(1)";
      if (kind === "gallery") site.info.gallery[0].url = "/media/../auth";
      if (kind === "duplicate-day")
        site.info.workingHours = [
          site.info.workingHours[0],
          site.info.workingHours[0],
        ];
      get.mockResolvedValue({ data: site });
      show(<Contact />);
      await screen.findByRole("alert");
      expect(document.querySelector('a[href^="javascript:"]')).toBeNull();
      expect(screen.queryByText("Synthetic Street 1")).toBeNull();
    },
  );
  it("an old request finishing after route refresh cannot overwrite the new public snapshot", async () => {
    let finish: (value: {
      data: ReturnType<typeof vankisiSite>;
    }) => void = () => {};
    const late = new Promise<{ data: ReturnType<typeof vankisiSite> }>(
      (resolve) => {
        finish = resolve;
      },
    );
    const current = vankisiSite();
    current.profile.phone = "+995 555 12 34 56";
    get.mockReturnValueOnce(late).mockResolvedValue({ data: current });
    show(
      <>
        <RouteChange />
        <Footer />
      </>,
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Test route change" }),
    );
    await screen.findByRole("link", { name: "+995 555 12 34 56" });
    finish({ data: vankisiSite() });
    await waitFor(() =>
      expect(
        screen.queryByRole("link", { name: "+995 599 98 93 76" }),
      ).toBeNull(),
    );
    expect(
      screen.getByRole("link", { name: "+995 555 12 34 56" }),
    ).toBeVisible();
  });
});
