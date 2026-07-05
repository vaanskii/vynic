# Vynic Responsive Foundation (UI Phase 2)

The layout half of the UI Phase 2 foundation: breakpoints, layout modes, and
panel/dialog/sidebar width rules that let UI Phase 3+ fix the shell and tables
at low resolutions and Windows display scaling **without each screen inventing
its own magic numbers**.

Additive and unused in Phase 2. Lives in `pos_app_client/lib/core/ui/`
(`vynic_breakpoints.dart`, `vynic_responsive.dart`, plus the layout primitives
in `widgets/`), re-exported from `vynic_ui.dart`.

Companion doc for color/type/etc.: **`docs/UI_TOKENS.md`**.

---

## Target resolutions

The Windows POS must work on restaurant terminals and staff laptops across:

`1024×768 · 1280×720 · 1280×800 · 1366×768 · 1440×900 · 1536×864 · 1600×900 ·
1920×1080 · 2560×1440`, on 24–32" external monitors, at Windows display
scaling **100% / 125% / 150%**.

### Why logical width, not resolution

Flutter measures in **logical pixels**, which already fold in the OS display
scale factor. A physical 1920px monitor at 150% scaling reports ~1280 logical
px. That's the point: at 150% there is genuinely less usable room, and our
breakpoints react to the logical width, so the same screen correctly becomes
"more compact" when the user scales up. **Always** measure with
`MediaQuery.sizeOf(context).width` or a `LayoutBuilder`'s `constraints.maxWidth`
— never branch on a hardcoded resolution or `Platform`.

---

## Layout modes & breakpoints (`vynic_breakpoints.dart`)

`VynicLayoutMode`:

| Mode | Logical width | Typical case |
|---|---|---|
| `compact` | `< 1100` | 1024×768; 1280×720/1366×768 minus chrome under 125–150% |
| `regular` | `1100 – 1599` | 1280×800, 1366×768, 1440×900, 1536×864, 1600×900 |
| `expanded` | `>= 1600` | 1920×1080, 2560×1440, large externals |

`VynicBreakpoints.compactMax = 1100` (matches the existing `compactDesktop`
check in `menu_screen.dart`), `expandedMin = 1600`. Resolve with
`VynicBreakpoints.modeForWidth(width)` or `VynicResponsive.modeOf(context)`.

---

## Panel width rules (`vynic_responsive.dart`)

Side panels (order cart, detail rail, side sheet):

- `minPanelWidth = 300` — never narrower, or controls fall below the touch
  floor and text wraps to noise.
- `maxPanelWidth = 460` — never wider, or lists become an awkward void on
  large displays.
- `compactPanelWidth = 300` — used in compact mode.
- `panelWidth(availableWidth, preferred: 380)` clamps to the above **and**
  caps at **42% of available width** so the primary pane is never starved.

`canShowTwoPanes(width, minPrimaryWidth: 480)` returns false below
`compactMax`, and otherwise only if the primary keeps its minimum after the
panel takes its share.

## Content width rules

- `maxContentWidth = 1200` — reading columns (forms, reports, settings) cap
  here via `VynicConstrainedContent` so lines stay scannable on 1920/2560.

## Dialog width rules

- `maxDialogWidth = 560` — hard cap regardless of screen size.
- `dialogViewportMargin = 32` — reserved on each side.
- `dialogWidth(context, preferred:)` = `min(preferred ?? 560, 560,
  screenWidth − 64)` — so a dialog **cannot overflow** a 1280×720 (or
  smaller-after-scaling) viewport. `VynicResponsiveDialog` also caps height at
  90% of screen and scrolls its body, so tall forms can't overflow vertically
  under 150% scaling.

## Sidebar / nav sizing

The persistent left rail stays a fixed comfortable width in `regular`/
`expanded` and is expected to collapse to icon-only (or a drawer) in `compact`
— UI Phase 3 owns the shell's actual rail; this doc fixes the rule, the phase
picks the exact widths using the layout mode.

## Adaptive spacing

- `gutter(mode)` — outer page padding: 16 compact / 24 regular / 32 expanded.
- `sectionGap(mode)` — gap between cards: 12 compact / 16 otherwise.

---

## Layout primitives (`widgets/`)

| Widget | What it guarantees |
|---|---|
| `VynicTwoPaneLayout` | Side-by-side when there's room; collapses to one pane (or stacks) when tight. Panel width clamped so it never overflows and primary keeps a minimum. **The main tool for shell/tables/menu/order at 1366×768 + scaling.** |
| `VynicResponsiveDialog` | Width capped by `dialogWidth`, height capped at 90%, body scrolls — overflow-safe on the smallest target. |
| `VynicScrollablePanel` | Wraps a fixed-height panel's body in a scroll view so data-driven content scrolls instead of overflowing. |
| `VynicConstrainedContent` | Caps + centers content width on wide monitors. |
| `VynicSideSheet` | Right-anchored sheet using the panel width rules; preferred over stacked dialogs for non-blocking flows. |

---

## Acceptance criteria met in Phase 2

- No fixed full-screen assumptions — every primitive uses `LayoutBuilder` /
  `MediaQuery`, none branches on a resolution.
- No primitive overflows at **1280×720** — asserted with long Georgian labels
  in `test/widget/vynic_primitives_test.dart`.
- Dialog primitives cap width by available screen width.
- Side panels support compact widths (down to 300).
- Touch targets stay ≥ 44px (see UI_TOKENS).
- Text uses ellipsis/wrap that works with Georgian labels.

---

## How future phases must test responsive layouts

For **every** screen a phase migrates, verify at minimum:

1. **1366×768 at 100%** — the most common cramped terminal.
2. **1280×720** — the smallest supported; nothing may overflow or clip.
3. **Windows 125% and 150%** — re-check the same screens; confirm no clipping,
   no overlap, no control below the 44px floor, no dialog touching the edge.
4. **1920×1080** — confirm content doesn't sprawl (panels cap, content columns
   constrained).
5. **Real Georgian strings**, not Latin placeholder — labels are ~20–40%
   longer; confirm ellipsis/wrap, not overflow.
6. **Keyboard focus** reachable and visibly ringed; dialogs trap and restore
   focus (Baseline Bar, UI_PLAN §6.1).

Prefer `LayoutBuilder`/`MediaQuery` + the helpers above over ad-hoc width
checks so the whole app reacts consistently.
