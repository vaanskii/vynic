# Vynic Frontend Design Modernization Plan

## Findings

The current frontend works, but the design language is split between several visual systems:

- POS desktop uses hardcoded blues, gradients, old panel styling, and screen-local color constants.
- Mobile manager app has a fancier glass/orb style, but it feels separate from the POS and can look decorative instead of operational.
- Admin screens are functionally rich but visually heavy, with many long files mixing state, business actions, layout, and styling.
- There is no shared Vynic design system used by POS, admin, and mobile together.

Large files that make design changes risky:

- `pos_app_client/lib/apps/windows_pos/screens/admin_screen.dart` - 3608 lines
- `pos_app_client/lib/apps/windows_pos/screens/order_detail_screen.dart` - 2929 lines
- `pos_app_client/lib/apps/windows_pos/widgets/admin/admin_menu_section.dart` - 2375 lines
- `pos_app_client/lib/apps/mobile_app/presentation/screens/dashboard_screen.dart` - 2074 lines
- `pos_app_client/lib/apps/windows_pos/widgets/admin/admin_packages_section.dart` - 2659 lines

The main issue is not only colors. The main issue is that Vynic does not yet have one shared product design language.

## Proposed Solution

Build a modern restaurant-operations design system first, then apply it screen by screen.

The direction should be:

- Modern, clean, operational, and fast.
- Dense enough for restaurant staff.
- Less decorative glass/orb styling.
- More professional dashboard/admin layouts.
- Strong status colors for live restaurant state.
- Clear navigation and stable layouts for Windows POS.
- Mobile manager app should feel premium, but still serious and readable.

Recommended visual identity:

- Base: warm off-white / light neutral background.
- Text: near-black charcoal.
- Primary action: deep blue-green or refined navy.
- Success: emerald.
- Warning: amber.
- Danger: red.
- Info/live: blue.
- Avoid making the whole app purple/blue gradient.
- Use shadows lightly.
- Use 8-12px radius for operational panels; avoid too many 20-24px rounded cards in POS/admin.

## Target Structure

Create shared design foundations:

```text
pos_app_client/lib/core/theme/
  vynic_colors.dart
  vynic_spacing.dart
  vynic_radii.dart
  vynic_text_styles.dart
  vynic_theme.dart

pos_app_client/lib/core/widgets/design/
  vynic_app_shell.dart
  vynic_side_nav.dart
  vynic_top_bar.dart
  vynic_status_badge.dart
  vynic_metric_tile.dart
  vynic_panel.dart
  vynic_action_button.dart
  vynic_empty_state.dart
```

Keep platform-specific widgets where needed:

```text
pos_app_client/lib/apps/windows_pos/widgets/design/
  pos_command_bar.dart
  pos_table_tile.dart
  pos_floor_toolbar.dart
  pos_order_summary_panel.dart

pos_app_client/lib/apps/mobile_app/widgets/design/
  mobile_manager_shell.dart
  mobile_metric_card.dart
  mobile_section_header.dart
```

## Visualizations

### POS Home Panel

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Vynic POS     Live: Online   Business Day: 23 Jun   User: Manager    Alerts │
├──────────────┬───────────────────────────────────────────────────────────────┤
│ Tables       │ Floor 1   [All] [Open] [Reserved] [Needs action]             │
│ Orders       ├─────────────────────────────────────────────┬─────────────────┤
│ Takeaway     │                                             │ Today Snapshot  │
│ Reservations │        Stable floor/table work area          │ Open tables     │
│ X Report     │        Big touch targets                     │ Reservations    │
│ Admin        │        Color by table status                 │ Takeaway        │
│ Logout       │                                             │ Recent changes  │
├──────────────┴─────────────────────────────────────────────┴─────────────────┤
│ [Open Table]  [Takeaway]  [Reservation]  [Print X]  [Refresh]               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### POS Order Detail

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Table 7       Waiter: Nika       Open 42m       Status: Active              │
├───────────────────────────────┬──────────────────────────────────────────────┤
│ Categories / Menu Search      │ Current Order                                │
│                               │ ┌ Item                     Qty   Total ┐     │
│ Fast item grid                │ │ Khinkali                  5    25.00 │     │
│ Touch optimized               │ │ Lemonade                  2     8.00 │     │
│                               │ └──────────────────────────────────────┘     │
│                               │ Subtotal / Service / Total                   │
├───────────────────────────────┴──────────────────────────────────────────────┤
│ [Send Kitchen] [Print Receipt] [Discount] [Split] [Close Table]             │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Admin Panel

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Admin Center     Sales today: 3,420 ₾    Open tables: 8    Printer: OK      │
├──────────────┬───────────────────────────────────────────────────────────────┤
│ Staff        │ Section header + filters + primary action                    │
│ Menu         ├───────────────────────────────────────────────────────────────┤
│ Packages     │ KPI row / table / forms                                      │
│ Sales        │ Clear dense panels, fewer nested cards                       │
│ Reports      │ Sticky actions for save/test/print                           │
│ Printers     │                                                               │
│ Backup       │                                                               │
└──────────────┴───────────────────────────────────────────────────────────────┘
```

### Mobile Manager App

```text
┌──────────────────────────────┐
│ Today                         │
│ Revenue 3,420 ₾      Online   │
├──────────────────────────────┤
│ Open Tables   Takeaway        │
│ Reservations  Alerts          │
├──────────────────────────────┤
│ Live activity                 │
│ Recent orders / changes       │
├──────────────────────────────┤
│ Dashboard  Tables  Finance    │
└──────────────────────────────┘
```

## Design Rules

- POS must stay fast and practical, not decorative.
- Windows POS is the main production target.
- macOS is useful for development/testing, but design decisions should respect Windows touch/click usage.
- Mobile can be more polished, but should share colors, typography, status badges, and cards with POS.
- Do not rewrite screens first.
- Do not change business logic while redesigning.
- Do not change printer flow, sync flow, close-day behavior, order behavior, or database behavior as part of design work.
- Preserve all existing public APIs and screen navigation until each screen is safely migrated.

## Risks

- Repainting large screens directly can break workflows.
- Admin screens contain business actions and settings logic, so visual refactors can accidentally change behavior.
- Mobile dashboard has controller/state logic mixed with layout, so changing it without extraction can cause rebuild or refresh issues.
- POS table/order screens are production-critical; layout changes must be tested on Windows before release.
- Changing colors without a design system will make the app look different but not truly better.

## Files Affected Later

First design-system phase:

- `pos_app_client/lib/core/theme/`
- `pos_app_client/lib/core/widgets/design/`
- `pos_app_client/lib/main.dart`

POS modernization phase:

- `pos_app_client/lib/apps/windows_pos/screens/home_screen.dart`
- `pos_app_client/lib/apps/windows_pos/widgets/home/`
- `pos_app_client/lib/apps/windows_pos/widgets/table_selection_widget.dart`
- `pos_app_client/lib/apps/windows_pos/screens/order_detail_screen.dart`
- `pos_app_client/lib/apps/windows_pos/widgets/order/`

Admin modernization phase:

- `pos_app_client/lib/apps/windows_pos/screens/admin_screen.dart`
- `pos_app_client/lib/apps/windows_pos/widgets/admin/`

Mobile modernization phase:

- `pos_app_client/lib/apps/mobile_app/core/theme/`
- `pos_app_client/lib/apps/mobile_app/widgets/`
- `pos_app_client/lib/apps/mobile_app/presentation/screens/dashboard_screen.dart`
- `pos_app_client/lib/apps/mobile_app/presentation/widgets/dashboard_sections.dart`
- `pos_app_client/lib/apps/mobile_app/presentation/screens/admin_screen/`

## Implementation Plan

### Phase 1 - Visual Direction Only

Goal: Decide the final Vynic look before touching production screens.

Steps:

1. Generate 2-3 visual mockups for:
   - Windows POS home panel
   - Windows POS admin panel
   - Mobile manager dashboard
2. Choose one design direction.
3. Lock color palette, typography, spacing, radius, elevation, and status colors.

What can break:

- Nothing, if this phase only creates mockups and planning docs.

Verification:

- Compare mockups against real restaurant usage.
- Confirm that POS is readable from distance and fast for staff.
- Confirm Georgian text fits buttons/cards.

### Phase 2 - Shared Design Tokens

Goal: Add shared theme files without changing screen behavior.

Steps:

1. Add `vynic_colors.dart`.
2. Add `vynic_spacing.dart`.
3. Add `vynic_radii.dart`.
4. Add `vynic_text_styles.dart`.
5. Add `vynic_theme.dart`.

What can break:

- Very low risk if screens do not use the new tokens yet.

Verification:

- `dart format`
- `flutter analyze`
- `flutter build macos --debug`

### Phase 3 - Shared Primitive Widgets

Goal: Build reusable UI pieces before touching big screens.

Steps:

1. Add `VynicPanel`.
2. Add `VynicMetricTile`.
3. Add `VynicStatusBadge`.
4. Add `VynicActionButton`.
5. Add `VynicSideNav`.
6. Add `VynicTopBar`.

What can break:

- Low risk if these widgets are added unused first.

Verification:

- Add widget previews or a small internal preview screen if approved.
- Run analyzer/build.
- Check light/dark contrast manually.

### Phase 4 - POS Home Modernization

Goal: Modernize the POS first screen without changing table/order behavior.

Steps:

1. Replace hardcoded POS colors with shared tokens.
2. Update sidebar styling.
3. Update top bar styling.
4. Update table dashboard panels.
5. Update bottom command bar.

What can break:

- Sidebar navigation.
- Table selection.
- Floor switching.
- Notification panel overlay.
- Bottom action buttons.

Verification:

- Open POS home.
- Switch floor.
- Select tables.
- Open reservation tab.
- Open takeaway tab.
- Open notification panel.
- Open admin panel.
- Test on Windows before production.

### Phase 5 - POS Order Detail Modernization

Goal: Modernize the order screen after home is stable.

Steps:

1. Extract visual header/summary components if needed.
2. Apply shared buttons/status badges.
3. Improve item list density and totals panel.
4. Keep all order actions unchanged.

What can break:

- Send kitchen check.
- Print receipt.
- Close table.
- Split/payment actions.
- Item quantity editing.

Verification:

- Create order.
- Add/remove items.
- Send kitchen check.
- Print receipt.
- Close paid order.
- Test on Windows.

### Phase 6 - Admin Panel Modernization

Goal: Make admin feel like a modern control center, not old settings pages.

Steps:

1. Modernize admin shell/sidebar first.
2. Modernize settings/printer panel.
3. Modernize sales/report panels.
4. Modernize staff/menu/package panels.

What can break:

- Printer settings.
- Close day.
- Backup/restore.
- Staff permissions.
- Menu/package editing.

Verification:

- Test every admin tab.
- Test printer save/test.
- Test close-day flow in safe test data.
- Test report generation.

### Phase 7 - Mobile Manager Modernization

Goal: Make mobile premium but less old/fancy and more product-grade.

Steps:

1. Merge mobile theme into shared Vynic tokens.
2. Reduce decorative glass/orbs.
3. Update dashboard cards and navigation.
4. Update mobile admin tabs.
5. Keep live socket/notification behavior unchanged.

What can break:

- Tab state retention.
- Notifications.
- Dashboard refresh.
- Live status views.
- Mobile admin forms.

Verification:

- Login on mobile.
- Switch all tabs.
- Open notifications.
- Open live table/order.
- Test light/dark appearance.
- Test on real Android/iOS if available.

## Recommended First Step

The safest first step is Phase 1: create visual mockups only.

No code behavior changes. No screen refactor. No business logic touched.

After mockups are approved, start Phase 2 by adding shared design tokens.

