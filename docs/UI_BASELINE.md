# Vynic UI Baseline — UI Phase 0

**Status:** baseline measurement only, no behavior changed · **Produced by:**
UI Phase 0 (`docs/UI_PLAN.md` §9) · **Depends on:** Phase 4 status-enum
foundation (done for the state-model half — see `docs/UI_PLAN.md` §3.1)

This document measures the current Windows POS UI as it exists today — tap
counts, dialog inventory, fixed-size/touch-target risk, resolution risk,
keyboard/focus gaps, and status-display gaps — so every later UI phase has a
"before" to verify against instead of a hunch. **Nothing in this document was
changed to produce it.** Every number below is grep/read-verified against the
current code, not estimated from memory.

---

## 1. Current key screens & affected files

| Screen | Primary file | Key supporting widgets |
|---|---|---|
| Login / Lock | `apps/windows_pos/widgets/login/login_desktop_view.dart` | `core/widgets/pin_button.dart` |
| Landing dashboard (current default, see §8 risk) | `apps/windows_pos/widgets/home/home_landing_dashboard.dart` | — |
| POS shell / navigation | `apps/windows_pos/screens/home_screen.dart` | `widgets/home/home_top_bar_section.dart` |
| Tables / Floor | `apps/windows_pos/widgets/home/home_tables_dashboard_section.dart` | `widgets/table_selection_widget.dart` |
| Menu / Order Entry | `apps/windows_pos/screens/menu_screen.dart` (2,800+ lines) | — |
| Order Detail | `apps/windows_pos/screens/order_detail_screen.dart` (2,900+ lines) | `widgets/order/order_detail_actions_panel.dart`, `widgets/order/order_detail_content_section.dart`, `widgets/order/order_detail_side_panels.dart`, `widgets/order/order_detail_header_section.dart` |
| Payment | `core/services/pos/table_payment_service.dart` | — |
| Reservations | `apps/windows_pos/widgets/home/home_reservations_section.dart` | `widgets/reservations_management_section.dart`, `widgets/home/home_reservation_table_assignment_dialog.dart` |
| Takeaway | `apps/windows_pos/widgets/home/home_take_away_section.dart` | — |
| Admin Center | `apps/windows_pos/screens/admin_screen.dart` (3,600+ lines) | 14 section files under `widgets/admin/` |
| X-Report | `apps/windows_pos/widgets/home/home_x_report_section.dart` | `widgets/home/home_x_report_helper.dart` |
| Calculator | `apps/windows_pos/widgets/home/home_calculator_page.dart` | `widgets/home/home_calculator_section.dart` |

---

## 2. Current waiter tap counts

Every count below is the **minimum number of taps** from the trigger action
to the outcome being committed, verified against the actual dialog/button
code — not typing keystrokes within a field, only discrete tap targets.

| Workflow | Taps | Path (verified) |
|---|---|---|
| **Open table** | **2** | Tap free table (`table_selection_widget.dart`) → tap "მენიუში გადასვლა" in the side-rail overview card (`home_tables_dashboard_section.dart:_buildSelectionOverview`) → Menu opens. |
| **Add normal item** | **3** | Tap item card (`menu_screen.dart:_onAddPressed`) → `_QuantityDialog` opens **showing "0", not a pre-filled 1** (see finding below) → tap digit "1" on the on-screen pin pad → tap "დამატება" (Add). |
| **Add variant item** | **4** | Tap item card → `_VariantSelectionDialog` opens, tap a variant → `_QuantityDialog` opens (same "0" issue) → tap "1" → tap "დამატება". |
| **Change quantity** (already in cart) | **1 per step** | Tap `+`/`-` in `_qtyStepper` (`menu_screen.dart`) — no dialog, this workflow is *not* part of the tap-count problem. |
| **Add note** | **2** + typing | Tap "+ კომენტარი" link → `_CommentDialog` opens with on-screen keyboard already visible → type → tap save. |
| **Apply discount** | **3** + typing | Tap "სხვა" (Other) in the fixed action row (`order_detail_actions_panel.dart`) → overflow dialog opens → tap "ფასდაკლება" tile → discount dialog opens (`order_detail_screen.dart:_showDiscountDialog`) → type amount → tap confirm. |
| **Complete cash payment** | **3** | Tap "მაგიდის დახურვა" (Close) → method dialog, tap "Cash" → confirmation dialog ("ნამდვილად გსურთ დახურვა — Cash?"), tap confirm. (`table_payment_service.dart:collect`) |
| **Complete card payment** | **4** | Tap Close → method dialog, tap "Bank" → **bank/terminal selection dialog** (TBC/BOG), tap terminal → confirmation dialog, tap confirm. One more step than cash because of the terminal-selection dialog. |
| **Print receipt** | **1** | Tap "ქვითრის ბეჭდვა" — a top-level button in the fixed action row, not behind any overflow. The one workflow in this list that's already efficient. |
| **Close table** | **1** to initiate | Tap "მაგიდის დახურვა" opens the payment flow above — full completion tap count is whichever payment method is chosen (see cash/card rows; listed separately here only as the initiating gesture, not double-counted). |

**Root-cause finding, not previously documented precisely:** `_QuantityDialog`
(`menu_screen.dart`, class starts ~line 2438) accepts a `defaultQty` parameter
(always passed as `1` at both call sites) but **never applies it** —
`initState` unconditionally sets `_quantityInput = ''`, the dialog displays
`'0'` until a digit is typed, and the confirm button
(`onPressed: qty > 0 ? ... : null`) is **disabled at zero**. This is why
"add normal item" costs 3 taps instead of the 2 you'd expect from a
pre-filled default — the parameter exists but does nothing. Worth confirming
whether this was ever intentional before UI Phase 4 removes the dialog
entirely.

---

## 3. Current dialog inventory (Windows POS)

`showDialog`/`showModalBottomSheet` call sites, counted per file:

| File | Count |
|---|---|
| `widgets/admin/admin_menu_section.dart` | 14 |
| `widgets/admin/admin_packages_section.dart` | 10 |
| `screens/order_detail_screen.dart` | 10 |
| `widgets/order/order_detail_content_section.dart` | 7 |
| `screens/menu_screen.dart` | 7 |
| `screens/admin_screen.dart` | 7 |
| `widgets/home/home_calculator_page.dart` | 6 |
| `widgets/admin/admin_staff_section.dart` | 6 |
| `widgets/admin/admin_close_day_section.dart` | 5 |
| `core/services/pos/table_payment_service.dart` | 4 |
| `widgets/admin/admin_reservations_section.dart` | 3 |
| `widgets/reservations_management_section.dart` | 2 |
| `widgets/reservation_creation_sheet.dart` | 2 |
| `widgets/home/home_take_away_section.dart` | 2 |
| `widgets/home/home_reservation_table_assignment_dialog.dart` | 2 |
| 10 further files | 1 each |

**Total: 93 dialog call sites in `apps/windows_pos/` alone**, plus 4 more in
the payment service and 1 in `core/widgets/service_fee_adjust_dialog.dart`.
Dialogs are the default interaction pattern in this app, not the exception —
this is the structural reason every workflow above chains 2–4 taps instead of
committing in one.

---

## 4. Fixed-size / touch-target risks

| File | Fixed `width:`/`height:` literals | Responsive constructs (`LayoutBuilder`/breakpoint) |
|---|---|---|
| `menu_screen.dart` | 75 | 1 breakpoint (`compactDesktop = maxWidth < 1100`, drives sidebar/cart panel width only) |
| `order_detail_screen.dart` | 66 | **0** — no `LayoutBuilder`, no breakpoint anywhere in this file |
| `admin_screen.dart` | 48 | 0 |
| `home_screen.dart` | 2 | 0 |

**Largest fixed widths found** (`order_detail_screen.dart`, `order_detail_content_section.dart`): 580px, 560px, 520px, 480px — all are **modal dialog containers**, not side-by-side layout panels, so they fit comfortably inside every target resolution below. Lower risk than the raw count suggests; flagging so nobody assumes an overflow crash that isn't there.

**Touch targets confirmed below the 44px floor** (already documented in
`docs/UI_PLAN.md` §1, re-verified here):
- Cart quantity stepper buttons: 28×30px (`menu_screen.dart:_stepButton`)
- Cart remove button: 30×30px (`menu_screen.dart:_cartIconButton`)
- "+ კომენტარი" / note affordance: a 12px text link, not a tappable icon
  button at all (`menu_screen.dart:_cartLink`)
- Table-tile secondary status text: 10–11px (`table_selection_widget.dart`)

**Accessibility-adjacent coverage, for context:** `Semantics(` appears in
only 2 of 55 `.dart` files under `apps/windows_pos/`
(`admin_screen.dart`, `home_top_bar_section.dart`); `Tooltip(` appears in 8
files. Neither is a substitute for real touch-target sizing, but both are
signals of how little explicit accessibility work exists today.

---

## 5. Screen/resolution risk

| Resolution / condition | Menu screen | Order Detail screen | Admin screen |
|---|---|---|---|
| 1366×768 | OK — falls just above the 1100px `compactDesktop` threshold; category sidebar 210px + cart panel 380px leaves ~776px for the item grid | No breakpoint at all; relies on `Expanded`/`double.infinity` so it won't overflow, but nothing shrinks deliberately for a smaller frame — text/padding stay full-size | 48 fixed sizes, no breakpoint found; not verified interactively this pass |
| 1280×800 | Same as above, still above 1100px threshold | Same as above | Same as above |
| 1920×1080 | Grid gains columns (`SliverGridDelegateWithFixedCrossAxisCount`, up to 5 columns) — scales up fine | Flexible panels get more room; no upper bound found, worth a manual check for panels growing awkwardly wide | Not verified interactively this pass |
| Windows 125–150% scaling | **Not verified this pass** — the 44px-floor touch targets already below spec at 100% scale (§4) will be smaller in *logical* pixels relative to a scaled cursor/finger, compounding the risk | Same concern | Same concern |
| Below 1100px window width (partial-screen POS window, docked taskbar, etc.) | `compactDesktop` mode engages — sidebar 172px, cart 340px | No equivalent compact mode | No equivalent compact mode |

**Manual verification still required** (this pass was static code analysis,
not a running-app measurement): actual rendering at 125%/150% Windows
scaling, and whether `order_detail_screen.dart`'s unbounded `Expanded` panels
look reasonable rather than merely non-crashing at 1280×800.

---

## 6. Keyboard / focus gaps

- `FocusNode`/`Focus(`/`Shortcuts(` usage exists in exactly **one** of the
  four main screen files: `home_screen.dart` (a single shortcut focus node
  for the whole shell, per its own doc comment — `_shortcutFocusNode`). Zero
  in `menu_screen.dart`, `order_detail_screen.dart`, `admin_screen.dart`.
- No custom focus-order or visible-focus-ring styling was found anywhere in
  `apps/windows_pos/` — keyboard navigation, where it works at all, relies
  entirely on Flutter's default traversal order, which is not guaranteed to
  match the visual layout in these custom-built dense grids/panels.
- Dialogs (93 call sites, §3) were not individually checked for focus-trap
  behavior in this pass — flagged as a manual-verification item, since
  `docs/UI_PLAN.md` §6.1's Baseline Bar requires dialogs to trap and return
  focus correctly, and nothing in the current code establishes that this
  happens today.

---

## 7. Status display gaps

Cross-referenced against `docs/UI_PLAN.md` §3.1 (updated this session):

- **Free/Occupied/Reserved** now have a real enum (`TableOperationalStatus`)
  but **`table_selection_widget.dart` doesn't consume it yet** — table-tile
  color is still computed from the raw `isReserved`/`activeOrderId` fields
  directly. This is the single highest-value, lowest-risk first consumer for
  whenever UI Phase 3 starts.
- **Reserved soon / Seated late / Dirty / Blocked** have no code
  representation at all — confirmed absent, not just unconsumed.
- **Order/Reservation lifecycle** (`OrderStatus`/`ReservationStatus`) exist
  and are wired into the write paths that matter (§9's earlier Phase-4
  report), but **no widget reads `.statusEnum` yet** — every status chip in
  every screen still branches on raw string comparisons
  (`admin_reservations_section.dart`, `reservations_management_section.dart`,
  `home_take_away_section.dart`, `order_detail_content_section.dart` all
  hand-roll their own `_buildStatusChip`, independently, per
  `docs/UI_PLAN.md` §6.4's design-system gap).
- **Printer failed / Kitchen failed** — confirmed zero observable status
  anywhere; `printer_service.dart` only reports success/failure via one-shot
  bool callbacks, nothing persisted or exposed to a widget.
- **Sync failed / Offline** — `BackendConnectionState` exists and is
  observable (`ConnectionStatusService`), and `pos_connection_status_indicator.dart`
  already renders it in the top bar. This is the one status category in this
  entire list that's actually in reasonable shape today.
- **Manager approval needed** — no status representation; `AdminVerificationDialog`
  is an interactive PIN flow, not something a screen can query the state of
  ahead of time.

---

## 8. Screens to screenshot manually before any UI work starts

Static analysis (this document) is not a substitute for seeing the running
app. Before UI Phase 2 touches anything, capture screenshots of the
following, at minimum at 1366×768, 1280×800, and 1920×1080:

1. Login screen
2. Landing dashboard (`home_landing_dashboard.dart`) — the screen UI Phase 3
   proposes retiring; capture it before it's gone
3. Tables/Floor, both floors, with at least one occupied and one reserved
   table visible
4. Menu/Order Entry — empty cart and a cart with 3+ items including one
   variant item
5. The quantity dialog specifically (showing the "0" state described in §2)
6. Order Detail — an order with a discount applied and the fixed action row
   visible
7. The full payment dialog chain — method dialog, bank/terminal dialog,
   confirmation dialog (3 separate screenshots)
8. Reservations queue and Takeaway queue, each with 2+ items in different
   statuses
9. Admin Center shell with the current flat 14-item sidebar
10. Mobile manager dashboard (for later comparison — out of Windows POS
    scope but referenced throughout `docs/UI_PLAN.md`)

None of this was captured as part of this pass — this document only lists
what to capture and why; actually driving the app was out of scope for a
static-analysis baseline.

---

## Related docs

- `docs/UI_PLAN.md` — the plan this baseline feeds; §3.1 and §9 (UI Phase 0)
  reference this document.
- `docs/VYNIC_PROJECT_PLAN.md` — master roadmap.
