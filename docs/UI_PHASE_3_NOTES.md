# UI Phase 3 Notes — POS Shell & Tables First

Companion to `docs/UI_PLAN.md` §9 UI Phase 3. This is the first phase that
changes what a waiter actually sees when they log in — everything before it
(Phase 4 status enums, UI Phase 0 baseline, UI Phase 1 permissions, UI Phase 2
tokens) was invisible foundation work.

Scope: Windows POS shell + Tables only (`--dart-define=APP_ROLE=pos`). The
manager app (no `APP_ROLE` define) is untouched — this phase never imports or
modifies anything under `apps/mobile_app/`.

---

## What changed

### 1. Tables is the landing screen, not a dashboard

Previously: logging in showed `HomeLandingDashboard` — a decorative metrics
screen with tap-through tiles for Tables/Calculator/Takeaway/Reservations/
X-Report/Admin. Reaching the floor plan took an extra tap through that
dashboard.

Now: the `menu` (Tables) destination is index 0 and the landing tab. The
dashboard route is gone from `home_screen.dart`'s navigation entirely.
`HomeLandingDashboard` was initially left in place, unreferenced, as a
deprecation placeholder — it has since been **deleted outright**: the top bar
fix below (see "Navigation regression fix") gives every role a direct path to
Reservations/Takeaway/X-report/Admin, so the dashboard's only real job
(reachability) is fully covered, and the file predates the Vynic tokens
(hardcoded colors, decorative layout) so reviving it later would mean
rebuilding it anyway. A future manager daily-state summary (UI_PLAN §7-H,
deferred to Phase 9) should be designed fresh against current tokens, not
resurrected from this file — it's recoverable from git history if ever
needed for reference.

Session-lock/staff-switch reset-to-landing now targets Tables (previously
targeted the now-gone `home` destination key).

### Navigation regression fix (post-launch)

Making Tables the landing screen initially broke reachability: the top bar's
quick-switch row only ever listed `menu`/`calculate`/`todaysTakeaways` —
Reservations, X-report, and the Management Center had no way back in once
the dashboard tiles were gone (they were only reachable by chance, via a
reservation notification tap). Fixed in `home_screen.dart` /
`home_feature_header.dart`: the quick-switch row is now derived from the
same `_destinations` list that already drives permission gating (so it can't
drift out of sync again) — every section the current role can reach is an
inline tab, all in the same row.

(An intermediate version of this fix put the less-frequent, supervisor/
manager-only sections — X-report, Management Center — behind a "More" popup
menu instead of showing them inline, to guard against overflow. That was
removed in the next iteration below: it added an extra click for no real
benefit once the header had room, so all sections are inline tabs again with
no hidden menu.)

**Header simplified further (post-launch):** the standalone home icon button
was removed — the "Tables" nav tab already gets you there, one tap, so a
dedicated home button was a second way to do the same thing. The icon +
screen-title + username block that sat next to it was also removed — the
highlighted nav tab already shows which screen is active, so that block was
duplicating information for no benefit.

**Header simplified again (post-launch):** three more iterations landed
together:
- Nav tabs (now including every role-gated section — see above) are
  left-packed at their natural width via `Flexible` instead of `Expanded`,
  so the bar doesn't stretch to fill the full width — it hugs its content
  and leaves empty space on the right, rather than spreading tabs out edge
  to edge. It still gracefully ellipsizes per-tab if a role has enough
  sections to genuinely run out of room.
- The role badge (icon + role name, e.g. "მენეჯერი") no longer collapses to
  icon-only at narrow widths — it always shows the full label; only its
  padding tightens when narrow.
- The sync/connection status indicator (cloud icon showing
  online/offline/syncing) was removed from the header — it was the only
  consumer of `PosConnectionStatusIndicator`, which is now dead code
  (`widgets/home/pos_connection_status_indicator.dart`, unreferenced
  anywhere). Left in place for now rather than deleted outright, in case
  sync visibility needs to resurface elsewhere (e.g. a settings/status
  screen) — flagged as debt below.

**Header rearranged once more (post-launch):** the role badge moved to the
very left of the bar (right before the Tables tab, no longer grouped with
date/clock/notification on the right), and the username it briefly carried
("role · username") was dropped from it. Business date, clock, and the
notification bell stay on the far right, unchanged. The username itself
moved out of the header entirely — it now shows in the Tables screen's side
rail (`home_tables_dashboard_section.dart`'s `_buildControlRail`), below the
four table-info metric cards. That rail is usually taller than four cards
need, so a `Spacer` pushes the username down into that leftover space
instead of taking room from anywhere the header or floor plan need it. This
only applies to the side-rail layout — the compact/stacked layout at
narrower widths doesn't show metrics or username at all, deliberately, so as
not to re-eat the vertical budget recovered for the floor plan there (see the
1024×768 fix below, which changes exactly which widths count as "narrower").

**Header refined again (post-launch):**
- Nav tabs now use `Expanded` (not `Flexible`) so the slot deterministically
  reserves *all* remaining free space — tabs render left-aligned within it
  (a real visible gap after the last tab), and the date/clock/notification
  cluster is guaranteed to land at the true right edge of the bar, not just
  wherever the tabs happen to end.
- At narrow widths, inactive nav tabs collapse to icon-only — only the
  active tab keeps its text label (still available as a tooltip on the
  others). Saves horizontal room without losing the "which screen am I on"
  signal, since the active tab is the one that matters.
- Business date and clock are now stacked vertically (date over time) in a
  single narrower column, instead of side-by-side — the 72px bar has
  vertical room to spare, and this trades some of that for less horizontal
  width.
- **No longer hides at narrow widths (post-launch fix).** It used to
  disappear below 1000px alongside the (now-removed) role badge. Once the
  role badge moved out of the header, there was consistently enough room
  for it, so it stopped making sense to hide — the nav tabs' own per-tab
  ellipsis (and icon-only collapse for inactive tabs) is the actual pressure
  valve now, not an all-or-nothing block that vanishes.

**Role badge relocated to the Tables side rail (post-launch, confirmed after
flagging the trade-off):** the role badge and its lock/staff-switch control
are gone from the header entirely (`_RoleBadge` deleted from
`home_feature_header.dart`, along with `HomeFeatureHeader`'s `roleLabel`/
`onStaffSwitchTap` params). They now live in a new `_StaffCard` at the
bottom of the Tables side rail (`home_tables_dashboard_section.dart`), right
below the username that was already there.

**Staff card restyled (post-launch, after a second design pass):** the
first version used a gradient tint, circular avatar, and elevated shadow to
read as a distinct "person" card. That was replaced with a flat style that
matches the plain metric cards above it exactly — `VynicColors.card`
background, `VynicColors.border` border, no shadow, a rounded-square icon
box (not a circle) — so it reads as one more item in the same list, not a
separate visual treatment.

**Admin panel entry point added (post-launch):** a flat button
("მართვის ცენტრი", manager/supervisor only — `onOpenAdminPanel` is null for
waiters, same rule as `canAccessManagementCenter` everywhere else) now sits
just above the staff card, in the same bottom-of-rail cluster, opening
`AdminScreen` directly via the same `_openAdminPanel()` the header's old
admin tab used.

**Trade-off now in effect:** locking/switching staff is only reachable from
the Tables screen, and only at ≥1000px width (the side-rail threshold) —
it's no longer available from Calculator, Takeaway, Reservations, X-report,
Admin, or from Tables itself below 1000px. Idle auto-lock (`SessionLock.arm()`
in `home_screen.dart`) is unaffected and still fires everywhere regardless —
only the *manual* "lock now" action moved. Worth knowing if a manual lock
is ever needed urgently from one of those other screens.

### 1024×768 root cause: wrong layout picked, not a cramped one

Earlier notes above described the 1024×768 issue as height-cramping inside
the stacked layout and shrank the heading/selection-overview to compensate.
Revisiting it after a report that the screen looked broken at that
resolution ("no info left, tables at the bottom") found the actual root
cause: **1024×768 was never using the side-rail (info-left, floor-right)
layout to begin with.** The side-rail/stacked switch used the shared
`VynicBreakpoints.compactMax` (1100px) — a general-purpose threshold tuned
for other screens, not this one. Below it, Tables falls back to a *stacked*
layout (info-top, floor-bottom), which is what 1024px (< 1100) was getting —
correctly stacked per that threshold, but not what this screen actually
needs at that width.

The side rail is a fixed 292px regardless of window width, and skips an
entire extra header (`_buildPlanPanel(showHeader: false)`) that the stacked
layout adds on top of the floor plan. Worked through concretely: at
1024×768, side-rail mode gives the floor plan roughly 648px of height;
stacked mode gives it roughly 400px — the side rail is strictly better
whenever it fits, and at 1024px width it fits with over 700px still left
over for the floor plan after the rail and its gap. There was no reason for
1024×768 to be using the worse layout.

Fixed in `home_tables_dashboard_section.dart`: the side-rail/stacked switch
is now a screen-local `constraints.maxWidth >= 1000` check instead of
reusing the shared 1100px breakpoint, so 1024×768 (and anything else in the
1000–1099px band) gets the side-rail layout. The compact/idle-collapse
changes made to the stacked layout in the earlier note still apply — they
now only kick in below 1000px instead of below 1100px.

**That fix didn't actually take effect at 1024×768 (post-launch, second
pass)** — a report that 1024×768 still had no side-rail after the fix above
led to finding a second bug stacked on the first: the check compared against
`constraints.maxWidth`, but this widget sits inside `home_screen.dart`'s
16px-each-side content padding (32px total), so at a nominal 1024px-wide
window, `constraints.maxWidth` here was actually **992**, not 1024 — still
under the 1000 threshold, so it silently kept falling back to stacked mode
despite the fix's intent. Fixed by comparing against
`MediaQuery.sizeOf(context).width` (the window's true logical width)
instead, which doesn't depend on knowing exactly how much ancestor padding
sits between the window edge and this widget. The `LayoutBuilder` this
lived in was removed too — nothing else in the widget used `constraints`.

**Small-resolution overflow safety net added:** the stacked layout's chrome
(heading + floor-control card + selection-overview) is now wrapped in a
`SingleChildScrollView`, so if a window is ever short enough that even the
already-shrunk chrome doesn't fit, it scrolls instead of throwing a
`RenderFlex` overflow error. The floor plan stays outside that scroll view
(it needs bounded height for its own scale-to-fit math, per the primitive-
design finding above) and still gets whatever height remains via its
`Expanded`, however little that is at extreme sizes.

### 2. Opening a free table: 2 taps → 1 tap

Previously: tap a free table (selects it) → tap "მენიუში გადასვლა" in the
side rail (navigates). Two actions, matching the UI Phase 0 baseline finding.

Now: a single tap on a free table, when nothing else is selected, selects it
**and** immediately navigates to the menu — one action.

**Multi-table selection (merging several free tables into one order) moved
to long-press**, so it doesn't fight with the fast single-tap path:
- Long-press a free table → adds/removes it from a multi-select set without
  navigating.
- Once a multi-select is in progress (via long-press, or because more than
  one table needs picking), further short taps on *other* free tables also
  add to the set instead of resetting it — so an accidental habitual tap
  can't silently discard progress mid-selection.
- The rail's "გაგრძელება/მენიუში გადასვლა" button still finalizes a
  multi-table selection, unchanged.

**Bug fix (post-launch):** tapping a table that was already part of a
multi-table selection of 2+ (e.g. select 1, 2, 3 via long-press, then tap 3
again to drop it) incorrectly fell through to the fast single-tap path and
navigated to the menu with only that table, silently discarding 1 and 2. The
tap handler only recognized "toggle off" when exactly one table was selected.
Fixed in `table_selection_widget.dart`'s `_handleTableTap` — toggling off now
works for any selection size, removing just the tapped table and keeping the
rest.

Reserved and occupied tables are **completely unaffected** — their
tap-to-focus, rail-button-to-open flow is exactly as before, per the task's
explicit "do not break reserved/occupied table behavior" constraint.

### 3. Occupied vs. Reserved are now visually distinct (a real, pre-existing bug fix)

Before this phase, `table_selection_widget.dart` checked `TableModel.isReserved`
for tile styling — but `isReserved` is `true` for **both** "guest seated, order
running" (occupied) and "booked for later, guest not here yet" (reserved).
Every busy table showed the same red fill, the same lock icon, and the same
"დაკავებულია" label, regardless of which case it actually was.

Now every table tile derives its icon + label from `TableModel.operationalStatus`
via a new shared helper, `table_status_presentation.dart`:

| Status | Icon | Label | Tone |
|---|---|---|---|
| Occupied (active order) | receipt/check icon | "დაკავებულია" | info (blue) |
| Reserved (booked, not seated) | calendar icon | "დაჯავშნილია" | warning (amber) |
| Free | (no badge, unchanged) | — | neutral |

This matches docs/UI_PLAN.md §3's rule that status is never color alone. The
per-reservation/order **unique group color** (so a waiter can see "these 3
tables are one party") is unchanged — it's an orthogonal identity signal, not
a status severity signal, so it was deliberately left alone rather than
folded into the 5-tone Vynic status system.

This fix applies identically across all three table-tile render modes (SVG
floor-plan map, custom-paint floor plan, and the plain button grid) — they
all now read from the same `TableStatusPresentation` helper instead of each
having their own copy of the same (buggy) logic.

### 4. Floor metrics are now accurate

The tables dashboard's metric cards ("სულ მაგიდები / თავისუფალი /
დაკავებული") previously computed "დაკავებული" (occupied) from the same
overloaded `isReserved` boolean — meaning it actually counted
occupied+reserved together, mislabeled as "occupied." Now there are four
accurate metrics: Total, Free, Occupied, Reserved — each from
`TableModel.operationalStatus`.

The selection-overview card (the panel that shows details about a
tapped/focused table) also got its title corrected: it used to say "დაკავებული
მაგიდა" (busy table) for both cases; it now says "დაკავებული მაგიდა" only for
a truly occupied table and "დაჯავშნილი მაგიდა" for a reserved one, plus a
small `VynicStatusChip` showing the same tone/icon/label.

### 5. Top bar: business date added

`HomeFeatureHeader` (the real top bar — `home_top_bar_section.dart` turned
out to be dead code referenced nowhere and was left alone) already showed
session (username), role (badge with icon), and sync status
(`PosConnectionStatusIndicator`, already wired to `BackendConnectionState`
from Phase 4). It was missing the **business date** — now shown next to the
clock (hidden together with the clock on narrow/1024px layouts, same
collapse rule as before). Printer status is still not surfaced, because
(per Phase 4's status debt) there is no observable printer status to show —
`PrintOperationalStatus` remains an unused scaffold enum.

### 6. Responsive: centralized breakpoint, corrected counts

The tables dashboard's side-rail-vs-stacked layout switch used a local,
ad-hoc `constraints.maxWidth >= 920` check. It now uses
`VynicBreakpoints.modeForWidth` (compact below 1100 logical px) — the same
breakpoint every future screen will use, instead of a screen-specific magic
number. This shifts the switch point from 920px to 1100px: on screens
between 920–1099px wide, the layout now stacks instead of showing the side
rail (a deliberate consistency improvement, not a bug).

**1024×768 fix (post-launch):** the stacked layout itself was found to be
genuinely cramped at 1024×768 — the page heading, floor-switch card, and
selection-overview card together ate roughly 300+px of the 768px of height
before the floor plan even started, squeezing the canvas down to a visually
tiny, hard-to-use render (not a `RenderFlex` overflow — just an unusably
small floor plan). Fixed in `home_tables_dashboard_section.dart`:
- The stacked branch now passes `compact: true` to `_buildPageHeading()`
  (was already done for the side-rail's `_buildControlRail`, just missed
  here) — drops the subtitle line and shrinks the icon.
- `_buildSelectionOverview()` gained a `compact` mode: when idle (no table
  selected) it collapses from the full card (~155px: icon row, status line,
  disabled button) to a single-line hint (~40px). The full card still
  appears once a table is actually selected — only the idle placeholder was
  wasteful.
- Net effect: roughly 130px more height returned to the floor plan canvas
  in the idle state at 1024×768, the worst case since that's what a fresh
  login lands on.

### 7. Visual tokens

Card/panel surfaces in `home_tables_dashboard_section.dart` and the free-tile
fills in `table_selection_widget.dart`'s button-grid and floor-plan render
modes now reference `VynicColors`/`VynicShadows` instead of local hex
literals (`Colors.white` → `VynicColors.card`, `#DDE4ED` → `VynicColors.border`,
etc. — visually identical or near-identical values, not a repaint). The
shell's top-level background changed from a decorative blue-tinted gradient
to a flat `VynicColors.background`, consistent with the "calm, operational,
not decorative" target direction.

---

## Screens migrated

- `screens/home_screen.dart` (shell chrome, navigation/default-route only —
  not the sub-screens it hosts for calculator/takeaway/reservations/x-report/
  admin, which are unchanged).
- `widgets/home/home_feature_header.dart` (top bar — added business date).
- `widgets/home/home_tables_dashboard_section.dart` (Tables screen wrapper).
- `widgets/table_selection_widget.dart` (table tiles — all 3 render modes;
  also fixed the multi-select tap-toggle bug above).
- `widgets/home/home_landing_dashboard.dart` — **deleted**. Retired as a
  route first, then removed outright once the top-bar nav fix made it fully
  redundant; see "Navigation regression fix" above.

Not touched, as instructed: menu screen, order detail screen, payment flow,
reservations screen, takeaway screen, admin screen, the mobile manager app,
`main.dart`/global `ThemeData`.

## A primitive-design finding worth recording

`VynicTwoPaneLayout` (from UI Phase 2) was evaluated for the Tables screen's
side-rail/floor-plan split but **not used** — its compact-mode fallback
either hides one pane or stacks both inside a `SingleChildScrollView`, and
the floor-plan canvas needs a *bounded* height in every mode (its internal
`LayoutBuilder`-driven scale-to-fit math breaks under unbounded height). The
existing hand-built `Row`/`Column` branching in
`home_tables_dashboard_section.dart` already handled this correctly, so it
was kept, only swapping its breakpoint for `VynicBreakpoints`. If a future
phase hits the same need (a canvas-like primary pane that must always have
bounded height, even when stacked), consider adding a
`stackModeExpandsPrimary` option to `VynicTwoPaneLayout` rather than
re-solving this per-screen.

## Known remaining issues / debt

- Manual on-device screenshot verification (see checklist below) has not
  been performed — only `flutter analyze`/`flutter test`/a debug build were
  run. Actual pixel-level behavior at 125%/150% Windows scaling is unverified.
- Printer status still has no signal to surface in the top bar (pre-existing
  debt from Phase 4, not created by this phase).
- The reservation-group unique color system (hash-based, one color per
  party) and the 5-tone Vynic status system now coexist by design (see point
  3 above) — a future design pass could consider whether they should be
  visually reconciled (e.g. a colored ring for the group + a solid tone fill
  for status) rather than the group color fully replacing the status tone
  the way it does today.
- `home_top_bar_section.dart` (373 lines) is dead code — not referenced from
  anywhere in the app. Left alone this phase (out of scope: "no broad
  refactors"/"no unrelated formatting"), but worth a follow-up cleanup task.
- `pos_connection_status_indicator.dart` (173 lines) is now also dead code —
  its only call site (the header) was removed. Same treatment as above: left
  in place rather than deleted, flagged for a follow-up cleanup pass.

### Post-launch round: rail overflow, admin nav removal, floor plan stretch

- **Control rail vertical overflow at 1024×768 (real bug, not the earlier
  1024×768 layout-choice bug — that one picked the right layout; this one
  overflowed within it).** `_buildControlRail` pushed the staff card to the
  bottom of the rail with `Expanded(child: Column(... Spacer() ...))` around
  the four metric cards + admin button + staff card. At 1024×768 that fixed
  content (four 72px metric cards + admin button + staff card) needed more
  height than the rail had left after the heading/floor-card/selection
  overview above it — `Spacer` can't shrink below zero, so the metrics
  column overflowed by 121px (`RenderFlex overflowed by 121 pixels`).
  Fixed by restructuring the rail so only the top section (heading, floor
  card, selection overview, metrics) sits inside an `Expanded` +
  `SingleChildScrollView`, with the admin button and staff card as fixed
  siblings below it (not inside the flexible/scrollable region). This keeps
  the same "staff card pinned to the bottom" visual result at normal
  heights, and scrolls the metrics list instead of overflowing when the rail
  is too short to fit everything.
- **Admin panel removed from the top-bar navigation.** Now that the Tables
  side rail has its own "მართვის ცენტრი" button (manager/supervisor only,
  opens Admin directly), the `adminPanel` nav-tab destination was redundant
  — tapping it never actually showed a page anyway (`_handleQuickSwitch` had
  a special case that intercepted the tap and opened `AdminScreen` directly,
  bypassing the `HomeAdminToolsSection` placeholder page entirely). Removed
  the `adminPanel` entry from `_createDestinations()`, deleted the now
  provably-unreachable `HomeAdminToolsSection` widget outright (its only
  call site), and simplified `_handleQuickSwitch` away (it was reduced to a
  pure pass-through to `_selectDestination`, so the call site now calls
  `_selectDestination` directly).
- **Floor plan now stretches to fill its panel instead of letterboxing.**
  The floor plan canvas is portrait/near-square (1005×1101 or 953×958)
  while the panel it renders into is landscape at every real POS
  resolution. Both render paths (`_buildSvgFloorPlan` for `svgMap` zones,
  `_buildFloorPlan` for `floorPlan` zones) computed `scale = min(scaleX,
  scaleY)` to preserve aspect ratio, which always left empty margins on the
  sides — reported as "tables not using full width." Confirmed with the
  user this should stretch non-uniformly rather than widen the canvas data
  or leave it letterboxed. Changed both paths to apply `scaleX`/`scaleY`
  independently (no more single `scale`): the SVG path's `FittedBox`s
  switched from `BoxFit.contain` to `BoxFit.fill`; the object-based path
  threads `scaleX`/`scaleY` through `_buildFloorPlanObject`,
  `_buildFloorPlanTable`, `_buildConnectedReservationBands`, and
  `floorPlanWallJoints` (shared with the admin layout editor, which still
  passes the same value for both — the editor keeps true-to-scale editing).
  Wall-joint math scales each endpoint's x/y components independently,
  which is exact for axis-aligned walls (the normal case) and only an
  approximation for genuinely diagonal ones.

### Post-launch round: stretch reverted, table-content overflow, no-tap-to-continue, shared staff/admin rail

- **Floor plan stretch reverted.** The non-uniform stretch above was tried
  and reported back as a regression: it made the POS floor plan look
  visibly different from the same layout shown true-to-scale in the admin
  layout editor (walls/tables mildly skewed on one screen, exact on the
  other), which was more confusing in practice than the empty side margins
  it was meant to fix. Both `_buildFloorPlan` and `_buildSvgFloorPlan` are
  back to a single uniform `scale = min(scaleX, scaleY)` (aspect-ratio
  preserved, matching the admin editor exactly again). The `scaleX`/`scaleY`
  parameter split on the internal helpers and `floorPlanWallJoints` was kept
  (both call sites just pass the same value for both now) since reverting
  the signatures too added no value and only risked re-introducing bugs.
- **Real, separate overflow bug: individual table content, not the rail.**
  At small scale factors (e.g. 1024×768, where the floor plan canvas scales
  down to fit) `_buildFloorPlanTable`'s icon+label(+status line) `Column`
  had no shrink behavior — a table box scaled below ~65-70px tall
  overflowed internally (`RenderFlex overflowed`), independent of and
  pre-dating this session's rail-overflow fix. Fixed by wrapping that
  `Column` in `FittedBox(fit: BoxFit.scaleDown)` — shrinks the icon+text
  proportionally when the box is tight, never enlarges past natural size
  when there's room.
- **Reserved/occupied tables now open immediately — no "continue" tap.**
  `TableSelectionWidgetState._handleTableTap`'s reserved-table branch used
  to only focus the table (or its whole reservation/order group) and wait
  for a manual tap on the rail's "გაგრძელება" button. It now calls
  `widget.onTableTap(tableModel)` directly on the same tap, matching the
  fast single-tap path free tables already had. Two (or more) tables
  reserved together for one party were already grouped by
  reservation/order key for the focus highlight — since they share the
  same `reservationId`/`activeOrderId`, opening any one of them already
  opened the shared order for the whole group via
  `_handleReservedTableTap`/`DatabaseService.activateReservation`, so no
  separate "open both" logic was needed once the tap itself auto-opens.
  `_buildSelectionOverview`'s busy-table branch in the Tables rail is now a
  brief, non-interactive "<table numbers> • იხსნება..." row with a spinner
  (no button — there's nothing left to press) shown only for the moment
  the async activation/order-lookup takes.
- **Tables side rail narrowed 292px → 260px**, now that the busy-selection
  card no longer needs room for order/reservation detail rows and a CTA
  button.
- **Admin panel button + staff/manager card: tried on every Home tab, then
  reverted back to Tables-only.** Briefly moved to a shared global rail in
  `home_screen.dart`'s shell (visible on every tab), per an earlier request;
  reported back as unwanted, so it's back to living only inside
  `HomeTablesDashboardSection`'s own rail, exactly as before that change.
  `_StaffCard`/`_AdminPanelButton` stayed extracted into the shared
  `HomeStaffAdminRail` widget (`home_staff_admin_rail.dart`) rather than
  being pasted back inline — `HomeTablesDashboardSection`'s rail now just
  calls `HomeStaffAdminRail(...)` directly as its footer, so the visuals are
  unchanged from before the global-rail experiment, only the file
  organization differs. `HomeTablesDashboardSection` has its
  `username`/`roleLabel`/`onStaffSwitchTap`/`onOpenAdminPanel` params back,
  and `home_screen.dart`'s shell is back to a plain
  `Expanded(child: IndexedStack(...))` with no extra rail alongside it.

### Post-launch round: idle hint removed, vertical floor switch, nav labels always visible

- **Idle "აირჩიეთ მაგიდა" hint removed from the rail entirely.**
  `_buildSelectionOverview` used to show a card (or, in compact mode, a
  slim one-line hint) telling the user to pick a free table when nothing
  was selected. Now it returns `SizedBox.shrink()` in that state — the
  floor plan itself is the affordance, no separate rail card is needed.
  The card still appears for an active free-table selection ("არჩეული
  მაგიდები" + continue button) and the brief busy-table "opening..."
  row; only the truly idle state was removed. The now-unused `compact`
  parameter was removed from `_buildSelectionOverview` along with it.
- **Floor switch in the rail is now vertical, not horizontal.**
  `_FloorSwitch` gained a `vertical` param — when set, its buttons stack
  top-to-bottom (full width each) instead of side-by-side. Used only in
  `_buildFloorControlCard` (the rail's floor card); the compact toolbar
  version in the floor plan panel's own header (`_buildFloorPanelHeader`)
  stays horizontal. Rail width dropped 260px → 220px accordingly, since
  the floor switch no longer needs room for two buttons side by side —
  giving the floor plan panel next to it more width.
- **Nav tab labels are now always visible, at every resolution.** The
  earlier "inactive tabs collapse to icon-only under 1000px" behavior was
  removed — every tab always shows its icon **and** label, matching how
  it already looked on bigger resolutions. `_DirectNavigationItem` lost
  its `showLabel` param entirely; the header's `LayoutBuilder` (previously
  only used to compute this) was removed along with it. Each tab's own
  `Flexible`+ellipsis is still the space-pressure valve if labels don't
  all fit.

## Manual screenshot checklist (for the user to run)

Log in as a **waiter** (discount/X-report should be hidden — Phase 1) and as
a **manager** (should see everything), and capture:

1. Login → landing (should show Tables directly, no dashboard in between).
2. Tables at 1366×768, 100% scaling — side rail + floor plan both visible,
   no overflow.
3. Tables at 1280×720 — same, smallest supported width.
4. Tables at 1024×768 — now uses the **side rail** layout (info-left,
   floor-right), same as wider resolutions, not the stacked fallback; rail
   and floor plan both fully visible, no overflow.
4b. Tables at ~900×768 (below the 1000px side-rail threshold) — stacked
   (single-pane) layout; idle state shows a slim one-line "select a table"
   hint (not the full card) and the floor plan gets the rest of the height
   at a usable scale; select a table and confirm the full overview card
   returns; no overflow.
5. Tables at 1920×1080 — side rail + floor plan, panel not overly wide.
6. Windows 125% and 150% scaling at 1366×768 and 1920×1080 — no clipped
   text, no overlapping controls, touch targets still usable.
7. Tap a free table → confirm it jumps straight to the menu (1 tap).
8. Long-press two free tables → confirm both get selected without
   navigating, then tap "გაგრძელება" to confirm the merge still works.
9. Tap a reserved table → confirm the quick-overview + rail "გაგრძელება"
   flow is unchanged.
10. Compare an occupied table vs. a reserved table side by side — confirm
    different icon + different label ("დაკავებულია" vs "დაჯავშნილია").
11. Top bar at full width — confirm there is **no** role badge in the
    header anymore; nav tabs sit left-packed at the left with a visible gap
    before the next cluster, business date/time show as two stacked lines
    (not side by side), and that stacked block + notification sit flush
    against the far right edge.
12. Top bar at ~1000px width and narrower (e.g. ~900px) — confirm business
    date/time stay **visible** (no longer hide) and every INACTIVE nav tab
    collapses to icon-only while the ACTIVE tab keeps showing its label.
13. Tables at 1024×768 specifically (log in fresh, don't just resize from
    wider) — confirm the side rail shows on the left with the floor plan on
    the right, same as 1280×720/1366×768, not the stacked fallback.
14. Tables side rail (shown down to 1000px width) — confirm, from the
    bottom of the rail upward: the flat staff card (icon box, username,
    role label — matching the metric cards' style, no gradient/shadow/
    avatar-circle) with a lock button that opens the same PIN/staff-switch
    flow as before and returns to Tables afterward; and, for
    manager/supervisor only, a "მართვის ცენტრი" button just above it that
    opens the Admin screen. Confirm a waiter session does NOT see that
    button.
15. Resize the Tables window down well below 1024×768 (e.g. ~1000×500) —
    confirm the stacked layout's chrome scrolls instead of throwing an
    overflow error, and the floor plan still renders (however small) in
    whatever height remains.
16. Any OTHER screen (Calculator, Takeaway, Reservations, X-report, Admin)
    and Tables below 1000px width — confirm there is intentionally **no**
    manual lock control there anymore (expected, per the trade-off above);
    confirm idle auto-lock still engages after inactivity regardless of
    which screen is open.
17. Tables at 1024×768 — confirm the side rail (heading, floor card,
    selection overview, metrics) renders fully with no overflow error; if
    the window is short enough that it still doesn't fit, it should scroll
    rather than overflow. Also confirm individual tables on the floor plan
    render their icon/label without an internal overflow error at this
    scale (they'll look small, not broken).
18. Top bar at every width — confirm there is no "მართვის ცენტრი" nav tab
    anymore; Admin is reachable only via the shared rail's button (see #20).
19. Floor plan (any resolution) — confirm it's aspect-ratio preserved (NOT
    stretched) and looks identical, proportion-wise, to the same layout
    shown in the admin layout editor; empty side margins are expected and
    intentional (stretching was tried and reverted).
20. Tap a reserved/occupied table — confirm it opens directly (brief
    "<table> • იხსნება..." row with a spinner, no button, then the order
    screen) with no separate "continue" tap required. For two tables
    reserved together as one party, confirm tapping either one opens the
    same shared order.
21. Other Home tabs (Calculator, Takeaway, Reservations, X-report) —
    confirm the staff card + admin-panel button are back to NOT appearing
    there (reverted); they should only show inside Tables' own rail, same
    as before the brief "every tab" experiment.
