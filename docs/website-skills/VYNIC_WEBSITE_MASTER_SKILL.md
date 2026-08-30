---
name: vynic-website-master-skill
description: Build the public product website for Vynic, a restaurant POS with offline-first service, floor plans, reservations, payments, and manager visibility.
---

# Vynic Website Master Skill

## Product Read

Vynic is a restaurant POS system for Georgian-style restaurant operations. The product is strongest where real service gets messy: offline shifts, table state, late close-day, banquet reservations, floor plans, Georgian payment habits, and manager visibility.

The website is a product marketing site for restaurant owners and operators. It should sell confidence: service keeps moving, staff can learn it quickly, managers can see the floor, and guests can reserve/pay from the restaurant website.

## Audience

- Restaurant owners deciding whether Vynic can run daily service.
- Managers who care about table state, staff control, reports, reservations, and mobile visibility.
- Restaurant groups who may later need multi-venue support, but the current product is single-restaurant.
- Georgian operators who care about GEL, BOG/TBC payment context, Georgian language, service fee, banquets, and non-fiscal close.

## Core Selling Points

1. Offline-first POS service: orders, printing, table state, and close-day keep working without internet.
2. Real business day: the POS day ends when the restaurant closes, not at midnight.
3. Visual floor plan: tables, VIP zones, walls, bars, stages, stairs, rotations, and multi-floor layouts.
4. Online reservations with deposits: guests can choose tables, preorder items, and pay through BOG.
5. Manager mobile app: live table/reservation/order visibility and limited remote control through the server/POS bridge.
6. Audit trail: discounts, cancellations, removed items, and staff actions are traceable.
7. Georgian operational fit: Georgian UI, GEL pricing, banquet packages, BOG e-commerce, TBC/BOG terminal awareness, service fee.

## Current Product Constraints

- Do not market Vynic as full SaaS yet. SaaS/venue tenancy is a later phase.
- Do not promise multi-venue management as live unless it is explicitly labeled future.
- Do not promise QR ordering, loyalty, delivery integrations, inventory, payroll, or warehouse management as live.
- Online website reservations currently use server table codes. Custom floor support for website reservations becomes cleaner after the later `tableRefs` migration.
- The current public API supports menu, table availability, reservations, BOG payment creation/status, website user auth, and admin-only reservation views.

## Website Goal

Create a modern, memorable website that makes a restaurant owner understand the product in under 30 seconds:

- "This runs my floor."
- "It keeps working during service."
- "My manager can see what is happening."
- "Guests can reserve online and pay a deposit."
- "It is built for the local restaurant reality."

## Design Dials

- `DESIGN_VARIANCE: 7` - polished, asymmetric, not chaotic.
- `MOTION_INTENSITY: 6` - visible scroll storytelling, but not distracting.
- `VISUAL_DENSITY: 5` - enough operational detail to feel real, still readable.

## Recommended Stack

- Next.js or React with Vite if the project is standalone.
- Tailwind for styling.
- Motion for reveal, hover, and small transitions.
- GSAP ScrollTrigger only for pinned scroll sections and horizontal screenshot pans.
- Phosphor, Tabler, or Radix icons. Use one icon family only.
- Bilingual content structure from the start: Georgian and English.

## Hard Design Rules

- Use real screenshots from Vynic where possible. Do not build fake dashboards from div blocks.
- If screenshots are not captured yet, reserve explicit placeholder slots with dimensions and filenames.
- No generic SaaS language like "revolutionize", "seamless", "next-gen", or "unleash".
- No fake metrics. Use only real facts from the product or clearly mark sample data.
- No claims that imply behavior not present in the app.
- Every CTA intent uses one consistent label. Recommended primary CTA: `Book a Demo`.
- Website must work beautifully on mobile because owners will open it from messages.

## Primary Navigation

- Product
- Floor Plan
- Reservations
- Manager App
- Contact

Keep desktop nav on one line and under 80px tall.

## Main Conversion

Primary: `Book a Demo`

Secondary: `See Screens`

Use `Book a Demo` consistently in nav, hero, and footer. Do not rotate between similar labels.
