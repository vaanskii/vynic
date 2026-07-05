# Vynic UI Plan

**Status:** planning only, not started · **Supersedes:** `docs/archive/plan.md` ·
**Sits inside:** `docs/VYNIC_PROJECT_PLAN.md` Phases 5–6 (UI/theme/responsive)

This is the detailed UI/design-system sub-plan for Vynic's Windows POS, mobile
manager app, and admin center. It was revised after reviewer feedback found the
first draft not implementation-ready: the phase order optimized the wrong step
first, accessibility was deferred to "final polish," payment work was one
oversized risky phase, design tokens were called zero-risk when app-wide
`ThemeData` wiring is not, several real POS workflows were missing from the
roadmap entirely, admin was planned as navigation only, operational states and
permissions were left undefined before visual decisions, and the plan leaned on
mockup files that no longer exist in the working tree. This revision fixes all
of that.

---

## 0. Gate — read this before doing anything else

**Do not start any UI Phase below (0–10) until
`docs/VYNIC_PROJECT_PLAN.md` Phase 4 (status enums) is complete.**

Checked against the master plan as of this writing: Phase 3 (data-driven
tables/zones) is marked **DONE**; Phase 4 (status enums) has **no DONE marker**
and is the next phase in sequence. The master plan's own §7 ("Do NOT do yet")
already states *"Do not start the UI redesign / responsive rework (Phases 5–6)
now"* — this entire document is that Phases 5–6 work, so the gate applies to
**all of it**, including UI Phase 0's measurement work, not only the phases
that touch code. Re-check `docs/VYNIC_PROJECT_PLAN.md` §6 before starting; if
Phase 4 is still open, stop here and work on Phase 4 instead.

Why this gate matters specifically for UI work: order/reservation status today
is stringly-typed (`'pending'`/`'confirmed'`/`'preparing'`/`'in-progress'`,
matched with `startsWith('confirmed')` in places). The **Operational State
Model** this UI plan requires (§3) is a UX-facing view of exactly those
statuses — building status chips, colors, and allowed-actions-per-state against
a stringly-typed backend means re-deriving state logic in the UI layer that
Phase 4 is about to replace with enums. Do the enum work first; the UI state
model in §3 should consume Phase 4's enums directly, not the raw strings.

**Phase 4 code status (as of this update):** the status-enum foundation
landed (`600475f feat(pos): add operational status enums`) — `OrderStatus`,
`ReservationStatus`, `TableOperationalStatus`, and a scaffold-only
`PrintOperationalStatus` now exist in code (see §3 for the mapping and §9 UI
Phase 1 for what's still outstanding). `docs/VYNIC_PROJECT_PLAN.md` §6 has
**not yet been marked DONE for Phase 4** — the status-enum work is in, but
the permissions-matrix half of what this plan's UI Phase 1 asks for
(new `StaffRole` checks) is not. Treat the gate below as satisfied for the
state-model dependency only; re-confirm the master plan's own Phase 4 line
before treating every downstream phase as fully unblocked.

---

## 1. Current UI Diagnosis

| Dimension | Finding | Evidence |
|---|---|---|
| **Workflow speed** | Adding one normal menu item costs 3 taps (tap→qty dialog→confirm) instead of 1. Variant items cost 4. Payment is 3–4 chained dialogs. Discount/adjustment/kitchen-print sit a further tap behind an "Other" overflow dialog. | `menu_screen.dart:1763` (`_onAddPressed`), `table_payment_service.dart:62-108`, `order_detail_actions_panel.dart:243-257` |
| **Visual consistency** | No shared token layer. 5+ independent accent systems (navy `#1E3A8A`/blue `#2563EB` in home shell, petrol `#075E6B` in tables, teal `#14B8A6` in admin/order-detail, gold `#C0AD7B` in totals, violet `#7C3AED` leaking in from mobile). 19 distinct font sizes, 15 distinct corner radii, 12 distinct animation durations (up to 700ms). | hex/fontSize/radius census across `apps/windows_pos/**/*.dart` |
| **Fixed layout / responsiveness** | Screens use hardcoded pixel dimensions instead of theme-driven/responsive values (`menu_screen.dart` alone: ~75 fixed sizes vs. 2 responsive references). | `prompts/05_UI_RESPONSIVE_THEME_AUDIT.md` |
| **Navigation** | Admin is 14 flat sidebar sections with no grouping. | `admin_screen.dart:1338-1396` |
| **Dialogs** | 80+ `showDialog` call sites in windows_pos alone; dialogs are the default interaction, not the exception. | grep count across `apps/windows_pos` |
| **Touch targets** | Cart qty steppers 28×30px, remove button 30×30px, "+ note" affordance is a 12px text link — below the ~44px floor a touch POS needs. | `menu_screen.dart:2004-2080`, `table_selection_widget.dart:518` |
| **Role-based landing** | Every role lands on the same decorative dashboard (`home_landing_dashboard.dart`) instead of Tables. | `home_landing_dashboard.dart` |
| **Payment flow** | Modal-chained: close→method dialog→(bank: terminal dialog)→confirmation dialog. No bill-split by item/guest — only tender-split cash/card. | `table_payment_service.dart:62-108` |
| **Admin organization** | Business logic/state/layout mixed in 40–134KB files; every visual change here is a behavior-change risk. | `admin_screen.dart` 134KB, `admin_menu_section.dart` 128KB, `admin_packages_section.dart` 109KB |
| **Mobile manager seriousness** | Violet gradients end-to-end (`#7C3AED→#8B5CF6`); shares zero tokens with the POS. | `manager_dashboard_theme.dart:148-191` |
| **Pre-l10n landmine** | Order actions looked up by matching hardcoded Georgian label strings (`_findByLabel(actions, 'მაგიდის დახურვა')`). ~2,870 inline Georgian strings exist. | `order_detail_actions_panel.dart:62-63` |
| **Role/permission model** | `StaffRole` (`core/models/staff_role.dart`) defines real roles (`manager`/`supervisor`/`waiter`, legacy `admin`→`manager`) and gates management-center access, reservation deletion, staff editing, and non-fiscal table close. It does **not** gate discount, void, refund, or X-report — any logged-in role can currently reach and use all of these. | `core/models/staff_role.dart`, confirmed absent in `menu_screen.dart`, `order_detail_screen.dart`, `home_x_report_section.dart` |

**Bottom line: this is a workflow-speed, state-definition, and permission
problem before it is a color problem.** Repainting screens without fixing tap
count, operational states, and role gating first would ship a prettier version
of the same slowdown — see §8, the explicit anti-repaint rule.

### Stale reference notice

The earlier draft of this plan referenced `design/mockups/managerdashboardmac.png`
and `design/mockups/takeaway.png` as visual direction. **Both files are deleted
in the current working tree** (`git status` shows them as `D`). They are not
design authority for this plan. Historical copies can be retrieved from git
history (`git show <commit>:design/mockups/<file>.png`) for reference, but any
new visual direction adopted in UI Phase 2 requires fresh, explicitly approved
mockups — do not resurrect the deleted ones and treat them as sign-off.

---

## 2. Target Vynic Design Direction

- **Base:** warm off-white / light neutral (`#F7F8FA`–`#FAFAFB`), never pure
  white as the only surface.
- **Text:** near-black charcoal (`#111827` primary, `#5B677A` muted) — no
  slate lighter than `#64748B` for anything read at a glance.
- **One primary accent:** deep teal/navy in the `#0F766E`–`#116A63` family —
  the only "press this" color across POS, admin, and mobile.
- **Status colors, fixed meaning everywhere:** success `#16A34A`, warning
  `#D97706`, danger `#DC2626`, info `#2563EB` — reserved exclusively for
  status (see §3 for the full state→token mapping), never reused as a second
  brand accent.
- **No purple/violet** anywhere in POS/admin/mobile.
- **Low animation:** 120ms (micro feedback) and 200ms (panel/sheet
  transitions) only. Nothing above 250ms in an operational flow.
- **High readability:** 5-step type scale, 12px operational floor, 14px+ for
  anything read standing up.
- **Large controls:** 44px minimum touch target on POS/waiter/cashier
  surfaces; 36px minimum on admin/mouse-only surfaces.
- **Two radii only:** 8px (controls) and 12px (cards/panels), plus pill for
  chips/switches.
- **Elevation, used sparingly:** one shadow token for floating panels/dialogs;
  flat 1px-bordered cards everywhere else. No glass, no blur, no gradients on
  operational surfaces.

---

## 3. Operational State Model

Define these before any color decision. Every state below must have a Phase-4
enum value (or explicit derivation from one) before UI Phase 2 assigns it a
token — do not invent UI-only state logic that duplicates or drifts from the
backend's status enum.

| State | Meaning | Where it appears | Token | Label (KA / EN) | Allowed actions | Severity |
|---|---|---|---|---|---|---|
| **Free** | Table has no active order or reservation | Tables floor plan | neutral surface, no badge | თავისუფალი / Free | Open order | None |
| **Occupied** | Table has an active open order | Tables, order list | info `#2563EB` | დაკავებული / Occupied | View order, add items, close | Normal |
| **Reserved** | Reservation linked, guest not yet arrived, outside arrival window | Tables, reservations queue | warning `#D97706` | დაჯავშნილი / Reserved | View reservation, seat guest, cancel | Normal |
| **Reserved soon** | Reservation arrival time within the next window (e.g. 30 min) | Tables (emphasized), reservations queue | warning `#D97706` + icon, no motion | მალე ჩამოდის / Arriving soon | Seat early, contact guest | Elevated |
| **Seated late** | Reservation time passed, guest not seated/marked | Tables, reservations queue | danger `#DC2626` | დაგვიანებული / Seated late | Mark no-show, contact guest, release table | High |
| **Dirty** | Table vacated but not yet reset for the next seating | Tables | distinct neutral/amber "needs-attention" token (not the same as warning-reserved, to avoid confusion) | დასალაგებელი / Needs cleaning | Mark clean | Normal |
| **Unpaid** | Order has a balance due | Order detail, tables | danger `#DC2626` | გადასახდელი / Unpaid | Take payment | High |
| **Printed** | Receipt/check already printed at least once | Order detail | info/neutral badge | დაბეჭდილია / Printed | Reprint | Low |
| **Sent to kitchen** | Items sent to kitchen printer | Order detail | info `#2563EB` | სამზარეულოშია / Sent to kitchen | Hold/fire (future, see §5) | Normal |
| **Kitchen failed** | Kitchen ticket failed to send/print | Order detail, alerts | danger `#DC2626` | სამზარეულოს შეცდომა / Kitchen ticket failed | Retry send, notify staff manually | High |
| **Sync failed** | Local change not yet confirmed by server | Top bar, order detail, admin | danger `#DC2626` | სინქრონიზაციის შეცდომა / Sync failed | Retry, view detail | High |
| **Printer failed** | Printer offline/unreachable | Top bar, order detail, admin | danger `#DC2626` | პრინტერის შეცდომა / Printer offline | Retry, switch printer, manual close (see §5 printer recovery) | High |
| **Manager approval needed** | Void/discount/refund pending manager sign-off | Order detail, admin alerts | warning `#D97706` (escalates to danger if blocking) | საჭიროა მენეჯერის დადასტურება / Needs manager approval | Approve (manager/supervisor via `AdminVerificationDialog`), deny | High |
| **Offline** | Device has no connection to server | Top bar | neutral/warning, not danger (local-first POS keeps working) | ოფლაინ რეჟიმი / Offline | Continue local operations, queue sync | Elevated |
| **Stale** | Data on screen may not reflect the latest state (mainly mobile manager cache) | Mobile manager, top bar | neutral | მოძველებული მონაცემები / Data may be outdated | Refresh | Low/Normal |
| **Blocked** | Table/order locked from action (concurrent edit, admin lock) | Tables, order detail | danger/neutral | დაბლოკილია / Blocked | View reason; unlock (admin only) | High |

**Design rule:** no two states may share the exact same token+no-label
combination — if a state is only distinguishable by color, colorblind staff
lose the signal (see the accessibility bar in §6.1). Every state above gets an
icon or text label, never color alone.

### 3.1 Code-backing status (post-Phase-4)

| State group | Backing today | Notes |
|---|---|---|
| Free / Occupied / Reserved | `TableOperationalStatus` (`core/models/table_operational_status.dart`), exposed as `TableModel.operationalStatus` | Computed, not stored — derives from existing `isReserved`/`activeOrderId`/`reservationId`. |
| Reserved soon / Seated late / Dirty / Blocked | **No code backing yet** | Need either a new stored flag (`Dirty`, `Blocked`) or a time-comparison helper against the linked reservation (`Reserved soon`/`Seated late`) — out of scope for the enum foundation, still future work. |
| Unpaid (and the order lifecycle generally) | `OrderStatus` (`core/models/order_status.dart`), exposed as `Order.statusEnum` | "Unpaid" = `!OrderStatus.isTerminal`; no separate enum needed for this state. |
| Printed / Sent to kitchen / Kitchen failed / Printer failed | **No code backing yet** — `PrintOperationalStatus` (`core/services/printing/print_operational_status.dart`) exists as an **unused scaffold enum only**; `printer_service.dart` has no observable status to wire it to | Wiring is a printer-service instrumentation task, not a status-enum task — remaining debt, see below. |
| Sync failed / Offline | `BackendConnectionState` (`core/services/sync/connection_status_service.dart`) — **pre-existing, not new** | No `SyncOperationalStatus` was added; this enum already covered the need. |
| Stale | Not modeled — would derive from `ConnectionStatusService.lastSyncedAt` age, not built yet | Future. |
| Manager approval needed | Not modeled as a status — `AdminVerificationDialog` exists as an interactive PIN step-up flow, not an observable state | This is a permission gate, not an operational status; belongs to §4/UI Phase 1's permissions-matrix half, not the state-enum half. |

Reservation lifecycle (pending/preparing/confirmed/in-progress/completed/
cancelled/no-show) is backed by `ReservationStatus`
(`core/models/reservation_status.dart`), exposed as `Reservation.statusEnum`.

**Two enums considered and deliberately not added:**
- **`PaymentMethod`** — `core/utils/payment_utils.dart` already normalizes
  payment method strings correctly, including genuinely open-ended values
  (`card-amex` collapsing to `card`, `other:voucher` carrying a custom label)
  that a closed enum would lose. Wrapping it in an enum would be a
  regression, not a fix.
- **`SyncOperationalStatus`** — `BackendConnectionState` already exists,
  wired, and observable (see table above). Adding a second enum for the same
  concept would recreate the exact fragmentation this plan exists to remove.

**Remaining status debt (not fixed by the Phase 4 enum work, flagged for
follow-up phases):**
1. `apps/windows_pos/widgets/table_selection_widget.dart` still computes
   table-tile color/state from the raw `isReserved`/`activeOrderId` fields
   directly, not from `TableModel.operationalStatus`. It's the natural next
   consumer of the new enum, but it's a widget file and was out of scope for
   the enum-foundation task — first real consumer for UI Phase 3.
2. Fuzzy `status.startsWith('confirmed')` / `startsWith('cancelled')`
   matching remains in `core/utils/home_reservations_helper.dart`,
   `apps/windows_pos/widgets/admin/admin_reservations_section.dart`, and
   `apps/windows_pos/widgets/reservations_management_section.dart`, instead
   of exact `ReservationStatus` comparisons. Left unmigrated because there's
   no way to confirm from source alone whether live restaurant data relies
   on a composite value that tolerance was written to catch.
3. Printer, sync-failure-as-distinct-from-offline, and manager-approval
   states have no observable instrumentation at all yet (see table above) —
   needs new plumbing in `printer_service.dart` and a discount/void approval
   flow before any UI phase can display them, not just a status enum.

---

## 4. Role & Permissions Model

### 4.1 Reconciling the UX roles with the code roles

This plan (and the reviewer feedback) frames UX priorities around four roles:
**waiter, cashier, manager, admin**. The codebase today
(`core/models/staff_role.dart`) has **three** roles: `manager`, `supervisor`,
`waiter` (legacy `admin` value auto-maps to `manager`). There is no separate
`cashier` or `admin`-distinct-from-`manager` account type.

Mapping used in this plan until/unless the team decides to add a role:

| UX role (this plan) | Maps to code role | Note |
|---|---|---|
| Waiter | `waiter` | As today |
| Cashier | `waiter` or `supervisor`, distinguished by **permission profile**, not a new account type | No schema change required — see 4.3 |
| Manager | `supervisor` | Existing `supervisor` already gets most manager-level access checks |
| Admin | `manager` | Existing `manager` already gets full access checks |

This is a UI-plan-level convention, not a data-model decision — introducing a
real `cashier` role (if ever needed) is out of scope for UI Phases 0–10 and
would be a separate backlog item against the user/role model, evaluated
independently of this plan.

### 4.2 What's already enforced (verified in code, not assumed)

`StaffRole` currently gates: management-center access (`manager`/`supervisor`),
reservation delete/cancel (`manager` only), non-fiscal table close (`manager`
only), full staff management (`manager` only), and PIN visibility rules
between `supervisor`/`waiter`. An existing `AdminVerificationDialog`
(`apps/windows_pos/widgets/admin_verification_dialog.dart`) already implements
a manager-PIN step-up flow — reuse it, don't build a second one.

**Since the UI Phase 1 permissions pass (below):** order-level cancel/void
was found to already be manager-only in the UI (`order_detail_action_helpers.dart`
only renders the cancel button for `PosPermission.voidOrder`, i.e. `isManager`)
— the note below that void had "zero role gating" was inaccurate; it was
mixing up order-level void (already gated) with the not-yet-built line-item
void. Discount and X-report were genuinely ungated and are now closed — see
below.

### 4.3 What is NOT enforced today (confirmed gap)

**Closed this pass:** discount / manual price adjustment (`order_detail_screen.dart`
— both actions share one risk class: they change what the customer owes) and
X-report (`home_screen.dart` sidebar + landing-dashboard tile) were reachable
by every role with **zero** gating. Both are now hidden for `waiter` via a new
central lookup, `core/models/pos_permission.dart` (`PosPermission` enum +
`PosPermissions.has(user, permission)`), which is a thin facade over new
`StaffRole.canApplyDiscount` / `StaffRole.canAccessXReport` methods — added
following the existing pattern in `staff_role.dart`, **not** a parallel
permission system. The facade also gave the existing manager-override bypass
in `_confirmCancelOrder` (previously three `widget.user.isAdmin` checks) a
named permission (`PosPermission.overrideManagerApproval`) with zero behavior
change, since `isAdmin` already meant `isManager`.

**Still open / scaffolded, not yet wired to a real screen:**
- `PosPermission.refundPayment`, `.deleteOrder`, `.editClosedOrder` — no such
  workflows exist in the app yet (§5); the enum values exist so the permission
  is ready the day those workflows are built, mirroring how
  `PrintOperationalStatus` was scaffolded ahead of its consumer in Phase 4.
- `PosPermission.manageMenu` / `.managePrinters` / `.viewSales` — already
  unreachable for `supervisor` because those sections are absent from the
  limited-admin sidebar in `admin_screen.dart`; the enum values document that
  fact but there is **no defense-in-depth check inside the section widgets
  themselves** (only nav-level gating). Flagged as remaining permission debt
  in case `AdminScreen` ever gains a second entry path.
- `PosPermission.closeDay` / `.manageStaff` / `.openAdmin` — facades over the
  existing `canAccessManagementCenter` gate; no behavior change.
- `PosPermission.closeTable` / `.reprintReceipt` / `.changeTable` — deliberately
  `true` for every role. These are everyday waiter operations (§4.4 marks them
  "Yes" for every role) and must stay open — do not gate these later without
  re-reading §4.4 first.

### 4.4 Target permissions matrix

"Hidden" = control does not render for that role. "Disabled" = control renders
but is inert/greyed with a reason. Prefer hidden for controls a role should
never need; disabled for controls that are conditionally available (e.g.
discount above a threshold).

| Control | Waiter | Cashier | Manager | Admin |
|---|---|---|---|---|
| Tables / order entry | Yes | Yes | Yes | Yes |
| Add/edit cart items | Yes | Yes | Yes | Yes |
| Apply discount (within limit) | Hidden | Yes | Yes | Yes |
| Apply discount (above limit) | Hidden | Disabled → requires manager PIN | Yes | Yes |
| Void line item | Hidden | Disabled → requires manager PIN | Yes | Yes |
| Refund (once implemented, §5) | Hidden | Hidden | Yes | Yes |
| Take payment / close table | Hidden (unless venue merges waiter+cashier) | Yes | Yes | Yes |
| Reprint receipt | Yes | Yes | Yes | Yes |
| Transfer table | Yes | Yes | Yes | Yes |
| X-Report | Hidden | Hidden | Yes | Yes |
| Admin / Management Center | Hidden | Hidden | Yes (scoped, §9 Phase 8) | Yes (full) |
| Settings | Hidden | Hidden | Limited | Yes |
| Sales / audit reports | Hidden | Hidden | Yes | Yes |
| Staff management | Hidden | Hidden | Limited (waiter targets only, per existing `canViewStaffPinInAdmin`/`canManageStaffUserInAdmin`) | Yes (full) |
| Printer/sync health (view) | Yes (read-only) | Yes (read-only) | Yes | Yes |
| Printer/sync config | Hidden | Hidden | Limited | Yes |
| Manager-override PIN approval | N/A (requester) | N/A (requester) | Yes (approver) | Yes (approver) |

This matrix is the acceptance target for UI Phase 1 and is re-verified at
every subsequent phase that touches a gated control (Phase 5 discount,
Phase 6 payment/void/refund, Phase 8 admin).

---

## 5. Missing POS Workflows & Product Gaps

Not implemented now. Placed correctly in the roadmap so nothing is designed in
a way that blocks them later. Status column reflects what actually exists in
code today (verified by grep, not assumed).

| Workflow | Current state | Scope tag | Lands in |
|---|---|---|---|
| Transfer table | **Exists** (`_showChangeTableDialog`, `order_detail_screen.dart`) | Current scope — visual/interaction polish only | Phase 5 |
| Reprint receipt | **Exists** | Current scope — polish only | Phase 5 |
| Merge checks (combine tables/orders into one bill) | Not found in codebase | Near-future | Flag in Phase 5/6 design, do not build |
| Split by seat/item/guest | Not found — only tender-split (cash/card amount) exists in `table_payment_service.dart` | Near-future — highest-priority gap | Phase 6 design must not preclude it |
| Hold/fire courses | Not found | Future | Note as out of scope in Phase 4/5 |
| Kitchen/bar routing | **Partial** — single kitchen printer + food/drink filter (`KitchenPrintFilter`); no multi-station routing | Near-future | Phase 5/8 |
| Void (order-level) | **Exists** (`paymentMethod: 'cancelled'` path) | Current scope | Phase 5 |
| Void (line-item, with reason code + approval) | Not found | Near-future | Phase 5 design leaves room; Phase 1 permission hooks required first |
| Comps | Not found as a concept distinct from discount | Future | Note in Phase 5 |
| Refunds | **Reporting field only** (`Monitoring.refunds`, mobile dashboard display) — no refund action exists anywhere | Near-future | Phase 6 (payment-adjacent) |
| Reopen closed receipt | Not found | Near-future | Phase 6 |
| Cash drawer | Not found | Future | Note in Phase 8 (admin) |
| Tips | Not found | Future | Note in Phase 6 |
| Shift close | **Partial** — X-Report (`home_x_report_section.dart`) is the closest equivalent; no formal cash-drawer shift-close | Current scope (X-report) / future (full shift close) | Phase 8 |
| Cash reconciliation | Not found beyond X-report totals | Future | Phase 8 |
| Staff permissions (discount/void/X-report/payment gating) | **Partial** — `StaffRole` infra exists, these specific checks don't | Near-future, required before Phase 5/6 ship | Phase 1 |
| Manager override PIN | **Partial** — `AdminVerificationDialog` exists as a mechanism, not yet wired to discount/void thresholds | Near-future | Phase 1 (hook), Phase 5/6 (wire in) |
| Printer offline recovery (operator-facing) | **Partial** — transport/service layer exists (`printer_transport.dart`, `printer_service.dart`); no confirmed day-to-day recovery surface for staff | Near-future | Phase 8 |
| Sync/offline conflict states (dedicated UX) | **Partial** — sync infrastructure exists (`SyncHub`, `MonitoringSocketService`); no dedicated conflict-resolution UI | Near-future | Phase 3 (surface state), Phase 8 (resolve) |
| Stock depletion / reorder visibility | Not found anywhere in models | Future — explicitly an inventory-path item, out of current product scope | Note only, no phase assigned |

Rule: any phase touching order actions, payment, or admin must leave visible
room (a slot in the action row, a section in admin nav) for the near-future
items above rather than hardcoding assumptions that make them harder to add
later (e.g. Phase 6's payment surface must be built so "split by item" can
become a real mode later without a rewrite — see Phase 6 acceptance criteria).

---

## 6. Design System Plan

### 6.1 Baseline Accessibility & Responsiveness Bar

This bar applies to **every UI phase from Phase 2 onward** (Phase 0 measures
against it, Phase 1 is documentation-only, Phase 10 audits it fully). Each
phase's acceptance criteria in §9 references this bar plus phase-specific
additions — it is not deferred to "final polish."

- **Resolutions:** 1366×768, 1280×800, 1920×1080, and 24–32" monitors (treat
  as a wide/high-density case, not just "bigger 1920").
- **Windows display scaling:** 125% and 150% — verify no clipping, no
  overlapping text, no controls falling below the touch-target floor once
  scaled.
- **Georgian text length:** every button/label/chip must be checked with real
  Georgian strings (typically 20–40% longer than English equivalents), not
  placeholder Latin text.
- **Keyboard focus:** every interactive control reachable via Tab/Shift+Tab in
  a logical order; focus state visibly distinct (not just a color shift —
  a visible outline/ring); dialogs trap focus and return it on close.
- **Color-blind status recognition:** every status in §3 distinguishable
  without color (icon, shape, or label) — verify with a deuteranopia/
  protanopia simulation pass, not just "looks fine to me."
- **Touch targets:** 44px minimum on POS/waiter/cashier surfaces, 36px
  minimum on admin/mouse-only surfaces (per §2).
- **Readable operational text:** 12px absolute floor, 14px+ for anything read
  standing up at table distance.

### 6.2 Tokens (additive first — see risk note)

```
surface/background   #F7F8FA
surface/card          #FFFFFF
surface/card-soft     #F9FAFB
border                #E5E7EB
text/primary          #111827
text/muted            #5B677A
text/disabled         #94A3B8   (disabled-only, never live info)
accent/primary        #0F766E
accent/primary-hover   +8% darken
status/success         #16A34A
status/warning         #D97706
status/danger          #DC2626
status/info            #2563EB
```

Typography: 11 / 13 / 15 / 18 / 24, weights 600/800 only. Spacing: 4/8/12/16/
24/32. Radius: 8/12/pill. Elevation: one shadow token for floating
panels/dialogs only; flat 1px-bordered cards otherwise. Motion: 120ms/200ms
only. Status chips: pill, 12px text minimum, 12%-opacity background + full
color text, **plus icon or label per §6.1's colorblind rule** — never color
alone, even for a "quick" chip.

### 6.3 Risk note: tokens are not zero-risk once wired

Adding token files (`vynic_colors.dart`, `vynic_spacing.dart`, etc.) and
primitive widgets (`VynicPanel`, `VynicStatusBadge`, `VynicActionButton`,
`VynicMetricTile`, `VynicEmptyState`) **unused** is genuinely low-risk — no
screen imports them yet, nothing can regress.

**Wiring `ThemeData` app-wide in `main.dart` is not the same action and is not
zero-risk** — it changes every screen's rendering simultaneously. This plan
does **not** wire `ThemeData` app-wide in Phase 2. Instead:

- Phase 2 adds the token layer and primitives, unused, and stops there.
- Each subsequent phase (3 onward) migrates **its own screens** off manually-
  passed colors (`_primaryColor`, `_textPrimary`, etc.) onto the token layer
  as part of that phase's own scoped work, with before/after screenshots
  captured for that phase's screens specifically.
- A single global `ThemeData` flip is only acceptable as its own explicitly
  scoped, separately reviewed step, after every screen has already been
  migrated to reference tokens individually — at that point flipping
  `ThemeData` is confirmation, not discovery, of what changes.

### 6.4 Primitives, dialogs → side sheets, tables, nav

Same content as the previous draft, unchanged in substance: reserve
`showDialog` for true interruptions (destructive confirmation, PIN entry);
route item variant+qty, discount entry, notes, and "other actions" to inline
panels or side sheets instead; data tables get a 44px row-height floor on any
row with a tap action; navigation is a persistent left rail (waiter/cashier,
6–7 items max) or grouped admin sections (§9 Phase 8) — never more than one
level of nested submenu.

---

## 7. Critical Workflow Redesigns

These are the target end-states each phase in §9 works toward. Listed once
here; §9 references them by letter instead of repeating full descriptions.

**A. Waiter opens table — target 1–2 taps.** Tap free table on Tables → Menu
opens directly with that table's context. (Phase 3.)

**B. Waiter adds normal item — target: tap = add ×1 instantly.** No dialog;
repeat taps increment; large quantities via a numpad on the qty number.
(Phase 4.)

**C. Waiter adds variant item — target: one panel, not stacked dialogs.**
Variant + qty stepper on one surface, one confirm. (Phase 4.)

**D. Waiter changes quantity — target: inline +/-, numpad for large values.**
(Phase 4.)

**E. Waiter adds note/modifier — target: fast inline or side sheet**, never a
full blocking dialog unless the note needs structured input (e.g. allergens).
(Phase 4.)

**F. Cashier applies discount — target: visible, not hidden behind "Other."**
Discount is a first-class, permission-gated action in the fixed row. (Phase 5.)

**G. Cashier completes payment — target: one payment surface**, not chained
dialogs; built so item/guest split can become a real mode later without a
rewrite. (Phase 6.)

**H. Manager checks daily state — target: revenue → open checks →
reservations → sync/printer health → alerts, in that order**, with no AI
banner above the actual operational numbers. (Phase 9.)

---

## 8. Do-Not-Repaint Rule

**No phase in this plan may ship a purely visual change to a screen whose
underlying workflow is known to be slow, unless that phase's explicit goal is
the workflow fix.** Concretely:

- Phase 2 does not restyle Tables, Menu, or Payment — it only adds unused
  tokens. Restyling those screens happens in Phases 3/4/6, bundled with the
  actual workflow fix, not before it.
- If a future task proposes "just apply the new colors" to Menu/Order Entry
  before Phase 4's tap-count fix ships, reject it — that's exactly the
  failure mode this plan exists to prevent (a prettier version of the same
  3-tap item add).
- Admin (Phase 8) is the one exception where navigation/shell restyle is
  allowed slightly ahead of deeper workflow fixes, because admin's core
  problem is organizational (§9 Phase 8), not tap-count — but even there, the
  section-body screens themselves stay untouched until their own workflow
  issues (if any) are scoped.

---

## 9. Implementation Phases

Every phase's acceptance criteria includes the Baseline Bar (§6.1) by
reference plus phase-specific additions — not repeated in full each time.

### UI Gate
See §0. Blocks everything below until master Phase 4 is done.

### UI Phase 0 — Baseline & safety
- **Status: static-analysis half done.** `docs/UI_BASELINE.md` now covers
  tap counts (workflows A–G, verified against actual dialog code), the full
  dialog inventory, fixed-size/touch-target risk, resolution risk, keyboard/
  focus gaps, and status-display gaps. **Not done yet:** the manual
  screenshot pass (`docs/UI_BASELINE.md` §8 lists exactly what to capture)
  and the 125–150% Windows-scaling verification, both of which require
  driving the running app rather than reading source.
- **Goal:** measure before touching anything.
- **Files touched:** none (screenshots/notes only, saved under
  `docs/archive/` or a new `docs/ui-baseline/`).
- **Allowed:** screenshotting current key screens (Login, Landing, Tables,
  Menu, Order Detail, Payment, Reservations, Takeaway, Admin shell, Mobile
  Dashboard) at each resolution in §6.1; tap-count measurement for workflows
  A–H (§7); a device/resolution matrix; a keyboard/focus audit; a full
  inventory of current `showDialog` call sites; a full inventory of current
  status representations (colors/labels/chips) across screens, cross-checked
  against §3.
- **Forbidden:** any code edit, any behavior change.
- **Acceptance criteria:** baseline doc exists covering all items above,
  reviewed and approved before Phase 1 starts.
- **Verification:** the doc itself is the artifact; confirm `git status
  --short` shows no source changes.
- **Rollback risk:** none.

### UI Phase 1 — Operational state model & permissions matrix
- **Status: done.** The state-model half landed with the Phase 4 status-enum
  foundation (`OrderStatus`, `ReservationStatus`, `TableOperationalStatus`,
  scaffold `PrintOperationalStatus` — see §3.1). The permissions half landed
  as a follow-up pass: `core/models/pos_permission.dart` (`PosPermission`
  enum + `PosPermissions.has(user, permission)`) plus two new `StaffRole`
  methods (`canApplyDiscount`, `canAccessXReport`) — see §4.3 for exactly
  what changed and what's still scaffolded.
- **What actually got wired into a real screen (a deliberate, narrow
  acceleration of two Phase 5/8 items, not a full Phase 5 discount/admin
  redesign):** discount + manual price adjustment hidden from `waiter` in
  `order_detail_screen.dart` / `order_detail_action_helpers.dart`; X-report
  hidden from `waiter` in `home_screen.dart` and `home_landing_dashboard.dart`;
  the existing manager-override bypass in `_confirmCancelOrder` renamed to a
  permission call with zero behavior change. No visual/styling changes, no
  token work, no other workflow changed — matches the narrow foundation scope
  this pass was authorized for.
- **Files touched:** `core/models/staff_role.dart`, `core/models/user.dart`,
  `core/models/pos_permission.dart` (new),
  `apps/windows_pos/widgets/order/helpers/order_detail_action_helpers.dart`,
  `apps/windows_pos/screens/order_detail_screen.dart`,
  `apps/windows_pos/screens/home_screen.dart`,
  `apps/windows_pos/widgets/home/home_landing_dashboard.dart`,
  `test/unit/pos_permission_test.dart` (new).
- **Acceptance criteria:** every row in §4.4's matrix has a corresponding
  `PosPermission` value or an explicit "existing method X already covers
  this" note (done — see §4.3). The two confirmed-ungated, high-risk gaps
  (discount, X-report) are closed; scaffolded/future permissions are
  documented, not silently skipped.
- **Verification:** `flutter analyze` (0 new issues), `flutter test` (99/99
  passing, 12 new in `pos_permission_test.dart`), `flutter build macos
  --debug` (succeeds).
- **Rollback risk:** low — every real-screen change is either an additive
  `if (permission)` guard around an existing button/dialog/destination, or a
  same-value rename (`isAdmin` → `overrideManagerApproval`). No screen lost
  functionality it needs; waiters keep every everyday operation (open table,
  add items, take payment, close table, reprint, change table).

### UI Phase 2 — Token layer & shared primitives (additive only)
- **Goal:** add the design system from §6.2/§6.4, completely unused.
- **Files touched:** `core/theme/*` (new: `vynic_colors.dart`,
  `vynic_spacing.dart`, `vynic_radii.dart`, `vynic_text_styles.dart`,
  `vynic_theme.dart`), `core/widgets/design/*` (new primitives).
- **Allowed:** pure additions.
- **Forbidden:** wiring `ThemeData` into `main.dart` (see §6.3 risk note);
  touching any existing screen file.
- **Acceptance criteria:** Baseline Bar (§6.1) verified against the token
  values themselves (contrast ratios for text/status tokens against
  `surface/background` and `surface/card`, specifically checked for
  colorblind distinguishability per §6.1) — plus: every primitive has a
  documented minimum touch-target size where applicable.
- **Verification:** `dart format`, `flutter analyze`,
  `flutter build macos --debug`; manual contrast check (WCAG AA) on every
  text/status token pair.
- **Rollback risk:** near zero — nothing consumes the new files yet.

### UI Phase 3 — POS shell & Tables first
- **Goal:** retire `home_landing_dashboard.dart` as a route; land
  waiters/cashiers on Tables; single-tap-to-menu on free tables; top bar
  carries session, printer/sync health (§3 states), business date, and role;
  migrate this shell's own screens onto Phase 2 tokens (per §6.3, scoped to
  these screens only).
- **Files touched:** `screens/home_screen.dart`,
  `widgets/home/home_top_bar_section.dart`,
  `widgets/home/home_tables_dashboard_section.dart`,
  `widgets/table_selection_widget.dart`,
  `widgets/home/home_landing_dashboard.dart` (deprecate/archive, don't
  delete).
- **Allowed:** navigation/default-route change; single-tap table→menu
  behavior change (explicit, scoped); shell restyle using Phase 2 tokens;
  surfacing Offline/Sync-failed/Printer-failed states (§3) in the top bar.
- **Forbidden:** touching order/payment logic; touching reservation
  assignment logic (`home_reservation_table_assignment_dialog.dart` — that's
  master-plan Phase 1 territory, not this plan's).
- **Acceptance criteria:** Baseline Bar (§6.1) full pass on Tables + shell at
  all listed resolutions/scaling — plus: session-lock/switch-user
  reset-to-landing behavior explicitly re-targets to Tables, not the old
  landing index; every table-status color in the floor plan matches §3's
  token mapping with a non-color-only signal.
- **Verification:** switch floor, select table (single + multi for merges),
  open every sidebar destination, open admin, test session-lock/switch-user,
  before/after screenshots for this phase's screens specifically (§6.3).
- **Rollback risk:** medium — most-trafficked navigation path in the app.

### UI Phase 4 — Menu/cart speed
- **Goal:** workflows B/C/D/E from §7. Tap = add ×1 instantly; variant items
  get one panel; cart controls resized to ≥44px; note becomes a fast
  inline/side-sheet interaction.
- **Files touched:** `screens/menu_screen.dart` (`_onAddPressed`,
  `_addToCartEntry`, `_QuantityDialog`, `_VariantSelectionDialog`, cart row
  builders).
- **Allowed:** entry-flow behavior change (explicit, scoped); visual resize
  of existing controls; token migration for this screen only.
- **Forbidden:** any payment change; any change to order totals math or
  service-fee calculation; any change to `_placeOrder` submission logic.
- **Acceptance criteria:** Baseline Bar full pass on Menu/Cart — plus: cart
  qty stepper and remove button measured ≥44px at 100% and 150% Windows
  scaling; note affordance is not a bare text link; Georgian item names at
  realistic length don't clip the qty/price columns.
- **Verification:** add single item, add variant item, add large-quantity
  item via numpad, remove item, edit note, place order; cart math identical
  to Phase-0 baseline for the same inputs; full shift test on Windows before
  wider rollout.
- **Rollback risk:** high — highest-traffic interaction in the product;
  stage behind a manual toggle if practical.

### UI Phase 5 — Order actions
- **Goal:** replace label-string action lookup with stable enum/action IDs;
  build the fixed, non-wrapping action row; make discount a visible,
  permission-gated first-class action (wiring Phase 1's
  `canApplyDiscount`/`canVoidItem` checks in); polish Transfer Table and
  Reprint Receipt (both already exist per §5) into the new row.
- **Files touched:** `widgets/order/order_detail_actions_panel.dart`,
  `screens/order_detail_screen.dart` (`_showDiscountDialog`, action wiring,
  `_showChangeTableDialog`).
- **Allowed:** action-lookup refactor to enums (behavior-preserving — output
  identical, only the lookup mechanism changes); UI restructuring of the
  action row; wiring Phase 1's permission checks into Discount/Void
  visibility per §4.4.
- **Forbidden:** any change to actual payment recording, printer/receipt
  logic, close-day finalization, discount calculation math.
- **Acceptance criteria:** Baseline Bar full pass on Order Detail's action
  row — plus: action row never wraps at any resolution in §6.1 (fixed slots,
  not `Wrap`); a waiter-role session cannot see the Discount/Void controls
  (§4.4); a cashier-role session sees Discount but it requires manager PIN
  above the configured limit.
- **Verification:** every action still fires correctly post-refactor for
  each role in §4.4; discount applies/limits correctly; transfer table and
  reprint still work; full regression since this is money-adjacent.
- **Rollback risk:** medium — action-lookup refactor touches every order
  action, but is designed to be behavior-preserving and independently
  testable from Phase 6's payment change.

### UI Phase 6 — Payment surface (isolated release)
- **Goal:** workflow G from §7. Collapse method→terminal→confirm into one
  payment surface; drop the redundant "are you sure — Cash?" dialog; leave
  visible room for split-by-item/guest (§5) as a future mode without
  requiring a rewrite; gate Void/Refund per §4.4.
- **Files touched:** `core/services/pos/table_payment_service.dart`,
  `screens/order_detail_screen.dart` (closure call sites).
- **Allowed:** UI restructuring of the payment surface only.
- **Forbidden:** any change to actual payment recording, printer/receipt
  logic, or close-day finalization semantics.
- **Acceptance criteria:** Baseline Bar full pass on the payment surface —
  plus: every state in §3 relevant to payment (Unpaid, Printer failed, Sync
  failed, Manager approval needed) is visibly represented on this one
  surface; the surface is released behind a feature toggle if practical,
  allowing instant fallback to the old flow.
- **Verification:** **transaction-by-transaction regression** — cash close,
  card close (both terminals), split-tender close, failed payment, cancelled
  order, print receipt, close table, sync/offline behavior during payment —
  each verified against Phase-0 baseline outcomes, on Windows, before this
  ships without the toggle.
- **Rollback risk:** highest in the plan — this is money flow. Ship this
  phase alone, never bundled with Phase 4 or 5.

### UI Phase 7 — Reservations & takeaway queues
- **Goal:** extract the shared queue-page scaffold (metric strip/list/detail/
  status-chip/empty-state) currently duplicated and drifting between
  Reservations and Takeaway; compress the metric row; make table-assignment
  time conflicts visible using §3's Reserved/Reserved-soon/Seated-late
  states.
- **Files touched:** `widgets/home/home_reservations_section.dart`,
  `widgets/home/home_take_away_section.dart`, new shared scaffold in
  `core/widgets/design/`.
- **Allowed:** extraction/consolidation; visual compression; surfacing §3
  states explicitly (not inventing new ad hoc status chips).
- **Forbidden:** touching reservation/takeaway data logic or table-assignment
  business rules — those belong to master-plan Phase 1's territory.
- **Acceptance criteria:** Baseline Bar full pass — plus: a reservation
  arriving within the "soon" window is visually distinguishable from a
  merely "reserved" one without relying on color alone; master-detail layout
  usable at 1280×800 without horizontal scroll.
- **Verification:** full reservation lifecycle (create/confirm/activate/
  cancel), full takeaway lifecycle, on Windows.
- **Rollback risk:** medium.

### UI Phase 8 — Admin operational redesign
- **Goal:** regroup the 14 flat sections into task-oriented clusters
  (**Operations, Catalog, People, Finance, System**) and make the admin
  landing surface **operational status**, not just navigation. On open,
  admin must surface: close-day readiness, printer health, sync health,
  staff permissions status, tax/service-charge configuration state,
  discount/void rule configuration, cash-drawer state (once it exists, §5),
  inventory/stock warnings (future, §5 — placeholder only), audit
  exceptions, and any active business alert — each using §3's severity
  scale, most-severe first.
- **Files touched:** `screens/admin_screen.dart` (nav/shell + a new landing
  summary panel) — section-body files
  (`admin_menu_section.dart`, `admin_packages_section.dart`, etc.) stay
  untouched this phase.
- **Allowed:** nav restructuring; shell restyle; new landing summary panel;
  settings search box.
- **Forbidden:** touching any individual section's internal logic.
- **Acceptance criteria:** Baseline Bar full pass on the admin shell — plus:
  every item in the operational-status list above is either shown or
  explicitly marked "not yet available" (no silent omission); a
  `supervisor`-role session sees the scoped subset per §4.4, not the full
  `manager` view.
- **Verification:** every admin tab still reachable; printer save/test;
  close-day flow on test data; report generation; role-scoped visibility
  tested for both `manager` and `supervisor`.
- **Rollback risk:** medium — purely navigational/summary, but admin holds
  business-critical settings; test every entry point.

### UI Phase 9 — Mobile manager restyle
- **Goal:** workflow H from §7. Merge mobile theme into shared Vynic tokens;
  remove the violet/gradient system; rebuild the dashboard priority order
  (revenue → open checks → reservations → sync/printer health → alerts); any
  AI-insight card is demoted below the fold, never the masthead; extract
  controller/state from `dashboard_screen.dart` before restyling it.
- **Files touched:** `apps/mobile_app/theme/*`,
  `apps/mobile_app/presentation/screens/dashboard_screen.dart`,
  `presentation/screens/admin_screen/`.
- **Allowed:** extraction, restyle, dashboard information-priority reorder.
- **Forbidden:** touching live-socket/notification wiring behavior.
- **Acceptance criteria:** Baseline Bar full pass (mobile-appropriate
  resolutions substituted for the desktop matrix) — plus: revenue/open-checks/
  reservations/health/alerts appear in that literal order above the fold; no
  AI card above the revenue number.
- **Verification:** login, all tabs, notifications, live table/order view,
  light/dark, real device if available.
- **Rollback risk:** medium — mixed controller/state file; extract as its
  own commit before any visual change.

### UI Phase 10 — Final hardening
- **Goal:** the full Baseline Bar (§6.1) swept across every screen touched
  in Phases 2–9, plus keyboard shortcuts, performance-perception pass
  (skeletons/optimistic updates only where they demonstrably help — no
  decorative loading states), full regression, and a manual restaurant
  smoke test.
- **Files touched:** sweep across `apps/windows_pos/**`,
  `apps/mobile_app/**` — one screen per commit.
- **Allowed:** layout/responsiveness/accessibility/performance-perception
  fixes only.
- **Forbidden:** new features, business logic changes.
- **Acceptance criteria:** every screen individually passes the full
  Baseline Bar; every workflow A–H (§7) re-measured against Phase-0 tap
  counts and shows the intended reduction; a full manual smoke test on a
  real or simulated shift (open table → order → kitchen send → payment →
  close, plus one reservation and one takeaway cycle) completes without a
  workaround.
- **Verification:** resize-testing at all resolutions/scaling in §6.1,
  contrast checker, full keyboard-nav pass, Georgian text fit-check, full
  regression suite, manual smoke test signed off before calling Phases 5–6
  of the master plan complete.
- **Rollback risk:** low-medium per commit, but this is a long tail — budget
  it as such, don't compress it.

**Note on localization (master-plan Phase 5b):** do the l10n move (2,870
inline Georgian strings → ARB) after UI Phase 5 (enum-keyed actions removes
the string-matching landmine) and before UI Phase 10, so responsive/
accessibility work in Phase 10 only touches each screen once, post-l10n.

---

## 10. First Implementation Recommendation

**Once the Gate (§0) clears: UI Phase 0, then UI Phase 1, then UI Phase 2,
then UI Phase 3 — in that exact order. Do not skip to Phase 4 first.**

This reverses the previous draft's recommendation (which suggested starting
with tokens then jumping straight to menu/cart speed) per the reviewer's
core finding: **waiters reach the menu through the shell and table
selection**, so the first live UX fix must remove the landing-screen and
table-entry drag (Phase 3) before optimizing item-add speed (Phase 4) —
otherwise you've made the fast path faster while the slow path to reach it is
unchanged. Phases 0–2 are prerequisites (measurement, state/permission
definitions, unused tokens) with effectively no user-facing risk; Phase 3 is
the first phase that changes what a waiter actually experiences, and it's
lower-risk than Phase 4 (no cart-state math, no money adjacency) while still
being Critical-priority.

Do not bundle Phases 1+2+3 into one commit. Each is independently
reviewable, independently rollback-able, and Phase 3 depends on Phase 1's
state/permission definitions being settled first (the top bar in Phase 3
surfaces §3 states — Offline, Sync failed, Printer failed — that Phase 1 must
have already mapped to real enum values).

---

## Related docs

- `docs/VYNIC_PROJECT_PLAN.md` — master roadmap; this doc is its Phase 5–6
  detail; **check its Phase 4 status before starting anything here (§0).**
- `docs/UI_BASELINE.md` — UI Phase 0's measurement output (tap counts,
  dialog inventory, fixed-size/resolution/keyboard/status-display risk).
- `docs/archive/plan.md` — superseded first draft this document replaces.
- `AGENTS.md` — root rules for all agents.
- `design/mockups/` — **stale**: referenced files are deleted from the
  working tree; see the notice in §1. Do not treat as design authority.
