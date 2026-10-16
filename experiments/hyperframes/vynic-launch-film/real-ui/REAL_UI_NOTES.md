# Vynic launch film: real-UI cut (43.0 s)

This version uses the **actual current POS and Manager UI**. It is not a hand-built imitation.

- **POS:** every screen is rendered from the app's own Flutter widgets (`apps/operations`), with synthetic demo data for the restaurant "ფიქალი".
- **Manager:** rendered the same way, with its API answered by a local mock client.
- **Websites:** the ready-made site and Vankisi are still the HTML rebuilds from the approved film.

Nothing in `apps/` was modified. The rendering ran in a scratch copy of the package, outside the repository.

## How the frames are made (`capture/`)

- **Test harness:** `pos_flow_capture_test.dart` and `manager_capture_test.dart` are `flutter test` harnesses. They pump the real screens, tap through them the way a user would, and save a PNG at each state.
  - POS: 1440×900 @2×.
  - Manager: 396×856 @3×, the exact size of the phone screen in the film.
- **Demo data:** `seed.dart` is the demo restaurant: menu, tables, a Georgian floor layout, an open table, two confirmed reservations, takeaways and saved menu counts.
- **Manager API:** `manager_api.dart` supplies demo API data through `http.runWithClient`, so no network or backend is used. The following states are real app behaviour driven through that mock:
  - pull-to-refresh changes ₾2,868.65 to ₾2,914.85;
  - posting a receiving changes "received today" to 60.00 ₾ and low stock from 2 to 1;
  - confirming a booking changes it from "მოლოდინში" (pending) to "დადასტურებული" (confirmed).
- **Clock:** `run.sh` runs the harness in a timezone where the clock reads about 21:00, so service happens at dinner time.
- **Overlay coordinates:** `*_rects.json` are the exact on-screen rects of the buttons and figures. The film places its tap, highlight and shared-element cues from them.
- **Fonts:** the harness loads the app's bundled Noto Sans Georgian. Some button labels have no font family and would use the OS fallback on a device. In the scratch copy only, those labels were given the bundled Georgian family so they don't render as boxes.

To re-capture, copy the package to a scratch folder, put these files in `test/capture/`, and run:

```bash
test/capture/run.sh test/capture/pos_flow_capture_test.dart
```

## What is shown

**POS:**
1. Floor, then Table 4.
2. The new order: quantity pad, then khachapuri, salad and lemonade go in, total 46.20 ₾.
3. The table view: occupied, with the real action list.
4. Back to the floor with Table 4 taken.
5. Then fast cuts:
   - დათვლა (saved menu counts);
   - გატანები (takeaways);
   - რეზერვაცია (confirmed bookings with pre-orders);
   - მართვის ცენტრი: staff, menu, day close.

**Manager (the real 6-tab app):**
1. Dashboard refresh; the revenue card expands to ₾2,914.85.
2. Tables.
3. Inventory, then a new receiving: flour 20 კგ × 3 ₾, partial payment 30.00 ₾, 30.00 ₾ left; the stock and debt cards expand; saved.
4. Stock balances.
5. Reservations: a pending booking from the website is opened and confirmed ("დადასტურება").

## Deliberately left out

- **"Vynic AI პროგნოზი" card:** hard-coded placeholder text in the current dashboard, not a real forecast. The dashboard is framed below it, and the captured pull frame that scrolls up to it is replaced by the app's refresh spinner drawn as an overlay.
- **Unbuilt features:** stocktake, transfers, waste and production.
- **Claims:** no realtime, offline, or "zero loss" claims.
