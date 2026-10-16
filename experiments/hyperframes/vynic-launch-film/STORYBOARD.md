---
format: 1920x1080 (16:9), 30 fps
duration: 60.0s
language: ka (Georgian narration and UI)
arc: The system starts → POS service → one restaurant foundation → Manager (day + Inventory) → online (SaaS → Custom) → one ecosystem → lockup
mode: autonomous
audio: separate stems (music, sfx); no narration
status: v2: on-screen Georgian captions replace the voice-over and scene tags (CAPTIONS_GE.md)
---

# Vynic launch film: storyboard (v2, 60.0s)

> **v2 changes:**
> - Narration and the small scene tags are replaced by on-screen Georgian captions in a left column; the text is in `CAPTIONS_GE.md`.
> - Products sit right of that column: POS at 0.78–0.82, Manager phone and both sites shifted right, sites at 0.85.
> - Site addresses are `pikali.vynic.ge` and `vankisi.vynic.ge`.
> - The lockup line is "რესტორნის მართვის ერთიანი სისტემა".
> - The Voice column below is historical.

## Shape of the film

- **One world, one camera, no cuts.** It is a single 6200×2700 world. The product film's language returns: the V geometry, plum light, the 44px grid, lavender connectors turning at the V's angle, data capsules, and depth arrivals.
- **Continuity joins between scenes:**
  - The V's stroke traces the POS terminal.
  - Table 4's total becomes a capsule that travels to the V, and a second capsule lands on Manager's revenue card.
  - A line pulse carries the menu to the website.
  - One dish card travels from the SaaS site into Vankisi.
  - Everything folds into the V at the end.
- **Scene tags:** short Georgian tags at top-left (screen space) make the muted web version readable.

| # | Time | Scene | Voice |
|---|---|---|---|
| 1 | 0.0–6.0 | The system starts | vo-01 1.9 |
| 2 | 6.0–18.2 | POS service | vo-02 6.6 · vo-03 12.8 |
| 3 | 18.2–24.3 | One restaurant foundation | vo-04 19.3 |
| 4 | 24.3–38.6 | Manager: Dashboard → Inventory | vo-05 27.7 · vo-06 31.4 |
| 5 | 38.6–52.7 | Online: SaaS → Custom (Vankisi) | vo-07 40.2 · vo-08 45.6 · vo-09 49.2 |
| 6 | 52.7–56.8 | One ecosystem | vo-11 53.7 |
| 7 | 56.8–60.0 | Lockup | vo-12 58.5 |

---

## 1 · The system starts (0.0–6.0)

- **What you see:**
  - A point of light, then the V's thick and thin strokes draw in lavender.
  - The grid opens from the centre, and "Vynic" comes into focus.
  - Light travels through the V and turns it white.
  - **2.4:** the outline of a restaurant floor (tables drawn in hairline) surfaces around the mark.
  - **4.4:** the camera begins to move. The thick stroke keeps going along its own axis, reaches a terminal's top edge, and traces the whole terminal in two directions (4.45–5.55).
  - **5.3:** the traced outline fills in and becomes the Vynic POS on its stand.
- **Motion:** push-in 1.0 → 1.06 (`sine.inOut`), strokes `power2.inOut`, camera travel 1.6s `power3.inOut`.
- **Sound:** atmospheric shimmer and pad; a spark chime; soft stroke draws; a low bloom under the wordmark; a faint rising tone with the trace.

## 2 · POS service (6.0–18.2)

The real Georgian Windows POS, rebuilt from `pos-live-*.jpg` and `pos_strings.dart`.

1. **Floor plan:** header "Vynic POS | მაგიდები"; tabs მაგიდები · დათვლა · გატანები · რეზერვაცია; "SERVICE RIGHT NOW" tiles.
2. **7.1–7.6:** Table 4 gets focus, then is tapped.
3. **8.05:** the order editor opens ("შეკვეთის რედაქტირება · მაგიდა 4", "პროდუქტის ძიება...", categories, product grid).
4. **Items:** ხაჭაპური აჭარული (8.8), ქართული სალათი (9.5), ლიმონათი (10.2). The panel counts "ჯამი პროდუქტები (3) 42.00 · სერვისი (10%) 4.20 · სულ ჯამი 46.20 ₾".
5. **11.15:** "✓ შეკვეთის დადასტურება" is pressed and becomes "✓ სამზარეულოში გაიგზავნა".
6. **12.15:** back on the floor, Table 4 is occupied at 46.20 ₾ and the tiles update: available 6 → 5, occupied 1 → 2.
7. **13.2–18.2:** the camera steps back to show the terminal on its stand (a local application on the restaurant's device), and the Vynic mark returns beside it.

- **Tag:** "VYNIC POS · რესტორნის სერვისი — მაგიდიდან სამზარეულომდე".
- **Sound:** a soft table-select tick; a two-note confirmation bell; the operational pulse begins.

## 3 · One restaurant foundation (18.2–24.3)

1. Table 4's total becomes a capsule, "მაგიდა 4 · 3 პოზიცია · 46.20 ₾".
2. It crosses the terminal, runs along a lavender line into the V, and docks in the record "VYNIC · რესტორნის ჩანაწერი / ფიქალი". Rows: მენიუ · მაგიდები და შეკვეთები (✓ 20:41) · გაყიდვები (დახურვისას).
3. Lines then draw toward Manager and the website, and the MENU row sends a pulse toward the website.
4. **22.5:** a second capsule, "მაგიდა 4 · 46.20 ₾", leaves for Manager, and the camera follows it.

- **Tag:** "VYNIC · ერთი რესტორანი — ერთი საფუძველი".
- **Sound:** a capsule glide, a dock chime, and one restrained swell for the handoff.

## 4 · Manager: Dashboard → Inventory (24.3–38.6)

The Georgian Manager app in its light theme, rebuilt from `manager-android-dashboard.png` and the Inventory code.

**A. Dashboard**

1. "საღამო მშვიდობისა, ნინო"; business day "ღია · 2026-09-30"; "აქტიური ცვლის შემოსავალი ₾2,868.65"; closed/open split; cash and card tiles.
2. **24.8:** pull-to-refresh. **25.3:** the capsule's figure lands: ₾2,868.65 → **₾2,914.85**, and ღია (2) → **(3)**.
3. **28.0:** the dashboard scrolls to its Inventory card ("მარაგები · დღევანდელი შესყიდვები 0.00 ₾ · ⚠ დაბალი მარაგი 2").

**B. Inventory, on the same device**

1. **29.5:** "გახსნა →" on the Dashboard's Inventory card opens the Inventory tab.
2. **31.0:** "+ ახალი მიღება" opens the receiving review step:
   - supplier "ქალაქის წისქვილი";
   - payment "ნაწილობრივ გადავიხადე", 30.00 ₾ paid now;
   - "დაემატება მარაგში: ფქვილი +20.000 კგ";
   - value 60.00 ₾, paid now 30.00 ₾, **debt 30.00 ₾** (highlighted).
3. **33.3:** "მიღების დადასტურება". Received today 0 → **60.00 ₾**, low stock **2 → 1**, and the receipt "ქალაქის წისქვილი · მარაგში დაემატა · 1 პოზიცია · 60.00 ₾".
4. **35.3:** "ნაშთები" (stock balances):
   - ფქვილი 21.500 კგ (+20.000);
   - **ყველი სულგუნი 1.200 კგ · დაბალი მარაგი** (minimum 3 კგ);
   - კარაქი, ზეთი, ლიმონი.

- **Tags:** "VYNIC MANAGER · სამუშაო დღე, შემოსავალი, მაგიდები", then "VYNIC MANAGER · მარაგები · მიღება, ნაშთი და მომწოდებლის დავალიანება".
- **Sound:** a chime as the figures land; a barely-there tab change; one quiet two-note cue on "confirm receiving". The bed gets richer here (bass and an off-beat pulse).

## 5 · Online: SaaS → Custom (38.6–52.7)

1. **38.6:** the camera travels down to a browser, and a pulse arrives from the record's menu.
2. **The SaaS site** ("ფიქალი · Vynic-ის საიტი", restaurant-web classic theme, Georgian) is fully populated:
   - a photo hero "ფიქალი";
   - about ("სადილი, როგორც სახლში");
   - a menu in four categories: ხინკალი, ცომეული, სალათები და ცივი კერძები, სასმელები;
   - a four-photo gallery;
   - hours and contact.
3. It scrolls top to bottom (41.3), and then the visitor taps "მენიუ" in the header (43.9).
4. **46.5:** the **ხინკალი ქალაქური** row lifts out of the page as a card.
5. The camera follows it right (47.0–49.0). Mid-flight the card changes from the paper style to Vankisi's dark and gold.
6. The card settles into **Vankisi's own menu** (vankisi.com: "ხინკალი" category, a khinkali photo) exactly where its row is.
7. **50.3:** the page scrolls up to Vankisi's real hero: the gold logo, "გემოს უმაღლესი ხელოვნება", "ვანკისი" in its own logotype face, and "მაგიდის დაჯავშნა".

- **Tags:** "VYNIC SAAS · რესტორნის ვებსაიტი — მზად გამოსაყენებლად", then "CUSTOM · ვანკისი · ინდივიდუალური ფრონტენდი, იმავე საფუძველზე".
- **Sound:** no hats; a bell-like arpeggio; soft air as the dish lifts; a long morph swell; a settle chime.

## 6 · One ecosystem (52.7–56.8)

- The camera pulls back. The POS terminal, the V, the Manager phone (still on stock balances), and both websites, side by side at 72%, form one composition joined by the V-angled lines.
- One pulse runs each line. There are no labels and no diagram boxes.
- **Sound:** chords gather toward D; a pulse glide.

## 7 · Lockup (56.8–60.0)

- Everything folds into the V (0.6s, `power3.in`), and the tile dissolves.
- **57.6:** "Vynic" comes into focus (blur to sharp). **57.95:** "რესტორანი. ერთ სისტემაში." The narrator says "Vynic." at 58.5.
- A slow push-in follows, and the lockup is on screen for about 2.4s.
- **Sound:** the pulse stops; a rising air; a restrained low impact (A1) and a D5 · A5 · F#6 chime; a resolved D chord.

---

**Final line options (the temporary line is used):**

1. **რესტორანი. ერთ სისტემაში.** (in use): "The restaurant. In one system."
2. **სერვისიდან ონლაინამდე — ერთი Vynic.**: "From service to online: one Vynic."
3. **ერთი რესტორანი. ერთი სისტემა.**: echoes line 11 exactly, so it would repeat the voice-over.
