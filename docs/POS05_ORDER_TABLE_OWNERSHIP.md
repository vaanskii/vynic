# POS-05: one active Order per physical Table

Status: **ACCEPTED for exact committed `ec430880`; Windows acceptance pending**.
Scope: one operational POS process, its local screens, and incoming Manager/
Edge writers. This does not enable independent offline multi-POS authority.
Windows VM operations are held. No customer storage or running POS is used.

## Result and acceptance

The previous create path could read a free Table, yield while writing an Order,
and admit another creator against the same free projection. A stale model or
screen could also overwrite a later edit or detach the Table from its owner.

Ordinary logical writers now share a reentrant process-wide mutation owner.
Inputs, business dates and editable Order images are captured before queueing.
After acquiring the owner, the writer validates the current identity/image and
physical ownership before creating an intent, changing data or appending audit.
Views and dialogs do not hold this owner for their lifetime. Conflicts show a
Georgian reason and require refreshing the current Order before retry.

Create, Reservation activation, physical Table movement and cancellation use
additive durable intents. Cancel/payment and other competing writers cannot
produce two accepted settlements or two owners. Existing item-transfer,
closure and Close Day journals retain their own recovery responsibilities.

## Protocol and recovery

- `orderTableMutationV1:<SHA-256 of request ID>` in the existing meta box stores
  protocol version 1, immutable request/fingerprint, before/after effects,
  business date, stable Order identity, outcome and the next durable effect.
- Actual store writes and flushes precede each flushed phase advance. A restart
  accepts the exact persisted prefix, completes the planned effects once, and
  retains the completed receipt. A completed receipt never replays over later
  edits. Reusing an ID for a different request is an explicit conflict.
- Cancellation captures its non-revenue history Sale, typed audit, genuine
  linked booking and Table effects; the terminal Order status is written last.
  A cancellation records no collection. Fiscal Sale and advance history are
  not repriced or rolled back by ownership recovery.
- `DatabaseCore.open` recovers pending ownership intent before Menu recovery,
  schema migrations, defaults or operational UI. Recovery cannot select a
  winner from unrelated/ambiguous persisted data. A failure latches admission
  until recovery succeeds on restart.
- Format-2 backup/restore validates the plan and persisted prefix before store
  replacement and completes restored intent while it owns admission. Modern
  Order/Reservation snapshots retain captured values and line identities;
  legacy import keeps its existing compatibility behavior.
- Hive schema remains v9; existing adapter fields are unchanged. An additive
  `reservationLineIdentitiesV1` bootstrap persists legacy pre-order line IDs
  after migrations and before new business operations. It does not repair
  occupancy, prices, booking status or content.

Main paths are `apps/operations/lib/core/database/local_data_admission.dart`,
`repositories/order_table_mutation_repository.dart`,
`transactions/cancel_order_transaction.dart`, `repositories/backup_repository.dart`
and `hive_migration_service.dart` beneath the same database directory. Public
model/repository/façade, POS screens and incoming command writers use the guard.

## Existing inconsistency and operator recovery

`DatabaseService.getOrderTableIntegrityReport()` reports duplicate Order IDs,
multiple physical Table rows, multiple active owners, missing/incorrect Table
projections and orphan Table owners. The Home screen exposes the report state.
Existing records remain readable; startup layout seeding, cleanup and duplicate
audit cleanup do not silently choose or rewrite a winner.

Relevant mutations and updater/rollback readiness refuse unresolved ownership.
Ordinary Table release cannot detach a live Order, and a direct physical model
terminal-status save cannot bypass cancellation/closure ownership. Controlled
journal recovery may finish its exact interrupted prefix.

For a conflict, refresh the Order and retry after checking the current owner.
For an interrupted persistence message, restart the same validated version and
let startup recovery finish. For a repair report or malformed journal, preserve
the store and obtain an explicit repair decision; do not delete intent, alter
current date, invent an owner or launch an older binary to bypass the check.

## Verification gates

Exact committed-source evidence is recorded in
`docs/proofs/POS05_COMMITTED_ec430880_2026-10-02.json`. Clean Git copies of
`ec430880fc092a6847dbbc7e937ea083533534ba` pass 738 distinct Flutter tests
in 62 suites, including the original 723 cases and 15 committed enrollment
cases. All 280 ownership and 88 transfer SIGKILL/restart checkpoints,
52-file format, 55-file analysis and the main_pos development build pass.
No uncommitted runtime code or tests are included. The following gates
passed on the exact committed runtime:

1. Independent public-entry properties: stale edits and money, local/local and
   local/remote create, cancel/payment, manual/stale Table release, legacy
   startup, duplicate Table lookup, refusal before audit, and model bypass.
2. Existing POS/Menu/backup/financial/command/startup/migration and widget
   regressions, plus new ownership, every-write failure, lossless pending
   restore, malformed-plan and legacy identity proofs.
3. Actual SIGKILL at each instrumented put/flush boundary, without closing Hive
   boxes, followed by a different native reader process, exact identity/value
   checks, second recovery and caller retry. POS-03 native recovery is rerun
   after the shared writer/model changes.
4. Scoped formatting/analyzer and a `lib/main_pos.dart` macOS development build
   with `APP_ROLE=pos`; the application is not launched.
5. Exact-manifest integration, protected working-file preservation and review
   of the staged commit. No push, deployment or merge is performed.

Process interruption tests flush the completed prefix. They establish recovery
from process death, not arbitrary power loss or filesystem/controller failure.
macOS development compilation is not Windows or printer qualification.

## Validated source identity and rollout

The initial working-profile proof in `docs/proofs/POS05_2026-10-02.json`
included three unrelated runtime WIP files: `pos_first_run.dart`,
`pos_enrollment_service.dart`, and `sync/api_config.dart`. Their changes
predate POS-05 and concern development URL helper text, loopback
classification and default HTTP ports. The exact committed-source rerun
excludes all three changes and passes; they are not required for POS-05
acceptance and remain user-owned WIP. Historical working-profile proofs
are retained, but the committed-source proof above is authoritative.

The original working directory still contains those changes. Windows
smoke must use a clean frozen export of `ec430880` with the committed-source
manifest, not copy the dirty working directory. Source hashes must match.

Windows smoke remains **PENDING_NOT_RUN / HELD**. It must use a frozen validated
source/checklist or a separately validated committed profile, with matching
hashes. Do not disable old POS-03 checksum checks or test moving/uncommitted
source silently. See `docs/POS05_WINDOWS_SMOKE.md` for the frozen-source checklist.

Update/rollback readiness rejects pending intent, malformed metadata and
ambiguous ownership. Complete intent with a compatible reader before replacing
the binary. Binary rollback preserves Hive data; exact old/new Windows artifact
compatibility remains OPS-01 qualification.

Plan references: `MASTER_BACKLOG.md` POS-05 and `POS_MENU_EDGE.md` POS-05 in
`docs/audits/2026-09-29-f7bb982/`. The accepted sequence after this milestone is
**POS-02 → SEC-05 → OPS-01 → PROD-01**. Physical printing, secret custody and
Windows release claims require their own evidence and decision gates.
