# Public website tenancy

**Step 4B2B.** How a public restaurant-website request is attributed to a Venue,
what that Venue then owns, and what is deliberately still open.

Companion documents: [TENANT_SCOPING.md](TENANT_SCOPING.md) (POS operational
ownership), [MANAGER_TENANT_AUTH.md](MANAGER_TENANT_AUTH.md) (Manager identity),
[PRODUCT_ENTITLEMENTS.md](PRODUCT_ENTITLEMENTS.md) (Plan / Feature / WebsiteMode),
[CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md) (still open),
[FUTURE_SAAS_WEBSITE.md](FUTURE_SAAS_WEBSITE.md) (not built).

---

## The boundary

```
request Host (or trusted X-Forwarded-Host)
        ↓  normalized: lowercased, port stripped, malformed refused
   VenueDomain.hostname          ← server-owned registration
        ↓
      Venue                      ← must be ACTIVE
        ↓
   Organization
        ↓
 effectiveFeatures(venueId)
        ↓
      WEBSITE?                   ← FeatureGuard, 403 if not
        ↓
 Venue-scoped public data
```

A public visitor has no credential, so there is nothing to authenticate. The
host is what identifies the restaurant, and the host is only ever *looked up* —
`VenueDomain` is written by the platform, never by a caller.

**A venueId in a request body, query string, or client-chosen header is not
tenant authority and is never read.** No public endpoint accepts one. The guard
overwrites whatever a caller put on the request with what the host resolved to.

---

## Domain identity

`VenueDomain` is intentionally the smallest model that answers "which restaurant
is this?".

| Field | Why |
|---|---|
| `hostname` | Globally `@unique`. One name can never resolve to two Venues. |
| `venueId` | FK `ON DELETE RESTRICT` — a Venue with domains cannot be deleted, so ownership is never silently orphaned. |
| `status` | `DISABLED` stops serving the site while keeping the name reserved. |

Not modelled: DNS records, TLS certificates, registrar state, verification
challenges. Those are deployment concerns, and none of them is needed to decide
which Venue a request belongs to.

### The bootstrap hostname

The repository contains no evidence of the production hostname for the existing
Vankisi site — `apps/venue-web/` resolves its API from `window.location`, and
every committed environment file uses placeholders. Guessing a live domain into
a migration would be a bad way to find out we guessed wrong, so the Step 4B2B
migration registers the bootstrap Venue under:

```
vankisi.localhost
```

`.localhost` is reserved by RFC 6761 and can never collide with a real domain.
**Registering the production hostname is a deployment configuration step**, one
row in `VenueDomain`. Until then, production requests on the real domain resolve
no Venue and are refused — which is the correct failure, not a regression to
hide behind a default.

### Host trust and reverse proxies

`apps/venue-web/` calls `/api` on its own origin in production, so the process
receives the site's hostname in `Host` directly. If a deployment terminates TLS
at a proxy that rewrites `Host`, set:

```
TRUST_PROXY_HOST=true
```

Only then is `X-Forwarded-Host` read, and only its first entry — the host the
client actually asked for. Without that flag the header is ignored entirely,
because any client can set it and would otherwise get to pick its own
restaurant. A deployment that serves the API from a *separate* hostname (via
`VITE_API_URL`) must register that hostname, since it is the one the backend
sees.

Normalization refuses rather than repairs: a value carrying a scheme, path,
query, fragment, userinfo, or whitespace resolves to nothing.

### Development fallback

Local work happens on `localhost`, a loopback literal, or a LAN address — none
of which can be a registered public domain. When `NODE_ENV !== 'production'` and
the request host is one of those, resolution retries against `WEBSITE_DEV_HOST`
(default `vankisi.localhost`).

It is transitional, it is environment-gated, and it applies only to addresses
that cannot exist publicly. **Production fails closed on an unknown host** —
there is no global "localhost means Vankisi" rule.

---

## CUSTOM and SAAS share this boundary

`WebsiteMode` describes how an entitled Venue's site is *built and served*. It is
not how its tenant is established.

| | CUSTOM | SAAS |
|---|---|---|
| Venue resolution | `VenueDomain` | `VenueDomain` |
| Entitlement | `WEBSITE` | `WEBSITE` |
| Public APIs | same | same |
| Frontend | a bespoke build (today, `apps/venue-web/`) | one generic app, not yet built |

Nothing in the backend branches on `CUSTOM` vs `SAAS` to decide a tenant. The
resolver returns `configuredMode` as information for a caller that needs it; the
question "may this Venue serve a website at all" is the `WEBSITE` entitlement,
and `VenueEntitlementsService.websiteAccess()` reports the two together
(`entitled`, `configuredMode`, `effectiveMode`, `consistent`). A configured mode
that contradicts entitlement is reported, never silently rewritten.

---

## Public request context

```ts
interface WebsiteTenantContext {
  tenant: TenantContext;   // the same shape POS and Manager produce
  hostname: string;
  configuredMode: WebsiteMode;
}
```

There is **one** `TenantContext` in the codebase (`src/tenancy/tenant-context.ts`).
A public request is not forced through `PosAuthContext` or `ManagerAuthContext` —
a visitor is not a Device and not a staff member — but it produces the same
tenant, so `requestTenant()` and `FeatureGuard` work identically for all three:

```
POS Device auth    ─┐
Manager staff auth  ├─→ TenantContext ─→ tenant-scoped services
Website host       ─┘
```

`WebsiteTenantGuard` writes `request.websiteTenant`; it must be listed before
`FeatureGuard`, which reads it.

Note that `WebsiteAuthGuard` puts a `WebsiteUser` on `request.user`. That is a
customer, not a tenant: it carries no `venueId`, so `requestTenant()` yields
nothing from it rather than mistaking it for one.

---

## Booking model ownership

| Model | Classification | `venueId` | Why |
|---|---|---|---|
| `WebsiteTable` | Venue-owned root | **added** | Queried directly by `websiteTableNumber`, a per-restaurant customer-facing label. |
| `WebsiteReservation` | Venue-owned root | **added** | The booking root, and the tenant a payment callback resolves through. |
| `WebsiteReservationTable` | Tenant child | inherited | Only ever created from tables already scoped to the reservation's Venue. |
| `WebsiteUser` | Global/shared | **not added** | See below. |

### Venue-aware uniqueness

- `WebsiteTable(websiteTableNumber)` → `WebsiteTable(venueId, websiteTableNumber)`.
  Two restaurants may both publish `table1`.
- `WebsiteReservation(posReservationId)` → `WebsiteReservation(venueId, posReservationId)`.
  Each Venue's own POS issues those ids; the same number in two restaurants is legitimate.

`websiteTableNumber`, `posFloor`, `posTableNumber` and `WEBSITE_TABLE_MAPPINGS`
are **unchanged**. Customer-facing identifiers and the legacy mapping keep
working exactly as before; only their uniqueness scope moved.

### Canonical Table UUID

`WebsiteTable` still maps to POS through `posFloor` + `posTableNumber`, encoded
by the shared table-identity contract. Adding an optional reference to the
canonical physical `Table` UUID was considered and **not** done: it is not
required for tenant integrity now that both sides are Venue-owned, and changing
the booking mapping would risk exactly the behaviour this step promised to
preserve. Recorded as possible later work, not a gap in the boundary.

### WebsiteUser stays global

A customer account is one identity that may eventually book several restaurants.
Duplicating a person per Venue would mean duplicate passwords, duplicate phone
uniqueness, and a migration to undo later. So:

```
WebsiteUser        = one global customer identity
WebsiteReservation = a Venue-owned booking
```

`/api/user/profile` is not Venue-scoped, because the account is not. But
`/api/user/reservations` **is**: a restaurant's site shows the bookings made at
that restaurant. The account is global; the bookings it can see through a given
site are not.

---

## Payment callbacks

A payment provider has no reason to know a website hostname, and BOG's callback
does not carry one. Requiring a host there would break payments while adding no
authority.

```
BOG callback  →  external_order_id  →  WebsiteReservation  →  Venue
```

`external_order_id` **is** the reservation's UUID, so tenant authority comes from
a server-owned booking row, not from anything the callback asserts. The callback
signature is verified against the raw signed bytes before any state is touched —
unchanged from before. `updateReservationPaymentStatus` now reads the Venue and
Organization off the reservation it loaded and passes that tenant to the POS
bridge.

`/api/bog/create-order` *does* come from a browser on a restaurant's site, so it
resolves a Venue from the host and requires `WEBSITE`, like the rest of the
public product surface.

---

## What is enforced where

| Endpoint | Host → Venue | `WEBSITE` | Notes |
|---|---|---|---|
| `GET /api/menu`, `GET /api/menu/:slug` | yes | yes | |
| `GET /api/tables`, `/availability`, `/availability/:n` | yes | yes | |
| `POST /api/tables/reservations` | yes | yes | Foreign table numbers are simply not found. |
| `GET /api/tables/reservations` | yes | yes | Public map and SUPER_ADMIN list, both Venue-scoped. |
| `POST /api/bog/create-order` | yes | yes | |
| `GET /api/bog/check-status/*`, `POST /api/bog/payment-callback` | no | no | Tenant from the reservation record. |
| `GET /api/user/reservations` | yes | yes | Global account, Venue-scoped bookings. |
| `GET/PATCH /api/user/profile` | no | no | Global customer identity. |
| `POST /api/auth/*` | no | no | Global customer identity; reads no restaurant data. |
| `POST /sync/*`, Device auth | **never** | **never** | Entitlement must not gate POS → Cloud sync. |

---

## Deferred, deliberately

- **Reservation race / `TableHold`.** Availability is still checked and then
  written without a hold. Tenant isolation and booking correctness are separate
  changes; this step did not touch locking, statuses, expiry, pre-orders, slot
  durations, the availability algorithm, or BOG semantics.
- **POS bridge addressing.** `PosCallbackClient` still reaches a single legacy
  LAN connection, so `fetchPosReservations()` is not Venue-addressed. It can only
  widen availability, never expose another Venue's stored data. Belongs with the
  Cloud → Edge work queue.
- **Domain management APIs.** Registering or disabling a domain is a mutation
  that needs a platform-admin authorization boundary, and that boundary does not
  exist yet. No write endpoint was created rather than creating an unprotected
  one. Domains are seeded by migration and by test fixtures today.
- **Custom website runtime.** How a bespoke site is built, hosted and deployed is
  still open — see [CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md). Domain
  → Venue resolution did not require deciding it.
- **Generic SaaS frontend.** Not built. See [FUTURE_SAAS_WEBSITE.md](FUTURE_SAAS_WEBSITE.md).
- **Wildcard / subdomain routing.** Matching is exact. A per-tenant subdomain
  scheme is a design decision, not a default.
- **`LEGACY_MANAGER_TENANT`.** Now gone from every website service. Its remaining
  callers are the Manager PIN login candidate scan, the legacy shared-key POS sync
  path, notification raising, and bootstrap seeding. It retires when POS runs
  entirely on Device credentials, Manager login discriminates Venue, and
  notification raising carries a tenant.
