# Shared printing architecture

Candidate, 2026-10-06: three separate POS computers in one Venue share two
configurable printers. Each computer has its own Go process. Any one POS turning
off must not make the shared LAN printers unavailable to the remaining POS.
Flutter retains business planning, Georgian raster rendering and operator UI.
The explicitly selected Go Edge owns durable shared print admission and
background dispatch. Each Windows host has one independent Go service, including
client-only hosts. This is a migration target; existing production authority
does not change merely because a new component compiles.

## Why this boundary

The current Flutter `PrintQueue` durably stores work in Hive, but its sender
belongs to one POS process. It serializes destinations globally, so one stalled
printer delays another and separate POS instances can still compete. A Go host
can retain a common SQLite queue and run independently of the Flutter UI. Go
already owns the Edge process, identity, durable store and local updater host.
Keeping the existing Flutter renderers avoids changing fonts, layout, historical
business calculations and the tested cutter/capability rules.

Go does not grant universal USB/serial/driver support. TCP sends printer-ready
bytes. Windows RAW uses a compatible installed queue and bytes in the device's
language. The tested Flutter-independent native spooler core can be rehosted in
a small Go-owned helper; delivery must not require a Flutter engine or MethodChannel.
Driver-rendered documents require a separate qualified renderer.

## Physical printer authority

- Two stable physical-printer UUIDs each own a durable ordered queue and one
  responsible worker. The workers can progress independently.
- Kitchen, bar, receipt, hostname/IP and Windows queue aliases refer to that
  registry; a role, route ID or endpoint string does not establish hardware identity.
  Each physical printer has one canonical transport destination. Conflicting or
  ambiguous registrations refuse admission. USB requires the fixed attached host.
- Freeze Venue, origin installation/terminal, physical-printer/route UUIDs,
  complete retained configuration and digest, renderer/profile, destination,
  bytes, business-effect ID and payload hash. Version 2 shared jobs keep the
  leader/executor/term/attempt in a separately committed assignment; they are not
  frozen to whichever POS first accepted the request. The distinct version 1
  LOCAL/fixed-gateway proof adapter additionally pins its selected host and
  installation epoch. Later settings changes do not redirect accepted work.
- Admit the complete print-effect set atomically with the business result.
  Stable retries retrieve that original result; changed bytes under the same ID
  are rejected. An accepted business operation must not lose its print effect.
- Persist attempt start before any transport call. Restart, lost replies or
  post-start timeouts leave uncertainty, holding that printer without automatic
  resend, reprint, takeover or fallback. Another printer may continue.
- Optional compatible beep has a separate durably spent reservation/outcome
  after primary acceptance. Keep the physical worker occupied until the original
  signal call settles. Unknown, unsupported or disabled sound is skipped; a
  beep failure never repeats successful print/cut output.

Ordering means application admission and submission order. The Windows spooler,
external applications and printer hardware can affect paper order. Accepted
bytes do not establish paper, and ordinary thermal transports do not prove
exactly-once physical output.

## Availability boundary

A printer's scope and transport are separate. `LOCAL` keeps one exclusive
host-local durable queue; `VENUE_SHARED` uses the Venue's pinned cluster authority
and replicated immutable queue. TCP/RAW, IPP, LPR and Windows USB/spooler are
transport choices, not membership or ownership policies. Existing implemented
adapters cover RAW TCP and Windows RAW; IPP/LPR are unimplemented transports and
must not be advertised as working merely because the scope model permits them.
Flutter's migration target is to speak only to its local Go service; that agent
performs local admission or relays shared commands without changing IDs/bytes.
Existing production Flutter direct transport is not yet cut over.

Membership is explicitly provisioned and stable across restarts. Do not discover
random voters at startup, equate the number of POS with voters, or replace
membership implicitly when an IP changes. All voters retain actual replicated
log/payload/state. A third participant for two POS is a data-bearing node, not a
metadata-only witness. Clients/nonvoters do not count toward quorum.

| Deployment | Shared voters | Majority | Committed-queue availability |
| --- | --- | --- | --- |
| One POS, standalone | 1 | 1 | No host-failure tolerance |
| Two POS without another participant | 2 | 2 | Loss of either stops shared commit |
| Two POS plus independent data-bearing participant | 3 | 2 | One voter may fail |
| Three POS | 3 | 2 | One voter may fail |
| Four POS | 3, plus 1 client | 2 | One voter may fail; client loss does not change quorum |
| Five or more POS, default | 3, remaining agents are clients | 2 | One voter may fail |
| Optional larger cluster | 5, remaining agents are clients | 3 | Two voters may fail |

These are consensus queue guarantees, not physical-output guarantees. Without
majority, shared commands fail closed; explicitly LOCAL printers retain their
own host-local authority. A leadership change must retain accepted immutable
payload/configuration/sequence and resolve interrupted dispatch as uncertain.
Deliberate reprints have new identity, an original reference and operator audit.
Never derive a new ID for a network retry or promote a client during an outage.

A fixed owner that runs on POS1 does not satisfy the requested availability:
POS2 and POS3 would lose printing when POS1 turns off. A portable fallback for
generic RAW printers is an independent always-on Venue print gateway outside
POS1/POS2/POS3. All three services forward immutable jobs to that gateway; it owns
the two durable physical-printer queues. Turning off a POS does not stop that
gateway. The gateway, printer power and Venue network remain availability
dependencies; this is not gateway-failure tolerance.

A qualified printer-native queue may remove the separate gateway. IPP capability
alone is insufficient: the standard permits devices without spooling, assigns
job IDs at the printer and does not require unique job names. Printer-native
atomic job buffering, serialization, retention, status and interrupted-request
semantics need model/firmware tests. Generic adapters remain independent of any
vendor; qualification selects a capability profile, not a universal promise.

Three-host consensus can replicate accepted jobs and continue with two hosts,
but cannot fence an external RAW writer. A paused Go1 can resume its old Write
after Go2/Go3 elect another owner. A missed heartbeat, epoch or lease does not
make the old TCP socket harmless. Two-node membership cannot both preserve
quorum safety and continue shared writes after one member disappears without a
third voter or another authority. Venue consensus and printing must not depend
on internet connectivity.

Graceful handoff must stop admission, drain actual primary/beep calls, persist
final receipts and release the old owner before transferring. Independently
verified power-off can exclude the old process; a network timeout cannot prove
power-off. An interrupted STARTED job remains uncertain and is never replayed
automatically. Do not silently skip that FIFO head while an old sender may still
write, or assume partial RAW command state has reset. Model-qualified recovery
and explicit operator reconciliation determine when new jobs may proceed.

Actual printer models/firmware and independent gateway availability are pending.
No infrastructure has been selected, purchased, installed or deployed. The
fixed-host `printqueue` package implements LOCAL/qualified-gateway primitives.
The distinct `printcluster` package implements an inert loopback-qualified
replicated queue with Hashicorp Raft and Bolt log/stable storage, plus a full/WAL
SQLite projection. Complete immutable envelopes are replicated in bounded chunks
before a majority-committed finalize can return ACCEPTED. It does not expose a
physical sender. Final exact-source tests are required before any queue claim;
neither package proves automatic three-POS RAW output or production business
replication. The physical eligibility proof always refuses shared dispatch.

## Lifecycle and installation

USB requires the fixed powered host attached to the printer. A different host
needs its own authenticated durable fixed-owner executor and exact receipts;
it cannot become an independent POS fallback queue.

The target background lifecycle is one independently running Go Windows service
per host. Flutter checks authenticated health, identity and protocol compatibility
and reports unavailability; opening another Flutter window must not spawn another
printer writer. A POS agent or print gateway has an explicit scope and ownership
policy. Only an explicitly selected independent-gateway availability profile
requires the gateway outside POS hosts; a LOCAL agent may be colocated with its
POS. The current per-user updater host/installer remains unchanged. A new
SCM service has not been installed or registered.

The concrete executable is `apps/edge/cmd/printer-agent`. Its explicit foreground,
service and validate modes consume a strict held profile and a separate existing
state root; there is no credential generation, default live root or physical
dispatch option. The loopback printer contract supplies authenticated health
and held mutation/query results. The installer source generates a reviewable
plan; an actual apply requires the approved principal and qualification receipt,
unchanged reviewed service state and exact artifact/configuration hashes.

Flutter's developer printer panel can manually read that health when an explicit
runtime profile is configured. The profile retains the current Device
installation separately from the Go installation pins (D019), validates the
current restore/Device context and asset digests, and discards stale health when
context changes. This readonly configuration guard does not establish printer
admission authority.

`printerprovisioning` validates a purpose-separated signed printer candidate
against freshly supplied server-owned issuer/current authorization, lifetime,
revocation/high-water and exact active route bytes. It issues no key or grant,
persists no protected authority state and admits no work. Attaching a real
production issuer, authoritative route registry and protected current-state
adapter remains an implementation dependency distinct from physical fencing.

Use a qualified least-privilege identity and preflight queue enumeration/opening
under that exact identity. Locally installed queues and per-user connections are
different; LocalSystem is not the signed-in user. A machine-local USB queue may
work under the service identity. A queue requiring a user session needs a narrow
authenticated fixed-owner transport agent; missing agent/logoff holds that
printer. Do not assume session-0 visibility or elevate to fix a failed preflight.
Actual service registration/account/ACL/firewall/trust/driver changes require a
reviewable separately authorized installation step. Bind helper protocol and
binary identity to the Edge bundle.
Before transmitting a request, attach the helper to a non-inherited Windows job
with kill-on-owner-close, or establish an equivalent verified lifetime fence.
Never release exclusivity merely because a public deadline elapsed while the
old helper could still submit. Killing a process does not retract spooled work.

The SQLite process lock protects one store directory. It does not fence another
machine, a copied database or the same hardware under another UUID. Controlled
handover must physically stop/fence the old host. A Cloud epoch or missed
heartbeat alone cannot authorize a competing printer owner.

## Migration and acceptance

Keep the existing single-POS Hive path until an explicit compatible cutover.
Before activating shared dispatch, fence every legacy Flutter, remote and
acceptance print path; reconcile or import unresolved jobs held; establish
physical alias/owner binding; qualify reader floors, updates and rollback.
The isolated operational proof contract remains nonphysical. It must never
silently gain hardware dispatch because a worker package is available.

Software acceptance uses three synthetic authenticated clients and two fake
printers: alias collapse, FIFO, parallel progress with one blocked printer,
duplicate/mismatched IDs, lost ACK, every durable crash boundary, competing
workers/processes, partitions and interrupted beep. Real RPC and Windows helper
inventory/invalid-request checks follow. Physical jobs, installed drivers,
paper/power/cable/sound tests, owner reconciliation policy and live cutover need
their separate approval and actual evidence. No successful simulation closes
those gates. The user requested 18 separate process/partition/recovery/topology
cases; the final report preserves passed, failed and not-run software/physical
boundaries instead of a blanket HA-ready verdict.

Primary references: [WritePrinter blocking and RAW requirements](https://learn.microsoft.com/en-us/windows/win32/printdocs/writeprinter),
[Windows job-status semantics](https://learn.microsoft.com/en-us/windows/win32/printdocs/job-info-2),
[Go connection deadlines](https://pkg.go.dev/net#Conn), and
[Windows service/session boundaries](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services).
