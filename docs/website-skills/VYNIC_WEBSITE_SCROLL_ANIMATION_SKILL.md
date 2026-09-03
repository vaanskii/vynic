---
name: vynic-website-scroll-animation-skill
description: Scroll animation and interaction rules for the Vynic public product website.
---

# Vynic Website Scroll Animation Skill

## Motion Goal

Motion should make restaurant workflows understandable. Every animation must communicate a sequence, a state change, or product hierarchy.

Use motion for:

- Revealing the product screen after the value prop.
- Moving through the service flow.
- Showing guest reservation to POS arrival.
- Comparing POS and manager mobile views.
- Making table availability feel alive without becoming distracting.

Do not use motion as decoration.

## Motion Stack

- Motion for basic reveal, hover, active, and in-view transitions.
- GSAP ScrollTrigger for pinned sections and horizontal screen tours.
- CSS transitions for small hover/focus states.
- Respect `prefers-reduced-motion` everywhere.

Do not use:

- React state tied to scroll position.
- `window.addEventListener("scroll")` for animation.
- Animation of layout properties like width, height, top, or left.
- Infinite animations on every card.

## Required Animation Sections

### 1. Hero Entrance

What it communicates: Vynic is the operational center.

Behavior:

- Headline and CTA fade/slide in once.
- Product screen enters slightly after copy.
- Screen frame can have a subtle y transform.

Reduced motion:

- Render static with no delay.

### 2. Horizontal Screenshot Tour

What it communicates: one product covers the whole service workflow.

Screens in order:

1. Floor plan.
2. Order entry.
3. Reservation list.
4. Payment flow.
5. Manager mobile.

Behavior:

- Pin the section when it reaches the top.
- Horizontal track moves as user scrolls vertically.
- Each screen has a short caption below or beside it.

Rules:

- Use GSAP ScrollTrigger.
- `start: "top top"`.
- `pin: true`.
- `scrub: 1`.
- End distance equals track width minus viewport width.
- No more than one horizontal pan section on the page.

Reduced motion:

- Render the screens as a vertical list.

### 3. Reservation Sticky Stack

What it communicates: the customer website connects to POS operations.

Cards:

1. Guest selects date, table, and time.
2. Guest adds preorder items.
3. Guest pays BOG deposit.
4. Staff sees the reservation in Vynic.

Behavior:

- Sticky stack where previous cards shrink and fade slightly as the next card arrives.
- Use real website/POS screens when possible.

Rules:

- Use GSAP ScrollTrigger only in a client-side component.
- Clean up triggers on unmount.
- Last card is not pinned.

Reduced motion:

- Render cards as normal stacked sections.

### 4. Floor Plan State Reveal

What it communicates: table state is live and visual.

Behavior:

- On in-view, table groups reveal with a small stagger.
- Use actual app colors or neutral labels.
- Do not invent status dots outside the floor screen.

Reduced motion:

- Show the final floor state instantly.

### 5. CTA Interaction

What it communicates: buttons are tactile and reliable.

Behavior:

- Hover: subtle lift or background shift.
- Active: small press transform.
- Focus: clear outline.

Rules:

- Button text remains on one line on desktop.
- CTA label stays `Book a Demo`.

## Motion Timing

Recommended:

- Reveal duration: 0.45s to 0.7s.
- Easing: cubic-bezier(0.16, 1, 0.3, 1).
- Stagger: 0.04s to 0.08s.
- Hover transition: 150ms to 220ms.

Avoid:

- Long cinematic delays before content becomes readable.
- Motion that blocks scrolling.
- Parallax on every image.

## Performance Rules

- Animate only transform and opacity.
- Reserve image dimensions to avoid layout shift.
- Lazy-load below-the-fold media.
- Do not apply noise or blur filters to scrolling containers.
- Test mobile scrolling on a real narrow viewport.

## Accessibility Rules

- Respect reduced motion.
- Do not hide essential content until animation completes.
- Keyboard users must reach all CTAs and form fields.
- Focus states must not be removed by custom styles.

## Acceptance Checklist

- Motion has a reason in every section.
- Reduced-motion fallback exists.
- No scroll listeners in React state.
- Horizontal tour works on desktop and becomes vertical on mobile/reduced motion.
- Sticky stack does not trap scrolling.
- No animation causes content overlap.
- No animation changes layout dimensions.
