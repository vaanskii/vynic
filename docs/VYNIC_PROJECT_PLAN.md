# Vynic — Master Project Plan

**Status:** active · **Owner:** giorgivanadze03@gmail.com · **Audience:** AI agents + maintainers

This is the single source of long-form context for the Vynic modernization. Skills
and prompts point here instead of repeating it. Read the section for your phase;
don't read the whole file if you don't need to.

---

## 1. Current system summary

- **`pos_app_client/`** — Flutter monorepo of two apps sharing `lib/core/`:
  - `apps/windows_pos/` — the POS. Local-first, persists to **Hive**. This is the
    **operational source of truth** during service.
  - `apps/mobile_app/` — manager app. REST + sockets to the server, with a cache
    fallback. Reads mostly; limited mutations.
- **`pos_app_server/`** — NestJS + Prisma + PostgreSQL. Mirrors POS data for the
  manager app and runs the customer website (menu, reservations, BOG payments).
  Architecture detail: `pos_app_server/CLAUDE.md`. Data-flow contract:
  `pos_app_client/docs/SYNC_CONTRACT.md`.
- **Persistence:** POS = Hive boxes; server = Postgres (`pos` + `website` schemas).
- **Business date:** POS tracks `currentDate` in settings, decoupled from wall clock
  ("POS day" ends at close-day, not midnight). Important — many bugs live here.

Single-restaurant today. One hardcoded floor plan, one language (Georgian), one
tenant, no feature gating.

---

## 2. Known bug — reservation activation after close-day (Phase 1 — FIXED)

**Status:** Fixed and committed (`40ed96d`). `ReservationRepository.activateReservation`
now returns a typed `ReservationActivationResult` (success/failure with reason) instead
of swallowing errors into `null`; the table picker checks
`TableModel.isReserved`/`activeOrderId`; `closeDayTransaction` finalizes reservations.
Verify against the symptom below before assuming it's fully closed out.

**Symptom (historical):** `Reservation activation returned null` logged from
`assign_reservation_to_table`; tables appear stuck/"busy" the day after close.

**Root causes (all in `pos_app_client/lib/core/services/database_service.dart`
unless noted):**

1. **Errors hidden behind `null`.** `activateReservation` (~line 6327) has ~5 silent
   `return null` paths **and** a catch-all that turns any exception into `null` with
   only a `developer.log`. The caller at
   `apps/windows_pos/screens/home_screen.dart` (~line 900) only sees `null` and can't
   report the real reason.
2. **Table picker ignores live table state.** The assignment dialog
   (`apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart`)
   computes availability **only from other reservations**
   (`unavailableTableCodesFromReservations`), never checking `TableModel.isReserved`
   / `activeOrderId`. A table locked by a walk-in or a stale lock still looks
   selectable, then `createOrder` (~line 1568) throws `StateError('Table X is busy')`
   → caught → `null`.
3. **`closeDay` doesn't finalize reservations.** `closeDay` (~line 4407) deletes
   closed orders and frees tables but leaves activated reservations with
   `status: 'in-progress'` and a stale `linkedOrderId` pointing at a now-deleted
   order. This is the "it keeps ids" symptom.
4. **Auto-activation re-grabs tables.** `activateTodaysReservations` (~line 6483)
   runs on business-date change and **creates real orders** for every confirmed
   reservation dated "today", locking tables hours before guests arrive. Manual
   assignment to those tables then throws.
5. **Activation marker is fragile.** "Already activated?" is detected by
   `notes.startsWith('Order #')`, but the edit-reservation dialog overwrites `notes`
   with user text → a reservation can be activated twice.
6. **No per-item isolation.** `activateTodaysReservations` has no per-reservation
   try/catch; one bad reservation (e.g. empty `tableNumbers` → `ArgumentError`)
   aborts the whole loop and retries next launch.

**Fix direction (see `prompts/02_RESERVATION_CLOSE_DAY_BUG.md`):** return a typed
result / rethrow + log real errors; make the picker respect `isReserved`; finalize
reservations in `closeDay`; replace the `notes` marker with `linkedOrderId` or a
dedicated `activatedAt` field; wrap each reservation activation in try/catch;
reconsider auto-creating orders at day-open (reserving the table is enough until
seating). Ship in small steps, each verified.

---

## 3. Architecture problems

- **God service:** `database_service.dart` (~6,600 lines) mixes persistence, orders,
  tables, reservations, sales, reports, settings, backup, exports.
- **Mega screens:** `admin_screen.dart` (~3,500), `order_detail_screen.dart`
  (~2,900), `menu_screen.dart` (~2,800) mix UI, validation, and domain rules.
- **No domain layer on the POS side** — screens call `DatabaseService` directly.
- **Duplicated table-code logic** — encode/decode + the `> 10 = VIP/second floor`
  convention is copied across ~11 files.
- **Reverse sync (server→POS) status is uncertain** — `pos_app_server/CLAUDE.md`
  describes it as working via outbox/callback; verify against the client before
  relying on it.

---

## 4. SaaS blockers (do NOT start these now — Phases 7–8)

1. **No tenancy.** No `Venue`/`Tenant` model; no `venueId` on any row; POS→cloud
   sync auth is one shared key. `posOrderId` is globally unique → collides with a
   second venue.
2. **Floor plan is compiled in.** `'first'`/`'second'`, `Table N` vs `VIP Zone N`,
   and the `code > 10` arithmetic are in business logic. Needs data-driven
   `Zone`/`Table` (Phase 3).
3. **No localization.** ~2,870 inline Georgian string literals. Needs ARB l10n
   (Phase 5).
4. **No feature flags / entitlements.** "Paid custom modules" (calculator, X-report,
   kitchen check, takeaway, website reservations) need a per-venue entitlement
   record + a single client gate (Phase 8).

---

## 5. UI / responsiveness problems

- Heavy use of fixed pixel dimensions (e.g. `menu_screen.dart`: ~75 fixed sizes vs 2
  responsive references). Breaks on other screen sizes.
- Colors/theme (`_primaryColor`, `_textPrimary`, …) passed manually through widget
  trees instead of `ThemeData`/`ColorScheme`.
- Staff workflow has too many modal/dialog layers (reservation → sheet → picker →
  confirm), which is slow and error-prone.
- **`plan.md` (root) is the detailed design/UI sub-plan** for this work. Phases 5–6
  below defer to it. Do not duplicate its content here.

---

## 6. Phased roadmap

Do phases **in order**. Do not skip ahead. Each phase = its own small change(s) +
verification, not one big commit.

- **Phase 0 — Repo hygiene + docs/skills cleanup.** (This doc set.) Archive stale
  docs, add AGENTS.md / plan / skill / prompts. Track `.DS_Store` in `.gitignore`.
- **Phase 1 — Reservation close-day bug fix. DONE.** Section 2 above.
- **Phase 2 — Split `database_service.dart` into feature repositories. DONE.**
  `database_service.dart` is now a ~1,265-line delegating façade
  over 13 repositories + 3 transactions in `pos_app_client/lib/core/database/`
  (`database_core.dart`, `repositories/`, `transactions/`). Behavior-preserving.
  `lib/core/services/` was also reorganized into concern
  folders (`auth/`, `sync/`, `notifications/`, `printing/`, `audit/`,
  `manager_app/`, `pos/`) as a follow-on hygiene pass — see git history for the
  file-by-file mapping. A second boundary cleanup moved shared UI/helpers
  (`pin_button.dart`, `service_fee_adjust_dialog.dart`,
  `home_reservations_helper.dart`) into `lib/core/`, kept manager-only toast UI in
  `apps/mobile_app/`, and removed `lib/core/` imports of `apps/*`. A final mobile
  layout cleanup renamed app-only `apps/mobile_app/core/theme/` to
  `apps/mobile_app/theme/` and consolidated mobile UI components under
  `apps/mobile_app/presentation/widgets/`. `core/models/` was left flat (small,
  not misleading; several files pair with Hive-generated `.g.dart` adapters we
  don't touch).
- **Phase 3 — Data-driven tables/zones. MOSTLY DONE.** Replace
  `'first'`/`'second'` and `> 10` with `Zone { id, name }` +
  `Table { id, zoneId, label, capacity }`.

  **What exists now:** `RestaurantTableLayout` (zones + tables + visual objects,
  JSON round-trip, `legacyFloor`/`legacyTableNumber` compatibility bridge) with
  three render modes — SVG map, button grid, and an app-created visual floor
  plan. The Windows POS Admin has a full floor-plan editor
  (`widgets/admin/table_layouts/`): draggable tables with shape presets,
  rotation, multi-select with bulk edits and group moves, point-to-point wall
  drawing with splitting/joints, wall-based entrances, venue objects
  (stage/bar/stairs/labels/…), dynamic extra floors, and a compact preview +
  expanded edit workspace. The active layout persists in settings
  (`activeTableLayoutJson`); saving reconciles the Hive table rows
  (`ensureTableLayoutConsistency`) and notifies sync. The table selector renders
  the saved plan; shared painters live in `widgets/floor_plan/`.

  **Hardening done:** corrupted saved layouts fall back to the default with a
  logged admin error; editor table numbers are stable across reorders/deletes;
  layout saves refuse to drop occupied tables (and the consistency pass never
  deletes them); all reservation table-code arithmetic is centralized in
  `ReservationTableAvailability`, `encodeTableCode` throws on codes the int
  encoding cannot represent (3rd floors, first-floor tables > 10), and pickers
  hide such tables (`canEncodeTableCode`). Unit-tested in
  `test/unit/reservation_table_availability_test.dart`.

  **Remaining:** (a) migrate `Reservation.tableNumbers` from encoded ints to
  stable table references so layouts beyond two floors / 10 first-floor tables
  become reservable — requires a Hive model change + `.g.dart` regeneration and
  a migration per `pos_app_client/docs/HIVE_MIGRATIONS.md`; get explicit
  sign-off before touching those. (b) Optional: extract the expanded-editor
  dialog out of `admin_table_layouts_section.dart` (~2,200 lines) into its own
  widget.
- **Phase 4 — Status enums + safer state.** Replace stringly-typed order/reservation
  statuses (`pending`/`confirmed`/`preparing`/`in-progress`, `startsWith('confirmed')`)
  with enums and explicit transitions.
- **Phase 5 — Localization + theme cleanup.** ARB l10n (`ka` + `en`); move colors
  into `ThemeData`/`ColorScheme`. Follow `plan.md`.
- **Phase 6 — Responsive UI rework.** Breakpoints (POS terminal / tablet / phone),
  `LayoutBuilder`/`Flexible` instead of fixed sizes, spacing/type scale from theme.
  Follow `plan.md`, screen by screen.
- **Phase 7 — Server SaaS foundation.** `Venue` model + `venueId` on every row +
  per-venue scoped auth + per-venue sync credentials + venue-scoped queries, rooms,
  notifications. Fix the global-unique `posOrderId`.
- **Phase 8 — Feature flags / entitlements.** Per-venue entitlements table synced to
  the client; single `Features.has(...)` gate replacing scattered checks.
- **Phase 9 — Onboard a second venue** (café/hotel/other restaurant). Only after
  1–8.

---

## 7. Do NOT do yet

- Do not start the SaaS migration (Phases 7–8) or add tenancy models now.
- Do not start the UI redesign / responsive rework (Phases 5–6) now.
- Do not change printer flow, sync flow, close-day semantics (beyond the Phase 1
  fix), order behavior, or DB shape as a side effect of another task.
- Do not introduce new `null`-swallowing error handling anywhere.
- Do not make sweeping cross-file refactors outside the current phase.

---

## 8. Verification

**Flutter client** (`cd pos_app_client`):
```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter build macos --debug     # or: flutter build windows --debug
flutter test                     # if the touched area has tests
```

**NestJS server** (`cd pos_app_server`):
```bash
npm run lint
npm run build
npm test
```

**Every task, regardless of phase:**
1. `git status --short` before and after — only intended files changed.
2. Run the relevant checks above.
3. For behavior changes (Phase 1): manually reproduce the old failure and confirm it
   no longer occurs; confirm the happy path still works.
4. Do not commit unless the user explicitly asks.

---

## 9. Related docs

- `AGENTS.md` — root rules for all agents.
- `plan.md` — UI/design system sub-plan (Phases 5–6).
- `pos_app_server/CLAUDE.md` — server architecture.
- `pos_app_client/docs/SYNC_CONTRACT.md` — POS↔server↔mobile data-flow contract.
- `pos_app_client/docs/HIVE_MIGRATIONS.md` — local schema migration workflow.
- `pos_app_client/docs/archive/` — superseded/historical docs (not current).
