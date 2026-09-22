import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, it, expect, vi } from "vitest";
const call = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: call }));
import { WebsiteImageUpload } from "../customer/WebsiteImageUpload";
beforeEach(() => call.mockReset());
it("uploads a file as multipart and returns its reference without publishing", async () => {
  const change = vi.fn(),
    busy = vi.fn();
  call.mockResolvedValue({ url: "/media/website-logos/new.webp" });
  render(
    <WebsiteImageUpload venueId="a" value="" onChange={change} onBusy={busy} />,
  );
  const file = new File(["png"], "logo.png", { type: "image/png" });
  await userEvent.upload(screen.getByLabelText("ლოგოს ატვირთვა"), file);
  await waitFor(() =>
    expect(change).toHaveBeenCalledWith("/media/website-logos/new.webp"),
  );
  expect(call.mock.calls[0][0]).toBe("venues/a/website/logo");
  expect(call.mock.calls[0][1].get("file")).toBe(file);
  expect(busy.mock.calls.map((c) => c[0])).toEqual([true, false]);
  expect(call).toHaveBeenCalledTimes(1);
});
it("retains the old logo after failure and permits retry and removal", async () => {
  const change = vi.fn();
  call.mockRejectedValueOnce(new Error("failed"));
  render(
    <WebsiteImageUpload
      venueId="a"
      value="https://example.invalid/old.png"
      onChange={change}
      onBusy={vi.fn()}
    />,
  );
  const input = screen.getByLabelText("ლოგოს ატვირთვა");
  const file = new File(["png"], "logo.png", { type: "image/png" });
  await userEvent.upload(input, file);
  await screen.findByRole("alert");
  expect(change).not.toHaveBeenCalled();
  expect(screen.getByRole("img")).toHaveAttribute(
    "src",
    "https://example.invalid/old.png",
  );
  call.mockResolvedValueOnce({ url: "/media/website-logos/retry.webp" });
  await userEvent.upload(input, file);
  await waitFor(() =>
    expect(change).toHaveBeenCalledWith("/media/website-logos/retry.webp"),
  );
  await userEvent.click(screen.getByRole("button", { name: "ლოგოს წაშლა" }));
  expect(change).toHaveBeenLastCalledWith("");
});
it("rejects an oversized image before requesting storage", async () => {
  render(
    <WebsiteImageUpload
      venueId="a"
      value=""
      onChange={vi.fn()}
      onBusy={vi.fn()}
    />,
  );
  await userEvent.upload(
    screen.getByLabelText("ლოგოს ატვირთვა"),
    new File([new Uint8Array(5 * 1024 * 1024 + 1)], "large.png", {
      type: "image/png",
    }),
  );
  await screen.findByRole("alert");
  expect(call).not.toHaveBeenCalled();
});

it("uploads the main photo through its own endpoint and retains it on failure", async () => {
  const change = vi.fn();
  call.mockResolvedValueOnce({ url: "/media/website-logos/hero.webp" });
  const view = render(
    <WebsiteImageUpload
      kind="hero"
      venueId="a"
      value=""
      onChange={change}
      onBusy={vi.fn()}
    />,
  );
  const file = new File(["image"], "restaurant.jpg", { type: "image/jpeg" });
  await userEvent.upload(screen.getByLabelText("მთავარი ფოტოს ატვირთვა"), file);
  await waitFor(() =>
    expect(change).toHaveBeenCalledWith("/media/website-logos/hero.webp"),
  );
  expect(call.mock.calls[0][0]).toBe("venues/a/website/hero");
  view.rerender(
    <WebsiteImageUpload
      kind="hero"
      venueId="a"
      value="/media/website-logos/hero.webp"
      onChange={change}
      onBusy={vi.fn()}
    />,
  );
  change.mockClear();
  call.mockRejectedValueOnce(new Error("failed"));
  await userEvent.upload(screen.getByLabelText("მთავარი ფოტოს ატვირთვა"), file);
  await screen.findByRole("alert");
  expect(change).not.toHaveBeenCalled();
  expect(screen.getByRole("img", { name: "მთავარი ფოტო" })).toHaveAttribute(
    "src",
    expect.stringContaining("/media/website-logos/hero.webp"),
  );
});
