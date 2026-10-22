# Fast-motion refine: style notes

This is a separate HyperFrames project for the refined cut. The current launch film in `../` (index.html, film.css, renders) is untouched.

- `base.css`: an unmodified copy of `../film.css`.
- `fast.css`: the new layers.
- `timeline.js`: the timeline source. `tools/inline.py` inlines it into `index.html`.
- `audio/`: the new music and SFX, built with the shared `../audio/lib.mjs`.

## Reference analysis (example.mp4, 13.5 s)

- **Pacing:** a cut about every 0.3–2 s. It holds only on data beats (2–3 s) and ends with a burst of one-word cards.
- **Transitions:**
  - geometric shape wipes, staggered vertical-bar wipes, and diagonal wedges;
  - a circle expanding to fill the frame;
  - a zoom-through into a pattern tile.

  Every transition also changes the background colour.
- **Typography:** huge, heavy, condensed capitals. Letters drop and slide in, with stacked outline echoes and underline strikes.
- **Colour:** flat full-bleed fields, one per shot: red-orange, acid lime, near-black, violet and warm paper.
- **Shape language:** rings with tick marks, orbiting dots, a morph from circle to square to triangle, and truchet-style patterns.
- **Overlay:** corner brackets, mono labels (section, timecode, fps and bpm), crosshairs and a progress bar.
- **Data:** giant count-ups with a progress ring, and bar charts that build in.
- **Texture:** fine grain and a radial light falloff.
- **Camera:** mostly locked off. The energy comes from the elements and from cuts hidden under wipes.

## Translated into Vynic

- **Palette:** plum `#764B7C` is the anchor. It opens, bridges and closes the film. Scene fields rotate as follows:

  | Colour | Hex | Used for |
  |---|---|---|
  | Near-black | `#121012` | Data and ecosystem scenes |
  | Warm paper | `#F2EEE7` | POS and website scenes |
  | Signal orange | `#EF5A2C` | The type-wipe and Manager |
  | Lime | `#D5F24B` | Only the tick marks, one orbit dot, and the SaaS→Custom edge |

- **Type:** Noto Sans Georgian at width 62.5 and weight 900, set in Mtavruli capitals. The words are short and sit behind the product:
  - სწრაფი მომსახურება;
  - გაყიდვები, then მარაგები, then მიღებები, then ნაშთები;
  - ონლაინ სივრცე, then ერთი მენიუ, then ორი დიზაინი;
  - ერთი სისტემა.
- **Graphic layer:**
  - technical grid, grain and radial falloff;
  - corner brackets, a timecode and a section index;
  - data rings with ticks and orbiting dots around the V.
- **Data (all figures already present in the product story; none invented):**
  - order 46.20 ₾ (itemised);
  - revenue ₾2,868.65 → ₾2,914.85, split closed ₾1,282.45 / open (3) ₾1,632.40;
  - flour +20.000 კგ;
  - supplier debt 30.00 ₾, with 30.00 of 60.00 ₾ paid.
- **One main motion idea per shot.** Fast acceleration with controlled deceleration: `expo` and `power4`, no bounce.

## Scene map (v2: 32.2 s, 120 bpm grid; v1 was 34.0 s)

| Time (s) | Scene | Main idea | Field |
|---|---|---|---|
| 0–2.5 | Open | V stroke → ring pulse → plum hit → wordmark → the stroke traces the terminal | ink → plum |
| 2.5–6.9 | POS | Table 4 ring → editor at once → 3 items fly into the order → total → confirm → amber occupied → push into T4 | paper |
| 6.7–7.9 | Type wipe | An orange panel carries "სწრაფი მომსახურება" across; the scene cuts underneath | signal |
| 7.6–10.6 | One system | The capsule docks in the V, the record pops, and 46.20 ₾ counts up itemised; lines reach out | ink |
| 10.2–10.8 | Whip | The camera runs the line to Manager; the total flies into the revenue card | ink → signal |
| 10.6–19.2 | Manager | Refresh → figures respond. The revenue card expands out of the phone into a data card and folds back. Inventory → receiving. Stock-added and debt cards expand out and fold back. Confirm → stock balances | signal |
| 19.2–19.7 | Scale-through | The phone screen opens to fill the frame | paper |
| 19.7–26.6 | Web | Ready-made site: fast scroll and menu tap. The shared line is annotated (dish · price). A lime-edged split wipe re-renders the same menu as Vankisi; the dish settles into its row; Vankisi hero | paper |
| 26.6–29.2 | Ecosystem | Ink hit. POS, Manager and both sites assemble around the V (Vankisi slides out from behind SaaS). Lines and pulses, then everything collapses into the V | ink |
| 29.2–32.2 | Lockup | Plum hit from the V; wordmark; "რესტორნის მართვის ერთიანი სისტემა" | plum |

**Product truth is unchanged from the approved film:**
- real Georgian POS, Manager and Inventory UI;
- `pikali.vynic.ge` and `vankisi.vynic.ge`;
- no stocktake, transfers or other unbuilt features, and no realtime, offline or "zero loss" claims.

The occupied table uses the POS legend's amber.

## Commands

```bash
npm run audio    # music.wav + sfx.wav
npm run check    # inline timeline + hyperframes check
npm run render   # 4K supersampled render → ../renders/style-refine/ (review MP4, contact sheet, old-vs-new sheet)
```
