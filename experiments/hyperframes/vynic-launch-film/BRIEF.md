---
workflow: general-video
flow: automation
storyboard: no
message: "Vynic is one connected restaurant platform: the POS runs service, Manager reads the day and runs inventory, and the same restaurant goes online as a Vynic SaaS site or a bespoke Custom build."
destination: launch (YouTube, launch post, sales presentation, customer demo intro)
aspect: 1920x1080
language: ka
length: 60s
---

# Brief: official Vynic launch film (v1)

## Intent

This is a 60 s Georgian-narrated launch film about one restaurant using Vynic: operation → management → inventory/business visibility → online presence → one ecosystem.

It is a new composition. The 25 s product film (`../vynic-product-film/`) stays as the website-hero candidate, and this film reuses its visual language (V geometry, plum, camera, capsules, connector lines, sound identity).

## Assets

- **Brand:** Vynic mark geometry (`tools/brand/`), POS and Manager tokens, platform-web plum.
- **Real UI references:**
  - `apps/platform-web/src/assets/pos-live-*.jpg` and `manager-android-dashboard.png` (the real Georgian POS and Manager);
  - `apps/restaurant-web` classic theme (SaaS);
  - `apps/vankisi-custom-web` (Custom).
- **Photography:**
  - Vankisi's own photos, used only inside the Vankisi site;
  - Vynic's own marketing interior photo (`restaurant-service-context.png`), cropped for the synthetic SaaS restaurant.
- **Fonts:** Geist, Geist Mono, Noto Sans Georgian (the POS/Manager app font), Noto Serif Georgian (the SaaS theme), Vankisi's own header font (the Vankisi logotype only).

## Truth constraints

- The POS is shown as a local application on the restaurant's device. There is no "offline", "zero data loss" or "100%" claim, and no multi-POS coordination.
- There is no card authorisation or acquiring.
- Manager reads Cloud data through its real pull-to-refresh; it is not a live mirror.
- Inventory shows only implemented features:
  - receiving with a supplier and a partial payment;
  - the review summary;
  - the posted receipt;
  - received today;
  - the low-stock warning;
  - stock balances.
- There is no stocktake, transfer, waste or production.
- SaaS and Custom read the same restaurant foundation. Custom is a separate, bespoke frontend; nothing says it is automatic. Vankisi is shown as a real example of a Custom build.
- There is no subscription billing and no ranking claim.
- POS, Manager and SaaS data is synthetic: restaurant "ფიქალი", waiter/manager "ნინო", supplier "ქალაქის წისქვილი".
