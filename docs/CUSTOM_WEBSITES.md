# CUSTOM websites

A CUSTOM website is **a bespoke frontend over the shared Vynic backend**. It is
not a second backend. Vankisi (`apps/vankisi-custom-web`) is the first one; every later
custom client follows the same model.

| Frontend | What it is |
| --- | --- |
| `apps/vankisi-custom-web` | Vankisi's bespoke website, the first production CUSTOM frontend. Standalone; not built on the starter or the shared client. |
| `apps/restaurant-web` | The generic SaaS frontend: one build for every SAAS Venue. |
| `templates/custom-site` | Starter for **future** custom frontends. |
| `packages/website-client` | Optional shared client for **future** custom frontends. |

Vankisi does not migrate to the starter or the client package. It already uses
the shared backend through the same Host-resolved routes (`/api/menu`,
`/api/tables/*`, `/api/auth/*`, `/api/user/*`, `/api/bog/*`), and rebuilding it
would add risk without changing what it can do. Bespoke and starter-based
frontends coexist over one backend.

```text
CUSTOM frontend A ─┐
CUSTOM frontend B ─┼─→ Vynic NestJS Cloud (tenancy, profile, menu, bookings,
SAAS restaurant-web┘    payments, website users, capabilities)
```

Companion documents: [PUBLIC_TENANCY.md](PUBLIC_TENANCY.md) (Host authority),
[CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md) (runtime ADR),
[WEBSITE_PHASE_W1.md](WEBSITE_PHASE_W1.md) (per-Venue BOG),
[WEBSITE_SAAS_HOSTNAMES.md](WEBSITE_SAAS_HOSTNAMES.md) (SaaS addresses only).

---

## 1. How Vankisi CUSTOM works (audit)

Classification: **SHARED** (reusable by any custom site), **VANKISI** (bespoke
to Vankisi), **LEGACY**, **SECURITY** (a risk; fixed unless stated),
**CLEANUP** (should be removed or changed later).

| Area | Current behaviour | Class |
| --- | --- | --- |
| Transport | `apps/vankisi-custom-web/src/services/api.ts`: on `localhost`/IP it calls `http://<host>:3000/api` (cross-origin, dev only); otherwise `VITE_API_URL` if set, else same-origin `/api` behind nginx. Axios `withCredentials`. | SHARED pattern; `VITE_API_URL` is a trap (below) |
| Venue association | Host → `VenueDomain` → Venue in `website/tenancy/website-tenant.service.ts`. No Venue id is sent by the frontend. | SHARED |
| Host used | Production: the site's own domain through a host-preserving proxy. Local: `localhost:3000` → dev fallback to `WEBSITE_DEV_HOST` (default `vankisi.localhost`, registered by migration). | SHARED / LEGACY fallback |
| Cross-origin hosting (`vercel.json`, `VITE_API_URL`) | The API would see its **own** Host, so the Venue could only resolve if the API hostname were registered to Vankisi — impossible for a second site — and SameSite=Strict cookies would not travel. | SECURITY / CLEANUP: unsupported; use same-origin proxy |
| Menu | `GET /api/menu`, `/api/menu/:slug` (`website/menu`): Vankisi's shape, raw operational menu, ignores website presentation. | VANKISI shape (kept) |
| Tables / availability / bookings | `/api/tables*` (`website/reservation`), Venue-scoped `WebsiteTable`, POS mirror via bridge. | SHARED |
| Paid booking | `POST /api/bog/create-order` re-prices from the Venue's menu, creates a PENDING booking, opens a BOG order with the Venue's own encrypted integration. 10% service fee and GEL are hardcoded in `BogService`. | SHARED (fee/currency VANKISI assumptions) |
| Payment status / callback | `check-status`, `check-reservation-status` (Host + stored payment), signed `payment-callback` resolves `external_order_id` → reservation → Venue. BOG public key hardcoded (it is BOG's). | SHARED |
| BOG credentials | `payment-integrations/`: per-Venue, encrypted with `PAYMENT_INTEGRATION_MASTER_KEY`; return origin must be an ACTIVE domain of that Venue. Global `BOG_CLIENT_*` are read only by `scripts/import-bog-integration.ts`. | SHARED; `BOG_*`/`TBC_*` in `.env` = CLEANUP |
| WebsiteUser auth | `/api/auth/*` global identity; encrypted JWT cookies, host-only, SameSite=Strict; CSRF double-submit on signup/signin/change-password. | SHARED |
| My bookings | `/api/user/reservations`: global account, this Venue's CONFIRMED/COMPLETED bookings, plus guest bookings whose email matches. | SHARED; email match = SECURITY (open, §9) |
| Booking account link | Bookings accepted a browser-supplied `userId`. | SECURITY — **fixed**: session cookie only |
| Website `SUPER_ADMIN` | Global role; `GET /api/tables/reservations` returned the full booking list of **any** Venue to it. | SECURITY — **fixed**: bound via `WebsiteUser.adminVenueId` |
| Anonymous booking map | `GET /api/tables/reservations` (no login) returned every guest's name and phone. `vankisi-custom-web` uses only status/tables. | SECURITY — **fixed**: redacted |
| Mode | Legacy routes served any WEBSITE Venue, including SAAS ones. | Now shared on purpose: capability-gated for both modes, only after launch ([WEBSITE_FOUNDATION.md](WEBSITE_FOUNDATION.md)) |
| `shared/bootstrap` | For the bootstrap Venue only: seeds Vankisi's `WEBSITE_TABLE_MAPPINGS`, seeds `SUPER_ADMIN` from `SUPER_ADMIN_*` env (now bound to that Venue), logs menu/env gaps. | VANKISI / LEGACY |
| Hardcoded identity | Frontend: none (no Venue id/domain). Backend: bootstrap Venue id only in the seeder, `LEGACY_MANAGER_TENANT`, and migrations; `vankisi.localhost` dev default. Vankisi branding, 3D floors, storage keys (`vankisi-cart`) live in `vankisi-custom-web`. | VANKISI (frontend), LEGACY (backend seeder) |
| CORS | Allow-list from `FRONTEND_URL`/`ALLOWED_ORIGINS` + dev LAN. Every custom domain had to be listed in deployment env. | CLEANUP — **replaced** by same-origin rule (§6) |
| Forwarded host | With `TRUST_PROXY_HOST`, an unregistered forwarded host fell back to the direct Host. | SECURITY — **fixed**: forwarded host is sole authority |
| Dev fallback | Any unregistered `*.localhost` became Vankisi in development. | CLEANUP — **fixed**: only anonymous local hosts fall back |

## 2. Binding model

```text
Organization → Venue → WEBSITE entitlement (plan + Trial/ACTIVE)
            → WebsiteMode = CUSTOM          (operator only)
            → CustomWebsiteBinding          (siteKey, status, note)
            → VenueDomain(s)                (operator only, globally unique)
            → custom frontend deployment    (manual, same-origin /api proxy)
```

`CustomWebsiteBinding` (migration `20261009120000_custom_website_binding`):

| Field | Meaning |
| --- | --- |
| `venueId` | PK, cascades with the Venue. |
| `siteKey` | The custom frontend build meant to serve this Venue, e.g. `vankisi-web`, `restaurant-x-web`. Not unique: one design may serve several branches. |
| `status` | `SETUP_PENDING` · `READY` · `ACTIVE` · `ERROR`. No row = `NOT_CONFIGURED`. Tracking only. |
| `statusNote` | Operator-internal, never public. |
| `expectedBuildId` | Optional reviewed public artifact SHA-256. Null is legacy/unrecorded and cannot verify deployment. |

### Why a site key exists

Domain + Venue already decide **tenancy**; the key is not tenant authority and
the backend never trusts a frontend's claim of it. It exists because Domain +
Venue cannot answer "which frontend should be on this domain?":

- **Misattachment**: a proxy/deploy mistake can put build X on restaurant Y's
  domain. The build would render Y's data in X's brand, and nothing on the
  server could notice. The shared client compares the bootstrap's `site.key`
  with its own compiled key and renders nothing on mismatch.
- **Operator visibility**: Platform shows which app serves the Venue, with
  audited changes.
- **Readiness**: READY/ACTIVE require a recorded frontend.

## 3. Operator workflow (Platform Admin → Venue → Website)

1. Create/use Organization and Venue.
2. Assign the Website Trial or ACTIVE plan (Commercial tab). Every WEBSITE
   assignment path requires an explicit SAAS/CUSTOM choice (`provisionWebsite`).
3. Select **CUSTOM** (audited `venue.website_mode_changed`). A CUSTOM choice
   never assigns a SaaS address. Menu authority follows the package, exactly as
   for SAAS (§3a).
4. **Custom website** panel: record the frontend identity (`siteKey`).
5. **Domains**: register the production domain(s). Replace = register new,
   then release old, or use **Change hostname** with a reason. Vynic subdomains
   such as `restaurant.vynic.ge` are allowed. Disable keeps the name reserved.
   Platform-owned apex/api/admin/preview/www origins remain protected. All audited.
6. Product/Payments: grant `ONLINE_PAYMENTS` if sold; the owner (or a controlled
   import) configures the Venue's own BOG credentials with a return origin on
   one of its ACTIVE domains.
7. Deploy the frontend (manual, §5) and verify the domain → Venue answer:
   `curl -H 'Host: <domain>' https://<api>/api/website/venue`
   shows the right name and `site.key`.
8. Set status `READY` (deployed, verified) and later `ACTIVE`. READY/ACTIVE are
   refused unless WEBSITE is effective, mode is CUSTOM, a site key is recorded
   and at least one domain is ACTIVE. `ERROR` records a known problem.
9. **Live site**: **Open website** opens the public URL (in development, the
   local frontend, §3c); **Check now** reports whether it answers (§3b). Use it
   before READY and whenever in doubt.

No database edits and no Venue ids in frontend code are needed.

Routes: `GET|PUT /platform/venues/:venueId/custom-website`,
`POST /platform/venues/:venueId/custom-website/check`
(`platform/platform-custom-website.controller.ts`,
`website/custom/custom-website.service.ts`). SUPPORT_READONLY can read only.
Audit: `venue.custom_website_site_key_changed`,
`venue.custom_website_status_changed`, `venue.custom_website_build_changed` (actor, Venue, from/to, note) in the same
transaction as the change; the panel lists them with mode/domain/feature events.

**Customers cannot** switch SAAS ↔ CUSTOM, choose a frontend, or claim a domain:
there is no owner mutation route for any of them, the generic draft editor refuses
non-SAAS Venues, and website addresses are read-only in the owner cabinet; customers contact support.

### 3a. Menu authority

SAAS and CUSTOM only choose who renders the site. Both read the one canonical
catalog (`MenuCategory`/`MenuSubcategory`/`MenuItem`/variants plus
`MenuItemWebsitePresentation`) through the same Host-resolved routes; there is
no CUSTOM menu table or API.

| Package | Menu authority | Owner Dashboard Menu |
| --- | --- | --- |
| WEBSITE without POS (SAAS or CUSTOM) | `CLOUD`, admitted when the operator provisions the Website | Full catalog: categories, subcategories, items, variants, prices, enabled, plus website presentation |
| POS included | `POS` (unchanged) | Presentation only; catalog writes are refused (409) |

Admission is the existing conservative one (`cloud-menu-admission.ts`): any
POS evidence (devices, enrollment, catalog, orders, sales, …) keeps POS
authority and records the reason. Vankisi therefore stays POS-authoritative.
A Website-only Venue still on POS authority (provisioned before this rule) has
no catalog writer; Platform shows `needsCloudAuthority` as a warning on the
Product tab and the Custom website panel, and the repair is the existing
audited **Dashboard menu editing → Enable** control.

### 3b. Runtime availability

Setup status is what the operator attests; runtime availability is what the
site does now. They are reported separately, and a check never changes the
status.

| Availability | Meaning |
| --- | --- |
| `UNKNOWN` | Not checked in this view. Nothing is stored or monitored. |
| `REACHABLE` | `GET /` on the primary domain answered 2xx. |
| `UNREACHABLE` | No answer, redirect, 4xx/5xx, or the domain was refused (below). |

The check also reads `/api/website/venue` and `/vynic-site-manifest.json`.
Stable public Venue identity replaces name comparison; renderer/app key, reviewed
build fingerprint and served HTML digest are checked separately. Older servers
without identity are `UNVERIFIED`; missing/unrecorded manifests cannot verify a
build. Commercial/domain/renderer/binding/publication evidence is displayed
separately and stale observations are refused. Status remains operator tracking;
SETUP_PENDING/ERROR public serving behavior is unchanged. Full contract, local
candidate proof and production limits: [WEB05_BUILD_IDENTITY.md](WEB05_BUILD_IDENTITY.md).

Safety (`website/custom/custom-website-runtime.ts`): the only destination is a
server-owned ACTIVE `VenueDomain` of the Venue (the primary one, or its
`.localhost` one in development, §3c); there is no URL, host, port or path input.
The name is resolved once and every address must be public unicast (private,
loopback, link-local, CGNAT, multicast, documentation, NAT64, IPv4-mapped
private all refused), and the connection is pinned to the checked address
(no rebinding). IP-literal domains are never contacted, redirects are not
followed, all answer bodies are capped at 64 KB, partial responses fail, each
request has a 5 s absolute deadline, and one in-flight check per Venue/service
instance plus a 5 s interval is allowed, SUPER_ADMIN/operator only (SUPPORT_READONLY cannot trigger it). Production
always uses `https://<primary domain>/` with the public-address rules above.
A reachable frontend does not prove the right build is deployed: only
frontends on the shared client refuse a mismatched `site.key`.

The **primary domain** is the earliest ACTIVE public domain, or the earliest
ACTIVE `.localhost` one when the Venue has no public domain. **Public URL** is
`https://<primary>/`, and none when the primary is `.localhost` (never public).

### 3c. Local frontends (development only)

A `VenueDomain` is domain identity only: `vankisi.localhost` or `vankisi.ge`,
never `vankisi.localhost:5174`. Registration refuses a scheme or path and
strips a port (`vankisi.localhost:5174` is stored as `vankisi.localhost`), the
same normalization the public Host lookup uses.

Which port a frontend's dev server listens on is a fact about the developer's
machine, so it is backend environment configuration keyed by the frontend
identity (`siteKey`), not a database field:

```bash
# apps/backend/.env (development); restart the backend after changing it
CUSTOM_WEBSITE_LOCAL_FRONTENDS=vankisi-web=5174,custom-b-web=5176
```

| Rule | Behaviour |
| --- | --- |
| Local frontend URL | `http://<the Venue's ACTIVE .localhost domain>:<port mapped to its siteKey>/` |
| Production (`NODE_ENV=production`) | Setting ignored; `localFrontend` absent from the Platform view; no port or `localhost` in any URL |
| Unmapped identity | `NOT_CONFIGURED`: no URL, **Check now** refused (409) with the exact line to add. There is no default port. |
| No identity / no `.localhost` domain | `NO_SITE_KEY` / `NO_LOCAL_DOMAIN` |
| Malformed, out-of-range (not 1024–65535), duplicated or port-clashing entries | Dropped and listed as problems in the panel |
| `CUSTOM_WEBSITE_DEV_PORT` (former single global port, default 5176) | No longer read; flagged in the panel if still set |
| Tenant authority | None. The check connects to 127.0.0.1 only, with the domain as Host; the backend still resolves the Venue from that Host. |

In development a Venue with an ACTIVE `.localhost` domain is checked at its
local frontend; one without is checked at its primary domain as in production.
Platform → Venue → Website → Custom website shows **Local frontend** (URL or
*Not configured* with **Configure local development**), the public URL, and
opens the local frontend from **Open website**. Owners never see any of it.

Each local frontend proxies `/api` to the backend with `changeOrigin: false`
(Vite), so the backend receives `Host: <domain>:<port>`, strips the port and
resolves the Venue; no forwarded-host trust, Venue id or header is added.

### Vankisi's binding

Vankisi is an existing live CUSTOM site, so steps 1–3 and 5–7 are already done
in production. The binding migration recorded it `ACTIVE` without a site key.
The intended operator state is:

| Setting | Value |
| --- | --- |
| Website implementation (mode) | `CUSTOM` |
| Custom frontend identity (`siteKey`) | `vankisi-web` |
| Setup status | `ACTIVE` |
| Domains | Every hostname that reaches the backend for Vankisi, `ACTIVE` (including `www.` if served) |

The one remaining action is to open Platform Admin → Venues → Vankisi →
Website → **Custom website**, enter `vankisi-web` in **Custom frontend
identity**, leave **Setup status** at `ACTIVE`, and **Save custom setup**. The
save is audited and is refused (409, with the checklist) if Website access,
CUSTOM mode or an active domain is missing. No database edit or migration sets
it, and `apps/vankisi-custom-web` never reads it: the key is operator metadata,
the Host still decides the Venue, and the frontend holds no Venue id.

## 4. Shared public website API

A CUSTOM frontend reads exactly what a SAAS site reads: the shared website
foundation. Contract, capability model and the full domain matrix are in
[WEBSITE_FOUNDATION.md](WEBSITE_FOUNDATION.md). In short:

| Route | Gate | Use |
| --- | --- | --- |
| `GET /api/website/venue` | Host, WEBSITE, launched | `mode`, `site {key,status}` (null for SAAS), public profile, `info` (hours, contact, socials, gallery), `capabilities` |
| `GET /api/website/venue/menu` | + MENU | Canonical menu with the owner's website presentation |
| `GET /api/menu`, `/api/menu/:slug` | + MENU | Vankisi's original menu shape over the same catalog |
| `GET /api/tables*`, `POST /api/tables/reservations` | + RESERVATIONS | Bookable tables, availability, anonymous occupancy map |
| `POST /api/bog/create-order` | + RESERVATIONS, ONLINE_PAYMENTS | Paid booking; account from session cookie |
| `GET /api/bog/check-reservation-status/:id` | Host + stored payment | Payment result after redirect |
| `POST /api/bog/payment-callback` | BOG signature | Server-to-server settlement |
| `POST /api/auth/signup`, `/signin` | + CUSTOMER_ACCOUNTS | Global website customer identity, offered per site |
| `GET /api/user/reservations` | cookie + CUSTOMER_ACCOUNTS | This site's bookings of the signed-in customer |

"Launched" means CUSTOM (provisioned) or a published SAAS site. The generic
page routes (`/api/website/bootstrap|menu|preview`) stay SAAS-only; for a
CUSTOM host `bootstrap` still answers only `{schemaVersion:2, mode:"CUSTOM"}`.
Capabilities are the shared ones (MENU, HOURS, RESERVATIONS, GALLERY,
CUSTOMER_ACCOUNTS, ONLINE_PAYMENTS; events, banquets and online ordering are
listed as not built) and mean the same in both modes. One-off custom behaviour
(Vankisi's 3D floor plan, its static events page) stays in that frontend.

## 5. Host authority and hosting

A custom frontend **must** be served so that `/api` is on its own origin and
the proxy preserves the Host:

```nginx
server {
  server_name restaurantx.ge;
  root /srv/restaurant-x-web/dist;
  location / { try_files $uri /index.html; }
  location /api/ {
    proxy_pass http://vynic-backend:3000;
    proxy_set_header Host $host;              # or set TRUST_PROXY_HOST=true
    proxy_set_header X-Forwarded-Host $host;  # and rely on this instead
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

Hosting a frontend on another origin that calls `api.vynic.ge` directly is not
supported: the backend would see `api.vynic.ge` as the Host (no Venue, or the
wrong one), and the site's SameSite=Strict session cookies would not be sent.
No header, query or signed browser token was added to work around this, because
same-origin proxying already gives a server-owned Host at no extra trust.

With `TRUST_PROXY_HOST=true`, only the first `X-Forwarded-Host` entry is read,
and when present it is the only candidate (no fallback to the direct Host).
Only enable it when the proxy overwrites the header.

**Vankisi deployment.** The repository holds only `apps/vankisi-custom-web/vercel.json`
(SPA rewrite) and the app's own `npm run build` → `dist/`; nothing in Git names
the directory. Any setting outside Git that points at the old
`apps/venue-web` path must be changed to `apps/vankisi-custom-web`, with the
build command (`npm run build`), output (`dist`) and environment left as they
are: a Vercel project's Root Directory, or a server's checkout/build path. The
API transport is unchanged: it calls same-origin `/api` unless `VITE_API_URL`
is set (the cross-origin case above).

## 6. CORS / origins

Allowed: explicit `FRONTEND_URL`/`ALLOWED_ORIGINS`, development LAN clients,
and any request whose `Origin` host:port equals its authoritative Host
(`website/tenancy/same-origin.ts`). The last rule makes every registered custom
domain work through its proxy without editing deployment env, and needs no
database lookup: a page cannot make a browser send another site's Origin, and
unregistered hosts still resolve no Venue. Everything else is refused before a
handler runs. There is no wildcard.

## 7. Payments

```text
Host → CUSTOM Venue → ONLINE_PAYMENTS effective → Venue PaymentIntegration → BOG
```

Each Venue has its own encrypted, versioned integration; the booking stores the
integration revision; the return origin must be an ACTIVE domain of that Venue;
callbacks and status checks resolve the stored reservation, not the browser.
The frontend never sends prices, credentials, Venue ids or account ids.
Proved per Venue in `custom-website.integration.spec.ts` (bank auth used A's
client id for A's booking, B's for B's).

## 8. Customer Dashboard

CUSTOM owners see a read-only **Custom website** card: status (active / setup
in progress / ready / needs attention) and their active domains. The generic
editor, publish, preview and SaaS address request are absent. Restaurant
profile, Menu (the full catalog editor for a Website-only package, §3a;
website presentation applies to `/api/website/venue/menu`), hours, gallery,
contacts, payments and subscription stay
available.
CUSTOM Trial: the operator assigns it and chooses CUSTOM; the owner sees setup
status, no generic renderer ever serves the Venue, and Trial expiry denies
WEBSITE exactly as for SAAS (public API 403, owner website settings refused).

## 9. Security review

| Check | Result |
| --- | --- |
| Host spoofing | Host is the authority by design; a spoofed Host can only read that Host's own public data. |
| Forwarded host | Ignored unless `TRUST_PROXY_HOST`; then sole authority, first entry only. |
| Direct API calls | Same guards as browser calls; `venueId`, `X-Venue-Id`, `X-Domain`, `?venueId` ignored (tested). |
| Unknown / SAAS / unentitled host | 404 / 404 / 403 on custom routes (tested, real server). |
| WebsiteUser scoping | Global identity; bookings Venue-scoped; account link from cookie only; admin bound to one Venue. |
| Payment scoping | Per-Venue credentials and return origins; callback via stored reservation. |
| CORS | No wildcard; same-origin rule + allow-list. |
| Cross-Venue | A cannot read B's profile, menu, bookings or tables (tested). |
| **Open**: email-linked bookings | `/api/user/reservations` also shows guest bookings whose email equals the account's; signup does not verify email, so an account registered with someone's unused email sees their guest bookings at that Venue. Needs email verification; changing it alters Vankisi behaviour, so not changed here. |
| **Open**: `/api/auth/verify` role | Still reports `SUPER_ADMIN` on every site; data access is scoped, the UI hint is not. |
| **Open**: booking race | No transactional hold (pre-existing). |

## 10. Remaining gaps

- Page text/design for CUSTOM stays in each bespoke frontend by design.
- Service fee (10%) and GEL are hardcoded in `BogService`.
- Vankisi validates `vankisi-web` for supported shared information; the
  operator checker also compares its emitted manifest/reviewed build and stable
  Venue identity. This is not a new global public launch gate. Production host
  and complete functional acceptance remain separate release checks.
- No deployment automation, DNS/TLS automation or monitoring: status is an
  operator attestation and availability is an on-demand check that is not
  stored (no history or alerts).
- Remove stale `BOG_*`/`TBC_*` and per-domain `ALLOWED_ORIGINS` entries from
  deployment env after verifying the same-origin proxy.

## 11. Developer workflow for a new custom site

See [templates/custom-site/README.md](../templates/custom-site/README.md) and
[packages/website-client/README.md](../packages/website-client/README.md).
The starter is the default for new clients, not a requirement: a bespoke app
like Vankisi's may call the shared routes directly, as long as it is served
behind the same-origin proxy (§5) and holds no Venue id.

| Step | Who | What |
| --- | --- | --- |
| 1 | Operator | Create/activate Venue; assign Website Trial/ACTIVE. |
| 2 | Operator | Select CUSTOM; record `siteKey` = `restaurant-x-web`. |
| 3 | Developer | `cp -R templates/custom-site apps/restaurant-x-web`; set `SITE_KEY`; `npm install`. |
| 4 | Operator (local DB) | Register `restaurant-x.vynic.localhost` for the Venue (or run the local fixture). |
| 5 | Developer | Pick a free port (e.g. 5176); add `restaurant-x-web=5176` to backend `CUSTOM_WEBSITE_LOCAL_FRONTENDS`; `PORT=5176 npm run dev`, open `http://restaurant-x.vynic.localhost:5176`; consume only `@vynic/website-client`. |
| 6 | Developer | Design; add bespoke modules inside the app only. |
| 7 | Operator | Register production `restaurantx.ge`; owner sets BOG with that return origin. |
| 8 | Developer/DevOps | Build, deploy behind a host-preserving `/api` proxy, DNS/TLS (manual). |
| 9 | Operator | Verify bootstrap for the domain; mark READY, then ACTIVE. |

Automatic: tenancy, entitlement/Trial enforcement, capability derivation,
misattachment detection, audit. Manual: frontend code, deployment, DNS/TLS,
status attestation.

## 12. Local proof

```bash
# fresh disposable database (never a named or live one), migrated
createdb -h 127.0.0.1 -p 55439 disposable_custom_local
DATABASE_URL=postgresql://…/disposable_custom_local npx prisma migrate deploy
CUSTOM_WEBSITE_LOCAL_DATABASE_URL=postgresql://…/disposable_custom_local \
PAYMENT_INTEGRATION_MASTER_KEY=<64 hex> \
  npx ts-node -T scripts/seed-custom-websites-local.ts --confirm-local
# run the backend on that DB, then:
cd templates/custom-site
VITE_SITE_KEY=custom-a-web VYNIC_WEBSITE_API=http://127.0.0.1:3000 npm run dev
# http://custom-a.vynic.localhost:5176 → Custom A Grill, its menu and tables
# http://custom-b.vynic.localhost:5176 → refused: this build is not B's frontend
# custom-a/b are Website-only (menu CLOUD); custom-p includes POS (menu POS).
# Backend env CUSTOM_WEBSITE_LOCAL_FRONTENDS=custom-a-web=5176 makes
# Platform → Check now reach A; B stays NOT_CONFIGURED until mapped.
# Vankisi alongside: apps/vankisi-custom-web `npm run dev` →
# http://vankisi.localhost:5174 with vankisi-web=5174 in the same setting.
```

Automated: `CUSTOM_WEBSITE_TEST_DATABASE_URL=<fresh disposable_*> npx jest
src/website/custom/custom-website.integration.spec.ts`.
