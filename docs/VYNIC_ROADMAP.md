# Vynic Roadmap

**Date:** 2026-07-21. Strict priority order, minimal parallel work. No time estimates by design.
P0 = production blockers · P1 = core Vankisi launch · P2 = high-value operations · P3 = growth.
Designs referenced: [VYNIC_ARCHITECTURE_PLAN.md](VYNIC_ARCHITECTURE_PLAN.md) (§n). Findings: [VYNIC_PRODUCTION_GAPS.md](VYNIC_PRODUCTION_GAPS.md) / [VYNIC_SECURITY_AUDIT.md](VYNIC_SECURITY_AUDIT.md).

---

## P0 — Production blockers (do first, in this order)

| # | Item | Solves | Apps | DB | Offline impact | Acceptance criteria | Rollback |
|---|---|---|---|---|---|---|---|
| P0-A | **Atomic idempotent table close** (§1) | P0-1 silent revenue loss / duplicate sales | POS client | Hive: SaleRecord model, closureId; server: `Order.closureId` | none (fully local) | double-run = 1 sale; crash-mid-close recovered by startup scan; Σbreakdown==total test green | settings flag to legacy path |
| P0-B | **Durable print spool + failure banner** (§2) | P0-2 lost kitchen tickets | POS client | Hive: printJobs box | improves offline | kill app with queued job → prints after restart; printer off 10 min → red banner, later delivery, ledger row | flag |
| P0-C | **Staged resumable close-day + archive orders** (§3) | P0-4 | POS client | Hive: closedOrders box, state markers | none | crash mid-close → resume; second close refused; closed orders queryable 90 d | flag |
| P0-D | **Cash management MVP** (§4) | P0-3 | POS + server + mobile read | Hive cashEvents; server CashEvent | events sync idempotently | open float → sales → count → difference printed & synced; drawer visible on mobile | additive only |
| P0-E | **PIN security package** (§5, S-1..S-4) | plaintext PINs, default admin, ingest fail-open | POS + server | Hive v4 migration (pinHash); drop vault | none | no plaintext PIN in Hive, payload, or server; ingest rejects keyless; first-run forces PIN | staged: hash-verify dual-read one release |
| P0-F | **Website reservation hold constraint** (P0-5) | double deposit booking | server | new unique hold table/constraint | n/a | concurrent create for same table/date/slot → exactly one succeeds | migration down |
| P0-G | **Sync payload windowing** (§9) | P0-7 unbounded growth | POS + server | none | protects sync | full sync bounded ≤35 d history; backfill command works; audit incremental | flag |
| P0-H | **Money type migration** (server Decimal + client Money helper) (§1) | P0-8 | both | Prisma Float→Decimal migration | none | all money columns Decimal; single rounding helper used by close/payment paths | tested migration + down |
| P0-I | **Hygiene**: `npm audit fix`, remove dev.db & artifacts, error-swallow sweep in money paths (H-4) | S-5, S-10 | both | none | none | audit clean; `git ls-files` clean; money-path catches rethrow typed results | trivial |

## P1 — Core launch (Vankisi go-live set)

| # | Item | Notes |
|---|---|---|
| P1-1 | Identity-bound manager approval + line-item **void with reason codes** (§5) | replaces shared destructive password; kitchen void delta already prints |
| P1-2 | **Per-station printer routing** (menu `station` field) (§2) | Vankisi: kitchen + optional bar; kills name-matching (H-5) |
| P1-3 | **Day-open ritual**: date confirmation + opening float + H-3 guard (§9) | one modal; blocks silent date reset |
| P1-4 | Reservation day-open behavior: reserve table **without creating order** until seating (H-1) | table shows "reserved 20:00" state; activation on arrival (transaction exists) |
| P1-5 | Guest count required on dine-in open (H-8) | one keypad step; enables covers/avg-check |
| P1-6 | Order `rev` versioning for conflicts (§9, H-2) | small; protects mobile-edit LWW |
| P1-7 | Tips field on payment + daily tip report (§4) | card tips reconciliation |
| P1-8 | Failure-visibility pass: sync health + failed prints + pending outbox on one admin status card (sync-4 exists partially) | manager can see "all green" before close |
| P1-9 | Test suite for money paths (close, cash, close-day, spool) | CI: `flutter test` + `npm test` gate |
| P1-10 | Ops runbook: backup/restore drill (BackupRepository), printer swap procedure, offline checklist, VLAN requirement | docs + tested restore |

## P2 — High-value operations (post-launch)

| # | Item | Depends on |
|---|---|---|
| P2-1 | **Attendance** (clock-in/out at login) (§8) | P0-E |
| P2-2 | **Inventory MVP**: ingredients, versioned recipes, close-time deduction, purchases, waste, counts, variance, food cost (§6) | P0-A (closureId), P0-H (Decimal) |
| P2-3 | **Waiter Mode** (`APP_ROLE=waiter`) (§7) | P1-1/2, server WAITER scope |
| P2-4 | Split bill by seat/items + merge tables | P0-A model supports multiple sale records per order |
| P2-5 | Structured modifiers (groups, prices) | menu model extension; kitchen ticket update |
| P2-6 | Favorites row + payment-flow flattening + responsive pass on menu/order screens (UX audit) | none |
| P2-7 | Reporting v2 on typed SaleRecords (hourly, covers, voids, cash diffs) | P0-A/D |
| P2-8 | Payroll foundation (fixed daily + threshold % + advances) | P2-1, P0-D |
| P2-9 | KDS pilot (single station) — only if printing pain persists | P2-2 item states |

## P3 — Growth / SaaS

Phase 7-8 from the project plan (Venue/tenancy, per-venue auth, entitlements, tableRefs wire format), localization (ka+en ARB), QR menu, loyalty on website accounts, delivery integrations (Wolt/Glovo — RestIQ parity), advanced analytics, second venue onboarding. **None before P0+P1 complete** — unchanged from the existing plan's own discipline.

---

## First 15 implementation tasks (exact order)

Each is independently executable and separately committable. Verification per repo rules: `dart format` / `flutter analyze` / `flutter build macos --debug --dart-define=APP_ROLE=pos` / `flutter test`; server `npm run lint && npm run build && npm test`; `git status --short` before/after.

1. **Add typed SaleRecord model + closureId field (schema only)**
   *Objective:* Hive `SaleRecord` adapter + `Order.closureId` + migration v5 scaffolding; dual-write behind flag, read path union (maps ∪ typed).
   *Why first:* every money fix hangs off this key; zero behavior change.
   *Files:* `core/models/sale_record.dart` (+.g.dart via build_runner — mind the memory note about hand-patched adapters), `core/models/order.dart`, `hive_migration_service.dart`, `sales_repository.dart`.
   *Accept:* migration runs on copy of real data dir; all existing reports unchanged. *Tests:* map↔typed round-trip. *Commit:* yes.

2. **Make table close atomic + idempotent** (P0-A)
   *Objective:* single `CloseTableTransaction.run(closureId…)` per §1; refuse re-close; typed result; UI double-tap guard.
   *Files:* `close_table_transaction.dart`, `order_detail_screen.dart:_finalizeTableClosure`, `home_take_away_section.dart`.
   *Accept:* double-invoke → one sale; already-closed → `alreadyClosed`; all four call sites migrated. *Tests:* new unit suite. *Commit:* yes.

3. **Startup money-recovery scan + attention banner**
   *Objective:* detect closed-without-sale and half-closed-day states at boot; banner + repair action.
   *Files:* new `core/services/pos/integrity_scan_service.dart`, home screen banner slot.
   *Accept:* seeded corrupt fixture surfaces and repairs. *Commit:* yes.

4. **Durable print spool** (P0-B)
   *Objective:* Hive-backed PrintJob per §2; drain on start; endless backoff while queued; failed-print banner + retry/cancel UI; ledger events to audit log.
   *Files:* `print_queue.dart` (rewrite internals, keep API), new `print_job.dart`, `printer_service.dart` enqueue points, home banner.
   *Accept:* app kill with queued job prints after restart; unplugged printer → banner within 60 s. *Commit:* yes.

5. **Print-job idempotency keys at call sites**
   *Objective:* deterministic job ids (`kitchen_<orderId>_<deltaHash>`, `receipt_<closureId>`); dedupe in spool.
   *Files:* kitchen/receipt call sites in `order_detail_screen.dart`, `menu_screen.dart`, ingest server print handlers.
   *Accept:* replayed callback prints once. *Commit:* yes (small).

6. **Staged resumable close-day + order archival** (P0-C)
   *Objective:* per §3; typed `CloseDayResult`; refuse double close; archive instead of delete.
   *Files:* `close_day_transaction.dart`, `admin_close_day_section.dart`, `database_core.dart` (box).
   *Accept:* crash-inject mid-close resumes; history screen reads archived orders. *Commit:* yes.

7. **Cash events + open-float + counted close** (P0-D)
   *Objective:* per §4 client side; close-day gains reconciliation step; Z-style print.
   *Files:* new `cash_repository.dart` + model, day-open modal, close-day section, report renderer.
   *Accept:* expected vs counted difference stored + printed + audit-logged. *Commit:* yes.

8. **Server CashEvent ingest + mobile drawer card**
   *Objective:* idempotent `POST /sync/cash-events`; Prisma model; financials screen card.
   *Files:* server `pos/` new controller slice, `schema.prisma` (+migration), mobile financials screen.
   *Accept:* replay batch → no dupes; mobile shows float/expected/counted. *Commit:* yes.

9. **POS PIN hashing (Hive v4) + local lockout** (P0-E part 1)
   *Objective:* per-user salt+hash, blank plaintext, dual-verify one release, 5-fail local lockout, first-run PIN wizard replacing `createDefaultAdmin` constant.
   *Files:* `user.dart` (+adapter migration), `user_repository.dart`, `login_screen.dart`, migration service.
   *Accept:* no plaintext PIN in any Hive box (scripted check); old PINs still log in once migrated. *Commit:* yes.

10. **Strip PINs from sync; retire server PIN vault** (P0-E part 2)
    *Objective:* staff payload = {username, role}; PIN changes only via explicit callbacks; delete `StaffPinVault` + mobile "view PIN" → "reset PIN".
    *Files:* `manager_sync_service.dart:862-872`, `sync.controller.ts` staff block, `staff-pin-vault.service.ts` (remove), `mobile-users.service.ts`, mobile users screen.
    *Accept:* payload capture shows no `pin` key; mobile reset flow works end-to-end. *Commit:* yes.

11. **Ingest server fail-closed + interface bind** (P0-E part 3)
    *Objective:* reject when key missing; bind chosen LAN interface; add basic per-IP rate limit; audit log auth failures.
    *Files:* `pos_ingest_server.dart:_isAuthorized/start`.
    *Accept:* keyless request → 403 always; callbacks still work from server. *Commit:* yes.

12. **Website reservation transactional hold** (P0-F)
    *Objective:* per §Gaps P0-5 — unique hold rows written in the reservation-create transaction; friendly conflict error.
    *Files:* `schema.prisma` (+migration), `reservation.service.ts:createReservation`, bridge availability path.
    *Accept:* parallel create race test → one CONFIRMED-able booking. *Tests:* jest concurrency test. *Commit:* yes.

13. **Sync history windowing + backfill** (P0-G)
    *Objective:* per §9 — 35-day window, changed-dates delta, admin backfill action; audit-reports incremental with weekly reconcile.
    *Files:* `manager_sync_service.dart` (payload builders), `sync.controller.ts` summaries block, admin connection section.
    *Accept:* payload size flat vs history length (measure with seeded 12-month fixture); mobile month views unchanged. *Commit:* yes.

14. **Server money columns → Decimal + client Money helper** (P0-H)
    *Objective:* Prisma migration; one rounding/summing helper adopted by recalcTotal, payment, cash, sales writers.
    *Files:* `schema.prisma`, server mappers, new `core/utils/money.dart`, `order.dart:recalculateTotal`, payment/sales call sites.
    *Accept:* property test Σ(parts)==total across 10k random splits; reports byte-identical on fixture. *Commit:* yes.

15. **Dependency + repo hygiene sweep** (P0-I)
    *Objective:* `npm audit fix` (verify build), remove `dev.db`/`flutter_01.*`/`deps.json` from tracking, add CI audit gate, sweep `catch → false` in `deleteOrderAndCleanup`/close paths to typed results.
    *Files:* package-lock, .gitignore, small repo edits.
    *Accept:* audit 0 high; tests green. *Commit:* yes.

Dependency notes: 2→1; 3→2; 5→4; 7→6 (close-day step) and →2 (expected cash from SaleRecords); 8→7; 10→9; 13 independent after 1; 14 anytime after 2 (helper) — sequenced late to avoid churn under tasks 2–7.

---

## Vankisi launch scope (exact)

**In:** P0-A…P0-I + P1-1…P1-10. Functionally: today's POS + atomic money path, durable printing with stations, cash reconciliation, staged close-day, hashed PINs + identity approvals, reservation-hold fix, windowed sync, day-open ritual, tips capture, void reasons, ops runbook.
**Explicitly out:** inventory, attendance, waiter mode, KDS, split-by-seat, modifiers rework, loyalty/QR/delivery, tenancy, localization.

## Version 2 scope

P2-1…P2-8: attendance → inventory MVP → waiter mode → split/merge → modifiers → UX speed pass → reporting v2 → payroll foundation. KDS only on demonstrated need.

## Future SaaS scope

Phase 7-9 per project plan: Venue/venueId everywhere, per-venue sync credentials + entitlements, tableRefs wire migration, ka+en l10n, feature-flag gate, billing, second venue pilot. Precondition: V2 stable at Vankisi for a full month of close-days with zero P0-class incidents.

---

## Final production launch checklist

- [ ] All P0 tasks merged; money-path test suite green in CI
- [ ] 3 consecutive rehearsal days on a staging terminal: open → service (incl. forced printer outage + forced offline hour + mid-service POS restart) → cash count → close-day, zero discrepancies
- [ ] Security checklist from [VYNIC_SECURITY_AUDIT.md](VYNIC_SECURITY_AUDIT.md) §checklist complete (PINs, HTTPS, VLAN, secrets rotation)
- [ ] Backup/restore drill executed on both Postgres and Hive data dir
- [ ] Failure-visibility card shows green states for sync/outbox/prints
- [ ] Staff trained: void/approval flow, failed-print banner response, cash count, day-open ritual
- [ ] Rollback plan: previous build installer retained; feature flags documented
