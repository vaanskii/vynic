# Server Security & Architecture TODO

Source: security/architecture review (2026-06-21). Worked **one step at a time, on approval**, each build-verified and committed separately. File/line refs are from the review and re-verified at execution time.

Legend: `[ ]` todo · `[x]` done · 🔴 critical · 🟠 high · 🟡 medium

---

## ✅ Already done
- [x] Fail-closed secrets — `JWT_SECRET`, `COOKIE_ENCRYPTION_KEY` throw on boot if missing (commit `dd9f8b0`).
- [x] `PosSyncGuard` fails closed in production when `POS_SYNC_API_KEY` unset (commit `cf27901`). *(Review lists this under "Good Design Decisions".)*

---

## 🔴 P0 — Critical security
- [ ] **C1. WebSocket lockdown** — `realtime/monitoring.gateway.ts`: remove `cors: { origin: '*' }` (L18); reject unauthenticated sockets (currently `return next()` accepts missing/invalid JWT, ~L51); emit to an authenticated manager room instead of `this.server.emit(...)` broadcast to all (L104-106). *Note: touches how the mobile app connects — verify client sends JWT.*
- [x] **C2. Payment callback signature** — now **mandatory**: rejects missing/invalid signatures with 401 before any state change; verifies against the **raw request bytes** (added `rawBody` capture in `main.ts`), not `JSON.stringify(body)`. ⚠️ **Must be tested against a real BOG sandbox callback before production** — the accept path (genuine BOG signature) can't be verified locally; if raw bytes don't match what BOG signed, real callbacks would be rejected. Rejection logs `[BOG] Rejected payment callback...` for diagnosis.
- [ ] **C3. Plaintext PIN storage & return** — `mobile/services/mobile-users.service.ts`: stop persisting/returning `staff:plain_pins` (L31 read, L56 return, L100-104 persist). Migrate plaintext PINs out of DB; never sync or display PINs. *(Needs POS-side coordination — POS may currently expect plain PINs in sync.)*
- [x] **C4. Mobile login brute-force** — added `LoginThrottleService` (in-memory, per-IP): 5 failed PINs → IP locked 15 min → `429`; success resets; lockouts logged (audit trail). *(Remaining C4 ideas left for later: device binding, shorter/revocable JWT. In-memory state resets on restart — fine for single server.)*
- [ ] **C5. POS callback URL SSRF / rogue-POS** — `pos/sync.controller.ts` persists attacker-suppliable `posCallbackUrl`/`posConnectionKey` (L321); `pos/pos-callback.client.ts` later `fetch()`es it (L53). Allowlist URL to LAN/private IP ranges; add device identity + signed callbacks + nonce/timestamp/idempotency.
- [x] **C6. `/sync/diff` unauthenticated** — added `@UseGuards(JwtAuthGuard, RolesGuard)` + `@Roles(MANAGER)` (commit `a6fa575`). Used **JWT, not PosSyncGuard**: the route is mobile-facing (client `_get` sends JWT Bearer; the endpoint is currently unused, so no caller broke).

---

## 🟠 P1 — High (architecture / correctness)
- [ ] **A1. Split `SyncController`** (god endpoint) into focused units: PosIngest / OrderSync / MenuSync / StaffSync / SalesSync / AuditSync. Manager-data route starts `pos/sync.controller.ts` L298.
- [ ] **A2. Transactional DB-mutation + outbox-enqueue** — `mobile/services/mobile-orders.service.ts`: items deleted/recreated (L167), order updated (L205), outbox enqueue is fire-and-forget (L315). A crash between commit and enqueue = split-brain. Wrap in one transaction.
- [ ] **A3. Route ALL POS-bound mutations through the outbox** — expenses/users/reservations use direct `posCallback` calls (e.g. `mobile-dashboard.service.ts` L502) and silently diverge if POS is offline.
- [ ] **A4. Reservation race** — `website/reservation/reservation.service.ts`: availability check (L125) then create (L139) with no DB-level uniqueness. Add unique constraint / locking on (date, tableId, blocking status).
- [ ] **A5. Conflict resolution beyond last-writer-wins** — add version / event-sequence / device-id / compare-and-swap for POS vs mobile order/table changes. *(Largest design item.)*

---

## 🟡 P2 — Medium
- [ ] **M1. DTOs + runtime validation** — mobile uses `body: any` (`mobile.controller.ts` L203, L348); POS sync uses TS interfaces only (no runtime effect). Add DTO classes with numeric/date/status bounds (the global `ValidationPipe` already exists — it just needs real DTOs).
- [ ] **M2. Body limit + rate limiting** — `main.ts` L39 allows 50mb JSON for every route; scope large limit only where needed; add global rate limiting.
- [ ] **M3. DB indexes** — `Order`: `businessDate`/`status`/`floor`/`createdAt` (schema L26-39); `WebsiteReservation`: `date`/`status` (L370-387); `Expense`: `createdAt`.
- [ ] **M4. Report query perf** — `mobile-reports.service.ts` (L132, L452) loads full order/item sets; paginate/aggregate before history grows.
- [ ] **M5. JWT re-checks staff active status** — deleted/disabled managers keep access until token expiry; re-validate in `JwtStrategy.validate`.

---

## Preserve (already good — do not regress)
Outbox pattern · Prisma-first data access · global `ValidationPipe` (whitelist + forbidNonWhitelisted) · server-side checkout pricing · httpOnly encrypted cookies + argon2 (website) · the two fail-closed fixes above.

---

## Recommended execution order
`C6` (quick win) → `C1` → `C2` → `C4` → `C3` → `C5` → `A2` + `A3` → `A4` → `A1` → `M1` → `M3` → `M5` → `M2` → `M4` → `A5`.
Each step: read+verify code → minimal change → build → commit → stop for review.

---

## Added during review
- [ ] **A6. Website reservation availability depends on a live POS fetch** — `WebsitePosReservationBridgeService` HTTP-fetches `posCallbackUrl` (`GET /mobile-reservations`) on every availability check. When the POS app is **offline**, the fetch fails (logs `POS reservations fetch/unavailable ... fetch failed`) and the website can't see POS-side bookings → risk of double-booking a POS-reserved table. Fix: **mirror POS reservations into PostgreSQL** (like orders) so the website reads reservation state from the DB, resilient to the POS being offline; treat the live fetch as a best-effort refresh, not the source of truth. Relates to A3/A4.
