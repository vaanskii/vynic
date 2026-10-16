# Vynic product film: motion direction

Everything here is taken from the shipped product. The sources are:

- **POS colour tokens:** `apps/operations/lib/core/ui/vynic_colors.dart` and `vynic_floor_tokens.dart`
- **Public site styles:** `apps/platform-web/src/styles/index.css`
- **The POS launch splash**
- **The mark:** `tools/brand/*.svg`

Where the docs and the code disagree, the code wins. `docs/UI_TOKENS.md` still calls the accent teal, but the code has been plum `#764B7C` since the rebrand.

## 1. Palette

The POS and the public site already share one plum accent and one warm, slightly red-leaning neutral family. The film uses only that family.

| Role | Hex | Where it comes from | Used for |
|---|---|---|---|
| **Stage (primary dark)** | `#1A1817` | site charcoal `#22201E`, pushed one step darker so raised surfaces read | the whole film's background |
| **Raised surface (dark)** | `#22201E` | site charcoal | hub tile, Cloud record, tags |
| **Accent** | `#764B7C` plum | POS `accent`, site `--vynic-plum` | glow, selection ring, tap flash |
| **Accent on dark** | `#B9A8C4` lavender | site dark-context accent, launch splash | connectors, labels, caption index |
| **Background (UI)** | `#F7F6F4` | POS `background`, mark ground | POS page; also text and mark on dark |
| **Surface** | `#FFFFFF` / `#FAF9F7` | POS `card` / `cardSoft` | POS cards and panels |
| **Text** | `#1C1A18` on light, `#F7F6F4` on dark | POS `textPrimary` | |
| **Muted** | `#6F6A65` on light, `#A8A09A` on dark | POS floor `textMuted` | secondary text, tagline |
| **POS action** | `#4C4272` | POS floor `accentStrong` | primary buttons, POS badge |
| **POS selection** | `#F2EFFA` fill, `#52447A` text | POS floor selection tokens | active tab, category, "+" buttons |
| **Status** | occupied `#D9A531`, success `#2E7D5B` / `#3E7D5F` | POS status tokens | Table 4 state, "Sent to kitchen" |
| **Glow (optional)** | `#764B7C` radial, 18–75% | launch splash radial | one per focal point |

Colour rules:

- **One stage colour** for the whole film.
- **Plum is the only accent hue** on the stage.
- **Products keep their real colours** inside their frames. Manager's blue-tinted UI and the SaaS and CUSTOM website themes are the products being shown, so they are not recoloured to match the brand.

## 2. Typography

- **Geist** (400 / 600 / 700) for the wordmark, captions and all POS UI. It is Vynic's brand sans and is embedded under the OFL, licence included in `assets/fonts/`.
  - Wordmark: 172px, weight 600, tracking −0.045em.
  - Captions: 36px, weight 600, tracking −0.02em.
- **Geist Mono** for data: totals, times, table codes, record labels, the data capsule and caption indexes.
  - Tabular figures, so counting numbers don't jitter.
  - Wide tracking (0.08–0.16em) for labels.
- **Website skins use the real sites' type stacks, embedded.** There is no fallback font; details are in `assets/fonts/FONTS.md`.
  - **SaaS "classic":** Noto Serif for display and menu, Noto Sans for body. That is the open Latin equivalent of restaurant-web's `"Noto Serif Georgian" … Georgia` / `"Noto Sans Georgian"` stack.
  - **CUSTOM (bespoke):** Cormorant Garamond 700 for brand, headline and menu. A Noto Serif Italic gold accent word replaces the reference site's Georgia-italic accents, which are proprietary. Noto Sans for uppercase labels.

## 3. Vynic logo geometry

The mark is two strokes on a 100-unit grid, from `tools/brand/vynic-manager.svg`:

| Stroke | Path | Width |
|---|---|---|
| thick (left) | (22, 26) → (52, 72) | 19 |
| thin (right) | (52, 72) → (84, 18) | 11 |

- **Construction:** round caps, placed with `translate(12.9 12.9) scale(0.742)` inside the tile. The weight ratio is 19 : 11.
- **Angles:** the left stroke runs about 57° from horizontal and the right about 59°. The vertex is at (52, 72).
- **Tile:** the app-icon container is a 260px tile with a 57px corner radius (22% of its width).
- **In the film:** the mark is *drawn* stroke by stroke (thick first, then thin), from a spark at the vertex. It is never spun, scaled from zero, glitched or given a 3D treatment.
- **As a motif:** the same two angles return as the turns in every connector line, so the whole film is drawn with the logo's own geometry.

## 4. Background treatment

- A flat stage `#1A1817`. There are no gradients on the ground itself.
- A **44px hairline grid**, the same grid as the public site, in `#F7F6F4` at 7%.
  - It is masked to a central oval, so it fades out toward the edges.
  - It drifts at 18% of the camera's speed for a quiet parallax.
- A soft **vignette** to `rgba(10,9,9,0.55)` at the corners.
- No particles, bokeh, noise textures or stock backgrounds.

## 5. Surface / card treatment

- **Product surfaces are real UI at native size.**
  - POS window: 1440×900, 18px radius.
  - Manager phone: 420×880, 64px radius.
  - Website windows: 1200×720, 16px radius.
- **Inside the POS:** 12–14px card radius, 1.5px warm borders (`#E6E3DE` / `#EBE8E3`) and near-flat shadows, as in the app.
- **On the stage:** product windows carry one deep, soft drop shadow, `0 60px 120px rgba(0,0,0,0.55)`, plus a 10px ring at 4% white. That separates them from the dark without adding a glossy bevel.
- **Film-only surfaces:** the Cloud record, tags and data capsule are dark `#22201E` / `#2B2629` with a thin lavender border (26–45%).
  - They read as system diagrams, clearly distinct from product screens.
- No glassmorphism, and no floating tilted 3D screenshots.

## 6. Light / glow treatment

- **One glow per focal point:** a plum radial `#764B7C` (55% at the centre, 18% at 38%, gone by 68%).
  - It blooms in as the camera arrives and settles back when the camera leaves.
- **Depth of field is a dim, not a blur.** Places the camera is not looking at drop to 28–55% opacity.
- **The only highlights:** the spark at the V vertex (white core fading to lavender) and the pulse that travels the connectors (`#F1E9F5`).
- No lens flares, light leaks or rim-light sweeps.

## 7. Easing / motion language

"Calm precision" is the rule, matching the public site's motion tokens in `apps/platform-web/src/lib/motion.ts` (`expo.out`, `power3.out`, `power2.inOut`).

| Use | Ease | Duration |
|---|---|---|
| Camera travel between places | `power3.inOut` (soft acceleration, long controlled deceleration); `power2.inOut` for the final pull-back | 1.3–1.5s |
| Camera settle / push-in while a scene plays | `sine.inOut`, small scale change (≤ 0.05) | 1.3–3.8s |
| Surfaces arriving in depth (POS, websites, phone) | `expo.out` with scale 0.94–0.97 → 1 and `rotationX`/`rotationY` 6–10° → 0 in perspective | 1.0–1.4s |
| UI reactions (lines, captions, pills) | `power3.out` / `power2.out` | 0.35–0.7s |
| Number interpolation | `power3.out` | 0.55–1.0s |
| Masked handoff (SaaS → CUSTOM scan) | `power2.inOut` | 1.1s |
| Data capsules along connectors | one `power2.inOut` over the whole path, at constant speed along the polyline | 1.1–1.35s |
| Things leaving | `power2.in` / `power3.in` | 0.3–0.6s |
| Glow, grid, dimming | `sine.inOut` / `sine.out` | 0.5–2.0s |
| Stroke drawing | `power2.inOut` | 0.7–0.8s |

- **No overshoot, bounce, elastic or spin anywhere.**
- **Motion blur is not used.** Every camera move is slow enough that a shutter smear would only soften the UI text.
- **Anticipation before actions:**
  - Table 4 lifts and the rest of the floor dims before the tap.
  - "Confirm order" brightens before the press.
  - The data-layer marks appear before the renderer changes.
- **Interactions are about 0.6s apart,** on the score's 0.5s grid. Cause and effect start on the same frame.
- **One camera, no cuts.** Every scene change is camera travel, a card morph into a data capsule, a capsule followed along a line, or a masked scan.
- **Nothing sits half-visible at a frame edge.** A place outside the camera's framing is hidden and returns when the camera frames it whole.

### Handoffs used (v3)

- **Mark → POS:** the thick stroke continues along its own axis and traces the POS window, which then fills in. This is shared geometry, with no scene change.
- **POS → Cloud → Manager:** the order total becomes a capsule, docks in the record, and a second capsule carries 61.60 GEL onto the Manager revenue card. The camera follows it.
- **Dashboard → Inventory:** a real in-app path (the Dashboard Inventory card, then the Inventory tab). A receiving page rises and falls within the same device.
- **SaaS → CUSTOM:** one dish card lifts out of the page, survives the renderer scan, restyles itself, and settles into the custom menu.

## 8. Why this looks specifically like Vynic

1. **The colours are the product's own.** The plum, the warm paper and the charcoal are what a restaurant sees on the POS and the site; there is no generic SaaS blue or neon gradient.
2. **The logo is the grammar.** The V is drawn from its real strokes, and its two angles shape every connector. The film ends where it began, on the mark.
3. **Real UI does the storytelling.** It shows Vynic's actual Tables screen, order editor, Manager dashboard and website theme, with the product doing its job: a table, an order, a total, a sync.
4. **The story is Vynic's architecture.**
   - POS works locally and keeps its own copy.
   - Cloud holds one restaurant record.
   - Manager reads it after a sync.
   - Both kinds of website read the same menu.
   - Nothing implies realtime Manager, multi-POS coordination, AI or automatic custom builds.
5. **The pace suits a tool restaurant staff trust:** quiet, exact, no spectacle.
