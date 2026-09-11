# Manager tenant authentication

Step 4B2A gives Manager requests an authoritative Venue. Step 4B1 scoped the
POS operational mirror to the Venue behind a Device credential; Manager
requests had no equivalent, so every Manager service resolved its tenant from a
hardcoded bootstrap constant. That constant is now gone from the Manager API.

```text
Manager credentials
       ↓
authenticated Staff identity        (who are you?)
       ↓
Venue                               (whose data is this?)
       ↓
Organization
       ↓
effectiveFeatures(venueId) → MANAGER_APP
       ↓
Manager APIs
```

## Four questions, four answers

Kept separate on purpose. Collapsing any pair of them is how a tenancy bug gets
written.

| Question | Answered by |
| --- | --- |
| **Authentication** — who are you? | `Staff.id`, the JWT subject |
| **Role** — what may you do here? | `Staff.role` + `RolesGuard` |
| **Tenant** — whose data is this? | `Staff.venueId` → `Venue` |
| **Entitlement** — did this Venue buy Manager? | `effectiveFeatures(venueId)` + `FeatureGuard` |

## Identity: Staff, not a new entity

Manager authentication reuses `Staff`. It is already the right thing — a
restaurant employee — and Step 4B1 made it directly Venue-scoped
(`@@unique([venueId, username])`). No `ManagerUser`, `PlatformUser`, or
`StaffUser` was introduced; a second identity model for the same people would
have to be kept in sync with this one forever.

Because `Staff.username` is unique only *within* a Venue, two restaurants may
both have an `admin`. Every Manager query is therefore Venue-scoped, and any
lookup keyed on username alone is a bug.

## Tenant authority

The Venue comes from the Staff row the token's subject names:

```text
JWT.sub  →  Staff.id  →  Staff.venueId  →  Venue.organizationId
```

A `venueId` or `organizationId` in a request body, query, or header is not
authoritative and is never read. No Manager endpoint accepts one — there is
nothing to strip, because the tenant is not an input.

### Resolved per request, not carried in the token

The token carries only `sub`, `username`, and `role`, unchanged from before.
Venue, Organization, role, and activity are re-resolved from the database on
every request, and the token's own `username`/`role` are ignored.

The trade-off, stated plainly: this costs one indexed primary-key lookup per
Manager request. It buys a single source of truth and immediate effect for
every change that should revoke access. Manager tokens live 24 hours, and
within that window a staff member can be deactivated, demoted, renamed, or have
their Venue disabled. A `venueId` minted into the token at login would keep
working through all of it, and a token and a database that disagree about which
Venue a request belongs to is precisely the failure this step exists to
prevent. `JwtStrategy` rejects a token whose staff no longer resolves.

This also means no client change was required: the token shape is untouched, so
the existing Manager app keeps working.

## Multi-Venue future

Today one Staff row belongs to one Venue, so an authenticated manager has
exactly one tenant. That matches the current schema and no membership table was
invented for a case that does not exist yet.

When one person must manage several Venues, the shape that fits is a membership
join (`StaffVenueMembership`, or an Organization-level principal) plus an
explicit *active venue* selection on the request — because with several
candidate tenants, the server can no longer infer which one a request means. The
boundary drawn here survives that change: `ManagerTenantService` stays the one
place a tenant is resolved, and every caller keeps receiving a single
`TenantContext`. Only the resolver's internals would change.

Organization-wide RBAC was deliberately not built.

## One TenantContext

```text
POS Device auth    ─┐
                    ├─→ TenantContext { venueId, organizationId } ─→ services
Manager staff auth ─┘
```

`src/tenancy/tenant-context.ts` holds the single definition;
`auth/pos-auth-context.ts` re-exports it so existing POS imports are unchanged.
Manager requests are **not** forced through `PosAuthContext` — a Manager is not
a device, has no `deviceId`, and has no authentication mode. `ManagerAuthContext`
extends the shared tenant with the person (`staffId`, `username`, `role`).

`requestTenant(req)` reads whichever mechanism authenticated the request and
returns `null` when neither did, so a caller that cannot prove a tenant is
denied rather than quietly served the bootstrap Venue.

## Manager API scoping

Every handler on `/mobile/*` takes `@ManagerTenant() tenant` and passes it as
the first argument to its service, mirroring the `sync(tenant, …)` convention
Step 4B1 established for POS. The services' Prisma calls were already
Venue-scoped; what changed is that the Venue is now the authenticated one
instead of a constant.

| Area | Tenant | Role | `MANAGER_APP` |
| --- | --- | --- | --- |
| Dashboard, tables, financials, expenses | authenticated Venue | MANAGER | yes |
| Orders, takeaway, walk-in | authenticated Venue | MANAGER | yes |
| Menu, counted menus | authenticated Venue | MANAGER | yes |
| Users (staff admin) | authenticated Venue | MANAGER | yes |
| Reports, audit, sales | authenticated Venue | MANAGER | yes |
| Notifications, push registration | authenticated Venue | MANAGER | yes |
| Restaurant settings | authenticated Venue | MANAGER | yes |
| Reservations, print relays | POS callback (see below) | MANAGER | yes |
| POS sync (`/sync/*`) | Device credential | — | **never** |

Reservations and the print relays proxy to the Windows POS over its callback
URL rather than reading the tenant-scoped mirror, so they carry no
`TenantContext` yet. That callback is still a single-installation route;
reservation tenancy is deferred with the rest of the reservation work.

## Entitlement enforcement

`MobileController` now carries
`@UseGuards(JwtAuthGuard, RolesGuard, FeatureGuard)` and
`@RequiresFeature(MANAGER_APP)`. The order is the meaning: authenticate, then
check the role, then check that the Venue bought the product. A Venue without
`MANAGER_APP` gets `403 Forbidden` from the standard exception filter, which
says nothing about whether any other Venue exists.

`FeatureGuard` was generalised to read the tenant from either authentication
mechanism. It is still attached to no POS sync route, no device route, and no
website route.

### Roles are not replaced by entitlements

Both are required and they answer different questions. `RolesGuard` still
enforces `@Roles(MANAGER)`; a waiter's token is refused at
`ManagerTenantService` before that. Entitlement asks whether the *restaurant*
bought Manager; role asks whether *this person* may use it. Removing either
would be a security regression.

## The invariant that did not move

```text
POS → Device auth → Venue → Cloud sync        (infrastructure — always on)
─────────────────────────────────────────────
Manager identity → entitlement → Manager API   (commercial — optional, above)
```

Turning `MANAGER_APP` off denies the Manager product and nothing else. POS →
Cloud synchronization, Device authentication, the operational mirror, and
historical retention are untouched, so a customer who buys Manager later finds
their history already there. This is proven for a Venue that never bought
Manager, not merely asserted.

## Venue-discriminating login

`POST /auth/mobile-login` now accepts `{ venueCode, pin }`. The unique, stored
`Venue.loginCode` is resolved before comparing PINs among active Manager/Admin
Staff in that active Venue. Exactly one PIN match is required; ambiguity within
a Venue is denied. Different Venues may use identical usernames and PINs.
The response adds `venueCode`; the JWT still identifies Staff by `sub`.
The generated boundary is `packages/contracts/schema/manager-login.contract.json`.

Previously a PIN-only request scanned only the bootstrap Venue. Old clients can
be supported by explicitly configuring `MANAGER_LEGACY_LOGIN_UNTIL` with an ISO
UTC expiry no later than `2026-12-01T00:00:00Z`. It is disabled when unset,
invalid, expired, or beyond that cap. It selects the stored code `vankisi`, never
an internal bootstrap UUID. Remove the setting after all deployed Managers use
venue codes; delete the compatibility branch in the next auth contract version.
See `docs/MANAGER_SAAS_PHASE1.md` for deployment order and proofs.

The Manager remembers only the selected code and the existing session token.
New sessions clear old cached restaurant data and notification history. Offline
fallback from a login attempt requires the same code as the cached session.
The desktop companion launcher also asks for a code and cannot bypass a Cloud
credential rejection using a local POS user.

## Legacy bootstrap tenant

No active Manager login, realtime, notification or sync route uses
`LEGACY_MANAGER_TENANT`. It remains only in the unrelated bootstrap seeder.
Device-less POS shared-key and frozen callback compatibility still resolve their
legacy tenant explicitly; these are not Manager tenant authorities.

## Notification, push, and draft ownership

Step 4B1 deferred these because Manager tenant authentication did not exist.
Reviewed now, with the classification and what was done:

| Model | Classification | Action |
| --- | --- | --- |
| `ManagerNotification` | Manager-owned root | **`venueId` added.** Deliveries are addressed by staff username, which is Venue-local. |
| `ManagerNotificationDelivery` | Tenant child | Inherits through its notification; queries filter on `notification.venueId`. |
| `PushDevice` | Manager-owned root | **`venueId` added.** `fcmToken` stays globally unique — a device token genuinely is — but the username it maps to is not. |
| `QuickOrderDraft` | Manager-owned root | **`venueId` added**, `draftId` uniqueness became Venue-local. Read and written by the Manager counted-menu endpoints. |
| `QuickOrderDraftItem` | Tenant child | Required draft relation supplies ownership. |

All four Manager-facing ones needed it: without ownership, a second Venue's
manager would have read the first's counted menus and notifications, so the
isolation claim would have been false for those endpoints.

`HybridNotificationService` now carries the triggering server-resolved Venue
through persistence, delivery rows, presence, coalescing and FCM recipient
selection. Socket rooms are `managers:<venueId>` and socket identity is resolved
from current Staff state at handshake and before outgoing Venue events.
`GET /sync/diff` and its unused Flutter wrapper were removed.
