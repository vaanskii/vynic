# Vynic Sync Contract

**Status:** Approved  
**Decision date:** 2026-05-28  
**Mobile → POS strategy:** **Option A** — secured local HTTP ingest on Windows POS (server pushes callbacks)

This document is the single source of truth for how data flows between **Windows POS (Hive)**, **NestJS backend**, and **Mobile Manager App**. Implementation tasks reference this file.

Related: [ARCHITECTURE_REVIEW.md](./ARCHITECTURE_REVIEW.md)

---

## 1. Actors

| Actor | Runtime | Local store | Role |
|-------|---------|-------------|------|
| **Windows POS** | Desktop (Flutter) | Hive (`Vpos_Data_*`) | Operational source of truth for live service |
| **Backend** | NestJS + Prisma | PostgreSQL | Manager visibility, mobile API, event broadcast |
| **Mobile Manager** | Android/iOS (Flutter) | Hive (JWT + cache only) | Monitoring, limited mutations that must reach POS |

---

## 2. Source of truth (per entity)

| Entity | Authoritative during service | Authoritative after close / for history |
|--------|------------------------------|----------------------------------------|
| Open orders, table state, menu (live) | **Windows POS Hive** | Hive + pushed to server on sync |
| Reservations (active day) | **Windows POS Hive** | Same |
| Daily sales / X-report totals | **Windows POS Hive** (business date) | Server copy after sync |
| Audit reports (order-level) | **Windows POS Hive** | Server after audit sync |
| Manager dashboard aggregates | **Server** (derived from last POS push) | Server |
| Mobile cache | **Not authoritative** — display fallback only | — |

**Rule:** Waiters and POS UI never depend on network for reads/writes during service. Mobile may read server; when mobile **mutates** something that exists on POS, the change **must** be applied to Hive via Option A callbacks.

---

## 3. Sync directions

```text
                    ┌─────────────────┐
                    │  Mobile Manager │
                    │  REST + Socket  │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
         push       │  NestJS Backend │       WebSocket events
    ┌──────────────►│     (Prisma)    ├──────────────────────► Mobile
    │               └────────┬────────┘
    │                        │
    │   POST /sync/manager-data (POS → cloud)
    │   POST /sync/audit-reports
    │                        │
    │   HTTP callbacks (cloud → POS)  ◄── Option A
    │   posCallbackUrl + secured routes
    ▼
┌─────────────────┐
│  Windows POS    │
│  Hive (local)   │
└─────────────────┘
```

### 3.1 POS → Cloud (push)

- **Trigger:** App startup (after Hive ready), periodic failsafe, manual “Sync now”, login, close day, and (future) outbox worker after critical mutations.
- **Endpoints:** `POST /sync/manager-data`, `POST /sync/audit-reports`
- **Payload includes:** `posCallbackUrl` (see §4) so the server can reach this POS machine.
- **Must be authenticated** (device token / API key — see implementation todo `sync-3`).

### 3.2 Cloud → POS (callbacks) — Option A

When mobile (via backend) changes data that lives on POS, the server calls the Windows POS **local HTTP API** at `posCallbackUrl`.

- **Transport:** HTTP on LAN (e.g. `http://192.168.x.x:8081`)
- **Security:** Shared secret via header (e.g. `X-POS-API-Key` or `X-Connection-Key`); bind listener to LAN only; not exposed to public internet.
- **Failure:** Log on server and POS; optional retry queue on server; mobile sees result via existing socket events after server DB update.

### 3.3 Cloud → Mobile (realtime)

- Socket.IO (`MonitoringGateway`) for `order_*`, `table_updated`, `day_closed`, `audit_updated`, etc.
- Mobile may also poll or use `GET /sync/diff` (future optimization).

---

## 4. POS callback URL registration

On every successful `manager-data` sync, Windows POS sends:

| Field | Example | Purpose |
|-------|---------|---------|
| `posCallbackUrl` | `http://192.168.1.50:8081` | Base URL for server → POS HTTP calls |
| `posConnectionKey` (optional) | Server-stored secret | Validates callback requests |

Server stores these in `SyncController` (in-memory; refreshed each sync). If `posCallbackUrl` is missing, mobile-originated mutations update **server only** and **do not** reach Hive until URL is registered again.

**Implementation status:** the client now starts a minimal secured ingest server
from `PosIngestServer.start()` on desktop POS runs, stores its base URL in
`PosCallbackConfig.baseUrl`, and includes `posCallbackUrl` plus
`posConnectionKey` in `manager-data` sync. The backend persists that callback
URL/key and uses them for mobile/website-originated mutations that must reach
Hive. Keep route changes in sync with
`apps/operations/lib/core/services/sync/pos_ingest_server.dart` and
`apps/backend/src/pos/pos-callback.client.ts`.

---

## 5. Required POS HTTP routes (server → POS)

These paths are invoked by `apps/backend/src/pos/sync.controller.ts`,
`apps/backend/src/pos/pos-callback.client.ts`, and the mobile/website
services that call the callback client. Windows POS implements them in
`apps/operations/lib/core/services/sync/pos_ingest_server.dart`.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/mobile-order-update` | Apply item/total changes to Hive order |
| POST | `/mobile-order-cancel` | Cancel/delete order + cleanup tables |
| POST | `/mobile-order-status` | Update order status in Hive |
| POST | `/mobile-order-create` | Create takeaway (or remote) order in Hive |
| POST | `/mobile-walk-in-order-create` | Create table/walk-in order in Hive |
| POST | `/mobile-order-print-check` | Print an order/table check on POS printers |
| GET | `/mobile-reservations` | List reservations for mobile |
| POST | `/mobile-reservation-create` | Create reservation in Hive |
| POST | `/mobile-reservation-status` | Update reservation status |
| POST | `/mobile-reservation-delete` | Delete reservation |
| POST | `/mobile-reservation-print-check` | Print a reservation check on POS printers |
| POST | `/mobile-counted-menu-print` | Print a counted-menu draft on POS printers |
| POST | `/mobile-expense-create` | Record expense in Hive |
| POST | `/mobile-user-create` | Add staff user to Hive |
| POST | `/mobile-user-update-pin` | Update staff PIN in Hive |
| POST | `/mobile-user-update-role` | Update staff role in Hive |
| POST | `/mobile-user-rename` | Rename staff user in Hive |
| POST | `/mobile-user-delete` | Remove staff user from Hive |

Optional health: `GET /health` for reachability checks.

**Previous implementation reference:** Logic existed in deleted
`lib/core/services/pos_sync_server.dart`; the current replacement is
`pos_ingest_server.dart`, not full LAN peer sync.

---

## 6. What is explicitly out of scope for Option A

- **POS-to-POS LAN sync** (second terminal mirroring Hive) — not required; each PC has its own Hive unless product changes.
- **Mobile offline mutation queue** — separate future work; mobile still needs network to mutate.
- **Automatic conflict merge** — if POS and mobile edit the same order simultaneously, **last successful callback wins** on Hive until a version field is added (todo `sync-9` reduces table races only).

---

## 7. Security requirements (mandatory before production)

1. **Authenticate** `POST /sync/*` from Windows (todo `sync-3`).
2. **Do not send plaintext PINs** in `manager-data` staff array; provision/hashing on server only.
3. **Authenticate POS callback routes** (shared key, rotate via admin).
4. **Bind ingest server** to `0.0.0.0` or LAN IP only; firewall at restaurant edge.
5. **JWT** remains required for mobile REST and socket (existing).

---

## 8. Implementation roadmap (linked todos)

| Todo | Description |
|------|-------------|
| sync-2 | Wire `ManagerSyncService.initialize()` on Windows — done |
| sync-3 | Secure cloud sync + remove PIN from payload |
| sync-4 | Admin UI: last sync / error / Sync now |
| sync-5 | Fix mobile invalid-PIN sync call |
| sync-6 | SyncHub refresh or removal |
| sync-7 | Sync outbox + retry worker |
| **sync-8** | **Restore secured POS ingest server + `posCallbackUrl` in push — implemented; needs end-to-end LAN verification** |
| sync-9 | Table/order race guard |
| struct-1 | Split `DatabaseService` |

---

## 9. Acceptance criteria for Option A

- [x] Windows POS starts local ingest HTTP server on desktop POS runs.
- [x] `manager-data` includes `posCallbackUrl` and `posConnectionKey` when ingest is bound.
- [ ] Mobile order edit on backend results in updated Hive order on POS within callback timeout.
- [ ] Failed callbacks are logged; admin can see sync health (sync-4).
- [x] Callback routes require the connection key when one exists.
- [ ] Cloud sync endpoints require deployment-provided POS sync auth (sync-3).

---

*Approved strategy: **A** — Secured server → POS HTTP ingest. Pull-only (B) and monitoring-only (C) are rejected.*
