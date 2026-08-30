---
name: vynic-website-screens-and-content
description: Page architecture, sections, screen list, and copy direction for the Vynic public product website.
---

# Vynic Website Screens And Content

## Site Structure

Start with a single-page marketing site. Add subpages only after the first version is visually strong.

Recommended anchors:

- `#product`
- `#floor-plan`
- `#reservations`
- `#manager`
- `#contact`

Optional future pages:

- `/product`
- `/reservations`
- `/manager-app`
- `/pricing`
- `/contact`

## Home Page Sections

### 1. Hero

Purpose: explain Vynic in one glance.

Headline direction:

- `Restaurant POS built for real service`
- Georgian version should be direct and owner-friendly, not literal marketing translation.

Subtext direction, max 20 words:

- `Run tables, orders, reservations, deposits, and manager visibility from one offline-first system.`

Primary CTA:

- `Book a Demo`

Secondary CTA:

- `See Screens`

Visual:

- Real POS floor plan screenshot or short silent product video.
- If no screenshot exists yet, reserve `hero-pos-floor-plan.png`.

### 2. Proof Strip

Purpose: show concrete operational coverage.

Use compact facts, not fake metrics:

- Offline service
- Business-day close
- Visual floor plan
- BOG deposits
- Manager mobile
- Audit trail
- Georgian UI

### 3. Floor Plan Section

Purpose: make Vynic feel different from ordinary POS software.

Content:

- Show the table layout editor and active POS floor.
- Explain that owners can model real floors, VIP rooms, walls, bars, stages, stairs, and multiple zones.
- Do not overpromise website support for all custom floors until the later table reference migration is complete.

Screen assets:

- `screen-admin-floor-editor.png`
- `screen-pos-floor-live.png`

Layout:

- Large product screenshot with two compact supporting details beside or below it.
- Use visual table/status colors only if they match the app.

### 4. Service Flow Section

Purpose: show the waiter workflow.

Story:

1. Open table.
2. Add menu items.
3. Send kitchen/bar items.
4. Close with cash, bank, or terminal context.
5. Keep history and reports aligned to the business day.

Screen assets:

- `screen-order-entry.png`
- `screen-payment-flow.png`

Avoid:

- Fake flow diagrams that invent screens.
- Promising inventory/payroll unless clearly future.

### 5. Online Reservations Section

Purpose: explain website to POS bridge.

Story:

Guest chooses a date, table, time, optional preorder items, and pays a deposit with BOG. The reservation lands in Vynic for staff to manage.

Supported API facts:

- `GET /api/menu`
- `GET /api/menu/:slug`
- `GET /api/tables`
- `GET /api/tables/availability?date=YYYY-MM-DD`
- `GET /api/tables/reservations?date=YYYY-MM-DD`
- `POST /api/tables/reservations`
- `POST /api/bog/create-order`
- `GET /api/bog/check-status/:orderId`
- `GET /api/bog/check-reservation-status/:reservationId`

Screen assets:

- `screen-website-reservation.png`
- `screen-bog-deposit.png`
- `screen-pos-reservation-list.png`

Copy direction:

- Be concrete: "Guests reserve a table online and pay a deposit."
- Avoid implying instant POS sync is guaranteed in every network state. The bridge depends on server/POS connectivity.

### 6. Manager Mobile Section

Purpose: show visibility and control.

Content:

- Live table and shift view.
- Reservations.
- Menu and order visibility.
- Manager actions through guarded endpoints.

Screen assets:

- `screen-manager-dashboard.png`
- `screen-manager-reservations.png`

Layout:

- Mobile screenshots should be large enough to read.
- Pair the phone with a POS screen to show the same restaurant state.

### 7. Local Fit Section

Purpose: make the Georgian restaurant fit unmistakable.

Content points:

- Georgian UI.
- GEL.
- Service fee.
- BOG e-commerce.
- TBC/BOG terminal context.
- Banquet/event packages.
- Close-day that matches late service.

Layout:

- Use a structured bento with mixed cells: one image, one screen, one text-led cell, one compact list.

### 8. Demo CTA

Purpose: collect lead details.

Fields:

- Name
- Restaurant name
- Phone
- Email
- Message

States:

- Empty state is just the form.
- Loading state disables submit and shows inline progress.
- Success state confirms that the request was sent.
- Error state says what failed and preserves entered values.

CTA label:

- `Book a Demo`

## Screenshot Capture Checklist

Capture these from the actual app before final build:

- POS role floor/table screen.
- POS role order entry/menu screen.
- POS role reservation assignment/list.
- POS role payment method flow.
- Admin floor-plan editor.
- Manager mobile dashboard/login or reservations view.
- Website reservation flow if one already exists.

Do not include secrets, real customer phone numbers, payment credentials, or private restaurant data in screenshots.

## Copy Voice

Use plain owner language:

- "Keeps service running when internet drops."
- "Your day closes when the restaurant closes."
- "Guests book online, staff see it in Vynic."
- "Draw the floor once, run service from it every day."

Avoid:

- "Seamless operations."
- "Revolutionize hospitality."
- "Next-generation platform."
- "Unlock your restaurant potential."
