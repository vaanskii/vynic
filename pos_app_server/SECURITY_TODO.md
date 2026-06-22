# Server Security & Architecture TODO

Source: security/architecture review (2026-06-21). Worked **one step at a time, on approval**, each build-verified and committed separately. File/line refs are from the review and re-verified at execution time.

Legend: `[ ]` todo · `[x]` done · 🔴 critical · 🟠 high · 🟡 medium

---

## ✅ Already done
- [x] Fail-closed secrets — `JWT_SECRET`, `COOKIE_ENCRYPTION_KEY` throw on boot if missing (commit `dd9f8b0`).
- [x] `PosSyncGuard` fails closed in production when `POS_SYNC_API_KEY` unset (commit `cf27901`). *(Review lists this under "Good Design Decisions".)*

---

## 🔴 P0 — Critical security
- [x] **C1. WebSocket lockdown** — `realtime/monitoring.gateway.ts`: (1) reject sockets with no/invalid JWT (`next(new Error('unauthorized'))`); (2) emit only to the `managers` room (`server.to('managers').except(...)`), never `server.emit` to all; (3) `cors: '*'` → `isAllowedSocketOrigin` (env allowlist; native clients with no Origin always allowed). **Verified safe:** only the mobile app connects and it always sends the JWT (`setAuth({token})`); the Windows POS does **not** use this socket (gets changes via HTTP callbacks). JWT + rooms is also the SaaS-ready pattern. *App must connect the socket only after login (post-login token); on token expiry the socket is rejected until re-login — correct behavior.*
- [x] **C2. Payment callback signature** — now **mandatory**: rejects missing/invalid signatures with 401 before any state change; verifies against the **raw request bytes** (added `rawBody` capture in `main.ts`), not `JSON.stringify(body)`. ⚠️ **Must be tested against a real BOG sandbox callback before production** — the accept path (genuine BOG signature) can't be verified locally; if raw bytes don't match what BOG signed, real callbacks would be rejected. Rejection logs `[BOG] Rejected payment callback...` for diagnosis.
- [x] **C3. Plaintext PIN storage** — chose **Option A** (managers/POS keep view/set; encrypt at rest). New `auth/staff-pin-vault.service.ts` (`StaffPinVault`) AES-256-GCM-encrypts the `staff:plain_pins` map; key derived from `COOKIE_ENCRYPTION_KEY` (distinct salt). Single source of truth for both `mobile-users.service.ts` and the POS staff sync in `sync.controller.ts` (also de-duplicated their inline read/write). Backward compatible — legacy cleartext rows read transparently and re-encrypt on next write; tampering fails closed. API still returns plaintext PIN to authenticated managers and syncs to POS (unchanged client behavior) — only DB-at-rest is now encrypted. *(Future hardening if ever wanted: Option B show-once, or restrict who can read PINs.)*
- [x] **C4. Mobile login brute-force** — added `LoginThrottleService` (in-memory, per-IP): 5 failed PINs → IP locked 15 min → `429`; success resets; lockouts logged (audit trail). *(Remaining C4 ideas left for later: device binding, shorter/revocable JWT. In-memory state resets on restart — fine for single server.)*
- [x] **C5. POS callback URL SSRF** — added `pos/pos-callback-url.ts` (`isAllowedPosCallbackUrl`): only http(s) to private/loopback IPv4 (`10/8`, `172.16/12`, `192.168/16`, `127/8`) or `localhost`; rejects public IPs, `169.254.x` cloud-metadata, and arbitrary hostnames (DNS-rebinding). Enforced in **two layers**: `persistPosCallback` (never persist a bad URL) and `PosCallbackClient.setCallbackUrl` (never hold one we'd `fetch()`, also covers legacy DB rows). *(Deeper C5 ideas — signed callbacks, device identity, nonce/timestamp/idempotency — left for later; the allowlist removes the SSRF blast radius.)*
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
- [ ] **A6. POS-offline resilience — mirror POS reservation/table state into PostgreSQL** *(do LAST — larger change, depends on A2/A3 sync work).* Today reservation reads do a **live HTTP fetch to the POS** (`posCallbackUrl` → `GET /mobile-reservations`). When the POS app is **closed**, that fetch fails (logs `POS reservations fetch/unavailable … fetch failed`), so **both**:
  - the **website** can't compute table availability → risk of double-booking a POS-reserved table, and
  - the **manager app's** reservation list (`/mobile/reservations` → `fetchPosReservations`) returns empty.

  Necessary data must stay available while the POS is offline. **Fix:** have the POS push reservation + table state on sync (like it already does for orders) and persist it in PostgreSQL; the **website availability check** and the **manager app** both read reservation state **from the DB**. The live POS fetch becomes a best-effort freshness refresh, never the sole source of truth.

- [ ] **C7. Website login has no rate-limiting** — `/api/auth/signin` + `/signup` (`website/auth/auth.controller.ts`) have no throttle. Lower urgency than C4 (email + argon2, not a 4-digit PIN), but reuse the `LoginThrottleService` (key by IP, or IP+identifier) to cap credential-stuffing.
