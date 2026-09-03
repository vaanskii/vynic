# Prompt — Phase 1: reservation close-day bug fix

The one behavior change currently allowed. Scope tightly. Small verified steps.

---

Fix the reservation-activation-after-close-day bug in Vynic. Read
`docs/VYNIC_PROJECT_PLAN.md` §2 first for the full root-cause map.

Symptom: `Reservation activation returned null` from `assign_reservation_to_table`;
tables stuck "busy" the day after close-day; stale `linkedOrderId`s.

Work in small, independently verifiable steps. Suggested order (confirm with me
before each step that changes behavior):

1. **Stop hiding the error.** In
   `apps/operations/lib/core/services/database_service.dart`, make
   `activateReservation` return a typed result (success with orderId / failure with a
   reason) or rethrow — and log the real error via the existing `logError` path.
   Update the caller in
   `apps/operations/lib/apps/windows_pos/screens/home_screen.dart` to show the real
   reason. **Do not** introduce new `null`-swallowing.
2. **Make the picker respect live table state.** In
   `home_reservation_table_assignment_dialog.dart`, mark a table unavailable when
   `TableModel.isReserved` / `activeOrderId` is set, in addition to the existing
   reservation-based check. Call `releaseStaleReservedTables()` before building the
   list.
3. **Finalize reservations in `closeDay`.** Mark activated reservations `completed`,
   clear `linkedOrderId`, and handle past unactivated ones (e.g. `no-show`). Don't
   leave stale links.
4. **Replace the fragile activation marker.** Stop using
   `notes.startsWith('Order #')`; use `linkedOrderId != null` or add an explicit
   `activatedAt`. Stop writing system text into the user-editable `notes` field.
5. **Isolate per-reservation activation.** Wrap each reservation in
   `activateTodaysReservations` in its own try/catch so one bad record can't abort
   the loop.
6. **Discuss with me** whether day-open should create orders at all, or only reserve
   tables until seating. Do not change this without agreement.

Constraints: no unrelated refactors; keep changes minimal and reviewable; one concern
per commit; never swallow errors in `null`/empty `catch`.

Verify each step: `flutter analyze`, `flutter build macos --debug` (or windows),
relevant `flutter test`; reproduce the old failure and confirm it's gone; confirm the
happy path (assign reservation → table → order) still works. `git status --short`
before/after. Do not commit unless I say so.
