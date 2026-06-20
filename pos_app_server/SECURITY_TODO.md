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
- [ ] **C2. Payment callback signature** — `website/payment/payment.controller.ts`: `verifyCallbackSignature(...)` result is ignored and "no signature" is accepted (L139); reject missing/invalid signatures **before** updating reservation payment state (L166).
- [ ] **C3. Plaintext PIN storage & return** — `mobile/services/mobile-users.service.ts`: stop persisting/returning `staff:plain_pins` (L31 read, L56 return, L100-104 persist). Migrate plaintext PINs out of DB; never sync or display PINs. *(Needs POS-side coordination — POS may currently expect plain PINs in sync.)*
- [ ] **C4. Mobile login brute-force** — `auth/auth.controller.ts` (PIN-only login) + `auth/auth.service.ts` (checks every manager hash, issues 24h JWT, L33/L49): add rate-limiting + lockout + audit trail; consider device binding, shorter/revocable JWT.
- [ ] **C5. POS callback URL SSRF / rogue-POS** — `pos/sync.controller.ts` persists attacker-suppliable `posCallbackUrl`/`posConnectionKey` (L321); `pos/pos-callback.client.ts` later `fetch()`es it (L53). Allowlist URL to LAN/private IP ranges; add device identity + signed callbacks + nonce/timestamp/idempotency.
- [ ] **C6. `/sync/diff` unauthenticated** — `pos/sync.controller.ts` (L271) exposes live table/order deltas with no `PosSyncGuard`/JWT. Add the guard. *(Smallest fix, near-zero blast radius — good quick win.)*

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
