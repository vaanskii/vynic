---
name: vynic-website-build-prompt
description: Ready-to-run prompt for creating the Vynic product website from the website skill pack.
---

# Vynic Website Build Prompt

Use this prompt when starting the actual website implementation.

```text
Build the public product website for Vynic, a restaurant POS application.

Before coding, read:
- docs/website-skills/VYNIC_WEBSITE_MASTER_SKILL.md
- docs/website-skills/VYNIC_WEBSITE_VISUAL_DIRECTION.md
- docs/website-skills/VYNIC_WEBSITE_SCREENS_AND_CONTENT.md
- docs/website-skills/VYNIC_WEBSITE_SCROLL_ANIMATION_SKILL.md
- docs/VYNIC_PROJECT_PLAN.md
- docs/VYNIC_FEATURE_STRATEGY.md

Design read:
This is a B2B hospitality product website for restaurant owners and managers. It should feel modern, product-led, premium, and practical. The website must show real Vynic workflows: POS floor plan, order entry, reservations, manager mobile, and local Georgian restaurant fit.

Build goals:
- Create a polished single-page website first.
- Include responsive desktop and mobile layouts.
- Include dark and light mode tokens.
- Use real Vynic screenshots where available.
- If screenshots are unavailable, create explicit placeholder slots with required filenames and dimensions.
- Use Motion for simple reveal/hover transitions.
- Use GSAP ScrollTrigger only for one horizontal screenshot tour and one reservation sticky stack.
- Respect prefers-reduced-motion.
- Include a contact/demo form with loading, success, and error states.
- Use consistent CTA label: Book a Demo.

Do not:
- Do not change Vynic POS app behavior.
- Do not start SaaS or tenancy work.
- Do not promise multi-venue SaaS as live.
- Do not use fake metrics.
- Do not use generic SaaS copy.
- Do not hand-roll fake screenshots from div rectangles.
- Do not implement scroll animation with React state or window scroll listeners.

Recommended sections:
1. Hero with POS floor screen and Book a Demo CTA.
2. Proof strip with concrete product facts.
3. Floor plan feature section.
4. Horizontal screenshot tour.
5. Reservation sticky stack from guest website to POS.
6. Manager mobile section.
7. Local Georgian operations section.
8. Demo/contact CTA and footer.

Verify before finishing:
- Desktop and mobile screenshots.
- Reduced-motion mode.
- Dark and light mode.
- No text overlap.
- CTA visible in hero without scrolling.
- Nav stays on one line on desktop.
- No unrelated files changed.
```
