# Website Phase W3 — the generic SaaS restaurant website

## Scope

W3 turns the W2 Website Core into a product a restaurant can actually publish:

- `apps/restaurant-web`, one generic frontend that serves every SaaS Venue;
- an owner editing/preview/publish experience in the Customer Portal that
  previews the *real* frontend, not a summary of the draft;
- a website presentation layer over the existing operational menu.

`apps/vankisi-custom-web` is untouched. It stays the bespoke Vankisi CUSTOM site, keeps
its own reservation/payment path and its W1 BOG semantics, and is never served
by the generic frontend. `website/auth`, `website/user`, `website/reservation`
and `website/payment` are unchanged and still back it.

Out of scope and not started: online ordering, SaaS online payments, generic
customer accounts/loyalty, KDS, a Go Edge website transport, custom-domain
DNS/TLS automation, a page builder, additional themes, a reservations redesign
and a full Restaurant Backoffice.

## Product boundary

```text
CUSTOM website                    SAAS website
apps/vankisi-custom-web           apps/restaurant-web
→ bespoke Vankisi frontend        → one generic frontend, many Venues
→ website/auth, user,             → website/core + shared public
  reservation, payment              capabilities
```

Both resolve their Venue the same way — `Host → VenueDomain → Venue` — and
neither may take a tenant from a query, body or client header. They are separate
frontend products that share backend capabilities, not two builds of one site.

## `apps/restaurant-web`

React + Vite, no router dependency: `/` is the public site and `/preview` is the
owner draft preview. There is no demo Venue, no `?venueId=`, and no fallback
restaurant — a request that cannot prove which restaurant it belongs to gets the
unavailable page.

It calls exactly two same-origin paths (`/api/website/bootstrap`,
`/api/website/menu`, or their `preview/` counterparts). Same-origin matters:
the dev/production proxy forwards the browser's Host unchanged, and that Host is
the tenancy authority. `vite.config.ts` therefore sets `changeOrigin: false`
deliberately. An absolute API base would replace the restaurant's hostname with
the backend's own and serve every host the same site.

States are distinct and none of them is dressed up as content:

| Backend answer | Page |
| --- | --- |
| SAAS, published | the restaurant, rendered by its `themeKey` |
| `mode: CUSTOM` | "custom website, managed separately"; no generic content, no menu request |
| 404 (unknown/disabled host, NONE, unentitled, unpublished) | "not available" |
| unknown `schemaVersion` | "could not be rendered" |
| transport failure | retryable error |

Georgian is the default language with English available; the toggle changes only
the frame and which authored name is shown, and never refetches or changes the
restaurant. Content is rendered as text — the content contract stores no HTML
and the frontend interprets none.

### The `classic` theme

One production-quality presentation, not a page builder and not several thin
themes. Fixed section order — header/nav, hero, about, menu, gallery, hours,
contact/socials, footer — where each section removes itself when the restaurant
has nothing to put in it, so a sparse draft and a complete site are both
coherent pages.

`themeKey` travels in the published content and `src/theme/registry.ts` maps it
to components. A second theme is one registry entry plus its components: the
public data model, the owner editor and the tenancy path do not change. An
unknown key falls back to `classic` rather than rendering nothing.

Presentation requirements met: responsive at 390 / 768 / 1280+ with no
horizontal overflow (`overflow-x: hidden` on `body` plus a `--shell` clamp),
a skip link, visible focus rings on both light and dark surfaces, `prefers-
reduced-motion` honoured, and font stacks that list Georgian-capable families
first. No webfont is loaded: the site must read correctly in Georgian and
English offline and on first paint. Adding one is a deployment choice.

### Restaurant identity

Name, branch, address, phone, timezone and currency come from the Venue profile
on every request and are never copied into website content. Legal ID, login
code, ownership and payment fields never enter a public payload. Logo is website
content because the Venue profile has no logo field today; if one is added, the
logo should move to it rather than being duplicated.

## Menu publication

The website keeps no menu of its own. `MenuItemWebsitePresentation`
(migration `20260926120000_website_menu_presentation`) answers one question per
*existing* `MenuItem`: whether and how it appears publicly.

```text
MenuItem                        MenuItemWebsitePresentation
POS/Cloud operational product   visibleOnWebsite, displayName?, description?,
identity, price, category,      imageUrl?, sortOrder
variants
```

- The row is keyed by `menuItemId` and cascades with the item, so an item that
  is deleted operationally cannot leave a public record behind. An item that
  stops being returned by the operational tree simply stops being published.
- `venueId` is carried on the row so a presentation write is scoped to one
  restaurant; every submitted id is proved to belong to the resolved Venue
  inside the transaction, and a borrowed id writes nothing at all.
- **No row means visible under the operational name.** A restaurant that has
  never opened the editor still gets a complete menu; the owner hides items
  explicitly. This is the documented default, not an accident.
- Effective order is `presentation.sortOrder ?? item.sortOrder`, so an untouched
  item keeps its POS position.
- Categories and subcategories with nothing visible are dropped rather than
  rendered as empty headings.
- The public menu shows categories, subcategories, items, variants/sizes, the
  current published price, and the optional description and image. Prices are
  read live; nothing is snapshotted at publish time.
- `showMenu: false` answers an explicitly empty menu (`enabled: false`) rather
  than 404, so "this restaurant does not publish a menu" stays distinguishable
  from "this host has no website".

The portal editor writes presentation only. It does not create, rename, reprice,
delete, or touch recipes, inventory mapping, kitchen routing or POS pricing
rules — those stay with the POS/Cloud menu authority.

## Draft preview

Owner preview renders the real frontend against the draft.

```text
Customer Portal → POST .../website/preview-session
                → { token, expiresAt, previewOrigin }
                → restaurant-web /preview#token=…
                → GET /api/website/preview/bootstrap + /preview/menu
```

- The token is its own principal type (`WEBSITE_PREVIEW`) and audience
  (`vynic-website-preview`), valid 30 minutes, bound to one Venue. It is not the
  owner's portal JWT: a public product should never hold a full account
  credential. Neither token works in the other's place, and both directions are
  tested.
- Ownership is proved again at redeem time, so a deactivated account or a Venue
  that has changed hands is refused inside an already-issued window.
- The token travels in the URL **fragment**, which browsers never send to a
  server, so preview authority does not reach proxy or request logs. The
  frontend moves it into `sessionStorage` and strips it from the address bar.
- The preview Venue comes from the token, not the host, so a preview opened on
  one restaurant's hostname still shows only the token's restaurant.
- Preview responses are `Cache-Control: private, no-store` plus
  `X-Robots-Tag: noindex, nofollow`; the page is `noindex, nofollow` with no
  canonical and no `og:image`. Preview never publishes anything.
- `SAAS_WEBSITE_PREVIEW_ORIGIN` is deployment-owned. Without it the portal says
  preview is not configured rather than guessing an address.

## Owner editor

`apps/platform-web/src/customer/WebsiteSettings.tsx` is a sectioned workspace,
not one long form: General, Hero, About, Theme, Menu, Gallery, Hours, Socials,
SEO and Publishing (`პუბლიკაცია`). The Georgian UI matches the rest of the
portal.

Always visible: mode, publication status, saved revision, published revision and
time, whether unpublished changes exist, and the registered addresses. Save,
preview and publish stay three separate acts — preview and publish are disabled
while edits are unsaved — and `expectedRevision` travels with every write, so an
edit made in another session is refused with 409 and offered a reload instead of
being silently overwritten.

## Media contract

Website content stores media **references**, never bytes:

- an absolute HTTPS URL (someone else's hosting), or
- a deployment-managed path matching `/media/<...>` — no traversal, no query, no
  escapes — which the frontend resolves against its own origin.

`http:`, `data:`, `javascript:`, credentials in URLs and anything outside
`/media/` are rejected by the content validator and by the menu presentation
validator. A large inline base64 image therefore cannot be written into website
content or the presentation table at all.

Local development ships placeholder SVGs in
`apps/restaurant-web/public/media/sample/`, served by the frontend's own origin.
They are fixtures, not product assets.

Owners can now upload PNG/JPEG/WebP logos and main photos through the authenticated website
editor. The backend validates and re-encodes files as bounded WebP images and
returns an immutable `/media/website-logos/<random-id>.webp` reference. Uploading
does not save or publish the draft. Production requires a persistent
`WEBSITE_MEDIA_DIR` shared by backend replicas and proxying that media prefix to
the backend on portal, public and preview origins. These are public logo assets;
website content/bootstrap still requires the existing Host or preview authority.
See `docs/WEBSITE_OWNER_EDITOR_UX.md` for deployment and retention details.

Gallery and about images remain references; there is no object-storage provider,
general gallery uploader or server-side fetching of external image URLs.

## SEO and page metadata

Metadata is applied at runtime from the published state in `src/seo/
documentHead.ts`: title (`seoTitle`, else name + hero), description, canonical,
Open Graph basics, `og:street_address`/`og:phone_number` from the public Venue
profile, and the logo as favicon.

Indexability is decided in one place and the safe answer is the default.
`index, follow` requires proving the page is published, public SAAS content;
everything else — draft preview, CUSTOM host, unpublished, unentitled, disabled,
load failure — is `noindex, nofollow`. `index.html` ships `noindex` so a page
is never briefly indexable before its state is known, and `robots.txt`
disallows `/preview` outright.

Canonical is always the site's own address on the current origin. A slug change
leaves the previous hostname registered as an alias, so a visitor arriving on an
old address is pointed at one canonical page instead of the content being
indexed twice.

**Deployment-specific:** this is a client-rendered SPA, so metadata is set after
the JavaScript runs. Modern search crawlers render it; simpler crawlers and some
link unfurlers will see `index.html` (deliberately `noindex`) instead. A
deployment that needs server-rendered metadata should put SSR or a prerenderer
in front of the same bootstrap contract — no content or tenancy change is
required. Advanced SEO tooling is out of scope.

## Caching

Public bootstrap and menu responses are `Cache-Control: private, no-cache` with
a strong `ETag` over exactly the bytes that would be sent, and answer `304` when
the client already has that version.

This is revalidate-always rather than a timed public cache, on purpose: every
request still reaches the backend, so removing an entitlement, switching a Venue
to CUSTOM or disabling a domain stops the site on the very next request, and a
newly published revision is observable immediately with no redeployment and no
cache to purge. What revalidation buys is the body, not the round trip.

`private` keeps shared proxies out. A host-keyed shared cache would first need
publication *and* entitlement invalidation designed, so it is not enabled — this
satisfies the W2 requirement that no-store be preserved until that design
exists, while still giving revision-based efficiency. Preview stays
`private, no-store`.

## Local development

Four processes, none of which may touch `vankisi_database`:

```text
backend                   :3000            apps/backend           npm run start:dev
backend website harness   127.0.0.1:3102   apps/backend/scripts/serve-website-w3-local.ts
restaurant-web (SAAS)     :5175            apps/restaurant-web    npm run dev
platform-web (portal)     :5173            apps/platform-web      npm run dev
vankisi-custom-web        :5174            apps/vankisi-custom-web npm run dev
```

`restaurant-web` proxies `/api` to `http://127.0.0.1:3000` by default — the
ordinary backend. The harness below is an alternative for the disposable
fixture, selected explicitly:

```sh
VYNIC_WEBSITE_API=http://127.0.0.1:3102 npm run dev
```

Its port is pinned (`strictPort`), because the fixture URLs and
`SAAS_WEBSITE_PREVIEW_ORIGIN` both name 5175; drifting to another port would
make preview links open a dead address.

### Disposable database, from `apps/backend`

Homebrew PostgreSQL 17 on macOS; use equivalent binaries elsewhere. If a
cluster is already listening on 55439, reuse it and create only the database.

```sh
export LC_ALL=C
/opt/homebrew/opt/postgresql@17/bin/initdb -D /tmp/vynic-w3-pg -A trust
/opt/homebrew/opt/postgresql@17/bin/pg_ctl -D /tmp/vynic-w3-pg -l /tmp/vynic-w3-pg/server.log -o '-h 127.0.0.1 -p 55439' start
/opt/homebrew/opt/postgresql@17/bin/createdb -h 127.0.0.1 -p 55439 vynic_w3_disposable
export W3_TEST_DATABASE_URL="postgresql://$(id -un)@127.0.0.1:55439/vynic_w3_disposable"
DATABASE_URL="$W3_TEST_DATABASE_URL" npx prisma migrate deploy
npx prisma generate
node -r ts-node/register/transpile-only scripts/seed-website-w3-local.ts --confirm-local
node -r ts-node/register/transpile-only scripts/serve-website-w3-local.ts --confirm-local
```

Then run the frontend against it with
`VYNIC_WEBSITE_API=http://127.0.0.1:3102 npm run dev`.


Both scripts require the explicit `W3_TEST_DATABASE_URL` and the exact
loopback/port/database before loading any application dependency. Seed is
repeatable and preserves existing edits. It never touches the real Vankisi Venue
and imports no bank credentials.

The fixture creates the four Venues W3 is proved against and prints each one's
owner email, Venue id and hostnames:

| Venue | Mode | WEBSITE | Expected |
| --- | --- | --- | --- |
| `restaurant-a` | SAAS | enabled | published site, own menu and media |
| `restaurant-b` | SAAS | enabled | published site, different menu |
| `vankisi` | CUSTOM | enabled | CUSTOM marker; not rendered generically |
| `restaurant-d` | NONE | disabled | unavailable |

### Hostnames

Each fixture Venue is registered under two aliases of the same Venue:

```text
<slug>.vynic.local        the deployment suffix publication actually claims
<slug>.vynic.localhost    reserved (RFC 6761); browsers resolve it to loopback
```

The `.localhost` aliases exist so the fixture is browsable with **no
`/etc/hosts` change**, which this phase does not make. Open:

```text
http://restaurant-a.vynic.localhost:5175/     Venue A, generic SaaS site
http://restaurant-b.vynic.localhost:5175/     Venue B, same build, different restaurant
http://vankisi.vynic.localhost:5175/          CUSTOM marker, not generic content
http://restaurant-d.vynic.localhost:5175/     unavailable
```

To use the `.vynic.local` names instead, add them yourself:

```text
127.0.0.1 restaurant-a.vynic.local
127.0.0.1 restaurant-b.vynic.local
127.0.0.1 vankisi.vynic.local
```

`vankisi.vynic.local` here is a local CUSTOM stand-in, not the real Vankisi
site. The real custom frontend is `apps/vankisi-custom-web`, run separately and
unchanged; the generic frontend must never render it.

Checking the JSON contract directly (`.local` can interact with mDNS, so these
bypass DNS without changing the authority):

```sh
curl --noproxy '*' --resolve restaurant-a.vynic.local:3102:127.0.0.1 http://restaurant-a.vynic.local:3102/api/website/bootstrap
curl --noproxy '*' --resolve restaurant-a.vynic.local:3102:127.0.0.1 http://restaurant-a.vynic.local:3102/api/website/menu
```

### Owner portal against the fixture

Sign in at `POST /customer/auth/login` with
`{"email":"restaurant-a@w3.test.invalid","password":"Local W3 owner password!"}`
(B/CUSTOM/D have matching emails and the same disposable password). Use the
token as `Authorization: Bearer …` with the Venue id the seed printed. Do not
use these credentials or the harness outside the local fixture.

The harness sets `SAAS_WEBSITE_PREVIEW_ORIGIN` to
`http://restaurant-a.vynic.local:5175`; change it to the `.localhost` form if
that is the address being browsed.

### Test commands

```sh
# apps/backend
W3_TEST_DATABASE_URL="$W3_TEST_DATABASE_URL" npm test -- --runInBand website
npm run build

# apps/restaurant-web
npm test && npm run lint && npm run build

# apps/platform-web
npm test -- website-settings payment-settings customer.integration product-website.integration feature-guidance
npm run build
```

## Isolation evidence

`src/website/core/website-w3.integration.spec.ts` runs the four-Venue fixture
over real HTTP, owner JWTs, preview tokens and Prisma, and proves:

- each host serves only its own restaurant's profile, content, media and menu,
  with no other restaurant's media prefix or dish names anywhere in the payload,
  and no `legalId`;
- forged `venueId` in query, body and `X-Venue-Id`, and an untrusted
  `X-Forwarded-Host`, change nothing; unknown hosts and `localhost` are 404 with
  no development fallback on these routes;
- a public route never returns a draft, and publishing A leaves B's site and
  menu byte-identical;
- ETag revalidation returns 304, and a new publication changes the validator
  immediately with no purge step;
- an A preview token cannot reach B's draft or menu even when sent on B's host;
  A's owner cannot mint a preview session for B; owner and preview credentials
  are each rejected on the other's routes; an unauthenticated preview is 401;
- a preview token is refused once its account no longer owns the Venue;
- a CUSTOM Venue returns only the marker, its generic menu is 404, and it can
  neither be edited generically nor previewed;
- a NONE Venue cannot edit generically; with SAAS mode but no entitlement it may
  draft and may not publish, and stays 404 publicly;
- a borrowed `menuItemId` is rejected and writes nothing, in both the
  wrong-Venue-route and wrong-owner cases;
- presentation overrides apply while the operational name stays authoritative,
  and `http:`, `javascript:`, `data:`, traversal and non-`/media` references are
  rejected;
- deleting a `MenuItem` removes its presentation row, leaving no orphan;
- `showMenu: false` yields an explicitly empty menu;
- content saved before the v2 fields existed still renders, completed from
  defaults.

`website-core.integration.spec.ts` keeps the W2 proofs (host authority, trusted
proxy, subscription policy, domain claiming, revision conflicts, transactional
audit) against the same disposable database.

`apps/restaurant-web/src/test/` covers rendering, per-host separation, language
switching, metadata and indexability, the schema-version refusal, menu-only
failure degradation, and the full preview token path including fragment
stripping. `apps/platform-web/src/test/website-settings.test.tsx` covers the
sectioned editor, save/preview/publish separation, the presentation editor, the
CUSTOM and unentitled cases, and conflict recovery.

Responsive and accessibility checks were made in a browser against the live
fixture at 390px and desktop widths: no horizontal overflow, Georgian and
English both legible, metadata correct per state.

## Backend notes

- `WEBSITE_SCHEMA_VERSION` is 2. Content gained `logoUrl`, `heroImageUrl`,
  `aboutImageUrl`, `showMenu`, `menuHeading`, `menuIntro`, `contactEmail`,
  `mapUrl` and `footerNote`. Writes still validate strictly; `readWebsiteContent`
  completes stored rows from the defaults and drops unknown keys so an older
  published snapshot keeps rendering. That is read tolerance, not a looser save.
- The W2 fixture scripts were superseded by the W3 ones rather than duplicated;
  the disposable database and env var are now `vynic_w3_disposable` /
  `W3_TEST_DATABASE_URL`.
- No broad backend folder rewrite was done. `customer/`, `payment-integrations/`,
  `website/core/`, `website/tenancy/` and the Vankisi-facing `website/auth`,
  `website/user`, `website/menu`, `website/reservation` and `website/payment`
  keep their current boundaries; see the boundary table above for which product
  owns what.

## What a production rollout still needs

1. A host-preserving reverse proxy in front of `apps/restaurant-web` that
   forwards the browser Host unchanged, strips client-supplied forwarding
   headers, and is the only thing allowed to set `X-Forwarded-Host` when
   `TRUST_PROXY_HOST` is enabled.
2. Production media volume/proxy deployment; general gallery uploads and object storage remain future work.
3. DNS and TLS for `*.<SAAS_WEBSITE_BASE_DOMAIN>`; nothing here performs any
   DNS or TLS action, and changing the suffix does not remap published sites.
4. `SAAS_WEBSITE_PREVIEW_ORIGIN` set to the deployed frontend.
5. A decision on SSR/prerendering if server-rendered metadata is required.

W1's production BOG acceptance and key-management rollout remain a payments
prerequisite. They are not a prerequisite for this read-only website product.
