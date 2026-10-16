# Printer production integration — current implementation and evidence

**NOT_DONE.** This change completes a substantial storage correction in the
existing Go station queue. It does **not** complete the requested production
shared-print software integration. Missing hardware is not the reason: the
production authentication, configuration, Flutter, controller and cutover work
listed below is still missing. Production admission and physical activation
remain held. No other Vynic milestone was started.

## A — Baseline and Git

Branch: `codex/docker-deployment-foundation`. Starting and final HEAD:
`3463ee406184fec7f53818416e11d0e5f5602c87`. No commit, push, reset, stash, index,
secret, migration or live-configuration operation occurred. Existing unrelated
WIP remains present. The new proof packet contains starting/final status and a
source-change manifest against the previous sealed printer candidate.

The accepted four-layer architecture is unchanged. Existing packages are
`printstation`, `printcluster`, `printqueue`, `printtransport`, `printeligibility`,
`printhost`, `printeragent`, `printerdaemon` and `printerprovisioning`, plus the
`printer-agent` executable. The production POS still calls `PrinterService` ->
`PrintQueue` -> `PrintJobRepository`/Hive -> the current native/TCP transport.
The Hive journal remains flushed `print_job:v1`/`print_job:v2` rows in `metaBox`.
The held agent and candidate validator do not confer production admission.

## B–F — Storage, performance, payloads, incremental state and retention

Schema 2 stores individually keyed records for immutable jobs, station sequences,
configuration snapshots, admission receipts, attempts, results and reconciliations.
Immutable bytes live in a separate checksum-addressed SQLite payload table with
explicit lengths and foreign-key-protected references. FULL/WAL commits publish
payload references, state transitions and applied indexes atomically. Failure
after writing but before commit rolls everything back; no receipt is exposed.
Reopening verifies blob digests, canonical row hashes, the complete row-set root,
references and the recovered state. Corruption fails explicitly.

Transitions copy mutable metadata and update changed SQL rows. They no longer
clone, parse, validate and rewrite all raster bytes on every command. The tests
install SQL triggers that refuse payload/job rewrites while reservations and
results commit. Immutable job metadata stays separate from mutable attempts.

Raft chunks transfer raw payload bytes and identify the frozen job and payload
separately. Finalization requires complete verified bytes. Once a payload is
committed, another job can reference that payload identity in one small entry.
Concurrent first transfers may still repeat chunks in the Raft log. Duplicate
admission retains exactly the original sequence, commit index and input digest.
A new request ID does not manufacture a second copy of an existing job.

Mutations wait for Raft majority commitment and leader FSM durability directly.
The former additional VerifyLeader/Barrier pair before every mutation was
redundant. Initial membership still has a barrier, and linearizable reads retain
their protection. A startup race exposed by the process suite was fixed before
the final passing run; failed intermediate logs are retained.

Snapshots serialize each immutable blob once. Their conservative total byte
budget remains 64 MiB. Raft keeps three snapshots and 32 trailing logs, with the
existing 64-entry threshold/20-second snapshot interval. Snapshots include
unfinished chunks and exact receipts, and restoration validates before publishing.

Explicit replicated compaction retains completed jobs, bytes, receipts, attempts
and reconciliation history for 30 days after the final event. QUEUED,
DISPATCHING, UNCERTAIN and unresolved FAILED work never expire. Retained reprints
pin their originals, including chains. Compaction retains monotonically increasing
station sequences and advances an admission time floor. Exact submissions older
than the collected history are rejected, not recreated. This does not promise
unlimited historical exactly-once behavior. Collected originals cannot be used
for byte-identical reprint admission.

The unresolved station-job cap remains 128. Terminal history uses the retention
and byte budget rather than consuming that pending-work count. Incomplete/rejected
requests remain bounded at 256, active staging at 16 jobs/32 MiB, catalogs at 64
and pinned peers at 16. Capacity exhaustion fails explicitly. There is no
production retention scheduler yet; full catalogs still need an operational
retention/migration policy before long-running production deployment. No automatic
schema-1 migration was added. Retained metadata maps are still scanned/copied in
memory; behavior near the history byte ceiling has not been performance-qualified.
SQL updates are incremental, but this is not a claim of constant-time CPU cost
independent of retained history.

| Sources / voters | Payload | Before p50 | After p50 / p95 / max | Result p50 | Allocated bytes | Replica disk growth | Snapshot bytes | Reopen/election |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 / 1 | 4 KiB | 39.9 ms | 21.5 / 21.5 / 21.5 ms | 7.8 ms | 879,256 | 283,512 | 14,997 | 2054.5 ms |
| 1 / 1 | 512 KiB | 138.2 ms | 60.2 / 60.2 / 60.2 ms | 7.9 ms | 30,275,664 | 2,942,520 | 708,804 | 1581.3 ms |
| 3 / 3 | 4 KiB | 197.1 ms | 82.9 / 83.8 / 83.8 ms | 23.2 ms | 10,336,728 | 1,950,576 | 24,920 | 1997.7 ms |
| 3 / 3 | 512 KiB | 595.9 ms | 171.3 / 199.6 / 199.6 ms | 19.8 ms | 253,017,328 | 29,012,088 | 719,019 | 1398.1 ms |
| 10 / 3 | 4 KiB | 428.5 ms | 194.0 / 280.1 / 280.6 ms | 19.6 ms | 50,537,392 | 6,840,528 | 59,000 | 1871.7 ms |
| 10 / 3 | 512 KiB | 2754.8 ms | 349.7 / 472.0 / 477.5 ms | 18.0 ms | 816,144,704 | 59,290,832 | 754,122 | 1469.2 ms |

The comparable 10-source/512 KiB admission median fell from **2754.8 ms to 349.7 ms**. Cumulative allocation fell from 29,785,184,320 to 816,144,704 bytes; replica disk growth from 248,439,616 to 59,290,832 bytes. The final snapshot is 754,122 bytes. Exact duplicate retry took 25.7 ms. Leader payload/reference persistence totaled 243.2 ms across 40 durable transactions.

With twenty **distinct** 512 KiB payloads, admission p50/p95/max was **325.8/394.7/399.5 ms**. Allocation was 1,217,769,096 bytes, replica disk growth 112,135,104 bytes, snapshot size 14,037,440 bytes, result commit p50 15.4 ms and reopen/election 1481.7 ms. Heap deltas, reservation timings, all persistence totals and raw samples remain in `evidence.json` and the logs.

All measurements use one Mac, all replicas in-process and synthetic transport.
Submission includes majority finalize and durable local application; result and
reservation timings include their commits. Payload persistence measures successful
FULL/WAL transactions containing payload/reference writes, including commit, and
is reported cumulatively for the leader. Allocation is cumulative across the
in-process replicas, not peak memory. The original comparison uses identical
payload bytes across jobs; a separate final stress run uses distinct payloads.
These are software measurements, not deployed LAN or physical throughput.

## G–J — Authentication, membership, publication and Admin configuration

**Not implemented as a production path.** Proof membership remains explicitly
pinned; three full voters, client-only extra sources and two-source fixed-host
profiles continue to pass component tests. Discovery grants no authority. The
version-2 proof peer marker now refuses older peers, but the transport is still
restricted to loopback and is not authenticated Venue LAN transport.

The existing TLS 1.3 local API and signed printer-purpose candidate validator
remain held. A production issuer/enrollment bridge, protected revocation/high-water
state and authenticated shared RPC/replication are missing. The existing backend
printer preparation produces PREPARED configuration. No signed station/controller/
activation-generation publication path was attached.

The current Admin printer controls and developer route catalog were inspected.
They still manage the prior role/destination model and held agent diagnostics.
No production Stations/Physical Printers/Primary/Backup management UI was added.

## K–N — Flutter, business routing, LOCAL and shared admission

**Not integrated.** The normal Flutter planner still enqueues in its Hive-backed
writer. `PrinterAgentClient.submitLocal` still expects the server's explicit
provisioning refusal. There is no new production Flutter -> local Go -> shared
LAN admission path. The real Menu routing configuration has not been migrated
to the station model. No synthetic rule was installed as restaurant configuration.

The existing station component remains source-independent, with deterministic
business-effect/station/output identity. Its LOCAL spool operates independently
of Raft and survives process loss. Shared accepted component jobs survive source,
leader and replica loss and retain exact retry receipts. Those results do not
prove normal Flutter exit or production POS-to-service integration.

## O–R — Controller receipts, recovery, reconciliation and fallback

The replicated logical attempts and synthetic controller adapter remain intact.
Durable controller-side receipts, production host drain/settlement and the
operator reconciliation boundary have not been implemented. `ReconcileProof`
remains a synthetic assertion and cannot release a paused physical writer.

Component tests preserve definitive-non-submission backup selection, uncertainty
holds, strict station FIFO and progress on independent stations. Partial writes,
positive native jobs and missing results never authorize automatic retry/fallback.
The synthetic adapter still refuses physical transports. No new physical writer
was activated.

## S–T — Hive cutover and rollback

**Not implemented or proven.** The old writer remains present and active. No
route admission freeze, unresolved-job import, old-writer exclusion, Go activation
generation or reverse cutover adapter was added. Retaining old code is not proof
of safe rollback after Go has submitted work. Such rollback must first fence Go,
drain/reconcile, preserve submitted/uncertain history and prevent Hive replay.

## U–W — Service lifecycle, principal and version gates

The held service executable and foreground/SCM host code are retained. The
installer still plans `CREATE_STOPPED_MANUAL_SERVICE` with `start=demand`.
Automatic boot start and bounded SCM crash recovery are **not implemented**.
Flutter still has no service-spawning path. No service was registered or started.

The eventual service principal needs these specific permissions, separately
qualified under its real SID:

- Modify its dedicated state directory, including SQLite database/WAL/SHM,
  Raft logs, snapshots and lock files. Ordinary POS users must not modify them.
- Read its server/LAN private keys and certificates; private keys must be
  inaccessible to unrelated users. POS client credentials remain separately owned.
- Read/execute the pinned agent and native helper, without permission to replace
  those binaries. The helper must run under the service identity and retained
  process/job ownership rules.
- Print/use access to each exact configured Windows queue, and visibility of its
  qualified driver/port mapping without an interactive desktop or prompts.
- Service logon under the selected virtual-service account or preprovisioned
  gMSA. It does not need LocalSystem or local administrator privileges. Installer
  administration and service-account runtime permissions remain distinct.
- Network access to explicitly configured peers and printers; firewall/account
  provisioning is separate from this software test and was not changed here.

Current-user VM success proves none of those service-principal permissions.
Actual SCM boot/recovery and principal qualification need Windows system testing,
not necessarily physical printers. Named-queue visibility and helper physical
submission additionally need the eventual driver/device configuration.

Storage, command and snapshot versions are 2. Schema-1 stores are refused before
schema changes, schema-1 binaries refuse schema 2, and the proof peer marker
excludes the prior protocol. This is a safe refusal boundary, not a production
rolling-upgrade, client compatibility or migration implementation.

## X–Z — Security, integrated matrix and Windows evidence

The final printer regression logs, affected-package rerun, race selection and
native ARM64 logs are retained in the proof packet. The new Windows selection
covers normalized persistence, payload corruption, exact retry, reader refusal,
snapshot/reopen, process recovery and the station topology components.

The required integrated A–Z matrix is **NOT_PROVEN_INTEGRATED**. No component test
is labeled as an integrated production pass. In particular there is no Flutter
process-exit proof, actual production shared client/voter runtime, Hive cutover,
rollback or application backup/restore integration proof.

The requested production security matrix is also **not proven**: wrong Venue,
foreign Device/installation, expired/revoked grants, stale/tampered configuration,
unknown station/printer, foreign-controller selection, unauthenticated LAN submit
and TLS mismatch require the missing production runtime and publication boundary.
Existing component/authentication regressions are retained without substituting
for that matrix.

Final printer selection: **524 PASS records, 5 explicit skips**, across ten packages.
The final affected-package rerun passes **132 records, 3 skips**. The race
selection passes **22 records, 2 skips**; its source differs only in timing
accounting, documented in the packet. Final native Windows: **58 PASS records,
2 explicit skips**. Skips are fixture entrypoints/opt-in performance, not hardware
passes. Go vet, formatting and final diff checks pass. The final source manifest
has no drift. The preceding sealed architecture packet still matches all 48
artifact hashes.

Windows tests ran under `VANSKI\vaanskii`, SID
`S-1-5-21-611125631-3759947118-1641436196-1000`, in the existing Windows 11 ARM64 VM.
They executed native ARM64 test binaries with hash verification in an isolated
guest temporary directory. The POS was not launched, no valid print document was
submitted, and no service/account/driver settings were changed. The VM was
returned to its original stopped state.

## AA–AB — Physical status and remaining decisions

All physical cases remain **NOT_RUN**. Required future named-hardware work covers
printer models/firmware, driver/queue identity, independent primary/backup devices,
RAW byte acceptance versus observed paper, power/cable/network loss, paper-out,
controller/service death during actual writes, buffered output/drain, cut/copy/
Georgian raster behavior, optional beep and backup output. Same-RAW-controller
failover remains unsupported without qualified downstream enforcement.

Software work is still required before this physical phase. The missing production
issuer/configuration, admission, controller receipts, reconciliation, cutover,
rollback and automatic service lifecycle cannot be deferred as hardware-only work.

## AC–AF — Files, proof, commits and final status

Changed Go/SQL/test files are enumerated with before/after hashes in
`proofs/PRINT_PRODUCTION_INTEGRATION_3463ee40_2026-10-09/changed-source-files.json`.
The central implementation files are `printcluster/normalized.go`, `clone.go`,
`snapshot_payloads.go`, `projection.go`, `state.go`, `stations.go`,
`station_local.go`, `node.go`, `transport.go`, `schema.sql`, and
`printstation/state.go`, `retention.go`. Focused tests and measurements accompany
them. The architecture, current project state and code map were updated for these
facts. Historical reports and sealed proofs were not rewritten.

Proof packet:
`docs/proofs/PRINT_PRODUCTION_INTEGRATION_3463ee40_2026-10-09/`.
No commit or push; the conditional software acceptance level was not reached.
**Final status: NOT_DONE.**

## Plain answers

1. Can the production Flutter POS submit through Go now? **No.**
2. Can any authorized POS send Kitchen/Bar jobs through the production shared runtime? **No; that runtime is not integrated.**
3. Does source exit lose accepted jobs? **The Go queue component retains accepted jobs; the production end-to-end path is not proven.**
4. Does LOCAL remain independent? **Yes in the Go spool component; normal Flutter admission is still unconnected.**
5. Is the known full-state storage blocker fixed? **The repeated full-raster copying/write mechanism is removed; see before/after and distinct-payload measurements above. Full production readiness is not established.**
6. Is backup restricted to definitive non-submission? **Yes in the retained state machine.**
7. Does UNCERTAIN prevent automatic retry/fallback? **Yes.**
8. Is automatic Windows service lifecycle implemented? **No.**
9. What needs real printers? **The named hardware/driver/output and failure cases in AA–AB. Considerable software work also remains.**
10. Is the old writer safely available for rollback? **Its code and journals are retained, but the controlled Go-to-Hive rollback procedure is not implemented or proven.**
