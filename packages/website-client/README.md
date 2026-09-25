# @vynic/website-client

Shared logic for CUSTOM restaurant frontends: a typed client for the Vynic
public website API, the frontend-identity gate, and optional data hooks. No
markup, no styles, no runtime dependencies — each custom site keeps its own
design.

```ts
import { createWebsiteClient, createWebsiteHooks } from "@vynic/website-client";
import { useEffect, useState } from "react";

export const client = createWebsiteClient();          // same-origin /api only
export const hooks = createWebsiteHooks({ useState, useEffect }, client);

const site = hooks.useSite("restaurant-x-web");       // this build's identity
```

## Rules

- There is no way to name a Venue, domain or organization. The backend picks
  the restaurant from the request Host; serve the site behind a host-preserving
  `/api` proxy (see `docs/CUSTOM_WEBSITES.md`). Do not set `baseUrl` to an
  absolute API host in a browser build.
- `useSite(key)` / `gateSite(bootstrap, key)` returns `misattached` when the
  Venue's operator-recorded frontend is not this build. Render nothing branded
  in that case.
- Hide features whose `capabilities` flag is false; the backend refuses them
  anyway.
- Prices, payment credentials and the booking's account are decided by the
  server. `bookAndPay` returns the bank redirect URL.

## API

| Client method | Route |
| --- | --- |
| `bootstrap()` | `GET /api/website/custom/bootstrap` (404 → `SiteUnavailableError`, 403 → access ended) |
| `menu()` | `GET /api/website/custom/menu` |
| `tables()`, `availability(date)` | `GET /api/tables`, `/api/tables/availability` |
| `bookAndPay(request)` | `POST /api/bog/create-order` |
| `paymentStatus(reservationId)` | `GET /api/bog/check-reservation-status/:id` |
| `session()`, `signIn()`, `signUp()`, `signOut()` | `/api/auth/*` (CSRF handled) |
| `myReservations()` | `GET /api/user/reservations` |

Helpers: `itemName(item, lang)`, `formatPrice(amount, currency)`.

## Consuming it

Source-only TypeScript. Apps alias it (see `templates/custom-site/vite.config.ts`
and `tsconfig.json`): `@vynic/website-client` →
`../../packages/website-client/src/index.ts`.

```bash
npm install && npm test && npm run typecheck
```
