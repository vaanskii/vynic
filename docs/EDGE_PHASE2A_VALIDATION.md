# Edge Phase 2A validation

macOS proof uses a disposable PostgreSQL 17 cluster, the production Nest foundation
provisioning components, a real TLS Go process/SQLite WAL, and independent Dart
terminal processes with actual Order/Table Hive adapters. No live restaurant DB,
production POS startup, website/BOG, payment callback or hardware is used.

Captured machine-readable evidence: `EDGE_PHASE2A_PROOF.json`. Its directory names
are redacted; UUIDs identify synthetic installations/terminals, not credentials.
The final run logs are `/tmp/vynic-edge-dev.c6o0jC/`. PostgreSQL and spawned services
are stopped by the harness. Run it with `apps/edge/tool/mac-dev.sh --phase2a`.

## Results

- **13 Phase 2A process checks pass**, in addition to **16 Phase 1 checks**.
  Distinct paired identities and separate Hive directories are recorded in JSON.
  The final projection has 9 events/sequence 9; the lost-ACK request adds exactly
  one event after terminal exit and Edge SIGKILL. Both typed Hive stores and full
  projection frames converge. Replayed tombstones remove the typed Order while
  retaining its revision and refusing resurrection.
- **14 Go top-level tests pass under `-race`**, plus nested cases. The separate
  `TestCrashWorker` helper intentionally skips in its parent test process and runs
  in the existing foundation crash test's child process. New cases cover same-base
  concurrent edits, stale multi-entity conflicts, changed request reuse, exact
  durable conflict/commit retry, epoch/auth/version/tenant refusal, dangling-link
  rollback, event/result write failure rollback, Phase 1 schema upgrade preserving
  identity/terminals, committed-WAL recovery and uncommitted sequence rollback,
  malformed/unreplayable documents and excluded payment fields.
- **260 targeted Flutter unit/widget tests pass** across 19 files: new migration/
  durable-client tests plus existing Orders, Tables, item transfer, backup, remote
  status, takeaway, money, close/service fee and Order screen/widget regressions.
  The client suite additionally passes after final frame/type-lookup hardening.
  An integration regression asserts the real Primary repository has not saved its
  Order/Table (or cancellation Sale) when the shadow proposal commits, and checks
  the actual post-operation Hive result matches. The Sale remains Flutter-owned.
- **386 backend unit tests / 42 suites pass**, and backend build passes.
- **21 real Nest/PostgreSQL tests / 2 suites pass** in the disposable harness,
  covering foundation provisioning and unchanged Phase 0 operational fencing.
- Empty-database Prisma migrations and schema drift check pass. No new PostgreSQL
  migration is needed: Phase 2A adds SQLite schema 2 and Hive migration 9 only.
- Focused Dart analysis on all changed implementation/tests/harness and generated
  Dart contracts reports no issues. Existing Cloud and new protobuf generator
  drift checks pass; generated Go contract module builds independently.
- `go vet` passes. Final service and Go simulator cross-compile as Windows amd64
  PE32+ binaries with `CGO_ENABLED=0`. Python harness syntax checks pass.
- `git diff --check` passes. Unrelated dirty files/stashes are preserved; the three
  mixed files are committed with only Phase 2A hunks.

## Limits of this evidence

The shadow positive cases match, and an intentionally injected mismatch is
correctly diagnosed. This does **not** prove every production writer is covered.
The conditional operational rollout gate is therefore withheld; normal startup
has no observer attached and every status still denies production business
mutation authority. See `EDGE_PHASE2A_ORDERS_TABLES.md` for exact uncovered writers
and Phase 2B admission requirements.

Hive uses a durable single-value projection frame and rebuildable typed boxes,
with a readiness barrier. It does not acquire multi-box transactional semantics.
No native Windows runtime, service/ACL deployment, disk-full/power-loss guarantee,
production capacity/compaction, full operational cutover, or restaurant fleet
shadow deployment is claimed. No push/deployment occurred.
