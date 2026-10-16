# POS-02.B — Authenticated Venue peer transport

**POS-02.B: DONE. Overall POS-02: NOT_DONE.**
This stage connects production printer identity to the existing logical station
queue. Physical dispatch is HELD. Flutter/Hive, production services, restaurant
storage, drivers, firewall rules and backend business authority are unchanged.

Evidence: [proof packet](proofs/POS02_B_2026-10-09/proof.json).
The accepted [architecture](VYNIC_PRINT_ARCHITECTURE.md) and
[POS-02.A provisioning](POS02_A_PROVISIONING.md) remain the foundation.

## A. Branch and HEAD

`codex/docker-deployment-foundation` at
`3463ee406184fec7f53818416e11d0e5f5602c87`. Extensive printer and unrelated WIP
preceded this stage. The proof includes a hash delta against the starting files.
No reset, stash, rebase, index operation or push occurred.

## B–D. Production transport, identity and RPC

`internal/printpeer` uses actual TCP and mutually authenticated TLS 1.3. It consumes
`printerprovisioning.ProductionStore`; there is no second identity/enrollment
system. Each connection proves possession of the exact certificate pinned by the
current production-purpose signed inventory. Foundation/candidate credentials
remain unusable. Numeric signed endpoint hints supply connection addresses only.
The wire envelope separately confirms protocol version, Venue and stable cluster.

Each RPC connection has one length-prefixed JSON request/response. The only
application operations are `submit` and `query`. A configured authorized client
can submit immutable station jobs; only a configured voter is an RPC target.
The server derives installation and Device from TLS, then checks station scope,
source Device, configuration digest and current grant. Request JSON cannot name
an arbitrary printer endpoint, controller, business master or Raft caller.
Unknown fields are rejected by the wire decoder. Application reprint admission
is deliberately refused pending the later business/reconciliation boundary.

Authorization is rechecked after reading a request, before station admission or
receipt lookup, and before releasing a response. Existing TLS connections cannot
retain learned-revoked/expired rights. A peer with stale inventory may need a
signed refresh before it can authenticate a new member; discovery cannot add it.

Limits: 16 MiB JSON frames; existing 8 MiB + 1 KiB primary payload limit; four Raft entries
per AppendEntries; each log command bounded by the existing Raft command limit;
64 MiB streamed snapshots; 32 inbound connections, eight active application
requests, 32 outbound calls and 16 queued Raft RPCs per process. Requests wait for
a bounded application slot. TCP dial is bounded at two seconds, each connection
at eight seconds. Client retries use at most six rounds, exponential delay and
an overall 12-second deadline. Raft supplies its existing bounded retry/election
behavior. Connections are tracked and closed on shutdown. No shared password or
unauthenticated broadcast is used. Configured voters remain trusted consensus
participants; Raft is not Byzantine consensus.

## E. Real Raft networking and storage

The production transport implements Hashicorp Raft's `Transport`/`WithPreVote`
interfaces. AppendEntries, votes, pre-votes, snapshots and leadership transfer
all use the same certificate checks. Clients cannot send Raft traffic. The Raft
header's node ID must equal the authenticated installation. The default proof
stream remains separate and is never selected by the production runtime.

`printcluster.OpenAuthenticated` reuses the existing Bolt log, FULL/WAL SQLite
projection, chunk admission, checksum-addressed payloads and snapshots. Production
storage pins bind Venue, cluster, scope and issuer, while the signed membership
journal supplies evolving participants. Proof pins remain exact and immutable.
Older proof binaries cannot read the production pin format. There is no automatic
migration of old queues or rolling-upgrade claim.

The signed configuration is itself committed and verified again on replay and
snapshot/reopen. Projection writes remain incremental. Neither RPC nor membership
updates serialize every retained ticket payload. Existing 30-day terminal-history
retention, unresolved-job holds, 128 unresolved jobs, 16 staged jobs/32 MiB staging,
256 pending request records and 64 catalog limits remain. Production membership
supports the provisioning limit of 256 identities. Retention scheduling remains
future work; queue capacity fails closed.

## F–G. Stable membership, controlled changes and joining

Authorization, client/voter role, queue leadership and configured physical
controller remain separate. A printer queue leader is never a business master.

A new enrollment joins as a client, including without an endpoint/listener. A
later signed voter assignment can open its first configured listener without a
restart; it cannot move an existing voter endpoint. After established members refresh their
signed inventory, that client can authenticate and submit without voting or
changing quorum. Three voters must be explicitly configured by the operator.
The runtime never counts online PCs to change membership.

For a one-to-three expansion, provision the two new full replicas with the signed
three-voter configuration first, then refresh the established host. The host
commits that exact signed target and projected station catalog into its existing
queue. It calls Hashicorp `AddVoter` serially using configuration-index checks.
The transition passes through a two-voter configuration requiring both voters;
there is no HA promise during expansion. Promotion does not imply caught-up
availability until the new quorum actually commits. An interrupted transition
resumes from the signed journal and Raft configuration after restart; it never
clears stores or bootstraps the joining replicas.

Existing voter removal/replacement, quorum shrink and voter endpoint movement are
explicitly refused by this stage's transition validator. They require a separately
qualified transition. New clients and one-to-three expansion are supported;
arbitrary fleet reconfiguration is not claimed.

Initialization is a separate explicit operator action, restricted to the first
published shared configuration (`revision=1`). Ordinary startup/reconnect never
calls bootstrap. A later expansion replica cannot initialize a second cluster.
An additive `runtime_queue` marker in the protected POS-02.A identity SQLite store
binds each queue to its canonical directory. If the identity survives but its
queue directory disappears, startup refuses to recreate it. Interrupted initial
creation can consequently require explicit recovery; deleting state is not a
repair procedure. No fresh installation imports an old identity.

## H–I. Topologies and stations

| POS sources | Proven mode | Queue availability |
| --- | --- | --- |
| 1 | One standalone full replica | Depends on that host |
| 2 | One fixed shared queue host + client | No automatic failover guarantee |
| 3 | Three full data voters | Two-voter majority |
| 4 | Three voters + one client | Same majority |
| 10 | Three voters + seven clients | Same majority |
| LOCAL-only | Existing exclusive local durable spool | No Raft or shared peer dependency |

Every source submits to independently ordered Main Kitchen, Bar, Cold Kitchen,
Desserts and Expo stations using configured UUIDs. Names have no special code
paths. The signed full catalog is projected with the existing `Catalog.ForQueue`;
jobs freeze that queue projection's digest. Wrong Venue/Device, unknown station
and foreign LOCAL submission fail closed. Full payload digests are checked on
actual replicas after restart. No Flutter planner is connected.

## J–K. Receipts, failures, loss and recovery

An ACCEPTED receipt comes only after majority log commitment and the leader's
durable FSM application. Followers redirect; clients never acknowledge a local
in-memory copy. Retries retain the same request ID, job ID and bytes. `Admission`
uses a leader/quorum barrier and returns the original job/input digest, station
sequence and commit index. A timeout or lost response leaves outcome UNKNOWN.

The process proof closes the submitting TLS connection before reading its ACK,
then recovers the exact result. Client exit, leader SIGKILL, full restart,
follower rejoin and snapshot/reopen retain acknowledged receipts and payloads.
The Windows equivalent uses process termination, not a Unix signal.

A minority cannot commit. Separate TCP fault relays close real replication
connections while every process remains running; restoring the relays allows
reconnection and exact receipt recovery. These relays forward opaque TLS bytes
and do not simulate Raft. Separate process kills also prove majority loss and
re-election. Offline members never reduce quorum or initialize replacement queues.

## L. Security and offline policy

Process tests cover unknown/unauthenticated peers, foreign Venue, wrong cluster,
wrong certificate, foreign Device, unknown station, foreign LOCAL scope, clients
attempting Raft, tampered signatures, invalid voter counts, stale generation,
revocation, open-session revocation, open-session expiry, clock rollback and
oversized framing. POS-02.A's existing expiry/issuer/purpose/storage tests are
also rerun. No private signer/key is written to logs or proof artifacts.

The POS-02.A policy is unchanged: **at most seven days from signed issuance**.
The process suite admits at `expiresAt - 1` without Cloud and refuses admission
result access at expiry. Learned revocation takes effect locally on refresh and
persists through restart. Unseen Cloud revocation remains effective on the next
verified refresh or expiry. A durable observed-time high-water rejects rollback.
This depends on protected storage and a trusted OS clock; full administrator image
rollback is not defeated. Longer disconnected operation stops new printer queue
authorization, but retains all jobs. This product limitation needs later owner
review if seven days is insufficient; this stage does not extend the policy.

## M–O. Process, Windows and performance evidence

The suite launches independent Go executables with separate identity and queue
directories, actual TCP listeners, real TLS certificates and signed disposable
production-purpose grants. No production signer is created or used. Non-Windows
fixture identity opening exists only under the `printerfixture` build tag;
distributable binaries require Windows protection. Windows fixtures still use
MachineGuid, DPAPI and the native directory ACL implementation.

Final results: **37 process test/subtest records**, **14 focused race records**,
**400 existing regression records**, and **37 native Windows records** pass.
The process entrypoint is intentionally skipped by the parent test runner and
executed in child processes. Six regression fixture/performance/backend-export
entrypoints are explicitly skipped; none substitutes for a required B case.
Exact tests, skips, binaries, versions and measurements are in `proof.json`. Windows ARM64 tests run in the existing
Windows 11 VM under `NT AUTHORITY\SYSTEM` through the VM executor. This is a native
process/DPAPI test, not an installed SCM service or service-principal qualification.
Both ARM64 and amd64 foreground binaries build. No service, driver, firewall or
printer configuration is changed. The initially stopped VM is returned to stopped.

Performance measures actual network admission of distinct 4 KiB and 512 KiB jobs,
including concurrent three- and ten-source calls. The final measurement runs with
the VM stopped and no concurrent test suite. The proof preserves each sample.

| Sources / voters | Bytes | p50 ms | p95 ms | Max ms |
| --- | --- | --- | --- | --- |
| 1 / 1 | 4096 | 31.532 | 31.532 | 62.159 |
| 1 / 1 | 524288 | 62.317 | 62.317 | 71.365 |
| 3 / 3 | 4096 | 120.162 | 181.202 | 199.885 |
| 3 / 3 | 524288 | 226.037 | 246.461 | 249.306 |
| 10 / 3 | 4096 | 194.918 | 275.333 | 290.45 |
| 10 / 3 | 524288 | 361.061 | 511.826 | 524.815 |

Percentiles use the lower empirical quantile; two samples at one source are not
a useful tail estimate. Three sources have six samples; ten sources have twenty.
The previous optimized component benchmark used one Mac with in-process replicas
and synthetic transport; its ten-source 512 KiB median was 349.7 ms (identical
payloads), or 325.8 ms for the separate distinct-payload run. The new measurements
include TCP/TLS, process isolation and current authorization checks. They are not
physical multi-PC LAN, printer throughput, power-loss or production hardware
qualification. Small sample counts do not establish a production tail-latency SLO.

An early full run exposed immediate slot refusal and an insufficient retry window
under concurrency/race instrumentation. Bounded slot waiting and six deadline-
bounded retry rounds corrected it; failed logs are retained separately. The final
suite and focused race checks pass. A final join review also added activation of
a first signed endpoint for an initially endpoint-less client; the process and
Windows suites cover that path. Child stderr is explicitly checked for race reports.

## P–R. Files, schema, evidence and commits

New entry points: `apps/edge/internal/printpeer/{wire,runtime}.go`,
`apps/edge/internal/printcluster/production.go`,
`apps/edge/internal/printerprovisioning/production_runtime.go`, and
`apps/edge/cmd/printer-peer/main.go`. Process fixtures/tests are purpose-isolated.
Focused changes adapt the existing queue constructor, pin validation, membership
projection and LOCAL spool without replacing storage. The complete before/after
hash list is in the proof packet.

No Prisma/backend/contract schema migration is added. `runtime_queue` is an additive
local identity-store table. The normalized station SQL schema stays version 2;
production pin version 2 is purpose-separated from proof pin version 1.

The foreground executable accepts an existing protected identity directory,
dedicated queue directory, Device UUID, independently trusted issuer public PEM
and optionally a signed grant file. `-initialize` is an explicit first-configuration
operator action. It registers no service and prints no tickets. Signed grant
refresh can be applied through the store owned by the runtime; automatic Cloud
renewal and SCM lifecycle wiring remain later work.

No commit: a focused standalone commit would depend on substantial pre-existing,
uncommitted printer packages. Their unrelated WIP is preserved. All older sealed
proof packets and reports remain unchanged. This packet adds new evidence.

## S–U. Status, remaining work and exact next stage

**POS-02.B is DONE** for this software boundary. Overall POS-02 remains
**NOT_DONE**. No physical writer, controller takeover, UNCERTAIN retry/fallback,
Flutter/Hive writer change or other master-plan milestone is activated here.

Exact next authorized-plan substage, **not started**:
**POS-02.C — Flutter/local Go admission and business routing.**
After that: POS-02.D controller receipts/recovery/reconciliation;
POS-02.E Hive cutover/rollback/service lifecycle; then actual hardware qualification.

## Vynic master roadmap status

The [master stabilization plan](audits/2026-09-29-f7bb982/VYNIC_MASTER_STABILIZATION_AND_RELEASE_PLAN_2026-09-29.md)
remains sequential. Printer work is the current authorized exception. POS-02.A is
DONE; this report qualifies only POS-02.B. Previously accepted POS/Manager/Menu
foundations retain their recorded status. INV-01 remains a partial location
foundation with transfers/UI/product decisions pending; the implemented inventory
subset is not full Inventory. Broader multi-POS business authority, deployment,
service rollout and physical printer acceptance remain separate gates. No
non-printer milestone starts or changes status in this stage.
