import { render, screen, waitFor, within } from "@testing-library/react";
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
  userEvent
    .setup()
    .click(
      within(await screen.findByRole("navigation")).getByRole("button", {
        name,
      }),
    );

beforeEach(() => call.mockReset());

describe("Owner website workspace", () => {
  it("keeps save, rendered draft preview and explicit publish distinct", async () => {
    call.mockResolvedValueOnce(initial);
    const user = userEvent.setup();
    const openWindow = vi.fn();
    vi.stubGlobal("open", openWindow);
    render(<WebsiteSettings venueId="a" />);

    await open("მთავარი");
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

    await open("გამოქვეყნება");
    // The preview opens the real frontend with the token in the URL fragment,
    // which a browser never sends to a server.
    call.mockResolvedValueOnce({
      token: "preview-token",
      expiresAt: "2026-09-22T10:30:00Z",
      previewOrigin: "http://restaurant-a.vynic.local:5175",
    });
    await user.click(screen.getByRole("button", { name: "საიტის ნახვა" }));
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
    await user.click(
      screen.getAllByRole("button", { name: "გამოქვეყნება" }).at(-1)!,
    );
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
    await open("მთავარი");
    await user.type(await screen.findByLabelText("მთავარი სათაური"), "!");
    await open("გამოქვეყნება");
    expect(
      screen.getAllByRole("button", { name: "გამოქვეყნება" }).at(-1)!,
    ).toBeDisabled();
    expect(screen.getByRole("button", { name: "საიტის ნახვა" })).toBeDisabled();
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
    expect(screen.queryByRole("button", { name: "მთავარი" })).toBeNull();
    view.unmount();

    call.mockResolvedValueOnce({
      ...initial,
      entitled: false,
      hasUnpublishedChanges: true,
    });
    render(<WebsiteSettings venueId="b" />);
    await open("გამოქვეყნება");
    expect(
      screen.getAllByRole("button", { name: "გამოქვეყნება" }).at(-1)!,
    ).toBeDisabled();
  });

  it("retains edits on failure and offers reload after a revision conflict", async () => {
    call.mockResolvedValueOnce(initial);
    render(<WebsiteSettings venueId="a" />);
    const user = userEvent.setup();
    await open("მთავარი");
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

describe("Owner-friendly controls", () => {
  it("uses eight sections and hides technical options until requested", async () => {
    call.mockResolvedValueOnce(initial);
    render(<WebsiteSettings venueId="a" address="თბილისი, რუსთაველის 12" />);
    const nav = await screen.findByRole("navigation");
    expect(
      within(nav)
        .getAllByRole("button")
        .map((b) => b.textContent),
    ).toEqual([
      "მთავარი",
      "ჩვენ შესახებ",
      "მენიუ",
      "ფოტოები",
      "სამუშაო საათები",
      "კონტაქტი",
      "დიზაინი",
      "გამოქვეყნება",
    ]);
    await open("კონტაქტი");
    expect(screen.getByText("თბილისი, რუსთაველის 12")).toBeVisible();
    expect(
      screen.getByRole("checkbox", { name: "რუკის ჩვენება" }),
    ).toBeChecked();
    expect(screen.getByLabelText("Google Maps-ის ბმული")).not.toBeVisible();
    for (const name of ["Instagram", "Facebook", "TikTok", "ვებსაიტი"])
      expect(screen.getByLabelText(name, { selector: "input" })).toBeVisible();
    await userEvent.click(screen.getByText("რუკაზე მდებარეობის დაზუსტება"));
    await userEvent.type(
      screen.getByLabelText("Google Maps-ის ბმული"),
      "maps.app.goo.gl/example",
    );
    await userEvent.tab();
    expect(screen.getByLabelText("Google Maps-ის ბმული")).toHaveValue(
      "https://maps.app.goo.gl/example",
    );
    await userEvent.click(
      screen.getByRole("checkbox", { name: "რუკის ჩვენება" }),
    );
    call.mockResolvedValueOnce({
      ...initial,
      draft: {
        ...draft,
        showMap: false,
        mapUrl: "https://maps.app.goo.gl/example",
      },
    });
    await userEvent.click(
      screen.getByRole("button", { name: "მონახაზის შენახვა" }),
    );
    await waitFor(() =>
      expect(call).toHaveBeenLastCalledWith(
        "venues/a/website/draft",
        expect.objectContaining({
          expectedRevision: 1,
          content: expect.objectContaining({
            showMap: false,
            mapUrl: "https://maps.app.goo.gl/example",
          }),
        }),
        "PUT",
      ),
    );
    await open("გამოქვეყნება");
    expect(screen.getByLabelText("ვებსაიტის მისამართი")).toBeVisible();
    expect(
      screen.getByLabelText("სათაური საძიებო სისტემისთვის"),
    ).not.toBeVisible();
    await userEvent.click(screen.getByText("დამატებითი პარამეტრები"));
    expect(screen.getByLabelText("სათაური საძიებო სისტემისთვის")).toBeVisible();
  });
  it("edits opening hours with day and time controls and preserves overnight hours", async () => {
    call.mockResolvedValueOnce(initial);
    render(<WebsiteSettings venueId="a" />);
    await open("სამუშაო საათები");
    await userEvent.click(screen.getByLabelText("ორშაბათი"));
    expect(screen.getByLabelText("გახსნა")).toHaveAttribute("type", "time");
    expect(screen.getByLabelText("დახურვა")).toHaveValue("22:00");
    await userEvent.clear(screen.getByLabelText("დახურვა"));
    await userEvent.type(screen.getByLabelText("დახურვა"), "01:00");
    call.mockResolvedValueOnce(initial);
    await userEvent.click(
      screen.getByRole("button", { name: "მონახაზის შენახვა" }),
    );
    expect(call).toHaveBeenLastCalledWith(
      "venues/a/website/draft",
      expect.objectContaining({
        content: expect.objectContaining({
          workingHours: [{ day: 1, opens: "10:00", closes: "01:00" }],
        }),
      }),
      "PUT",
    );
  });
});
