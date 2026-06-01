# Vynic

**Vynic** is a modern point-of-sale system for restaurants and cafes. It combines a fast **Windows POS** for staff at the counter, a **mobile manager app** for owners and supervisors, and a **NestJS** backend with real-time sync.

## Features

- **Windows POS** — menu, tables, orders, payments, receipts, service fee, counted menus
- **Mobile manager** — live tables, order editing, dashboard, finances, notifications
- **Real-time sync** — WebSockets between POS, mobile, and server
- **Offline-first** — local storage and sync when the connection returns
- **Backend** — NestJS, Prisma, JWT auth, REST + Socket.IO
- **UI** — Dark glass design on mobile; built for Georgian-language operations

## Stack

| Layer   | Tech                          |
|---------|-------------------------------|
| Client  | Flutter (Windows, Android)    |
| Server  | NestJS, Prisma, PostgreSQL    |
| Sync    | Socket.IO, local Hive storage |

## Repository layout

- `pos_app_client/` — Flutter app (Windows POS + Vynic Manager mobile)
- `pos_app_server/` — NestJS API and sync services