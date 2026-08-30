---
name: vynic-website-visual-direction
description: Visual direction for the Vynic public website: modern restaurant operations, real screens, premium but practical.
---

# Vynic Website Visual Direction

## Design Read

This is a B2B hospitality product website for restaurant owners and managers. The visual language should be modern, confident, and operationally grounded. It should feel premium enough for a serious product demo, but practical enough for a restaurant manager during service.

## Visual Personality

- Clean operational confidence.
- Hospitality warmth without beige craft clichés.
- High-quality product screens, not abstract software illustrations.
- Strong contrast, restrained accent color, clear type hierarchy.
- Movement should feel like the restaurant floor coming alive.

## Palette

Use a neutral base with one accent.

Recommended light mode:

- Background: off-white cool neutral.
- Text: charcoal, not pure black.
- Surface: white with subtle cool-gray borders.
- Accent: deep green or cobalt blue.
- Warning/attention: use sparingly and only for real status states.

Recommended dark mode:

- Background: deep charcoal or zinc.
- Surface: elevated charcoal.
- Text: off-white.
- Accent: same hue as light mode, adjusted for contrast.

Avoid:

- AI-purple gradients.
- Beige/brass/espresso premium restaurant palette as the default.
- Pure black and pure white.
- Decorative glow around every button.

## Typography

Use a modern sans-serif with a professional product feel:

- Good choices: Geist, Satoshi, Cabinet Grotesk, Outfit, or a similar self-hosted family.
- Pair with a mono only for operational labels, totals, times, and table codes.
- Do not default to Inter unless the implementation already uses it.
- No random serif emphasis in headings.

## Layout Language

Use asymmetric layouts and product-led composition:

- Hero: left product message, right real POS screenshot or video still.
- Below hero: immediate proof strip with product capabilities, not logos.
- Main body: alternate between screenshot-led product sections, sticky story sections, and horizontal screen tours.
- Avoid three equal feature cards as the main section.
- Avoid putting page sections inside large floating cards.

## Screen Treatment

Vynic screens are the star. Treat screenshots like product evidence:

- Use real app screenshots from the POS and manager app.
- Show exact workflows: floor plan, order entry, payment, reservation assignment, manager dashboard, website booking.
- Put screenshots in stable aspect-ratio frames.
- Use thin borders and subtle shadows only where they separate the screen from the page.
- Do not overlay fake labels on screenshots.
- Do not crop so hard that the product cannot be understood.

## Imagery

Minimum image set:

- Hero product screen or app video still.
- Restaurant-floor lifestyle image or generated hospitality photograph.
- POS terminal context image.
- Online booking/reservation visual.
- Manager mobile screen.

If real assets do not exist yet, create placeholders with required filenames:

- `hero-pos-floor-plan.png` at 1600x1000.
- `screen-order-entry.png` at 1600x1000.
- `screen-admin-floor-editor.png` at 1600x1000.
- `screen-manager-mobile.png` at 900x1400.
- `screen-website-reservation.png` at 1600x1000.
- `restaurant-service-context.jpg` at 1600x1100.

## Components

Use these component families:

- Sticky navigation with language toggle and primary CTA.
- Hero with product screen.
- Product proof rows using compact facts.
- Horizontal screenshot tour.
- Sticky-stack story for "from guest booking to POS table".
- Feature bento with mixed visual cells.
- Testimonial or owner quote area, only if real quotes exist.
- Contact/demo form with clear states.
- Footer with product links, contact, and language switch.

## Accessibility

- All text must pass WCAG AA contrast.
- Product screenshots need useful alt text.
- The demo/contact form must have labels above inputs.
- All scroll animation must respect reduced motion.
- Keyboard focus states must be visible.

## Pre-Flight Design Check

- Hero fits initial viewport on desktop and mobile.
- CTA is visible without scrolling.
- No CTA text wraps on desktop.
- Desktop nav is one line.
- Every section has a distinct layout family.
- Screens are real or clearly listed as placeholders.
- No fake stats.
- No generic SaaS filler copy.
- One accent color across the whole site.
- One radius system across the whole site.
