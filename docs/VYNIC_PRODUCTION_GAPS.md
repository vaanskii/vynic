# Vynic Production Gaps — Reliability & Data Integrity

**Date:** 2026-07-21. Every finding cites source. P0 = production blocker for Vankisi launch.

---

## 1. P0 production blockers

### P0-1 · Table close is not atomic and not idempotent (money loss / duplication)
**Evidence:** `apps/operations/lib/apps/windows_pos/screens/order_detail_screen.dart:2351-2460` (`_finalizeTableClosure`): `closeOrderWithPayment` → `saveSaleRecord` → optional advance `saveSaleRecord` → `refreshDailySalesTotalForDate` → background print, each a separate `await`. `CloseTableTransaction.withPayment` (`close_table_transaction.dart`) returns `true` even if the audit append throws, and returns `true` again if called on an already-closed order.
**Failure scenarios:**
- Crash/power loss after close, before sale record → order is `closed` with **no revenue record**; close-day (`close_day_transaction.dart:213-219`) then deletes the order → the sale is gone from every report.
- Double invocation (double-tap, dialog re-entry, event replay) → **duplicate sale records** → inflated revenue and cash expectation.
**Fix:** single `CloseTableTransaction` that (a) refuses when `status == closed`, (b) writes order status + sale record + audit event before returning, (c) is keyed by a `closureId` (uuid) stored on both order and sale record so re-runs are no-ops, (d) recovery scan at startup: `closed` orders in today's box without a matching sale record → alert + repair screen.
**Blocking: YES.**

### P0-2 · Kitchen tickets can be silently lost
**Evidence:** `print_queue.dart` — in-memory `Queue`, no persistence. `printer_transport.dart` — `_maxRetries = 2`, then `false`. `printer_service.dart` catches everything to `developer.log`. No persistent print ledger; `onComplete` toast is the only surfacing and is optional.
**Failure scenarios:** printer off/jammed for >3 attempts, POS restart with queued jobs, transient LAN drop → guests' order never reaches kitchen; nobody is alerted; no record it failed.
**Fix:** durable Hive-backed print spool (job = rendered bytes + target + orderId + status + attempts), background drain with backoff **forever** until acknowledged/cancelled, a red "N failed prints" banner on the POS home screen, and a print ledger row per job (audit). Reprint = re-enqueue same job id (dedupe).
**Blocking: YES** — this is the classic "lost order" in a real service.

### P0-3 · No cash management or reconciliation
**Evidence:** no opening-float, drawer, cash-count, or expected-vs-actual concept anywhere (`grep` across client/server; close-day transaction has zero cash steps). X-report exists (`monthly_report_service.dart`, admin close-day section) but is informational.
**Failure:** cash difference (theft, mistakes) is undetectable; close-day produces reports nobody can trust against the drawer.
**Fix:** minimum viable cash module — see [VYNIC_ARCHITECTURE_PLAN.md](VYNIC_ARCHITECTURE_PLAN.md) §4: opening float at day open, cash in/out entries (already have expenses), expected cash = float + cash sales − cash out, counted cash entry at close-day, difference stored + manager-signed.
**Blocking: YES** for money trust; small to build.

### P0-4 · Close-day: non-atomic, error-blind, double-runnable
**Evidence:** `close_day_transaction.dart` — sequential awaits (finalize reservations → advance date → reset totals → delete closed orders → free tables) inside one `try` whose `catch` returns `false` (line 241-244) — caller cannot distinguish "active orders remain" from "crashed halfway". Nothing prevents a second run advancing the date again. Orders are **hard-deleted** at close (line 213-219) — order-level history survives only as schemaless sale maps.
**Fix:** staged close with a persisted `closeDayState` marker (started/step/completed) so a crashed close resumes instead of half-applying; typed result enum instead of bool; confirmation shows the date being closed and refuses if it already closed; archive orders (move to a `closedOrders` box or keep with `businessDate` index) instead of delete.
**Blocking: YES.**

### P0-5 · Website reservation double-booking race
**Evidence:** `reservation.service.ts:createReservation` — `areWebsiteTablesAvailable(...)` check then `websiteReservation.create(...)` with no transaction/lock/unique constraint; nothing in `schema.prisma` prevents two reservations holding the same table+date+slot.
**Failure:** two customers paying deposits for the same table on a banquet night.
**Fix:** unique partial constraint (e.g. `ReservationTableHold(tableId, date, timeSlot)` unique where status in PENDING/CONFIRMED) written in the same transaction as the reservation; map constraint violation → "table just taken".
**Blocking: YES** (real money via deposits).

### P0-6 · Plaintext PIN pipeline (see SECURITY audit S-1/S-2)
Blocking for production per SYNC_CONTRACT.md §7.2's own mandate.

### P0-7 · Unbounded sync payload growth
**Evidence:** `manager_sync_service.dart` full sync sends `salesHistoryByDate` built from **`getAllSales()`** (every sale ever, with per-day `closedTables` incl. item lines, top-300 items/day) and `_syncAuditReports` always sends **all** audit reports with `fullSync: true`. Server body limit 50 MB (`main.ts`).
**Failure:** after months of service the periodic sync becomes slow (json encode in isolate, but upload+server upsert loops are O(history)), then starts failing at the body limit — and because the flag-based retry keeps re-attempting the same giant payload, POS→cloud sync effectively dies.
**Fix:** window full history to N days + a one-time backfill command; audit-report sync switches to since-timestamp incremental with occasional reconciliation.
**Blocking: YES over time** (a time bomb, not a day-one failure).

### P0-8 · Money as binary floating point end-to-end
**Evidence:** Dart `double` everywhere (`Order.totalAmount`, sale maps), Prisma `Float` (`schema.prisma` Order/OrderItem/Expense/DailySnapshot), patched by `double.parse(toStringAsFixed(2))` at each hop (e.g. `table_payment_service.dart:_round`, `sales_repository.dart`).
**Failure:** ±0.01 drifts across split tender / service fee / discount combinations; X-report vs drawer mismatches that erode trust.
**Fix (incremental, no rewrite):** server: migrate money columns to `Decimal`; client: centralize all arithmetic in one `Money` helper (int tetri) used by recalculateTotal/payment/sales paths; keep wire format as fixed-2 strings/cents.
**Blocking: YES (server migration + client helper), full int-tetri conversion can be staged.**

---

## 2. High-priority (not launch-blocking, fix soon)

| ID | Finding | Evidence | Risk |
|---|---|---|---|
| H-1 | Day-open auto-activation creates real orders for evening reservations, locking tables all day | `activate_reservation_transaction.dart:activateTodaysReservations` (creates orders); plan §2 fix-direction item explicitly deferred | Walk-ins blocked from reserved tables at 11:00 for a 20:00 booking; staff confusion |
| H-2 | LWW conflict compares POS clock vs server clock | `sync-conflict.ts` (`posWinsOrderConflict(order.updatedAt [POS], outboxRow.createdAt [server])`) | Clock skew silently flips winners; mobile edits lost or POS edits reverted |
| H-3 | Business date silently resets if settings box is fresh | `business_day_repository.dart:getCurrentDate` `defaultValue: DateTime.now()` | Host rename / data-dir move → wrong business date → server reconciliation deletes "stale" orders for that date (`sync.controller.ts:790-813`) |
| H-4 | Error-swallowing persists in money paths | `deleteOrderAndCleanup` catch→false; `CloseTableTransaction` catch→false; contradicts AGENTS.md hard rule | Failures indistinguishable from business refusals |
| H-5 | Kitchen routing by item-name string matching | `kitchen_print_filter.dart` | Renamed item → drink misclassified → not printed in kitchen |
| H-6 | Restore-closed-order doesn't reverse daily totals atomically | `restoreClosedOrderFromSale` + separate `refreshDailySalesTotalForDate` | Momentary/crash-window inconsistent totals |
| H-7 | Server order snapshot deletes rows for current date not in POS push (protected only by incoming ids + pending outbox) | `sync.controller.ts:780-824` | Combined with H-3 or a partial POS box, valid orders can be dropped from the manager view (POS Hive remains truthful) |
| H-8 | No guest-count requirement; avg check/covers analytics unreliable | `order_detail_screen.dart:322` | Reporting quality |
| H-9 | Dependency vulns: 2 high (multer chain), 1 moderate (protobufjs) | `npm audit` 2026-07-21 | Server exposure |
| H-10 | Mobile JWT 24 h, no refresh/rotation; logout ≠ revocation | `auth.service.ts` | Stolen phone risk window |

---

## 3. Failure-mode table (workflow-mapped)

| Step | Possible failure | Likelihood | Impact | Existing protection | Missing protection | Fix | P0? |
|---|---|---|---|---|---|---|---|
| Open day | Wrong date after data-dir reset | Low | High (report corruption, H-3) | none | explicit open-day confirmation | Confirm date at first login of day; alarm if date ≠ yesterday+1 | no |
| Open table | Double-open same table | Low | Med | `createOrder` throws `StateError` on reserved table [verified] | — | keep | — |
| Send to kitchen | Ticket lost (printer down/restart) | **Med** | **High** | 2 retries, persistent conn | durable spool, alarm, ledger | P0-2 | **yes** |
| Second round | Delta ticket duplicated on retry | Low | Med | sequential queue | job idempotency key | include in P0-2 | yes |
| Mobile edit vs POS edit | Wrong edit wins on clock skew | Low-Med | Med | LWW + held snapshots + echo guards | monotonic/logical versioning | H-2: add per-order version counter | no |
| Discount | Unattributable approval | Med | Med | shared destructive password | per-manager PIN approval + audit identity | replace mechanism | no |
| Payment | Crash between close & sale record | Low | **High** (silent revenue loss) | none | atomic close + recovery scan | P0-1 | **yes** |
| Payment | Double-tap duplicate sale | Med | High | dialog flow only | closed-status refusal + closureId | P0-1 | **yes** |
| Split tender | Sum ≠ total | Low | Med | ±0.01 tolerance validation [verified] | float-exact math | P0-8 | partial |
| Website booking | Two deposits, one table | Low-Med | High | availability pre-check | transactional hold constraint | P0-5 | **yes** |
| Reservation day | Table locked all day by auto-activation | **High** (daily) | Med | — | reserve-without-order until seating | H-1 | no |
| Cash count | Drawer difference invisible | **Certain** | High | none | cash module | P0-3 | **yes** |
| Close day | Half-applied close after crash | Low | **High** | guards before mutation | staged/resumable close | P0-4 | **yes** |
| Close day | Double close advances two days | Low | High | none | closed-date marker refusal | P0-4 | **yes** |
| Sync | Payload outgrows limit; sync dies | **Certain, months** | High | 50 MB limit (failure mode, not protection) | windowed history | P0-7 | **yes** |
| Restart | POS restart mid-service | Med | Low | Hive persistence + startup sync + stale-boot guard [verified] | print spool (P0-2) | — | — |
| Server restart | Outbox rows survive, resume | — | Low | `PosCallbackOutbox` persisted, boot retry [verified] | — | — | — |

---

## 4. What is already reliable (verified, keep as-is)

- **Cloud→POS outbox**: persisted rows, exponential backoff capped 60 s, transport failures don't burn the attempt budget, `kickPending()` revives failed rows on POS reconnect (`pos-outbox.service.ts`) — this is the pattern the rest of the system should copy.
- **Audit event log**: UUID-keyed, append-only, `synced` flag, idempotent server upsert (`audit_event_service.dart` + `sync.controller.ts:syncAuditEventLogs`).
- **Mobile order-id allocation**: `allocateMobileOrderId` (≥90001, counter ∨ max+1, P2002 retry classification) — collision-safe against offline POS counters.
- **Stale-boot table protection** + business-date-advance table reset (`sync.controller.ts:509-587, 1120-1161`).
- **BOG callback signature** over preserved raw body (`main.ts` verify hook + `payment.controller.ts`).
- **Reservation close-day finalization** (Phase 1 fix) — confirmed present in `close_day_transaction.dart` and `activate_reservation_transaction.dart` (typed results, per-item try/catch, `linkedOrderId` marker).
