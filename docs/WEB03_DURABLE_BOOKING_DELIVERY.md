# WEB-03 — durable Website booking delivery

Status: **DONE at the delivery boundary**, candidate `3463ee406184fec7f53818416e11d0e5f5602c87` plus preserved working-tree changes, qualified 2026-10-13. This is not paid-booking production admission: WEB-01 and WEB-04 remain open. D002, the frozen legacy callback surface and existing booking/payment rules remain in force.

A confirmed payment previously committed before POS dispatch; the bridge then wrote `posReservationId` before queue insertion. A database error or process loss could leave a paid booking without work, or a link whose missing command was skipped by every subsequent callback.

## Current boundary

- The callback derives Venue from the server-owned booking and rechecks payment references under **Venue → booking** locks. Existing provider status mapping is unchanged. The payment outcome and immutable `WebsiteReservationDeliveryIntent` commit together. Failure to record the intent rolls back that outcome, allowing the provider's normal callback retry.
- First confirmation of a PENDING, unlinked booking reserves one POS identity in the intent, with its customer/table/stored-menu snapshot. Concurrent callbacks retain that snapshot and identity. A Venue lock and retained-identity unique index prevent reuse. A previously settled, untracked booking is not given a new CREATE intent just because a confirmation callback repeats.
- The bridge worker starts with the backend and polls every 15 seconds, admitting at most 50 due intents in due-time order. Multiple replicas share the Venue lock. Transient queue/database errors retain the intent with bounded backoff; recording and notification errors are logged without customer/provider payloads.
- **Queue insertion, booking POS link and intent receipt commit in one transaction.** Device history selects the existing Edge pull transport, including disabled devices: no secondary terminal or legacy fallback is selected automatically. An unenrolled non-bootstrap Venue waits visibly for enrollment. The bootstrap Venue alone can use the already frozen reservation endpoints, recorded in its durable legacy outbox without a LAN call inside the transaction.
- A conflicting identity, unavailable table or unsupported table encoding becomes `ATTENTION`. Nothing reselects tables, reprices the cart, changes a hold, refunds, or rebooks. Existing day-level availability and stale-mirror behavior remain unchanged; WEB-01 exclusivity/hold work is still necessary.
- Cancellation intent is also captured with the existing failed-payment outcome. When a tracked CREATE exists, CANCEL waits for its successful POS ACK (or accepted legacy callback), keeping the same POS identity. An uncertain/failed/pruned CREATE receipt makes cancellation operator-visible attention. A historical linked booking's cancellation retains its existing identity and the old whitespace normalization.
- Queue payload/key/target are immutable after admission. A scoped database trigger prevents generic enqueue from rewriting or reviving this outbox's terminal work, while unrelated command retry behavior remains unchanged. Existing Edge claim leases, Primary fencing, ACK and Hive idempotency apply. Lost ACKs redeliver the same command and reservation identity, not another booking.
- Read-only `GET /platform/venues/:venueId/website-deliveries?offset=0` and the Platform Venue Website panel distinguish waiting intent, queue, lease, success, failure, attention, legacy acceptance, and unknown/pruned outcome. Pages are bounded to 25 bookings. Only Platform authentication is accepted, including support read-only; no snapshot, customer contact, menu contents, payment reference or credential is projected. Historical creation tracking remains explicitly untracked even when a new cancellation is tracked. There is no retry/refund/rebook/write endpoint or button.

## Historical data and rollout

Additive migration: `20261019120000_website_reservation_delivery`. It creates the outbox, composite Venue/booking FK, indexes and scoped immutability guards. It does not backfill or replay historical bookings. Local deletion's child-first matrix includes the new model; no reset/deletion was executed.

Historical confirmed bookings with or without a POS link remain **UNTRACKED** until reconciled using actual POS/provider evidence. A pruned queue receipt means **UNKNOWN**, not success or permission to send again. Inspect the saved identity, the selected POS journal and actual booking first; code prevention does not repair old lost/uncertain deliveries. The read-only panel deliberately supplies no automatic repair policy.

Apply the additive migration before starting a compatible backend in an authorized deployment. Do not drop intents/receipts on rollback. Pause new booking creation and retain compatible callback/outbox handling; reverting to the old bridge with pending work would restore the loss window. No deployment, live migration, DNS/TLS, live-data change or live-service restart occurred in this task.

## Final qualification

Machine-readable evidence: [qualification](proofs/WEB03_3463ee40_2026-10-13/qualification.json).

| Check | Exact result |
|---|---|
| New WEB-03 actual Nest callback HTTP + PostgreSQL | 26 passed, 0 failed |
| WEB-06 / W1 / Website / SEC-01 / SEC-02 / tenant regressions on separate fresh PostgreSQL databases | 7 / 8 / 23 / 45 / 25 / 20 passed, 0 failed |
| Backend aggregate, including its mandatory fresh MENU-09 database | 851 passed, 801 opt-in skipped, 0 failed |
| Distinct backend tests across aggregate + focused runs | **1005 passed**, no overlap; 647 of the aggregate's opt-in skips were not run |
| Platform frontend aggregate | **176 passed**, 0 failed, including 6 new delivery panel state/interaction cases |
| Existing POS/Hive convergence + Edge journal tests | **28 passed**, 0 failed |
| Backend/frontend builds, TypeScript, Prisma validate/generate, contracts consistency | pass |
| Changed implementation/new test formatting and `git diff --check` | pass |
| New source/tests lint | clean; touched-source baseline retains 13 backend + 1 frontend errors, **zero new diagnostics** |
| Fresh install, populated upgrade and migration replay | pass; 2 historical booking rows byte-identical; 0 auto-created intents |

Fault injection covers failure to insert intent, failure to insert queue and failure after queue insertion before booking link; concurrent callbacks/workers; process-wake loss/recovery; lost ACK lease retry; immutable snapshots and identities; collision allocation; no terminal revival; unavailable table; cancellation ordering; historical/pruned receipts; same-organization/different-Venue and different-organization isolation; disabled Primary; bootstrap legacy outbox; read-only Platform authorization and privacy.

Provider signature acceptance is stubbed only in the new HTTP fixture; unsigned callbacks and mismatched payment references are rejected, and existing payment-reference and security regressions pass. Bank HTTP/credentials are synthetic; no real provider transaction was exercised. Workers were restarted as fresh service instances against retained synthetic rows, not by killing a deployed process. Flutter tests use temporary Hive data; they do not qualify actual Windows/Mac devices, networking or hardware. UI verification is jsdom state/interaction coverage, not a screenshot/browser visual qualification. The owned `/tmp` PostgreSQL cluster is stopped after qualification.

## Remaining plan decisions

- **WEB-01:** whole-day versus time-slot occupancy, and what to do when a payment arrives after its hold expires. Existing semantics were preserved, not selected anew.
- **WEB-04:** approved provider authorized/captured/partial/refund mapping and the owner of operational exceptions. This fix does not add an event ledger, verify settled amount/currency or change payment ordering.
- **INV01 F2:** the three outstanding product choices remain pending. POS02.C's other checkout work was reconciled and not duplicated.
