// Run with the three local servers in docs/SAAS_OWNER_INVITATIONS.md.
// PLAYWRIGHT_MODULE may point to a shared installation; no production URLs allowed.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const output =
  process.env.ONBOARDING_PROOF_DIR || '/tmp/vynic-onboarding-proof';
fs.mkdirSync(output, { recursive: true });
const portal = 'http://127.0.0.1:5173';
const stamp = Date.now().toString(36);
const password = 'Local owner-created passphrase!';
(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.ONBOARDING_BROWSER_PATH
      ? { executablePath: process.env.ONBOARDING_BROWSER_PATH }
      : {}),
  });
  try {
    const adminContext = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
    });
    const admin = await adminContext.newPage();
    await admin.goto(portal + '/admin/onboarding');
    await admin
      .getByLabel('Email', { exact: true })
      .fill('admin@onboarding.test.invalid');
    await admin
      .getByLabel('Password', { exact: true })
      .fill('Local onboarding admin password!');
    await admin.getByRole('button', { name: 'Sign in', exact: true }).click();
    await admin.waitForURL((url) => !url.pathname.includes('/login'));
    await admin.goto(portal + '/admin/onboarding');
    await admin.getByRole('heading', { name: 'Pilot policy' }).waitFor();
    await admin.getByLabel('Open pilot registration').check();
    await admin
      .locator('select[name=trialPlanId]')
      .selectOption({ label: 'Local website trial' });
    await admin
      .locator('select[name=defaultWebsiteMode]')
      .selectOption('SAAS');
    const savedPolicy = admin.waitForResponse(
      (r) =>
        r.url().endsWith('/onboarding/policy') &&
        r.request().method() === 'PUT',
    );
    await admin.getByRole('button', { name: 'Save policy' }).click();
    assert.equal((await savedPolicy).status(), 200);
    await admin
      .getByLabel('Organization name')
      .fill('Browser Assisted ' + stamp);
    await admin
      .getByLabel('Restaurant name', { exact: true })
      .fill('Assisted Table ' + stamp);
    await admin
      .getByLabel('Owner email', { exact: true })
      .first()
      .fill('assisted-' + stamp + '@test.invalid');
    await admin
      .locator('select[name=planId]')
      .selectOption({ label: 'Local website trial' });
    await admin
      .getByRole('button', { name: 'Create restaurant and invitation' })
      .click();
    const invitationInput = admin.getByLabel('Owner invitation link');
    await invitationInput.waitFor();
    const invitation = await invitationInput.inputValue();
    // Capture layout without recording the one-time secret.
    await admin.screenshot({
      path: output + '/admin-onboarding.png',
      fullPage: true,
      mask: [invitationInput],
    });
    const ownerContext = await browser.newContext({
      viewport: { width: 1280, height: 900 },
    });
    const owner = await ownerContext.newPage();
    await owner.goto(invitation);
    await owner.getByLabel('სახელი', { exact: true }).fill('Invited Owner');
    await owner.getByLabel('პაროლი', { exact: true }).fill(password);
    await owner
      .getByRole('button', { name: 'მოწვევის მიღება', exact: true })
      .click();
    await owner.waitForURL(portal + '/dashboard');
    await owner
      .getByRole('heading', { name: 'Assisted Table ' + stamp, exact: true })
      .waitFor();
    assert.equal(
      await owner
        .getByRole('heading', { name: '1. რესტორანის დამატება' })
        .count(),
      0,
    );
    await owner.getByLabel('მისამართის სახელი', { exact: true }).waitFor();

    async function publish(page, context, slug, title) {
      await page.getByLabel('მისამართის სახელი', { exact: true }).fill(slug);
      await page
        .getByRole('button', { name: 'მთავარი ბლოკი', exact: true })
        .click();
      await page.getByLabel('მთავარი სათაური', { exact: true }).fill(title);
      const saved = page.waitForResponse(
        (r) =>
          r.url().endsWith('/website/draft') && r.request().method() === 'PUT',
      );
      await page
        .getByRole('button', { name: 'მონახაზის შენახვა', exact: true })
        .click();
      assert.equal((await saved).status(), 200);
      await page
        .getByRole('button', { name: 'პუბლიკაცია', exact: true })
        .click();
      const newPage = context.waitForEvent('page');
      await page
        .getByRole('button', { name: 'მონახაზის ნახვა', exact: true })
        .click();
      const preview = await newPage;
      await preview
        .getByRole('heading', { name: title, exact: true })
        .waitFor();
      await preview.screenshot({
        path: output + '/' + slug + '-preview.png',
        fullPage: true,
      });
      await page
        .getByRole('button', { name: 'პუბლიკაცია', exact: true })
        .click();
      page.once('dialog', (d) => d.accept());
      const published = page.waitForResponse(
        (r) =>
          r.url().endsWith('/website/publish') &&
          r.request().method() === 'POST',
      );
      await page
        .getByRole('button', { name: 'გამოქვეყნება', exact: true })
        .click();
      assert.equal((await published).status(), 201);
      const publicPage = await context.newPage();
      await publicPage.goto('http://' + slug + '.vynic.localhost:5175');
      await publicPage
        .getByRole('heading', { name: title, exact: true })
        .waitFor();
      await publicPage.screenshot({
        path: output + '/' + slug + '-public.png',
        fullPage: true,
      });
      const payload = await publicPage.request.get(
        'http://' + slug + '.vynic.localhost:5175/api/website/bootstrap',
      );
      assert.equal((await payload.json()).preview, false);
      return publicPage;
    }
    await publish(
      owner,
      ownerContext,
      'assisted-' + stamp,
      'Assisted Table Website',
    );
    await owner.setViewportSize({ width: 390, height: 844 });
    await owner.screenshot({
      path: output + '/owner-mobile.png',
      fullPage: true,
    });
    assert(
      await owner.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    );

    const selfContext = await browser.newContext({
      viewport: { width: 1280, height: 900 },
    });
    const self = await selfContext.newPage();
    await self.goto(portal + '/signup');
    await self.getByLabel('სახელი', { exact: true }).fill('Self Owner');
    await self
      .getByLabel('ელფოსტა', { exact: true })
      .fill('self-' + stamp + '@test.invalid');
    await self.getByLabel('პაროლი', { exact: true }).fill(password);
    await self
      .getByRole('button', { name: 'ანგარიშის შექმნა', exact: true })
      .click();
    await self
      .getByLabel('რესტორნის სახელი', { exact: true })
      .fill('Self Table ' + stamp);
    await self.getByRole('button', { name: 'გაგრძელება', exact: true }).click();
    await self.getByLabel('მისამართის სახელი', { exact: true }).waitFor();
    await publish(self, selfContext, 'self-' + stamp, 'Self Service Website');
    console.log(
      'PASS: assisted UI creation → invite → existing Venue → draft → real preview → publish → Host-scoped public website',
    );
    console.log(
      'PASS: self-service UI signup → Venue → SaaS draft → preview → published website',
    );
    console.log('PASS: 390px owner portal has no horizontal overflow');
    fs.writeFileSync(
      output + '/result.json',
      JSON.stringify(
        {
          assistedSlug: 'assisted-' + stamp,
          selfSlug: 'self-' + stamp,
          verified: true,
        },
        null,
        2,
      ),
    );
  } catch (error) {
    for (const [index, context] of browser.contexts().entries()) {
      const page = context.pages()[0];
      if (page) {
        console.error(
          'Browser state:',
          await page.locator('h1,h2,[role=alert]').allTextContents(),
        );
        await page.screenshot({
          path: output + '/failure-' + index + '.png',
          mask: [page.locator('input')],
        });
      }
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.message.replace(/token=[^\s"']+/g, 'token=[redacted]'));
  process.exitCode = 1;
});
