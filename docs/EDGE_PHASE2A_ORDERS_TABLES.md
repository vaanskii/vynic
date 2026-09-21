# Edge Phase 2A — Orders/Tables shadow coordination

## Locked scope before implementation

Phase 0 Primary POS remains the sole production operational writer. This phase
adds an authenticated SHADOW Order/Table projection on the bound Edge. No Cloud
active Edge selection or production authority cutover is implied. The local
`authorityEpoch=1` fences this projection generation; it is not a Cloud lease.
No automatic promotion, failover, destructive reseed, or epoch reset API exists.

Order UUID and OrderLine UUID are additive to legacy Hive integer/display IDs.
Existing data is assigned IDs once in a versioned Hive migration. Clones and
serialization preserve them. Tables use the existing layout-owned canonical physical Table UUID; floor/number remain display aliases.
Order/Table revisions belong to the Edge projection; revision zero means absent.
A committed tombstone is retained and cannot be resurrected under the same ID.

A request has an immutable UUID, authenticated originating terminal, epoch and
complete proposed post-images with expected revisions. Edge serializes validation
and atomically commits post-images, incremented revisions, one Venue/installation
sequence, the event and the exact request result in SQLite. Same request retries
return the original result; changed payload/origin with that ID is rejected.
Revision conflicts return every touched current entity and never partially apply.
Conflict results are also durable; retrying a rejected intent requires a new ID.

Flutter retains business calculation. Its coordination client persists the intent
before sending, applies only committed results, and advances a Hive projection
cursor only with the whole event. It replays missing events before accepting a
new proposal. A lost ACK leaves the same durable request for retry. Snapshots
include state, tombstones and sequence from one SQLite transaction. No event
compaction is performed in this phase; replay from zero remains supported.

Shadow observation records a proposed intent before the operational Hive write,
then compares the committed Edge projection to the actual operational result.
Failures/mismatches are diagnostic and cannot veto the Phase 0 primary operation.
Shadow data never flows back into production Hive. The isolated convergence
harness instead reconciles two independent Hive projections from committed Edge
events, exercising the future ACK flow without granting restaurant authority.

Production cancellation also writes a Sale; transfer-close writes closure and
reservation history. These remain under Phase 0, as do payment, close, advance,
restore, Close Day, inventory, printing and Cloud transport. A production rollout
gate must not be enabled until all bypasses and those interactions are fenced.
The Phase 2A shadow protocol is additive (1.1 + orders_tables.shadow capability),
and existing 1.0 foundation clients remain compatible. SQLite upgrades from 1 to
2 transactionally; downgrading the binary refuses schema 2, never resets it.

## Implemented entry points and exact wire contract

- `packages/contracts/proto/vynic/edge/v1/orders_tables.proto`: `Commit`, `Replay`,
  `Snapshot`; generated Go/Dart stubs accompany the existing Foundation service.
- `packages/contracts/schema/orders-tables-projection.schema.json`: JSON document
  shape inside a projection entity. Monetary **snapshots** of ordinary line price,
  quantity and calculated total are opaque to Go; Go performs no pricing rules.
  Payment, advance, discount adjustment, package, closure and Sale fields are not
  accepted. Flutter's codec refuses those unsupported operational Orders.
- `apps/edge/internal/store/coordination.go`: compare-and-swap, request digest,
  durable conflict/commit results, consistent replay/snapshot and occupancy checks.
- SQLite migration `002_orders_tables.sql`: one coordination head/epoch,
  projection rows, append-only committed events and request results. The immutable
  installation supplies Venue scope; there is no client-selectable database tenant.
- `apps/operations/lib/core/services/edge/orders_tables/`: codec, durable client,
  observer and existing POS-to-shadow projection. `OrderTableCoordinator.prepare`
  writes and flushes the request before transport. It preserves the caller's expected
  revisions; catching up never silently rebases stale edits.
- Hive migration 9 persists additive Order/OrderLine UUIDs. Legacy numeric Order
  IDs remain unchanged. JSON, clone, adapters and backup preserve IDs. A full
  unmerged line move preserves its UUID; a split creates a new line UUID and an
  existing destination merge retains that destination line's identity.

`CommitResult.CONFLICT` carries all touched current post-images (revision 0 for a
never-existing entity). Successful results carry complete changed post-images,
sequence, epoch and originating terminal/request. Changed request reuse returns
`AlreadyExists`; invalid schema/cursor returns `InvalidArgument`; wrong epoch or
protocol returns `FailedPrecondition`. A rejected revision result is durable, so
later edits cannot turn a retry into a success. Credential, Venue and installation
validation precede all three RPCs. The 1.0 Foundation client remains supported;
coordination requires 1.1. No existing Cloud command version is changed.

The store also validates bidirectional Order/Table occupancy and globally unique
live line UUIDs before commit. Releasing/occupying Tables and changing the Order
must occur in one intent; invalid references roll the whole transaction back.
Order/Table tombstones retain their next revision with empty document bytes.
Removed lines are represented by complete Order post-images: consumers replace
that Order's line set, never merge absent lines back in. There is no resurrection
or tombstone expiry API. Cancellation tombstones remove a shadow projection only;
they are **not** authority to cancel an Order or write a Sale.

Bounds for this development phase: at most 100 touched entities/request, 8 KiB
per entity document, 256 retained entities including tombstones, 1 MiB incoming
RPC, replay pages at most 100 events/approximately 2 MiB. Reaching a limit fails
explicitly; production operation does not depend on this bounded shadow store.
Events and idempotency results are not compacted. Capacity/retention is a rollout
prerequisite, not an invitation to reset a store.

## Shadow attachment and coverage

Normal POS startup never creates a coordinator or sets `OrderTableShadow.observer`.
Its default is null. A development attachment supplies a paired authenticated
client and a **separate shadow Hive box**, calls `open`, then attaches an observer.
At a quiescent point on the Phase 0 Primary, `seedPrimary` with
`PosShadowProjection.currentSnapshot` seeds an empty projection and verifies the
comparison. It refuses non-empty Edge history and reports unsupported live state;
it never clears/replaces that history. No Venue setting enables operational Edge
writes, no independent terminal becomes a production writer, and no active Cloud
Edge/epoch pointer is introduced under a foundation grant.

Observed production paths: ordinary walk-in and takeaway creation, ordinary
`updateOrder`, item transfers, Order screen table moves, and cancellation's
Order/Table tombstone projection. Proposals precede the existing Hive writes.
Nested repository observers are suppressed within the outer logical operation so
a transfer compares one atomic change set. Cancellation's Sale, reservation and
audit effects still execute exclusively in the existing Flutter transaction.
No payment/close/restore/Close Day writer was moved or enabled on Go.

Diagnostics persist the last 100 outcomes in the shadow box (`matched`,
`mismatch`, `proposal_failed`, `operational_failed`, `comparison_failed`,
`uncompared`) and log via `EdgeOrdersTablesShadow`. Proposal/network/schema failure
still runs the Primary operation and is never reported as a clean comparison.
The durable pending proposal remains retryable after an uncertain network result.
A changed operational result is not silently uploaded as a correction.

**No production authority rollout gate is added in Phase 2A.** The ordinary-order
simulation is clean, but it does not establish complete production shadow
coverage. Mobile/Cloud upserts, status-only writes, layout/reservation transitions,
package/adjusted Orders, transfer-close and close/restore remain existing writers.
They can produce unobserved or unsupported changes. These are explicit reasons to
withhold the conditional production gate, not to enable a partial cutover. An
isolated coordinator is not safe to attach to production Order/Table boxes.

## Hive reconciliation and recovery

A single Hive frame contains the immutable Venue/installation/terminal binding,
shadow epoch, projection entities, cursor, pending request and last result. Secrets
are not copied into the pending intent. A frame write is flushed before continuing.
Persistence failure marks the coordinator unready. Typed Order/Table boxes in the
isolated simulator are rebuildable views of this frame; replay and bootstrap use
complete post-images. While those views are rebuilding, `ready=false`; callers
must not expose partial cross-box state. Startup rebuilds them before becoming
ready. This is a recovery/readiness boundary, not a claim that Hive supports a
multi-box database transaction.

ACK handling replays preceding events from other terminals before advancing to
its own event; it never jumps the cursor straight to the ACK. Retry after lost ACK
uses the same request and terminal, including after process death. Replay gaps,
backward sequence, changed binding and incompatible epoch fail closed. A snapshot
cannot replace a projection with an unresolved pending request or an older cursor.
Integer display numbers in isolated typed boxes are local UUID-to-number aliases;
they do not serve as distributed identity or a global receipt-number allocator.

## macOS proof

Resolve backend dependencies, `flutter pub get` in `apps/operations`, and the
Phase 1 Dart simulator dependencies, then use the pinned tools from the Edge
README and run from repository root:

```sh
apps/edge/tool/mac-dev.sh --phase2a
```

This runs all Phase 1 proofs plus `tool/phase2a_proof.py`, invoking
`apps/operations/tool/edge_phase2a_terminal.dart` as separate OS processes with
separate credentials and directories. Each has actual typed Order/Table Hive
boxes. Flutter's Order model calculates the shadow result. Go runs as a real TLS
gRPC process backed by SQLite/WAL; the disposable Nest/PG fixture provisions its
identity. Nothing connects to a live restaurant database. Captured evidence is in
`docs/EDGE_PHASE2A_PROOF.json` and `docs/EDGE_PHASE2A_VALIDATION.md`.

The proof includes deliberate mismatch injection, two simultaneous stale-base
edits, stale Table occupancy, missed events, atomic table relocation, duplicate
request after lost ACK, abrupt terminal exit and Edge SIGKILL, snapshot agreement,
tombstone replay/no resurrection and clean restart. Backend Phase 0 fencing tests
remain part of the same harness. Windows cross-compilation remains required;
actual Windows runtime/service/ACL proof remains outstanding.

## Exact Phase 2B prerequisites

1. Complete production shadow coverage and gather zero unexpected mismatches,
   unsupported/uncompared operations and replay gaps across representative Venue
   workflows, including the remaining writers listed above. Preserve integer
   display IDs/Cloud aliases without allowing collision to become authority.
2. Add separately authenticated Cloud selection of one active operational Edge
   per Venue and monotonic authorityEpoch. Bind terminal write admission to it.
   Prove manual old-host fencing, clone/restore rejection and explicit handover;
   foundation grants/local shadow epochs are not sufficient.
3. Add a disabled-by-default, explicit per-Venue Orders/Tables rollout gate only
   after those proofs. Route every in-scope writer through detached intent → Edge
   ACK → Hive reconciliation; prevent bypass via screens, repositories, remote
   commands and stale full snapshots. No automatic failover or independent Hive
   writer when Edge is unreachable.
4. Establish interaction/fencing boundaries with payment, Sale/close, advance,
   restore, non-fiscal close, transfer-close, cancellation history, Close Day,
   packages and reservations before enabling real multi-POS operation. Do not
   implement those authority migrations merely to turn on the Orders/Tables gate.
5. Prove audit identity, terminal lifecycle/readiness UI, unresolved-intent/conflict
   operator handling, background replay/reconnect and no reads of partially rebuilt
   typed Hive views. Preserve pending outcomes across disk/write failures.
6. Define production capacity, snapshot paging, log/idempotency retention,
   compaction, permanent line/entity retirement policy and upgrade/rollback.
   Preserve cursors and request results through backup/restore; never reset to
   evade a limit or a schema mismatch.
7. Test actual Windows coexistence, service lifecycle, permissions, certificate
   distribution/rotation, terminal rotation, disk-full and power-loss recovery.
   Cross-compilation and SIGKILL tests alone do not prove these.
8. Reconcile the Primary's Hive state and outstanding Cloud/local journals before
   any controlled cutover or rollback. Keep Phase 0 fencing and unchanged Cloud
   command ownership until a separately authorized transition proves no dual
   writer interval. Custom venue-web/BOG remains outside this work.
