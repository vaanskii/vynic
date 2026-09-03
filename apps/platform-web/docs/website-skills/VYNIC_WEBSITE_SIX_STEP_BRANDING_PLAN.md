---
name: vynic-website-six-step-branding-plan
description: Track and implement the six-step Vynic website branding and motion pass without mixing the hero launch screen with POS product replicas.
---

# Vynic Website Six-Step Branding Plan

## Purpose

Use this plan when continuing the Vynic website branding and animation work. Complete one step at a time, verify it on desktop and mobile, then update the status before moving to the next step.

The motion should make Vynic feel like a restaurant operating system coming online. It should communicate readiness, service flow, and connected product states rather than add decorative movement.

## Non-Negotiable Separation

- The hero uses the standalone `ProductLaunchMenu` only.
- The hero launch screen must not transition into or reveal a POS floor/table replica.
- POS replicas belong to Product experience and later product-story sections only.
- Use the official logo from `src/assets/vynic-logo.png` for Vynic brand moments.
- Preserve `prefers-reduced-motion` behavior in every step.

## Progress

| Step | Focus | Status |
| --- | --- | --- |
| 1 | Hero power-up and branded loading menu | Complete |
| 2 | Product experience shift choreography | Complete |
| 3 | Floor plan state storytelling | Complete |
| 4 | Reservation journey motion | Complete |
| 5 | Manager and local-operations connection | Not started |
| 6 | Site-wide motion polish and final QA | Not started |

## Step 1 — Hero Power-Up And Branded Loading Menu

Status: **Complete — 2026-08-26**

Outcome:

- The hero visual is a dedicated launch component in `src/components/product/ProductLaunchMenu.tsx`.
- The official Vynic logo powers up inside a high-contrast branded device screen.
- The launch phrase is `Built for the rush.`
- The supporting state reads `PREPARING SERVICE`.
- Floor plan, reservations, and offline service rotate between `LOADING` and `READY` states.
- The launch menu remains visible and does not reveal the table screen afterward.
- The launch component is separate from `PosScreenReplica`, which remains available for Product experience.
- Desktop, mobile, reduced-motion behavior, production build, and browser console were verified.

Locked acceptance criteria:

- Do not reintroduce a table/floor screen into the hero.
- Do not replace the official logo with a text lettermark.
- Keep the launch copy short enough to remain readable in the device at mobile width.
- Keep the loading animation continuous but quiet; it must not delay access to hero copy or CTAs.

## Step 2 — Product Experience Shift Choreography

Status: **Complete — 2026-08-26**

Outcome:

- Desktop choreographs floor, active check, order editing, payment, and close-day as one pinned shift sequence.
- Progress, current step, and captions stay synchronized with screen transitions.
- Mobile uses a readable vertical story, while reduced motion renders the same product evidence without the pin or crossfade.
- Responsive GSAP cleanup prevents stale desktop triggers when the viewport changes.

Goal: make the Product experience section feel like one connected restaurant shift instead of a slideshow of unrelated screens.

Direction:

- Reuse the useful live POS state-change idea here, not in the hero.
- Choreograph floor, active check, order editing, payment, and close-day as a clear sequence.
- Make the current step, progress, and caption changes feel synchronized with the screen transition.
- Keep controls and product evidence readable while the section is pinned.
- Keep mobile as a clear vertical story and provide a static reduced-motion path.

Done when:

- The sequence is understandable without reading every paragraph.
- Scroll does not trap, jump, or leave overlapping screens.
- Product screens remain the focus; animation does not look like a generic carousel.

## Step 3 — Floor Plan State Storytelling

Status: **Complete — 2026-08-26**

Outcome:

- The floor plan section now contains a full-width interactive room editor modeled on the original Flutter workflow: palette placement, full-canvas grid, snapping, selectable grid step, 16:10 / 16:9 / 4:3 canvas presets, editable dimensions, selection, transform handles, inspector values, duplicate/delete, undo/redo, preview, and save state.
- The editor stays flexible about table count and uses the real room vocabulary — tables, walls, dividers, entrances, bars, stages, stairs, zones, and labels — instead of a fixed-number marketing claim.
- The Product experience section owns the larger live POS floor preview, where Table 8 moves through available, reserved, and occupied states.
- An adjacent English state rail stays synchronized with the product preview and explains what each state means for staff.
- Mobile keeps the live floor and explanation together in the Product section; the editor remains horizontally workable with the palette and inspector reordered below the canvas.
- Production build, desktop, mobile, interaction, and browser console checks passed.

Goal: show that Vynic runs a live room, not just a static table diagram.

Direction:

- Reveal table groups in operational order with a restrained stagger.
- Demonstrate one meaningful state change such as available to active or reservation arrival.
- Connect the state change to the nearby explanatory copy.
- Use actual Vynic status colors and labels only.

Done when:

- The floor reads immediately as restaurant operations.
- The animation explains a state change without creating fake product behavior.

## Step 4 — Reservation Journey Motion

Status: **Complete — 2026-08-29**

Outcome:

- The reservation story now carries one shared booking identity — Table 8, 20:30, 4 guests — through guest table selection, preorder context, and staff handling.
- A stage rail and per-card progress cue make the guest-to-staff handoff legible before reading the supporting copy.
- Desktop uses a cleaned-up GSAP handoff where completed cards settle back as the next card arrives; the active card remains fully readable.
- Mobile and reduced-motion paths keep the same sequence as normal stacked content without sticky or scroll-bound animation.
- Desktop, mobile, browser console, overflow, interaction, and production build checks passed.

Goal: make the path from guest booking to restaurant action feel connected.

Direction:

- Progress through table selection, preorder context, and staff handling.
- Refine the sticky stack so each step hands off naturally to the next.
- Use a shared visual cue to show that the same reservation is moving through the journey.
- Keep payment and connectivity claims within current product capabilities.

Done when:

- A restaurant owner can understand the reservation flow at a glance.
- Sticky behavior works without obscuring content or trapping mobile scrolling.

## Step 5 — Manager And Local-Operations Connection

Goal: connect the POS floor to manager visibility and Georgian restaurant reality.

Direction:

- Show a restrained handoff from an in-service POS state to the manager view.
- Bring Georgian UI, GEL, business-day close, local payment context, and offline readiness into the visual rhythm.
- Prefer coordinated highlights and state continuity over decorative floating cards.
- Keep this section calmer than the Product experience sequence.

Done when:

- The manager view feels connected to the same restaurant shift.
- Local operational details feel central to the product, not appended as feature badges.

## Step 6 — Site-Wide Motion Polish And Final QA

Goal: make the complete page feel like one intentional Vynic brand system.

Direction:

- Normalize reveal timing, easing, hover response, and section handoffs.
- Refine navigation, CTA feedback, footer arrival, and any remaining abrupt transitions.
- Remove redundant or decorative loops that compete with product storytelling.
- Check spacing, typography, contrast, focus states, reduced motion, and performance.

Done when:

- Desktop and mobile have a consistent rhythm from hero to footer.
- No animation causes layout shift, overlap, unreadable content, or scroll problems.
- Reduced-motion mode preserves all meaning and functionality.
- The production build passes and the browser console is clean.

## Working Rule For Every Next Step

Before editing, read this plan together with `VYNIC_WEBSITE_SCROLL_ANIMATION_SKILL.md`. After implementation, verify desktop, mobile, reduced motion, and the production build. Change only the active step's status; do not mark later steps complete in advance.
