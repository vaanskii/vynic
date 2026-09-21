# Vynic — SaaS Readiness Audit

Investigation-only audit of the whole Vynic monorepo as of commit `156d095`
(branch `pos/admin-restyle-and-low-res-legibility`, 2026-09-11). No production
code, schema, migration or live database was changed. This document is the
master planning input for the next development phase.

Method: `docs/agent-state/VYNIC_PROJECT_STATE.md` → `VYNIC_CODE_MAP.md` →
`VYNIC_DECISIONS.md`, then every material claim was verified against code.
Where a document claims something the code does not prove it is marked
`DOC_ONLY / NOT_PROVEN`. Where code exists without a reachable UI:
`IMPLEMENTED_BUT_NOT_EXPOSED`. Where UI exists over incomplete backend behavior:
`UI_ONLY / PARTIAL`.

Validation performed during the audit (read-only):

| Suite | Result |
|---|---|
| `apps/backend` `npx jest` | 38 suites / 367 tests passed; **21 suites / 271 tests skipped** — every `*.integration.spec.ts` self-skips without `TENANT_INTEGRATION_DATABASE_URL` |
| `apps/operations` `flutter test` | 1253 passed, 3 skipped |
| `apps/platform-web` `vitest run` | 6 files / 21 tests passed |
| `packages/contracts` `generate.mjs --check` | ok (backend TS, Dart, Flutter re-export all in sync) |

Status vocabulary used below: `COMPLETE`, `PARTIAL`, `MISSING`, `LEGACY`,
`IMPLEMENTED_BUT_NOT_EXPOSED`, `UNSAFE`, `NOT_APPLICABLE`,
`BACKEND_EXISTS_UI_MISSING`. Priority: `P0` blocks safe multi-restaurant paid
launch; `P1` before serious customers; `P2` maturity; `P3` later.

---

## A. Executive Summary

Vynic today is a **strong single-restaurant system with a genuinely
multi-tenant data model and a partially built control plane**. It is not yet a
product a second paying restaurant can be onboarded onto without a developer.

What is proven in code:

- Venue-scoped PostgreSQL schema with server-owned tenant derivation for all
  four principals (Device→Venue, Staff→Venue, Host→VenueDomain→Venue,
  booking→Venue), with real two-Venue isolation integration tests
  (`apps/backend/src/tenancy/*.integration.spec.ts`).
- An offline-first POS with journaled, idempotent money closing, a durable
  per-Sale Cloud ledger in `Decimal(18,2)`, append-only audit, inventory
  quantity ledger, payroll and obligations — all Decimal and append-only.
- Edge pull transport (claim/lease/ack) with one-time Device enrollment codes,
  Argon2id verifiers, credential rotation and DISABLE/REVOKE lifecycle.
- A separate `PlatformUser` principal and an authenticated Platform Admin UI
  covering Organizations, Venues, plan/feature overrides, WebsiteMode, domains,
  enrollments, devices, credentials and a platform audit trail.

What blocks multi-restaurant rollout (verified, not doc-derived):

1. **Manager login is single-Venue.** `AuthService.mobileLogin` searches
   `Staff` only inside the hardcoded bootstrap Venue
   (`apps/backend/src/auth/auth.service.ts:48-53`). A second Venue's manager
   cannot obtain a token at all. The Manager product is therefore not
   multi-tenant today even though every authenticated Manager route is
   correctly Staff→Venue scoped.
2. **Cross-tenant realtime and notification leaks.** The WebSocket gateway
   puts every authenticated manager of every Venue into one `managers` room
   (`realtime/monitoring.gateway.ts:80,119`) and every sync broadcast goes to
   that room; `HybridNotificationService` writes every push notification and
   its deliveries against `LEGACY_MANAGER_TENANT`
   (`realtime/notifications/hybrid-notification.service.ts:79,90`).
   `GET /sync/diff` (manager-authenticated) reads bootstrap-Venue tables/orders
   regardless of the caller's Venue (`pos/sync/sync.controller.ts:75,81`).
3. **The "Cloud" backend is deployed on the restaurant's POS PC.**
   `apps/backend/DEPLOY.md` documents PM2 + local PostgreSQL on Windows at
   `10.10.10.4`. There is no hosted deployment configuration, no Dockerfile, no
   CI, no health endpoint, no documented PostgreSQL backup, and `PROJECT_STATE`
   itself lists production Cloud foundations as not established.
4. **Feature entitlement is three coarse keys.** `POS`, `WEBSITE`,
   `MANAGER_APP` are the only `Feature` rows seeded
   (`prisma/migrations/20260831160000_.../migration.sql:120-123`,
   `entitlements/feature-keys.ts`). Inventory, Payroll, Obligations,
   Profitability, Reservations and Audit are all bundled under `MANAGER_APP`.
   The Platform UI can toggle exactly those three.
5. **No Platform-side Staff bootstrap or reset.** Nothing in
   `apps/backend/src/platform/` touches `Staff`. The first manager of a new
   Venue exists only because the POS seeds a default `manager`/`000000`
   (`user_repository.dart:45-46`) and syncs it; there is no "reset manager
   access" path from Platform Admin.
6. **Printers and diagnostics require a Vynic developer token.**
   `AdminScreen.developerSections = ['errors','printers','connection','developer']`
   (`admin_screen.dart:70-75`) — a restaurant cannot configure its own
   printers, and the signing tool (`apps/devtool`) never ships to customers.
7. **Recoverable PINs.** Manager `/mobile/users` returns every staff member's
   plaintext `pinCode` from the Cloud vault (`mobile-users.service.ts:62-77`);
   POS Hive stores `User.pinCode` in clear (`core/models/user.dart:12`) in an
   unencrypted Hive store.

Overall SaaS readiness: **INTERNAL_BETA**. Single-tenant Vankisi production is
credible; a second restaurant needs developer involvement at onboarding, cannot
use the Manager app, and would share realtime/notification streams with the
first restaurant.

---

## B. Current Architecture

### Runtime map (verified)

| Component | Where | Authority | Persistence |
|---|---|---|---|
| POS (Windows/desktop Flutter) | `apps/operations/lib/apps/windows_pos/` | Owns live operation: tables, orders, close, printing, business date, menu, staff, settings | Hive (`core/database/database_core.dart`), unencrypted; Device credential in `edge_device.json` outside Hive |
| Manager (Android/iOS/desktop-client Flutter) | `apps/operations/lib/apps/mobile_app/` | Cloud-driven reads; mutations become Edge commands to the POS | Hive cache of API responses |
| Cloud backend (NestJS + Prisma) | `apps/backend/src/` | Tenant authority for every principal; ledger/inventory/finance system of record | PostgreSQL, schemas `pos` and `website` |
| Platform Admin | `apps/platform-web/src/platform/` under `/admin` | Cross-Venue operator | Bearer token in browser session |
| Vynic corporate site | `apps/platform-web/src/pages/HomePage.tsx` (`/en`, `/ka`, `/product`) | None (static marketing) | — |
| Venue website (Vankisi) | `apps/venue-web/` | Host→Venue via `VenueDomain` | Server-side; `vercel.json` SPA rewrite |
| Realtime | `apps/backend/src/realtime/` (socket.io) + FCM via `firebase-admin` | Manager JWT to join | In-memory presence; `ManagerNotification` rows |
| Edge transport | `apps/backend/src/edge/` ↔ `core/services/edge/` | Device credential | `EdgeCommand` queue; Hive `edge_command_journal` |

### Authority boundaries — confirmed

| Claim | Verdict | Evidence |
|---|---|---|
| POS critical operations are local/offline-first | **CONFIRMED** | `CloseTableTransaction`, `CancelOrderTransaction`, Hive closure journal; `EdgeDeviceCredentialStore.load` "never fails the boot" (`main.dart:128-130`) |
| Manager is Cloud-driven | **CONFIRMED** | Every `/mobile/*` route is `JwtAuthGuard + RolesGuard + FeatureGuard` over Prisma; mutations go through `PosCommandDispatcher` |
| Platform Admin is cross-Venue | **CONFIRMED** | `PlatformUser` has no `venueId`/`organizationId`; `PlatformAuthGuard` on every `/platform/*` route |
| Venue Website is Venue-scoped | **CONFIRMED** | `WebsiteTenantService.resolveByHostname` (`website/tenancy/website-tenant.service.ts`), fails closed in production |
| Device → Venue | **CONFIRMED** | `DeviceCredentialService.verifyCredential` returns `venueId` from the Device row; rejects `DISABLED/REVOKED` Device and `DISABLED` Venue |
| Staff → Venue | **CONFIRMED** (per request) | `JwtStrategy.validate` ignores token `role/username`; `ManagerTenantService.resolveByStaffId` re-reads Staff + Venue status each request |
| Host/VenueDomain → Venue | **CONFIRMED** | `VenueDomain.hostname @unique`, DISABLED domain resolves to nothing |
| PlatformUser separate | **CONFIRMED** | Separate audience `vynic-platform`, `typ` claim, `PlatformUser` subject lookup (`platform-auth.service.ts`) |

### Actual sync directions

| Direction | Mechanism | Status |
|---|---|---|
| POS → Cloud | `POST /sync/manager-data` full snapshot every 30 s (`manager_sync_service.dart:69`), `POST /sync/audit-reports` incremental with revision ACK, `POST /sync/audit-logs`, `POST /edge/inventory/consumption` | Edge-initiated; not feature-gated |
| Cloud → POS | `POST /edge/commands/claim` (10 s idle poll, 2 s drain, 5 min max backoff — `edge_transport_service.dart:53-55`) + `ack`; `GET /edge/inventory/catalog` pull | 17 real command types + NOOP, contract v2 |
| Cloud → POS (legacy) | LAN HTTP callback via `PosCallbackClient` + `PosCallbackOutbox` | `LEGACY`, frozen fallback for unenrolled Venue only |
| Manager → Cloud | HTTPS JWT | Mutations become Edge commands |
| Website → Cloud | HTTPS + cookie session | Bookings; POS bridge via `PosReservation` mirror |
| Platform Admin → Cloud | HTTPS Bearer | Control plane only |
| Cloud → Manager | socket.io `managers` room; FCM | **Not Venue-scoped** (see §F/§R) |

### Places the implementation still behaves single-restaurant

| Location | Behavior | Impact |
|---|---|---|
| `auth/auth.service.ts:48` | Manager PIN login searches only `BOOTSTRAP_VENUE_ID` | Venue B has no Manager access — **P0** |
| `realtime/monitoring.gateway.ts:80,119` | One `managers` room for all Venues | Venue B managers receive Venue A order/table/day-closed events — **P0** |
| `realtime/notifications/hybrid-notification.service.ts:79,90` | Notifications and deliveries pinned to bootstrap Venue | Venue B events push to Venue A managers; Venue B managers get nothing — **P0** |
| `pos/sync/sync.controller.ts:75,81` | `GET /sync/diff` reads bootstrap Venue tables/orders | Cross-tenant read for any manager; Flutter defines `getDiff` but no caller was found — **P1** (dead but reachable) |
| `pos/sync/pos-connection.registry.ts:35` | Restores one process-wide POS callback URL from bootstrap Venue | Legacy path; harmless once enrolled — `LEGACY` |
| `pos/pos-outbox.service.ts:37,287-353` | Outbox stats/retry hardcoded to bootstrap Venue | `LEGACY` |
| `shared/bootstrap/bootstrap.service.ts:37-41,110` | Seeds `WebsiteTable` mappings and reports menu status for bootstrap Venue on every boot | Other Venues get no website tables without manual work — **P1** |
| `website/tenancy/website-tenant.service.ts:18` | `BOOTSTRAP_WEBSITE_HOST = 'vankisi.localhost'` | Dev convenience; production fails closed — OK |
| `website/payment/payment.service.ts:11-12` | `BOG_CLIENT_ID/SECRET` process-wide | Second paying Venue would route money to Vankisi's merchant — **P0 if WEBSITE+payments sold**, otherwise `NOT_APPLICABLE` |
| `website/user/*`, `WebsiteUser.role = SUPER_ADMIN` seeded from `SUPER_ADMIN_*` env | A global website admin identity can read any Venue's full reservation list by targeting its host (`reservation.controller.ts:107`) | Third cross-tenant principal outside `PlatformUser` — **P1** |
| `database_service.dart:527-541` | `adoptLegacyVenueHeader` seeds Vankisi name/address/phone/legal id only for *existing* installs | Correct for fresh installs — OK |
| `user_repository.dart:45-46` | Default POS manager `manager`/`000000` on empty user box | Weak default credential on every new terminal — **P1** |

---

## C. Backend

### Module inventory

Controllers found: 16 (`grep @Controller`). Route counts: `mobile` 73,
`platform/venues` 24, `mobile/finance` 14, `website/*` 20, `edge` 5,
`sync` 5, `platform/*` 9, `auth` 1.

| Domain | Purpose | Authority / tenant key | Main models | Main endpoints | Consumers | Status | Gaps / risk |
|---|---|---|---|---|---|---|---|
| Auth (Manager) | PIN → JWT (24 h) | Staff row → `venueId` | `Staff` | `POST /auth/mobile-login` | Manager | **PARTIAL** | Bootstrap-Venue search only (**P0**); no refresh/revocation; per-IP throttle only (`LoginThrottleService`, in-memory) |
| Platform Auth | email/password → JWT (8 h) | `PlatformUser` | `PlatformUser`, `PlatformAuditEvent` | `POST /platform/auth/login`, `GET /platform/auth/me` | Platform Web | **COMPLETE** for one role | Single role `SUPER_ADMIN`; **no login throttle** (P1); first admin via CLI script only |
| POS Sync | Snapshot ingestion | `PosSyncGuard`: Device credential or legacy shared key → bootstrap Venue | `Table`,`Order`,`OrderItem`,`MenuCategory/Subcategory/Item/Variant`,`Expense`,`Staff`,`PosReservation`,`DailySnapshot`,`Setting`,`AuditReport/Event/EventLog`,`CloudSale*`,`SaleLedgerDay` | `POST /sync/manager-data`, `/sync/audit-reports`, `/sync/audit-logs`, `GET /sync/ping`, `GET /sync/diff` | POS | **COMPLETE** (Device path) / **LEGACY** (shared key) | Full-snapshot every 30 s; sequential upserts (2004 reservations ≈ 650 ms measured); `/sync/diff` cross-tenant |
| Edge | Command queue, inventory catalog, consumption upload, enrollment | `EdgeDeviceGuard` → Device → Venue | `EdgeCommand`, `Device`, `DeviceEnrollment` | `POST /edge/commands/claim|ack`, `GET /edge/inventory/catalog`, `POST /edge/inventory/consumption`, `POST /edge/enroll` | POS | **COMPLETE** | No Platform view of pending/failed backlog beyond the NOOP test command |
| Realtime | socket.io + FCM | Manager JWT to join | `ManagerNotification*`, `PushDevice` | WS gateway; `GET /mobile/notifications`, `POST /mobile/push/*` | Manager | **UNSAFE** for multi-tenant | Single room; bootstrap-Venue notifications |
| Manager/Mobile | Everything a manager reads/does | `@ManagerTenant()` from JWT-resolved Staff | (all above) | 73 routes under `/mobile` | Manager | **COMPLETE** (tenant) | Entire controller `@Roles(MANAGER)` + `@RequiresFeature(MANAGER_APP)`; no finer permission |
| Finance | Payroll, obligations, summary | Staff → Venue | `StaffCompensation`,`PayrollPeriod`,`PayrollAccrual`,`PayrollPayment`,`FinancialObligation`,`ObligationCycle`,`ObligationReserveEntry`,`ObligationPayment` | 14 routes `/mobile/finance/*` | Manager | **COMPLETE** | Gated only by `MANAGER_APP` |
| Inventory | Catalog, receiving, recipes, consumption, cost | Staff → Venue (Manager) / Device → Venue (POS) | `StockItem`,`Supplier`,`SupplierProduct`,`StockItemPurchaseUnit`,`Receiving`,`ReceivingLine`,`StockMovement`,`MenuConsumptionRecipe/Component`,`SaleConsumption*` | `/mobile/inventory/*` (24 routes), `/edge/inventory/*` | Manager, POS | **COMPLETE** for Steps 1–4.7 | Gated only by `MANAGER_APP` |
| Website/Public | Menu, tables, bookings, customer auth, BOG payments | Host → VenueDomain → Venue; booking → Venue for callbacks | `WebsiteUser`,`WebsiteTable`,`WebsiteReservation*` | `/api/menu`, `/api/tables/*`, `/api/auth/*`, `/api/user/*`, `/api/bog/*` | venue-web | **PARTIAL** | Global `WebsiteUser`; process-wide BOG creds; reservation race (no hold); no website login throttle |
| Venue/Org directory | Lifecycle | `PlatformAuthGuard` | `Organization`,`Venue` | `/platform/organizations/*`, `/platform/venues/*` | Platform Web | **PARTIAL** | Venue has only `name/timezone/currency/status`; no address/legal/branding/business-date settings in Cloud |
| Entitlements | Effective features | pure function over plan + overrides | `Feature`,`Plan`,`PlanFeature`,`VenuePlanAssignment`,`VenueFeatureOverride`,`VenueWebsiteConfig` | `/platform/venues/:id/product|plan|features/:key|website` | Platform Web, `FeatureGuard` | **COMPLETE** mechanism / **PARTIAL** coverage | Three keys only |
| Devices | Lifecycle, credentials, enrollment | `PlatformAuthGuard` | `Device`,`DeviceEnrollment` | 10 routes under `/platform/venues/:id/devices|enrollments` | Platform Web | **COMPLETE** | `lastSeenAt` written at most every 5 min |
| Domains | Hostname registry | `PlatformAuthGuard` | `VenueDomain` | 4 routes | Platform Web | **COMPLETE** | DNS/TLS not modelled (by design) |
| Settings | Per-Venue key/value | Venue | `Setting` (`@@id([venueId,key])`) | via sync + `/mobile/restaurant-settings` | POS, Manager | **PARTIAL** | Cloud is a mirror; POS is authority; no Platform read/write |
| Legacy callback | LAN reverse push | bootstrap Venue only | `PosCallbackOutbox` | none public | Dispatcher fallback | **LEGACY** | Frozen (`LEGACY_ENDPOINTS` table); retire after fleet enrollment |

### Structural observations

- **Controllers are thin.** Platform controllers validate with
  `platform-validation.ts` helpers and delegate; `MobileController` delegates
  every handler to a service. No domain logic found in controllers.
- **Direct repository writes** are all inside services, and id-addressed
  updates follow a tenant-scoped lookup (e.g. `receiving.service.ts:289`
  `lockReceiving(tx, actor.venueId, id)` before `update({ where: { id } })`;
  `payroll.service.ts:307-322` checks `existing.venueId !== actor.venueId`).
- **Runtime validation gap.** `MobileController` accepts `body: any`/plain
  interfaces for most routes; the global `ValidationPipe` with
  `forbidNonWhitelisted` has no DTO classes to act on (SECURITY_TODO M1 still
  open). Platform controllers hand-validate. `P2`.
- **Arbitrary statuses** are refused where it matters: `RemoteOrderStatusRule`
  (POS) admits only `confirmed`/`cancelled`; Edge ack admits only
  `SUCCEEDED|FAILED`; platform status endpoints use `requireEnumValue`.
- **Duplicated business rules**: legacy salary Expense classification lives
  in both `mobile/util/expense-category.ts` and Dart `expense_category.dart`
  (intentional mirror); takeaway detection rule exists in Dart only.
- **No raw SQL** (`$queryRaw`/`$executeRaw`: 0 occurrences).
- **Logging**: 43 `console.*` vs 12 `new Logger(...)`; no structured logger.
- **No health/readiness endpoint**: `GET /` returns a hello string
  (`app.controller.ts`).
- **Body limit** `50mb` JSON for every route (`main.ts`); no global rate
  limiter.

---

## D. POS (product)

| Area | Capability | SaaS readiness | Evidence |
|---|---|---|---|
| Login | Local PIN, roles manager/supervisor/waiter; session lock | **COMPLETE** | `login_screen.dart`, `session_lock.dart` |
| First run | `VenueSetupScreen` asks only the venue name; empty table layout saved; no inherited menu | **PARTIAL** | `database_service.dart:246-262`, `venue_setup_screen.dart` |
| Default credential | `manager` / `000000` created on empty user box | **UNSAFE** default (P1) | `user_repository.dart:45-55` |
| Tables / floors | Local layout editor (`tableLayouts`), canonical table identity contract | **COMPLETE**, local-only | `TableRepository.ensureCanonicalTableIdentity` |
| Walk-In / Takeaway / Packages | Order-backed; typed creation audit | **COMPLETE** | `order_repository.dart`, `takeaway_order.dart`, `package_repository.dart` |
| Reservations | Local bookings + Cloud mirror; timeline audit | **COMPLETE** | `reservation_repository.dart`, `reservation_audit.dart` |
| Orders / payments / split / advances | `CloseTableTransaction` with `closureId`, journal, recovery | **COMPLETE** | `close_table_transaction.dart`, `closure_journal_repository.dart` |
| Printing | Kitchen/receipt, LAN transports, renderers, Edge print commands | **PARTIAL** | `print_queue.dart` is in-memory (`Queue<_QueuedPrintJob>`, no persistence) — VYNIC_PRODUCTION_GAPS P0-2 remains open; printer config is developer-only |
| Close Day | Journaled transaction; blocks on open orders | **COMPLETE** | `close_day_transaction.dart` |
| Restore / cancellation | Restore-to-order with closure B; single cancel routine | **COMPLETE** | `cancel_order_transaction.dart` |
| Offline mode | Everything local; sync is async mirror | **COMPLETE** | D001 |
| Inventory projection | Read-only catalog v5 pulled from Cloud; consumption snapshot at close | **COMPLETE** | `inventory_projection_sync_service.dart`, `sale_consumption_snapshot.dart` |
| Audit | Order reports + venue-wide feed, both local and mirrored | **COMPLETE** | `global_audit.dart`, `audit_repository.dart` |
| Admin | 14 manager sections + 4 developer sections | **PARTIAL** | printers/connection/errors/developer behind signed token |
| Backup / restore | Manual file backup/restore from Admin; safety backup before restore | **PARTIAL** | `backup_repository.dart:683,746`; no scheduled backup; no off-machine copy |
| Sync failure behavior | Retries; ledger ACK state; last-good catalog kept | **COMPLETE** | `sale_ledger_sync_state.dart`, `inventory_projection_sync_service.dart` |
| Enrollment | Self-service from login screen: server address + one-time code | **COMPLETE** | `login_screen.dart:_openEnrollment`, `admin_pos_enrollment_panel.dart:150-178` |
| Upgrade compatibility | Hive migration v8; contract v2 accepts v1; backend normalizer must deploy first | **PARTIAL** | no auto-update mechanism found in `apps/operations` |
| Cash management | none (X-report counts only) | **MISSING** (P2 product) | `admin_close_day_section.dart:308` counts orders, not cash |

### Multi-Venue assumptions in POS

- Legacy shared `POS_SYNC_API_KEY` in `.env` still supported
  (`api_config.dart:posSyncApiKey`); Device credential wins when present.
- `.env.example` carries printer IPs and callback host — dev/legacy only.
- The POS never sees `venueId`; its tenant is the enrolled Device. Correct.

### What a new restaurant installation requires a developer for today

| Step | Requires |
|---|---|
| Printer host/port configuration | **Developer signed token** (`developerSections` includes `printers`) |
| Changing backend URL after enrollment | **Developer token** (`connection` section), unless re-enrolling |
| Recovering a forgotten admin PIN | Developer token (`developer` section) |
| Viewing POS error log | Developer token |
| Cloud staff row for the first manager | Automatic via staff sync, but only usable in Manager for the bootstrap Venue |

---

## E. Manager (product)

Shell: 5 tabs — Dashboard, Tables (`LiveStatusScreen`), Financials,
Reservations (file is misleadingly named `staff_performance_screen.dart`),
Management (`MobileAdminScreen` with 7 sub-tabs: Report, Sales, Audit,
Activity, Inventory, Team, Settings) — `manager_app_shell.dart:42-113`,
`admin_screen/mobile_admin_screen.dart:47-54`.

| Module | Proven | Reachability | Notes |
|---|---|---|---|
| Dashboard | `dashboard_screen.dart`, `GET /mobile/dashboard` | tab 0 | Ledger provenance shown |
| Tables / live | `live_status_screen.dart`, `GET /mobile/tables`, WS | tab 1 | Free table, order editor |
| Financials | `financials_screen.dart`, `/mobile/financials`, `/financial-summary` | tab 2 | Expenses add/delete; links to Payroll/Obligations |
| Sales history / detail | `mobile_admin_sales_tab.dart`, `/mobile/sales`, `/sales/:id` | Management → Sales | keyset pagination |
| Reservations | `staff_performance_screen.dart`, `reservation_*_screen.dart`, `/mobile/reservations` | tab 3 | reads `PosReservation` mirror |
| Staff | `mobile_admin_users_tab.dart`, `/mobile/users*` | Management → Team | returns plaintext PINs |
| Inventory / Suppliers / Receiving / Recipes | `mobile_admin_inventory_tab.dart`, `mobile_admin_receiving.dart`, `mobile_admin_recipes.dart` | Management → Inventory | Georgian unit labels |
| Consumption history | `consumption_history_screen.dart` (5 callers) | from Inventory/Sale detail | |
| Expenses | inside Financials | tab 2 | procurement categories rejected |
| Payroll / Obligations | `finance_planning_screen.dart` (3 callers), `financial_planning_card.dart` | Financials + Dashboard deep links | |
| Audit / Activity | `mobile_admin_audit_tab.dart`, `mobile_admin_activity_tab.dart`, `/mobile/audit`, `/audit-log` | Management | |
| Settings | `mobile_admin_settings_tab.dart` | Management → Settings | backend URL override, logout |
| Counted menus / calculator | `mobile_counted_menus_screen.dart`, `mobile_calculator_screen.dart` | reachable | Manager-only drafts |
| Emergency controls | `emergency_controls_screen.dart` (1 caller) | reachable | |

Findings:

- No unreachable screens found; every screen file has ≥1 caller.
- **Auth is the product blocker**: PIN-only login, bootstrap Venue only, 24 h
  token, no refresh, no server-side revocation (mitigated by per-request Staff
  re-resolution — disabling a Staff row takes effect immediately).
- **Permissions**: the whole `/mobile` and `/mobile/finance` surface is
  `MANAGER` role + `MANAGER_APP` feature. Supervisors cannot log in
  (`MOBILE_APP_STAFF_ROLES = [MANAGER, ADMIN]`). There is no per-module
  gating (Payroll, Inventory, etc.) — everything or nothing.
- **Cloud-only limitation**: Manager cannot edit menu, tables, floors,
  service fee, printers or business date (all POS-authored). It is a
  monitoring + financial + inventory + staff + reservations product, which is
  coherent for its role.
- **Offline expectations**: cached reads via `MobileCacheService`; mutations
  fail without Cloud. Acceptable.
- **Realtime**: cross-tenant room (see §R).

Verdict: Manager is a coherent restaurant-management product **for one
Venue**. Multi-tenant blocker is authentication + realtime, not screens.

---

## F. Platform Web / Admin

Two distinct things live in `apps/platform-web`:

1. **Public Vynic corporate site** — `/`, `/en`, `/ka`, `/product`
   (`HomePage.tsx`, `data/siteContent.ts`, demo form). Marketing only.
2. **Platform Admin** — `/admin/*` behind `ProtectedRoute` (`App.tsx:53-64`).
   Pages: Overview, Organizations (+detail), Venues (+detail with tabs
   overview/product/website/devices/activity), Plans, Features, Devices,
   Domains, Audit.

### Venue lifecycle

| Control | Backend | Platform UI | Status |
|---|---|---|---|
| Create Venue | `POST /platform/venues` (organizationId, name, timezone, currency) | `VenuesPage` | **COMPLETE** |
| View / Edit | `GET/PATCH /platform/venues/:id` | `VenueDetailPage` edit dialog | **COMPLETE** (3 fields) |
| Activate / Suspend | `PUT /platform/venues/:id/status` `ACTIVE|DISABLED` | `VenueOverviewTab` | **COMPLETE** — DISABLED blocks Device auth, Manager auth, website |
| Disable vs Suspend vs Archive | one `DISABLED` state | — | **PARTIAL** — no `SUSPENDED` (billing) vs `ARCHIVED` distinction |

### Venue identity

| Field | Cloud model | Platform UI | Status |
|---|---|---|---|
| name, timezone, currency | `Venue` | yes | **COMPLETE** |
| legal/business info, address, phone | POS Hive settings only (`SettingsRepository.setVenueLegalId` etc.) | no | **MISSING** in Cloud |
| business date settings | POS Hive; Cloud `Setting` mirror `currentBusinessDate` | no | **MISSING** control |
| logo / branding | POS Hive `venueLogoPng` | no | **MISSING** in Cloud |

### Device management

`list`, `enroll` (one-time code, TTL 5–1440 min), `create with credential`,
`disable`, `revoke`, `activate`, `rotate credential`, `lastSeenAt`, NOOP
connection test with polling — all **COMPLETE** (`VenueDevicesTab.tsx`,
`VenueEnrollmentPanel.tsx`, `platform-device.service.ts`). Missing: `replace`
as a first-class action (documented as "revoke + enroll again"), sync health
(no backlog/last-snapshot view), command history.

### Staff / admin bootstrap

**MISSING.** No `/platform/*` route touches `Staff`. Cannot create the first
Manager, reset a PIN, or disable access from Platform Admin.

### Website

| Control | Status |
|---|---|
| WebsiteMode NONE/SAAS/CUSTOM | **COMPLETE** (`PUT /platform/venues/:id/website`, `VenueWebsiteTab`) |
| Domains register/disable/release | **COMPLETE** |
| Consistency warning (entitled vs mode) | **COMPLETE** (`websiteAccess.consistent`) |
| Publish state / custom-site deployment | **MISSING** — `docs/CUSTOM_WEBSITE_RUNTIME.md` is `DOC_ONLY / NOT_PROVEN` |
| SAAS site engine | **MISSING** (`docs/FUTURE_SAAS_WEBSITE.md`) |

### Features per Venue

Platform UI can toggle exactly the seeded features (`POS`, `WEBSITE`,
`MANAGER_APP`) via plan assignment and ENABLED/DISABLED overrides
(`VenueProductTab.tsx`). For Inventory, Receiving, Recipes, Payroll,
Obligations, Advanced Financials, Profitability, Reservations, Packages,
Audit: **MISSING** — no Feature row, no guard, no UI. `FeaturesPage` is
read-only (`GET /platform/features`; no create route exists).

### Operational controls

| Question | Answer today |
|---|---|
| Last POS sync | Only `Device.lastSeenAt` (written ≤ every 5 min on any authenticated call) |
| Sale sync backlog / ledger completeness | **MISSING** in Platform; `SaleLedgerDay` exists and is shown to Manager only |
| Inventory sync | **MISSING** |
| Device health | `lastSeenAt` + manual NOOP test |
| Audit health | **MISSING** |
| Current business date / Close Day status | **MISSING** in Platform (Cloud `Setting currentBusinessDate` exists) |
| Reconciliation | **MISSING** in Platform |

### Support operations

- Investigate Venue: partial (activity tab = platform audit for that Venue).
- Impersonation: none exists. **Do not add unrestricted impersonation**; a
  scoped, audited read-only "view as Venue" is the safe shape.
- Reset/re-enroll: enrollment code issuance is complete; PIN/manager reset is
  missing.
- Diagnostics: none beyond the NOOP.

---

## G. Venue Website

`apps/venue-web` (`package.json` name `vankisi`) is a bespoke React/Three.js
site: 3D floor map meshes for one specific building
(`components/restaurant3d/*Mesh.tsx`), Vankisi branding across 16 files.
Backend serves it through the same Host→Venue boundary as any future site.

| Capability | Status |
|---|---|
| Venue resolution | **COMPLETE** (server-side, via `VenueDomain`) |
| Custom domain | **COMPLETE** registry; DNS/TLS out of repo |
| Menu | **COMPLETE**, reads Cloud `MenuItem.id` |
| Reservations + preorders | **COMPLETE** for Vankisi; **race** — availability check then create with no hold (`SECURITY_TODO A4`, `PROJECT_STATE` known blocker) |
| Live table map | Vankisi-specific 3D |
| Branding / contact / hours | hardcoded in `venue-web` |
| SEO | not audited in depth; SPA |
| Payments | BOG, process-wide credentials; signature verified on raw body |
| Deployment | `vercel.json` SPA rewrite; `VITE_API_URL` |

Modes: `NONE` / `SAAS` / `CUSTOM` exist as data (`WebsiteMode`), and the
tenant boundary treats CUSTOM and SAAS identically
(`public-tenant-isolation.integration.spec.ts:479`). Only `CUSTOM` has an
implementation, and only for Vankisi. For a second restaurant to use a
website: build the generic `SAAS` frontend (data-driven branding, hours,
contact, menu, simple booking without a 3D map) and per-Venue payment
credentials. Neither exists. `P2` unless WEBSITE is part of the initial offer.

---

## H. Database & Multitenancy

Schema: `apps/backend/prisma/schema.prisma` (1769 lines, 31 migrations, tip
`20260914120000_payroll_day_adjustments`).

### Tenant ownership

Directly Venue-scoped (have `venueId` FK, `onDelete: Restrict`): `Table`,
`Order`, `MenuCategory`, `MenuItem`, `Expense`, `StockItem`, `Supplier`,
`SupplierProduct`, `StockItemPurchaseUnit`, `Receiving`, `StockMovement`,
`MenuConsumptionRecipe`, `MenuConsumptionComponent`, `SaleConsumption*`,
`CloudSale`, `SaleLedgerDay`, `Staff`, `PosReservation`, `AuditReport`,
`AuditEventLog`, `DailySnapshot`, `QuickOrderDraft`, `Setting`, `Device`,
`DeviceEnrollment`(Cascade), `EdgeCommand`, `VenuePlanAssignment`(Cascade),
`VenueFeatureOverride`(Cascade), `VenueWebsiteConfig`(Cascade), `VenueDomain`,
`ManagerNotification`, `PushDevice`, `PosCallbackOutbox`, `WebsiteTable`,
`WebsiteReservation`, all payroll/obligation models.

Indirect ownership (no `venueId`, reached through parent FK): `OrderItem`,
`MenuSubcategory`, `MenuItemVariant`, `ReceivingLine`, `SaleLine`,
`SalePayment`, `QuickOrderDraftItem`, `ManagerNotificationDelivery`,
`WebsiteReservationTable`. Acceptable; every read path found joins through the
scoped parent.

Nullable tenancy: `AuditEvent.venueId String?` — denormalized, deliberately
not a relation; authority is `report.venueId`. Acceptable.

Global by design: `WebsiteUser` (customer identity across Venues; `phone`,
`email` `@unique`), `PlatformUser`, `Feature`, `Plan`, `Organization`.

### Uniqueness — tenant-scoped where it must be

`Table (venueId,tableNumber,floor)`, `Order (venueId,posOrderId)`,
`MenuCategory (venueId,slug)`, `Staff (venueId,username)`,
`StockItem (venueId,sku)`, `CloudSale (venueId,posSaleId)` and
`(venueId,closureId)`, `WebsiteTable (venueId,websiteTableNumber)`,
`EdgeCommand (venueId,idempotencyKey)`, `Setting @@id(venueId,key)`.

Global uniques that are correct: `VenueDomain.hostname`,
`Device.installationId`, `DeviceEnrollment.codeSelector`,
`PushDevice.fcmToken`. Worth noting: `Order.closureId @unique` is global
(UUID, so practically safe) while `CloudSale` scopes it per Venue —
inconsistent but not a defect.

### Cascades that could destroy history

| Relation | Behavior | Assessment |
|---|---|---|
| `MenuItem.category / subcategory → Cascade`; `MenuItemVariant → Cascade`; `MenuConsumptionRecipe → Cascade` on MenuItem/Variant; `MenuConsumptionComponent → Cascade` | Deleting a category deletes items, variants and **recipe definitions** | Consumption history is frozen in `SaleConsumption*` (Restrict), `SaleLine.menuItemId` is a plain string — history survives; definitions do not. Acceptable; menu-sync reconciliation is child-first and identity-gated |
| `StockItemPurchaseUnit → Cascade` on StockItem | StockItem cannot be deleted while `ReceivingLine`/`StockMovement` reference it (Restrict) | Safe |
| `AuditEvent → Cascade` on AuditReport | Reports are never deleted operationally | Safe |
| `SaleLine/SalePayment → Cascade` on CloudSale | CloudSale never deleted; revision updates touch lifecycle fields only | Safe |
| `Venue` children | `Restrict` on every history-bearing child | Venue cannot be hard-deleted — correct |

### Historical durability

Sales (`CloudSale*`, Decimal, revision-guarded), Audit (`AuditEvent.seq`,
append-only `AuditEventLog`), Receiving (`POSTED` immutable, reversal rows
beside originals, `@@unique([receivingLineId, movementType])`), StockMovement
(append-only, `Decimal(21,6)`), Payroll/Obligations (append-only signed
accruals, `reserveConsumed` recorded), `PosReservation` (mirror, reconciled
wholesale — not history; POS holds history). Orders in Cloud are an
operational mirror deleted by POS Close Day; `AuditReport` deliberately has no
FK to `Order`. **All financially durable tables are sound.**

### Remaining Float money / quantity

`Table.currentBill`, `Order.totalAmount/discountAmount/manualAdjustmentAmount/
serviceFeePercent`, `OrderItem.price`, `MenuItem.price`, `MenuItemVariant.size/
price`, `Expense.amount`, `DailySnapshot.*Revenue/totalExpenses/avgOrderValue`,
`QuickOrderDraft.subtotal/serviceFeeAmount/total/serviceFeeRate`,
`QuickOrderDraftItem.price`, `WebsiteReservation.totalAmount`. Of these,
**`Expense.amount` is the only one that enters financial reporting**
(`mobile-dashboard.service.ts:554-566` sums it via `Prisma.Decimal(row.amount)`
after the Float read). `P2`: migrate `Expense.amount` to `Decimal(18,2)`; the
rest are operational mirrors.

---

## I. Authentication & Permissions

### Authentication systems

| Principal | Credential | Token | Lifecycle | Revocation | Evidence |
|---|---|---|---|---|---|
| POS Device | `vynic-device-v1.<deviceId>.<secret>` header `X-POS-Sync-Key` | none (per-request Argon2id verify) | rotate/disable/revoke | immediate | `device-credential.service.ts` |
| POS legacy | shared `POS_SYNC_API_KEY` | none | env | redeploy | `pos-sync.guard.ts` — fails closed in production when unset |
| Manager Staff | 4+ digit PIN, bcrypt cost 12 | JWT HS256 `JWT_SECRET`, 24 h, `sub` only trusted | no refresh | Staff `isActive=false` or Venue DISABLED takes effect next request | `auth.service.ts`, `jwt.strategy.ts` |
| Platform User | email + password, Argon2id | JWT 8 h, audience `vynic-platform`, `typ`, optional `PLATFORM_JWT_SECRET` (falls back to `JWT_SECRET`) | no refresh | status DISABLED next request | `platform-auth.service.ts` |
| Website customer | phone/email + password Argon2 | cookie session + `hashedRefreshToken` | refresh | — | `website/auth` |
| Payment callback | BOG signature over raw body | — | — | — | `payment.controller.ts`, `main.ts` rawBody |
| POS developer | Ed25519-signed, terminal-bound, expiring token | local | — | — | `security/developer_access.dart` |

### Findings

- **PIN handling**: Cloud `staff:plain_pins` vault is AES-256-GCM with key
  derived from `COOKIE_ENCRYPTION_KEY`; plaintext returned to Manager
  (`mobile-users.service.ts:77`) and re-synced to POS. POS Hive stores
  `User.pinCode` cleartext; Hive is not encrypted (`database_core.dart` has no
  cipher). **P1**: move to show-once + hashed-only, or at minimum encrypt the
  POS store.
- **Brute force**: Manager login has per-IP in-memory throttle (5 fails/15
  min). Platform login and website login have **none**. `P1`.
- **JWT**: no refresh, no jti/revocation list; per-request DB re-resolution
  is the effective revocation. Acceptable for pilot; `P2` refresh + shorter
  TTL.
- **Device enrollment**: attempt counter, expiry, cancel, Argon2id verifier,
  installation-id reuse rotates rather than duplicates — sound.
- **Staff disabled/deleted**: Manager token stops working next request;
  payroll-referenced Staff retained inactive. Sound.
- **Conflation**: `MANAGER_APP` entitlement (commercial) is the only thing
  standing between a MANAGER and every module — feature entitlement, staff
  permission and Venue policy are collapsed into "is MANAGER and Venue bought
  MANAGER_APP". D006 says entitlement ≠ policy; the code has no policy layer
  yet (`docs/VENUE_POLICY_PLAN.md` is `DOC_ONLY / NOT_PROVEN`).
- **Cross-tenant identity**: `WebsiteUser.role = SUPER_ADMIN` is a global
  admin seeded from env and honoured in `reservation.controller.ts:107`. This
  is a second cross-Venue admin identity outside `PlatformUser` (D005). `P1`.

### Permission matrix (derived from code)

| Action | Waiter (POS) | Supervisor (POS) | Manager (POS) | Manager (Manager app) | Platform Admin |
|---|---|---|---|---|---|
| Take/edit orders | yes | yes | yes | yes (Edge command) | no |
| Cancel order | with cancellation PIN | with PIN / approval | yes (`canOverrideApproval`) | yes (`POST /mobile/order/:id/cancel`) | no |
| Restore Sale to order | no | no | yes (Admin) | no route | no |
| Close Day | no | yes (`_limitedAdminSections` has `closeday`) | yes | no | no |
| Staff CRUD / PIN | no | yes (`staff`,`users`) | yes | yes | **no** |
| Menu | no | no | yes (POS Admin only writer) | read-only | no |
| Tables / floors | no | no | yes | free table only | no |
| Inventory / Receiving / Recipes | no | no | read-only (Admin inspection) | full | no |
| Payroll / Obligations | no | no | no | full | no |
| Expenses | no | no | yes | yes | no |
| Audit read | no | no | yes | yes | platform audit only |
| Settings (service fee, receipt, business date) | no | no | yes | read-only | no |
| Printers / backend URL | no | no | **developer token** | backend URL override | no |
| Backup create / restore | no | no | create; restore needs developer | no | no |
| Venue/plan/features/devices/domains | — | — | — | — | yes |

Server-side gaps behind UI hiding: none found that are MANAGER-only in UI but
open to WAITER on the server — because the backend never issues a token to a
non-MANAGER. The real gap is the opposite: **no server-side distinction below
MANAGER at all**.

---

## J. Feature Entitlements

Model exists and is correct in shape: `Feature` rows, `Plan`, `PlanFeature`,
`VenuePlanAssignment` (one per Venue), `VenueFeatureOverride` (ENABLED/DISABLED
wins over plan), `resolveEffectiveFeatures` pure function with tests,
`FeatureGuard` fail-closed. Seeded: features `POS`, `WEBSITE`, `MANAGER_APP`;
plans `POS`, `POS_WEBSITE`, `POS_MANAGER`, (all-features plan). Nothing gates
POS→Cloud sync (by design).

Current status: **features are present for everyone who has `MANAGER_APP`.**
Turning Payroll off for Venue B is impossible without a code change.

### Desired control matrix

| Feature | Backend gate | Manager hide | POS hide | Platform control | Current status |
|---|---|---|---|---|---|
| POS (sync always on) | none by design | — | — | plan | COMPLETE |
| Manager App | `@RequiresFeature(MANAGER_APP)` on `/mobile`, `/mobile/finance` | login refused (403) | — | plan/override | COMPLETE |
| Website | `WEBSITE` on `/api/*` | — | — | plan/override + mode | COMPLETE |
| Inventory (items, suppliers, receiving, recipes, consumption) | **MISSING** (needs `INVENTORY` key on `/mobile/inventory/*`, `/edge/inventory/*` returns empty catalog when off) | **MISSING** | Admin inventory section hide **MISSING** | **MISSING** | BACKEND_EXISTS_UI_MISSING → really MISSING gate |
| Payroll | **MISSING** (`PAYROLL` on `/mobile/finance/payroll*`) | **MISSING** | n/a | **MISSING** | MISSING |
| Financial Planning / Obligations | **MISSING** | **MISSING** | n/a | **MISSING** | MISSING |
| Profitability (theoretical cost, future COGS) | **MISSING** | **MISSING** | n/a | **MISSING** | MISSING |
| Reservations (website booking / Manager booking) | website via `WEBSITE`; Manager **MISSING** | **MISSING** | POS reservations are core — do not gate | **MISSING** | PARTIAL |
| Advanced Audit (venue-wide feed) | **MISSING** | **MISSING** | keep local | **MISSING** | MISSING |
| Packages | POS-local | — | — | — | NOT_APPLICABLE (core POS) |

Required to make `Venue A → Payroll ON, Venue B → Payroll OFF` without
redeploy: (1) seed Feature rows (data migration, no schema change), (2) add
`@RequiresFeature` per route group, (3) expose effective features to Manager
(`GET /mobile/entitlements` or in `/mobile/dashboard`) and hide tabs, (4)
include effective features in the Edge inventory catalog response so the POS
Admin hides its inventory section, (5) Platform UI already handles arbitrary
feature keys (`VenueProductTab` renders `features` list). Estimated: backend +
Manager + Platform data, no schema migration. `P0` for commercial packaging.

---

## K. Plans / Subscription / Billing

What exists: `Plan` with `ACTIVE|RETIRED`, `VenuePlanAssignment` (no dates,
no state), `Organization` with `name` only. **No** `Subscription`, trial,
billing cycle, invoice, payment status, seat/device limits, feature limits,
grace period or suspension reason. `VenueStatus` is `ACTIVE|DISABLED` only.
D013 says restaurant payments ≠ Vynic billing — correct, and nothing conflates
them.

Classification:

| Requirement | Class |
|---|---|
| Record per-Venue commercial state (`TRIAL`, `ACTIVE`, `PAST_DUE`, `SUSPENDED`, `CANCELLED`) with dates and a note, editable in Platform Admin | **must-have before paid rollout** (manual administration is fine) |
| Device/Staff limits per plan | **can be manual initially** (Platform Admin sees device count) |
| Automatic suspension on non-payment, invoices, processor integration | **later automation** |
| Contract/price fields on Organization | **can be manual initially** (external accounting) |

Architecture supports a manual subscription table today: adding a
`VenueSubscription` model + Platform routes + UI is additive.

---

## L. New Venue Onboarding — end to end

"If tomorrow we sign a new restaurant, what exact steps until the first Sale?"

| # | Step | Who today | Class | Evidence |
|---|---|---|---|---|
| 1 | Create Organization | Platform Admin UI | PLATFORM_ADMIN | `OrganizationsPage.tsx` |
| 2 | Create Venue (name, timezone, currency) | Platform Admin UI | PLATFORM_ADMIN | `VenuesPage.tsx` |
| 3 | Assign plan / overrides | Platform Admin UI | PLATFORM_ADMIN | `VenueProductTab.tsx` |
| 4 | Configure features per module | — | **MISSING** (only 3 keys) | §J |
| 5 | Business settings in Cloud (legal id, address, business-date rule, service fee) | — | **MISSING** in Cloud; entered on POS | POS `SettingsRepository` |
| 6 | Issue enrollment code | Platform Admin UI | PLATFORM_ADMIN | `VenueEnrollmentPanel.tsx` |
| 7 | Install POS build on Windows PC | Vynic staff copies a build | **DEVELOPER_MANUAL** (no installer/updater found) | — |
| 8 | POS first run: venue name | Restaurant | SELF_SERVICE | `VenueSetupScreen` |
| 9 | POS enrollment: server URL + code → credential + `apiBaseUrl` | Restaurant/installer | SELF_SERVICE | `admin_pos_enrollment_panel.dart` (requires `DEVICE_API_BASE_URL` set on server) |
| 10 | Change default `manager`/`000000` PIN | Restaurant | SELF_SERVICE (but not forced) | `user_repository.dart` |
| 11 | Menu, tables, floors, service fee, receipt header/logo | Restaurant manager on POS | RESTAURANT_MANAGER | POS Admin sections |
| 12 | Printers | **Vynic developer with signed token** | **DEVELOPER_MANUAL** | `admin_screen.dart:70-75`, `apps/devtool` |
| 13 | Manager app access | POS staff sync creates Cloud `Staff`; login only works for bootstrap Venue | **MISSING for Venue ≥2** | `auth.service.ts:48` |
| 14 | Website/domain (if sold) | Platform registers domain; **no site to serve** unless custom-built; `WebsiteTable` seeding only for bootstrap Venue | **DEVELOPER_MANUAL / MISSING** | `bootstrap.service.ts`, §G |
| 15 | Payment credentials (if sold) | env, process-wide | **DEVELOPER_MANUAL / UNSAFE** for 2nd paying Venue | `payment.service.ts` |
| 16 | First Order / first Sale on POS | Restaurant | SELF_SERVICE | local |
| 17 | Cloud ledger receives Sale | automatic ≤ 30 s | SELF_SERVICE | `sale-ledger-sync.service.ts` |
| 18 | Verify sync from Platform | `lastSeenAt` + NOOP only | PARTIAL | §F |

Hosting prerequisite for all of the above: a **hosted backend reachable from
the restaurant**. Today the only documented deployment is on the restaurant's
own PC (`DEPLOY.md`), which for a second restaurant means either a second
backend per restaurant (not SaaS) or an undocumented cloud host —
**DEVELOPER_MANUAL / MISSING**, and the first-ever `PlatformUser` is created by
`npm run platform-admin:create` on the server shell (CLI).

### Launch blockers from this list (require developer / DB / CLI / env / code)

1. Hosted backend + PostgreSQL deployment (no config in repo).
2. Manager login for a non-bootstrap Venue (code change).
3. Printer configuration behind developer token (code change or policy).
4. Module-level feature keys (data seed + code).
5. Website tables/branding for a second Venue (code/DB).
6. Per-Venue payment credentials (schema + code) — only if payments sold.
7. POS installer/updater distribution (release process).
8. First Platform admin via CLI — acceptable once, but document it.

---

## M. Device / Sync

| Item | Status | Evidence |
|---|---|---|
| Device `ACTIVE/DISABLED/REVOKED` | COMPLETE | `DeviceStatus`, `setDeviceStatus` |
| Enrollment code lifecycle (pending/redeemed/cancelled/expired, attempts) | COMPLETE | `DeviceEnrollment`, `enrollment-rate-limiter.ts` |
| Credential rotation | COMPLETE (old invalid immediately) | `rotateCredential` |
| Edge pull/claim/ack with lease (120 s), max attempts 10, expired-lease release | COMPLETE | `edge-command.service.ts`, contract `limits` |
| POS journal prevents replay; interrupted prints fail visibly | COMPLETE | `edge_command_journal.dart`, D009 |
| Version compatibility | COMPLETE (v2 accepts v1; catalog v3/4/5) | contract `compatibleContractVersions` |
| Retry/backoff on POS | COMPLETE (jittered, 5 min cap) | `edge_transport_service.dart:340` |
| Platform inspect/control without DB | PARTIAL — lifecycle yes; **queue backlog, failed commands, last snapshot time, ledger completeness: no** | `platform-device.service.ts` reads only the test command |
| Backlog visibility per stream (Sales, Audit, Inventory effects, Orders, Menu, Reservations) | Sales: `SaleLedgerDay` (Manager only). Audit: revision ACK state on POS only. Inventory effects: POS `sale_consumption_sync_service` state only. Orders/Menu/Reservations: none (full snapshot each time) | |
| "Why is this Venue not syncing?" | **Cannot be answered without logs/DB**: `lastSeenAt` says a credential was used; nothing says whether `manager-data` ingested, when, or with what error | |

Recommendation (`P1`): persist per-Venue `SyncHeartbeat` (last snapshot at,
last audit at, last ledger ACK, last catalog pull, last error) written by the
ingest services and read by a `GET /platform/venues/:id/sync` route.

---

## N. Sales / Financials

Cloud Sale Ledger verified: `CloudSale/SaleLine/SalePayment` `Decimal(18,2)`;
`(venueId,posSaleId)` idempotency; revision updates limited to
void/restore lifecycle; `SaleLedgerDay` completeness/reconciliation; Manager
summary/history/detail/product analytics tenant-safe
(`mobile-sale-ledger.service.ts`, 16 `venueId` predicates, no bare lookups).
Non-fiscal/cancelled normalization sends zero collection; fiscal advances must
match. Restore excluded by revenue predicate. Legacy `salesHistoryByDate`
summary fallback for days with no per-Sale rows, flagged as partial.

Interaction check (`mobile-dashboard.service.ts:551-568`):
`totalOutflows = otherExpenses + (legacySalaryExpenses + payrollPayments) +
obligationPayments + procurement.businessDay.total`; procurement categories are
filtered out of `Expense`; reserves are excluded. **No double counting found.**

Remaining blockers for commercial reporting:

- `Expense.amount` Float (P2).
- Revenue for non-complete days falls back to POS aggregate settings JSON
  (`summarySetting`) — honest but not auditable per Sale (P2, self-heals).
- No exportable statement / CSV / period lock (P2).
- No cash drawer reconciliation (P2 product).
- Historical realized COGS / Gross Profit not implemented (P2/P3, documented).

---

## O. Inventory

| Capability | Status | Exposure |
|---|---|---|
| Stock Items (UUID, SKU, min stock, FOOD/BEVERAGE) | working | Manager full; POS read-only |
| Suppliers + Supplier Products | working | Manager |
| Receiving DRAFT/POSTED/CANCELLED, waybill, business date | working | Manager |
| Purchase history / daily procurement totals | working | Manager Financials |
| Recipes (one active per item+variant, yield, base-unit per unit) | working | Manager |
| Consumption at close + restore reversal | working | POS snapshot → Cloud; Manager history |
| Current stock (derived SUM), LOW/NEGATIVE | working | Manager; POS catalog v4+ |
| Theoretical current cost | working | Manager |
| Feature-gated? | **no** (only `MANAGER_APP`) | |

Remaining domain gaps (not launch blockers): Waste, manual write-off,
Stocktake, Variance, historical realized COGS, Gross Profit, yield/loss,
sub-recipes — all listed as deferred in `PROJECT_STATE`; `P2/P3`.

---

## P. Payroll / Obligations

Verified in `finance.controller.ts` (14 routes), `payroll.service.ts`,
`obligations.service.ts`, `finance-rules.ts`, `finance.integration.spec.ts`,
and Manager `finance_planning_screen.dart` + widget tests: compensation rules
(MONTHLY_FIXED/DAILY_FIXED/MANUAL, effective month), frozen periods, daily
sheet with request-UUID idempotency and signed adjustments, payments with
period lock, obligation templates, monthly cycles, reserves, payments under
cycle lock, dashboard card. **COMPLETE** for the defined scope.

Should be optional entitlements: `PAYROLL`, `FINANCIAL_PLANNING`
(obligations/reserves). Both are Venue-scoped and append-only, so gating is
purely a route/UI concern.

---

## Q. Audit

Order-level reports (`AuditReport/AuditEvent`, POS-owned `seq`), venue-wide
`AuditEventLog` with `entityType/entityId`, reservation timeline,
`PlatformAuditEvent` for operator actions. All append-only; ingestion copies
`venueId` from the authenticated principal, never the payload. Manager and POS
readers exist. Retention policy: **none** (no purge, no archive) — fine for
now, `P3` to define. Gaps: no audit of Manager *reads* (not needed), no alert
on anomalies (P2), Platform cannot view a Venue's `AuditEventLog` (P2 support
feature, must stay read-only and audited).

---

## R. Security

| # | Finding | Priority | Evidence |
|---|---|---|---|
| S1 | WebSocket `managers` room shared across Venues; sync broadcasts include order/table ids and `day_closed` | **P0** | `monitoring.gateway.ts:80,119`, `sync-broadcast.service.ts` |
| S2 | Manager notifications + deliveries always written to bootstrap Venue; Venue B managers get nothing, Venue A managers get Venue B events | **P0** | `hybrid-notification.service.ts:79,90` |
| S3 | `GET /sync/diff` returns bootstrap Venue tables/orders to any authenticated manager | **P1** (no live caller; remove or scope) | `sync.controller.ts:75,81` |
| S4 | Plaintext staff PINs returned by `/mobile/users`; POS Hive PINs cleartext, Hive unencrypted | **P1** | `mobile-users.service.ts:77`, `user.dart:12` |
| S5 | Default POS manager PIN `000000` not forced to change | **P1** | `user_repository.dart:46` |
| S6 | No throttle on `/platform/auth/login` or `/api/auth/signin`; Manager throttle in-memory per IP (resets on restart, NAT-shared) | **P1** | `platform-auth.controller.ts`, `SECURITY_TODO C7` |
| S7 | `WebsiteUser SUPER_ADMIN` global admin identity seeded from env; reads full reservation list of whatever Venue's host it targets | **P1** | `bootstrap.service.ts:seedWebsiteAdminIfConfigured`, `reservation.controller.ts:107` |
| S8 | Process-wide BOG merchant credentials | **P0 if a second Venue takes payments**, else NOT_APPLICABLE | `payment.service.ts:11-12` |
| S9 | CORS allows any LAN origin on dev ports only in non-production; production requires `FRONTEND_URL`/`ALLOWED_ORIGINS` — sound, but production values undocumented | P2 | `main.ts` |
| S10 | 50 MB JSON limit on every route, no global rate limit | P2 | `main.ts` |
| S11 | No DTO validation on `/mobile` bodies (`body: any`) | P2 | `SECURITY_TODO M1` |
| S12 | Manager JWT 24 h, no refresh, `JWT_SECRET` shared with platform tokens unless `PLATFORM_JWT_SECRET` set | P2 | `platform-auth.service.ts:secret` |
| S13 | Secrets: `secrets/` gitignored and untracked; `.env*` ignored; `firebase.json` tracked is client config only. No leaked secrets found in tracked files | OK | `git ls-files` |
| S14 | Raw SQL: none. IDOR: none found — all id-addressed Manager reads/mutations checked scope through `venueId` or a scoped lock first | OK | §C |
| S15 | Website reservation availability race (no transactional hold) | P1 (if WEBSITE sold) | `reservation.service.ts`, `SECURITY_TODO A4` |
| S16 | POS backup restore / wipe / PIN recovery gated by Ed25519 developer token bound to terminal id — sound design, but centralizes support on one private key | P2 (key custody runbook) | `developer_access.dart` |
| S17 | `POS_SYNC_API_KEY` legacy shared key still accepted → resolves to bootstrap Venue | P1 (retire after fleet enrollment, D012) | `pos-sync.guard.ts` |

---

## S. Observability / Support

| Capability | State |
|---|---|
| Structured logging | **MISSING** — `console.*` (43) + Nest `Logger` (12), no correlation ids, no JSON |
| Error tracking (Sentry etc.) | **MISSING** |
| Health/readiness endpoint | **MISSING** (`GET /` hello; `GET /sync/ping` unauthenticated ok) |
| Sync metrics | `[SyncTiming]` log line per sync (POS and backend) — logs only |
| Device last seen | `Device.lastSeenAt` (≤5 min granularity), in Platform UI |
| Queue/backlog visibility | `EdgeCommand` rows exist; no Platform list; `PosCallbackOutbox.getStats()` exists but is bootstrap-only and has no caller |
| Ledger mismatch monitoring | `SaleLedgerDay.reconciliation = MISMATCH` stored; visible to Manager; no alert |
| DB monitoring / backup status | **MISSING** |
| Audit anomalies | **MISSING** |
| Inventory pending effects | POS-local ACK state only |

"50 restaurants, one says POS is not syncing" — today: SSH/RDP to the server,
`pm2 logs`, then SQL on `Device.lastSeenAt`, `EdgeCommand`, `SaleLedgerDay`,
`AuditReport.syncRevision`. **Entirely manual.**

Minimum SaaS observability (`P1`): health endpoint; structured JSON logs with
`venueId`/`deviceId`; per-Venue sync heartbeat table + Platform "Sync" tab;
error tracker; alert on `SaleLedgerDay.MISMATCH` and on `lastSeenAt` older
than N hours during business hours.

---

## T. Deployment / Infrastructure

Repository evidence only:

| Concern | Evidence | Assessment |
|---|---|---|
| Backend hosting | `apps/backend/DEPLOY.md`: Windows POS PC, PM2, local PostgreSQL, fixed LAN IP `10.10.10.4` | **Single-machine, single-restaurant.** No Dockerfile, no compose, no IaC, no hosted config |
| Env | `.env.example`, `scripts/check-env.mjs`; `DEVICE_API_BASE_URL`, `TRUST_PROXY_HOST`, `PLATFORM_JWT_SECRET` documented | OK for what exists |
| Migrations | `prestart:prod` runs `prisma migrate deploy` | OK; no rollback strategy documented |
| platform-web deployment | none in repo (Vite build only) | MISSING |
| venue-web deployment | `vercel.json` SPA rewrite; `VITE_API_URL` | OK for Vankisi |
| Flutter release | no CI, no installer, no updater; `pubspec.yaml` `version: 1.0.0+1` never bumped | MISSING release process |
| Domain / SSL | not in repo; backend listens plain HTTP `0.0.0.0:PORT` | requires reverse proxy; undocumented |
| Backup | none documented for PostgreSQL | **MISSING** (P0 for hosted SaaS) |

Inappropriate for SaaS: in-memory login throttle, in-memory presence, in-memory
POS callback URL, `firebase-admin` credentials via absolute file path, single
process assumption throughout (`@Cron` in-process). All fine for one instance;
horizontal scaling would need Redis/adapter — `P3`.

---

## U. Backup / Disaster Recovery

| Question | Current truth |
|---|---|
| Cloud PostgreSQL backup | **Not documented, not automated.** |
| If Cloud PostgreSQL is lost | POS keeps operating (Hive is authoritative for operation and Sales). Re-syncing would restore: menu, tables, orders (open), staff (with PINs re-sent for unacknowledged members), reservations mirror, Sales ledger (POS re-uploads unacknowledged revisions — but **acknowledged Sales are not re-sent**, so ledger history older than the ACK window is lost unless POS backup is replayed with reset ACK state), audit reports (revision-based; acknowledged ones not re-sent). **Lost permanently**: Inventory (StockItem, Supplier, Receiving, StockMovement, recipes — Cloud is the only authority; POS holds only a read excerpt), Payroll, Obligations, Platform data (Organizations, Venues, Devices, plans, domains, platform audit). |
| If a POS PC dies | Sales/orders/audit since last manual backup are lost locally. Cloud holds the mirror (Sales ledger, audit, menu, staff, reservations) but **there is no Cloud→POS restore path**: `BackupRepository.restoreDataBackupFromFile` needs a local backup file. Inventory catalog re-pulls automatically. |
| New POS re-enrollment | Platform issues a new enrollment code; POS enrolls; menu/tables must be restored from a POS backup file or re-entered. Old Device row stays (D008). |
| Historical Sales | Durable in Cloud once acknowledged; Cloud backup is the gap. |
| Audit retention | Unbounded, no purge. |

Missing runbooks/features: PostgreSQL automated backup + restore test;
Cloud→POS bootstrap (menu/tables/staff) for a replaced terminal; POS scheduled
local backup to a second location; "force full re-upload" switch on POS for
ledger/audit after a Cloud restore. `P0`: DB backup. `P1`: the rest.

---

## V. Legacy / Duplication

| Item | Class | Notes |
|---|---|---|
| `PosCallbackClient`, `PosOutbox`, `PosCallbackModule`, `PosConnectionRegistry`, `LEGACY_ENDPOINTS` | KEEP_COMPATIBILITY | frozen fallback for unenrolled Venue (D012); retire after fleet enrollment evidence |
| Legacy shared `POS_SYNC_API_KEY` path in `PosSyncGuard` and `LegacyPosTenantService` | MIGRATE_LATER | with the above |
| `LEGACY_MANAGER_TENANT` in `auth.service.ts`, `sync.controller.ts` (`/sync/diff`), `hybrid-notification.service.ts`, `bootstrap.service.ts` | **INVESTIGATE → must fix** | these are not compatibility; they are single-tenant defects (§A) |
| `GET /sync/diff` | SAFE_TO_REMOVE (after confirming no client) — Dart `getDiff` has no caller | |
| `PosReservation` legacy `isTakeAway`/`linkedOrderId` bookkeeping rows | KEEP_COMPATIBILITY | mirror reconciles |
| Order statuses `preparing/served/paid` read-only | KEEP_COMPATIBILITY | documented |
| `LEGACY_ADMIN_ROLE = 'ADMIN'` normalization | KEEP_COMPATIBILITY | |
| Legacy salary `Expense` category (read-only) beside Payroll | KEEP_COMPATIBILITY | documented in FINANCIALS_STEP47 |
| `DailySnapshot` + `salesHistoryByDate` Float aggregates beside `CloudSale` | MIGRATE_LATER | fallback for pre-ledger days |
| `WebsiteUser SUPER_ADMIN` + `SUPER_ADMIN_*` env seeding | INVESTIGATE | overlaps `PlatformUser`; likely SAFE_TO_REMOVE once a Venue-scoped booking admin exists |
| `WEBSITE_TABLE_MAPPINGS` seed in `BootstrapService` | MIGRATE_LATER | move to Platform/Venue configuration |
| `Order.closureId @unique` global vs `CloudSale (venueId, closureId)` | INVESTIGATE | harmless inconsistency |
| POS `.env` printer keys, `POS_INGEST_PORT`, `POS_CALLBACK_HOST` | KEEP_COMPATIBILITY | dev/legacy |
| `staff_performance_screen.dart` actually hosts Reservations | SAFE_TO_RENAME (P3) | naming only |
| `apps/backend/dev.db`, `docs/archive`, `VYNIC_PRODUCTION_GAPS.md` (2026-07-21, partly resolved) | INVESTIGATE | stale artifacts; mark superseded items |

---

## W. Platform Admin — Desired Control Matrix

| Control | Backend support exists? | Platform UI exists? | Currently enforceable? | Missing work | Priority |
|---|---|---|---|---|---|
| Venue create/edit (name, tz, currency) | yes | yes | yes | — | done |
| Venue status ACTIVE/DISABLED | yes | yes | yes (Device/Manager/Website auth) | add `SUSPENDED` (commercial) vs `DISABLED` (operational) semantics | P1 |
| Venue identity (legal id, address, phone, logo) in Cloud | no | no | no | Venue fields or `VenueProfile`; POS pulls via catalog-like read | P1 |
| Plan assignment | yes | yes | yes (3 features) | — | done |
| Subscription state (trial/active/past-due/suspended, dates, note) | no | no | no | `VenueSubscription` model + routes + UI; gate Manager/Website on it | P0 (manual admin acceptable) |
| Feature toggles per module | mechanism yes; keys no | UI generic yes | no | seed keys; route guards; Manager/POS hide | P0 |
| Website Mode | yes | yes | yes | — | done |
| Domains | yes | yes | yes | — | done |
| Devices (list/enroll/disable/revoke/rotate/last seen) | yes | yes | yes | "replace" flow; command history | P2 |
| Manager/Admin access (create first manager, reset PIN, disable) | no | no | no | Platform route writing `Staff` for a Venue + Edge `STAFF_UPSERT` dispatch; audited | P0 |
| Staff limits | no | no | no | plan limit + check in `mobile-users`/staff sync | P2 |
| Device limits | no | no | no | plan limit + check in enrollment | P2 |
| Inventory feature | no key | — | no | see §J | P0 |
| Payroll feature | no key | — | no | see §J | P0 |
| Financial Planning feature | no key | — | no | see §J | P0 |
| Profitability feature | no key | — | no | see §J | P1 |
| Reservations (Manager/website) feature | website via WEBSITE | — | partial | key for Manager reservations | P2 |
| Support diagnostics (read-only Venue view, sync state, recent errors) | partial (platform audit) | partial (activity tab) | — | per-Venue sync heartbeat + read-only Venue inspector, fully audited | P1 |
| Last sync (snapshot / audit / ledger / catalog) | no (only `lastSeenAt`) | last seen only | — | heartbeat table + UI | P1 |
| Ledger completeness per day | model yes (`SaleLedgerDay`) | no | — | Platform read route + UI | P1 |
| Business date / Close Day status | Cloud `Setting currentBusinessDate` | no | — | read route + UI | P2 |
| Website tables mapping per Venue | model yes (`WebsiteTable`) | no | — | Platform CRUD (or Manager) | P1 if WEBSITE sold |
| Payment credentials per Venue | no | no | no | encrypted per-Venue merchant config | P0 if payments sold |
| Platform users (invite, disable, roles) | model yes; routes no | no | — | routes + UI; second role (SUPPORT read-only) | P1 |

---

## X. SaaS Launch Checklist

### P0 — must fix before multi-restaurant paid rollout

1. **Hosted backend + PostgreSQL with automated backups and restore test**;
   HTTPS termination; `DEVICE_API_BASE_URL`, `ALLOWED_ORIGINS`,
   `PLATFORM_JWT_SECRET` set (§T, §U).
2. **Manager login venue discrimination** — replace bootstrap-Venue PIN scan
   with a Venue-discriminating credential (e.g. venue code + PIN, or
   username+PIN scoped by a Venue slug) (`auth.service.ts`).
3. **Venue-scope realtime and notifications** — per-Venue socket rooms and
   `HybridNotificationService` carrying the sync tenant; remove or scope
   `GET /sync/diff` (S1–S3).
4. **Module feature keys + guards + client hiding** (§J).
5. **Manual subscription/commercial state** in Platform Admin (§K).
6. **Platform-side Manager bootstrap/reset** for a Venue (§W).
7. **Restaurant-configurable printers** (move `printers` out of
   `developerSections`, or provide a Cloud-pushed printer configuration
   command) — otherwise every install needs a Vynic developer.
8. **Per-Venue payment credentials** — only if WEBSITE with payments is sold
   at launch; otherwise refuse to sell payments until done (S8).

### P1 — before first serious customers

- Force PIN change from default `000000`; hashed-only or show-once PINs;
  encrypt POS Hive or at least the user box (S4, S5).
- Login throttling on Platform and website; persistent throttle store (S6).
- Retire `WebsiteUser SUPER_ADMIN` or fold into a Venue-scoped role (S7).
- Sync heartbeat + Platform "Sync" tab + ledger completeness view (§M, §S).
- Health endpoint, structured logs with `venueId`, error tracking (§S).
- Venue identity fields in Cloud (legal id, address, phone, logo) (§W).
- Cloud→POS bootstrap for a replaced terminal; scheduled POS backups (§U).
- Website reservation hold (S15) — if WEBSITE sold.
- Fleet enrollment → retire legacy shared key (S17).
- Run the 271 integration tests in CI against a disposable PostgreSQL.
- Second Platform role (support read-only) and Platform user management UI.

### P2 — product maturity

- DTO validation on `/mobile`; global rate limit; body-size scoping.
- `Expense.amount` → Decimal; period lock / export for financials.
- Durable print spool; cash drawer reconciliation.
- Generic `SAAS` venue website engine; Platform-managed `WebsiteTable`.
- Staff/Device plan limits; `SUSPENDED` vs `DISABLED` semantics.
- Realized COGS / Gross Profit, waste, stocktake.
- Sub-MANAGER permissions in Manager (supervisor read-only etc.).
- Audit retention policy; Platform read-only Venue audit inspector.

### P3 — later / scale

- Redis-backed presence/throttle/socket adapter for multi-instance.
- Delta sync for tables/orders/menu instead of 30 s full snapshot.
- Automated billing/invoicing integration.
- OS keychain for Device credential; Device-addressed printers.
- Rename `staff_performance_screen.dart`; archive superseded docs.

---

## Y. Product Maturity Scorecard (0–5)

| Area | Score | Evidence |
|---|---|---|
| Core POS | **4** | journaled close, cancel, restore, close day, packages, takeaway, reservations, 1253 Flutter tests; missing cash management, durable print spool |
| Offline reliability | **4** | Hive authority, closure journal + recovery, Edge journal, last-good catalog; no automatic local backup |
| Manager | **3** | complete module set for one Venue; auth is single-Venue; realtime not scoped |
| Financials | **4** | Decimal ledger, reconciliation, payroll/obligations, no double count; `Expense` Float, no export/lock |
| Inventory | **4** | Steps 1–4.7 with concurrency-safe posting and derived stock; waste/stocktake/COGS missing (documented) |
| Website | **2** | works for Vankisi only; no SAAS engine; race; process-wide payments |
| Platform Admin | **3** | venue/plan/features/devices/domains/audit real; no staff bootstrap, no sync health, 3 features, no subscription |
| Multitenancy | **3** | schema and principal authority excellent with tests; Manager login, WS, notifications, `/sync/diff` still single-tenant |
| Security | **3** | Argon2/bcrypt, fail-closed guards, one-time secrets, signature-checked callbacks; recoverable PINs, default PIN, missing throttles, global website admin |
| Onboarding | **2** | enrollment and first-run are self-service; printers, Manager access, hosting, website need a developer |
| Entitlements | **2** | correct mechanism, three keys |
| Billing | **0** | nothing beyond plan assignment |
| Observability | **1** | logs + `lastSeenAt` only |
| Deployment | **1** | PM2 on the POS PC; no CI; no hosted config; no DB backup |
| Supportability | **1** | developer token tooling exists; no diagnostics surface |

**Overall SaaS readiness: INTERNAL_BETA.** The single Vankisi deployment is
production-grade for one restaurant. A second restaurant cannot be served
without developer involvement (hosting, printers, Manager access) and would
share realtime/notification streams with the first. The gap to
`PAID_PILOT_READY` is mostly control-plane, auth-scoping and operations work
on top of a sound foundation — not a rewrite.

---

## Z. What Is Already Strong

- **Tenant authority discipline**: every principal resolves its Venue on the
  server; request `venueId` is never authority (`tenant-identity.ts` composite
  helpers make forgetting scope a compile-time inconvenience); three
  two-Venue isolation integration suites.
- **Money integrity**: `CloseTableTransaction` + `closureId` + closure journal
  + startup recovery; Sale ≠ collected; typed close events; restore creates a
  new closure instead of rewriting; `Decimal(18,2)` everywhere the ledger
  lives; per-day reconciliation with honest `PARTIAL/LEGACY` provenance.
- **Append-only history**: audit `seq` owned by the POS, Receiving reversals
  beside originals with DB-level idempotency, signed payroll adjustments,
  immutable consumption snapshots keyed to recipe `revision`.
- **Edge transport**: pull-only, leased, idempotent, journaled, versioned
  contract shared through `packages/contracts` with a `--check` generator.
- **Device identity**: one-time codes, Argon2id verifiers, rotation, lifecycle
  states, platform audit of every mutation.
- **Platform Admin foundation**: separate principal, audience-separated
  tokens, thin validated controllers, working UI with integration tests.
- **Inventory model**: derived stock, exact unit conversion rules that refuse
  ambiguous conversions, one active recipe per product enforced by a non-null
  discriminator.
- **Documentation hygiene**: `PROJECT_STATE`/`CODE_MAP`/`DECISIONS` were
  accurate on every claim checked; known blockers were already honest.

---

## AA. Target Architecture (evolution of current code)

```text
Platform (PlatformUser, /platform/*, apps/platform-web/admin)
├── Organizations / Venues (+ identity profile, status: ACTIVE|SUSPENDED|DISABLED)
├── Plans / Feature keys (per module) / Subscription state (manual first)
├── Devices (enroll, lifecycle, credentials) + Sync heartbeat / backlog view
├── Venue access bootstrap (first manager, reset, disable) → Edge STAFF_* commands
├── Domains / WebsiteMode / per-Venue payment credentials (encrypted)
├── Support (read-only, audited Venue inspector; no impersonation)
└── Operations (health, structured logs, alerts on MISMATCH / stale devices)

Venue (Staff, Device, Host principals; all Venue-scoped)
├── POS (local authority: orders, tables, close, printing, business date, menu, staff, settings)
│     └── Edge pull: commands, catalog, feature flags, printer/venue config push
├── Manager (Cloud-driven; Venue-discriminating login; per-Venue socket room)
├── Website (SAAS engine or CUSTOM; Host→Venue)
├── Sales ledger / Financials / Payroll / Obligations (Cloud system of record)
├── Inventory (Cloud system of record; POS read projection)
└── Audit (POS-owned order timelines; venue-wide log; mirrored)
```

Local vs Cloud: keep D001/D002/D014 exactly as they are. Move to Cloud only
what is already Cloud-authoritative (inventory, finance, entitlements,
identity, printer *configuration* as pushed commands — never printing
itself). Add Cloud→POS bootstrap (menu/tables/staff) as an explicit recovery
command set, not as a change of authority.

---

## AB. Recommended Roadmap

### Phase 1 — Multi-tenant Manager & realtime correctness
- **Goal**: a second Venue's manager can log in and receives only their
  Venue's events.
- **Scope**: Venue-discriminating Manager login; per-Venue socket rooms;
  tenant-carrying notifications; remove/scope `/sync/diff`; integration
  tests for both.
- **Dependencies**: none. **Risk**: login contract change for the existing
  Vankisi Manager app (ship backward-compatible bootstrap fallback briefly).
- **Impact**: unblocks Manager as a multi-tenant product.

### Phase 2 — Entitlement keys, subscription state, Platform access bootstrap
- **Goal**: Platform operator controls what each Venue has and whether it is
  commercially active, and can create/reset a Venue's manager.
- **Scope**: seed `INVENTORY`, `PAYROLL`, `FINANCIAL_PLANNING`,
  `PROFITABILITY`, `MANAGER_RESERVATIONS`, `ADVANCED_AUDIT`; route guards;
  effective-features to Manager and POS catalog; `VenueSubscription`
  (manual); Platform Staff bootstrap routes + UI; Platform user management.
- **Dependencies**: Phase 1 for Manager testing. **Risk**: low (additive).
- **Impact**: sellable packages without redeploy.

### Phase 3 — Hosted deployment, backup, observability
- **Goal**: backend runs off the restaurant PC with backups and diagnosis.
- **Scope**: containerized backend; managed PostgreSQL with automated backups
  and a tested restore; HTTPS; health endpoint; structured logs; error
  tracker; sync heartbeat table + Platform Sync tab; CI running unit +
  integration (Postgres service) + Flutter + Vitest + contracts check.
- **Dependencies**: none technically; should precede any second customer.
- **Risk**: migration of Vankisi from LAN server to hosted (POS re-enrolls;
  legacy key retired). **Impact**: SaaS becomes operable and supportable.

### Phase 4 — Onboarding without a developer
- **Goal**: install → enroll → configure → first Sale with no Vynic engineer.
- **Scope**: restaurant-configurable printers (with guardrails), forced
  default-PIN change, Venue identity profile in Cloud pulled by POS, POS
  installer/updater, Cloud→POS bootstrap for replaced terminals, scheduled
  local backups, onboarding checklist in Platform.
- **Dependencies**: Phases 2–3. **Risk**: printer misconfiguration support
  load. **Impact**: onboarding becomes PLATFORM_ADMIN + RESTAURANT only.

### Phase 5 — Security hardening
- **Goal**: close P1 security items.
- **Scope**: show-once/hashed PINs, encrypted POS user box, throttles on all
  logins (persistent store), remove website SUPER_ADMIN, DTO validation, body
  limits, dedicated `PLATFORM_JWT_SECRET`, key-custody runbook for the
  developer signing key.
- **Dependencies**: none. **Risk**: PIN UX change for managers.

### Phase 6 — Website as a product (only if sold)
- **Goal**: second restaurant can have a website.
- **Scope**: generic `SAAS` frontend; Platform/Manager-managed branding,
  hours, tables; per-Venue payment credentials; reservation hold.
- **Dependencies**: Phase 2. **Risk**: scope creep; keep 3D map CUSTOM-only.

### Phase 7 — Product gaps and maturity
- **Scope**: cash management, durable print spool, `Expense` Decimal,
  exports/period lock, waste/stocktake/COGS, sub-MANAGER permissions, audit
  retention, delta sync, multi-instance readiness.

---

## AC. Top 10 Next Actions

1. Implement Venue-discriminating Manager login and delete the bootstrap-Venue
   scan (`auth.service.ts`).
2. Scope socket rooms and `HybridNotificationService` by the sync tenant;
   remove `GET /sync/diff`.
3. Seed module Feature keys and add `@RequiresFeature` per route group;
   expose effective features to Manager and POS.
4. Add `VenueSubscription` (manual state) + Platform UI; gate Manager and
   Website on it.
5. Add Platform routes/UI to create/reset/disable a Venue's manager Staff
   (dispatching `STAFF_UPSERT` to the POS).
6. Stand up hosted backend + managed PostgreSQL with automated backup and a
   restore drill; document production env; retire the LAN-PC deployment for
   new venues.
7. Add health endpoint, structured logging with `venueId`, error tracking,
   and a per-Venue sync heartbeat surfaced in Platform Admin.
8. Make printers restaurant-configurable; force change of the default POS
   PIN; stop returning plaintext PINs.
9. Add throttles to Platform and website logins; remove website
   `SUPER_ADMIN` seeding.
10. Wire CI: backend unit + integration (with PostgreSQL), Flutter tests,
    platform-web tests, contracts `--check`, Prisma migrate check.

---

## AD. STOP

This audit is complete. No production code, schema, migration or database was
modified. Implementation of any item above is a separate, explicitly requested
task.
