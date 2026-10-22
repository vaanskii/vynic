---
workflow: general-video
flow: automation
storyboard: no
message: "Vynic runs the restaurant on the POS and connects one restaurant foundation to Manager and to SaaS or custom websites."
destination: website-hero
aspect: 1920x1080
language: en
audience: restaurant owners and operators evaluating Vynic; launch/showcase viewers
length: 25s
angle: product-principle film — show the product working, not floating screenshots
---

## Intent

A premium 10–15 second Vynic product film for the website hero, launch and
social showcase, and later scroll-linked website use. It must explain the
product: the Windows POS runs restaurant service; Cloud connects and
synchronises the appropriate data; Manager reads it; SaaS and CUSTOM websites
are different frontends over the same restaurant foundation. Feel: premium,
precise, technical, fast, controlled, modern, high-end. Not gaming, cyberpunk,
neon, AI-template, overly glassy, cartoonish or busy.

Scene beats requested (adapted to real UI): 1 system awakens (mark built from
its own forms) → 2 POS runs service (table → order → item → total) → 3
connected data / Cloud → 4 Manager reads the result → 5 one restaurant menu in a
SaaS renderer, then a bespoke CUSTOM renderer → 6 One Vynic, simplify to the
wordmark and a short statement.

## Assets

- tools/brand/vynic-manager.svg, tools/brand/generate_app_icons.py — V mark stroke geometry (POS mark = the two V strokes; Manager adds a stem).
- apps/operations/lib/core/ui/vynic_colors.dart, vynic_floor_tokens.dart — current POS palette and floor states.
- apps/platform-web/src/styles/index.css — public-site palette (same plum accent).
- apps/restaurant-web/src/styles/base.css — SaaS "classic" theme tokens.
- apps/vankisi-custom-web/src/index.css — reference for the bespoke CUSTOM register (dark, gold, serif); no Vankisi name/logo/content is used.
- apps/platform-web/src/assets/pos-live-floor.jpg, manager-android-dashboard.png — reference for faithful HTML rebuilds.

## Customizations

- Two deliveries: MASTER with original sound design (optional audio), WEBSITE silent.
- Review MP4 + website-oriented MP4/WebM; evaluate a transparent WebM.
- Storyboard written first as `STORYBOARD.md` (self-reviewed; the user reviews the rendered film, per the request to leave review renders ready).

## Notes

- Synthetic restaurant data only. No private customer data, no real venue names.
- Do not show planned functionality as released: no multi-POS coordination, no real-time Manager mirror (Manager catches up on sync), no AI analytics, no automatic CUSTOM deployment.
- No invented marketing claims. No official tagline exists; propose three, use the least risky.
- No copyrighted music. Sound is synthesised from code (original, deterministic).
- Keep the composition isolated from application code; do not commit.
