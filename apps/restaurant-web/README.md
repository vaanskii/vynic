# apps/restaurant-web

The generic Vynic SaaS restaurant website. One build serves every `SAAS` Venue;
which restaurant a visitor sees is decided by the backend from the request Host.

This is **not** `apps/venue-web`, which is the bespoke Vankisi `CUSTOM` site and
stays a separate product.

## Rules this app lives by

- **No tenant identity here.** The app never sends a Venue id. A public visit is
  resolved from the Host; an owner preview is resolved from a short-lived
  preview token. There is no demo Venue and no fallback restaurant.
- **Same-origin API only.** `/api/...` is proxied to the backend with the
  browser's Host forwarded unchanged (`changeOrigin: false` in
  `vite.config.ts`). Pointing the app at an absolute API base would replace the
  restaurant's hostname with the backend's and serve every host the same site.
- **Indexable only when proven published.** `index.html` ships `noindex`;
  `src/seo/documentHead.ts` grants `index, follow` only to a published public
  page. Drafts, CUSTOM hosts and unavailable pages stay `noindex, nofollow`.
- **Content is text.** The backend stores no HTML and this app interprets none.

## Layout

```text
src/api/         bootstrap + menu contract and transport
src/i18n/        Georgian (default) and English frame strings
src/seo/         title, description, canonical, Open Graph, indexability
src/theme/       themeKey registry; `classic` is the one production theme
src/components/  the non-site page states
public/media/    local placeholder media fixtures, not product assets
```

Adding a theme is one entry in `src/theme/registry.ts` plus its components. The
public data model, the owner editor and the tenancy path do not change.

## Commands

```sh
npm install
npm run dev        # http://<restaurant>.vynic.localhost:5175
npm test
npm run lint
npm run build
```

`npm run dev` expects the website backend on `http://127.0.0.1:3102`; override
with `VYNIC_WEBSITE_API`. The local four-Venue fixture, hostnames, owner
credentials and preview flow are documented in `docs/WEBSITE_PHASE_W3.md`.
