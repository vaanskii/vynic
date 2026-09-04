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
- The staff plain-PIN vault (`staff:plain_pins`) is one encrypted `setting` row
  per Venue, and every read/write requires a resolved tenant. There is no
  bootstrap-Venue default: an unestablished Venue raises rather than being
  served the bootstrap Venue's credentials.
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
- Supported fiscal and internal payment closes use `CloseTableTransaction` with
  a durable `closureId` and Hive closure journal. Cancellation, hard-delete,
  emptied-by-transfer, and Close Day paths are separate. Startup recovery
  treats the Sale as the financial boundary and never recreates it. A shared,
  journaled post-Sale step idempotently completes the Order, physical Table
  where applicable, genuine linked Reservation, and typed/locked closure audit
  before the journal becomes complete; crash-before-Sale recovery still
  abandons the attempt without revenue or closure effects.
- Successful fiscal closes emit the typed `CLOSE` audit event, while internal
  closes emit `INTERNAL_CLOSE`; `CANCEL_TABLE` remains cancellation-only. Close
  events carry structured closure identity and money details locally and in the
  Cloud audit mirror. Every close event also carries `details.source`
  (`AuditSource` wire values `POS`, `MANAGER`, `EDGE`, `SYSTEM`,
  `SYSTEM_RECOVERY`, `DEVELOPER`); a close finished by startup recovery keeps
  its type and operator actor but records `source=SYSTEM_RECOVERY` and
  `recoveryAction=finished`. A closure already finalized is never re-stamped.
- Every genuine Order cancellation goes through `CancelOrderTransaction`: the
  POS detail screen, the Takeaway home panel, the Admin close-day repair list,
  and the Manager commands `ORDER_CANCEL` and `ORDER_STATUS_UPDATE
  status=cancelled`. It writes exactly one `CANCEL_TABLE` event (with
  `orderKind`, `tableRefs`, `source`, `actorId`, `actorName`, `approvedBy`,
  `reason`, `businessDate`), locks the report as CANCELLED, writes one
  non-fiscal `isCancelled` record with zero collection, moves a genuine linked
  Reservation to cancelled without touching its identity or link, frees
  physical tables (never for Takeaway), and writes the Order status last so a
  crash retry or a repeated Manager delivery converges on one cancellation. A
  closed Order is not cancellable until restored.
- Normal operations no longer hard-delete business Orders or their audit
  reports. `ORDER_CANCEL` is a cancellation, not a delete. The only physical
  delete of a live Order is the repair primitive
  `OrderRepository.hardDeleteOrderForRepair`, which has no operational caller,
  preserves the audit report, and logs `ORDER_HARD_DELETED`. Close Day still
  deletes already-closed Order rows because their Sale is the durable record.
- Every Order audit report opens with a typed creation event carrying
  `orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`, `RESERVATION`), `tableRefs`,
  `source`, `actorId`, `actorName`, `businessDate`: `CREATE_WALKIN` for POS
  and Manager table Orders (and the carrier of a Package), `CREATE_TAKEAWAY`
  for POS and Manager Takeaway (report exists from creation, guest details in
  `details`), `ACTIVATE_RESERVATION` for a seated genuine booking
  (`reservationId`, `customerName`; `source=SYSTEM` at day-open), followed by
  `APPLY_PACKAGE` (package fields and lines) for a Package Order. Initial
  `ADD_ITEM` rows follow the creation event at the same instant and are ordered
  by the report's `sequence`, not by that instant. Moving items between open Orders writes
  `MOVE_ITEMS` on both reports (`direction`, `fromOrderId`, `toOrderId`,
  quantities still set so older readers degrade to add/remove). An Order
  emptied by transfer closes its report with a locked `TRANSFER_CLOSE`
  (`closeReason=EMPTIED_BY_TRANSFER`, `transferredToOrderId`) and still writes
  no Sale. The backend normalizer stores all of these as themselves; it must be
  deployed before a POS build that emits them. Manager `DELETE
  /mobile/takeaway-orders/:id` now marks the Cloud row cancelled instead of
  deleting it before dispatching `ORDER_CANCEL`.
- Close payment semantics are structured, not textual: `CLOSE` /
  `INTERNAL_CLOSE` stay the only closure types and `details.paymentMethod`,
  `paymentBreakdown`, `cashAmount`, `cardAmount`, `advanceApplied`,
  `collectedNow`, `isFiscal`, `closureId` are the truth; a close of a genuine
  linked booking also carries `details.reservationId`. Both audit UIs render
  payment chips (`Cash`, `Card — TBC`, `Cash 40.00 + TBC 60.00`, advance
  shown separately, provider derived from the method) through
  `CloseEventPresentation` and fall back to the historical `note` only when
  an event has no structured details. The Manager endpoint returns `details`.
- Reservations have their own append-only timeline written by the repository
  (`ReservationAuditAction`: `CREATE_RESERVATION`, `UPDATE_RESERVATION`,
  `CONFIRM_RESERVATION`, `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`,
  `COMPLETE_RESERVATION`, `DELETE_RESERVATION`) with `reservationId`,
  customer, date/time, `guestCount`, `tableRefs`, `previousStatus`,
  `newStatus`, `source` (`POS`, `MANAGER`, `WEBSITE`, `SYSTEM`), actor,
  `businessDate`, `reason`. Every POS, Admin, Manager, website-bridge, Close
  Day, activation, close, cancel, restore, delete path goes through it; a
  status already in force, an existing id, or an absent row writes nothing.
  Seating writes `UPDATE_RESERVATION` (to `in-progress`) beside the Order's
  `ACTIVATE_RESERVATION`; a delete writes the booking's last snapshot first.
  Legacy `reservation_cancelled` rows are read as `CANCEL_RESERVATION` and
  never written again.
- Money mutations on an open Order are mirrored into its visible report:
  `RECORD_ADVANCE` (`previousAmount`, `newAmount`, `receiptId`,
  `collectedOn`), `ADJUST_ORDER` (`field` `manualAdjustment` or `serviceFee`,
  `previousValue`, `newValue`, totals). A Sale void appends `VOID_SALE`
  (`saleId`, `closureId`, `grossAmount`, `reason`) to the closed, locked
  report without changing its status or lock; it is not `CANCEL_TABLE`. The
  write-only log rows (`ADVANCE_RECORDED`, `ORDER_MANUAL_ADJUSTMENT_CHANGED`,
  `ORDER_SERVICE_FEE_CHANGED`, `SALE_CANCELLED`) are still written as
  compatibility duplicates. Cancellation stores `approvedById` /
  `approvedByName` beside the note.
- Restore-to-order keeps the original close and Sale as history, marks closure
  A reversed, clears the Order closure identity, and emits `RESTORE` in the same
  unlocked audit report; re-close creates closure B and appends a new `CLOSE`.
  The restored Sale retains its tender detail but is excluded by the existing
  revenue predicate. A consumed advance is put back on the open Order and is
  applied to closure B only.
- Restoring a table Order occupies its tables locally again. Takeaway restore
  has no physical-table dependency, Package fields remain on the existing
  Order, and a genuine linked Reservation moves from completed back to
  in-progress without changing its identity or Order link, then completes on
  re-close.
- Internal/non-fiscal close preserves operational gross and advance identity
  while recording `paymentMethod=non-fiscal`, zero cash/card, and
  `collectedNow=0`; the transaction boundary normalizes legacy caller input so
  it cannot masquerade as collected tender.
- Advances are receipts on the collection day and are applied at close; they do
  not reduce the sale's gross value.
- Gross sales and money collected are separate derived figures. POS X/Z/monthly
  and Manager current-day, all-time, history, dashboard, report, and financial
  totals use Sale-derived summaries and the revenue predicate. Missing Manager
  summaries fail closed instead of treating raw, open, cancelled, restored, or
  internal Orders as revenue; open-table payable remains a separate operational
  metric. Per-waiter revenue is unavailable until Cloud has authoritative Sale
  attribution.
- Cloud mirrors the POS Order and derived sales summaries, but the Order payload
  does not currently carry `closureId`, gross, advance-applied, collected-now,
  or fiscal classification as independent reconciliation fields. PostgreSQL
  money columns still use `Float`; a Decimal migration remains deferred.

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
- The order of a report's events is a zero-based `sequence` the POS assigns
  when it appends them, not a sort of `timestamp` — a creation event and the
  initial `ADD_ITEM` rows share one instant deliberately. Events are appended
  at the next free sequence and never re-sorted, so a backdated clock, a
  reopen, or a re-close extends the timeline instead of rewriting it.
  `sequence` is serialized in Hive, carried on the wire, and included in the
  revision hash; it survives backup/restore because the backup stores the
  report row verbatim. Backend ingestion writes it straight into
  `AuditEvent.seq` when every event in a report carries one, and falls back to
  array position for an older POS build. `AuditReport.fromMap` numbers a
  report written before sequences existed from its stored array order (stable
  by timestamp), deterministically, so its revision still settles; the numbers
  reach the wire immediately and reach Hive on the report's next write.
  Historical rows are not rewritten eagerly.
- Cloud `AuditEvent` carries a denormalized `venueId`, copied from the parent
  report — that is, from the authenticated Device or Staff — and never from the
  payload. It is not a relation: the report's own foreign key is the tenant
  authority. `AuditReport.orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`,
  `RESERVATION`) is derived at ingestion from the report's own creation event
  and is null when no creation event proves one; `floor` is never used as
  evidence. Both are query metadata; the events remain the semantics.
- `AuditReport` still has no foreign key to `Order`, deliberately: Close Day
  deletes the operational Order row and the report, its events and their
  sequences have to outlive it.
- Audit report deserialization resolves missing times from the record itself,
  never from the clock, and reports are listed once per id. Both are required
  for a revision to settle; without them a report is dirty on every sync.
- Backups carry the audit box's keys (`auditLogKeys`, additive) and restore
  files each row under its canonical key, so a repeated restore updates rows
  instead of duplicating them. Keyless older backups still restore.
- Tables, orders, menu, staff, and `salesHistoryByDate` still use broad snapshot
  payloads; further sync windowing/scaling is deferred.
- The home takeaway panel is Order-backed. `TakeawayTickets.forBusinessDate`
  builds the queue from takeaway orders (`isTakeawayOrder`, the one definition
  of the floor/`TA-` rule), and list, counts, items, totals, status and actions
  all come from `Order`. A takeaway order with no reservation row renders
  completely, including guest name, phone and pickup time when supplied. Those
  three are additive Hive fields on `Order`; local, mobile, remote and Edge
  Takeaway creation/upsert paths populate the values they carry. A legacy
  Reservation lookup remains only as a display fallback when an old Order's
  new fields are empty.
- Routine Order sync sends Takeaway guest/pickup metadata directly from
  `Order`; it does not join the bookkeeping Reservation. Close Day likewise
  derives pending Takeaways from the centralized Order-backed source, excluding
  completed, cancelled, Walk-In and Package Orders.
- New Takeaway Orders no longer create Reservation bookkeeping rows; local,
  mobile, remote and Edge paths are Order-only. Historical `isTakeAway` rows
  remain supported and backup/restore preserves them unchanged.
- New Walk-In and Package Orders likewise no longer create Reservation
  bookkeeping rows. Walk-In remains Order + Table, Package remains package data
  applied to an Order, and only genuine advance-booking flows create new
  Reservation records. Real Reservation activation creates the operational
  Order while preserving and linking the existing booking.
- Reservations are only status-transitioned, never purged, so local reservation
  storage stays deliberately mixed: bookings alongside Walk-In, Package and
  historical Takeaway bookkeeping rows. Nothing rewrites old history, and
  backup/restore preserves all of it verbatim.
- Home refreshes counts, table state and Order-backed cards immediately from
  completed local POS mutations. Close publishes an Order lifecycle event only
  after the local transaction completes; this UI refresh is independent of
  Cloud acknowledgement and the periodic sync scheduler.
- Cloud `PosReservation` is real-advance-bookings-only. The POS projects its box
  through `ReservationClassification.projectForCloud` when it builds a full
  snapshot, and the mirror's existing "the list is the authoritative set"
  contract reconciles previously mirrored bookkeeping rows away. The canonical
  rule is `isTakeAway` or a `notes` prefix of `Order #`; `linkedOrderId` is
  deliberately not part of it, because an activated booking is still a booking
  and close-day nulls that field on past rows. An unclassifiable legacy shape is
  sent, not dropped. Each full snapshot logs a `[ReservationProjection]` count
  line carrying no reservation content.
- The narrower three-clause predicates that do consult `linkedOrderId`
  (`isRealTableBooking`, `isRealPosTableBooking`, the Manager `getReservations`
  filter) answer "is this an un-activated table booking" and are unchanged;
  Cloud consumers now receive an already-clean mirror.
- `ReservationSyncService` still issues one `posReservation.upsert` per record
  sequentially plus one reconciling `deleteMany`, so its cost tracks the number
  of rows sent. Measured before the projection at Vankisi: 2004 records,
  617-685ms, under 10ms of which is enumeration and mapping. `preOrderItems`
  stays on the wire unread by the backend; the POS needs it because the home
  takeaway panel renders and totals from those rows.
- `salesHistoryByDate` and `MenuSyncService` have the same shape: one
  sequential upsert per business day and per menu node.
- A POS edit only marks pending. The single automatic push is a 30-second
  periodic flush, and it sends the full snapshot rather than the realtime fast
  path, so an ordinary edit waits 0-30s and then re-sends menu and history.
- The realtime path is built but unreached: `syncRealtimeToManagerApp()` has no
  caller in `apps/operations`, and the `...Debounced()` helpers that edits do
  call are deliberate no-ops that only mark pending ("manual-first mode"). The
  backend already honours `realtimeOnly`, skipping menu, staff, reservations,
  all-time and per-day history.
- A routine snapshot carries staff identity and role but no PINs. The POS sends
  `pin` only for a member whose credential the backend has not acknowledged, and
  records the acknowledgment in `staff_credential_sync_state`; a server that
  reports `staffNeedingPin` gets those PINs back on the next snapshot. Ingest
  additionally skips bcrypt for a supplied PIN that already matches the vault
  entry of an existing member, so an older POS that still sends every PIN costs
  no re-hashing either. Only a genuine create or PIN change runs bcrypt now.
- Both POS and backend print one `[SyncTiming]` line per sync, from monotonic
  timers, splitting trigger wait / build / encode / network / ingest / audit.

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
  `20260905090000_audit_event_sequence_tenancy`.
- Immediately preceding state migrations:
  `20260904120000_audit_closure_semantics`,
  `20260903140000_pos_reservation_mirror`, and
  `20260903120000_audit_report_sync_revision`.
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
