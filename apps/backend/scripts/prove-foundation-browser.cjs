// Requires the disposable foundation harness on 3103 and frontends on 5173/5175.
// All API/media traffic is routed to 3103; the ordinary backend is never queried.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');
(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.BROWSER_EXECUTABLE,
    args: ['--host-resolver-rules=MAP *.vynic.localhost 127.0.0.1'],
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
  });
  await context.route(
    (url) =>
      /^\/(customer|api\/website|media\/website-logos)\//.test(url.pathname),
    async (route) => {
      const req = route.request(),
        u = new URL(req.url());
      const response = await context.request.fetch(
        'http://127.0.0.1:3103' + u.pathname + u.search,
        {
          method: req.method(),
          headers: { ...req.headers(), host: u.host },
          data: req.postDataBuffer() ?? undefined,
        },
      );
      await route.fulfill({ response });
    },
  );
  const page = await context.newPage();
  const tag = Date.now().toString(36);
  await page.goto('http://localhost:5173/signup');
  await page.locator('[name=displayName]').fill('Foundation browser owner');
  await page
    .locator('[name=email]')
    .fill(`browser-${tag}@foundation.test.invalid`);
  await page.locator('[name=password]').fill('Foundation browser password!');
  await page
    .getByRole('button', { name: 'ანგარიშის შექმნა', exact: true })
    .click();
  await page
    .getByLabel('რესტორნის სახელი', { exact: true })
    .fill('Foundation Browser');
  const sharp = require('sharp');
  const png = await sharp({
    create: { width: 32, height: 32, channels: 3, background: '#884422' },
  })
    .png()
    .toBuffer();
  await page
    .locator('input[type=file]')
    .setInputFiles({ name: 'logo.png', mimeType: 'image/png', buffer: png });
  await page.locator('#first-run-address').fill('foundation-' + tag);
  await page.getByRole('button', { name: 'გაგრძელება', exact: true }).click();
  await page
    .getByRole('navigation', { name: 'მართვის პანელის განყოფილებები' })
    .waitFor();
  if (
    await page
      .getByRole('button', { name: 'POS-ის დაკავშირება', exact: true })
      .count()
  )
    throw Error('Unexpected POS setup');
  await page.goto('http://localhost:5173/dashboard/menu');
  await page
    .getByRole('button', { name: 'კატეგორიის დამატება', exact: true })
    .click();
  await page.getByLabel('სახელი ქართულად', { exact: true }).fill('სასმელი');
  await page.getByLabel('სახელი ინგლისურად', { exact: true }).fill('Drinks');
  await page.getByRole('button', { name: 'შენახვა', exact: true }).click();
  await page
    .getByRole('button', { name: 'ქვეკატეგორიის დამატება', exact: true })
    .click();
  await page.getByLabel('სახელი ქართულად', { exact: true }).fill('ჩაი');
  await page.getByLabel('სახელი ინგლისურად', { exact: true }).fill('Tea');
  await page.getByRole('button', { name: 'შენახვა', exact: true }).click();
  await page
    .getByRole('button', { name: 'ქვეკატეგორიის შეცვლა', exact: true })
    .waitFor();
  await page
    .getByRole('button', { name: 'კერძის დამატება', exact: true })
    .last()
    .click();
  await page.getByLabel('სახელი ქართულად', { exact: true }).fill('მთის ჩაი');
  await page
    .getByLabel('სახელი ინგლისურად', { exact: true })
    .fill('Mountain Tea');
  await page.getByLabel('ფასი', { exact: true }).fill('12.50');
  await page.getByRole('button', { name: 'შენახვა', exact: true }).click();
  await page
    .getByRole('button', { name: 'ზომის დამატება', exact: true })
    .click();
  await page.getByLabel('ზომა (ლ)', { exact: true }).fill('0.5');
  await page.getByLabel('ფასი', { exact: true }).fill('8.50');
  await page.getByRole('button', { name: 'შენახვა', exact: true }).click();
  await page
    .getByRole('button', { name: 'რედაქტირება', exact: true })
    .waitFor();
  await page.screenshot({
    animations: 'disabled',
    path: '/private/tmp/foundation-menu-desktop.png',
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page
    .getByRole('button', { name: 'რედაქტირება', exact: true })
    .waitFor();
  await page.screenshot({
    animations: 'disabled',
    path: '/private/tmp/foundation-menu-mobile.png',
    fullPage: true,
  });
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth > innerWidth,
  );
  if (overflow) throw Error('Mobile horizontal overflow');
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole('button', { name: 'რედაქტირება', exact: true }).click();
  await page
    .getByLabel('სახელი ვებსაიტზე', { exact: true })
    .fill('Mountain Tea Public');
  await page.getByLabel('აღწერა', { exact: true }).fill('Fresh mountain tea');
  await page
    .locator('input[type=file]')
    .setInputFiles({ name: 'tea.png', mimeType: 'image/png', buffer: png });
  await page.getByRole('button', { name: 'შენახვა', exact: true }).click();
  await page
    .getByRole('button', { name: 'რედაქტირება', exact: true })
    .waitFor();
  await page.goto('http://localhost:5173/dashboard/website');
  await page
    .getByRole('button', { name: 'გამოქვეყნება', exact: true })
    .waitFor();
  const previewPromise = context.waitForEvent('page');
  await page
    .getByRole('button', { name: 'ვებსაიტის ნახვა', exact: true })
    .click();
  const preview = await previewPromise;
  await preview.getByText('Mountain Tea Public', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'გამოქვეყნება', exact: true }).click();
  await page.getByText('გამოქვეყნებულია', { exact: true }).waitFor();
  const publicPage = await context.newPage();
  await publicPage.goto('http://foundation-' + tag + '.vynic.localhost:5175');
  await publicPage.getByText('Mountain Tea Public', { exact: true }).waitFor();
  await publicPage.screenshot({
    path: '/private/tmp/foundation-public.png',
    fullPage: true,
    animations: 'disabled',
  });
  fs.writeFileSync(
    '/private/tmp/foundation-ui-result.json',
    JSON.stringify({ slug: 'foundation-' + tag, url: page.url(), overflow }),
  );
  await browser.close();
  console.log('Browser onboarding + catalog CRUD + responsive proof passed');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
