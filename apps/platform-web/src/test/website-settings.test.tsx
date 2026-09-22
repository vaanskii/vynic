import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
const call = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: call }));
import { WebsiteSettings } from "../customer/WebsiteSettings";
const draft = {
  slug: "restaurant-a",
  themeKey: "classic",
  heroTitle: "Old title",
  heroSubtitle: "",
  about: "",
  seoTitle: "",
  seoDescription: "",
  workingHours: [],
  socials: [],
  gallery: [],
};
const initial = {
  mode: "SAAS",
  entitled: true,
  status: "PUBLISHED",
  revision: 1,
  publishedRevision: 1,
  publishedAt: "2026-09-22T10:00:00Z",
  hasUnpublishedChanges: false,
  draft,
  baseDomain: "vynic.local",
  domains: ["restaurant-a.vynic.local"],
};
beforeEach(() => call.mockReset());
describe("Owner website draft workflow", () => {
  it("keeps save, authenticated preview and explicit publish distinct", async () => {
    call.mockResolvedValueOnce(initial);
    const user = userEvent.setup();
    render(<WebsiteSettings venueId="a" />);
    const title = await screen.findByLabelText("მთავარი სათაური");
    await user.clear(title);
    await user.type(title, "New title");
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "მონახაზის ნახვა" }),
    ).toBeDisabled();
    const saved = {
      ...initial,
      revision: 2,
      hasUnpublishedChanges: true,
      draft: { ...draft, heroTitle: "New title" },
    };
    call.mockResolvedValueOnce(saved);
    await user.click(screen.getByRole("button", { name: "მონახაზის შენახვა" }));
    await screen.findByText("მონახაზი შენახულია. საჯარო გვერდი არ შეცვლილა.");
    expect(call).toHaveBeenLastCalledWith(
      "venues/a/website/draft",
      { expectedRevision: 1, content: saved.draft },
      "PUT",
    );
    call.mockResolvedValueOnce({
      content: saved.draft,
      revision: 2,
      profile: { name: "Restaurant A", address: null, phone: null },
    });
    await user.click(screen.getByRole("button", { name: "მონახაზის ნახვა" }));
    await screen.findByRole("heading", { name: "New title" });
    expect(call).toHaveBeenLastCalledWith("venues/a/website/preview");
    call.mockResolvedValueOnce({
      ...saved,
      publishedRevision: 2,
      hasUnpublishedChanges: false,
    });
    await user.click(screen.getByRole("button", { name: "გამოქვეყნება" }));
    await screen.findByText("ვებსაიტი გამოქვეყნებულია.");
    expect(call).toHaveBeenLastCalledWith(
      "venues/a/website/publish",
      { expectedRevision: 2 },
      "POST",
    );
  });
  it("shows CUSTOM status without generic editing and disables unentitled publishing", async () => {
    call.mockResolvedValueOnce({ ...initial, mode: "CUSTOM" });
    const view = render(<WebsiteSettings venueId="c" />);
    await screen.findByText("ინდივიდუალური ვებსაიტი ცალკე იმართება.");
    expect(screen.queryByLabelText("მთავარი სათაური")).toBeNull();
    view.unmount();
    call.mockResolvedValueOnce({
      ...initial,
      entitled: false,
      hasUnpublishedChanges: true,
    });
    render(<WebsiteSettings venueId="b" />);
    await screen.findByLabelText("მთავარი სათაური");
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();
  });
  it("retains edits on failure and offers reload after a revision conflict", async () => {
    call.mockResolvedValueOnce(initial);
    render(<WebsiteSettings venueId="a" />);
    const user = userEvent.setup();
    const title = await screen.findByLabelText("მთავარი სათაური");
    await user.type(title, " changed");
    call.mockRejectedValueOnce(new Error("conflict"));
    await user.click(screen.getByRole("button", { name: "მონახაზის შენახვა" }));
    await screen.findByRole("alert");
    expect(title).toHaveValue("Old title changed");
    call.mockResolvedValueOnce(initial);
    await user.click(
      screen.getByRole("button", { name: "ფორმის გადატვირთვა" }),
    );
    await waitFor(() => expect(title).toHaveValue("Old title"));
  });
});
