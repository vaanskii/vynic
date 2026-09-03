# Vynic Project State

Compact snapshot of implemented facts. This is not a changelog or an
architecture manual. Current code, schema, migrations, contracts, and tests win
if this file becomes stale.

Some phase documents preserve the state at the time they were written. In
particular, older deferred lists for enrollment, tenancy, and Platform Admin
predate Step 6C; use this snapshot and `docs/EDGE_COMMAND_MIGRATION.md` for the
current transport status.

## Current Product Shape

- `apps/operations/` is one Flutter codebase for the offline-first desktop POS
  and the mobile/desktop Manager client.
- `apps/backend/` is the modular NestJS service over PostgreSQL through Prisma.
- `apps/platform-web/` contains the public Vynic product site and the
  authenticated Platform Admin under `/admin`.
- `apps/venue-web/` is the bespoke Vankisi customer website. It is not the
  generic multi-Venue SaaS website.
- `packages/contracts/` owns the generated Cloud/Edge command and table-identity
  wire contracts.

## Current Architecture

- The POS owns live restaurant operation and persists it in Hive. Cloud mirrors
  operational state and coordinates Manager, website, and Edge work.
- PostgreSQL uses shared `pos` and `website` schemas with explicit
  `Organization -> Venue` ownership; Venue is the operational tenant boundary.
- Tenant authority is server-owned: Device -> Venue for POS, Staff -> Venue for
  Manager, Host -> VenueDomain -> Venue for public website requests, and booking
  identity -> Venue for payment callbacks.
- `PlatformUser` is a separate cross-tenant principal. It is not Staff and has
  no Venue membership.
- Cloud-originated POS work uses a persistent pull queue. The Edge initiates the
  connection, executes locally, journals the outcome, and acknowledges it.

## Current Phase

- No product implementation phase is marked in progress by current code/docs.
- The latest completed sequence covers Money Integrity 1A/1B, POS enrollment
  1C, incremental audit sync, and Edge Step 6C.
- Production Cloud deployment foundation is the documented recommended next
  phase; it has not been implemented or deployed by this repository state.

## Completed Foundations

- Organization/Venue foundation and Venue-scoped operational data are
  implemented (Steps 4A and 4B1).
- Manager Staff -> Venue resolution and `MANAGER_APP` enforcement are
  implemented (Step 4B2A).
- Public Host -> Venue resolution, Venue-owned website tables/bookings, and
  `WEBSITE` enforcement are implemented (Step 4B2B).
- Plan, Feature, Venue assignment/override, and WebsiteMode are implemented
  (Step 5A). Effective features come from `VenueEntitlementsService`.
- Edge queue/backend transport, POS claim/execute/journal/ack, and real command
  migration are implemented (Steps 6A-6C).
- Platform principal/API and the authenticated Platform Admin UI are implemented
  (Steps 7A-7B).
- One-time, Venue-bound POS self-enrollment is implemented (Phase 1C).

## POS / Edge State

- A Device credential resolves the Device and Venue; the legacy shared POS key
  cannot claim Device-specific Edge work.
- Enrollment is available through Platform Admin and `POST /edge/enroll`; the
  POS stores the issued credential outside Hive in `edge_device.json`.
- Contract v2 declares 18 types: `NOOP` plus 17 real commands covering orders,
  dine-in/takeaway, reservations, expenses, staff, and three print operations.
- All declared command types have POS handlers. Mutations converge on
  `PosCommandApplier`, shared by Edge and the legacy LAN adapter.
- Delivery is at least once. The Hive `edge_command_journal` prevents replay of
  completed work; interrupted print commands fail visibly instead of printing
  a possibly duplicated check.
- Enrolled Venues use Edge dispatch. The old callback client/outbox/listener are
  frozen fallback only for a Venue with no enrolled Device and for rollout
  compatibility; no new operations belong there.
- Fleet-wide enrollment is not established by repository code. Until every
  deployed POS has a Device credential, the fallback cannot be retired.

## Money Integrity State

- Phase 1A and 1B are implemented: material money mutations are locally audited,
  expense and adjustment data reaches Cloud, and legacy POS ingest fails closed.
- All table-close variants use `CloseTableTransaction` with a durable
  `closureId` and Hive closure journal. Startup recovery completes recorded
  sales or abandons attempts that collected nothing without duplicating revenue.
- Advances are receipts on the collection day and are applied at close; they do
  not reduce the sale's gross value.
- Gross sales and money collected are separate derived figures. X/Z/monthly and
  Manager summaries share `SalesRepository.countsAsRevenue` and exclude voided,
  restored, and internal closures as documented.
- Cloud mirrors closure/money reconciliation fields. PostgreSQL money columns
  still use `Float`; a Decimal migration remains deferred.

## Platform / Admin State

- Platform Admin can manage Organizations, Venues, plan assignment, feature
  overrides, WebsiteMode, domains, Devices, credentials, enrollment codes, and
  platform audit records. It can issue a fixed `NOOP` connection test.
- Device credentials and enrollment codes are one-time values; verifier hashes
  are never returned by normal reads.
- Restaurant Backoffice does not exist. Restaurant operators must not be
  authenticated as `PlatformUser` to fill that gap.
- Venue Policy is documented in `docs/VENUE_POLICY_PLAN.md` but not implemented.
  Current operational switches/settings remain local to the POS.
- Custom restaurant roles/permissions, inventory, SaaS billing, and per-Venue
  payment integration configuration do not exist.

## Website State

- Public APIs resolve registered hostnames through `VenueDomain`; production
  fails closed for unknown or disabled hosts.
- `WebsiteUser` remains global; each `WebsiteReservation` is Venue-owned.
- Payment callbacks derive Venue from the server-owned reservation.
- The Vankisi site remains `CUSTOM`. The generic data-driven `SAAS` restaurant
  frontend and custom-site runtime/deployment control are not implemented.
- BOG merchant credentials remain process-wide for the bootstrap deployment.
  Adding another paying Venue before per-Venue credentials exist would route
  money through the wrong merchant account.

## Current Transport and Sync State

- POS -> Cloud snapshot ingestion remains Edge-initiated and is not gated by a
  commercial feature.
- Reservations now sync into `PosReservation`; Manager and website reads no
  longer make a synchronous LAN call to the POS.
- Audit reports sync incrementally in batches using content revisions and
  acknowledgments. Legacy `fullSync` remains accepted for older POS builds.
- Tables, orders, menu, staff, and `salesHistoryByDate` still use broad snapshot
  payloads; further sync windowing/scaling is deferred.

## Known Blockers

- Website reservation availability has no transactional hold; simultaneous
  bookings can still allocate the same table.
- Manager PIN-only login searches only the bootstrap Venue. Authenticated
  requests are correctly Staff-scoped, but a second Venue's manager cannot yet
  obtain a token without a Venue-discriminating login contract.
- Notification raising still assigns some sync-triggered notifications to the
  bootstrap Venue instead of carrying the authenticated sync tenant through.
- Production Cloud deployment foundations (origins, HTTPS, CORS, runtime
  secrets, hosting, and deployment verification) are not established.
- Full legacy callback retirement depends on real fleet enrollment, not merely
  the existence of enrollment code.

## Deferred Work

- Restaurant Backoffice, Venue Policy, custom roles/RBAC, inventory, cash
  management, reservation holds, generic SaaS venue web, SaaS billing, and
  per-Venue payment credentials.
- Device-addressed printer selection, lower-latency Edge long polling, OS
  keychain credential storage, and multi-Device queue contention optimization.
- Legacy shared sync key/callback removal after rollout evidence permits it.

## Current Migration Versions

- Prisma migration tip:
  `20260903140000_pos_reservation_mirror`.
- Immediately preceding state migrations:
  `20260903120000_audit_report_sync_revision`,
  `20260903090000_device_enrollment`, and
  `20260902090000_money_reconciliation_fields`.
- Flutter Hive database target version: `6` in
  `apps/operations/lib/core/database/hive_migration_service.dart`.
- A migration file in the repository does not prove deployment to any database.

## Important Recent Commits

- `1526db6` — wire the shared POS command module into backend consumers.
- `41cb9af` — remove unused callback operations and freeze the remaining fallback.
- `4c841bd` — complete Step 6C real-command migration and reservation mirror.
- `d3cc1a7` — add acknowledged, incremental audit-report sync.
- `89a38b9` / `f2f25e3` — add POS enrollment UI/client and backend redemption.
- `79ad18f` / `879084a` — implement atomic close/money integrity and Cloud fields.

## Maintenance

- Update this file only when a represented current fact changes. Replace stale
  facts; do not append session notes, dates, or a task history.
- Keep it compact. New detail belongs in task docs or the canonical engineering
  protocol, not here.
