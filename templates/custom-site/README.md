# Custom restaurant site starter

Starting point for a CUSTOM website sold to one client. It is a plain Vite +
React app with placeholder styling; the design is yours to replace. What it
shows is the wiring: identity gate, capabilities, menu, availability and paid
booking through `@vynic/website-client`.

## New client site

```bash
cp -R templates/custom-site apps/restaurant-x-web
cd apps/restaurant-x-web
# 1. package.json "name" → "restaurant-x-web"
# 2. src/site.ts → export const SITE_KEY = "restaurant-x-web";  (hardcode it)
npm install
```

The operator records the same key as the Venue's **Custom frontend identity**
in Platform Admin → Venue → Website, and registers the domains.

## Run locally

1. Backend on a local disposable database, with the Venue provisioned as CUSTOM
   and a local domain such as `restaurant-x.vynic.localhost` registered
   (or use `apps/backend/scripts/seed-custom-websites-local.ts`).
2. `VYNIC_WEBSITE_API=http://127.0.0.1:3000 npm run dev` (port 5176; set
   `PORT` to run several custom sites side by side).
3. Open `http://restaurant-x.vynic.localhost:5176`.
4. For Platform's **Check now**, map the identity to that port in the backend
   environment: `CUSTOM_WEBSITE_LOCAL_FRONTENDS=restaurant-x-web=5176`
   (comma-separated for several sites; see `docs/CUSTOM_WEBSITES.md` §3c).

`*.localhost` resolves to your machine; the dev proxy forwards `/api` with the
browser's Host unchanged, which is how the backend knows the restaurant. Never
call the API by an absolute URL from the browser.

## Production

`npm run build`, then serve `dist/` for the client's domain behind a proxy that
sends `/api/` to the Vynic backend with the Host preserved (nginx example in
`docs/CUSTOM_WEBSITES.md` §5). DNS and TLS are manual. After deploying, the
operator verifies the domain and moves the site to READY/ACTIVE.

## What stays shared vs. custom

Shared (don't copy backend code): tenancy, profile, menu, tables, bookings,
BOG payments, website accounts. Custom (inside this app only): layout, brand,
pages, animations, anything one client alone needs.

`npm test` · `npm run typecheck` · `npm run build`
