# Vynic launch film: on-screen Georgian captions

The film has **no narration**. The story is told by on-screen Georgian captions over music and SFX, so the muted website version reads fully on its own.

- **Layout:** captions sit in a left column (x = 112px) over a soft dark gradient, and the product sits to the right. The ecosystem line sits bottom-left.
- **Structure:** each caption has three parts:
  - an eyebrow: a scene number and name;
  - a headline in Noto Sans Georgian, 56px, semibold;
  - one supporting line, 24px.
- **Tone:** the text is formal ("თქვენ"), factual, and describes only what is on screen.

| # | Time (s) | Eyebrow | Headline | Supporting line | On screen |
|---|---|---|---|---|---|
| 01 | 6.3–12.6 | 01 · სალარო | მაგიდიდან სამზარეულომდე | აირჩიეთ მაგიდა, დაამატეთ კერძები და შეკვეთა სამზარეულოში გაგზავნეთ. | Table 4 → order editor → three items → confirm → table occupied |
| 02 | 19.3–22.7 | 02 · ერთი სისტემა | მონაცემები ერთ ადგილას | შეკვეთები, გაყიდვები და მენიუ რესტორნის ერთიან ჩანაწერში ინახება. | The order capsule docks into the V; the restaurant record |
| 03 | 24.2–29.45 | 03 · მენეჯერი | რესტორანი თქვენს ტელეფონში | დღის შემოსავალი, ღია მაგიდები და სამუშაო დღის მდგომარეობა. | Manager dashboard: pull-to-refresh, revenue, open tables |
| 04 | 30.1–38.4 | 04 · მარაგები | მიღებები და ნაშთები | მომწოდებლისგან მიღებული საქონელი მარაგს ემატება, გადაუხდელი თანხა კი დავალიანებად აღირიცხება. | Receiving from a supplier (30 ₾ paid, 30 ₾ debt) → stock balances |
| 05 | 40.2–46.6 | 05 · ვებსაიტი | მზა ვებსაიტი რესტორნისთვის | მენიუ, ფოტოები, სამუშაო საათები და კონტაქტი — იმავე სისტემიდან. | The ready-made site `pikali.vynic.ge`, scrolled end to end |
| 06 | 49.3–52.65 | 06 · ინდივიდუალური ვებსაიტი | თქვენი ბრენდის დიზაინით | ინდივიდუალურად შექმნილი საიტი, რომელიც იმავე Vynic-ის სისტემაზე მუშაობს. | The dish card lands in Vankisi's custom site `vankisi.vynic.ge` |
| 07 | 54.0–56.55 | — | სალარო. მენეჯერი. ვებსაიტი. | — | The whole ecosystem |
| Lockup | 57.6– | — | Vynic | რესტორნის მართვის ერთიანი სისტემა | Logo and wordmark |

**English meanings, for review:**

1. **01:** "From table to kitchen": choose a table, add dishes and send the order to the kitchen.
2. **02:** "Data in one place": orders, sales and the menu are kept in the restaurant's single record.
3. **03:** "The restaurant on your phone": the day's revenue, open tables and the state of the business day.
4. **04:** "Receiving and stock": goods received from a supplier are added to stock, and the unpaid amount is recorded as debt.
5. **05:** "A ready-made website for the restaurant": menu, photos, opening hours and contact, from the same system.
6. **06:** "Designed for your brand": an individually built site that runs on the same Vynic system.
7. **07:** "POS. Manager. Website."
8. **Lockup:** "Unified restaurant management system". This replaces the earlier temporary line "რესტორანი. ერთ სისტემაში.".

**Claims check:**
- There are no realtime, offline, "zero loss", "best" or "#1" claims.
- Custom is described as individually built, never as automatic.
- No capability that is not in the product is shown or named.

**Site addresses:**
- The ready-made site shows `pikali.vynic.ge`: one label under `SAAS_WEBSITE_BASE_DOMAIN=vynic.ge`, per `docs/DEPLOYMENT.md`.
- The custom site shows `vankisi.vynic.ge`: the `CUSTOM_HOST` in `.env.production.example`.
