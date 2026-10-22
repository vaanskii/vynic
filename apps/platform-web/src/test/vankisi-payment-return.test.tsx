import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import PaymentSuccess from "../../../vankisi-custom-web/src/pages/PaymentSuccess";
import PaymentFail from "../../../vankisi-custom-web/src/pages/PaymentFail";
const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  clear: vi.fn(),
  language: "ka",
}));
vi.mock("../../../vankisi-custom-web/src/services/api", () => ({
  default: { get: mocks.get },
}));
vi.mock("../../../vankisi-custom-web/src/contexts/CartContext", () => ({
  useCart: () => ({ clearCart: mocks.clear }),
}));
vi.mock("../../../vankisi-custom-web/src/contexts/WebsiteInfoContext", () => ({
  useWebsiteInfo: () => ({ state: { kind: "loading" }, reload: vi.fn() }),
}));
vi.mock("../../../vankisi-custom-web/src/contexts/LanguageContext", () => ({
  useLanguage: () => ({
    language: mocks.language,
    t: (key: string) =>
      key === "payment.success.title" ? "Confirmed reservation" : key,
  }),
}));
const keys = [
  "reservationData",
  "vankisi_reservation",
  "vankisi_preorder",
  "selectedReservationDate",
  "selectedReservationTime",
  "vankisi-cart",
  "checkoutInProgress",
  "redirectAfterLogin",
];
beforeEach(() => {
  mocks.get.mockReset();
  mocks.clear.mockReset();
  mocks.language = "ka";
  for (const key of keys) localStorage.setItem(key, "synthetic-retained-cart");
});
for (const [label, Component] of [
  ["success redirect", PaymentSuccess],
  ["failure redirect", PaymentFail],
] as const) {
  describe(`WEB-04 ${label} verifies actual server booking`, () => {
    function show(search = "?reservation_id=synthetic-booking") {
      render(
        <MemoryRouter initialEntries={["/ka/payment-return" + search]}>
          <Component />
        </MemoryRouter>,
      );
    }
    it.each(["PENDING", "REVIEW", "FAILED", "unknown"])(
      "%s preserves the cart and never displays success",
      async (status) => {
        mocks.get.mockResolvedValue({ data: { success: true, status } });
        show();
        expect(
          await screen.findByRole("button", { name: "ხელახლა გადამოწმება" }),
        ).toBeVisible();
        expect(screen.queryByText("Confirmed reservation")).toBeNull();
        expect(mocks.clear).not.toHaveBeenCalled();
        for (const key of keys)
          expect(localStorage.getItem(key)).toBe("synthetic-retained-cart");
        expect(mocks.get).toHaveBeenCalledWith(
          "/bog/check-reservation-status/synthetic-booking",
        );
      },
    );
    it("API error stays unconfirmed and a read retry can verify success", async () => {
      mocks.get
        .mockRejectedValueOnce(new Error("Synthetic outage"))
        .mockResolvedValue({ data: { success: true, status: "CONFIRMED" } });
      show();
      await userEvent.click(
        await screen.findByRole("button", { name: "ხელახლა გადამოწმება" }),
      );
      expect(await screen.findByText("Confirmed reservation")).toBeVisible();
      expect(mocks.get).toHaveBeenCalledTimes(2);
      expect(mocks.clear).toHaveBeenCalledTimes(1);
      for (const key of keys) expect(localStorage.getItem(key)).toBeNull();
    });
    it("missing identity cannot use redirect, browser history or stored checkout as proof", async () => {
      show("?success=true");
      expect(
        await screen.findByText("ჯავშანი ჯერ არ დადასტურებულა"),
      ).toBeVisible();
      expect(mocks.get).not.toHaveBeenCalled();
      expect(mocks.clear).not.toHaveBeenCalled();
      expect(localStorage.getItem("checkoutInProgress")).toBe(
        "synthetic-retained-cart",
      );
    });
    it("CONFIRMED without successful response is not booking proof", async () => {
      mocks.get.mockResolvedValue({
        data: { success: false, status: "CONFIRMED" },
      });
      show();
      expect(
        await screen.findByRole("button", { name: "ხელახლა გადამოწმება" }),
      ).toBeVisible();
      expect(mocks.clear).not.toHaveBeenCalled();
      expect(screen.queryByText("Confirmed reservation")).toBeNull();
    });
    it("English return also preserves the cart while bank processing continues", async () => {
      mocks.language = "en";
      mocks.get.mockResolvedValue({
        data: { success: true, status: "PENDING" },
      });
      show("?order_id=synthetic-order");
      expect(
        await screen.findByText("Waiting for the payment result"),
      ).toBeVisible();
      expect(mocks.get).toHaveBeenCalledWith(
        "/bog/check-status/synthetic-order",
      );
      expect(mocks.clear).not.toHaveBeenCalled();
    });
  });
}
