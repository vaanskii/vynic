# Vynic Architecture Plan — Implementation-Ready Designs

**Date:** 2026-07-21. Designs for everything classified **Critical now** or **Important after core launch** in [VYNIC_FEATURE_STRATEGY.md](VYNIC_FEATURE_STRATEGY.md). All designs are incremental — no module rewrite. Examples are illustrative, not full implementations.

Ordering principle: **§1–§5 are prerequisites for §6–§9.** Do not build inventory on top of a non-atomic close.

---

## 1. Atomic, idempotent table closure (fixes P0-1)

### Client (POS)
New single entry point replacing the `_finalizeTableClosure` sequence:

```dart
class CloseTableTransaction {
  /// Idempotent: closureId is generated once by the UI when the payment
  /// dialog confirms; re-running with the same id is a no-op success.
  static Future<CloseTableResult> run({
    required int orderId,
    required String closureId,          // uuid, stored on order AND sale
    required TablePaymentSelection payment,
    required String closedById,
  }) async { ... }
}

sealed class CloseTableResult {}          // success / alreadyClosed /
                                          // orderNotFound / failure(reason)
```

Rules:
- Refuse (return `alreadyClosed`) when `order.closureId != null || statusEnum == closed`.
- Write order mutation + `SaleRecord` + audit closing event before returning success; on any thrown error return `failure(e)` **and log**, never `false`.
- Startup recovery scan: orders with `status == closed && closureId != null` lacking a sale record with that `closureId` → surfaced on a "needs attention" banner (repair = regenerate sale record from order snapshot).
- Typed `SaleRecord` Hive model (new adapter, typeId next free) replacing raw maps for new writes; legacy maps still readable. Fields: `closureId (key)`, orderId, businessDate, items[], subtotal, serviceFee, discount, manualAdjustment, total, paymentBreakdown{method→amount}, tipAmount, isFiscal, isCancelled, restoredToOrder, createdBy, closedById, closedAt.

### Server
- Prisma `Order`: add `closureId String? @unique` (migration additive; backfill null). Sync upsert passes it through. Duplicate snapshot upserts stay idempotent by `posOrderId` as today.
- Money columns migrated `Float → Decimal(12,2)` (`totalAmount`, `discountAmount`, `currentBill`, `OrderItem.price`, `Expense.amount`, DailySnapshot fields). Additive-safe migration; Prisma Decimal serializes as string — mobile parsing already goes through `Number(...)`, adjust mappers.

### Tests
Unit: double-run same closureId → one sale record; crash simulation (throw between steps) → recovery scan finds orphan; split-tender sums exact at 2 dp. These are the first money tests in the repo.

Rollback: keep old code path behind a settings flag for one release; sale records written by the new path are a superset.

---

## 2. Durable print spool + station routing (fixes P0-2, H-5)

### Model (Hive box `printJobs`)
```dart
class PrintJob {              // typeId next free
  String id;                  // uuid — idempotency key
  PrintTarget target;         // kitchen | bar | receipt  (stations, see below)
  List<int> payloadBytes;     // rendered ESC/POS, rendered ONCE at enqueue
  int? orderId; String? label;
  PrintJobStatus status;      // queued | delivered | failed | cancelled
  int attempts; DateTime createdAt; DateTime? deliveredAt; String? lastError;
}
```
- `PrintQueue.enqueue` writes the job to Hive **before** attempting; drain loop (existing sequential per-target semantics) marks delivered/failed; backoff 5 s → 60 s cap, retry indefinitely while `queued`.
- On app start: re-drain all `queued` jobs (crash recovery). `failed` requires operator action.
- POS home banner: `N failed prints` (red) with retry/cancel per job — the alarm P0-2 demands.
- Delivered/cancelled jobs pruned after 7 days; the job list **is** the print audit ledger (syncs via existing audit-log channel as `PRINT_FAILED` / `PRINT_RETRIED` events).

### Station routing (replaces name matching)
- `MenuItemDB` + server `MenuItem`: add `station String` (`'kitchen' | 'bar' | 'none'`, default from category `sendToKitchen`). Admin menu section edits it. `KitchenPrintFilter` becomes a lookup by itemKey → station; the keyword fallback stays only for unknown items and **logs loudly**.
- Settings: printer per station (`kitchen`, `bar` optional second printer, `receipt`). Vankisi can run bar==kitchen initially; model supports the split without code change.

Duplicate prevention: enqueue is keyed — callers that retry a UI action pass the same job id (e.g. `kitchen_<orderId>_<deltaHash>`); dedupe rejects an id already `queued|delivered`.

---

## 3. Staged close-day (fixes P0-4)

Persist progress in settings: `closeDay:{date}:state` = `started|reservationsDone|dateAdvanced|purged|done` + timestamp + userId.

Flow: guards (unchanged) → write `started` → finalize reservations → record operated date → **cash reconciliation step (§4)** → advance date → reset daily total → archive (not delete) closed orders into `closedOrders` box keyed by businessDate (retention: 90 days locally; server keeps summaries as today) → free tables → `done`.

- Re-entry: if state ≠ `done` at startup or on retry, resume from the recorded step (each step idempotent).
- Double-close guard: refuse if `closeDay:{date}:state == done` for the current date, or if requested date ≠ current business date.
- Return `CloseDayResult` enum (blockedByActiveOrders / blockedByTakeaways / blockedByCash / resumed / done / failure(reason)) — kills the bool ambiguity (H-4).
- Server: on `day_closed` broadcast nothing changes; `Setting['closeDayCompleted:<date>'] = true` synced for mobile display.

---

## 4. Cash management MVP (fixes P0-3)

### Client model (Hive `cashEvents` box, typed)
```dart
class CashEvent {
  String id; String businessDate;       // uuid + day key
  CashEventType type;                   // openingFloat | cashIn | cashOut |
                                        // expensePaid | tipOut | countedClose
  double amount; String reason; String byUserId; DateTime at;
}
```
- Day open (first login of a new business date): modal asks opening float (prefill = last counted close).
- Cash out/in from admin quick action; `expensePaid` auto-created when an expense with `paymentType == cash` is saved (link id).
- Close-day step: expected = openingFloat + Σcash sales (from SaleRecords) + Σ(cashIn − cashOut − cash expenses); operator enters counted; difference stored as `countedClose` event with delta; manager identity required (per-manager PIN, §5).
- Z-close print: existing `printTextReport` renders expected/counted/difference + payment breakdown.
- Sync: cashEvents piggyback on the audit-log channel (UUID-idempotent) → new server table `CashEvent` mirroring fields, `@@unique([id])`, indexed by businessDate → mobile financials shows drawer status live.
- Tips: `tipAmount` field on SaleRecord (entered on the payment screen, default 0); reported daily; payout via `tipOut` cash event.

---

## 5. Identity-bound manager approval (fixes S-6, part of S-1)

- PIN hashes on POS (`User.pinHash`, salt per user; migration hashes existing `pinCode` then blanks it — Hive migration v4 per `HIVE_MIGRATIONS.md` workflow; **do not hand-edit `.g.dart`** beyond the documented exception).
- `ManagerApprovalService.request(action, context) → ApprovalResult{managerUserId}`: dialog accepts any active manager's PIN, verifies against hash, returns identity; audit event records `approvedBy` distinct from `performedBy`.
- Replaces destructive-password dialogs at: order cancel, item removal after send (void), discount above threshold, restore closed order, cash difference sign-off. The shared destructive password is retired (kept one release as fallback behind a flag).
- Sync payload: `staff` array sends `{username, role}` only (strip `pin`) — provisioning stays on the explicit `/mobile-user-*` callbacks. Server bcrypt path is already correct; delete `StaffPinVault` after the mobile "view PIN" feature is replaced with "reset PIN".

Line-item **void** semantics ride on this: removal of a sent item requires approval + reason code (`out_of_stock | guest_changed_mind | kitchen_error | other`), writes `AuditEventType.voidItem` (new), prints a kitchen delta (already supported via removedItems).

---

## 6. Inventory MVP (Important after core)

### Prisma (server = source of truth for stock; POS sends consumption events)
```prisma
model Ingredient { id String @id @default(uuid()); name String; unit Unit;
  minStock Decimal(12,3)?; isActive Boolean @default(true);
  updatedAt DateTime @updatedAt; @@schema("pos") }
enum Unit { G KG ML L PCS PKG @@schema("pos") }
model UnitConversion { id String @id @default(uuid()); ingredientId String;
  fromUnit Unit; toUnit Unit; factor Decimal(12,6);
  @@unique([ingredientId, fromUnit, toUnit]) @@schema("pos") }

model Recipe { id String @id @default(uuid()); menuItemId String;
  version Int; isActive Boolean;          // versioned: history stays accurate
  createdAt DateTime @default(now());
  lines RecipeLine[];
  @@unique([menuItemId, version]) @@schema("pos") }
model RecipeLine { id String @id @default(uuid()); recipeId String;
  ingredientId String; qty Decimal(12,3); unit Unit; @@schema("pos") }

model StockMovement { id String @id @default(uuid());  // POS event id — idempotent
  ingredientId String; qty Decimal(12,3);              // signed
  type StockMovementType; businessDate String;
  sourceId String?;      // closureId | wasteId | purchaseId | countId
  byUser String; at DateTime;
  @@unique([id]) @@index([ingredientId, businessDate]) @@schema("pos") }
enum StockMovementType { SALE_DEDUCTION WASTE PURCHASE COUNT_ADJUST TRANSFER @@schema("pos") }

model Purchase { id String @id @default(uuid()); supplierId String?;
  businessDate String; total Decimal(12,2); items PurchaseItem[] @@schema("pos") }
model PurchaseItem { id String @id @default(uuid()); purchaseId String;
  ingredientId String; qty Decimal(12,3); unit Unit; cost Decimal(12,2) @@schema("pos") }
model Supplier { id String @id @default(uuid()); name String; phone String? @@schema("pos") }
model StockCount { id String @id @default(uuid()); businessDate String;
  ingredientId String; countedQty Decimal(12,3); byUser String @@schema("pos") }
```
TheoreticalStock = Σ movements; Variance = last count − theoretical at count time; FoodCost from PurchaseItem weighted average; MenuProfitability = price − Σ(recipeLine qty × ingredient cost) using the recipe version active at sale time.

### Deduction semantics (the part that must be exact)
- Deduct **on order close**, inside the atomic close (§1): for each sale line, resolve active recipe version → emit `StockMovement(type: SALE_DEDUCTION, id: hash(closureId, lineKey, ingredientId), sourceId: closureId)`.
- Idempotency: the deterministic movement id + `@@unique([id])` makes offline replay/duplicate sync impossible to double-deduct.
- Cancels/voids before close: nothing was deducted → nothing to reverse. Restore-closed-order (`restoredToOrder`): emit compensating positive movements keyed `hash(closureId,'restore',...)`. Complimentary (non-fiscal close): still deducts (food left the kitchen). Waste: manual entry (dish or ingredient level). Recipe edits create a new version; old movements keep pointing at their version.
- POS keeps a read-only theoretical-stock cache + low-stock badge; stock truth lives server-side (inventory is a back-office concern; the POS only emits events — keeps offline semantics trivial).

### NestJS
`InventoryModule`: `IngredientsController/Service`, `RecipesController/Service`, `StockController/Service` (`POST /inventory/movements:batch` idempotent ingest from POS audit-channel, `GET /inventory/stock`, `GET /inventory/variance`, `GET /inventory/food-cost`). Manager-role guarded. WS event `stock_updated` (coalesced).

### Flutter
Admin sections: Ingredients, Recipes (per menu item, versioned editor), Purchases, Waste, Stock count sheet. Mobile: stock overview + low-stock notifications (existing hybrid channel).

---

## 7. Waiter Mode (Important after core)

- `APP_ROLE=waiter` third boot mode in `main.dart` (pattern exists; evidence: POS/manager split).
- Reuses: models, `MobileApiService` transport (JWT with new `WAITER` scope — extend `MOBILE_APP_STAFF_ROLES` and add `RolesGuard` per-route instead of controller-wide MANAGER), monitoring socket for table state, server→POS callback path for mutations (`/mobile-order-create|update` already exist; add `X-Acting-User` so audit attributes the waiter, not "მობილური მენეჯერი" — currently hardcoded fallback in `pos_ingest_server.dart:_handleOrderUpdate`).
- Server additions: `WAITER`-scoped endpoint subset (own/assigned tables only — add `assignedFloor` to Staff), rate-limited.
- Screens (5): PIN login → floor/table grid (reusing floor-plan painters) → order compose (menu + favorites + notes) → confirm/send → my-tables list with statuses. No payment, no admin.
- Offline: not supported v1 (device must reach server or POS ingest on LAN — prefer direct-to-POS LAN path when reachable, fall back to cloud callback).
- Acceptance: waiter sends a round from the floor; ticket prints; POS shows items within 2 s (LAN) / 15 s (cloud path); audit shows the waiter's name.

## 8. Attendance (Important after core)

Hive `attendance` box + server `AttendanceEntry(id @unique, userId, businessDate, clockIn, clockOut?, editedBy?)`; clock-in prompt at first PIN login of the business day, clock-out on logout/day close sweep; manager edit screen; syncs over audit channel (idempotent ids). Payroll formulas (fixed daily + threshold % + bonus/penalty/advance) come later, computed from AttendanceEntry × per-waiter sales × CashEvent advances — schema reserves `PayrollPeriod`, not built now.

## 9. Sync hardening designs (P0-7, H-2, H-3)

- **Windowed history:** full sync sends `salesHistoryByDate` for last 35 days + dates changed since last ack (server returns `lastSummaryDates` hash so client can skip unchanged); one-shot `POST /sync/backfill` admin action streams older history in date-chunks. Audit reports: add `updatedSince` incremental push, weekly full reconciliation.
- **Versioned order conflicts:** add `rev Int` on POS order (incremented on each local mutation) sent in snapshots; outbox rows record the `rev` they were based on; server LWW uses `rev` comparison instead of cross-clock timestamps; timestamps stay as tiebreaker.
- **Business-date guard:** `getCurrentDate` with no stored value → require explicit manager confirmation before first sync (blocks the silent-reset deletion path).
- **Snapshot schema validation:** class-validator DTO for `SyncPayload` (bounded array sizes, string lengths) behind PosSyncGuard.

## 10. Cross-cutting rules for every design above

- Idempotency: every event that leaves a device carries a UUID; every server ingest has a unique constraint on it.
- Ordering: per-entity monotonic `rev`; cross-entity ordering not assumed anywhere.
- Transactions: Prisma `$transaction` around multi-row server writes (menu sync loops, order+items upsert — currently unwrapped); Hive multi-step flows get staged markers (§1, §3 pattern).
- Auditability: new sensitive actions (cash events, voids, approvals, print failures, stock adjustments) all emit `AuditEventLog` rows — the channel already exists and is idempotent.
- Soft delete: server rows gain `isActive`/`deletedAt` instead of `deleteMany` where history matters (staff, menu items, website tables). Snapshot reconciliation flips flags rather than deleting.
- Migration strategy: all Prisma changes additive (new columns nullable/defaulted, new tables); Hive changes via `HiveMigrationService` versioned migrations (v4 PIN hash, v5 SaleRecord, v6 attendance/cash boxes) with backup-first (BackupRepository exists).
- Rollback: feature flags in settings for each new flow for one release; old read paths preserved.
- Tests required per design: idempotent-replay test, crash-mid-flow test, and a money-sum property test (Σ breakdown == total) — server Jest + client `flutter test`.
