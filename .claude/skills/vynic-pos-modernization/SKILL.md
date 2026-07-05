---
name: vynic-pos-modernization
description: Use when working on the Vynic restaurant POS (pos_app_client Flutter / pos_app_server NestJS) — fixing the reservation close-day bug, splitting database_service.dart, data-driven tables, status enums, localization/theme, responsive UI, or SaaS/tenancy work. Loads the phased plan and hard constraints so you act on the right phase without re-deriving context.
---

# Vynic POS modernization

Compact checklist. Long context lives in `docs/VYNIC_PROJECT_PLAN.md` — read it, don't repeat it.

## When to use
Any Vynic task: the reservation/close-day bug, refactors, tables/zones, statuses,
l10n/theme, responsive UI, or SaaS. Not for unrelated one-off questions.

## Read first (in order)
1. `AGENTS.md` — root rules.
2. `docs/VYNIC_PROJECT_PLAN.md` — find your phase; read that section + §7 + §8.
3. The matching file in `prompts/` if one exists.
4. For UI phases only: `docs/UI_PLAN.md`.

## Phase order (never skip)
0 hygiene/docs · 1 reservation close-day bug · 2 split `database_service.dart`
(behavior-preserving) · 3 data-driven tables/zones · 4 status enums · 5 l10n+theme ·
6 responsive UI · 7 server SaaS/`Venue`+`venueId` · 8 feature flags · 9 second venue.
Do exactly one phase.

## Hard constraints
- One phase at a time; small changes; small commits.
- No behavior change unless the task IS a behavior change (Phase 1 only, for now).
- Never swallow errors in `null`/empty `catch` — return a typed result or rethrow and
  log. (This is the live bug's root cause.)
- Do NOT start SaaS (7–8) or UI redesign (5–6) unless the task explicitly says so.
- Never touch secrets, `.env*`, Prisma migrations, `*.g.dart`, or assets. Prefer
  archiving to `docs/archive/` over deleting.

## Bug quick-map (Phase 1)
`database_service.dart`: `activateReservation` (~6327, null-swallowing),
`createOrder` (~1568, throws "table busy"), `closeDay` (~4407, doesn't finalize
reservations), `activateTodaysReservations` (~6483, re-grabs tables).
Picker ignoring live table state:
`apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart`.

## Verify before done
- `git status --short` before and after — only intended files changed.
- Client: `dart format --set-exit-if-changed .` · `flutter analyze` ·
  `flutter build macos --debug` (or windows) · `flutter test` if relevant.
- Server: `npm run lint && npm run build && npm test`.
- Phase 1: reproduce the old failure, confirm it's gone, confirm happy path.
- Do not commit unless the user says to.
