# Website Phase W2 — generic Website Core

## Scope and authority

The shared backend now supplies generic website content. `apps/vankisi-custom-web` remains
Vankisi CUSTOM; its reservation/payment controllers and W1 integration path are
unchanged. No `apps/restaurant-web`, orders, SaaS payments, Edge website handler,
reservation redesign, page builder or DNS/TLS automation is included.

`GET /api/website/bootstrap` resolves the authoritative HTTP Host through active
`VenueDomain` -> active Venue -> existing WEBSITE entitlement (including subscription
policy) -> mode -> published state. Client Venue IDs in queries, bodies or headers
are not authority. Unknown hosts return 404 even in development: this endpoint
never uses the legacy custom-site localhost fallback. `TRUST_PROXY_HOST` defaults
to false; when explicitly enabled, the first X-Forwarded-Host entry is authoritative
and an unknown/malformed value does not fall back to Host. The deployment must
strip client-supplied forwarding headers and allow only its trusted proxy to reach
the backend. This is an existing deployment trust contract, not domain verification.

- SAAS, entitled, published: versioned payload below.
- CUSTOM, entitled: `{ "schemaVersion": 1, "mode": "CUSTOM" }`, without generic content.
- NONE, disabled entitlement/subscription, disabled Venue/domain, unpublished SAAS:
  404 `Website unavailable`.

All successful public bootstrap and authenticated read/preview responses use
`Cache-Control: private, no-store`. W3 must preserve this until a host-aware cache
with publication and entitlement invalidation is explicitly designed.

## Model and publication

Extends existing `pos.VenueWebsiteConfig`, retaining `WebsiteMode=NONE|SAAS|CUSTOM`.
New `WebsitePublicationStatus=DRAFT|PUBLISHED`, validated `draft`/`published` JSON,
`revision`, `publishedRevision`, `publishedAt`, and globally unique published `slug`.
No existing mode or entitlement is changed by migration
`20260925120000_website_core`; all existing configs start with no generic publication.

> Since `20261010120000_shared_website_foundation`, working hours, contact
> email, map URL, socials and gallery are Venue data in `VenuePublicProfile`
> (live, shared with CUSTOM) and no longer part of the page document; the
> validation rules below still apply to them. See
> [WEBSITE_FOUNDATION.md](WEBSITE_FOUNDATION.md).

Content v1 has slug, `themeKey=classic`, heroTitle/heroSubtitle, about,
seoTitle/seoDescription, workingHours, socials and gallery references. Text lengths,
list lengths, URL schemes and nested fields are validated; unknown fields, HTML
markup and unsupported themes fail. Content is plain text, never trusted HTML.

- Working hours: up to seven `{day, opens, closes}` rows, unique ISO day 1=Monday
  through 7=Sunday, `HH:mm`; omitted day means closed. Closing before opening
  means the following day. Equal times/24-hour opening and split shifts are not
  supported in v1. Hours use the Venue timezone.
- Socials: up to eight `{label, url}` entries; HTTPS URLs without credentials.
- Gallery: up to twenty `{url, alt}` HTTPS references; no upload, server fetching,
  image proxy, asset ownership workflow or media storage is introduced.
- Venue name, branchName, address, phone, timezone and currency come directly from
  Venue. Legal ID, login code, ownership and payment fields never enter the payload.
  Profile edits remain independently effective; draft isolation applies to website
  content, not a duplicate snapshot of shared Venue identity.

A draft save increments revision only. A published website remains PUBLISHED
while a newer draft exists; `hasUnpublishedChanges` reports the difference.
Publishing copies the saved draft into the published snapshot and timestamps it.
`expectedRevision` on both writes rejects stale clients with 409. The config row
lock serializes edits/publishes and Platform mode updates. Publishing the same
revision again is a no-op; audit events and content writes share one transaction.
Audit stores actor, Venue target and revision, not website content. This is revision
tracking, not a complete historical CMS/rollback archive.

Publishing requires active Venue, SAAS mode, WEBSITE access, a saved draft and a
nonempty hero title. Draft editing/preview is allowed in SAAS mode without WEBSITE
access, to prepare content before activation. Owners cannot change mode or grant
entitlements: existing Platform Website/Product access controls do that.

`SAAS_WEBSITE_BASE_DOMAIN` is a deployment-owned suffix, e.g. `vynic.local` locally.
Publishing atomically claims `<slug>.<suffix>` in VenueDomain. A conflicting or
disabled domain is rejected, never reassigned/reactivated. A new draft slug does
not create a public domain until publish. Previous active domains remain aliases
for the same Venue after a slug change; Platform may disable them explicitly.
No DNS/TLS action occurs. Changing the deployment suffix needs an operator rollout;
it does not automatically remap already published sites.

## API contract for W3

```json
{
  "schemaVersion": 1,
  "mode": "SAAS",
  "preview": false,
  "revision": 2,
  "publishedAt": "2026-09-22T10:00:00.000Z",
  "profile": {
    "name": "Restaurant A", "branchName": null, "address": null,
    "phone": null, "timezone": "Asia/Tbilisi", "currency": "GEL"
  },
  "content": {
    "slug": "restaurant-a", "themeKey": "classic",
    "heroTitle": "Welcome", "heroSubtitle": "", "about": "",
    "seoTitle": "", "seoDescription": "",
    "workingHours": [{"day": 1, "opens": "10:00", "closes": "22:00"}],
    "socials": [], "gallery": []
  }
}
```

Authenticated owner routes (CustomerAccount -> Organization -> Venue):

| Route | Behavior |
| --- | --- |
| GET `/customer/venues/:venueId/website` | Mode, entitlement, draft, revision/publication status and registered addresses |
| PUT `.../website/draft` | `{expectedRevision, content}`; strict full content replacement |
| GET `.../website/preview` | Same SAAS content shape, `preview:true`, draft revision, `publishedAt:null`; no public preview token |
| POST `.../website/publish` | `{expectedRevision}`; explicit atomic publication |

Another owner's Venue is 404 for every route. The owner portal adds a focused
Georgian Website section with saved/public state, content form, optional hours,
links/gallery/SEO groups, save, authenticated content review and publish. Unsaved
edits disable preview/publish; failed saves retain edits and offer reload for stale
revisions. CUSTOM/NONE show their mode without generic edit controls. Preview
reviews text/references; it does not pretend to be the future W3 renderer.

## Exact disposable local setup

**Superseded by W3.** `seed-website-w2-local.ts` and `serve-website-w2-local.ts`
were replaced by `seed-website-w3-local.ts` and `serve-website-w3-local.ts`
rather than maintained in parallel; the disposable database and variable are now
`vynic_w3_disposable` and `W3_TEST_DATABASE_URL`, and the fixture covers four
Venues instead of three. Use `docs/WEBSITE_PHASE_W3.md` for the current
commands. The W2 section below records what was validated at the time.

Never use `vankisi_database`. Commands below are from `apps/backend`, using
Homebrew PostgreSQL 17 on macOS. On another OS use equivalent PostgreSQL binaries.
If the earlier W1 cluster is already listening on 55439, reuse that server and
create only the separate W2 database. Otherwise:

```sh
/opt/homebrew/opt/postgresql@17/bin/initdb -D /tmp/vynic-w2-pg -A trust
/opt/homebrew/opt/postgresql@17/bin/pg_ctl -D /tmp/vynic-w2-pg -l /tmp/vynic-w2-pg/server.log -o '-h 127.0.0.1 -p 55439' start
/opt/homebrew/opt/postgresql@17/bin/createdb -h 127.0.0.1 -p 55439 vynic_w2_disposable
export W2_TEST_DATABASE_URL="postgresql://$(id -un)@127.0.0.1:55439/vynic_w2_disposable"
DATABASE_URL="$W2_TEST_DATABASE_URL" npx prisma migrate deploy
npx prisma generate
node -r ts-node/register/transpile-only scripts/seed-website-w2-local.ts --confirm-local
node -r ts-node/register/transpile-only scripts/serve-website-w2-local.ts --confirm-local
```

Both scripts require the explicit W2 variable and exact loopback/port/database
before loading application dependencies. Seed is repeatable and preserves existing
edits. It creates separate owners, A/B SAAS publications and a CUSTOM stand-in;
it never accesses the real Vankisi Venue or imports bank credentials. The isolated
HTTP harness runs real Core/owner authentication at `127.0.0.1:3102`, without
operational workers. It is a development tool, not a production server or full
Customer Portal backend. It uses only disposable local credentials.

Optional `/etc/hosts` entries (not edited by this task):

```text
127.0.0.1 restaurant-a.vynic.local
127.0.0.1 restaurant-b.vynic.local
127.0.0.1 vankisi.vynic.local
```

Open `http://restaurant-a.vynic.local:3102/api/website/bootstrap` and its B/Vankisi
counterparts. These return JSON, because W3 frontend is not built. `.local` may
interact with mDNS; these commands bypass DNS without changing the authority:

```sh
curl --noproxy '*' --resolve restaurant-a.vynic.local:3102:127.0.0.1 http://restaurant-a.vynic.local:3102/api/website/bootstrap
curl --noproxy '*' --resolve restaurant-b.vynic.local:3102:127.0.0.1 http://restaurant-b.vynic.local:3102/api/website/bootstrap
curl --noproxy '*' --resolve vankisi.vynic.local:3102:127.0.0.1 http://vankisi.vynic.local:3102/api/website/bootstrap
```

For local authenticated edits, POST `/customer/auth/login` with
`{"email":"restaurant-a@w2.test.invalid","password":"Local W2 owner password!"}`.
Use the response token as `Authorization: Bearer ...` and the Venue ID printed by
seed for owner routes. B/Vankisi have corresponding emails and the same disposable
password. Do not use these credentials or the harness outside the local fixture.
The regular owner portal consumes the same routes from the normal backend.

Test commands:

```sh
W2_TEST_DATABASE_URL="$W2_TEST_DATABASE_URL" npm test -- --runInBand website-core.integration.spec.ts
npm run build
# from apps/platform-web:
npm test -- website-settings payment-settings customer.integration product-website.integration feature-guidance
npm run build
```

Stop harness with Ctrl-C. Stop the cluster you started using `pg_ctl -D <its-path>
stop -m fast`; do not stop an unrelated database server.

## Validation evidence

All 42 migrations applied to disposable W2 PostgreSQL. Real HTTP/owner JWT/Prisma
proof covers A/B Host isolation, forged IDs and untrusted forwarded hosts, strict
unknown-host denial, CUSTOM marker, NONE/entitlement/subscription/domain/Venue denial,
private draft and authenticated preview, explicit isolated publishing, stale and
concurrent edits, domain collisions, transactional audit rollback, publication audit
idempotency, validation and live profile sourcing. Named local fixture requests
returned A content, B content and CUSTOM with no content. Seed was repeated safely.

Portal workflow tests cover save/preview/publish separation, CUSTOM and entitlement
controls, and conflict recovery. Desktop and 390px compact layout were visually
checked with a disposable mocked component fixture; that fixture was removed.
Backend and portal builds pass. Final validation: 96 tests across 11 Core/W1
payment/website tenancy/entitlement suites; 20 existing public tenant isolation
tests; 14 portal tests across five suites. The old entitlement integration helper
was corrected to list the actual Manager bundle explicitly, rather than implicitly
granting W1 ONLINE_PAYMENTS. No runtime entitlement behavior changed. No live bank
or production access is part of W2 validation.

## Exact W3 prerequisites

All six are implemented; see `docs/WEBSITE_PHASE_W3.md`.


1. Build the separate `apps/restaurant-web` consumer; preserve `apps/vankisi-custom-web`
   and route CUSTOM away from the generic renderer. Handle v1 SAAS, CUSTOM and
   unavailable responses explicitly, with no demo/default Venue fallback.
2. Define the `classic` presentation, mobile/accessibility requirements and asset
   policy. Render text escaped, safe HTTPS links/images only; do not server-fetch
   arbitrary gallery URLs without a separate SSRF-safe media design.
3. Establish host-preserving frontend-to-backend transport (same-origin proxy or
   trusted server transport), local frontend host allowlist, CORS/cookies and
   reverse-proxy header stripping. Never turn a query Venue ID into authority.
4. Specify SSR/SEO metadata, canonical/alias policy, 404 behavior and caching.
   Keep no-store until Host/content revision/entitlement invalidation is proven.
5. Decide authenticated rendered-preview integration; never put owner JWTs in
   public URLs or cache private drafts. Current portal preview is content review.
6. Verify W3 against the same A/B/CUSTOM fixture, entitlement denial and draft
   isolation, plus browser accessibility/responsive checks. Production hosting,
   DNS/TLS and rollout require a separate authorized deployment phase.

Ordering, SaaS payments, reservations and global WebsiteUser/auth changes remain
separate scope decisions. W1 production BOG acceptance/key-management rollout is
still a payment prerequisite, not a requirement to build the read-only W3 renderer.
