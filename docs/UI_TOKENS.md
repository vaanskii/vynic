# Vynic UI Tokens & Primitives (UI Phase 2)

The shared design foundation for the modern light Windows POS direction. Added
in UI Phase 2 as an **additive, unused** layer — no existing screen imports it
yet. Future phases migrate their own screens onto it (see `docs/UI_PLAN.md`
§6.3 for why we do this screen-by-screen instead of flipping `ThemeData`).

All of it lives under `apps/operations/lib/core/ui/`, re-exported from a single
barrel: `import 'package:vynic/core/ui/vynic_ui.dart';`

Responsive/layout rules have their own companion doc: **`docs/UI_RESPONSIVE.md`**.

---

## Purpose

- One source of truth for color, type, spacing, radius, motion, elevation,
  touch targets, and status colors.
- Values are the same family as the existing `admin_design.dart` (teal accent,
  neutral greys, 8px radius) so migrating a screen onto tokens is a lateral
  move, not a repaint.
- Design direction: **calm, operational, light**. Restrained teal accent,
  neutral surfaces, clear status colors, large touch targets, minimal motion,
  high readability, Georgian-first text. **No** purple/violet dominance, **no**
  decorative glass for operational screens.

---

## Colors (`vynic_colors.dart`)

| Token | Hex | Use |
|---|---|---|
| `background` | `#F7F8FA` | App background behind cards |
| `card` | `#FFFFFF` | Raised surface (cards, panels, dialogs) |
| `cardSoft` | `#F9FAFB` | Inset/nested surface |
| `border` | `#E5E7EB` | Default 1px line |
| `borderStrong` | `#D1D5DB` | Structural divider |
| `textPrimary` | `#111827` | Primary text (17.7:1 on card) |
| `textMuted` | `#5B677A` | Secondary text (5.7:1 on card — AA) |
| `textDisabled` | `#94A3B8` | Disabled only, never live info |
| `accent` | `#0F766E` | Primary accent (teal) |
| `accentHover` | `#0E6D65` | Pressed/hover (accent −8%) |
| `accentSoft` | `#0F766E @ 12%` | Selected chip/nav fill |
| `onAccent` | `#FFFFFF` | Text/icon on accent or danger fills |

### Status colors

Each status has three roles: a **full-strength hue** (fills, icons, dots), a
**soft background** (12%-ish tint for chips) and a **soft border**. Small chip
*text* uses a darkened, WCAG-AA-compliant shade where the hue alone doesn't
clear 4.5:1 on its tint (11px bold is not "large text" under WCAG).

| Tone | Hue (icon/fill) | Chip text | Soft bg | Soft border | Text-on-bg ratio |
|---|---|---|---|---|---|
| success | `#16A34A` | `#15803D` | `#ECFDF5` | `#A7F3D0` | 4.76 ✓ |
| warning | `#D97706` | `#B45309` | `#FFFBEB` | `#FDE68A` | 4.84 ✓ |
| danger  | `#DC2626` | `#B91C1C` | `#FEF2F2` | `#FECACA` | 5.91 ✓ |
| info    | `#2563EB` | `#2563EB` | `#EFF6FF` | `#BFDBFE` | 4.75 ✓ |
| neutral | `#5B677A` | `#5B677A` | `#F1F5F9` | `#E2E8F0` | 5.23 ✓ |

All chip text/background pairs are asserted ≥ 4.5:1 in
`test/unit/vynic_tokens_test.dart`.

---

## Status → operational-state mapping (`vynic_status_tokens.dart`)

`VynicOperationalState` is a **presentation** enum with the 16 states from
`docs/UI_PLAN.md` §3. It does **not** replace the domain enums (`OrderStatus`,
`ReservationStatus`, `TableOperationalStatus`, `BackendConnectionState`) — a
future widget derives the operational state from those, then asks for its token.

| Operational state(s) | Tone |
|---|---|
| Free, Stale, Printed | neutral |
| Occupied, Sent to kitchen | info |
| Reserved, Reserved soon, Dirty, Manager approval needed, Offline | warning |
| Seated late, Unpaid, Kitchen failed, Sync failed, Printer failed, Blocked | danger |

Several states share a tone on purpose. **Color is never the only signal**
(§3 rule): `VynicStatusChip` always renders a label, and callers pass an icon
for states colorblind staff must distinguish. Resolve with
`VynicStatusTokens.ofState(state)` / `.toneForState(state)`.

---

## Typography (`vynic_text_styles.dart`)

Scale **11 / 13 / 15 / 18 / 24**, weights **600 / 800 only**. Styles set no
`fontFamily`, so text inherits the ambient font and Georgian rendering is
unaffected. 11px is the absolute floor (`minFontSize`).

| Style | Size / weight | Use |
|---|---|---|
| `title` | 24 / 800 | Screen/section title |
| `heading` | 18 / 800 | Card/sub-section heading |
| `bodyStrong` | 15 / 600 | Primary body / list text |
| `body` | 15 / 600 muted | Secondary body |
| `label` | 13 / 600 muted | Labels, secondary rows |
| `caption` | 11 / 800 muted | Chip text, smallest allowed |

---

## Spacing, radius, motion, elevation, touch targets

- **Spacing** (`vynic_spacing.dart`): `xxs 4 · xs 8 · sm 12 · md 16 · lg 24 · xl 32`.
- **Radius** (`vynic_radius.dart`): `sm 8` (cards/buttons), `lg 12` (dialogs/
  sheets), `pill 999` (chips). `BorderRadius` constants provided.
- **Motion** (`vynic_motion.dart`): `fast 120ms`, `normal 200ms` — and nothing
  else. `VynicMotion.allowed` is asserted to be exactly those two in tests.
- **Elevation** (`vynic_shadows.dart`): `panel` (subtle, floating cards),
  `overlay` (dialogs/sheets), `none` (flat bordered cards). One shadow per
  surface; no colored glows.
- **Touch targets** (`vynic_touch_targets.dart`): `minPos 44`, `minAdmin 36`,
  `minRow 44`. These are **logical** px; because Flutter folds the Windows
  display-scale factor into logical px, a 44-logical-px control stays ≥ 44
  physical px at 100% and grows under 125%/150% scaling — so sizing to these
  is scale-safe. Asserted `>= 44 / >= 36` in tests.

---

## Primitives (`vynic_ui.dart` → `widgets/`)

All additive; none wired into a real screen in Phase 2. All truncate/ellipsize
long Georgian labels rather than overflowing.

| Widget | Purpose | Min touch target |
|---|---|---|
| `VynicButton` | Primary/secondary/danger action button | 44 (POS), pass `minAdmin` for admin |
| `VynicStatusChip` | Pill status chip (`.forState` picks the tone) | n/a (display) |
| `VynicCard` | Flat/bordered or floating surface | 44 if `onTap` |
| `VynicSectionHeader` | Title + subtitle + action (stacks action when narrow) | — |
| `VynicMetricTile` | KPI tile (label + big value) | 44 min height |
| `VynicEmptyState` | Icon + title + message + action placeholder | — |
| `VynicLoadingState` | Centered progress + optional message | — |
| `VynicSideSheet` | Right-anchored sheet shell for non-blocking flows | 44 close button |
| `VynicResponsiveDialog` | Width/height-capped modal (see UI_RESPONSIVE) | — |
| `VynicTwoPaneLayout` | Responsive primary+secondary panes | — |
| `VynicScrollablePanel` | Scroll-safe fixed-height panel body | — |
| `VynicConstrainedContent` | Caps content column width on wide screens | — |

---

## How future phases must use these

1. **Never hardcode** a hex, spacing literal, radius, duration, or tap size
   that a token already covers. Import the token.
2. **Migrate one screen at a time** (UI_PLAN §6.3). Replace the screen's
   manually-passed `_primaryColor`/`_textPrimary`/etc. with tokens, capture
   before/after screenshots for that screen, and stop there.
3. **Status is icon + label, never color alone** — always pass an icon to
   `VynicStatusChip` for a state colorblind staff must tell apart.
4. **Do not wire `ThemeData` app-wide** until every screen already references
   tokens individually (that flip is a separate, later, reviewed step).
5. **Do not repaint without a workflow improvement** (UI_PLAN §8) — tokens are
   a means to consistency, not a license to restyle for its own sake.
