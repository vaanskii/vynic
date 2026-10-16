---
format: 1920x1080 (16:9), 30 fps
duration: 25.0s
message: "Vynic runs the restaurant on the POS and connects one restaurant foundation to Manager (business day + Inventory) and to SaaS or custom websites."
arc: Identity → Operation (POS) → Connection (Cloud) → Manager (day + Inventory) → Reach (websites) → One system
mode: autonomous
music: original score synthesised from code (audio/synth.mjs), D major, 0.5s grid
status: v3. One-shot opening, a two-state Manager with Inventory, and a shared dish card in the website morph.
---

# Vynic product film: storyboard (v3, 25.0s)

Every timestamp is the exact position of a tween in `index.html`.

## How it's built

- **One world, one camera, no cuts.** The film is one 3840×2160 world, and one virtual camera travels through it.
- **Camera travel:** 1.4–1.5s moves with `power3.inOut`.
- **Settles:** where the camera stops, it keeps a slow `sine.inOut` push-in.
- **Arrivals:** surfaces arrive in perspective depth, with no slides.
- **Nothing half-visible:** anything the camera can't frame whole leaves before it would sit half-visible at the frame edge.

## The five ideas (and only these)

1. **Restaurant operations:** the POS runs a table from tap to kitchen.
2. **Local operation:** the POS is a local app on the restaurant's device. There is no "offline", "zero data loss" or other guarantee.
3. **Manager:** the business day and Inventory, on a second Vynic surface.
4. **One restaurant foundation:** the Vynic Cloud record that everything reads.
5. **SaaS or CUSTOM website:** the same menu in two renderers.

**Shared palette:**

| Role | Hex |
|---|---|
| Stage | `#1A1817` |
| Raised surface | `#22201E` |
| Plum | `#764B7C` |
| Lavender | `#B9A8C4` |
| Paper | `#F7F6F4` |
| Muted-on-dark | `#A8A09A` |

---

## Scene 1: the mark becomes the POS

**0.00 – 3.60s** (one shot)

| | |
|---|---|
| **What you see** | A point of light; the V's thick stroke draws, then the thin one, in lavender. The grid opens from the centre, the tile settles, and "Vynic" comes into focus. Light travels through the V and turns it white (1.60–2.35). **2.20:** the camera begins a slow move left and down. **2.30:** the thick stroke keeps going: a lavender line leaves its end cap along the stroke's own axis, reaches the POS window's top edge, and traces the window in both directions (2.30–3.35). The wordmark and the mark dissolve as the camera leaves them. **3.00:** the traced outline fills in and becomes the Vynic POS. The line fades into the window's edge. |
| **Colours** | Stage `#1A1817`. Strokes `#B9A8C4` → `#F7F6F4`. Light `#FFFFFF`. Tile `#22201E`. Grid `#F7F6F4` at 7%. Plum glow on the mark, then on the POS. Trace lavender, 4px. |
| **Forms** | The real V (`tools/brand/`), its thick-stroke axis extended (the same 46 : 30 slope). A 57px-radius tile. The 44px grid. The window outline with 18px rounded corners. |
| **Animation** | Push-in 1.00 → 1.08 (0–2.2). Strokes 0.8s / 0.7s `power2.inOut`. Wordmark 1.0s `expo.out` (blur → sharp). Camera travel 2.2–3.6, `power3.inOut`. Trace A 1.05s and trace B 0.87s, `power2.inOut`. POS fill 0.6s. |
| **Text** | "Vynic" |
| **Sound** | A low filtered "room" and a slow high shimmer under the whole opening. A spark chime with a long tail. Soft stroke draws. A low bloom under the wordmark. A shimmer as the light crosses. A deep camera swell and a faint rising tone with the trace. |

## Scene 2: POS runs service

**3.60 – 7.60s**

| | |
|---|---|
| **What you see** | The camera settles, then keeps a slow push toward the order.<br>**3.95** Table 4 gets focus: the rest of the floor dims, Table 4 lifts slightly, and a soft ring appears.<br>**4.45** Tap: the ring goes solid.<br>**4.75** The floor steps back; the order editor and Table 4's order arrive.<br>**5.55** Khachapuri is added (27.50).<br>**6.15** Khachapuri again, so the line becomes 2 × 25.00 (55.00).<br>**6.75** Churchkhela is added (**61.60 GEL**).<br>**7.10** "Confirm order" brightens.<br>**7.35** Press.<br>**7.45** "✓ Sent to kitchen · 20:41". |
| **Colours** | POS tokens: paper `#F7F6F4`, cards `#FFFFFF`, ink `#1C1A18`, selection `#F2EFFA` / `#52447A`, action `#4C4272` → `#5A4F86`, plum `#764B7C`, occupied `#D9A531`, sent `#3E7D5F`. |
| **Text** | "01 · POS" / "Runs service on the floor. *A local app on the restaurant's own device.*" |
| **Sound** | One soft tick on Table 4. Every other tap is silent. A two-note bell for "sent to kitchen". The low pulse bed begins. |

## Scene 3: the Vynic connection / handoff

**7.60 – 10.40s**

| | |
|---|---|
| **What you see** | The order total compresses into a capsule, "TABLE 4 · 3 ITEMS · 61.60 GEL": white like the order card, then dark. The floor returns with **Table 4 occupied at 61.60 GEL**. The camera eases back until the POS and the Vynic hub share the frame; the hub appears only once it is fully in frame. The capsule travels a V-angled connector into the hub. The Cloud record rises: "VYNIC CLOUD · VENUE RECORD / Demo Bistro": MENU, TABLES & ORDERS, SALES LEDGER. At the dock, TABLES & ORDERS shows **✓ 20:41**. The POS total reappears (it keeps its copy). Connectors then draw toward Manager and the websites. |
| **Text** | "02 · VYNIC CLOUD" / "One restaurant record behind every surface." |
| **Sound** | Chord moves to Bm7. A deep swell. A soft glide with the capsule. The dock chime. |

## Scene 4: Manager, Dashboard → Inventory

**10.40 – 16.40s**

All of this happens on one phone, a faithful rebuild of the current Manager in its light theme. The real app is written in Georgian; its labels are translated to English here.

| | |
|---|---|
| **Handoff** | **10.45** A capsule, "TABLE 4 · 61.60 GEL", leaves the record. The camera follows it along the connector, and it lands on the **revenue card** (11.85). |
| **A. Dashboard** | The real layout: greeting with the notification bell, Active business day, Active shift revenue (closed and open tables), and the Inventory summary card. **12.00:** a **pull to refresh**, the Manager's own update mechanism. Manager reads the Cloud; it is not a live mirror. **12.45:** revenue 2,868.65 → **2,930.25**, Open tables (2) → **(3)**, open value 1,586.20 → 1,647.80. |
| **Transition** | **13.15** Tap "Open →" on the Dashboard's Inventory card, the real path to the Inventory tab. **13.35** The Dashboard steps out, Inventory steps in, and the navigation pill moves to Inventory. |
| **B. Inventory** | The real Inventory home: "+ New receiving"; Received today 0.00; the **Low stock: 2** warning chip; Daily work (Receiving history · Stock balances · Payments & debt); Today's receipts.<br>**14.30** Tap "New receiving".<br>**14.45** The receiving review step: supplier Old Town Mill; payment "Not paid yet"; "Will be added to stock: Flour **+20.000 kg**"; Receiving value 30.00; Paid now 0.00; **Debt 30.00 GEL**, which is briefly highlighted.<br>**15.30** "Confirm receiving".<br>**15.95** Back on Inventory: Received today 0.00 → **30.00**, Low stock **2 → 1** (Flour is no longer low), and the receipt **"Old Town Mill · Added to stock · 1 item · 30.00 GEL"**. |
| **Colours** | Manager light tokens: background `#E3EDFC` / `#DCE8FB`, surface `#FFFFFF`, border `#C7D9F5`, ink `#0F172A`, muted `#475569` (darkened from `#64748B` for legibility), primary `#2563EB`, warn `#F59E0B`, good `#10B981` (text `#047857`). |
| **Text** | "03 · MANAGER" / "The business day, synced from the floor." Then "03 · MANAGER · INVENTORY" / "Goods received. *Stock and supplier debt follow.*" |
| **Sound** | Chord moves to Em9, then A-sus for Inventory. One restrained handoff swell and glide, with a soft low land on the revenue card. A chime when the figures land. A barely-there tick on "Open". One quiet two-note cue on "Confirm receiving" and a soft chime as stock and debt update. |

## Scene 5: same menu, SaaS → CUSTOM

**16.40 – 21.20s**

| | |
|---|---|
| **What you see** | The camera travels to the websites. A pulse runs from the record's MENU line into a browser, and the Vynic-hosted SaaS page (paper, Noto Serif) fills its menu. **18.10:** plum markers and a "MENU · VYNIC CLOUD" tag mark the menu as Cloud data. **18.55:** the **Khachapuri** row lifts out of the page as a card. **19.00–20.10:** a lavender scan line changes the page underneath to the bespoke CUSTOM build (dark `#0A0A0A`, gold `#AE895E`, Cormorant Garamond, "Dinner in the *Old Town*"). **19.75:** the lifted card changes its own style from paper to dark and gold. **20.25:** it settles into the custom menu exactly where its row is. The URL changes to "custom domain", the tag changes to CUSTOM · BESPOKE BUILD, and the SaaS site turns in behind (20.40). |
| **Text** | "04 · WEBSITES" / "Same menu. *A Vynic site or a custom build.*" |
| **Sound** | Chord moves to Gmaj9. Soft air as the dish lifts. A long swell under the scan. A G5 chime as the dish settles. |

## Scene 6: One Vynic

**21.20 – 25.00s**

| | |
|---|---|
| **What you see** | The camera pulls back to four things: the POS with Table 4 occupied, the Vynic hub, Manager still showing Inventory, and both websites. There are no labels and no diagram boxes; one light pulse travels each connector. **22.65:** everything folds into the V (0.6s, `power3.in`), and the camera returns to the mark. **23.40:** "Vynic" comes into focus. **23.70:** "Restaurant operations, connected." The frame holds, with a barely perceptible push, until 25.0. |
| **Lockup** | Wordmark on screen for about 1.6s, the full lockup settled for about 1.1s. |
| **Website version** | Fades to the empty stage from 24.25, so the loop is clean. |
| **Sound** | Resolves to D with a swell. A rising air into the fold. A restrained low impact plus a soft D5 · A5 · F#6 chime at the lockup. |

---

**Inventory truth:** the film shows only implemented features:

- Receiving with a supplier, goods and a payment choice.
- The review summary (stock added, value, paid now, debt).
- The posted "Added to stock" state.
- The received-today total.
- The low-stock warning.
- The Payments & debt destination.

**Not shown**, because it is not implemented: stocktake or physical count, location transfers, waste or internal consumption, purchase-order fulfilment, and production batches.

**Tagline candidates:** "Restaurant operations, connected." (used) · "One restaurant. One connected system." · "From the floor to the web."
