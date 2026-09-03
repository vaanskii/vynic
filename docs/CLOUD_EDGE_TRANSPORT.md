# Cloud ↔ Edge transport

**Step 6A** established the backend side. **Step 6B** put the POS on it.
**Step 6C** moved the real restaurant work onto it — see
[EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md) for the endpoint
inventory, the per-command idempotency arguments, and the current status of every
legacy component. This document is the transport itself.

Companion documents: [EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md),
[AUDIT_SYNC.md](AUDIT_SYNC.md), [SYNC_CONTRACT.md](SYNC_CONTRACT.md) (snapshot payload),
[DEVICE_IDENTITY.md](DEVICE_IDENTITY.md) (Device credentials),
[TENANT_SCOPING.md](TENANT_SCOPING.md) (Venue ownership),
[PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md) (who may enqueue work,
eventually), [PAYMENT_INTEGRATIONS.md](PAYMENT_INTEGRATIONS.md).

---

## The invariant this protects

Vynic POS is **offline-first**. Taking an order, opening a table, printing a
check, closing the business day, and reading local configuration must all keep
working with the Internet unplugged. Hive stays the local operational store.

Nothing in this document may become a runtime dependency of those operations.

## The problem

The server used to reach the POS by dialling it — and still does, for a Venue
with no enrolled Device:

```
Server ──HTTP──▶ http://192.168.1.50:8080/mobile-order-update
```

The address is registered by the POS in every snapshot push, kept in
`Setting('pos:callback_url')`, and guarded against SSRF by
`isAllowedPosCallbackUrl`, which — correctly for today — **only** accepts
loopback and RFC 1918 addresses.

That guard is also the proof that the model cannot move to Cloud. A hosted
Vynic has no route to `192.168.1.50`. The addresses the transport is restricted
to are exactly the addresses a Cloud deployment can never reach.

Three further assumptions come with it:

- **One address per installation.** `PosCallbackClient` holds a single in-memory
  `callbackUrl`, restored for the bootstrap Venue at boot. A second Venue would
  overwrite the first.
- **No Device in the loop.** The callback URL belongs to a Venue, not to a
  machine. There is nothing to route to when a restaurant runs two POS
  terminals.
- **Cloud decides success.** In `PosCallbackOutbox`, `status = 'delivered'`
  means *an HTTP POST returned 2xx*. Whether the POS actually applied the change
  is never reported back.

## The direction

```
                   VYNIC CLOUD
                 NestJS / PostgreSQL
                       │
      Manager ─────────┼───────── Websites
                       │
                Device identity
                       │
                 HTTPS transport
                       │
                       ▼
                  POS / Edge
                Flutter + Hive
                       │
                       ├── printers
                       ├── LAN devices
                       └── offline operation
```

**The Edge opens every connection.** It already holds a Device credential and
already pushes snapshots, so it is the side that can reach the other. Cloud
holds work and waits.

---

## Two mechanisms, not one

These are different problems and are kept apart deliberately.

| | **A. Edge → Cloud state** | **B. Cloud → Edge work** |
|---|---|---|
| Carries | orders, tables, menu, staff, business days, expenses, audit | configuration refresh, printer config, a device command, a support action |
| Shape | a snapshot of what is true | an instruction to do something |
| Repeating it | converges — same snapshot, same result | must be made safe deliberately |
| Ordering | last write wins | per-command lifecycle |
| Today | `POST /sync/manager-data` → `IngestPosSnapshotService` — **unchanged** | `POST /edge/commands/*`, claimed by the POS since 6B |

Collapsing them would mean one version number, one retry policy and one failure
mode for two things that need three different answers each. Step 6A leaves the
snapshot path exactly as it is — `PosSyncGuard` → `TenantContext` →
`SyncController` → `IngestPosSnapshotService` → scoped sync services — and adds
the second mechanism beside it.

---

## The work queue

```prisma
model EdgeCommand {
  id, venueId, deviceId?, type, contractVersion, payload,
  idempotencyKey, status, attemptCount, maxAttempts,
  availableAt, claimedAt, claimedByDeviceId, claimExpiresAt,
  acknowledgedAt, resultCode, resultDetail
  @@unique([venueId, idempotencyKey])
}
```

### Why not evolve `PosCallbackOutbox`

It was the first thing considered, and it is genuinely close: durable,
Venue-owned since Step 4B1, with attempts, backoff, and a terminal state. It is
not reusable because its central column means the wrong thing.

| | `PosCallbackOutbox` | `EdgeCommand` |
|---|---|---|
| `endpoint` / `type` | an HTTP path on the POS's ingest server | a command type, transport-independent |
| terminal success | the POST returned 2xx | the Edge says it executed |
| who reports the outcome | Cloud, from its own transport | the Edge, with a code and detail |
| routing | Venue | Venue **or** a specific Device |
| identity for the Edge | `dedupeKey`, server-side collapse only, often null | `idempotencyKey`, always present, unique per Venue |
| versioning | none | `contractVersion` on the row and the wire |
| retry trigger | a push failed | a lease expired |

Retrofitting a claim/acknowledge lifecycle onto it would give `status` two
incompatible readings at once — "due for an HTTP push" and "available to claim" —
during exactly the period when both an unmigrated POS and a new Edge client are
live. That is a data-corruption shape, not a refactor.

**There is one long-term queue.** `PosCallbackOutbox` is dated: no new command
type may be added to it, and it retires under the conditions below.

### Lifecycle

```
        enqueue
           │
           ▼
   ┌──▶ PENDING ──── claim ────▶ CLAIMED ──── ack ────▶ SUCCEEDED
   │                               │                 └─▶ FAILED
   └──── lease expired ────────────┤
                                   └── attempts exhausted ──▶ FAILED
```

- **A claim is a lease, not a completion.** Cloud has handed the work over; only
  the Edge can say what happened to it.
- **Silence is retried; an explicit failure is not.** A lease that runs out
  (`claimExpiresAt`, 120s) makes the command available again — that is the answer
  to "the POS crashed between receiving and acknowledging". An Edge that
  *reports* `FAILED` has executed and failed, so repeating it automatically would
  just repeat the failure. Re-issuing it is a deliberate act: enqueue the same
  `idempotencyKey` again and the row is revived with a fresh attempt budget.
- **Exhaustion is recorded, not deleted.** After `maxAttempts` redeliveries the
  command becomes `FAILED` with `resultCode = lease_expired_attempts_exhausted`.
  Command history is never dropped to make room.
- Expired leases are swept lazily at claim time, so there is no background timer
  to own, restart, or reason about.

### Delivery semantics

**At-least-once, with idempotent execution.** Not exactly-once — that is not
available across a network partition and pretending otherwise would just move
the duplicate somewhere less visible.

`EDGE_IDEMPOTENT_COMMAND_TYPES` in the generated contract is the enforcement, not
the documentation: `enqueue()` **refuses** a type that is not declared idempotent.

**Since Step 6C the catalogue is the real one** — eighteen types at contract
version 2, covering orders, walk-ins, reservations, expenses, staff and the three
prints. Each declares its payload, its idempotency argument and its failure codes
in the schema, and the generator renders all three into both languages.

It was deliberately not true that every POS action is naturally safe to repeat.
Two needed identity to move to Cloud before they could be queued at all — a
reservation whose id the POS used to invent, an expense that used to be appended
— and printing needed a second mechanism, because paper is a side effect the
world keeps. `EDGE_NO_REPEAT_AFTER_INTERRUPTION` is that mechanism: a print whose
execution was interrupted is not repeated, because nobody can say whether the
check came out and a silent second one is worse than a reported failure. The full
argument for each type is in
[EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md).

### Idempotency

- `@@unique([venueId, idempotencyKey])` — enqueueing the same intent twice
  updates one row rather than creating a second. Two Venues may of course use the
  same key.
- Acknowledgment is idempotent by construction: a terminal command keeps the
  outcome it ended with, and a repeated acknowledgment reports
  `alreadyAcknowledged: true` rather than rewriting history — including when the
  repeat disagrees with the first.

---

## Routing

`deviceId` is nullable, and the two cases are both real:

- **null** — work for the Venue's Edge installation. Any Device of that Venue may
  take it. This is what a single-terminal restaurant uses.
- **set** — work for one machine: its printer, its screen, its local state.

A Venue may eventually run several Devices, so nothing assumes one. The claim
filter is `venueId = <authenticated> AND (deviceId IS NULL OR deviceId = <authenticated>)`.

This is the replacement for the single global callback address. Cloud-originated
work routes `Venue → appropriate Device`, and the legacy path's "one URL per
server process" is not carried forward.

### Authority

```
X-POS-Sync-Key: vynic-device-v1.<deviceId>.<secret>
        ↓  argon2id verification
     Device (ACTIVE)
        ↓
      Venue (ACTIVE)
        ↓
   its queue, and nothing else
```

- **Device credentials only.** `EdgeDeviceGuard` refuses the legacy shared POS
  key. That key names a Venue but no machine, so it could neither be routed to
  nor held responsible for a lease. `PosSyncGuard` still accepts it for snapshot
  pushes, which is why the two guards are separate.
- **No request field names a tenant.** Neither route reads a `venueId` or
  `deviceId` from a body. There is no parameter that could widen the filter.
- A foreign Venue's command acknowledges as **404, not 403** — an acknowledgment
  must not become a way to probe which command ids exist elsewhere.
- Another Device's lease is **403**.
- A revoked Device, a disabled Device, and a disabled Venue are all refused at
  the credential, before the queue is touched.
- **Not entitlement-gated.** This is infrastructure. No commercial feature may
  switch a restaurant's transport off, exactly as no feature gates POS → Cloud
  sync.

### Connectivity

`Device.lastSeenAt` already exists and is refreshed (throttled to 5 minutes) by
every credential verification — and a poll *is* a credential verification, so
polling updates it for free.

No `lastPollAt`, `transportVersion` or `appVersion` column was added. Each would
be a second, noisier answer to a question `lastSeenAt` already answers, and the
contract version an Edge understands already travels on the claim request where
it is actually used. When there is a control plane that needs to *display*
per-Device transport state, that is the moment to decide what it needs.

---

## Contract and versioning

`packages/contracts/schema/edge-command.contract.json` is the source of truth:
the version, batch limits, lease duration, attempt ceiling, and the command-type
catalogue with its idempotency classification. `--check` covers the rendered
output like every other contract.

**Both languages since Step 6B**, when the POS gained a consumer. The Dart
rendering carries the envelope, the result, the limits and the type catalogue,
and `--check` covers all four generated copies — there are no hand-maintained
Dart DTOs for this contract.

The version travels three ways: on the row, on every envelope, and on the claim
request (`acceptedContractVersions`), so an Edge is only handed work it
understands. **N/N-1 compatibility exists since Step 6C**, when a second version
appeared: `compatibleContractVersions` is `[2, 1]`, an Edge sends both on every
claim, and work enqueued under the older envelope still reaches a terminal that
has moved on.

Existing sync DTOs were deliberately **not** moved into the package. The
envelope needed a shared definition; `SyncPayload` does not, and moving it would
be churn justified only by the package existing.

---

## Printers stay on the LAN

```
POS / Edge ──LAN──▶ printer
```

Cloud may eventually *store* printer configuration and deliver it as an
`EdgeCommand`. Cloud must **never** open a connection to a printer's private
address. Printing remains an Edge responsibility with an Edge failure mode: a
print that fails is reported as a command result, not retried by Cloud into a
network it cannot see. Current printing is unchanged.

---

## Configuration direction

Recorded now, implemented later:

| | Authority |
|---|---|
| Operational state — orders, tables, business day | **POS / Edge** |
| Configuration and catalogue — menu, staff, roles, permissions, Venue settings, printer config | **Cloud administrative authority**, with a full offline Edge cache the POS can still read and edit |

Step 6A implements none of the bidirectional conflict model. What it guarantees
is that when that model exists, there is a durable, ordered, acknowledged channel
to deliver a configuration change over.

---

## Legacy compatibility

Step 6C migrated every business operation. What survives is a fallback with one
purpose, and the per-component status table lives in
[EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md#legacy-status). In summary:

| Path | Status |
|---|---|
| `PosCallbackClient` per-operation and synchronous-read methods | **Removed.** All migrated; the synchronous LAN read has no replacement by design. |
| `PosCallbackClient.deliverToPos`, `PosConnectionRegistry`, the SSRF guard | **Frozen fallback.** Reached only for a Venue with no enrolled Device. |
| `PosOutboxService` / `PosCallbackOutbox` | **Frozen fallback.** Same single caller. |
| `PosIngestServer` | **Frozen fallback.** Serves that path, and an older backend during a rollout. |
| `POST /sync/*` snapshot ingestion | **Keeps.** Edge → Cloud state is the right direction already, and since 6C it also carries reservations. |
| `POST /edge/commands/*` | **The transport.** Carries every migrated operation. |

**Retirement conditions for the legacy callback path** — all of them, not any:

1. ~~A Flutter Edge client claims and acknowledges commands.~~ **Done in 6B.**
2. ~~Every command type sent through `PosCallbackClient` has an idempotent Edge
   handler and a declared type in the contract.~~ **Done in 6C — 17 operations,
   all migrated.**
3. ~~Reservation reads have a Cloud-side answer, since a pull queue delivers work
   but does not answer a synchronous question.~~ **Done in 6C — `PosReservation`,
   filled from the snapshot.**
4. Every deployed POS has a Device credential — the legacy shared
   `POS_SYNC_API_KEY` path resolves no Device and cannot use this transport.
   *(Phase 1C gave this a path that scales past a hand-written file, but a path
   is not a fleet: this is satisfied when every installation has actually
   enrolled, not when it becomes possible for them to.)*

Three of four hold. The honest status is therefore narrower than "Cloud never
needs a private POS address": **an enrolled Venue's migrated operations need
none**, and the fallback exists precisely because condition 4 does not hold yet.

---

---

## The POS Edge client (Step 6B)

`apps/operations/lib/core/services/edge/`.

```
main() → DatabaseService.init()
       → EdgeDeviceCredentialStore.load()
       → ManagerSyncService.initialize()
       → EdgeTransportService.start()      ← not awaited
```

### Device credential

The POS had none. It authenticated `POST /sync/*` with the shared
`POS_SYNC_API_KEY` alone, and the Edge endpoints refuse that key because it
names a Venue but no machine. So 6B gave the installation a real identity.

- **`installationId`** — a UUID generated on first run and kept.
- **The credential** — issued per installation. Never hardcoded, never one
  global secret for the fleet, never committed.
- **Where it lives** — `<data directory>/edge_device.json`, owner-only where the
  platform has POSIX permissions.

**Not the Hive settings box, deliberately.** `BackupRepository.createDataBackup`
serializes that box wholesale into an exportable JSON file, so a credential
stored there would land in every backup an operator copies off the machine. A
separate file keeps it out of backups entirely.

**The boundary, stated plainly:** this is file protection inside a per-user
application-data directory. It is not an OS keychain, and anything running as
the same user can read it. Windows DPAPI / macOS Keychain would need a platform
plugin and a change to both desktop build configurations; that is recorded as
deferred rather than pretended away.

### Provisioning

**Since Phase 1C the normal path is enrollment.** An administrator mints a
one-time, Venue-bound code in Platform Admin; the terminal redeems it at
`POST /edge/enroll` and receives its credential and its Venue in one step. The
two paths below both remain, as the support and bootstrap paths respectively.
See [POS_ENROLLMENT.md](./POS_ENROLLMENT.md).

**Since Step 7A there is an authenticated route:**
`POST /platform/venues/:venueId/devices` returns the credential once, and
`POST …/devices/:deviceId/credential` rotates it — see
[PLATFORM_CONTROL_PLANE_API.md](PLATFORM_CONTROL_PLANE_API.md).

The shell path below remains, because it is how a device gets provisioned before
the first administrator exists, and because it requires shell access to the
server — an authorization boundary that already exists and one that **cannot
quietly become the SaaS onboarding model**:

```bash
# On the server
npm run device:issue -- --venue <venueId> --name "Bar terminal" --platform windows
```

The secret is printed once — only its Argon2id verifier reaches the database, so
there is no recovering it later; issue a new credential and revoke the old
Device instead. To install it, write that one line to
`<POS data directory>/edge_device_provision.txt` and restart the POS. It is
absorbed into `edge_device.json` and the drop file is deleted, so the secret does
not sit on disk as a second copy.

### Poll lifecycle

One timer, one owner. Screens do not poll.

| Situation | Next poll |
|---|---|
| work claimed | 2s — drain the queue |
| nothing waiting | 10s (was 30s before real work rode this transport) |
| Cloud unreachable or erroring | exponential from 30s, capped at 5min, ±20% jitter |
| credential rejected | loop stands down; re-provisioning resumes it |
| no credential | never starts |

Re-entrant polls are refused rather than queued: two claims in flight would take
two leases on the same work for no benefit.

**Offline is the normal state, not a failure.** `EdgeTransportService.start()` is
not awaited, so it cannot delay startup. Every transport failure is an outcome
rather than a throw. Nothing on the path of taking an order, opening a table or
printing a check consults it. A POS with no credential — which is every
installation until one is provisioned — starts and runs exactly as it always did.

### Handler registry

The transport does not know printer, menu or table logic. It resolves a type to
an `EdgeCommandHandler` and calls it; a handler that throws produces a failed
result with a reason, not a crash.

Step 6B shipped **one** handler, `NOOP`. Step 6C added seventeen, all of them
thin adapters over `PosCommandApplier` — the one place the restaurant work
actually happens, shared with the legacy LAN server so the two transports cannot
drift. A test asserts that every type the contract declares has a handler: one
without would be claimed, refused and redelivered until its attempts ran out.

### Local execution journal

Cloud acknowledgment alone cannot cover the sequence that actually happens:

```
POS receives a command → executes it → the connection dies
→ the acknowledgment never lands → the lease expires
→ Cloud offers the same command again
```

Without a local record the side effect happens twice. So the Edge keeps its own
durable answer in a Hive box (`edge_command_journal`): command id, idempotency
key, type, first-seen time, and outcome. **No payloads** — enough to decide
whether to run something, without holding whatever a future command type carries.

- A command that already **succeeded** here is acknowledged again, with
  `already_executed`, and is not re-run.
- A command that already **failed** keeps that outcome. Step 6A's semantics
  apply: an explicit failure is terminal, and re-issuing it is a deliberate
  control-plane act.
- **Crash policy.** An entry left mid-execution by a process that never returned
  is marked `interrupted` on the next start, not guessed at in either direction.
  It is non-terminal, so a redelivered command is executed again — which is safe
  precisely because only idempotent types may be queued.

  **Since Step 6C there is one exception, and it is the honest one.** A type in
  `EDGE_NO_REPEAT_AFTER_INTERRUPTION` — the three prints — is *not* re-executed
  from an interrupted entry. Nobody can say whether the paper came out, and a
  second kitchen check appearing silently is worse than an
  `interrupted_not_repeated` failure somebody can see and act on.
- **Retention** — terminal entries are pruned after 7 days, comfortably longer
  than any lease or redelivery window, with a 5000-row ceiling as a backstop.
  Non-terminal entries are never pruned: they are exactly the ones a redelivery
  needs to be judged against. The journal is not included in backups, so a
  restore starts it empty; for idempotent command types that is harmless.

### Snapshot sync

Unchanged in shape. The one adjustment: `ApiConfig.posSyncHeaders` now prefers a
provisioned Device credential over the shared key. Both travel in the same
header and the server tells them apart by prefix, so a provisioned installation
gets its snapshot push attributed to its own Device and Venue while an
unprovisioned one behaves exactly as before. **The shared-key path is not
removed.**

---

## Deferred

- ~~**Step 6C — legacy business-command migration.**~~ **Done.** See
  [EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md).
- ~~**Synchronous Edge reads.**~~ **Done** — `PosReservation`, a Cloud mirror
  filled from the snapshot, rather than a fake command.
- **Device-addressed printing.** Every command is Venue-addressed
  (`deviceId: null`), which is right for a one-terminal restaurant and wrong for
  a venue where the bar and the kitchen each have a till. `EdgeCommand.deviceId`
  already exists; nothing chooses a value for it yet.
- **Print latency.** A queued print waits up to one idle poll — ten seconds —
  before a terminal claims it. A long-poll on the claim endpoint would make it
  immediate while keeping the Edge as the side that opens the connection. Not
  needed for correctness; recorded as the obvious next improvement.
- **Reservation double-allocation.** No `ReservationHold` exists, so two
  simultaneous website bookings for one table can both pass the availability
  check. Unchanged by the mirror, and not solved by it.
- **OS keychain credential storage.** Windows DPAPI / macOS Keychain instead of
  an owner-only file.
- **Multi-Device contention.** The claim uses an optimistic status guard, which
  is correct but lets a loser claim fewer rows. A Venue with several busy Edges
  would be better served by `SELECT … FOR UPDATE SKIP LOCKED`.
- **Enqueue authorization.** Since Step 7A a platform administrator may queue a
  `NOOP` to test a device. No route names a type or a payload, so the declared
  registry and the idempotency rule cannot be routed around — see
  [PLATFORM_CONTROL_PLANE_API.md](PLATFORM_CONTROL_PLANE_API.md).
- **Manager App Cloud networking.** Untouched; a later phase.
- No message broker was introduced. One NestJS monolith and one PostgreSQL
  answer this workload; Kafka, RabbitMQ, Redis Streams and NATS would each be a
  second system to operate for no evidence-backed gain.
