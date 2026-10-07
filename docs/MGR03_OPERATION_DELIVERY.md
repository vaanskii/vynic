# MGR-03 — retained Manager operation delivery

Status: **DONE** from runtime commit `4c020120893cc8f360fe29e34c4e6237af8927bd`, verified on a fresh exact-commit export. [Source-identified proof](proofs/MGR03_COMMITTED_4c02012_2026-10-07.json).

The Manager reports completion only after a retained POS SUCCEEDED result.
QUEUED and CLAIMED mean accepted and pending; FAILED, UNAVAILABLE and unknown
outcomes remain visible. Qualification uses isolated synthetic data and cached
tools. The final source-identified receipt records exact committed verification.

## Requests and authority

The seven operation kinds are order_cancel, takeaway_cancel, takeaway_create,
dine_in_create, reservation_create, reservation_status and reservation_delete.
POST /mobile/operation-requests/:kind carries a stable UUID v4 and frozen body;
GET /mobile/operation-requests/:requestId reads the retained Staff-owned outcome.
Manager authentication resolves current Staff -> Venue; client actor or Venue
fields never confer authority. Reservation feature gates apply to admission and
status reads. Legacy mutation routes use the same guarded admission and require
a request UUID. MGR-05 Order editing and MGR-02 table repair remain separate.

A Venue-locked transaction validates the complete request, selects its ACTIVE
primary POS and creates one immutable MANAGER_OPERATION command. Duplicate
UUID/body retries retain its reference, device and result; changed bodies
conflict. A missing primary or required current-primary Order baseline is
explicit UNAVAILABLE without creating a command or allocating an Order number.
Creation freezes the server's business date and allocates a retained reference.
Cancellation freezes the original Order UUID/date from the POS projection.
Admission and ACK never mutate the Cloud Order/Table/Reservation mirrors or
broadcast fabricated operational completion. Subsequent POS sync owns those
mirrors. Cloud adds no LAN calls or legacy callback operations.

## Native durability and uncertainty

The additive MANAGER_OPERATION type fences older POS registries before effects.
The modern handler verifies the marker, operation type, actor, dates and allowed
status. Existing unguarded command behavior is unchanged. Guarded Edge intent
and terminal outcome must flush before execution and acknowledgment. Guarded
terminal and interrupted entries survive transport age/overflow pruning.

Order operations use the existing POS-05/POS-03 recoverable admission and sealed
receipts. Creation cannot overwrite an existing Order; cancellation checks its
original UUID/date and durable receipt. A pending business recovery or failure
to persist transport completion causes no failure ACK. Recovery/retry retains
the original outcome and preserves later local changes.

Reservation writes and audits explicitly propagate storage errors and flush
before success, including unchanged-status and absent-delete goals. There is
no new reservation atomic multi-box transaction. Interrupted reservation intent
or a storage-uncertain effect is durably FAILED with
manager_operation_outcome_unknown. It is retained, never automatically
reexecuted, dismissed or issued a new UUID; staff must reconcile at the POS.
A retained terminal transport result is acknowledged without running the handler.
The same conservative Manager policy applies to primary_replaced_outcome_unknown
and lease_expired_attempts_exhausted.

Manager supports pending, confirmed and cancelled reservation assignments.
The existing Cloud policy rejects completed/in-progress; the unsupported Manager
Complete button is removed. Completion/seating remains owned by the POS.

## Manager lifecycle

The scoped manager_operations_v1 Hive journal flushes UUID/body before HTTP and
result before completion feedback. A failed put/flush shadows optimistic Hive
memory as unknown; retries reflush the original intent. Known command IDs use
status reads. Navigation/restart restores the frozen draft, and origin/principal/
Venue changes fence late responses and stale actions. The shell checks pending
outcomes on foreground/resume and its existing polling cadence. The panel shows
assigned POS references and preserves unknown/uncertain requests. Safe terminal
records can be dismissed only after delete/flush; errors remain visible.

Fresh creation forms explicitly allocate a new UUID after prior completion,
even for identical details. Retrying a completed request returns its retained
result without HTTP. Pending, claimed and unknown requests cannot be replaced
by a new form. Reservation and Takeaway screens stay open while pending and pop
only on POS success; cancellation/status actions follow the same outcome model.
Existing print screens use accurate delivery copy; this is no printer transport,
driver or physical-paper implementation.

## Verification and limits

Exact committed acceptance passed 416 Flutter tests across 31 suites (85 MGR-03
client/native/widget cases and 331 regressions), 55 backend snapshot tests, and 24 actual
HTTP/PostgreSQL tests. All seven actual Cloud claim -> native Hive execution ->
lost ACK -> reopen -> successful HTTP ACK flows preserve later POS work and
leave Cloud mirrors unchanged. Twelve concurrent duplicate POSTs converge on
one command/reference. Authority, feature, validation, old registry/version,
lease/primary uncertainty, real journal/audit write failures and compact/tablet
navigation (320/1024 px) are covered. Independent source review approved the
seven paths without open correctness findings.

The SIGKILL runner verifies 21 selected checkpoints: each operation's durable
Edge intent, native effect flush and boundary before terminal Edge write. Every
reader runs in a different native process. These are three checkpoints per
operation, not every possible I/O or arbitrary power-loss qualification.
Analysis/format of 36 selected Dart files (including the generated contract),
generated-contract checks, TypeScript build,
Prisma validation and macOS development builds of both Manager and POS roles
passed on the exact export. All 2,117 regular files and 29 symlinks match the
runtime commit. The build-generated checksum-only Podfile metadata was recorded
and restored; runtime source stayed unchanged. Existing WIP was excluded from
the tested export and commits. The new server helper and HTTP fixture pass typed ESLint; legacy
service lint findings are measured against the clean base, not claimed clean.

Reproduction tools are apps/backend/tool/prove_mgr03_postgres.py and
apps/operations/tool/prove_mgr03_recovery.py. They require explicit cached
Node/Flutter/PostgreSQL paths, use owned temporary Hive/loopback fixtures and
install nothing. Fresh migration replay uses unchanged committed migrations and
a privately regenerated Prisma client. No schema or Hive adapter change occurs.
The final proof archive retains test selection, raw logs and source hashes.

POS-02 physical printer/driver/paper acceptance remains NOT_DONE/deferred.
Windows VM operations remain HELD. Windows release/device replacement remains
an OPS-01 gate. No customer/live restaurant access, deployment, merge or push is
part of this milestone. Existing unsupported Takeaway increment behavior (the
first increment creates quantity two) is adjacent and deferred from delivery
scope; no quantity behavior was changed here.

## Compatibility and operational rollback

Keep retained Manager and guarded Edge journals. Older Cloud rejects the new
endpoint; older POS refuses the additive command type. Never downgrade unresolved
work into an unguarded command or erase uncertainty to retry blindly. Recover and
reconcile with a compatible build before operational rollback or replacement.
