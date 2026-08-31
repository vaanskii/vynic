# Cloud ↔ Edge transport

**Step 6A.** How a future Vynic Cloud and a restaurant's POS talk to each other,
and why the direction had to change before anything else could.

Companion documents: [SYNC_CONTRACT.md](SYNC_CONTRACT.md) (snapshot payload),
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

Today the server reaches the POS by dialling it:

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
| Today | `POST /sync/manager-data` → `IngestPosSnapshotService` — **unchanged** | `POST /edge/commands/*` — new in 6A |

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
It is deliberately not true that today's POS actions are all safe to repeat —
printing a check twice prints two checks — so those types stay out of the queue
until Step 6B gives them Edge-side idempotency. Step 6A ships exactly one type,
`NOOP`, which does nothing and exists so the transport can be exercised end to
end without performing restaurant work.

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

**TypeScript only, for now.** There is no Dart consumer yet — the POS still
receives work over the legacy callback path — and emitting an unused Dart file
into `apps/operations/` would be dead code dressed as a contract. Step 6B adds
the Dart rendering alongside the Edge client that reads it.

The version travels three ways: on the row, on every envelope, and on the claim
request (`acceptedContractVersions`), so an Edge is only handed work it
understands. **N/N-1 compatibility is a documented future requirement**: once a
second version exists, Cloud must be able to serve both while a fleet upgrades.

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

Nothing was removed and nothing changed behaviour. The Vankisi installation runs
exactly as it did.

| Path | Status |
|---|---|
| `PosCallbackClient`, `PosConnectionRegistry`, `pos-callback-url` SSRF guard | **Transitional.** Still the only delivery mechanism in production. |
| `PosOutboxService` / `PosCallbackOutbox` | **Transitional.** Frozen: no new command types. |
| `POST /sync/*` snapshot ingestion | **Keeps.** Edge → Cloud state is the right direction already. |
| `POST /edge/commands/*` | **New foundation.** Unused by production POS until Step 6B. |

**Retirement conditions for the legacy callback path** — all of them, not any:

1. A Flutter Edge client claims and acknowledges commands (Step 6B).
2. Every command type currently sent through `PosCallbackClient` has an
   idempotent Edge handler and a declared type in the contract.
3. Reservation reads (`fetchPosReservations`) have a Cloud-side answer, since a
   pull queue delivers work but does not answer a synchronous question.
4. Every deployed POS has a Device credential — the legacy shared
   `POS_SYNC_API_KEY` path resolves no Device and cannot use this transport.

Until then a Cloud deployment is not possible, and that is the honest status:
6A makes the *transport* Cloud-compatible, not the product.

---

## Deferred

- **Step 6B — POS Edge client.** The Flutter side, the Dart contract rendering,
  and migrating command types across.
- **Synchronous Edge reads.** `fetchPosReservations()` is a request-response the
  website makes into POS Hive. A work queue does not answer it; that needs either
  a Cloud-side mirror or a different mechanism.
- **Multi-Device contention.** The claim uses an optimistic status guard, which
  is correct but lets a loser claim fewer rows. A Venue with several busy Edges
  would be better served by `SELECT … FOR UPDATE SKIP LOCKED`.
- **Enqueue authorization.** `EdgeCommandService.enqueue` has no HTTP route on
  purpose — see [PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md).
- **Manager App Cloud networking.** Untouched; a later phase.
- No message broker was introduced. One NestJS monolith and one PostgreSQL
  answer this workload; Kafka, RabbitMQ, Redis Streams and NATS would each be a
  second system to operate for no evidence-backed gain.
