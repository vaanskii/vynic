# Vynic Security Audit

**Date:** 2026-07-21 · Read-only review of source, config, git history, and dependencies.
Severity: **Critical / High / Medium / Low**. "Blocks production" = must fix before Vankisi runs real money/staff data on it.

---

## Summary

No committed live secrets were found (`.env*` and `secrets/` are correctly gitignored; git history shows only `.env.example` files ever added). Server auth architecture is better than typical (fail-closed sync guard, JWT-verified WebSocket, throttled PIN login, signed BOG callbacks, strict CORS, whitelisted DTO validation). The dominant risk is the **staff PIN lifecycle**: plaintext at rest on the POS, plaintext in transit every full sync, recoverable by design on the server, with a hardcoded default manager PIN.

| # | Finding | Severity | Blocks prod |
|---|---|---|---|
| S-1 | Plaintext staff PINs in Hive + sent on every full sync | **Critical** | YES |
| S-2 | Recoverable server-side PIN vault | High | YES (policy) |
| S-3 | Hardcoded default manager `vaanskii` / PIN `000000` | High | YES |
| S-4 | POS ingest server: fail-open auth, 0.0.0.0 bind, plain HTTP | High | YES |
| S-5 | Dependency vulns: 2 high, 1 moderate | High | YES (trivial) |
| S-6 | Shared destructive-action password ≠ individual approval | Medium | no |
| S-7 | Unencrypted Hive data dir (orders, sales, audit) | Medium | no |
| S-8 | PIN-only login namespace (4–6 digits, shared space) | Medium | no |
| S-9 | Mobile JWT: 24 h, no revocation/refresh | Medium | no |
| S-10 | `dev.db` tracked in git; stray build artifacts | Low | no |
| S-11 | Verbose money/PIN-adjacent logging | Low | no |
| S-12 | In-memory login throttle resets on restart | Low | no |

---

## Findings

### S-1 · Plaintext staff PIN pipeline — **Critical**
**Evidence:**
- `apps/operations/lib/core/models/user.dart:12` — `String pinCode;` plain Hive field; `user_repository.dart:authenticateByPin` compares plaintext.
- `manager_sync_service.dart:862-872` — every **full** sync sends `'pin': u.pinCode` for all staff to `POST /sync/manager-data`.
- `docs/SYNC_CONTRACT.md` §7.2 explicitly forbids this ("Do not send plaintext PINs in manager-data staff array") — the contract's own mandate is unmet. The server interface comment (`sync.controller.ts:78` "routine POS sync must not send PINs") documents the intent; the client violates it.
**Impact:** anyone with the POS disk, a Hive backup, or a network position (if `BACKEND_URL` is plain HTTP) obtains every staff PIN — which is also the **mobile manager login credential** (`auth.service.ts:mobileLogin` authenticates managers by the same PIN).
**Remediation:** hash PINs on the POS (per-user salt; store hash in Hive), verify locally against hash; provision/change PINs to the server only through the explicit user-management callbacks (which already exist: `/mobile-user-create`, `/mobile-user-update-pin`); strip `pin` from the routine staff sync payload; require HTTPS `BACKEND_URL` in production.

### S-2 · Recoverable server PIN vault — High
**Evidence:** `staff-pin-vault.service.ts` stores the plaintext PIN map AES-256-GCM-encrypted in `Setting['staff:plain_pins']`, key derived from `COOKIE_ENCRYPTION_KEY`. Encrypted ≠ hashed: any server compromise that reads env + DB recovers all PINs. It exists so managers can *view* PINs in the mobile app.
**Remediation:** drop the view-PIN feature (reset-only flow, like every mature POS); delete the vault after S-1 lands. Rotate all PINs when doing so.

### S-3 · Hardcoded default admin — High
**Evidence:** `user_repository.dart:createDefaultAdmin` seeds `username: 'vaanskii', pinCode: '000000', role: 'manager'` on fresh install.
**Impact:** a fresh/reset terminal (see H-3 data-dir reset scenario) silently reintroduces a known manager PIN.
**Remediation:** first-run setup wizard forces choosing a manager PIN; never ship a constant.

### S-4 · POS ingest server hardening — High
**Evidence:** `pos_ingest_server.dart` — `_isAuthorized` **returns `true` when no key is configured** (line 149-154, fail-open); binds `InternetAddress.anyIPv4` (line 43); transport is plain HTTP; the connection key travels to the server in sync payloads and back in headers.
Mitigations already present: key auto-generated via `ensurePosIngestConnectionKey()`; server-side SSRF guard only allows private/LAN callback URLs (`pos-callback-url.ts`, verified referenced in `sync.controller.ts:persistPosCallback`).
**Impact:** on the restaurant LAN (staff Wi-Fi, guest Wi-Fi if not segmented), an attacker who reaches :8081 in a keyless state can create/cancel orders, change PINs (`/mobile-user-update-pin`!), delete users.
**Remediation:** fail **closed** (reject when key missing); bind to the specific LAN interface; rate-limit; long random key rotation from admin; document network segmentation (POS VLAN) as a deployment requirement.

### S-5 · Dependency vulnerabilities — High
**Evidence:** `npm audit` (2026-07-21): **2 high** (multer ≤2.0.2 chain via `@nestjs/platform-express`), **1 moderate** (protobufjs 7.5.0–7.6.4 DoS). Fix available via `npm audit fix`.
**Remediation:** run the fix, pin, add CI audit gate. Flutter deps not scanned (no `dart pub audit` equivalent run); `pubspec.lock` is committed ✓.

### S-6 · Shared destructive-action password — Medium
**Evidence:** `settings_repository.dart:486-523` — one global salted-hash password gates deletes/voids; audit rows attribute to the logged-in user, but the *authorizer* is unproven (anyone who knows the shared secret).
**Remediation:** manager-PIN approval dialog (enter any manager's own PIN → identity recorded in the audit event). Cheap; big accountability win.

### S-7 · Hive at rest unencrypted — Medium
**Evidence:** `database_core.dart:open()` — all boxes opened without `encryptionCipher`.
**Impact:** POS disk/backup exposure of orders, sales, customer names/phones (reservations), PINs (until S-1).
**Remediation:** after S-1, encrypt at minimum `users` and `reservations` boxes with `HiveAesCipher` keyed from Windows DPAPI/keystore.

### S-8 · PIN-only shared login namespace — Medium
**Evidence:** `authenticateByPin` scans all users; PINs 4–6 digits, uniqueness enforced (`isPinCodeExists`); server mobile login iterates bcrypt across all manager-role staff (`auth.service.ts`).
**Impact:** small keyspace; server side is throttled (5/15 min per IP — `login-throttle.service.ts` ✓) but POS side has no local lockout.
**Remediation:** local lockout after N failures; 6-digit minimum for manager roles.

### S-9 · Mobile JWT lifecycle — Medium
**Evidence:** `auth.service.ts` — 24 h expiry, no refresh rotation, no server-side revocation list; `jwt.strategy.ts` validates signature+expiry only.
**Remediation:** short access + refresh rotation, or at least a `tokenVersion` claim checked against Staff row so PIN change / deactivation kills sessions.

### S-10 · Repository hygiene — Low
**Evidence:** `apps/backend/dev.db` tracked (SQLite, tables empty — verified with sqlite3; added in commit 19a9b4e); `flutter_01.png/.log`, `deps.json` tracked. `firebase_options.dart` + `google-services.json` committed (normal for Firebase client apps; API keys there are not secret by design).
**Remediation:** `git rm --cached dev.db` etc., extend `.gitignore`.

### S-11 · Logging — Low
**Evidence:** `[Sync][MoneyDebug]` logs revenue figures server-side (`sync.controller.ts:499-507, 1282-1295`); POS logs full reservation/customer dumps at close-day (`close_day_transaction.dart:64-81`). No PINs logged (verified grep).
**Remediation:** demote to debug level; scrub customer PII from routine logs.

### S-12 · Login throttle survivability — Low
**Evidence:** `login-throttle.service.ts` in-memory (self-documented as adequate for single instance).
**Accepted for single-server deployment;** revisit at SaaS.

---

## Checked and found acceptable [verified]

- **CORS** (`main.ts`): explicit allow-list + dev-only LAN regex gated on `NODE_ENV`, credentialed.
- **Validation**: global `ValidationPipe { whitelist, forbidNonWhitelisted, transform }` — mass-assignment guarded (website DTOs exist; sync payload interfaces are typed but unvalidated depth — acceptable behind PosSyncGuard, worth adding schema validation later).
- **PosSyncGuard**: fail-closed in production when `POS_SYNC_API_KEY` unset.
- **WebSocket**: JWT verified in `server.use` middleware; unauthenticated sockets rejected; broadcasts only to `managers` room (`monitoring.gateway.ts`).
- **BOG callback**: RSA-SHA256 over preserved raw bytes; rejected before any state change (`payment.controller.ts:handlePaymentCallback`). Server-side price recalculation defeats cart manipulation (`validateAndCalculateOrder`).
- **Website auth**: argon2-hashed refresh tokens, encrypted cookie access token, CSRF service, roles guard.
- **Git history**: no `.env`, key, or dump files ever committed (checked `git log --all --diff-filter=A` patterns).
- **SSRF**: POS callback URL restricted to private ranges before persistence.

---

## Production security checklist (condensed)

1. S-1→S-4 fixed and verified end-to-end (PIN hash-only everywhere, no PIN in sync, ingest fail-closed, no default PIN).
2. `npm audit fix` applied; CI gate added.
3. HTTPS on `BACKEND_URL` (cloud) — POS↔cloud must not carry auth headers over plain HTTP.
4. POS + printers on an isolated VLAN; guest Wi-Fi segregated; :8081 unreachable from guest network.
5. `JWT_SECRET`, `POS_SYNC_API_KEY`, `COOKIE_ENCRYPTION_KEY` rotated from any dev values; ≥32 random bytes.
6. `dev.db` and stray artifacts removed from the repo.
7. Postgres backups + Hive data-dir backup schedule tested (restore drill).
