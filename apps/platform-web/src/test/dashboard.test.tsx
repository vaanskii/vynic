import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
const api = vi.hoisted(() => ({ call: vi.fn(), session: vi.fn(() => true) }));
vi.mock("../customer/api", () => ({
  customerApi: api.call,
  hasCustomerSession: api.session,
  customerLogout: vi.fn(),
}));
import { CustomerDashboard } from "../customer/CustomerDashboard";
import type { OwnerMenu, OwnerMenuItem } from "../customer/WebsiteMenuEditor";

const draft = {
  slug: "tabla",
  themeKey: "classic",
  logoUrl: "/media/website-logos/logo.webp",
  heroTitle: "Tabla",
  heroSubtitle: "",
  heroImageUrl: "",
  about: "",
  aboutImageUrl: "",
  showMenu: true,
  menuHeading: "",
  menuIntro: "",
  seoTitle: "",
  seoDescription: "",
  footerNote: "",
};
/** Venue public information: saved live through `public-info`, in any mode. */
const shared = {
  workingHours: [] as { day: number; opens: string; closes: string }[],
  contactEmail: "",
  mapUrl: "",
  socials: [] as { label: string; url: string }[],
  gallery: [] as { url: string; alt: string }[],
  revision: 0,
};
const capabilities = (off: string[] = []) =>
  ["MENU", "HOURS", "RESERVATIONS", "GALLERY", "CUSTOMER_ACCOUNTS"].map(
    (key) => ({
      key,
      label: key,
      built: true,
      available: !off.includes(key),
      ready: true,
      live: !off.includes(key),
    }),
  );
const website = (patch: Record<string, unknown> = {}) => ({
  commercialStatus: "TRIAL",
  hostnameChangeAllowed: false,
  mediaUploadAllowed: true,
  schemaVersion: 2,
  themeKeys: ["classic"],
  mode: "SAAS",
  entitled: true,
  status: "DRAFT",
  revision: 1,
  publishedRevision: null as number | null,
  publishedAt: null,
  hasUnpublishedChanges: true,
  draft,
  shared,
  capabilities: capabilities(),
  baseDomain: "vynic.localhost",
  domains: [],
  publishedSlug: null,
  ...patch,
  // Mirrors the server: an entitled Venue without a mode is setup pending.
  state:
    (patch.state as string | undefined) ??
    ({ SAAS: "SAAS", CUSTOM: "CUSTOM" } as Record<string, string>)[
      String(patch.mode ?? "SAAS")
    ] ??
    "SETUP_PENDING",
});
const venueStatus = (patch: Record<string, unknown> = {}) => ({
  venue: {
    id: "venue-a",
    name: "Tabla",
    address: null,
    phone: null,
    branchName: null,
    legalId: null,
    loginCode: "tabla-7",
    timezone: "Asia/Tbilisi",
    currency: "GEL",
  },
  plan: { name: "Starter" },
  features: ["POS", "MANAGER_APP", "WEBSITE"],
  subscription: { status: "TRIAL", trialEndsAt: "2026-10-23T00:00:00Z" },
  managers: [],
  devices: [],
  enrollments: [] as { id: string; code: string; expiresAt: string; status: string; initialManagerSetup: boolean }[],
  checklist: { restaurant: true, manager: false, menu: false },
  ready: false,
  ...patch,
});
const ownerMenu: OwnerMenu = {
  categories: [
    {
      id: "georgian",
      slug: "georgian",
      name: { ka: "ქართული კერძები", en: "Georgian" },
      items: [],
      subcategories: [
        {
          id: "dough",
          slug: "dough",
          name: { ka: "ცომეული", en: "Dough" },
          items: [
            {
              menuItemId: "khinkali",
              name: { ka: "ხინკალი", en: "Khinkali" },
              price: 1.5,
              variantCount: 0,
              variants: [],
              visibleOnWebsite: true,
              displayName: null,
              description: null,
              imageUrl: null,
              sortOrder: 0,
              configured: false,
            },
            {
              menuItemId: "khachapuri",
              name: { ka: "ხაჭაპური", en: "Khachapuri" },
              price: 18,
              variantCount: 2,
              variants: [
                { id: "s", size: "S", price: 14 },
                { id: "l", size: "L", price: 22 },
              ],
              visibleOnWebsite: true,
              displayName: null,
              description: null,
              imageUrl: null,
              sortOrder: 1,
              configured: false,
            },
          ],
        },
      ],
    },
  ],
};

/** A small in-memory Customer API; returns the calls for assertions. */
function serve({
  venues = [venueStatus()],
  site = website(),
  menu = ownerMenu,
  taken = [] as string[],
  catalog,
}: {
  venues?: ReturnType<typeof venueStatus>[];
  site?: ReturnType<typeof website>;
  menu?: OwnerMenu;
  taken?: string[];
  catalog?: Record<string, unknown>;
} = {}) {
  // The portal projection carries the same server website state.
  venues = venues.map((v) => ({
    websiteState: v.features.includes("WEBSITE") ? site.state : "NOT_ENTITLED",
    ...v,
  }));
  const state = { venues, site, menu };
  api.call.mockImplementation(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async (path: string, body?: any, method?: string) => {
      if (path.endsWith("/hostname-requests")) return [];
      if (path.endsWith("/trial-requests")) return null;
      if (path === "access-requests/plans") return [];
      if (path.endsWith("/subscription"))
        return state.venues.find((v) => path.includes(v.venue.id))
          ?.subscription;
      if (path === "portal")
        return {
          account: { email: "owner@test.invalid" },
          releaseLinks: {},
          websiteBaseDomain: "vynic.localhost",
          venues: state.venues,
        };
      if (path === "venues") {
        state.venues = [
          venueStatus({ venue: { ...venueStatus().venue, name: body.name } }),
        ];
        return { id: "venue-a" };
      }
      if (path.endsWith("/profile")) {
        state.venues = [
          venueStatus({ venue: { ...state.venues[0].venue, ...body } }),
        ];
        return body;
      }
      if (path.includes("/website/address/")) {
        const slug = path.split("/").at(-1)!;
        return { valid: true, available: !taken.includes(slug) };
      }
      if (path.endsWith("/website/logo") || path.endsWith("/website/hero"))
        return { url: "/media/website-logos/new.webp" };
      if (path.endsWith("/website/public-info")) {
        if (body.expectedRevision !== state.site.shared.revision)
          throw new Error("conflict");
        const fields = { ...body };
        delete fields.expectedRevision;
        state.site = {
          ...state.site,
          shared: {
            ...state.site.shared,
            ...fields,
            revision: state.site.shared.revision + 1,
          },
        };
        return state.site;
      }
      if (path.endsWith("/website/draft")) {
        if (body.expectedRevision !== state.site.revision)
          throw new Error("conflict");
        state.site = {
          ...state.site,
          revision: state.site.revision + 1,
          hasUnpublishedChanges: true,
          draft: body.content,
        };
        return state.site;
      }
      if (path.endsWith("/website/publish")) {
        state.site = {
          ...state.site,
          status: "PUBLISHED",
          publishedRevision: state.site.revision,
          hasUnpublishedChanges: false,
        };
        return state.site;
      }
      if (path.endsWith("/website/preview-session"))
        return {
          token: "preview-token",
          expiresAt: "2026-09-23T10:30:00Z",
          previewOrigin: "http://tabla.vynic.localhost:5175",
        };
      if (catalog && path.endsWith("/catalog")) return catalog;
      if (path.endsWith("/website/menu")) {
        if (method === "PUT") {
          const [row] = body.items;
          const patch = (items: OwnerMenuItem[]) =>
            items.map((i) =>
              i.menuItemId === row.menuItemId ? { ...i, ...row } : i,
            );
          state.menu = {
            categories: state.menu.categories.map((c) => ({
              ...c,
              items: patch(c.items),
              subcategories: c.subcategories.map((s) => ({
                ...s,
                items: patch(s.items),
              })),
            })),
          };
        }
        return state.menu;
      }
      if (path.endsWith("/website")) return state.site;
      if (path.endsWith("/enrollments")) {
        const issued = { id: "synthetic-enrollment", code: "synthetic-once", expiresAt: "2099-01-01T00:00:00Z", status: "PENDING", initialManagerSetup: body.initialManagerSetup === true };
        state.venues = state.venues.map((v) => ({ ...v, enrollments: [issued] }));
        return issued;
      }
      if (path.endsWith("/managers"))
        return { id: "m1", displayName: body.displayName };
      throw new Error(`unexpected ${path}`);
    },
  );
  return state;
}
function Where() {
  return <p data-testid="where">{useLocation().pathname}</p>;
}
const renderPortal = (entry = "/dashboard") =>
  render(
    <MemoryRouter initialEntries={[entry]}>
      <Routes>
        <Route
          path="/dashboard/:section?"
          element={
            <>
              <CustomerDashboard />
              <Where />
            </>
          }
        />
        <Route path="*" element={<Where />} />
      </Routes>
    </MemoryRouter>,
  );
const nav = async () =>
  within(
    await screen.findByRole("navigation", {
      name: "მართვის პანელის განყოფილებები",
    }),
  );
const calls = (path: string) => api.call.mock.calls.filter(([p]) => p === path);

beforeEach(() => {
  api.call.mockReset();
  api.session.mockReturnValue(true);
  vi.stubGlobal("scrollTo", vi.fn());
});

describe("First-run setup", () => {
  it("Website Trial setup shows a read-only assigned address but no photo upload", async () => {
    const state = serve({
      site: website({
        revision: 0,
        mediaUploadAllowed: false,
        draft: { ...draft, slug: "tabla", logoUrl: "", heroTitle: "" },
      }),
    });
    const user = userEvent.setup();
    renderPortal();
    expect(await screen.findByLabelText("რესტორნის სახელი")).toHaveValue(
      "Tabla",
    );
    expect(screen.queryByLabelText("ლოგოს ატვირთვა")).toBeNull();
    await user.click(screen.getByRole("button", { name: "გაგრძელება" }));
    expect(
      await screen.findByRole("heading", { name: "გამარჯობა, Tabla" }),
    ).toBeVisible();
    expect(state.site.draft.slug).toBe("tabla");
    expect(state.site.draft.logoUrl).toBe("");
    expect(calls("venues/venue-a/website/logo")).toHaveLength(0);
  });

  it("Trial cannot choose an address or submit a hostname request", async () => {
    serve({ site: website({ revision: 0, mediaUploadAllowed: false }) });
    renderPortal();
    expect(await screen.findByText("თქვენი ვებსაიტის მისამართი")).toBeVisible();
    expect(screen.getByText("tabla.vynic.localhost")).toBeVisible();
    expect(screen.queryByLabelText("ვებსაიტის მისამართი")).toBeNull();
    expect(
      screen.queryByRole("button", { name: "მისამართის შეცვლის მოთხოვნა" }),
    ).toBeNull();
  });

  it("prefills an invited restaurant and keeps its prepared profile", async () => {
    const invited = venueStatus({
      venue: { ...venueStatus().venue, name: "Prepared", address: "Vake 1" },
    });
    const state = serve({
      venues: [invited],
      site: website({
        revision: 0,
        draft: { ...draft, slug: "tabla", logoUrl: "", heroTitle: "" },
      }),
    });
    const user = userEvent.setup();
    renderPortal();
    const name = await screen.findByLabelText("რესტორნის სახელი");
    expect(name).toHaveValue("Prepared");
    expect(screen.getByText("tabla.vynic.localhost")).toBeVisible();
    await user.clear(name);
    await user.type(name, "Tabla");
    await user.upload(
      screen.getByLabelText("ლოგოს ატვირთვა"),
      new File(["png"], "logo.png", { type: "image/png" }),
    );
    await user.click(screen.getByRole("button", { name: "გაგრძელება" }));
    await screen.findByRole("heading", { name: "გამარჯობა, Tabla" });
    expect(calls("venues")).toHaveLength(0);
    expect(calls("venues/venue-a/profile")[0][1]).toMatchObject({
      name: "Tabla",
      address: "Vake 1",
    });
    expect(state.site.draft.slug).toBe("tabla");
  });

  it("shows setup pending, not 'not included', when Website is sold but not provisioned", async () => {
    serve({ site: website({ mode: "NONE", revision: 0 }) });
    renderPortal();
    expect(
      await screen.findByRole("heading", { name: "გამარჯობა, Tabla" }),
    ).toBeVisible();
    expect(screen.getByText("ვებსაიტის მომზადება მიმდინარეობს")).toBeVisible();
    expect(
      screen.queryByText("ვებსაიტი თქვენს პაკეტში ჯერ არ არის ჩართული"),
    ).toBeNull();
    expect(screen.queryByText("ფოტოების დამატება")).toBeNull();
  });

  it("says Website is not included only when the package lacks it", async () => {
    serve({
      venues: [venueStatus({ features: ["POS", "MANAGER_APP"] })],
      site: website({ mode: "NONE", revision: 0 }),
    });
    renderPortal();
    expect(
      await screen.findByText("ვებსაიტი თქვენს პაკეტში ჯერ არ არის ჩართული"),
    ).toBeVisible();
    expect(screen.queryByText("ვებსაიტის მომზადება მიმდინარეობს")).toBeNull();
  });
});

describe("Owner portal", () => {
  it("offers one section per concern", async () => {
    serve();
    renderPortal();
    expect(
      (await nav()).getAllByRole("button").map((b) => b.textContent),
    ).toEqual([
      "მთავარი",
      "რესტორნის პროფილი",
      "ვებსაიტი",
      "მენიუ",
      "ფოტოები",
      "სამუშაო საათები",
      "ონლაინ გადახდები",
      "მოწყობილობები / POS",
      "მენეჯერები",
      "გამოწერა",
      "პარამეტრები",
    ]);
  });

  it("keeps website edits across sections and saves, previews and publishes separately", async () => {
    const state = serve();
    const user = userEvent.setup();
    const openWindow = vi.fn();
    vi.stubGlobal("open", openWindow);
    renderPortal("/dashboard/hours");

    await user.click(await screen.findByLabelText("ორშაბათი"));
    expect(screen.getByLabelText("გახსნა")).toHaveAttribute("type", "time");
    await user.clear(screen.getByLabelText("დახურვა"));
    await user.type(screen.getByLabelText("დახურვა"), "01:00");

    await user.click((await nav()).getByRole("button", { name: "მთავარი" }));
    expect(screen.getByText("შეუნახავი ცვლილებები")).toBeVisible();
    expect(
      screen.getByRole("button", { name: "ვებსაიტის ნახვა" }),
    ).toBeDisabled();
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    // Hours are Venue data: saved live, not into the page draft.
    await waitFor(() =>
      expect(state.site.shared.workingHours).toEqual([
        { day: 1, opens: "10:00", closes: "01:00" },
      ]),
    );
    expect(calls("venues/venue-a/website/public-info")[0][1]).toEqual({
      expectedRevision: 0,
      workingHours: [{ day: 1, opens: "10:00", closes: "01:00" }],
    });
    expect(calls("venues/venue-a/website/draft")).toEqual([]);
    expect(
      await screen.findByText("ცვლილებები შენახულია და საიტზე უკვე ჩანს."),
    ).toBeVisible();

    await user.click(screen.getByRole("button", { name: "ვებსაიტის ნახვა" }));
    await waitFor(() =>
      expect(openWindow).toHaveBeenCalledWith(
        "http://tabla.vynic.localhost:5175/preview#token=preview-token",
        "_blank",
        "noopener,noreferrer",
      ),
    );
    expect(state.site.status).toBe("DRAFT");

    await user.click(screen.getByRole("button", { name: "გამოქვეყნება" }));
    await screen.findByText("ვებსაიტი გამოქვეყნებულია.");
    expect(calls("venues/venue-a/website/publish")[0][1]).toEqual({
      expectedRevision: 1,
    });
    expect(screen.getAllByText("გამოქვეყნებულია")[0]).toBeVisible();
  });

  it("retains edits after a conflict and can discard them", async () => {
    const state = serve();
    const user = userEvent.setup();
    renderPortal("/dashboard/website");
    await user.click(
      await screen.findByRole("button", { name: "მთავარი გვერდი" }),
    );
    const title = screen.getByLabelText("მთავარი სათაური");
    await user.type(title, " changed");
    state.site = { ...state.site, revision: 5 };
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await screen.findByRole("alert");
    expect(title).toHaveValue("Tabla changed");
    await user.click(screen.getByRole("button", { name: "გაუქმება" }));
    expect(title).toHaveValue("Tabla");
  });

  it("shows the assigned website address and hides search settings until asked", async () => {
    serve({ taken: ["taken"] });
    const user = userEvent.setup();
    renderPortal("/dashboard/website");
    expect(await screen.findByText("თქვენი ვებსაიტის მისამართი")).toBeVisible();
    expect(screen.queryByLabelText("ვებსაიტის მისამართი")).toBeNull();
    await user.click(screen.getByRole("button", { name: "დიზაინი" }));
    expect(screen.getByLabelText("სათაური ძიების შედეგებში")).not.toBeVisible();
    await user.click(screen.getByText("Google-ში გამოჩენა"));
    expect(screen.getByLabelText("სათაური ძიების შედეგებში")).toBeVisible();
  });

  it("normalizes contact links and leaves the address to the profile", async () => {
    const state = serve();
    const user = userEvent.setup();
    renderPortal("/dashboard/website");
    await user.click(
      await screen.findByRole("button", { name: "კონტაქტი და ბმულები" }),
    );
    expect(screen.getByText("მისამართი ჯერ არ არის დამატებული.")).toBeVisible();
    await user.type(
      screen.getByLabelText("Instagram", { selector: "input" }),
      "instagram.com/tabla",
    );
    await user.tab();
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await waitFor(() =>
      expect(state.site.shared.socials).toEqual([
        { label: "Instagram", url: "https://instagram.com/tabla" },
      ]),
    );
    await user.click(
      screen.getByRole("button", { name: "მისამართის დამატება" }),
    );
    expect(await screen.findByLabelText(/^მისამართი/)).toBeVisible();
  });

  it("disables publishing for an unentitled website and explains CUSTOM", async () => {
    serve({ site: website({ entitled: false }) });
    const view = renderPortal();
    expect(
      await screen.findByText("გამოქვეყნება თქვენს პაკეტში გამორთულია."),
    ).toBeVisible();
    expect(screen.getByRole("button", { name: "გამოქვეყნება" })).toBeDisabled();
    view.unmount();

    serve({
      site: website({ mode: "CUSTOM", custom: { status: "SETUP_PENDING" } }),
    });
    const custom = renderPortal("/dashboard/website");
    expect(await screen.findByText("ინდივიდუალური ვებსაიტი")).toBeVisible();
    expect(screen.getByText("მომზადება მიმდინარეობს")).toBeVisible();
    expect(screen.getByText("დომენი ჯერ არ არის მიბმული.")).toBeVisible();
    // No generic editor, publication or address request for a CUSTOM site.
    expect(screen.queryByRole("button", { name: "გამოქვეყნება" })).toBeNull();
    expect(screen.queryByText(/მისამართის შეცვლის მოთხოვნა/)).toBeNull();
    custom.unmount();

    serve({
      site: website({
        mode: "CUSTOM",
        custom: { status: "ACTIVE" },
        domains: ["tabla.ge"],
      }),
    });
    renderPortal("/dashboard/website");
    expect(await screen.findByText("აქტიური")).toBeVisible();
    expect(screen.getByRole("link", { name: "tabla.ge" })).toHaveAttribute(
      "href",
      "https://tabla.ge",
    );
  });
});

describe("Shared website data", () => {
  const customSite = (patch: Record<string, unknown> = {}) =>
    website({
      mode: "CUSTOM",
      custom: { status: "ACTIVE" },
      domains: ["tabla.ge"],
      ...patch,
    });

  it("lets a CUSTOM owner manage hours and contacts, saved live without a draft", async () => {
    const state = serve({ site: customSite() });
    const user = userEvent.setup();
    renderPortal("/dashboard/hours");
    await user.click(await screen.findByLabelText("ორშაბათი"));
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await waitFor(() => expect(state.site.shared.workingHours).toHaveLength(1));
    expect(calls("venues/venue-a/website/draft")).toEqual([]);

    await user.click((await nav()).getByRole("button", { name: "ვებსაიტი" }));
    expect(await screen.findByText("ინდივიდუალური ვებსაიტი")).toBeVisible();
    await user.type(
      screen.getByLabelText("Instagram", { selector: "input" }),
      "instagram.com/tabla",
    );
    await user.tab();
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await waitFor(() =>
      expect(state.site.shared.socials).toEqual([
        { label: "Instagram", url: "https://instagram.com/tabla" },
      ]),
    );
    // The generic page's own controls never appear for a custom design.
    expect(screen.queryByText("რუკის ჩვენება")).toBeNull();
    expect(screen.queryByRole("button", { name: "გამოქვეყნება" })).toBeNull();
  });

  it("shows gallery management for CUSTOM but not the SAAS page photos", async () => {
    serve({ site: customSite() });
    renderPortal("/dashboard/photos");
    expect(
      await screen.findByRole("heading", { name: "გალერეა" }),
    ).toBeVisible();
    expect(screen.queryByRole("heading", { name: "მთავარი ფოტო" })).toBeNull();
  });

  it("follows the operator's capability switch, whatever the mode", async () => {
    for (const mode of ["SAAS", "CUSTOM"]) {
      serve({
        site: website({
          mode,
          custom: mode === "CUSTOM" ? { status: "ACTIVE" } : null,
          capabilities: capabilities(["HOURS"]),
        }),
      });
      const view = renderPortal("/dashboard/overview");
      // The Hours page is not offered to either kind of website.
      expect(
        (await nav()).queryByRole("button", { name: "სამუშაო საათები" }),
      ).toBeNull();
      view.unmount();
    }
  });
});

describe("Menu section", () => {
  it("lets a Website-only CUSTOM owner author the canonical catalog", async () => {
    serve({
      venues: [venueStatus({ features: ["WEBSITE"] })],
      site: website({
        mode: "CUSTOM",
        custom: { status: "ACTIVE" },
        domains: ["tabla.ge"],
      }),
      catalog: {
        authority: "CLOUD",
        editingEnabled: true,
        posIncluded: false,
        revision: 3,
        categories: [],
      },
    });
    renderPortal("/dashboard/menu");
    // The custom design renders it; the menu itself is edited here.
    expect(
      await screen.findByRole("button", { name: "კატეგორიის დამატება" }),
    ).toBeVisible();
    expect(screen.queryByText(/იმართება POS-ში/)).toBeNull();
    expect(await screen.findByText("ქართული კერძები")).toBeVisible();
  });

  it("shows the POS hierarchy and saves presentation one item at a time", async () => {
    const state = serve();
    const user = userEvent.setup();
    renderPortal("/dashboard/menu");

    expect(await screen.findByText("ქართული კერძები")).toBeVisible();
    expect(screen.getByText("ცომეული")).toBeVisible();
    expect(screen.getByText("ხინკალი")).toBeVisible();
    expect(screen.getByText("S · 14.00 ₾")).toBeVisible();
    expect(screen.getByText("L · 22.00 ₾")).toBeVisible();
    // Operational menu authoring stays in the POS.
    expect(screen.queryByRole("button", { name: /კატეგორია/ })).toBeNull();

    await user.click(
      screen.getByRole("switch", { name: "ხინკალი — ვებსაიტზე ჩვენება" }),
    );
    await waitFor(() =>
      expect(calls("venues/venue-a/website/menu").at(-1)).toEqual([
        "venues/venue-a/website/menu",
        {
          items: [
            {
              menuItemId: "khinkali",
              visibleOnWebsite: false,
              displayName: null,
              description: null,
              imageUrl: null,
              sortOrder: 0,
            },
          ],
        },
        "PUT",
      ]),
    );
    expect(
      screen.getByRole("switch", { name: "ხინკალი — ვებსაიტზე ჩვენება" }),
    ).not.toBeChecked();

    const [, edit] = screen.getAllByRole("button", { name: "რედაქტირება" });
    await user.click(edit);
    await user.type(screen.getByLabelText("აღწერა"), "ყველით");
    await user.click(screen.getByRole("button", { name: "შენახვა" }));
    await screen.findByText("„ხაჭაპური“ შენახულია.");
    expect(state.menu.categories[0].subcategories[0].items[1].description).toBe(
      "ყველით",
    );
    expect(screen.getByText(/ვებსაიტზე ჩანს/)).toHaveTextContent(
      "ვებსაიტზე ჩანს 1 / 2 კერძი",
    );
  });

  it("explains that an empty menu comes from the POS", async () => {
    serve({ menu: { categories: [] } });
    renderPortal("/dashboard/menu");
    expect(await screen.findByText("მენიუ ჯერ ცარიელია")).toBeVisible();
  });
});

describe("Operational sections", () => {
  it("existing Manager access is read-only in the owner cabinet", async () => {
    serve({
      venues: [
        venueStatus({
          managers: [
            {
              id: "existing",
              username: "giorgi",
              displayName: "Giorgi",
              isActive: true,
            },
          ],
        }),
      ],
    });
    renderPortal("/dashboard/managers");
    expect(await screen.findByText("Giorgi")).toBeVisible();
    expect(
      screen.queryByRole("button", {
        name: /PIN-ის შეცვლა|გამორთვა|მენეჯერის დამატება|აქტივაციის კოდის მიღება/,
      }),
    ).not.toBeInTheDocument();
    expect(screen.queryByLabelText("PIN")).not.toBeInTheDocument();
  });
  it("directs Manager installation linking to support without owner code or PIN mutation", async () => {
    serve();
    renderPortal("/dashboard/managers");
    expect((await screen.findAllByText(/Vynic-ის მხარდაჭერისგან მიიღეთ ერთჯერადი დაკავშირების კოდი/))[0]).toBeVisible();
    expect(screen.queryByRole("button", { name: "კოდის კოპირება" })).not.toBeInTheDocument();
    expect(screen.queryByLabelText("PIN")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "აქტივაციის კოდის მიღება" })).not.toBeInTheDocument();
    expect(calls("venues/venue-a/manager-links")).toHaveLength(0);
    expect(calls("venues/venue-a/managers")).toHaveLength(0);
  });

  it.each([true, false])("owner enrollment carries only the server's first Manager eligibility (%s)", async (eligible) => {
    serve({ venues: [venueStatus({ initialManagerSetupEligible: eligible })] });
    const user = userEvent.setup();
    renderPortal("/dashboard/devices");
    await user.click(await screen.findByRole("button", { name: "მოწყობილობის კოდის შექმნა" }));
    await waitFor(() => expect(calls("venues/venue-a/enrollments")).toHaveLength(1));
    expect(calls("venues/venue-a/enrollments")[0][1]).toEqual({ initialManagerSetup: eligible });
    expect(await screen.findByText("synthetic-once")).toBeVisible();
    expect(calls("venues/venue-a/manager-activation")).toHaveLength(0);
  });

  it("owner can connect an additional POS while first Manager registration is still pending", async () => {
    serve({ venues: [venueStatus({ initialManagerSetupEligible: true })] });
    const user = userEvent.setup();
    renderPortal("/dashboard/devices");
    const checkbox = await screen.findByRole("checkbox", { name: "პირველი Manager-ის რეგისტრაციაც" });
    expect(checkbox).toBeChecked();
    await user.click(checkbox);
    await user.click(screen.getByRole("button", { name: "მოწყობილობის კოდის შექმნა" }));
    expect(await screen.findByText("synthetic-once")).toBeVisible();
    expect(calls("venues/venue-a/enrollments")[0][1]).toEqual({ initialManagerSetup: false });
    expect(calls("venues/venue-a/manager-activation")).toHaveLength(0);
  });

  it("shows plan and payment availability in their own sections", async () => {
    serve();
    const user = userEvent.setup();
    renderPortal("/dashboard/subscription");
    expect(await screen.findByText("Starter")).toBeVisible();
    expect(screen.getByText("საცდელი პერიოდი")).toBeVisible();
    expect(
      (await nav()).getByRole("button", { name: "ონლაინ გადახდები" }),
    ).toBeVisible();
    await user.click(
      (await nav()).getByRole("button", { name: "მოწყობილობები / POS" }),
    );
    expect(screen.getByText(/Vynic POS · Windows —/)).toBeVisible();
  });
});

describe("Mobile section menu", () => {
  // jsdom does not evaluate the phone media query that reveals the burger, so
  // it is found by what it controls rather than by its (hidden) name.
  const burger = () =>
    screen
      .getAllByRole("button", { hidden: true })
      .find((b) => b.getAttribute("aria-controls") === "portal-sections")!;
  const sections = () =>
    screen.getByRole("navigation", { name: "მართვის პანელის განყოფილებები" });

  it("opens the sections from a burger button and closes after choosing", async () => {
    serve();
    const user = userEvent.setup();
    renderPortal();
    await nav();
    expect(burger()).toHaveAttribute("aria-label", "განყოფილებები · მთავარი");
    expect(burger()).toHaveAttribute("aria-expanded", "false");
    await user.click(burger());
    expect(burger()).toHaveAttribute("aria-expanded", "true");
    expect(sections()).toHaveClass("is-open");

    await user.click(
      within(sections()).getByRole("button", { name: "მენეჯერები" }),
    );
    expect(sections()).not.toHaveClass("is-open");
    expect(burger()).toHaveAttribute(
      "aria-label",
      "განყოფილებები · მენეჯერები",
    );
    expect(screen.getByTestId("where")).toHaveTextContent(
      "/dashboard/managers",
    );

    await user.click(burger());
    await user.keyboard("{Escape}");
    expect(sections()).not.toHaveClass("is-open");
    expect(burger()).toHaveAttribute("aria-expanded", "false");
  });
});

describe("Dashboard routes", () => {
  it("opens a section straight from its address, as after a refresh", async () => {
    serve();
    renderPortal("/dashboard/restaurant");
    expect(
      await screen.findByRole("heading", { name: "რესტორნის პროფილი" }),
    ).toBeVisible();
    expect(
      (await nav()).getByRole("button", { name: "რესტორნის პროფილი" }),
    ).toHaveAttribute("aria-current", "page");
  });

  it("changes the address when the owner picks a section", async () => {
    serve();
    const user = userEvent.setup();
    renderPortal();
    await user.click((await nav()).getByRole("button", { name: "გამოწერა" }));
    expect(screen.getByTestId("where")).toHaveTextContent(
      "/dashboard/subscription",
    );
    await user.click((await nav()).getByRole("button", { name: "მთავარი" }));
    expect(screen.getByTestId("where")).toHaveTextContent(/^\/dashboard$/);
  });

  it("sends an unknown section back to the dashboard home", async () => {
    serve();
    renderPortal("/dashboard/nope");
    expect(
      await screen.findByRole("heading", { name: "გამარჯობა, Tabla" }),
    ).toBeVisible();
    expect(screen.getByTestId("where")).toHaveTextContent(/^\/dashboard$/);
  });

  it("asks for sign-in without a customer session", async () => {
    api.session.mockReturnValue(false);
    renderPortal("/dashboard/menu");
    expect(await screen.findByTestId("where")).toHaveTextContent("/login");
    expect(api.call).not.toHaveBeenCalled();
  });

  it("returns to the Vynic site after logout", async () => {
    serve();
    const user = userEvent.setup();
    renderPortal("/dashboard/settings");
    const header = await screen.findByRole("banner");
    expect(within(header).getByText("მართვის პანელი")).toBeVisible();
    await user.click(within(header).getByRole("button", { name: "გასვლა" }));
    expect(screen.getByTestId("where")).toHaveTextContent(/^\/$/);
  });
});
