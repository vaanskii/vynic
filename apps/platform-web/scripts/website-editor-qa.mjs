// Run against a local Vite server. All customer responses are disposable fixtures.
// PLAYWRIGHT_MODULE can point to an existing Playwright installation.
import { mkdir } from "node:fs/promises";
import assert from "node:assert/strict";
const { chromium } = await import(
  process.env.PLAYWRIGHT_MODULE || "playwright"
);
const browser = await chromium.launch({
  headless: true,
  ...(process.env.BROWSER_PATH
    ? { executablePath: process.env.BROWSER_PATH }
    : {}),
});
const output = process.env.QA_OUTPUT || "/tmp/vynic-website-editor-qa";
await mkdir(output, { recursive: true });
const draft = {
  slug: "tabla",
  themeKey: "classic",
  logoUrl: "",
  heroTitle: "ტაბლა — გემო, რომელიც გვაერთიანებს",
  heroSubtitle: "ქართული სამზარეულო თბილისის გულში",
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
  showMap: true,
  footerNote: "",
  workingHours: [{ day: 1, opens: "10:00", closes: "01:00" }],
  socials: [],
  gallery: [],
};
const initial = {
  schemaVersion: 2,
  themeKeys: ["classic"],
  mode: "SAAS",
  entitled: true,
  status: "DRAFT",
  revision: 1,
  publishedRevision: null,
  publishedAt: null,
  hasUnpublishedChanges: true,
  draft,
  baseDomain: "vynic.ge",
  domains: [],
  publishedSlug: null,
};
const sections = [
  "მთავარი",
  "ჩვენ შესახებ",
  "მენიუ",
  "ფოტოები",
  "სამუშაო საათები",
  "კონტაქტი",
  "დიზაინი",
  "გამოქვეყნება",
];
try {
  for (const width of [390, 768, 1440]) {
    const context = await browser.newContext({
      viewport: { width, height: 1000 },
    });
    await context.addInitScript(() =>
      sessionStorage.setItem("vynic-customer-token", "local-qa"),
    );
    const page = await context.newPage();
    const errors = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") console.log(msg.text());
    });
    page.on("requestfailed", (request) =>
      console.log(request.url(), request.failure()),
    );
    page.on("pageerror", (e) => errors.push(e.message));
    await page.route("**/media/tabla.jpg", (route) =>
      route.fulfill({
        contentType: "image/svg+xml",
        body: '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="400"><rect width="800" height="400" fill="#e8e3d4"/><circle cx="400" cy="200" r="120" fill="#faf9f4"/><circle cx="400" cy="200" r="70" fill="#789567"/></svg>',
      }),
    );
    let settings = structuredClone(initial);
    let paymentRequests = 0;
    await page.route("**/customer/**", async (route) => {
      if (new URL(route.request().url()).pathname.startsWith("/src/"))
        return route.continue();
      const path = new URL(route.request().url()).pathname.split(
        "/customer/",
      )[1];
      let body;
      if (path === "portal")
        body = {
          account: {
            email: "owner@example.invalid",
            emailVerifiedAt: "2026-09-22",
          },
          releaseLinks: {},
          venues: [
            {
              venue: {
                id: "qa",
                name: "ტაბლა",
                address: "თბილისი, რუსთაველის გამზირი 12",
                loginCode: "tabla",
              },
              features: ["WEBSITE"],
              subscription: { status: "TRIAL" },
              managers: [],
              devices: [],
              enrollments: [],
              checklist: {},
              ready: false,
            },
          ],
        };
      else if (path === "venues/qa/website") body = settings;
      else if (path === "venues/qa/website/menu") body = { categories: [] };
      else if (path === "venues/qa/website/draft") {
        const request = route.request().postDataJSON();
        assert.equal(request.expectedRevision, settings.revision);
        settings = {
          ...settings,
          draft: request.content,
          revision: settings.revision + 1,
        };
        body = settings;
      } else if (path === "venues/qa/website/publish") {
        assert.equal(
          route.request().postDataJSON().expectedRevision,
          settings.revision,
        );
        settings = {
          ...settings,
          status: "PUBLISHED",
          publishedRevision: settings.revision,
          hasUnpublishedChanges: false,
        };
        body = settings;
      } else if (path.includes("payments")) {
        paymentRequests++;
        body = { entitled: false };
      } else
        return route.fulfill({
          status: 404,
          json: { message: "Unknown fixture route" },
        });
      await route.fulfill({ json: body });
    });
    await page.goto(`${process.env.QA_URL || "http://127.0.0.1:5193"}/portal`);
    const workspace = page.locator(".website-workspace");
    await workspace
      .getByRole("textbox", { name: "მთავარი სათაური" })
      .fill("ტაბლა — ახალი სათაური");
    assert.equal(
      await page.getByRole("button", { name: "კოდის კოპირება" }).isVisible(),
      false,
    );
    for (const [index, name] of sections.entries()) {
      await workspace
        .getByRole("navigation")
        .getByRole("button", { name, exact: true })
        .click();
      if (name === "კონტაქტი") {
        assert.equal(
          await workspace.getByLabel("Google Maps-ის ბმული").isVisible(),
          false,
        );
        await workspace
          .getByLabel("Instagram", { exact: true })
          .fill("instagram.com/tabla");
        await workspace.getByLabel("Facebook", { exact: true }).focus();
        assert.equal(
          await workspace.getByLabel("Instagram", { exact: true }).inputValue(),
          "https://instagram.com/tabla",
        );
      }
      if (name === "ფოტოები") {
        await workspace
          .getByRole("button", { name: "ფოტოების დამატება" })
          .click();
        await workspace
          .getByLabel("ფოტო", { exact: true })
          .fill("/media/tabla.jpg");
      }
      if (name === "გამოქვეყნება") {
        assert.equal(
          await workspace
            .getByLabel("სათაური საძიებო სისტემისთვის")
            .isVisible(),
          false,
        );
        assert.equal(
          await workspace
            .getByRole("button", { name: "გამოქვეყნება", exact: true })
            .last()
            .isDisabled(),
          true,
        );
      }
      assert.equal(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
        true,
        `Overflow at ${width}: ${name}`,
      );
      await page.screenshot({
        path: `${output}/${width}-${index}.png`,
        fullPage: true,
      });
    }
    await workspace.getByRole("button", { name: "მონახაზის შენახვა" }).click();
    await workspace
      .getByText("მონახაზი შენახულია. საჯარო გვერდი არ შეცვლილა.")
      .waitFor();
    assert.equal(settings.draft.heroTitle, "ტაბლა — ახალი სათაური");
    await workspace
      .getByRole("button", { name: "გამოქვეყნება", exact: true })
      .last()
      .click();
    await workspace.getByText("ვებსაიტი გამოქვეყნებულია.").waitFor();
    await page
      .getByRole("button", { name: "რესტორნის გამართვა", exact: true })
      .click();
    assert.equal(await workspace.isVisible(), false);
    assert.equal(paymentRequests, 0);
    assert.deepEqual(errors, []);
    console.log(
      `${width}px: 8 sections, no overflow, save/publish, setup isolation and payment gate passed`,
    );
    await context.close();
  }
} finally {
  await browser.close();
}
