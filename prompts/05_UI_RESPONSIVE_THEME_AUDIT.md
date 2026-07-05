# Prompt — Phases 5–6: UI, responsiveness & theme

Only after Phases 1–4. This is the UI redesign — do NOT start it earlier. Follow the
detailed design sub-plan in `docs/UI_PLAN.md`.

---

Modernize Vynic's UI for responsiveness and a shared theme. Read
`docs/VYNIC_PROJECT_PLAN.md` §5 and §6 (Phases 5–6), then `docs/UI_PLAN.md` (the detailed
design system plan).

Problems to address (from the audit):
- Heavy fixed pixel dimensions (e.g. `menu_screen.dart` ~75 fixed sizes vs 2
  responsive refs) — breaks on other screen sizes.
- Colors/theme passed manually (`_primaryColor`, `_textPrimary`, …) instead of
  `ThemeData`/`ColorScheme`.
- Too many modal/dialog layers slow staff down.
- ~2,870 inline Georgian strings (localization).

Sequencing (do NOT do all at once):
1. **Phase 5a — theme:** introduce shared tokens/`ThemeData` per `docs/UI_PLAN.md`; migrate
   screens off manually-passed colors incrementally. No layout changes yet.
2. **Phase 5b — localization:** move Georgian strings into ARB (`ka` + `en`). Do this
   before layout rework so each screen is touched once.
3. **Phase 6 — responsive:** define breakpoints (POS terminal / tablet / phone),
   replace fixed sizes with `LayoutBuilder`/`Flexible`/grids, drive spacing/type from
   the theme. One screen at a time; start with the highest-traffic POS screens.

Constraints:
- Do not change business logic, order/close-day/print/sync behavior while
  restyling — `docs/UI_PLAN.md` says the same.
- One screen (or one token layer) per change; keep commits small.
- Verify each screen visually on macOS/Windows plus `flutter analyze` + build. Confirm
  Georgian text still fits controls. `git status --short` before/after. Do not commit
  unless I say so.
