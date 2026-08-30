# Vynic Product Audit

**Date:** 2026-07-21 · **Scope:** full repository, read-only · **Deployment target:** Vankisi restaurant, Batumi
**Companion docs:** [VYNIC_PRODUCTION_GAPS.md](VYNIC_PRODUCTION_GAPS.md) · [VYNIC_SECURITY_AUDIT.md](VYNIC_SECURITY_AUDIT.md) · [VYNIC_FEATURE_STRATEGY.md](VYNIC_FEATURE_STRATEGY.md) · [VYNIC_ARCHITECTURE_PLAN.md](VYNIC_ARCHITECTURE_PLAN.md) · [VYNIC_ROADMAP.md](VYNIC_ROADMAP.md)

Every claim below is labeled: **[verified]** (read in source), **[inferred]** (deduced from code but not executed), **[docs]** (documentation claim only), or **[recommendation]**.

---

## 1. Executive assessment (blunt)

Vynic is a **real, substantially engineered single-restaurant POS**, not a prototype. The offline-first POS core, the server→POS durable outbox, the floor-plan editor, the audit trail, and the website→POS reservation bridge are genuinely implemented and thoughtfully hardened in places (echo suppression, LWW conflict resolution, SSRF guard, BOG signature verification over raw bytes). The phased engineering discipline (AGENTS.md, plan, small commits) is far above typical solo-project standard.

It is **not yet safe to run Vankisi's money on it unattended**. The specific reasons, all verified in source:

1. **Table close is not atomic.** `_finalizeTableClosure` (order_detail_screen.dart:2351-2460) runs close → sale record → advance record → print as separate awaits with no transaction, no idempotency key, and `return true` even when the audit append fails. A crash or double-tap can close an order with no sale record (revenue silently missing after close-day deletes the order) or write duplicate sale records.
2. **Kitchen tickets can be silently lost.** The print queue (`print_queue.dart`) is in-memory only; a crash, restart, or exhausted retry (2 retries, `printer_transport.dart`) drops the ticket with only a `developer.log`. There is no durable spool, no reprint ledger, no operator-facing failed-print alarm surface.
3. **Cash management does not exist.** No opening float, no cash-in/out, no expected-vs-counted reconciliation, no Z-report lock. Close-day (`close_day_transaction.dart`) never asks how much cash is in the drawer.
4. **All money is binary floating point** (Dart `double`, Prisma `Float`) patched with `double.parse(toStringAsFixed(2))` at ~40 call sites.
5. **Staff PINs are plaintext** in Hive (`User.pinCode`), pushed plaintext to the server on every full sync (`manager_sync_service.dart:866`), and stored server-side in a *recoverable* encrypted vault (`staff-pin-vault.service.ts`) — with a hardcoded default manager PIN `000000` (`user_repository.dart:createDefaultAdmin`).

None of this requires a rewrite. The architecture is sound; the gaps are completable.

---

## 2. Repository architecture map [verified]

```
vynic/
├── apps/operations/           Flutter monorepo — ONE codebase, TWO apps via APP_ROLE
│   └── lib/
│       ├── main.dart          APP_ROLE dart-define selects UI: (default)=manager, pos=Windows POS
│       ├── apps/windows_pos/  POS UI: login, home, menu, order_detail, admin (5 screens + widgets)
│       ├── apps/mobile_app/   Manager app: dashboard, financials, orders, reservations, staff,
│       │                      audit, emergency controls, calculator, counted menus
│       └── core/
│           ├── database/      DatabaseCore (13 Hive boxes) + 13 repositories + 3 transactions
│           │                  (close_day, close_table, activate_reservation)
│           ├── models/        Hive models (+ .g.dart adapters): Order, TableModel, Reservation,
│           │                  User, MenuCategoryDB, Package, QuickOrderDraft; enums:
│           │                  OrderStatus, ReservationStatus, StaffRole, PosPermission, TableRef
│           ├── services/
│           │   ├── sync/      manager_sync_service (POS→cloud snapshot push),
│           │   │              pos_ingest_server (cloud→POS HTTP, port 8081),
│           │   │              monitoring_socket_service, api_config, sync_events (SyncHub)
│           │   ├── printing/  printer_service, print_queue (in-memory), printer_transport (raw
│           │   │              TCP 9100), escpos renderers (kitchen/receipt/report),
│           │   │              kitchen_print_filter (name-based food/drink routing)
│           │   ├── audit/     audit_event_service (durable append-only log + batched sync)
│           │   ├── auth/      mobile_auth_service (JWT for manager app)
│           │   ├── pos/       table_payment_service, monthly_report_service, change highlights
│           │   └── notifications/ firebase_messaging_service, manager_notification_inbox
│           └── services/database_service.dart  1,281-line delegating façade over repositories
├── apps/backend/              NestJS + Prisma + PostgreSQL (schemas: pos, website)
│   └── src/
│       ├── pos/               sync.controller (POST /sync/manager-data, /sync/audit-reports,
│       │                      /sync/audit-logs), pos-outbox.service (durable cloud→POS queue,
│       │                      backoff + kickPending), pos-callback.client, sync-echo-guard,
│       │                      sync-conflict (LWW)
│       ├── mobile/            JWT+MANAGER guarded manager API (43 endpoints): orders,
│       │                      reservations, users, menu, reports, dashboard, devices
│       ├── realtime/          MonitoringGateway (Socket.IO, JWT handshake, 'managers' room),
│       │                      hybrid notifications (WS + FCM), presence
│       ├── website/           public menu, cookie+CSRF customer auth (argon2 refresh),
│       │                      reservations, BOG payments (RSA callback verification),
│       │                      website-pos-reservation-bridge
│       ├── auth/              JwtStrategy, PosSyncGuard (X-POS-Sync-Key, fail-closed in prod),
│       │                      LoginThrottleService (5 fails → 15 min IP lock), StaffPinVault
│       └── prisma/schema.prisma  pos: Table, Order(posOrderId unique), OrderItem, Menu*, Staff,
│                              Audit*, DailySnapshot, Setting, ManagerNotification*, PushDevice,
│                              PosCallbackOutbox · website: users, tables, reservations
├── docs/                      project plan, SYNC_CONTRACT.md, UI plan/tokens, archive
├── prompts/, .claude/skills/  agent task prompts + skill
└── secrets/                   Firebase admin SDK json (gitignored ✓)
```

### Data flows [verified]

1. **POS → cloud:** whole-snapshot push to `POST /sync/manager-data` (tables, today's orders + items, menu, staff **including plaintext PINs**, all-time sales history, business date, hints). Triggered on Hive change (debounced flag + 30 s retry timer) and 3 s after startup. There is **no per-event outbox on the POS side** — durability comes from re-pushing full snapshots.
2. **Cloud → POS:** mobile mutations enqueue rows in `PosCallbackOutbox` → `PosCallbackClient` HTTP-POSTs to the POS's `PosIngestServer` on LAN port 8081 (`x-connection-key` shared secret). Retries with backoff; `kickPending()` flushes when the POS next syncs. This *is* a real durable outbox.
3. **Cloud → mobile:** Socket.IO events (`order_updated`, `table_updated`, `tables_bulk_touch`, `orders_bulk_touch`, `data_updated`, `day_closed`, `audit_updated`) to the JWT-authenticated `managers` room + FCM push for background users.
4. **Website → POS:** reservation created `PENDING` → BOG payment → signed callback → `CONFIRMED` → `WebsitePosReservationBridgeService.pushConfirmedReservationToPos` → outbox → POS Hive.
5. **Printers:** POS → raw TCP :9100, one kitchen printer + one receipt printer (single IP each from settings).

### Ownership problems [verified]

- Kitchen routing decision lives in **item/category names** (`kitchen_print_filter.dart` string-matches item names against menu cache, falls back to drink keywords) — fragile, not data-driven per station.
- `sync.controller.ts` is 1,462 lines mixing menu upsert, table sync, order LWW, staff sync, settings, sales summaries, and notification hints — the server-side god-file.
- Sales history lives as **schemaless `Map`s in Hive `salesBox`** (`sales_repository.dart`), duplicated into server `Setting` rows as JSON strings (`salesSummary:<date>`), not queryable rows.
- Legacy encoded table codes (`>10 = second floor`) remain the wire format for reservations (`reservation-table-codes.ts`, mobile, website) while POS is ref-based — documented Phase 7 debt.

---

## 3. Verified feature inventory

Status legend: ✅ Fully implemented · 🟡 Partially implemented · 🖥 UI only · ☁ Backend only · 📄 Planned in docs · ❌ Missing · ⚠️ Risky · ❓ Cannot be verified

### POS

| Feature | Status | Evidence & notes |
|---|---|---|
| Staff PIN login | ✅⚠️ | `login_screen.dart` — auto-login at ≥4 digits (fast). ⚠️ PINs plaintext in Hive; default manager `vaanskii`/`000000` (`user_repository.dart`) |
| Floor selection | ✅ | `table_selection_widget.dart` + data-driven `RestaurantTableLayout` zones |
| Table opening / walk-in | ✅ | `OrderRepository.createOrder` — reserves tables, creates walk-in reservation record, audit events |
| Guest count | 🟡 | Stored on linked reservation (`order_detail_screen.dart:322-336`), not required at open; defaults 0 |
| Menu browse/search/categories | ✅ | `menu_screen.dart` (2,818 lines) — categories, subcategories, variants, search |
| Favorites | ❌ | No favorites concept found in menu code |
| Modifiers | 🟡 | Free-text `OrderItem.comment` only; no structured modifier groups/prices |
| Item notes | ✅ | `comment` on `OrderItem` |
| Order creation / add items later | ✅ | `OrderRepository.addItemToOrder`, kitchen delta printing of added/removed items |
| Order status | ✅ | `OrderStatus` enum (Phase 4): pending/confirmed/…/closed/cancelled |
| Discount | ✅⚠️ | `order.discountAmount`; gated by `PosPermission.applyDiscount`; approval = shared destructive password, not per-manager PIN |
| Void (line item) | ❌ | Explicitly absent — `pos_permission.dart:38` "There is no line-item void yet". Item removal exists but isn't a distinct audited void with reasons |
| Order cancellation | ✅ | `deleteOrderAndCleanup` (manager + destructive password); ⚠️ swallows errors to `false` |
| Manager approval | 🟡⚠️ | Shared **destructive-action password** (salted SHA, `settings_repository.dart:486`) — not per-manager identity; approvals not attributable |
| Table transfer | ✅ | `changeTable` flow in `order_detail_screen.dart` |
| Table merge (two open orders) | ❌ | Not found; multi-table orders exist, merging separate orders does not |
| Split bill (by seat/item) | ❌ | Only split **tender** (cash+card) — `table_payment_service.dart`. No per-guest checks |
| Payment (cash/card/split tender) | ✅⚠️ | `TablePaymentService` cash / TBC / BOG / split; ⚠️ non-atomic close sequence (see §1.1) |
| Tips | ❌ | Zero occurrences in codebase |
| Refunds | ❌ | `pos_permission.dart:47` "No refund action exists anywhere in the app yet" |
| Reopen closed order | ✅ | `SalesRepository.restoreClosedOrderFromSale` — same-day only, table-conflict-checked |
| Receipt printing | ✅ | ESC/POS renderer with logo, Georgian, PDF preview fallback |
| Business-day handling | ✅⚠️ | `BusinessDayRepository.currentDate` decoupled from wall clock; ⚠️ default when settings missing = `DateTime.now()` — a fresh/moved data dir silently resets the business date |
| Takeaway orders | ✅ | `home_take_away_section.dart` + linked takeaway reservations |
| Banquet packages | ✅ | `Package` model, `createOrderForPackage`, per-person pricing, allowed tables |
| Counted menus / quick drafts | ✅ | `QuickOrderDraft` + server sync + mobile print |

### Tables & floor plans

| Feature | Status | Evidence |
|---|---|---|
| Multiple floors / dynamic extra floors | ✅ | `RestaurantTableLayout` zones; editor supports adding floors |
| Table statuses + realtime | ✅ | `TableModel.isReserved/activeOrderId`, `TableOperationalStatus` enum, socket `table_updated` |
| Floor-plan editor (drag, shapes, rotation, walls, entrances, stage/bar/stairs/labels, multi-select, bulk edit) | ✅ | `widgets/admin/table_layouts/` (~2,207-line section), shared painters in `widgets/floor_plan/` |
| Corrupt-layout fallback, stable numbering, refuse dropping occupied tables | ✅ | Commits `0c65953`, `1c3f04c`, `e1075de` + code in layout save path |
| Reservation overlays on plan | ✅ | Table selector renders saved plan with reservation state |
| Website "exact table" mapping | ✅ | `WebsiteTable.posTableNumber/posFloor` mapping + 3D map endpoint `getPublicMapReservations` |

### Kitchen & printing

| Feature | Status | Evidence & notes |
|---|---|---|
| Kitchen check printing (initial + deltas) | ✅ | `escpos_kitchen_renderer.dart`, added/removed item sections |
| Kitchen stations / per-station routing | ❌ | One kitchen printer IP (`getKitchenPrinterIp`). Routing = food-vs-drink only |
| Product→printer routing rules | 🟡⚠️ | `kitchen_print_filter.dart` matches **item names** against menu `sendToKitchen` flags, falls back to keyword list — renames break routing |
| Retry logic | 🟡 | 2 retries + persistent-connection fallback (`printer_transport.dart`) — then gives up |
| Offline printing | ✅ | Printing is fully local (LAN TCP), independent of internet |
| Durable queue / crash recovery | ❌⚠️ | `print_queue.dart` is in-memory `Queue` — restart loses pending jobs |
| Duplicate prevention | 🟡 | Sequential per-target queue prevents interleaving; nothing prevents re-enqueue of the same ticket |
| Missing-print detection / print audit | ❌ | Failures go to `developer.log` + optional toast; no persistent record that ticket N was/wasn't printed |
| Printer health / reconnection | 🟡 | `PrinterConnectionManager` persistent sockets + `testConnections`; admin printers section exists |
| Reprint | ✅ | `PosPermission.reprintReceipt` (open to all roles) |
| KDS | ❌ | No kitchen display anywhere |

### Payments

| Feature | Status | Notes |
|---|---|---|
| Cash / card (TBC, BOG terminal) / split tender | ✅ | Breakdown persisted in sale record `paymentBreakdown` |
| Payment entity / idempotency | ❌⚠️ | No `Payment` model anywhere (server `Order.paymentType` is one string). Sale records are schemaless Hive maps |
| Duplicate-payment protection | ❌⚠️ | No guard against double `_finalizeTableClosure` beyond dialog flow |
| Refunds / cancelled payments | 🟡 | `cancelSaleRecord` + `restoreClosedOrderFromSale` (all-or-nothing, same-day); no partial refund |
| Online payment (BOG e-commerce) | ✅ | `payment.service.ts` — OAuth, order create, **RSA-SHA256 callback verification over raw body** [verified], server-side price recalculation, manipulation detection |
| Payment status polling | ✅ | `check-status/:orderId` reconciles via BOG receipt API |
| Close-day reconciliation | ❌ | No expected-vs-counted anywhere |

### Reservations

| Feature | Status | Notes |
|---|---|---|
| Website reservation creation + deposit payment | ✅⚠️ | `reservation.service.ts:createReservation`; ⚠️ availability check → create is **not transactional** — two concurrent customers can double-book the same table (no DB constraint prevents it) |
| Pending expiry | ✅ | Cron every minute fails PENDING >10 min |
| Confirmed → POS delivery | ✅ | Bridge + outbox; `posReservationId` backlink prevents re-push |
| Payment-failed → POS cancel | ✅ | `cancelPosReservation` on FAILED |
| POS reservation CRUD, table refs, availability | ✅ | `reservation_repository.dart`, `ReservationTableAvailability`, db v3 migration to `tableRefs` |
| Activation (manual + day-open auto) | ✅⚠️ | `activate_reservation_transaction.dart` — typed results, per-item isolation (Phase 1 fix verified). ⚠️ **Auto-activation still creates real orders at day-open**, locking tables from morning for evening bookings (plan §2 "reconsider" not done) |
| Completion / no-show at close-day | ✅ | `close_day_transaction.dart:156-193` completed/no-show finalization [verified — Phase 1 fix real] |
| Timezone/business-date behavior | 🟡 | Website `dayBounds` is calendar-day; POS is business-day — a reservation "today" after midnight but before close-day is ambiguous between systems [inferred] |
| Duplicate prevention | 🟡 | POS: `linkedOrderId` marker (fixed). Website: none under concurrency |

### Mobile manager

| Feature | Status | Notes |
|---|---|---|
| Dashboard (revenue, open payable, occupancy) | ✅ | `dashboard_screen.dart` (3,013 lines), `mobile-dashboard.service.ts`, `shiftTotalRevenue` |
| Orders list/detail/edit/cancel | ✅ | Edits flow through outbox → POS Hive; LWW conflict handling on the server [verified in `sync-conflict.ts` + spec] |
| Takeaway + walk-in creation from mobile | ✅ | Server allocates collision-safe `posOrderId` ≥ 90001 (`allocateMobileOrderId`) — clean solution [verified] |
| Reservations CRUD + print check | ✅ | Via callbacks |
| Financial reports / month history | ✅ | Reads `salesSummary:<date>` Settings mirrors of POS history |
| Staff performance | ✅ | `staff_performance_screen.dart` from waiter attribution on orders |
| Notifications (WS + FCM, inbox, coalescing) | ✅ | `hybrid-notification.service.ts`, delivery dedupe table |
| Emergency controls | ✅ | `emergency_controls_screen.dart` + `POST /mobile/tables/:n/free` |
| Offline behavior | 🟡 | Read cache fallback (`mobile_cache_service.dart`); mutations need network (documented out of scope) |
| Permissions | ✅ | JWT + `RolesGuard` MANAGER on the whole controller (`mobile.controller.ts:32`) |

### Staff & permissions

✅ Roles (manager/supervisor/waiter, legacy admin migrated), `PosPermission` facade (16 gates), per-target `canManageStaffUser`, staff sync with deletion reconciliation protected against in-flight outbox changes [verified — unusually careful]. ⚠️ Gaps: plaintext PINs, no per-manager approval PIN at POS, no inactive flag on POS side (server has `isActive`), attendance/clock-in **missing entirely**.

### Audit & reporting

✅ Two-layer audit: per-order `AuditReport`+`AuditEvent` (locked on close, full-set sync w/ reconciliation) and append-only `AuditEventLog` (UUID-idempotent, durable local queue, 2-min batched sync — the one true event-outbox in the system). ✅ X-report, monthly report service, sales/audit admin sections, mobile audit tab. ⚠️ All reporting reads schemaless Hive maps; historical accuracy depends on those maps never corrupting; server copies are JSON blobs in `Setting`, not queryable.

### Offline sync (POS↔cloud)

| Property | Status | Notes |
|---|---|---|
| POS fully operational offline | ✅ | All service paths are Hive+LAN local |
| POS→cloud durability | 🟡 | Snapshot re-push + pending flag + 30 s timer; converges, but no event granularity, no ordering, no dead-letter |
| Cloud→POS durability | ✅ | `PosCallbackOutbox` with backoff, revival of failed rows, collapse dedupe |
| Conflict resolution | 🟡 | LWW POS-vs-queued-mobile-edit (`posWinsOrderConflict`); ⚠️ compares POS clock vs server clock — skew-sensitive |
| Echo/duplicate suppression | ✅ | `sync-echo-guard.ts` re-armed at delivery time |
| Snapshot payload growth | ⚠️ | Full sync sends **all-time** sales history + all audit reports every push (`salesHistoryByDate`, `fullSync: true`) — unbounded growth; 50 MB body limit is the only ceiling |
| Restart recovery | ✅ | 3 s-delayed startup sync; stale-boot protection on server (skip "all tables free" cold push) |

---

## 4. Real restaurant workflow audit (open → close)

Verdict per step of the required Vankisi day; failure detail and the full failure-mode table live in [VYNIC_PRODUCTION_GAPS.md](VYNIC_PRODUCTION_GAPS.md).

| # | Step | Works today? | Weakest point |
|---|---|---|---|
| 1 | Manager opens business day | 🟡 implicit | No explicit "open day" act or opening cash float; date advances only at close |
| 2 | Employee clocks in | ❌ | No attendance system |
| 3 | PIN login | ✅ | Plaintext PIN store; shared-knowledge PINs |
| 4–6 | Floor → table → guests | ✅ | Guest count optional (skews avg-check analytics) |
| 7–9 | Add items, notes, send to kitchen | ✅ | Modifiers are free text; "send" = status confirm + print |
| 10 | Kitchen receives correct items | ⚠️ | Silent loss on printer failure/restart — **worst operational risk** |
| 11–12 | Second round, station routing | 🟡 | Delta printing ✅; only one kitchen station exists |
| 13 | Manager notifications | ✅ | WS+FCM hybrid verified |
| 14–16 | Bill, split, pay cash+card | 🟡 | Split tender ✅; per-guest split ❌; close not atomic ⚠️ |
| 17 | Void one product | 🟡 | Removal + audit event exists; no reason codes, no distinct void semantics |
| 18 | Discount w/ manager approval | 🟡 | Shared password ≠ manager identity |
| 19 | Staff performance updates | ✅ | Waiter attribution on orders/sales |
| 20 | Inventory reduced | ❌ | No inventory module |
| 21 | Reservation completed | ✅ | Close-table + close-day finalization (Phase 1 fix) |
| 22 | Cash counted | ❌ | No cash count workflow |
| 23 | Business day closed | 🟡 | Guards ✅ (active orders, takeaways, stale locks); atomicity ❌, error→`false` ambiguity ⚠️ |
| 24 | Reports generated | ✅ | X-report + history; from schemaless maps |
| 25 | Offline events synchronize | ✅ | Snapshot convergence + outbox |
| 26 | Audit shows sensitive actions | 🟡 | Order lifecycle ✅; approvals not identity-attributed; prints not audited |

---

## 5. UX & speed audit (Windows POS)

Measured from code paths (tap counts assume configured printers and a logged-in view):

| Action | Interactions | Assessment |
|---|---|---|
| Log in | 4–6 digits, auto-submit at match | ✅ excellent (`login_screen.dart:addDigit`) |
| Open table | floor tab → table tap → (guest dialog) | ✅ ~2-3 taps |
| Add common product | category → (subcategory) → item | 🟡 2–3 taps; **no favorites row** for top sellers |
| Send order | confirm button → prints | ✅ |
| Split-tender payment | pay → method → [bank] → confirm | 🟡 3–4 dialogs deep (`table_payment_service.dart` chains method → bank → confirm modals) |
| Void/cancel order | actions panel → destructive password dialog | 🟡 password typing is slow mid-service |
| Second round | reopen table → add → send | ✅ |
| Switch floors | 1 tap | ✅ |

Findings [verified]:
- **Dialog stacking** is the dominant pattern: `menu_screen.dart` 7 `showDialog`s, `order_detail_screen.dart` 9. Payment alone chains up to 3 modals + confirm.
- **Fixed pixel sizing**: 75 fixed width/height refs in `menu_screen.dart`, 66 in `order_detail_screen.dart`, fixed dialog widths (600/720/520 px) in payment service — breaks below ~1280 px and on tablets. Phase 6 (responsive) is planned but not started; design tokens (`vynic_status_tokens.dart`, commit 53dd7f8) exist.
- Georgian-only hardcoded strings (~2,870 per plan §4.3 [docs], spot-verified) — fine for Vankisi, blocks SaaS.
- `flutter analyze`: 275 issues, all info-level (deprecations/style), zero errors [verified run].
- Mega-screens (`admin_screen.dart` 3,513; `menu_screen.dart` 2,818; `order_detail_screen.dart` 2,933) make UI changes risky.
- No favorites, no "repeat last round", no keyboard shortcuts for Windows POS beyond on-screen keyboard.

**Do not visually redesign.** The wins are: favorites row, flatten payment to one screen, per-manager PIN approval instead of typed password, responsive pass on menu/order screens only.

---

## 6. Test & quality baseline [verified]

- Server: `npm test` **passes** (app.controller, sync-conflict, sync.controller specs). `npm audit`: **2 high, 1 moderate** (multer via @nestjs/platform-express; protobufjs DoS) — fix available.
- Client: 8 unit test files (enums, permissions, availability, tokens) + widget test dir. **No tests for money paths** (close table, sale records, close-day) — the highest-risk code is untested.
- `flutter analyze` clean of errors/warnings (275 infos).
- Committed artifacts that shouldn't be: `apps/backend/dev.db` (empty SQLite, still tracked), `apps/operations/flutter_01.png/.log`, `deps.json`.
