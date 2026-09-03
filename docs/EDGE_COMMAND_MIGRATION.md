# Cloud → POS command migration

**Step 6C.** What used to reach a restaurant by the backend dialling
`http://192.168.1.50:8081`, and what happens instead.

Companion documents: [CLOUD_EDGE_TRANSPORT.md](CLOUD_EDGE_TRANSPORT.md) (the
queue and its lifecycle), [SYNC_CONTRACT.md](SYNC_CONTRACT.md) (the snapshot
payload), [POS_ENROLLMENT.md](POS_ENROLLMENT.md) (how a terminal gets a Device
credential), [AUDIT_SYNC.md](AUDIT_SYNC.md).

---

## The problem this closes

Step 6A built a durable Cloud → Edge work queue. Step 6B put the POS on it. What
neither did was move any restaurant work onto it: the queue carried exactly one
command type, `NOOP`, and everything a manager actually pressed still travelled
over the LAN callback path.

That path is the reason a Cloud deployment was not possible. `isAllowedPosCallbackUrl`
accepts loopback and RFC 1918 addresses and nothing else — correctly, as an SSRF
guard — and those are precisely the addresses a hosted backend can never route
to. Eighteen endpoints depended on it.

---

## The inventory, and what happened to each

Eighteen routes existed on `PosIngestServer`. They classify into four kinds.

### A — Mutation commands → migrated to `EdgeCommand`

| Legacy route | Command type | Idempotency |
|---|---|---|
| `POST /mobile-order-update` | `ORDER_UPDATE` | Assignment. The payload is the order's new content, so a second delivery writes the same values. The audit diff is taken against what is stored, so a replay produces no events, and `MoneyAudit` already declines a service-fee entry that did not move. |
| `POST /mobile-order-cancel` | `ORDER_CANCEL` | Goal state "gone". An order already absent satisfies it. |
| `POST /mobile-order-status` | `ORDER_STATUS_UPDATE` | Assignment. |
| `POST /mobile-order-create` | `TAKEAWAY_ORDER_UPSERT` | Upsert on the Cloud-allocated `posOrderId`. The kitchen check fires only when the order was not already here. |
| `POST /mobile-walk-in-order-create` | `DINE_IN_ORDER_UPSERT` | As above. |
| `POST /mobile-reservation-create` | `RESERVATION_CREATE` | **Identity moved to Cloud.** See below. |
| `POST /mobile-reservation-status` | `RESERVATION_STATUS_UPDATE` | Assignment. |
| `POST /mobile-reservation-delete` | `RESERVATION_DELETE` | Goal state "gone". |
| `POST /mobile-expense-create` | `EXPENSE_CREATE` | **Write changed from append to upsert.** See below. |
| `POST /mobile-user-create` | `STAFF_CREATE` | Goal state "this username exists with this role and PIN". Cloud has already refused a duplicate before enqueueing. |
| `POST /mobile-user-update-pin` | `STAFF_PIN_UPDATE` | Assignment. |
| `POST /mobile-user-update-role` | `STAFF_ROLE_UPDATE` | Assignment. |
| `POST /mobile-user-rename` | `STAFF_RENAME` | Goal state "new exists, old does not". |
| `POST /mobile-user-delete` | `STAFF_DELETE` | Goal state "gone". |

### B — Print commands → migrated, with a named crash boundary

| Legacy route | Command type |
|---|---|
| `POST /mobile-order-print-check` | `ORDER_CHECK_PRINT` |
| `POST /mobile-reservation-print-check` | `RESERVATION_CHECK_PRINT` |
| `POST /mobile-counted-menu-print` | `COUNTED_MENU_PRINT` |

### C — Synchronous read → **not** a command

`GET /mobile-reservations` is a question, and a work queue does not answer
questions. It became a Cloud-side mirror; see *Reservation reads* below.

### D — Obsolete

`GET /health` is a liveness probe on the POS's own listener, not Cloud work. It
stays with the listener.

---

## Idempotency, argued rather than asserted

Delivery is at-least-once: a lease can expire after the POS executed but before
the acknowledgment landed, and Cloud will offer the command again. Every type in
the catalogue therefore has to be safe to run twice, and the contract's
`EDGE_IDEMPOTENT_COMMAND_TYPES` is the enforcement — `enqueue()` refuses a type
that is not declared idempotent.

Most commands are convergent by construction: the payload states the goal rather
than a delta, so running it again lands on the same state. Two were not, and
identity had to move for them.

### Reservations

The POS invented the id — `Date.now()` in milliseconds — and handed it back over
a synchronous LAN call. Two consequences. A booking had no POS identity until the
restaurant answered, so a paid website booking could not be linked while the
terminal was asleep. And a redelivered create produced a *second reservation*,
because nothing tied the two deliveries together.

Cloud allocates it now: `allocatePosReservationId()` returns the same millisecond
value plus three random digits. Sixteen digits where a POS mints thirteen, so a
Cloud id and a POS id generated in the same millisecond are still different ids —
a collision is impossible rather than unlikely. It stays numeric because every
stored record, backup and website-bridge column has only ever seen digits.

`ReservationRepository.createReservation` gained an optional `id`. A booking
taken at the terminal still mints its own.

### Expenses

`saveExpenseRecord` always appended, even when given a `sourceId`. One retried
delivery showed up as two expenses in a restaurant's day — silently, in the
figures it reports. It upserts on that id now.

### Printing

Paper is a side effect the world keeps, and no amount of contract language makes
a second kitchen check un-print itself. The protection is the local execution
journal: a command already recorded as succeeded is acknowledged again without
being run.

**The boundary, stated plainly.** If the process dies after the printer accepted
the data but before the journal recorded the outcome, nobody can say whether the
check came out. Exactly-once physical printing is not available without printer
acknowledgement, which this hardware path does not provide.

So the three print types are listed in `EDGE_NO_REPEAT_AFTER_INTERRUPTION`, and
an interrupted execution of one is **not** repeated. It is acknowledged as
`FAILED` with `interrupted_not_repeated`, which an operator can see and act on.
A silent second check is worse than a reported failure. Every other command type
*is* repeated after an interruption, because for a convergent command that is
free and stranding work is not.

---

## One implementation, two transports

`PosCommandApplier` holds the POS-side behaviour. `PosIngestServer` and the Edge
handlers are both adapters over it.

```
Manager / website
        │
        ▼
PosCommandDispatcher ──enrolled?──▶ EdgeCommand queue ──claim──▶ Edge handler ─┐
        │                                                                       │
        └──not enrolled──▶ PosCallbackOutbox ──LAN──▶ PosIngestServer ──────────┤
                                                                                ▼
                                                                    PosCommandApplier
                                                                                │
                                                                              Hive
```

During a migration the worst outcome is the two paths quietly diverging — an
order cancelled one way over the LAN and another way over the queue. There is one
body of code and the transports differ only in how an outcome is reported.
`PosIngestServer` went from 1105 lines to 252 with its behaviour unchanged,
including still answering 404 for a missing order.

The one deliberate difference is the reconciliation flags. The LAN server reports
*delivery* — the outbox marks a row delivered on a 2xx — so a 404 for an order
that is already gone is useful there. The queue reports *execution*, and keeps a
terminal failure terminal, so a redelivery that finds the work already done must
say "done". A false failure there is a command somebody has to go and re-issue.

---

## Reservation reads

`fetchPosReservations()` had three consumers: the manager reservation list, the
public website's table-availability page, and paid-booking creation. All three
waited on one restaurant PC being awake, and none of them could work at all from
a hosted backend.

They read `PosReservation` now — a Cloud mirror the POS fills from the snapshot
it already pushes, reconciled wholesale like tables and orders. A snapshot that
omits the field changes nothing, so an un-upgraded terminal does not empty a
restaurant's mirror.

**The mirror lags, and the direction of the lag matters.** A reservation
cancelled at the till while the restaurant was offline still blocks its table
here — the safe error. One *taken* at the till is missing — not safe. So
`PosReservationMirrorService.freshness()` exists and the availability path logs
when it is answering from a stale picture, rather than treating an old mirror as
an empty restaurant.

### What this does not fix

Double-allocation is still possible. There is no `ReservationHold`, so two
website bookings for the same table at the same instant can both pass the
availability check. Moving the read to a mirror neither caused nor solved that;
it remains an open blocker, recorded here and in the roadmap rather than implied
away by "reservations are in PostgreSQL now".

---

## Paid website bookings

A successful paid booking no longer requires reaching a private LAN.

The reservation id is allocated by Cloud and written to
`WebsiteReservation.posReservationId` **before** anything is dispatched, so the
link is durable immediately. The Edge command is then recorded for the terminal
to claim.

`updatePaymentStatus` no longer rethrows when the hand-off fails. It is a
payment-provider callback about money that has already moved: throwing unbooks
nothing and only makes the provider retry into the same failure. The booking and
its payment are persisted first, and a failure to hand over is logged as the
operational problem it is.

Payment providers and per-Venue merchant credentials are untouched.

---

## What a caller may claim

A queued command has not run. Every migrated mutation returns a `posDelivery`
block:

```
QUEUED            recorded; no terminal has claimed it
CLAIMED           a terminal holds a lease and has not reported back
SUCCEEDED         the POS ran it and said so
FAILED            the POS ran it and reported a failure
DELIVERED_LEGACY  handed over the LAN and accepted (transitional)
UNAVAILABLE       nothing could be recorded
```

The three prints use `dispatchAndAwait`, which waits a bounded fifteen seconds
for the terminal's own answer before reporting `QUEUED`. That is the "bounded
request/result job" the engineering protocol permits, not the forbidden
"enqueue and wait indefinitely" — a request never hangs on a closed restaurant.

The Manager reads it. `PosCommandDelivery.isDone` is true only for `SUCCEEDED`
and `DELIVERED_LEGACY`, and the order-detail screen now says "sent to the POS"
rather than "the check printed" when the terminal has not answered.

**The idle poll came down from 30s to 10s**, because what rides this transport
stopped being a `NOOP`. It is also the base of the failure backoff, whose
five-minute cap is unchanged, so an offline restaurant still stops asking
quickly.

---

## Contract version 2

The catalogue grew from one type to eighteen. `compatibleContractVersions` is
`[2, 1]` and an Edge sends both on every claim, so work enqueued under the older
envelope still reaches a terminal that has moved on — the N/N-1 compatibility the
6A document recorded as a future requirement.

The generated files carry each type's payload shape, its idempotency argument and
its failure codes as doc comments rendered from the schema, so a handler and the
queue cannot disagree about what a type promises. `pos_edge_command_handlers_test`
asserts that every declared type has a handler: one without would be claimed,
refused, and redelivered until its attempts ran out.

---

## Legacy status

| Component | Status | Why |
|---|---|---|
| `PosCallbackClient` — per-operation methods | **REMOVED** | All seventeen migrated. Nothing calls them. |
| `PosCallbackClient` — `requestPos` (synchronous read) | **REMOVED** | The only synchronous LAN read path. Reservations are answered from the mirror; removing the method is what stops a future caller reaching for the old shape. |
| `PosCallbackClient` — `deliverToPos`, URL/key state | **FROZEN FALLBACK** | Reached only by `PosCommandDispatcher` for a Venue with no enrolled Device. No method may be added. |
| `PosOutboxService` / `PosCallbackOutbox` | **FROZEN FALLBACK** | Same single caller, for mutations. Its `isPosUnreachableError` classifier is **REMOVED** — it described the synchronous path that no longer exists. |
| `PosConnectionRegistry`, `pos:callback_url`, `pos:connection_key` | **STILL REQUIRED** | The fallback needs an address. Retires with it. |
| `isAllowedPosCallbackUrl` SSRF guard | **STILL REQUIRED** | Guards the fallback. Must be the last thing removed, not the first. |
| `PosIngestServer` | **FROZEN FALLBACK** | Serves the fallback, and serves an older backend during a rollout. No route may be added. |
| Legacy POS connection key | **STILL REQUIRED** | Authenticates the fallback. |
| `GET /mobile-reservations` on the POS | **FROZEN** | No Cloud code calls it. Kept only so a new POS paired with an un-upgraded backend still answers, and it goes when the fallback does. |

### What still gates full retirement

1. ~~A Flutter Edge client claims and acknowledges commands.~~ **Done in 6B.**
2. ~~Every command type has an idempotent Edge handler and a declared type.~~
   **Done in 6C.**
3. ~~Reservation reads have a Cloud-side answer.~~ **Done in 6C.**
4. **Every deployed POS has a Device credential.** Still open. This is a fleet
   fact, not a code change: it is satisfied when every installation has actually
   enrolled, not when it becomes possible for them to. The fallback exists
   precisely because it is not satisfied yet.

An enrolled Venue's migrated operations need no private POS address today. That
is a narrower claim than "Cloud never needs one", and it is the true one until
(4) holds.

### Rollout note

A Venue with an enrolled Device gets Edge dispatch, and its terminal must be
running a 6C build. An enrolled terminal on an older build declares contract v1
and Cloud withholds v2 work from it: the commands are durable and wait for the
upgrade rather than being lost, but they do wait. Upgrade the terminal and the
backend together.
