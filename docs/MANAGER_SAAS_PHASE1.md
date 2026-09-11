# SaaS Phase 1 — Manager tenancy

Baseline: `SAAS_READINESS_AUDIT.md`, Phase 1. That audit remains a historical
investigation; current implementation facts live here and in project state.
No entitlements/subscriptions, hosted deployment or operational POS redesign.

## Login and identity

Previously `AuthService.mobileLogin` scanned active Manager/Admin Staff only in
the bootstrap Venue. A second restaurant could not obtain a Manager token.

The new request is `POST /auth/mobile-login { venueCode, pin }`. Resolve the
unique stored `Venue.loginCode`, require an ACTIVE Venue, then compare PINs only
among that Venue's active Manager/Admin Staff. Exactly one matching Staff is
required. PIN alone is never searched across Venues. Same username/PIN across
Venues works; duplicate matching PINs within one Venue are rejected. This keeps
the existing 4–6 digit keypad UX without requiring staff to remember usernames.

The JWT remains a Staff subject, not a client-selected tenant authority.
`JwtStrategy` still resolves current Staff -> Venue on every HTTP request.
Disabled/deleted/demoted Staff and disabled Venues fail on the next request.
No PIN is returned, logged or newly persisted by this flow.

The schema/generator in `packages/contracts` owns the route, field names, code
format and rollout constants, with checked TypeScript and Dart output.

## Manager UI and session changes

The existing Georgian login card adds **რესტორანი** above the PIN keypad.
It initially shows `vankisi` for the existing installation and remembers the
last successfully authenticated code in Manager preferences. It does not save
the PIN; the transient shell User no longer receives the PIN either.
The desktop POS's companion launcher asks for the same code. It no longer enters
Manager as a local POS user after Cloud rejects credentials. POS login itself
is unchanged. The keypad now fits a 320px phone without horizontal overflow.

A successful login clears the old Manager read cache, notification history and
pending notification timers. A failed offline login can use only a cached
session for the same Venue code. Old cached tokens without a stored code cannot
be used as a fallback for a newly selected code. The new client requires the
server to echo the matching `venueCode`, refusing an old backend which silently
ignored it.

## Migration and Platform

Additive migration: `20260915120000_manager_login_code`.

- Adds required, unique `Venue.loginCode`, with a lowercase code format check.
- Existing Vankisi receives `vankisi`. Other existing Venues receive deterministic
  codes from their ID-sorted ordinal, padded to twelve digits. No display-name
  dependency, operational rewrite or history rewrite.
- New Venues automatically receive `venue-` plus twelve random hexadecimal
  characters. The database unique index prevents collisions (a collision fails
  creation; it never aliases an existing Venue).
- Codes are immutable through current APIs, including Platform updates.
  Platform's existing authenticated Venue directory returns the field and the
  Venue record displays it as selectable/copyable text. No restaurant endpoint
  can edit it. A future rename operation must live behind Platform authority.

Full migration chain was applied to a fresh isolated PostgreSQL 17 cluster in
`/tmp` on port 55439. Only disposable `manager_phase1` databases were used;
`vankisi_database` was not accessed or modified.

## Realtime event audit

Every runtime `broadcastUpdate` call requires a resolved `TenantContext`.
`MonitoringGateway` is the only room-emission boundary. Rooms are
`managers:<venueId>`; a client-supplied room/venue/username/role cannot select
membership. The handshake verifies JWT and resolves current Staff. Before a
Venue envelope is emitted, existing sockets are re-resolved and expired,
disabled, renamed or reassigned identities are disconnected.

| Current producer | Events | Classification / authority |
| --- | --- | --- |
| `mobile-orders.service` (9 calls) | `audit_updated`, `order_updated`, `orders_bulk_touch`, `table_updated`, `order_cancelled`, `takeaway_created`, `order_created`, `takeaway_deleted` | Venue / authenticated Staff |
| `mobile-reservations.service` (3) | reservation `data_updated` | Venue / authenticated Staff |
| `mobile-menu.service` (3) | `data_updated` | Venue / authenticated Staff |
| `mobile-dashboard.service` (1) | `table_updated` | Venue / authenticated Staff |
| `ingest-audit-reports.service` (1) | `audit_updated` | Venue / authenticated Device or frozen shared-key POS resolver |
| `sync-broadcast.service` (7) | order/table bulk touch, reservation `data_updated`, `order_updated`, `table_updated`, aggregate `data_updated`, `day_closed` | Venue / authenticated sync context |
| `website-pos-reservation-bridge.service` (2) | reservation `data_updated` | Venue / server-resolved website/booking context |
| Gateway heartbeat/pong | timestamp only | Connection control; direct to the requesting connection |
| Gateway aggregate alias | `data_updated` alongside specific events | Same Venue room and exclusions as the original event |
| Hybrid immediate/coalesced emit | original event envelope | Same resolved Venue; no global path |

There are no Platform/global business broadcasts. `WsEventType` also retains
legacy/unproduced `staff_sync` and `order_closed` names for wire compatibility;
this phase adds no producers. Legacy POS transport events use the resolved POS
Venue and the same scoped room. Echo suppression keys and service-fee coalescing
include Venue, so identical POS IDs in A and B neither merge nor mute each other.
The frozen callback outbox carries its persisted row Venue into echo suppression.

## Notifications and push devices

The triggering server-owned Venue is threaded through notification creation,
Manager lookup, delivery rows, presence and FCM token selection. Notification
children inherit Venue through their notification parent. Presence keys are
Venue + username; A being online does not suppress B's offline push.
FCM queries require matching Venue, active Venue and the active Manager usernames.
Existing notification replay already filters by authenticated Venue and username.

Push registration already globally upserts the FCM token under the authenticated
Staff username and Venue. Re-registering a handset moves the record instead of
creating a second tenant association; stale logout is scoped and cannot delete
its new owner. The Flutter client unregisters and deletes the old FCM token
before a new successful session, and deletes it on logout even when backend
unregistration fails. Actual Firebase transport is mocked in the database proof;
recipient selection and delivery rows use the real production service and DB.
No production push was sent.

## Dead sync route and legacy cleanup

`MobileApiService.getDiff` was the only `/sync/diff` occurrence in active Flutter
source and had no callers. Remove that wrapper and the Manager-authenticated
backend route. Tests assert no route metadata, HTTP 404, and no active Flutter
route/wrapper dependency. Other Manager reads remain Staff-scoped.

`LEGACY_MANAGER_TENANT` has no remaining runtime use in Auth, Realtime,
Notifications or Manager sync. It remains in the unrelated bootstrap seeder.
Device-less POS authentication, callback/outbox fallback and bootstrap/dev
helpers remain as documented existing compatibility mechanisms.

## Deployment order and compatibility removal

1. Apply the additive migration before starting the new backend.
2. If old Vankisi Manager clients remain deployed, set
   `MANAGER_LEGACY_LOGIN_UNTIL` to a concrete future ISO UTC deadline, no later
   than `2026-12-01T00:00:00Z`, **before** switching backend traffic. Example for
   this rollout: `2026-10-01T00:00:00Z`. No setting means no PIN-only fallback.
   Invalid, expired or beyond-cap values fail closed.
3. Deploy the backend and Platform UI. Verify Vankisi's code and complete a
   code+PIN login plus an old-client PIN-only login while the window is open.
4. Ship the new Manager client, including the desktop companion flow. Copy each
   new Venue's code from Platform; Staff provisioning remains the existing flow.
5. Verify both Venues' login, HTTP, socket and push behavior in the deployment.
6. Once old clients are retired, unset the compatibility variable. Delete the
   PIN-only branch in the next auth contract version; its hard cap already stops
   operation on 2026-12-01. Existing explicit `vankisi` logins continue afterward.

Do not ship the new Manager client before its compatible backend. Do not roll
back to the old globally broadcasting backend while multi-Venue traffic is
active. No migration rollback/drop is required for application rollback.

## Validation

- Full backend PostgreSQL/unit suite: 61 suites, 649 passed, one optional retained
  Sale snapshot test skipped because no retained POS snapshot was supplied.
- Real two-Venue HTTP + Socket.IO integration, identical credentials, wrong
  discriminator, disabled Staff/Venue, bounded Vankisi compatibility, notification
  rows/replay, offline FCM recipients, token movement and stale logout.
- Realtime unit tests cover Venue-local echo suppression and same-ID coalescing.
- Manager Flutter: 4 auth tests and 2 widget tests passed. They cover generated
  request shape, selected-code persistence without PIN, cache isolation, logout,
  offline mismatch, rejection of an old backend, and 320px/desktop layouts.
- Platform UI: 7 suites / 22 tests passed, including visible restaurant code.
- Backend and Platform TypeScript checks, backend build, Flutter analysis,
  contracts `--check`, and `git diff --check` passed.

Reproduce on a disposable migrated database whose name contains both
`manager_phase1` and `vynic_step47_test` (the payroll suite's existing safeguard):

```sh
TENANT_INTEGRATION_DATABASE_URL=postgresql://USER@127.0.0.1:PORT/manager_phase1_vynic_step47_test npm test -- --runInBand
```

Run from `apps/backend`; never point these integration tests at a live database.

## Remaining SaaS P0 items / stop

The audit's remaining P0s are hosted infrastructure/backups/restore proof,
module entitlement keys, commercial subscription state, Platform Manager
bootstrap/reset, restaurant printer configuration, and per-Venue payment
credentials if website payments are sold. They are deferred to their own phases.
No subscription, billing, hosted deployment, printer or PIN-security redesign was
implemented here. No commit, push or deployment was requested or performed.
