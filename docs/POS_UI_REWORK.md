# POS UI rework — approved design implemented

Scope: Flutter Windows POS and its internal Management Center. The separate Manager app is not redesigned. The work is prepared for the subsequently authorized publication of all legitimate pending repository changes. Existing checkout, reservation advance/hold, contact search, Manager-only estimate deletion and the collapsed Home side panel remain in place.

**Current status:** the approved Count composition is implemented in the working POS and carried through Takeaways, Reservations, Menu, Order, login and internal Admin. Shared forms, input behavior and the measured keyboard delay are corrected. The isolated Count candidate remains as design evidence; production-widget screenshots are listed below. Native Windows rendering and physical-touch qualification remain unperformed on this macOS host.

The approved community `flutter-ui-design` skill was fully reviewed, installed and byte-verified at commit `5b89c05fcd817d284a97e970e410a9b806a29d40`. It contains Markdown/JSON guidance and no executable hooks. The existing Flutter layout/testing skills remain in use; no UI dependencies, fonts or architectural replacements were introduced. [Installation evidence](proofs/POS_UI_REWORK/skill-install.json).

Shared visual foundation: `PosTheme` now selects the existing bundled Georgian font at the POS root. A regression reproduced Admin button styles dropping that font; button, menu and feedback styles now preserve it. Shared page/Admin/modal controls and pane switches use 56 logical pixels (about 48 painted pixels at 1024×768). Keyboard/PIN controls use the same existing Vynic palette; windows below 700 logical pixels high keep compact keys so the active form remains visible. No authentication, transaction or permission rules changed.

## Implemented visual system

The approved direction uses a connected list/detail workspace, aligned product columns, quiet selection and summary figures, and a clear progression action. `PosWorkspace`, page/Admin headers, shared action controls, `PosTheme` and the existing warm Vynic palette are the common foundation. The bundled Georgian font is retained in explicit button and dropdown styles as well as inherited text.

| Surface family | Implemented and verified |
| --- | --- |
| Home and floor | Consistent navigation and touch controls; the right panel allocates its own space, defaults collapsed and has no duplicate Reservations destination. Actual Home fixtures cover expanded/collapsed 1024×768 and 1440×900 layouts. |
| Count | Connected list/detail, contact search, direct edit/reservation/preview/print/delete actions, larger quantity controls and anchored totals/footer. Original callbacks and Manager-only deletion remain. |
| Takeaways and reservations | Shared workspace and quiet summaries, aligned detail/actions, existing owner/Admin, hold/advance and cancellation protections. Long hold status wraps in its list row. Narrow layouts switch panes. |
| Menu and order | Shared search/input, variant, quantity, comment, amount and confirmation forms; readable cart rows, shared controls and quiet metrics. Existing transactional owners retain all calculations and mutation rules. |
| Login, lock and onboarding | Root typography, shared PIN/keypad controls, errors and modal vocabulary; authentication, back protection and activation remain unchanged. |
| Internal Admin | Shared headers and controls across Staff, menu, packages, inventory, reservations, reports, audit, settings, display, backup and developer/support sections. Compact render fixtures cover fourteen sections. |
| Payment and specialist views | Shared payment method, split, provider and confirmation shells; financial distinctions remain visible. Floor editor, close day, print-job/support and setup fixtures retain their specialized behavior. |

Visual inspection used synthetic records and actual production widgets, including normal/enlarged Georgian text and compact/wide layouts. The Order screenshot assembles production Order components in its existing test harness; it does not run terminal startup. Admin section screenshots reserve sidebar width without reproducing the sidebar; separate Admin navigation tests cover that shell. No dark theme or architecture replacement was added.

## Inventory and implementation

The pre-change inventory found 224 dialog/sheet/surface references in 45 POS files. This counts route calls and widget declarations, not 224 distinct user flows. The exact inventory is in [modal-inventory-before.json](proofs/POS_UI_REWORK/modal-inventory-before.json).

| Family | Result |
| --- | --- |
| POS modal routes | `showPosModal` supplies a scoped theme, typography, touch targets, barrier, reduced-motion behavior and keyboard viewport. All direct POS `showDialog`/`showGeneralDialog` calls now use that entry point; the reservation menu preview also uses the shared form shell instead of a separate bottom sheet. |
| Reservation create/confirm/edit | Admin, Home, Order and estimate confirmation use `ReservationCreationSheet.show` and one `PosFormDialog`. Relevant name, phone, guests, date/time, notes, hold and advance fields share validation and presentation. Existing edit-only restrictions and financial admission stay with their original owners. |
| Guest contact | Reservation, estimate and takeaway use `PosGuestFields`. Optional contact fields stay optional; the reservation phone exception remains supported. |
| PIN and time | Shared `PosPinForm` for Admin verification and Staff PIN forms; common compact keypad/shell and inline errors. Time input uses that visual vocabulary and fixes deletion across the colon. Login/lock submission and authentication rules remain unchanged. |
| Admin menu products | Category/subcategory add/edit use one `MenuItemForm`, preserving names, kitchen default, variants and 0.50 GEL price steps. Failed saves keep the draft and show an error. |
| Other forms | Menu comments, quantity/variant, receipt language, POS service fee, payment and amount forms share shells and controls. `PosAmountForm` preserves each caller’s parser, validation and save ownership. Manager service-fee rendering remains on its existing branch. |
| Specialized surfaces | Report, receipt, layout-editor, payment and SDK calendar content retains its task-specific layout and business behavior; POS route styling/dismissal policy is shared. |

Forms keep their title and actions fixed while their bodies scroll. Close/discard alerts center in the usable viewport independently of the underlying form. Escape first dismisses an open input dock; dirty reservations still require explicit discard. Invalid fields stay visible with inline errors.

## Count and Takeaways

| Task from the selected record | Before | After |
| --- | --- | --- |
| Count → reservation form | Manage → confirm: 2 taps | Reservation: 1 tap |
| Count → rename, preview, delete confirmation | Manage → action: 2 taps | Labeled toolbar action: 1 tap |
| Count → edit / print | 1 tap, small equal-weight buttons | 1 tap, 56px controls and distinct primary reservation action |
| Takeaway → menu editor | All details → edit: 2 navigation steps | Edit menu: 1 step |
| Takeaway → payment choice | 1 tap labeled “Close order” | 1 tap labeled “Payment” |
| Takeaway → cancellation confirmation | 1 tap labeled “Cancel” | 1 tap labeled “Cancel order”; destructive confirmation retained |

Count uses a connected browser/editor, larger quantity controls, a directly accessible service-rate control and no management modal. Takeaways places actions below the selected order instead of spending a third column on them. Payment and editing remain prominent; history/advanced operations and cancellation remain available. A dismiss button now says “Back” where “Cancel” was ambiguous. At narrow widths the list and selected record switch panes without stacking a second screen below the fold.

The direct takeaway editor calls the same extracted owner/Admin policy as the existing Order screen. Payment still uses the existing payment collection and durable closure path; cancellation still uses the existing Manager check and cancellation transaction. No new financial or cancellation semantics were introduced.

## Lag reproduction and input behavior

The reproducible input delay was an awaited 160ms `Scrollable.ensureVisible` before the keyboard route could build. With a deterministic 16ms widget-test clock, the first keyboard build took **192ms before** and **16ms after** for both Admin and estimate reservation fixtures. The fix opens the dock immediately and reveals only the obscured field after layout. POS dock slide and dialog-inset animations no longer compete with that reveal.

Controller-backed fields keep actual focus and a blinking caret, including mouse clicks on dock keys, numeric entry with leading zero, hardware input and Escape. The input scope no longer resizes the whole app. Only modal forms reserve dock space; existing fields scroll by the covered distance. Confirmation dialogs apply the inset once.

These measurements establish scheduling delay, not Windows GPU frame time or physical touchscreen latency. Route-settle durations include cursor timers and are not used as an opening-performance claim.

## Verification

- PASS: final targeted reservation/search/Admin/Home run, **26 tests**. It covers the hold-status overflow fix and current search labels while preserving contact/amount filtering and hold restrictions.
- PASS: production-scale Home/Menu/Order/Login group, **78 tests**; specialist/layout/setup group, **67 tests**; payment/checkout/workflow group, **29 tests**; shared input/Home/support group, **33 tests**; compact Admin/font group, **18 tests**. Groups overlap and are not added together.
- PASS: explicit amount validation/keyboard Enter/clear/cancel/Escape, reservation preview totals and repeated close, Menu comment delete/cancel semantics, reservation dirty-discard and duplicate-submit guards. Existing regressions cover back navigation, mouse focus, 150% Georgian text and 800×600–1920×1080 modal layouts.
- PASS: final `flutter analyze --no-pub`, no issues; final Home capture regression, **4 tests**; `git diff --check`.
- FAILED aggregate: **2700 passed, 17 skipped, 44 failed** with `--concurrency=2` and isolated Go fixtures. The 44 failure names match the independently reproduced pre-rework printer baseline exactly; **no additional failures** remain. [Machine-readable qualification](proofs/POS_UI_REWORK/final-qualification.json), [full log](proofs/POS_UI_REWORK/logs/final-full-aggregate.log).
- SKIPPED: aggregate cases requiring native/live fixture orchestrators, retained-data inputs or unavailable signing material; those inputs were not accessed.
- NOT RUN: native Windows build, Windows GPU/raster profiling and physical touchscreen exercise. No running restaurant terminal or live restaurant data was used.

The saved pre-rework source independently reproduces **44 printer failures**: 20 runtime-sync, 8 route-catalog, 14 print-delivery and 2 printer-configuration cases. Their exact names are recorded in [printer-baseline-comparison.json](proofs/POS_UI_REWORK/printer-baseline-comparison.json). Printer architecture and implementation were not changed by this UI rework. Earlier failures during the UI iteration are retained in logs and are not reported as passing runs.

## Screenshots and exact files

All screenshots use synthetic contacts/orders in temporary Hive directories or standalone review fixtures. Persistent Library IDs are recorded in [library-screenshots.json](proofs/POS_UI_REWORK/library-screenshots.json). The original before/after modal captures demonstrate the shared-form correction; the final captures show the approved design in production widgets.

| Surface | Before | Completed design |
| --- | --- | --- |
| Admin reservation | [Before](proofs/POS_UI_REWORK/screenshots/pos-admin-before.png) | [Shared form](proofs/POS_UI_REWORK/screenshots/pos-admin-after.png) |
| Estimate reservation | [Before](proofs/POS_UI_REWORK/screenshots/pos-estimate-before.png) | [Shared form](proofs/POS_UI_REWORK/screenshots/pos-estimate-after.png) |
| Time input | [Before](proofs/POS_UI_REWORK/screenshots/pos-time-before.png) | [After](proofs/POS_UI_REWORK/screenshots/pos-time-after.png) |
| Admin PIN | [Before](proofs/POS_UI_REWORK/screenshots/pos-pin-before.png) | [After](proofs/POS_UI_REWORK/screenshots/pos-pin-after.png) |
| Count | [Before](proofs/POS_UI_REWORK/screenshots/pos-count-before.png) | [Final Home](proofs/POS_UI_REWORK/screenshots/final-home-count.png) |
| Takeaways | [Before](proofs/POS_UI_REWORK/screenshots/pos-takeaway-before.png) | [Final Home](proofs/POS_UI_REWORK/screenshots/final-home-takeaway.png) |

Other final captures: [Reservations](proofs/POS_UI_REWORK/screenshots/final-home-reservations.png), [Menu](proofs/POS_UI_REWORK/screenshots/final-menu.png), [Order](proofs/POS_UI_REWORK/screenshots/final-order.png), [Staff](proofs/POS_UI_REWORK/screenshots/final-admin-staff.png), [Display](proofs/POS_UI_REWORK/screenshots/final-admin-display.png). The approved prototype and first-pass images remain as historical evidence, not substitutes for final screenshots.

The [changed-files manifest](proofs/POS_UI_REWORK/changed-files.txt) lists every Dart file touched by this UI task. The [deliverables manifest](proofs/POS_UI_REWORK/deliverables.txt) lists its documentation and evidence. Existing unrelated modifications and stashes were preserved. The subsequent user authorization covers committing and pushing all legitimate pending repository work after review; the [publication review](proofs/POS_UI_REWORK/publication-review.json) records cross-project checks and explicit local exclusions. The source diff check passes; the complete publication diff retains whitespace in raw proof logs/patches and historical Markdown, detailed in that review. No deployment, service restart, account change or live-data change was performed. Only requested synthetic screenshots were uploaded.
