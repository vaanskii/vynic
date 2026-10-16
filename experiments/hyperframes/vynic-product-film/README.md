# Vynic product film (HyperFrames)

A 25-second, 16:9 product film: the V draws and its stroke traces the POS →
POS runs a table → the order syncs into one restaurant record in the Vynic
cloud → Manager reads the day and receives goods in Inventory → the same
menu appears on a Vynic-hosted SaaS site and on a bespoke CUSTOM build → the
whole system folds back into the V.

Experiment only. Not part of any app build; nothing here is imported by
`apps/*`.

| File | What it is |
| --- | --- |
| `BRIEF.md` | The confirmed brief and the product-truth constraints. |
| `frame.md` | Design truth: palette, type, form vocabulary, all traced to the repo. |
| `STORYBOARD.md` | The six scenes with exact timestamps, colours, forms, sources, motion, text and sound. |
| `MOTION_DIRECTION.md` | Palette, type, logo geometry, surfaces, light, easing, and why it reads as Vynic. |
| `index.html` | The composition: one world, one camera, one paused timeline. |
| `audio/synth.mjs` | Original score + sound design, synthesised deterministically. |
| `assets/fonts/` | Geist, Geist Mono, Noto Serif/Sans, Cormorant Garamond (all SIL OFL; see `FONTS.md`). |

## Commands

```bash
npm run audio          # regenerate assets/audio/vynic-score.wav (0.6s, deterministic)
npm run dev            # HyperFrames Studio preview
npm run check          # lint + runtime + layout + motion + contrast
npm run render:preview # review cut: Scenes 1–2 only (0–8.0s) → renders/preview/
npm run render:master  # MASTER: 1080p30 MP4 with sound (Docker render)
npm run render:web     # WEBSITE: 1080p30 MP4, no audio track
npm run render:webm    # WEBSITE: WebM (VP9), no audio track
tools/contact-sheet.sh # key frames from every scene + 720p quick-review copy
```

Renders use `--docker` so the host needs no FFmpeg; Docker must be running.
`{"sound": false}` is a declared composition variable: the website renders
contain no audio track at all rather than a silent one.

## Truth constraints (do not "improve" these away)

- Manager updates by **pull to refresh**, its real mechanism. The earlier
  "Syncing… / Synced" pill was invented and has been removed. Manager reads
  Cloud snapshots; it is not a realtime mirror, and no latency is claimed.
- The Manager rebuild is a faithful **English translation** of the current
  Georgian-only Manager UI (Dashboard, Inventory home, receiving review step,
  receipt card) in its light theme.
- **Inventory shows implemented features only:**
  - Receiving from a supplier.
  - The payment choice.
  - The review summary (stock added, value, paid now, debt).
  - The posted "Added to stock" receipt.
  - Received today.
  - The low-stock warning.
  - Payments & debt.
- **Never show:** stocktake or count, transfers, waste, purchase-order
  fulfilment, production batches.
- **No other unfinished features:** no multi-POS coordination, no acquiring,
  no AI (the real Manager's AI card is removed), no automatic CUSTOM deployment
  ("bespoke build").
- **No POS guarantees:** it is "a local app on the restaurant's own device",
  never "offline", "zero data loss" or "100%".
- **Synthetic data only:**
  - Demo Bistro, Nino.
  - Table 4: 2 × Khachapuri + Churchkhela = 61.60 GEL.
  - Old Town Mill: Flour +20.000 kg, 30.00 GEL, unpaid.
- The POS keeps its local copy: the total lifts off as a capsule and returns.
