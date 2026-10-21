# Manager UI implementation and rendered evidence

Generated captures, logs and machine receipts referenced below are local-only; see the [proof output policy](../README.md).

Implementation of the approved Manager direction, following the isolated design
proposal in `experiments/manager-design-preview/`. The proposal remains separate
as historical design evidence. These screenshots render the actual Manager
widgets with synthetic records; they are not image-generation artwork or a
claim of physical-device testing.

## Scope

Manager now has a shared light/dark visual system, Noto Sans Georgian typography,
solid surfaces, restrained purple actions, bounded desktop content, and one
responsive navigation shell. At 1100 logical pixels the sidebar shows names;
700–1099 uses a compact rail with tooltips; below 700 the bottom navigation keeps
Dashboard, Tables, Reservations and Financials visible, with Inventory and
Management in More. Count and saved menus have explicit entries. Cmd+1…6 selects
the existing destination order; Cmd+K opens calculation.

Changes are confined to Manager presentation, its entry-point theme, and Manager
tests. Existing API clients, tenant/session authority, entitlements, durable
operations, financial calculations and POS ownership remain the implementation
boundaries. No backend, contract, migration or shared printer architecture is
changed by this work. Existing and concurrent POS changes in the checkout are
not part of this Manager delta. No commit, push, deployment or device installation
was performed.

| Surface | Implementation and retained flow |
| --- | --- |
| Access | One-use venue linking, remembered venue/PIN, offline authentication feedback, restaurant switch and logout. Hardware PIN entry/backspace and the on-screen keypad. Production endpoint controls remain hidden. There is no self-service PIN reset or profile-onboarding capability to add. |
| Dashboard | Current shift total, closed/open amounts and payment distinctions, seven-day history, occupancy, active business day, reservations, saved menus, staff/products, Inventory and planning links. Decorative forecast/sample actions were removed. |
| Tables / orders | Existing zone, occupancy and takeaway filters; physical table identity; guarded repair and order actions. Wide windows show the actual order detail beside the table grid; narrower windows retain route navigation. Order editing, receipt preview, cancellation and pending results remain on their existing services. |
| Reservations | Existing date/status/search and detail actions; adjacent New Reservation and Guest Without Reservation actions call the existing flows. Guest/preorder form uses bounded content and a primary footer above the keyboard. Existing availability/table selection and cancellation/printing remain. |
| Calculation / saved menus | Category, subcategory, variant, quantity and service fee controls; desktop summary; centered cart editor; saved draft creation, editing, reservation confirmation, print/PDF and deletion. A submission guard prevents duplicate save taps. |
| Financials | Existing exact revenue/outflow distinctions, provider/advance breakdowns, warnings, expenses, sale history/detail, Payroll and Obligations links. Shared form/dialog styling applies to planning, history and corrections without changing accounting behavior. |
| Inventory | Daily receiving, stock, payments/payables, supplier/catalog and composition destinations; the existing receiving, recipes, archive/restore, movements/consumption and supplier history flows inherit the shared Material theme. Existing workflows and navigation are regression-tested. |
| Management | Reports, Sales, Audit, Activity, Team and Settings remain reachable. Team forms, date/filter controls, venue profile, session and light/dark appearance share the theme. |
| State / notifications | Freshness and source details, cached/unavailable reads, retained POS requests and their recovery actions are preserved. Notification history and its existing deep links remain. |

Two inventory corrections to the initial proposal: the real Financials overview
does not have a period selector (Reports/planning provide their own period/month
controls), and appearance offers light/dark, not a system-following mode. The
implementation does not invent either capability. Takeaway creation retains its
actual customer/pickup/menu fields.

## Render and interaction verification

`test/widget/manager_redesign_render_test.dart` imports the production widgets.
Its HTTP override permits only the test-owned loopback port, and Hive uses a
temporary directory. All screenshots visibly identify synthetic test data.
Financial/planning fixtures are injected through existing test seams. The
render harness composes the actual adaptive navigation and screens; it does not
start the full production socket/push session.

- Light: 390×844 phone, 834×1112 tablet, 780×900 narrow desktop and 1440×1000
  wide desktop. Dark: phone and wide desktop. Additional 320×900 at 130% text
  scale catches narrow Georgian wrapping. PNGs are rendered at 2× resolution.
- Actual Dashboard, Tables, Reservations, Financials, Inventory, Management,
  Calculation, Saved Menus, Login, Payroll, Obligations, Takeaway creation and
  Notifications render without framework exceptions. Management tabs are
  traversed; team/settings and desktop order inspection are captured.
- Count journey on phone and desktop: select a product and a 750 ml variant,
  quantity two each, verify 128.00 subtotal/service fee payload, save once, edit
  the same draft, open reservation confirmation with its name, queue the existing
  print request, and delete. A queued request is not claimed as printed output.
- Both reservation entry actions are tested on phone and desktop. Guest/phone
  form input and a 300-pixel keyboard inset leave the primary action visible.
  Walk-in uses the existing menu selector and table picker; Escape returns
  without a business write.
- Count, saved-menu and More navigation are exercised at three widths, including
  Cmd+K. Production-mode login checks rendered link/PIN states, hidden endpoint
  controls, hardware digits/backspace and masked semantics at three widths.
- Stale cached reads, unavailable history and queued POS work are rendered with
  the actual state components and synthetic journal data. Empty states appear in
  notification, receiving and history fixtures.

Visual review corrected Georgian wrapping, scaled filters, phone dashboard
density, the PIN backspace glyph, centered cart sizing, keyboard-safe form
footer and restrained occupied-table color. Rendering verifies layout and widget
behavior. All 46 named foreground-token/principal-surface pairs meet 4.5:1
(minimum 4.84:1; see `validation/theme-contrast.json`); this excludes inherited
custom colors and disabled controls. It does not establish VoiceOver quality, native window chrome, a real
iOS keyboard, authenticated network operation or physical printer behavior.

## Regression evidence

Logs retained in `validation/` record:

- Manager analyzer: no issues.
- 202 existing widget regressions passed: activation/login, entitlements,
  financial ledger, planning/correction history, guarded order editing, stock,
  receiving, recipes, consumption, catalog cost, inventory navigation, daily UX,
  procurement and final inventory journeys.
- 16 new layout/navigation/count/reservation/state tests and 3 production-login
  tests passed (221 distinct tests across the regression and new suites). The
  seven surface matrix cases were rerun after the final Georgian button-font fix
  and passed again. Results are in the corresponding logs.
- 32 freshness widget/unit tests passed after the aggregate exposed nine old-copy
  assertions in `mgr04_data_status_test.dart`. Assertions now verify the redesigned
  refresh-failure/limited labels and explicitly reject a fresh-data claim for stale
  or failed reads. Source age, cache scoping, session fencing, unavailable-versus-zero
  and lifecycle refresh checks remain; a complete/current POS case was added.

The final whole-project aggregate was rerun after the freshness assertion fix:
**2,744 passed, 17 skipped, 44 failed**. Every remaining failure exactly matches
the prior printer baseline; all nine Manager failures from the concurrent POS
run are resolved, with no additional failures. This is **not** a green whole-suite
result. The 44 printer failures remain outside the Manager UI task. Exact names,
comparison and command: `validation/aggregate-comparison.json`; complete output:
`validation/manager-final-aggregate.log`. Focused counts overlap the aggregate
and must not be added to it.

Example reproduction from `apps/operations/`:

```sh
MANAGER_RENDER_DIR=/tmp/manager-renders flutter test --no-pub test/widget/manager_redesign_render_test.dart
MANAGER_RENDER_DIR=/tmp/manager-renders flutter test --no-pub --dart-define=VYNIC_ENV=production --dart-define=VYNIC_API_URL=https://manager-ui-fixture.invalid test/widget/manager_login_preview_test.dart
flutter analyze --no-pub lib/apps/mobile_app lib/main_manager.dart test/widget/manager_redesign_render_test.dart test/widget/manager_login_preview_test.dart test/fixtures/manager_redesign_fixture.dart
```

## Native qualification

Native build evidence uses the product helper's isolated Manager checkout at
`/tmp/vynic-manager-redesign-20261017`. The helper's relative generated-contract
dependency was resolved to the existing repository package only in that copy;
no generated source or repository dependency was changed. Final Manager source
was copied into the isolated checkout after visual fixes.

The macOS debug app builds successfully at
`build/macos/Build/Products/Debug/Vynic Manager.app`. An ARM64 iOS Simulator debug build also succeeds at
`build/ios/Debug-iphonesimulator/Runner.app`, using command-line
`ARCHS=arm64 ONLY_ACTIVE_ARCH=YES IPHONEOS_DEPLOYMENT_TARGET=15.0
CODE_SIGNING_ALLOWED=NO`. The default Flutter simulator command failed in
`debug_unpack_ios` because it treated the combined architecture string as one
architecture; installed Xcode then rejected the existing iOS 13 pod target. These
build-only overrides apply to the temporary checkout. Repository deployment
targets are unchanged; the default simulator build remains a toolchain follow-up.
Logs are retained in `validation/`.
No signing, installation or release qualification is implied by a debug build.
Native interactive inspection remains unverified: the earlier computer-use
inspection timed out. Physical iOS/Android, Windows Manager and printer
qualification remain separate.

## Existing printer touchpoints (deferred architecture)

| UI entry | Existing hook retained |
| --- | --- |
| Order detail → check | `MobileApiService.printOrderCheck`; delivery-aware status and repeated-tap guard |
| Order receipt preview | `PrinterService.generateReceiptPngBytes` and the existing receipt preview |
| Saved count → check / PDF | `MobileApiService.printCountedMenu`; existing `_printPdf` receipt generation and per-draft busy state |
| Reservation detail → check | `MobileApiService.printReservationCheck`; existing loading/result handling |
| Management sale/order receipt | `MobileAdminScreen.viewCheckPdf` and existing receipt rendering |

The Manager continues to request POS delivery through its existing API. Printer
selection, routing, transport, discovery, retry policy and backend/POS ownership
were not redesigned here.

## Deliverables

`index.html` is a local review gallery of 27 selected images; `renders/` contains
the PNG evidence. All 27 uploads were independently read back as native Library
files; `library-readback.json` retains their confirmed identities and sizes. `library-attachments.json` and
`render-manifest.json` record the selected retained Library attachments, confirmed
IDs, dimensions and content hashes for viewing from iOS. Only the selected review
set is uploaded; all render outputs remain local. The design-only prototype and
its original Library IDs remain in `experiments/manager-design-preview/`.
