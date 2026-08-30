# Prompt — Phase 2: split database_service.dart (behavior-preserving)

Do this only after Phase 1 is done. **No behavior change.**

---

Refactor `apps/operations/lib/core/services/database_service.dart` (~6,600 lines) into
feature repositories, preserving behavior exactly. Read
`docs/VYNIC_PROJECT_PLAN.md` §3 and §6 (Phase 2) first.

Approach:
1. Propose a target layout before moving code, e.g.:
   `core/repositories/reservation_repository.dart`, `table_repository.dart`,
   `order_repository.dart`, `sales_repository.dart`, `settings_repository.dart`.
2. Move one concern at a time. Keep the existing `DatabaseService` static methods as
   thin delegators so **no call sites change** in the same step.
3. Do not alter logic, Hive box usage, `SyncHub` events, or method signatures. Pure
   extraction/mechanical move.
4. One concern per commit. After each: `dart format`, `flutter analyze`,
   `flutter build macos --debug`, run any tests.

Hard rules:
- Behavior must be identical — this is a structure change only.
- No new features, no status changes, no "while I'm here" fixes. Note anything you
  spot; don't fix it here.
- Never swallow errors; keep existing error handling as-is (except obvious existing
  `null`-swallow bugs — flag those to me, don't silently rewrite).
- `git status --short` before/after. Do not commit unless I say so.
