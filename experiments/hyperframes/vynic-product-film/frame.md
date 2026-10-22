# Vynic film — design truth

Derived from the shipped product, not invented. Sources: POS tokens
`apps/operations/lib/core/ui/vynic_colors.dart` + `vynic_floor_tokens.dart`,
public site `apps/platform-web/src/styles/index.css`, the POS launch splash,
and the mark geometry in `tools/brand/`.

## Palette

The POS and the public site already share one plum accent (`#764B7C`) and a
warm, slightly red-shifted neutral family. The film keeps that one family and
uses the POS launch splash (charcoal ground, plum light) as its dark stage.

| Role | Hex | Source |
| --- | --- | --- |
| PRIMARY (ink / stage) | `#1A1817` stage, `#22201E` raised | site charcoal `#22201E`, mark ink `#111112` |
| ACCENT | `#764B7C` plum | POS `accent`, site `--vynic-plum` |
| ACCENT on dark / line | `#B9A8C4` lavender | site dark-context accent, launch splash |
| BACKGROUND (UI) | `#F7F6F4` | POS `background`, mark ground |
| SURFACE | `#FFFFFF` card, `#FAF9F7` soft | POS `card`, `cardSoft` |
| TEXT | `#1C1A18` on light, `#F7F6F4` on dark | POS `textPrimary`, mark ground |
| MUTED | `#6F6A65` on light, `#A8A09A` on dark | POS floor `textMuted` |
| POS action | `#4C4272` | POS floor `accentStrong` (primary buttons) |
| Status | occupied `#D9A531`, success `#2E7D5B` | POS floor/status tokens |
| OPTIONAL GLOW | `#764B7C` radial at 18–28% on the stage | launch splash radial |

Rules: one stage colour for the whole film; plum is the only accent hue on
the stage; UI surfaces keep their real product colours inside their frames
(the Manager's blue-tinted look and the SaaS/CUSTOM website themes are
diegetic — they are the products being shown).

## Type

- Geist 400/600/700 (brand sans, OFL, embedded) for statements and UI.
- Geist Mono (embedded) for data: totals, table codes, record labels, captions' index.
- Display tracking −0.035em; nothing under 18px on screen at the final camera scale except diegetic UI micro-labels.
- Website skins use the real sites' type stacks as restaurant content: Noto Serif + Noto Sans for the SaaS "classic" theme; Cormorant Garamond with a Noto Serif Italic gold accent for the bespoke CUSTOM build (see `assets/fonts/FONTS.md`).

## Form vocabulary (one grammar, every scene)

- **The V strokes.** Two round-capped strokes, 19 : 11 weight ratio, left stroke ≈ 57° and right ≈ 59° from horizontal. The mark is drawn, never spun.
- **Connectors.** Thin round-capped lines that travel horizontally and then turn at the V's angle into a node. They always land on a real element.
- **Data tokens.** Mono capsules carrying real record fields (table, items, total), never glowing dots.
- **UI surfaces.** POS 12px radius cards, chair-tick table shapes, lavender selection fills; a phone for Manager; browser frames for the websites.
- **Light.** One soft plum radial glow per focal point; a 44px hairline grid (the site's grid) as depth.

## Motion

Calm precision, same as the site: `expo.out`/`power3.out` settles, `power3.inOut`
camera moves, no overshoot, no spin, no glitch. The camera is one `.world`
transform; scenes are places in one world, not slides.
