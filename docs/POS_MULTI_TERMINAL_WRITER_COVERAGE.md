# Multi-terminal operational writer coverage

Architecture/design receipt, 2026-10-06. This document records required coverage
for three collaborating terminals and the next isolated implementation boundary.
It does not activate production authority or qualify a release. See
[readiness scope](POS_MULTI_TERMINAL_READINESS_PLAN.md) and decisions D018–D022.

## Implemented foundation versus pending integration

| Area | Current status |
| --- | --- |
| Go operational store | Isolated proof source implements pinned signed authority, immutable request/result retention, revision/read-dependency checks, transactional post-images/events/effects and replay. It does not calculate restaurant business rules. Actual Go runtime qualification remains separate from SQL checks. |
| Canonical kinds | Isolated source adds seven explicit kinds to the existing six, through additive migration 004, canonical proto and Dart domain. The uncompiled Go candidate uses schema 4 and stays in the sealed source handoff until SDK verification. Kind vocabulary alone does not validate business documents or enforce mandatory control CAS. |
| RPC | Canonical `operational_proof.proto` requires proof protocol 1.3. Generated bindings, authenticated wire adapter and fixture-only server verification remain pending. Normal server/startup must not attach proof authority. |
| Dart proof client | Dedicated flushed Hive frame, pinned identity, strict replay/result checks, pending recovery and retained settled-request receipts exist. Isolated scripted tests are not LAN or real three-terminal evidence. |
| Business planners/adapters | Detached ordinary physical/takeaway create, physical move and cancellation planners with an exhaustive journal adapter pass 20 isolated cases and affected legacy regressions. They require explicit canonical identities, frozen policy inputs and control CAS. Legacy recovery prefixes and the other writer families remain unsupported. No writer family below is production-integrated. |
| Manager retained-line changes | Detached `manager_items_planner.dart` and `manager_items_adapter.dart` admit Manager quantity/removal changes only, preserve retained UUIDs, fee/payment/ownership state and the exact existing item-diff report/audit. The adapter regenerates the draft and validates complete canonical links, Staff/policy/dependency reads and control CAS. Nineteen new cases pass on macOS and Windows, including three actual local-Hive command-applier parity cases; eight affected macOS suites pass 143 tests. Canonical identity bootstrap, authenticated origin capture and production command ingress/ACK remain pending. |
| Production operation | Existing Hive writers retain ownership. No operational proof attachment, dual-write path, authority promotion or production cutover is approved. |

Schema migration runs when the new store opens, even without proof authority.
An inactive capability therefore does not make an old Edge binary compatible
with the upgraded database. Signed reader floors and actual rollback/recovery
compatibility are release gates.

## Canonical state and ownership

| Kind | Required representation |
| --- | --- |
| `OPERATIONAL_CONTROL` | One stable Venue-owned UUID: global `lastOrderId`, `currentDayId`, admitted operational/recovery phase and recovery generation. Every shared mutation CAS-writes this row initially. |
| `DAY` | Stable dated business state, operated/closed status and totals. Local `currentDate` and `dailySalesTotal` become projections; operated dates derive from canonical days. |
| `ORDER`, `TABLE` | Complete business images with explicit canonical identity and ownership references. Numeric order number and floor/table label are business fields, not canonical identity. |
| `RESERVATION`, `PACKAGE` | Booking/package images and exact links. Purchased package data remains frozen in historical Orders. |
| `SALE` | Historical financial image, consumption snapshot and cancellation/return state. Business cancellation is not a canonical tombstone. |
| `AUDIT_REPORT` | Mutable report, lock/status and ordered event history. Separate from immutable audit effects. |
| `CLOSURE` | Closure identity and durable financial completion/reversal facts, with Order/Sale/Advance references. Local execution-journal progress is separate. |
| `ADVANCE` | Collection, amount, application and reversal state. Explicitly distinguish these records from ordinary Sales despite their current shared Hive box. |
| `EXPENSE` | Expense identity and financial state. |
| `STAFF` | Restaurant staff identity, role and permitted credential representation. Device/enrollment secrets are outside operational documents. |
| `OPERATIONAL_POLICY` | Typed service-fee, report-assumption and destructive-action policy, plus admitted menu/inventory/runtime revision references. No arbitrary settings blob. |
| Immutable `AUDIT` / `PRINT` effects | Stable effect identities, exact bytes and frozen context. Print includes Venue, route/revision, physical destination, profile, fixed owner and payload. |

`applicationData` may contain an exact typed caller result. It must not contain
hidden writes, recovery instructions or effects omitted from the canonical
transaction. Printer configuration retains its separate Cloud/Device authority.

All planning reads come from one immutable view at a verified canonical cursor.
Control CAS deliberately serializes the first three-terminal implementation and
fences number allocation and collection scans, including absent-row/phantom
checks. The admitted business API must enforce this rule; a comment or client
convention is insufficient for production. Go retains canonical storage and CAS
ownership; existing Dart planners retain business calculation and validation.

## Full writer matrix — all integration pending

Paths below are relative to `apps/operations/lib/core/`; line numbers are review
anchors and may move as implementation changes.

| Family / actual entrypoints | Complete required shared operation |
| --- | --- |
| Ordinary create/move/cancel: `database/repositories/order_repository.dart:93`; `order_table_mutation_repository.dart:1453,1634`; `database/transactions/cancel_order_transaction.dart:68` | Order, every affected Table, control allocator, mutable AuditReport and audit effects. Activation also updates Reservation; cancellation can update Sale and Reservation. |
| Edit/items/status: `order_repository.dart:678,731,895,915,935`; `models/order.dart:105`; `models/table.dart:50` | Order/Table ownership, AuditReport/audit and exact policy/package/menu dependencies. Detached Manager retained-line changes cover one bounded subset; new catalog quotes, POS modification PRINT, status/fee writers and all production ingress remain pending. Model `save()` guards do not cover direct box writes. |
| Confirmation/printing: `services/pos/order_confirmation_print.dart:12` | Confirmation, report/audit and all frozen ticket effects atomically. Existing local print admission before status save cannot run before canonical acceptance. |
| Transfer/split/merge/release: `services/pos/order_item_transfer.dart:152,258,294,326,570,939`; `order_transfer_journal_repository.dart` | Source/destination Orders and line identities, Tables, Reservation state, reports and audit. Existing pure line movement is reusable; surrounding live capture and pre-journal UUID persistence require extraction/migration. |
| Payment/closure: `database/transactions/close_table_transaction.dart:102,282,331,525`; `closure_journal_repository.dart`; `sales_repository.dart:82` | Closure, Order, Sale and frozen consumption, Advance application, released Tables, linked Reservation, report/audit and Day totals. No early local closure-ID save or parallel local completion. |
| Void/return/reopen/advance/expense: `sales_repository.dart:289,390,483,697,781` | Financial images, Closure reversal, reopened Order/ownership/Reservation, report/audit and Day totals. Preserve consumption reversal and historical snapshots. |
| Reservation: `reservation_repository.dart:42,226,291,486,551,666,762,855`; `database/transactions/activate_reservation_transaction.dart:34,145`; `table_repository.dart:345,439,509,756,791` | Booking and availability dependencies, Order creation/linkage, Tables, advances and audit. Scheduled activation/stale-table cleanup uses the same planners. |
| Package: `package_repository.dart:63,127,253,278`; `order_repository.dart:517` | Definition revision/audit; package-order creation reads the exact definition and preserves its purchased snapshot. |
| Day/close day: `business_day_repository.dart:86,158,186`; `database/transactions/close_day_transaction.dart:101,394,420`; `close_day_journal_repository.dart` | Control day pointer, affected Day records, Reservations/Tables/Orders, totals and audit. Resolve existing local journal keys explicitly. |
| Policy/layout: `settings_repository.dart:542–615`; `table_repository.dart` layout/default/consistency writers | Shared policy and affected open Orders atomically; stable Table layout identities and ownership. Financial-report assumptions/destructive-action policy need typed treatment. |
| Staff: `user_repository.dart:30,45,57,104,161,165,199,229,265`; `services/pos/pos_command_applier.dart:1033–1220` | Staff, authorization dependencies and audit. Defaults, role migration and remote changes are writers too. Credential-sync acknowledgement bookkeeping is local, not Staff authority. |
| Manager/Cloud/legacy remote: `services/pos/pos_command_applier.dart:143–1300`; `services/edge/pos_edge_command_handlers.dart` | Same canonical planners and stable command/request identity, exact retained outcome through lost ACK. Preserve one selected Cloud publisher/claimant; no new legacy callback operations or Cloud-to-LAN calls. |
| Restore/import/repair: `backup_repository.dart:848,1009,1217,1270,1366,1465,1516,1667,1845`; audit/closure recovery services | Exclusive fenced canonical import/recovery with atomic publication. Terminal-local restore/replacement/wipe cannot mutate shared projections. |
| Startup/defaults/migrations: `database/database_core.dart:211–240`; `audit_repository.dart:189,245,565`; `services/pos/closure_recovery_service.dart` | Resolve authority mode before legacy restore/journal recovery/default writers. Replay canonical outcomes instead of independently resuming old financial work. |

Two additional boundaries must remain explicit:

- `quick_order_repository.dart` drafts may remain terminal-owned until checkout.
  Checkout validates current canonical policy and uses a stable request identity.
  A remote service-fee change invalidates/reprices stale drafts at checkout;
  canonical open Orders participate in the shared policy transaction.
- `menu_repository.dart` and `inventory_repository.dart:14,63` keep their existing
  documented owners. Calculations bind exact admitted revisions/content hashes.
  Independent local edits/imports or unversioned terminal caches cannot silently
  change the inputs to a shared operation.

`services/pos/update/tracked_box.dart` wraps box writes and model saves for update
readiness; it currently provides no multi-terminal authority. Future attachment
needs explicit domain-classified admission for all such writers and scoped
projection/recovery application. Never turn each individual box write into an
independent shared business transaction.

## Implemented isolated planner/adapter boundary

1. `OperationalPlanningView`: detached immutable entities at one verified cursor,
   control revision, actor authorization and policy/catalog dependencies, plus an
   explicit stable identity resolver. No live Hive reads or clock calls.
2. Detached business plan factories: extract current create/move/cancel logic,
   retaining model calculations and existing intent validators. Freeze request,
   actor, time and generated identities once. Do not call live commit then diff.
3. Exhaustive adapter: convert every effect and read dependency into one proof
   request, with typed exact caller outcome and control CAS. Validate before
   `client.prepare()`, durable frame changes or transport.

| Existing ownership-intent effect | Canonical mapping |
| --- | --- |
| `orders` | `ORDER` |
| `tables` | `TABLE` |
| `settings:lastOrderId` | Control allocator; other keys require explicit reviewed mapping |
| `auditReport` | `AUDIT_REPORT` |
| `auditEvent` | Immutable `AUDIT` |
| `reservation` | `RESERVATION` |
| `sales` | Validated financial subtype; cancellation Sale is `SALE`, not `ADVANCE` |

Missing/ambiguous identity or foreign reference, unsupported effect/key, invalid
image or unbound read fails with a typed error before preparation. Stable UUID
mapping must cover legacy Hive keys and business references; terminal positions
and mutable labels cannot define it. New order number is control `lastOrderId+1`
under CAS. Existing legacy-prefix cancellation recovery must preserve its Sale
and report or return recovery-required; it must not invent replacement history.

Required isolated acceptance: no live writes during planning; equivalent complete
business images/outcomes; create counter/report effects; cancellation financial
and booking variants; unsupported inputs leave frame and transport untouched;
three clients racing for table/number; stale losers publish nothing; lost ACK and
reopen preserve exact outcomes and single effects. Passing this milestone covers
only these adapters, not the other mandatory families.

## Atomic size and qualification gates

Close Day and global service-fee changes can exceed the current 128-write limit.
Do not truncate targets or split them into independently visible commits. Before
admitting those operations, implement a bounded atomic transaction mechanism or
an exclusive staged operation with durable recovery and atomic publication.
Capacity rejection must occur before any business effect. Control CAS alone does
not solve transaction size or journal/event-retention limits.

Production attachment requires all of the following:

- Complete matrix coverage, coherent dependencies, stable bootstrap identity and
  explicit closure of every legacy direct writer; no dual local/canonical writer.
- Generated/authenticated RPC and fixture-server proof; protocol/reader-floor and
  schema migration validation with compatible binary rollback or controlled
  recovery. Rejecting an old reader is containment, not successful rollback.
- Three real authenticated terminals proving competing opens, edits, transfers,
  financial actions, reservations, day/policy races, restart, replay and lost ACK.
- Cloud-offline operation through the selected LAN coordinator; LAN partitions
  fail shared writes closed. No automatic failover. Fence the old offline host
  before handover; a newer Cloud epoch alone cannot stop it.
- One retained business/print effect identity and fixed printer owner; uncertain
  physical delivery is held without automatic retry or timeout-based reassignment.
- Fenced backup/import/replacement rehearsal, projection rebuild and recovery
  admission before startup writers, with exact signed source/binary evidence.

Store-only CAS, SQL checks, scripted transport and portable spooler tests do not
establish these production or physical-printing gates.
