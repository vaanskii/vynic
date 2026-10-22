import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
const call = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: call }));
import { PaymentSettings } from "../customer/PaymentSettings";
beforeEach(() => call.mockReset());
describe("Owner payment settings", () => {
  it("clears write-only credentials after save and supports disable", async () => {
    call.mockResolvedValueOnce({ configured: false, entitled: true });
    const user = userEvent.setup();
    render(<PaymentSettings venueId="a" />);
    await screen.findByText("სტატუსი: არ არის დაკავშირებული");
    await user.type(screen.getByLabelText("Client ID"), "test-client");
    await user.type(screen.getByLabelText("Client Secret"), "test-secret");
    await user.type(
      screen.getByLabelText("ვებსაიტის მისამართი"),
      "https://a.example",
    );
    call.mockResolvedValueOnce({ configured: true, entitled: true });
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await screen.findByText("შენახულია.");
    expect(screen.getByLabelText("Client Secret")).toHaveValue("");
    expect(screen.getByLabelText("Client ID")).toHaveValue("");
    expect(call).toHaveBeenCalledWith(
      "venues/a/payments/bog",
      {
        clientId: "test-client",
        clientSecret: "test-secret",
        returnOrigin: "https://a.example",
      },
      "PUT",
    );
    call.mockResolvedValueOnce({ configured: false, entitled: true });
    await user.click(screen.getByRole("button", { name: "გათიშვა" }));
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "გათიშვა" })).toBeDisabled(),
    );
  });
  it("reports load failure with retry rather than pretending unconfigured", async () => {
    call.mockRejectedValueOnce(new Error("secret-bearing-error"));
    render(<PaymentSettings venueId="b" />);
    expect(await screen.findByRole("alert")).not.toHaveTextContent(
      "secret-bearing-error",
    );
    expect(screen.queryByText("სტატუსი: არ არის დაკავშირებული")).toBeNull();
    call.mockResolvedValueOnce({ configured: false, entitled: false });
    await userEvent.click(screen.getByRole("button", { name: "ხელახლა ცდა" }));
    await waitFor(() =>
      expect(
        screen.queryByRole("heading", { name: "ონლაინ გადახდები" }),
      ).toBeNull(),
    );
    expect(screen.queryByLabelText("Client ID")).toBeNull();
  });
});
