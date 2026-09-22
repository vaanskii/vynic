import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
const call = vi.hoisted(() => vi.fn());
vi.mock("../customer/api", () => ({ customerApi: call }));
import { WebsiteSettings } from "../customer/WebsiteSettings";

const draft = {
  slug: "restaurant-a",
  themeKey: "classic",
  logoUrl: "",
  heroTitle: "Old title",
  heroSubtitle: "",
  heroImageUrl: "",
  about: "",
  aboutImageUrl: "",
  showMenu: true,
  menuHeading: "",
  menuIntro: "",
  seoTitle: "",
  seoDescription: "",
  contactEmail: "",
  mapUrl: "",
  footerNote: "",
  workingHours: [],
  socials: [],
  gallery: [],
};
const initial = {
  schemaVersion: 2,
  themeKeys: ["classic"],
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
  publishedSlug: "restaurant-a",
};
const ownerMenu = {
  categories: [
    {
      id: "cat",
      slug: "starters",
      name: { ka: "ცივი კერძები", en: "Starters" },
      items: [
        {
          menuItemId: "item-1",
          name: { ka: "ფხალი", en: "Pkhali" },
          price: 12,
          variantCount: 0,
          visibleOnWebsite: true,
          displayName: null,
          description: null,
          imageUrl: null,
          sortOrder: 0,
          configured: false,
        },
      ],
      subcategories: [],
    },
  ],
};
/** Switch sections, waiting for the settings load that renders the nav. */
const open = async (name: string) =>
  userEvent.setup().click(await screen.findByRole("button", { name }));

beforeEach(() => call.mockReset());

describe("Owner website workspace", () => {
  it("keeps save, rendered draft preview and explicit publish distinct", async () => {
    call.mockResolvedValueOnce(initial);
    const user = userEvent.setup();
    const openWindow = vi.fn();
    vi.stubGlobal("open", openWindow);
    render(<WebsiteSettings venueId="a" />);

    await open("მთავარი ბლოკი");
    const title = await screen.findByLabelText("მთავარი სათაური");
    await user.clear(title);
    await user.type(title, "New title");

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

    await open("პუბლიკაცია");
    // The preview opens the real frontend with the token in the URL fragment,
    // which a browser never sends to a server.
    call.mockResolvedValueOnce({
      token: "preview-token",
      expiresAt: "2026-09-22T10:30:00Z",
      previewOrigin: "http://restaurant-a.vynic.local:5175",
    });
    await user.click(screen.getByRole("button", { name: "მონახაზის ნახვა" }));
    await waitFor(() =>
      expect(openWindow).toHaveBeenCalledWith(
        "http://restaurant-a.vynic.local:5175/preview#token=preview-token",
        "_blank",
        "noopener,noreferrer",
      ),
    );
    expect(call).toHaveBeenCalledWith("venues/a/website/preview-session", {});

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
    vi.unstubAllGlobals();
  });

  it("blocks preview and publish while the draft has unsaved edits", async () => {
    call.mockResolvedValueOnce(initial);
    const user = userEvent.setup();
    render(<WebsiteSettings venueId="a" />);
    await open("მთავარი ბლოკი");
    await user.type(await screen.findByLabelText("მთავარი სათაური"), "!");
    await open("პუბლიკაცია");
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "მონახაზის ნახვა" }),
    ).toBeDisabled();
  });

  it("edits website presentation without touching operational menu data", async () => {
    call.mockResolvedValueOnce(initial);
    const user = userEvent.setup();
    render(<WebsiteSettings venueId="a" />);
    call.mockResolvedValueOnce(ownerMenu);
    await open("მენიუ");

    const visible = await screen.findByRole("checkbox", { name: /ფხალი/ });
    expect(visible).toBeChecked();
    await user.click(visible);
    call.mockResolvedValueOnce({
      categories: [
        {
          ...ownerMenu.categories[0],
          items: [
            { ...ownerMenu.categories[0].items[0], visibleOnWebsite: false },
          ],
        },
      ],
    });
    await user.click(
      screen.getByRole("button", { name: "მენიუს ჩვენების შენახვა" }),
    );
    await screen.findByText("მენიუს ჩვენება შენახულია.");
    expect(call).toHaveBeenLastCalledWith(
      "venues/a/website/menu",
      {
        items: [
          {
            menuItemId: "item-1",
            visibleOnWebsite: false,
            displayName: null,
            description: null,
            imageUrl: null,
            sortOrder: 0,
          },
        ],
      },
      "PUT",
    );
  });

  it("shows CUSTOM status without generic editing and disables unentitled publishing", async () => {
    call.mockResolvedValueOnce({ ...initial, mode: "CUSTOM" });
    const view = render(<WebsiteSettings venueId="c" />);
    await screen.findByText("ინდივიდუალური ვებსაიტი ცალკე იმართება.");
    expect(screen.queryByRole("button", { name: "მთავარი ბლოკი" })).toBeNull();
    view.unmount();

    call.mockResolvedValueOnce({
      ...initial,
      entitled: false,
      hasUnpublishedChanges: true,
    });
    render(<WebsiteSettings venueId="b" />);
    await open("პუბლიკაცია");
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();
  });

  it("retains edits on failure and offers reload after a revision conflict", async () => {
    call.mockResolvedValueOnce(initial);
    render(<WebsiteSettings venueId="a" />);
    const user = userEvent.setup();
    await open("მთავარი ბლოკი");
    const title = await screen.findByLabelText("მთავარი სათაური");
    await user.type(title, " changed");
    call.mockRejectedValueOnce(new Error("conflict"));
    await user.click(screen.getByRole("button", { name: "მონახაზის შენახვა" }));
    await screen.findByRole("alert");
    expect(title).toHaveValue("Old title changed");
    call.mockResolvedValueOnce(initial);
    await user.click(screen.getByRole("button", { name: "ფორმის გადატვირთვა" }));
    await waitFor(() => expect(title).toHaveValue("Old title"));
  });
});
