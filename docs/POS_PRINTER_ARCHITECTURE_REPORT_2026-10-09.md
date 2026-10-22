# Generic printer architecture refinement

**Task status: NOT_DONE.** The generic design and an additive, tested station
queue/controller domain are implemented. This is **not** a completed production
printer integration, and physical qualification is **not** the only remaining
work. Production admission and physical activation remain held. No other Vynic
milestone was started.

Authoritative design: [VYNIC_PRINT_ARCHITECTURE.md](VYNIC_PRINT_ARCHITECTURE.md).
Current evidence: [proof directory](proofs/PRINT_ARCHITECTURE_3463ee40_2026-10-09/).
The October 6 report and all its sealed proof packets remain historical,
unchanged evidence. Their passed Windows/native checks are not attributed to
this new source.

## A — Starting branch and HEAD

`codex/docker-deployment-foundation`,
`3463ee406184fec7f53818416e11d0e5f5602c87`. The workspace already contained extensive
printer and unrelated WIP. This task edits the printer paths listed below and
the three relevant agent-state documents. No stash or index operation occurred.

## B–C — Retained work and architecture changes

Retained: Go service host/SCM boundary, authenticated loopback API, Flutter
renderers and current Hive writer, LOCAL spool, native helper and transport,
Hashicorp Raft/Bolt/SQLite/chunk/snapshot machinery, immutable receipts, optional
beep implementation, physical holds and RAW counterexamples.

Added `printstation` rather than replacing those packages. The new state machine
routes business outputs to station IDs, keeps physical attempts separate, binds
controllers explicitly and implements station FIFO plus definitive-failure
backup selection. `printcluster` carries that state in its existing durable
projection and replicates station payloads through the existing chunk protocol.
Old physical-config and new station-config modes cannot be mixed in one queue.
Staging permits 16 concurrent jobs within the existing 32 MiB byte ceiling, so
ten sources can stage small tickets concurrently. The 128-job retained proof
capacity remains an explicit production limitation.

## D–E — Logical routing and stations

The model has configurable id, Venue, name, open role text, enabled/sort order,
scope, optional LOCAL owner and ordered physical route IDs. Kitchen, Bar, Cold
Kitchen, Dessert, Expo, Receipt, Fiscal and custom names are representable. A role
does not implement fiscal or KDS transport.

Routing precedence is explicit station override, item, subcategory, category,
then Venue default. Within a rule, order-type-specific configuration wins over
the generic rule. Missing or duplicate destinations fail visibly. One line may
explicitly target several stations. Output identity is deterministic from
Venue + business effect + station + output kind, excluding source POS and physical
route. A changed payload under the same job ID is refused.

A full Venue catalog can contain shared Kitchen/Bar and per-Device LOCAL
receipts. Scope projections retain only the appropriate station/printer/controller
set, with separate configuration digests. Planning happens before projection;
filtered queue catalogs contain no business routing rules. They are not authority
grants. The production Cloud publication/UI bridge is not yet implemented.

## F–G — LOCAL and VENUE_SHARED

LOCAL has an exclusive FULL/WAL SQLite proof spool using the same station state
machine without starting Raft. It reopens durable work after process death;
interrupted attempts become uncertain. Cross-Device local ownership is rejected.
The spool lock uses the resolved directory, so an alternate directory alias cannot
acquire a second owner for the same database.
The existing production Hive path and earlier local Go queue remain available.

VENUE_SHARED station admission uses complete replicated immutable bytes,
committed per-station sequences and exact retry receipts. Proof callers map to
pinned Venue/Device/installation membership, including client-only POS agents.
Committed work survives source/leader exit. The new API is a Go component API;
normal Flutter -> local service -> authenticated shared LAN admission remains
unimplemented. It is not silently enabled through the existing held RPC.

## H — Raft responsibility

Raft owns logical durability/order, immutable identity, station configuration,
attempt reservation/result and recovery state. It does not own the printer
socket, fence a RAW receiver or elect physical ownership. Three full data voters
are the default; extra sources are clients. A witness-only participant is never
proposed. Five voters require an explicit higher-tolerance choice. Existing
loopback proof transport is not authenticated production LAN transport.

## I–J — Controllers and physical routes

Controllers retain explicit host ID, Go installation and Device mapping. Physical
printers retain stable identity, configured controller, frozen destination,
capability profile and enabled/failover mode. Configuration refuses endpoint
alias duplication, controller movement/rebinding, and unqualified fenced modes.
It holds incompatible capability changes while affected jobs remain unresolved.
Physical alias qualification still must rule out two different addresses/queues
for the same hardware; endpoint comparison alone cannot prove that fact.

RAW TCP and Windows RAW are the existing implemented transports. USB is through
its attached Windows queue/controller. IPP, LPR, KDS and
QUALIFIED_FENCED_GATEWAY are extension points, not working adapters. Typed route
states are AVAILABLE, OFFLINE, UNREACHABLE, HELD, UNCERTAIN and DISABLED.

## K–L — Fallback, ordering and uncertainty

Each job freezes the complete compatible primary/backup set. An attempt records
ID, job, ordinal, physical printer, controller, start/result time and diagnostic.
Definitive zero-byte/non-entered submission failure advances to the next route.
A positive Windows job ID, attempted write, partial byte count or inconsistent
transport result becomes UNCERTAIN. SUBMITTED proves transport acceptance only.

An unavailable controller may be bypassed through a committed no-reservation
decision. This transition races atomically with Begin: once Begin wins, timeout
cannot use that fallback path. A disabled route before dispatch records a
NOT_SUBMITTED attempt. A primary's K101 then K102/K103 retain station FIFO on the
backup. The synchronous synthetic controller adapter demonstrates these calls
and refuses a real physical sender.

UNCERTAIN never retries, falls back or silently releases the station head. It
also holds that physical printer if another station shares it. Bar on a different
printer progresses. Reconciliation leaves original attempts unchanged; a manual
copy has new identity and original/actor/reason/time audit. `ReconcileProof` is
explicitly synthetic: production reconciliation still needs verified controller
drain/downstream settlement and authenticated Staff policy. An operator assertion
does not fence an old paused writer.

## M–Q — POS-count behavior

| POS count | Shared profile | Consequence |
| --- | --- | --- |
| 1 | One data host | Durable queue; no machine-failure tolerance |
| 2 | Fixed one-host shared queue + client by default | No HA claim; add a third full participant for three-voter consensus |
| 3 | Three full voters | Majority survives one voter loss |
| 4 | Three full voters + one client | Same queue tolerance |
| 10 | Three full voters + seven clients | Same queue tolerance; sources do not become physical writers |

Six-source topology is also exercised. A dedicated gateway is optional, can be
a full participant, and owns its configured printers. A single gateway remains
an availability dependency. All-LOCAL configurations need no shared cluster.

## R–S — Kitchen, Bar and receipts

Khinkali -> Main Kitchen and Beer -> Bar produce the same station assignments
and deterministic output IDs from POS 1 through 10. Neither station is tied to a
source Device. Cashier receipts can stay LOCAL and belong to their Device;
shared receipts are an explicit shared station. No POS number has cashier or
kitchen authority. These are tested model behaviors, not a claim that the current
production Flutter business path has already switched to them.

## T–V — Replication, controller failure and physical guarantees

New tests exercise complete 700 KiB payload survival, lost admission ACK across
leader loss, replica rejoin, minority refusal, snapshot corruption, stable retry
identity and LOCAL process-kill/reopen uncertainty. The earlier three-process
Raft SIGKILL suite is rerun as a retained-component regression.

Controller loss does not discard a committed logical job. If no reservation
exists, the scheduler can commit a skip and use a different backup. If a
reservation or write may exist, the station holds. No new leader automatically
owns the same printer. One physical printer provides durable work and conservative
duplicate avoidance, not continuous production through printer/controller failure
or exactly-once paper. Backup printers on independently available controllers
add automatic continuation only for definitive non-submission. Same-printer HA
needs actual downstream enforcement; it is disabled here.

## W — Windows service behavior

The retained executable/host supports independent foreground/service entrypoints,
exclusive ownership, health/version/reader/helper checks and retained drain.
Existing service-control/queue lifecycle regressions pass. The installer still
plans `CREATE_STOPPED_MANUAL_SERVICE`; production automatic start/restart policy
is not implemented or installed. No SCM registration, service account change,
driver change, Windows reboot or service-principal print test occurred.

Native ARM64 station and queue tests ran in the existing Windows 11 VM under
`VANSKI\vaanskii`, not the future service principal. The VM was started for these
tests; the POS was not started. Actual Windows process-kill/reopen and queue tests
are software evidence only. They do not qualify boot-time printing.
After testing, the VM was gracefully returned to its original stopped state.

## X — Security and provisioning

Retain the existing TLS 1.3 loopback certificate/identity/expiry/revocation checks
and printer-purpose candidate validator. The new component methods derive Venue,
Device and controller from a pinned proof caller; job JSON cannot create that
mapping. The unauthenticated proof Raft hello remains restricted to loopback.

Production needs the server-owned issuer/enrollment bridge, signed station/scope
and controller configuration, protected revocation/high-water state, chosen
offline validity policy, authenticated LAN submission/replication and controller
receipt/drain ownership. None is replaced by a caller-filled Authority struct,
synthetic grant or boolean activation flag. No real credentials were created.

## Y — Upgrade and rollback

The design specifies: freeze old admission; inventory/drain/reconcile jobs and
native calls; preserve/import unresolved rows held; establish old-writer exclusion;
activate Go; verify; complete. Rollback fences Go first and never replays submitted
or ambiguous jobs into Hive. New station state is separately identified and old
strict readers refuse its fields; a supported production reader-floor/rollback
matrix remains to be built. The actual Hive cutover/import adapter and attachment
to every business print entry point are **not implemented** by this change.
The current production path is retained and recoverable.

## Z–AB — Validation and physical matrix

See `evidence.json` for final per-run counts, source hashes and separate software,
Windows and physical cases. Normal printer-only regressions, focused race checks,
Go vet and native Windows station tests are recorded with raw logs. Child fixture
entrypoints and opt-in performance are identified as skips, not passed hardware.
The initial sandbox-denied loopback run and Windows launcher argument failure are
retained as unsuccessful attempts.

Final combined normal selection: **519 PASS records, 5 explicit skips** across
ten printer packages. The full run is combined with reruns of the affected two
packages after scope projection and LOCAL tests after the alias-lock fix; records
are deduplicated by package/test, not added repeatedly. Focused race selection:
**42 PASS, 2 skips**. Native Windows ARM64: **42 PASS, 2 skips**. Go vet and
`git diff --check` pass. The 173-file final Go/SQL/fixture source manifest matches
the checkout. No Flutter source changed or new Flutter integration test ran.

All physical cases are **NOT_RUN**: controller power loss, Ethernet pull, printer
power loss, paper out, printer cable removal, switch partition, service kill
during a real write, before/during/after physical submission, cutter, optional
beep, Windows reboot, installed service restart, primary hardware failure and
physical backup output. Synthetic accepted bytes are never counted as paper.

## AC — Performance

`TestStationSoftwarePerformance` measures 1/3/10 concurrent source profiles,
two station queues, 4 KiB and 512 KiB frozen tickets, majority finalize, attempt
reservation/result commits, full node reopening/election, allocation and disk.
All replicas run on one Mac; these are bounded software observations, not a LAN
SLO or printer throughput. Recovery is process/store reopening, not power-loss
qualification. Results and raw logs are in the proof packet.

| Sources / voters | Payload | Submission p50 | Result commit p50 | Controller begin p50 | Reopen + election |
| --- | --- | --- | --- | --- | --- |
| 1 / 1 | 4 KiB | 39.9 ms | 17.1 ms | 16.1 ms | 1.37 s |
| 1 / 1 | 512 KiB | 138.2 ms | 27.0 ms | 29.3 ms | 1.94 s |
| 3 / 3 | 4 KiB | 197.1 ms | 39.9 ms | 42.8 ms | 1.61 s |
| 3 / 3 | 512 KiB | 595.9 ms | 68.7 ms | 64.9 ms | 1.38 s |
| 10 / 3 | 4 KiB | 428.5 ms | 39.4 ms | 35.2 ms | 1.48 s |
| 10 / 3 | 512 KiB | 2754.8 ms | 228.2 ms | 233.5 ms | 1.64 s |

Each profile submits to two stations (2/6/20 jobs). The ten-source 512 KiB run
grew replica files by 248,439,616 bytes and post-GC live heap by 157,117,080 bytes,
with 29,785,184,320 cumulative allocated bytes across the three in-process
replicas. Cumulative allocation is not peak memory. Small negative heap deltas in
other cases reflect GC/noise; this is not a memory-release guarantee. Performance
was measured before the final LOCAL directory-lock-only fix; its replicated
queue execution path is unchanged, with both source manifests retained.

The measured ten-source large-raster case exposed full-projection copying and
serialization costs. The storage engine is a bounded correctness proof with no
production pruning/retention. It must move to separately retained payloads and
incremental normalized state with tested snapshots and admission receipts before
production. Raising limits alone would amplify the problem. Raft's logical role
and the station/attempt model can remain.

## AD–AF — Files, evidence and commits

- Added `apps/edge/internal/printstation/{model,state,controller}.go` and
  `state_test.go`.
- Added `apps/edge/internal/printcluster/stations.go`, `station_local.go`,
  `station_controller.go`, `stations_test.go`, `station_controller_test.go`,
  `station_process_test.go`, `station_performance_test.go`.
- Extended existing `printcluster/{state,projection,types}.go`; old APIs and
  safety holds remain.
- Added this report, `VYNIC_PRINT_ARCHITECTURE.md` and the new proof directory.
- Updated the relevant facts in `VYNIC_PROJECT_STATE.md`, `VYNIC_CODE_MAP.md`
  and D034 in `VYNIC_DECISIONS.md`.

No Flutter, backend, website, inventory, Manager, operational Order authority,
generated contract, migration, secret or live configuration was edited by this
task. No commit or push: the user's conditional acceptance level is not achieved.

## AG–AH — Final status and remaining decisions

**NOT_DONE / production integration and physical activation held.** Calling this
only IMPLEMENTED_NOT_PHYSICALLY_QUALIFIED would conceal missing software. The
station/attempt design is suitable as the generic direction, but acceptance still
requires production storage/retention, authenticated service and Flutter admission,
configuration publication/UI, durable controller receipts, safe reconciliation,
Hive cutover/rollback, and automatic SCM lifecycle integration.

Physical decisions: supported printer models/firmware and interfaces; fixed
controller placement or optional gateway; independent backup printer/controller
placement; service identity and queue visibility; operator reconciliation policy;
and, only if same-printer automatic takeover is desired, a qualified downstream
fence. None requires optimizing for one particular restaurant.

## Plain answers

1. **Long-term architecture:** yes to the four-layer station/queue/controller/
   printer design; the current proof implementation is not production-ready.
2. **One physical printer:** immutable durable jobs, ordered conservative
   dispatch and visible uncertainty; no printer-failure availability or
   exactly-once paper guarantee.
3. **Automatic production fallback:** optional independent backup printer and
   available controller for definitive non-submission. Uncertain output still
   requires reconciliation. Same-printer takeover additionally requires fencing.
4. **1/2/3/4/10 POS:** standalone; standalone or add third full participant;
   three voters; three plus client; three plus seven clients. LOCAL-only needs
   no shared queue. Queue HA never implies physical HA.
5. **Kitchen source independence:** yes in the tested station domain; production
   business-path integration remains pending.
6. **Bar source independence:** the same; it is normally shared preparation.
7. **Local receipts:** yes, with independent Device-owned durable spools.
8. **Unsafe same-RAW takeover:** none is enabled; fenced failover mode is refused.
