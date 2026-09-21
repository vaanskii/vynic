# SaaS Phase 2 — Platform control plane

Baselines: `SAAS_READINESS_AUDIT.md` and `MANAGER_SAAS_PHASE1.md`. Phase 1
Venue login, tenant authority, realtime rooms and `/sync/diff` removal remain.
This phase adds manual commercial administration; it does not deploy hosting,
observability, automated billing, payment integrations or restaurant policy.

## Feature contract and enforcement

Stable keys are centralized in backend `entitlements/feature-keys.ts` and Flutter
`core/models/feature_keys.dart`. The existing Feature/Plan/PlanFeature,
VenuePlanAssignment and VenueFeatureOverride engine remains authoritative.
An override wins over the plan; removing it restores plan inheritance.
Retiring a Plan does not revoke its existing assignments.

| Key | Commercial boundary |
| --- | --- |
| POS | Existing POS product entitlement; never consulted by critical local operations, Device authentication or operational sync |
| WEBSITE | Existing host-resolved Website APIs; subscription policy also applies; payment callbacks remain independent so already-started payments can settle |
| MANAGER_APP | Base Manager API requirement; remains required alongside each module annotation; realtime/push also require it |
| INVENTORY | All `/mobile/inventory/*`: stock, suppliers/assortment, receipts, composition/recipes, supplier payments/payables, consumption/history |
| PAYROLL | `/mobile/finance/payroll*`, Staff compensation/history and legacy salary views |
| FINANCIAL_PLANNING | Obligations, cycles/reserves/payments and planning summary; disabled Payroll is neither opened nor included in planning |
| PROFITABILITY | Derived inventory valuation, moving unit costs and theoretical recipe costs are removed from Manager/Device responses; purchasing amounts, receipt evidence and raw quantities remain available with Inventory |
| MANAGER_RESERVATIONS | Manager reservation reads, creation, status, removal and printing; local POS reservations continue |
| ADVANCED_AUDIT | Manager `/mobile/audit-log*` and advanced activity navigation; cached POS advanced activity navigation. Core Order audit and audit writing continue |

FeatureGuard checks both controller and handler requirements, rather than
allowing a method annotation to replace MANAGER_APP. Missing module access
returns HTTP 403 with the feature key in the error. Tenant authority remains
Staff → Venue, Device → Venue, or registered host → Venue.
The response interceptor removes derived profitability fields recursively;
it does not corrupt procurement evidence or cash-flow totals. Financial reports
retain historical actual cash outflows even when an associated editing module
is disabled. Commercial controls cannot rewrite accounting history.

`GET /mobile/entitlements` returns server-resolved `features`, `commercialAccess`
and public subscription status/dates. It exposes no Platform operator note or
actor identity. Clients never calculate plan/override precedence.

## Manager runtime and offline behavior

The Manager shell starts with no optional modules and fetches the authoritative
snapshot. It refreshes on resume, every 10 seconds, and Dashboard pull-to-refresh.
A changed snapshot clears Manager read caches, closes stale pushed screens,
recreates kept-alive tabs and returns to Dashboard. Stable destination indices
map Dashboard links to the currently visible navigation, so removing Inventory
or Reservations does not shift a link into another module. Payroll and obligation
links, Dashboard cards, reservation shortcuts and advanced activity tabs disappear
when disabled. Disabled Profitability hides the theoretical-cost panel.

A network failure retains only this session's last resolved optional features;
the server remains authoritative for every request. An explicit auth/entitlement
rejection clears features and cached reads. Entitlements are not persisted as
an offline permission grant. Logout clears them, and a response from a replaced
session cannot change the new session's features. Past due displays a warning.
The existing Georgian UI language and responsive layouts are retained.

## POS projection and operational safety

Effective feature keys ride in the existing versioned Inventory catalog and are
stored atomically in the same Hive catalog value. No new startup network
requirement is introduced. A catalog without keys remains compatible with older
backups/servers and retains prior optional visibility until a successful pull.

INVENTORY off returns an empty catalog/recipe list, hides optional Admin
inspection, and prevents new recipe-based consumption intent after refresh.
Frozen Sale intents from before refresh still deliver and reverse exactly:
commercial toggling must not strand historical ledger effects. Offline POS uses
its last catalog until the next successful pull; it never waits for Cloud at
checkout. PROFITABILITY only removes cost fields, not stock quantities.
ADVANCED_AUDIT hides optional local activity inspection without stopping writers.

Subscription suspension does not alter Device authentication, Edge claim/ack,
POS inventory projection, Sale ingestion, orders, payments, printing or day close.
Already-open local sessions/operations can finish safely.

## Subscription policy

`VenueSubscription` is a separate optional one-to-one Venue row, with status,
started/trial/current-period/suspended/cancelled dates, operator note, updatedBy
and timestamps. `Venue.status` remains operational ACTIVE/DISABLED.

| Status | Policy |
| --- | --- |
| TRIAL | Commercial Cloud access allowed, subject to features |
| ACTIVE | Commercial Cloud access allowed, subject to features |
| PAST_DUE | Access retained during operator-controlled grace; Manager warning |
| SUSPENDED | Manager HTTP/login and Website commercial access denied |
| CANCELLED | Same commercial denial; data retained |
| Return to ACTIVE/TRIAL | Access resumes on next request/session refresh |

Dates are informational in this manual phase. There is no scheduler silently
expiring a trial or grace period. Operators explicitly suspend/cancel. Missing
rows retain legacy access for compatibility; migration creates ACTIVE rows for
all existing Venues, and Platform creates new Venues with TRIAL rows.
Manager Staff re-resolution rejects suspended/cancelled Venues on each request;
existing sockets re-resolve before emission. Push recipient selection respects
current Staff activity and commercial access. Website payment callbacks retain
their existing server-owned booking authority and are deliberately not suspended.

## Platform UI and API

Existing Venue Product controls list all Feature rows dynamically, including
new modules, and distinguish plan inclusion, enabled/disabled overrides,
inheritance and effective entitlement. A suspended subscription is explicitly
shown as blocking Cloud access even though assigned entitlements remain.

Venue **Commercial** provides subscription state/dates/notes and explicit Start
trial, Activate/Reactivate, Mark past due, Suspend and Cancel actions. Mutations
require confirmation. The same section lists Manager access and provides Create,
Reset PIN/Reactivate and Disable. PIN inputs clear after success/closing and
normal reads never return them. Errors preserve a retry key and the operator's
inputs so transient failures can be retried.

| Route | Authority / result |
| --- | --- |
| GET/PUT `/platform/venues/:venueId/subscription` | Platform read / SUPER_ADMIN mutation |
| GET/POST `/platform/venues/:venueId/managers` | List / create actual Staff, MANAGER or ADMIN |
| POST `/platform/venues/:venueId/managers/:staffId/reset` | Reset PIN and reactivate; same Staff identity |
| POST `/platform/venues/:venueId/managers/:staffId/disable` | Set inactive; never hard-delete Cloud Staff |
| GET/POST `/platform/users` | List / create PlatformUser with initial password |
| POST `/platform/users/:id/disable` | Disable another PlatformUser; self-disable refused |

Staff mutations require a UUID `requestId`. Create also requires `displayName`,
`username`, `role`, `pin`; reset requires `pin`. PINs retain the 4–6 digit rule
and cannot duplicate another active Staff PIN in that Venue.
Platform users use SUPER_ADMIN or SUPPORT_READONLY. The shared Platform guard
rejects every non-read method for SUPPORT_READONLY. Platform tokens remain a
separate audience/principal; Manager tokens cannot enter cross-Venue APIs.
There is no invitation email service: an operator creates an initial password
and distributes it through their own secure channel. No email is sent here.

## Staff authority, durable delivery and conflicts

A Venue row lock serializes Platform access changes with Staff snapshot sync.
One transaction writes Cloud Staff, encrypted existing PIN vault, EdgeCommand
and PlatformAuditEvent. No Device needs to be online or enrolled at mutation
time; the untargeted Venue command waits for a Device to enroll and claim it.
No legacy callback or Cloud→LAN call is used.

Platform-managed Staff carry `platformManaged=true`. Incoming snapshots cannot
change their PIN, role or active state, or remove them when absent. Restaurant
Manager APIs cannot mutate these Platform-controlled access rows; their Manager
Staff UI explains ownership and hides those actions/PIN values. Other Staff
retain their existing operational ownership. Historical payroll/audit references
remain attached to the same Cloud Staff UUID.

Create and reset use existing `STAFF_CREATE` goal-state application. Disable
uses `STAFF_DELETE` with additive Platform metadata. `staffId`, `platformAction`
and a monotonic `platformRevision` are recorded in the shared contract. The
current POS persists the highest successful revision per Staff in settings;
older delayed commands become `superseded`, and identical delivery is convergent.
The existing Edge journal handles completed-command redelivery and lost ACKs.
Reset reconciles an existing username rather than inserting a duplicate user.
Failed PIN/role updates are reported as failures, never false success.

Platform disable retains the local User row and a persisted disabled-login flag,
including for the last Manager; it does not invoke the normal last-Manager-delete
restriction. Future PIN login fails and normal Staff lists omit the disabled row.
Reset clears that flag after the goal state is applied. Existing POS sessions
can finish operations. Settings backup preserves both flags and revisions.
Cloud Manager JWTs stop working immediately on the next request after disable.
A reset changes the PIN but does not otherwise revoke an already-issued JWT;
the existing token lifetime remains unchanged.

Retrying the same request UUID returns the original command/status without
reviving it or writing another audit row. Reusing it for a different action,
Staff, username or PIN fails with 409. New deliberate changes use a new UUID.
Terminal Edge failures remain visible and require a new deliberate access change;
there is no automatic hidden success or queue rewrite.

The existing transport still carries plaintext PIN inside the Device-only command
payload, and the existing Cloud PIN vault remains recoverable/encrypted. This is
an explicit compatibility limit, not a full PIN-security redesign. Platform
responses and audit metadata never contain PINs, passwords or hashes.

## Audit

Subscription changes, feature override set/clear, Manager create/reset/disable,
and Platform User create/disable are recorded atomically with their mutation.
Venue targets keep the existing Venue activity feed useful. Metadata includes
semantic old/new state and target Staff/command where relevant, never a PIN.
PlatformAuditEvent supplies actor and timestamp. Existing audit writers and
historical accounting are preserved.

## Migration and existing Vankisi compatibility

Additive migration: `20260918120000_saas_phase2_control_plane`.

- Adds VenueSubscription, its five-state enum, SUPPORT_READONLY, and Staff
  displayName/platformManaged fields with backward-compatible defaults.
- Safely inserts the six new Feature rows.
- Adds all six formerly bundled modules to every existing plan containing
  MANAGER_APP. Existing explicit MANAGER_APP-enabled Venue overrides receive
  module grants as well, without replacing any existing module override.
- Gives every existing Venue ACTIVE subscription state. Existing disabled
  operational Venues remain disabled; MANAGER_APP-disabled Venues remain denied
  by the base product guard even if their plan contains module entitlements.
- Vankisi's existing full plan retains POS, WEBSITE, MANAGER_APP and all six
  modules. The disposable bootstrap-Vankisi assertion proves that migration
  result; no live `vankisi_database` was accessed.

All 35 repository migrations applied from empty to an isolated PostgreSQL 17
cluster under `/tmp/vynic_saas_phase2_pg`, loopback port 55443. Prisma migrate diff
against the resulting schema reports no difference. A repository migration is
not evidence of production deployment.

## Validation and reproduction

Backend: 64 suites / 673 tests passed, one optional retained-Sale-fixture test
skipped. The new real HTTP/DB suite provisions Venues through Platform, creates
first Staff through Platform (no manual Staff fixture), logs in, claims/applies/
ACKs a simulated POS command, resets/disables, tests stale sync, request retry,
foreign Staff targeting, subscription states, effective overrides, product/module
guard intersection, Support read-only and Platform-user disable.

Flutter: full suite 1375 passed / 3 existing skips. Tests exercise real Hive
Staff create/reset/disable, duplicates, delayed revision rejection, cached POS
inspection hide/show, and Manager navigation at 360/768/1280px. Platform:
8 suites / 24 tests passed, including subscription confirmation and Manager
create/reset/disable inputs, cleared PINs and Support read-only controls.
The isolated staged Flutter snapshot also passes analysis and 46 focused tests,
without relying on the separate uncommitted Inventory workflow/layout changes.

Run backend integration only against a disposable database whose name contains
`manager_phase1`, `saas_phase2`, `procurement_` and `vynic_step47_test`, satisfying
all suite safety checks. For example:

```sh
TENANT_INTEGRATION_DATABASE_URL=postgresql://USER@127.0.0.1:55443/manager_phase1_saas_phase2_procurement_vynic_step47_test npm test -- --runInBand
```

Other checks: Prisma validate, migration history from empty and migrate diff,
backend build/TypeScript, Platform TypeScript/tests, Flutter analyze,
contracts generator `--check`, and `git diff --check`.

## Deployment order and stop boundary

1. Back up the actual deployment using its established procedure. Apply the
   additive schema/data migration before the new backend.
2. Deploy backend; existing Vankisi module access is preserved. Old Manager
   clients remain server-gated and may display forbidden errors for a module
   disabled before their upgrade. No destructive fallback is introduced.
3. **Upgrade enrolled POS builds before using Platform Manager access changes.**
   Existing STAFF_CREATE/DELETE types exist on older POS, but last-Manager soft
   disable and revision ordering require this Phase 2 build. Verify enrollment,
   claim/ACK and Staff compatibility on the deployment before exposing the actions.
4. Deploy Platform Web and Manager. Verify public entitlement refresh, both
   Venue combinations, manual subscription transitions and Manager bootstrap.
5. Confirm effective feature projection refresh on POS; disconnect Cloud and
   verify normal local operation/day close. POS installation is never a Cloud
   subscription enforcement point.

No production migration, deployment, push, billing or hosted infrastructure work
is included. Remaining SaaS P0s are hosted deployment/backups/restore proof,
restaurant printer configuration/onboarding, and per-Venue payment credentials
if Website payments are sold. Broader PIN security, website reservation holds,
and fleet-wide legacy retirement remain separately tracked work.
