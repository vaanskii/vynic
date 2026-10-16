# Launch film: motion direction

This film inherits the Vynic motion language defined in
`../vynic-product-film/MOTION_DIRECTION.md` (palette, V geometry, surfaces,
light, easing) and extends it for a 60 s Georgian narrative.

## Palette (from code)

| Role | Hex | Source |
|---|---|---|
| Stage / raised | `#1A1817` / `#22201E` | platform-web charcoal |
| Accent | `#764B7C` plum | POS `accent`, site `--vynic-plum` |
| Accent on dark | `#B9A8C4` lavender | site / launch splash |
| POS UI | `#F7F6F4` paper, `#FFFFFF` cards, `#4C4272` action, `#F2EFFA`/`#52447A` selection, `#D9A531` occupied | `vynic_colors.dart`, `vynic_floor_tokens.dart` |
| Manager UI (light) | `#E3EDFC`/`#DCE8FB` bg, `#FFFFFF` surface, `#C7D9F5` border, `#0F172A` ink, `#2563EB` primary, `#F59E0B` warn, `#10B981` good | `manager_dashboard_theme.dart` |
| SaaS classic | `#FBF8F3` paper, `#F4EDE2` raised, `#1B1815` ink, `#7D5B2E` accent, `#161310` dark | `restaurant-web/src/styles/base.css` |
| Vankisi | `#050505` ground, `#AE895E` gold | `vankisi-custom-web` |
| Glow | plum radial, 10–85% | launch splash |

Each product keeps its own colours inside its frame. Plum is the only accent on the stage.

## Type

- **Geist / Geist Mono:** Vynic, the wordmark, and numbers.
- **Noto Sans Georgian:** the font the POS and Manager apps actually ship, used for all Georgian UI, tags and the tagline.
- **Noto Serif Georgian:** the SaaS classic theme's display face.
- **Vankisi's own header face:** only for the name "ვანკისი" in Vankisi's hero.

## Camera and motion

- **One continuous camera.**
  - Travels: 1.4–2.2 s, `power3.inOut` or `power2.inOut`.
  - Settles: slow `sine.inOut` push-ins.
  - Nothing is ever cut.
- **Arrivals:** surfaces arrive in depth (a small scale change plus `rotationX` in perspective), and only once they are framed whole.
- **Shared elements:**
  - the V stroke that becomes the terminal outline;
  - the order total that becomes a capsule, then a Manager figure;
  - the menu pulse;
  - one dish card, SaaS → Vankisi.
- **In-app transitions** follow each app's real navigation: the POS floor ↔ order editor; Manager tab change, a receiving page that rises, and a push to stock balances.
- **Interaction pacing:** UI taps are about 0.7 s apart and only a few are audible. No bounce, overshoot or spin.
- **No stray artefacts:** clipped page content is culled, and connectors fade after they retract.
