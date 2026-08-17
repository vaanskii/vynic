# Vynic Feature Strategy

**Date:** 2026-07-21. Competitor claims are research inputs only — classified as *publicly claimed*, *officially documented*, or *unknown*; none are technically verified by us. Recommendations require a Vankisi justification, not competitor parity.

---

## 1. Competitor & industry snapshot

| Capability | RestIQ | iiko | Toast | Lightspeed | Square | Poster | MICROS | GloriaFood | Vynic today (verified) |
|---|---|---|---|---|---|---|---|---|---|
| Table-service POS | claimed | documented | documented | documented | documented | documented | documented | ✗ (online ordering focus) | ✅ implemented |
| Offline operation | claimed | claimed | **documented** (offline mode + local-sync hub; printed tickets continue offline) | partial/claimed | claimed | claimed ("keep taking orders, printing, kitchen tickets offline") | documented (on-prem heritage) | n/a | ✅ **stronger**: POS is offline-*first*, not offline-*fallback* |
| KDS | claimed (with recipes) | claimed | documented | claimed | claimed | claimed | documented | n/a | ❌ |
| Kitchen printer routing per station | claimed | documented | documented | documented | documented | documented | documented | n/a | ❌ (single kitchen printer) |
| Recipe/ingredient inventory + auto-deduction on sale | claimed | documented (auto deduction, forecasting) | claimed | documented | partial | **documented** (deduction on order close, per-storage rules) | documented | n/a | ❌ |
| Suppliers/purchases/waste/food cost | claimed | documented | claimed | documented | partial | documented | documented | n/a | ❌ (manual expense entries only) |
| Staff schedules/attendance/payroll | claimed | claimed | claimed (add-on) | partial | claimed | claimed | claimed | n/a | ❌ (perf. attribution only) |
| Reservations w/ exact table pick | unknown | partial | via add-ons | partial | ✗ mostly | partial | partial | ✗ | ✅ **implemented incl. website 3D map + deposit payments** |
| Floor-plan editor (walls, stages, custom objects) | unknown | partial | basic | basic | basic | basic | yes (enterprise config) | n/a | ✅ implemented, unusually rich |
| Mobile manager app | claimed | claimed | documented | claimed | documented | claimed | claimed | n/a | ✅ implemented (realtime + FCM + edits reaching POS) |
| Close-day / Z-report / cash reconciliation | claimed (shift open/close) | documented | documented | documented | documented | documented | documented | n/a | 🟡 close-day yes; **cash reconciliation missing** |
| Delivery integrations (Wolt/Glovo) | **claimed (both, Georgian market)** | claimed | US-centric | claimed | claimed | claimed | claimed | claimed | ❌ |
| QR menu / QR ordering | claimed | claimed | documented | claimed | documented | claimed | claimed | **core product** | ❌ (website menu exists) |
| Loyalty/customer profiles | claimed | claimed | documented | claimed | documented | claimed | claimed | claimed | 🟡 website accounts only |
| Multi-location / SaaS | claimed | documented | documented | documented | documented | documented | documented | claimed | ❌ (planned Phase 7-8) |
| Local Georgian bank terminal ecosystem | **claimed** | ✗ | ✗ | ✗ | ✗ | partial | ✗ | ✗ | ✅ TBC/BOG tender tracking; BOG e-commerce **implemented** |

**Industry baseline every mature system provides that Vynic lacks:** per-station kitchen routing, cash-drawer reconciliation with X/Z discipline, recipe inventory with deduction, structured modifiers, attendance. These are *standard restaurant requirements* (justification class 4), not feature envy.

**Where competitors are weakest vs Vynic's position:** cloud-first products (Toast/Square/Lightspeed) treat offline as degraded mode with documented caveats (e.g. Toast: router restarts break offline printing). Vynic's POS never needs the cloud for a single service operation — the правильный fit for Batumi's connectivity reality. RestIQ is the local benchmark: its claims (KDS, inventory, Wolt/Glovo, AI) are broad but unverified; its existence proves the Georgian market pays for exactly this category.

---

## 2. Vynic's strongest genuine advantages (proved from code)

| Advantage | Proof | Maturity | Weakness to fix | Owner-language selling point |
|---|---|---|---|---|
| **Offline-first service** | Entire POS path (orders, tables, printing, payments recording) touches only Hive + LAN (`core/database/*`, `printer_transport.dart`) | High | Print spool + close atomicity (P0-1/2) | «ინტერნეტი გაითიშა? რესტორანი მუშაობს ჩვეულებრივად — შეკვეთები, სამზარეულო, ჩეკები.» *Your restaurant keeps taking orders even when the internet fails.* |
| **Explicit business day** | `BusinessDayRepository` — day ends at close-day, not midnight | High | Open-day ritual + cash count missing | *The "day" is your working day, until you close it — late-night banquets land in the right report.* |
| **Custom floor-plan editor** | `widgets/admin/table_layouts/` — walls, stages, bars, stairs, rotation, bulk ops, corrupt-fallback | High, unusually rich | Extract 2,207-line dialog; mobile/website still code-based tables | *Draw your real restaurant — every floor, VIP room and banquet hall — yourself, no vendor visit.* |
| **Website ⇄ POS reservations with deposits** | `website-pos-reservation-bridge.service.ts`, BOG payments, signed callbacks, expiry cron | Medium-High | Double-booking race (P0-5); wire format legacy codes | *Guests book a specific table online, pay a deposit, and it appears on your POS by itself.* |
| **Mobile manager with real control** | 43 guarded endpoints; edits actually reach the POS via durable outbox (`pos-outbox.service.ts`) | High | Mobile offline mutations out of scope | *See every table and shift total from your phone — and fix an order without walking to the terminal.* |
| **Two-layer audit trail** | `AuditReport/AuditEvent` per order + append-only `AuditEventLog` idempotent sync | Medium-High | Approvals not identity-bound; prints unaudited | *Every removed item, discount and closed table is recorded — with who and when.* |
| **Georgian operational fit** | Georgian UI, GEL, TBC/BOG terminals, banquet packages (`Package` model), non-fiscal close | High | Georgian-only blocks SaaS later | *Built for how Georgian restaurants actually run — banquets, terminals, service fee.* |
| **Engineering discipline** | AGENTS.md, phased plan, migrations doc, echo guards, LWW, SSRF guard | — | Discipline hasn't reached money paths yet | (internal advantage: changes ship without regressions) |

---

## 3. Missing operational modules — evaluation

Classification: **Critical now** · **Important after core launch** · **Useful later** · **Not worth building yet**

### A. Waiter Mode — **Important after core launch**
Vankisi justification: multiple floors + private rooms mean walking to the terminal per round; a phone/tablet waiter flow cuts round-trip time (justification 1, 5).
**Recommended form: role-based mode in the existing shared Flutter app.** Evidence: the codebase already boots two apps from one codebase via `APP_ROLE` (`main.dart` ~L79; skill docs `vynic-pos` / `vynic-manager`) — a third `APP_ROLE=waiter` reuses core models, sync, and the ingest-callback path the mobile manager already uses. A separate app or web app would duplicate the offline stack for no benefit.
Constraint: waiter devices are online-dependent (they go through the server→POS callback path like the manager app). True offline waiter terminals would require POS-to-POS sync — explicitly out of scope (SYNC_CONTRACT §6). Scope v1: PIN login, assigned floor, table status, open table, add items/notes, send, request bill. No payments on the phone.

### B. Kitchen Display System — **Useful later; printing first**
Vankisi has kitchen **printers** and the printing pipeline is 90 % there. Decision: **printing only for launch** (hardened per P0-2 + per-station routing), KDS as a later add-on once order-item states exist. A KDS without reliable item-level status modeling (currently ❌) would be a screen showing tickets — the printer already does that. Revisit when second-round volume or remote stations (bar vs hot kitchen vs cold) justify it.

### C. Inventory & recipes — **Important after core launch** (MVP scope)
Justification: food-cost control is the owner's #1 economic lever (justification 5); every competitor treats it as core. But it must not precede money-path reliability — deductions derived from unreliable sale records would be garbage.
MVP (single restaurant, no warehouse complexity): Ingredient, Unit (g/kg/ml/l/pcs/pkg + conversions), Recipe per menu item, deduction **on order close** (same transaction as the sale record — P0-1's atomic close is the prerequisite), Waste entries, Purchase entries (extend existing expenses), theoretical stock + periodic StockCount → variance. Full design in [VYNIC_ARCHITECTURE_PLAN.md](VYNIC_ARCHITECTURE_PLAN.md) §6.
Deduction rules: on close (not on send — voids/cancels before payment then need no stock reversal; kitchen waste from cancelled-after-cooking is recorded as explicit Waste, which matches how small restaurants actually reconcile). Recipes are versioned (`RecipeVersion`) so historical cost reports stay accurate. Offline double-deduction is prevented by deriving deductions from the uniquely-keyed sale record (closureId), never from events.

### D. Attendance & payroll — **Attendance: Important after core. Payroll: Useful later.**
Justification: the requested compensation model (fixed daily + % of sales above threshold + bonuses + advances) needs (a) trustworthy per-waiter sales (exists), (b) attendance days (missing), (c) advances (partially exists as sale-record `advance` concept, misused for reservations deposits — keep separate). Build clock-in/out on the POS login screen first (one tap at login, one at logout, editable by manager, synced like audit logs). Payroll calculation only after a month of clean attendance + the cash module (advances are cash-out events).

### E. Cash management — **Critical now** (see P0-3)
Minimum launch scope: opening float at day open; cash-in/out with reasons (supplier payment, incasso, tips-out); expected cash computed from sale records; counted cash at close-day; difference stored, manager-attributed, printed on the Z-style close report. Tips: record card-tip amounts at payment (field on sale record) — payout handling later.

### F. Reporting & analytics
- **Possible now from existing data** (salesBox + audit): daily/hourly sales, by waiter, by product/category (names), payment methods, discounts given, cancellations, table turnover (from audit open/close), reservation conversion (POS+website rows).
- **Requires schema change**: covers/avg-check (enforce guest count), void reasons, tip reporting, cash differences (cash module), profit with real COGS.
- **Requires inventory**: food cost %, menu profitability, waste, variance.
- **Postpone**: forecasting, AI anything, cross-location comparisons.

### G. Customer & growth — **Not worth building yet** (all of it)
Loyalty, QR ordering, delivery integrations (Wolt/Glovo), SMS/push marketing, gift cards: none solve a current Vankisi operational problem and all depend on a stable core. Exception worth keeping warm: the website already has customer accounts + reservation history — a natural loyalty seed for V2/SaaS. QR **menu** (read-only) is nearly free (website menu exists) — acceptable as a marketing checkbox anytime.

---

## 4. Fix vs rebuild verdicts

| Area | Verdict | Reason |
|---|---|---|
| Offline sync (both directions) | **Fix/extend** | Outbox + snapshot model works; add windowing (P0-7) and versioning (H-2) |
| Order/close/payment path | **Fix** (make atomic + idempotent) | Logic correct, orchestration unsafe |
| Printing | **Fix** (durable spool + routing) | Renderers and transport fine |
| Close-day | **Fix** (staged + resumable) | Guards good, atomicity missing |
| Sales storage (Hive maps) | **Rebuild gradually** into typed model with ids | Schemaless maps are the root of report fragility — introduce typed `SaleRecord` with adapter migration, keep maps readable |
| sync.controller.ts | **Refactor** into services (menu/tables/orders/staff/summaries) | God-file, but behavior sound |
| Reservation wire format (encoded codes) | **Replace** with tableRefs (already planned Phase 7 item) | Known debt, contained |
| UI mega-screens | **Refactor opportunistically** (already happening: repositories split, order widgets extracted) | No rewrite justified |
| Nothing | **Full rewrite** | No module met the bar for rewrite |
