# POS System Architecture

## System Overview

Backend (NestJS + Prisma + PostgreSQL) is the central hub between:

- POS Windows app (offline-first, operational truth)
- Mobile Manager app (realtime monitoring + limited mutations)
- Restaurant Website (customer reservations + menu)
- Kitchen / external devices (via POS callbacks)

---

## Core Principle

POS is the source of operational truth during service.

- POS can create / modify / close orders and tables
- All other clients must go through backend rules
- Backend ensures consistency and synchronization

---

## 1. POS Sync Layer (src/pos/)

Purpose: keep POS and server state aligned.

- Receives POS snapshots via `/sync/manager-data`
- Stores POS callback URL per device
- Writes snapshot into PostgreSQL

### Reverse sync (server → POS)

- `pos-callback.client` sends changes back to POS
- `pos-outbox.service` guarantees delivery with retries
- Works even if POS is temporarily offline

---

## 2. Mobile Manager API (src/mobile/)

Purpose: manager app control layer.

- JWT + MANAGER role protected
- Reads from PostgreSQL only
- Writes:
  - update DB
  - enqueue POS callback (never direct POS calls)

Modules:
- dashboard / financials
- reports
- orders (dine-in / takeaway / walk-in)
- reservations
- users
- menu
- devices

---

## 3. Realtime Layer (src/realtime/)

- Socket.IO gateway broadcasts:
  - order_updated
  - table_updated
  - data_updated (reservations: { type: 'reservations', action: 'created' | 'updated' | 'cancelled' })

- FCM push notifications for background users

Rules:
- echo-guard prevents self-notifications
- no business logic inside gateway

---

## 4. Website API (src/website/)

Purpose: customer-facing system.

- public menu
- authentication (cookie + CSRF)
- reservations
- payment integration (BOG)

Bridge:
- confirmed reservations → sent to POS via callback system

---

## Cross-cutting (src/auth/, src/shared/)

- JWT authentication (mobile + manager)
- API-key auth (POS sync)
- Prisma service layer
- shared utilities only (no business logic)

---

## Data Flow Rules

- POS → Server → PostgreSQL → Mobile/Web
- Mobile/Web writes → Server → DB → POS (via outbox)
- All realtime updates come from server only

---

## System Guarantees

- No direct Mobile → POS communication
- All POS updates are durable (outbox retry)
- Server is always source of truth outside live POS session
- Realtime is secondary, DB is primary