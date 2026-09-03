# POS enrollment

**Status:** implemented (Phase 1C). The analysis it came from is
[POS_ENROLLMENT_ANALYSIS.md](./POS_ENROLLMENT_ANALYSIS.md), which is now
history: sections 1 and 2 describe what this replaced.

How a new POS terminal gets a Vynic identity, and how to run the whole thing on
one desk.

Related: [DEVICE_IDENTITY.md](./DEVICE_IDENTITY.md),
[CLOUD_EDGE_TRANSPORT.md](./CLOUD_EDGE_TRANSPORT.md),
[PLATFORM_CONTROL_PLANE_API.md](./PLATFORM_CONTROL_PLANE_API.md)

---

## 1. What changed

Before, a credential reached a terminal one way:

```text
Platform Admin ──► create Device ──► copy the raw secret out of the browser
                                            │
operator ──► write it into edge_device_provision.txt beside the data directory
operator ──► separately type the backend address into the POS admin panel
```

Two unrelated manual steps in the right order, a long-lived secret handled by a
person, and no confirmation on either side that it worked.

Now:

```text
Platform Admin ──► "Enrol a POS" for a Venue
                        │
                   one-time code, 12 characters, minutes to live
                        │
POS  ──► Connect this POS to Vynic ──► server address + code
                        │
        POST /edge/enroll  { enrollmentCode, installationId, platform }
                        │
  backend ─ verifies the code, claims it, mints the Device credential
          ─ creates the Device, or reuses this installation's existing one
          ─ returns the credential once, with the Venue it belongs to
                        │
POS  ──► persists the credential, confirms it landed, keeps the address
     ──► starts sync and Edge polling, shows "Enrolled — <Venue>"
                        │
Platform Admin ──► the enrollment flips to ENROLLED, and a Device appears
```

**The file path still works.** `edge_device_provision.txt` is absorbed on
startup exactly as before, and an installation provisioned that way keeps
running untouched. It is the support path now, not the onboarding path.

## 2. The code

```text
7K2Q - M4XB - 9TFR
└──┘   └──────────┘
selector   secret
```

Crockford base32 with no I, L, O or U, because this is read off a screen and
typed on a till. `I` and `L` are read as `1` and `O` as `0` on input rather than
refused — there is exactly one sensible reading of each.

The split mirrors the Device credential: `codeSelector` is stored in the clear
and indexed, `codeHash` is an Argon2id verifier of the secret half. That is what
makes a lookup one indexed read instead of an Argon2 verification against every
live enrollment, which on an unauthenticated route would be a denial-of-service
surface. Forty bits of secret, single use, minutes to live, five attempts.

The selector may collide; creation retries. Widening what a human types to avoid
a retry would be the wrong trade.

## 3. Authority

```text
Platform Admin (authenticated PlatformUser)
        │  creates an enrollment bound to one Venue
        ▼
enrollment code ── redeemed by a terminal ──► Device ──► Venue
```

**The POS never sends a `venueId`.** It cannot name the restaurant it would like
to join; the enrollment an administrator created decides that, and the response
reports which Venue it turned out to be so the operator can check before
trusting the till. `/edge/enroll` is not a general device-creation endpoint and
must not become one.

Everything downstream is unchanged: `Device credential → Device → Venue` is
still the only tenant authority for a POS.

## 4. Order of checks

The order *is* the security boundary.

| # | Check | On failure |
|---|---|---|
| 1 | per-IP rate limit | `429` |
| 2 | `installationId` is a UUID, `platform` present | `400` |
| 3 | code parses to 12 valid characters | `400` |
| 4 | per-selector rate limit | `429` |
| 5 | selector exists | `401`, one generic message |
| 6 | durable attempt ceiling not reached | `401`, same message |
| 7 | Argon2 verify of the secret half | `401`, same message, attempt counted |
| 8 | not cancelled / not expired | `401`, **specific** reason |
| 9 | Venue is ACTIVE | `401` |
| 10 | already redeemed by another installation | `409` |
| 11 | this installation belongs to another Venue | `409` |

Steps 5–7 return one indistinguishable answer, so a guessed selector teaches an
attacker nothing. From step 8 the caller has proved it holds the real code, and
"expired" versus "already used" are different actions for the same person, so
they are told apart.

Rate limiting is an in-process fixed-window counter. With several backend
processes it is per-process, which still bounds the total; the ceiling that
actually protects one code is `DeviceEnrollment.attemptCount`, which survives a
restart and fails that code closed.

## 5. Reinstall, retry, and moving a terminal

`installationId` is a UUID the POS mints on first run and keeps. It is what makes
all three cases behave.

| Situation | What happens |
|---|---|
| New terminal | A Device is created for this installation. |
| Reinstall / repair, same installation, new code | The **existing** Device is reused and its credential rotated. One terminal, one Device, and the old secret is dead the moment the new one is issued. |
| Same code redeemed again from the **same** installation | Rotates and re-issues. This is the recovery path — see below. |
| Same code from a **different** installation | `409`. Single use means single terminal. |
| A code for Venue B typed into a terminal already enrolled in Venue A | `409`. Nothing is created, and the terminal stays with Venue A. |
| Enrolling a `DISABLED` or `REVOKED` Device | Reinstated as `ACTIVE` with a new credential, because the administrator who minted the code authorized exactly that. The revoked secret stays dead. Recorded in the audit metadata with the status it came from. |

**Moving a terminal between Venues is never a side effect of typing a code.** It
requires a deliberate platform action against the Device.

### The recovery path

The credential is issued once. A POS that received one and failed to write it to
disk would otherwise be stranded with a spent code. So:

- the POS **reads the file back** after writing and only then reports success;
- a failed write leaves nothing half-applied — the terminal is still unenrolled
  in memory too;
- redeeming the same code again from the same installation rotates and re-issues
  until the code expires.

## 6. Lifecycle

Enrollment status is derived from timestamps, never stored, so a row cannot say
one thing while its own fields say another:

```text
cancelled ──► CANCELLED
redeemed  ──► ENROLLED
past its expiry ──► EXPIRED
otherwise ──► PENDING          ("Waiting for enrollment" in the admin panel)
```

There is no `ONLINE`. Nothing can honestly report it; `Device.lastSeenAt` says
when a terminal last authenticated and no more.

Device status is unchanged and there is still **no hard delete**:

- **DISABLED** — temporarily out of service. Reversible; no credential is rotated.
- **REVOKED** — this credential must never authenticate again. Not a delete: the
  row, its command history and its audit trail all stay, and the terminal can
  only come back through a new enrollment.

## 7. What the audit trail records

| Action | When | Target |
|---|---|---|
| `device.enrollment_created` | an administrator mints a code | Venue |
| `device.enrollment_cancelled` | an administrator kills one early | Venue |
| `device.enrollment_redeemed` | a terminal enrolls | Device |
| `device.enrollment_failed` | a valid selector, refused | Venue |

`PlatformAuditEvent.platformUserId` is required, and a redemption is performed by
a machine. It is attributed to **the administrator whose enrollment code
authorized it**, with `redeemedBy: "device"` in the metadata so nobody reads it
as an administrator having created a device by hand.

**One honest gap:** an attempt with a selector that matches no enrollment has no
row, so no Venue to hang the event on and no administrator to attribute it to.
It is counted by the rate limiter and logged, not written to the platform trail.
Inventing an actor would be worse than the gap.

No code, no secret and no verifier is ever written to the trail. A test asserts
it.

## 8. The response, and the backend URL

```jsonc
{
  "enrollmentId": "…",
  "device":  { "id": "…", "installationId": "…", "displayName": "…", "platform": "WINDOWS", "status": "ACTIVE" },
  "venue":   { "id": "…", "name": "Vankisi", "timezone": "Asia/Tbilisi", "currency": "GEL" },
  "credential": "vynic-device-v1.<deviceId>.<secret>",   // once, and only here
  "apiBaseUrl": null,
  "edgeContractVersion": 1,
  "reusedExistingDevice": false,
  "enrolledAt": "2026-09-03T10:00:00.000Z"
}
```

`apiBaseUrl` comes from the optional `DEVICE_API_BASE_URL`. **Leave it unset in
local development.** `API_URL` exists so payment callbacks can find their way
back to the process and is loopback locally; handing that to a till on another
machine would break the connection that had just worked.

When it is unset the POS keeps the address it enrolled through — which is by
definition an address that reaches the server. When it is set the POS adopts it,
*except* a loopback answer offered to a terminal that reached the server on a
real address, which is ignored for the same reason.

## 9. Where it lives

| | |
|---|---|
| Model | `DeviceEnrollment`, migration `20260903090000_device_enrollment` |
| Service | `apps/backend/src/edge/device-enrollment.service.ts` |
| Route | `POST /edge/enroll` — `device-enrollment.controller.ts`, no guard |
| Control plane | `GET/POST /platform/venues/:venueId/enrollments`, `DELETE …/:enrollmentId` |
| Admin UI | `apps/platform-web/src/platform/pages/venue/VenueEnrollmentPanel.tsx` |
| POS client | `apps/operations/lib/core/services/edge/edge_enrollment_client.dart` |
| POS flow | `…/edge/pos_enrollment_service.dart` |
| POS UI | `…/widgets/admin/admin_pos_enrollment_panel.dart`, in Settings → Connection and on the login screen while unenrolled |

The migration is purely additive: one table, its indexes and three foreign keys.
Nothing existing is touched, so an installation that never enrolls is unaffected.

## 10. Running it locally

Nothing here is hosted. This is a laptop, a LAN and a till.

**1. PostgreSQL.** Whatever you already run. `DATABASE_URL` in
`apps/backend/.env` points at it.

```bash
cd apps/backend && npx prisma migrate deploy
```

**2. Backend.** It already binds `0.0.0.0`, so the LAN reaches it.

```bash
cd apps/backend && npm run start:dev
```

Find the address the POS should use — the machine's LAN IP, not localhost:

```bash
ipconfig getifaddr en0
```

That gives `http://<that address>:3000`. Confirm the terminal can reach it, from
the terminal's own machine:

```bash
curl http://<backend LAN IP>:3000/
```

**3. Platform Admin.**

```bash
cd apps/platform-web && npm run dev
```

Open `http://localhost:5173/admin`. If it is a fresh database, create the first
administrator first:

```bash
cd apps/backend && npm run platform-admin:create -- --email you@example.com --name "Your Name"
```

**CORS.** `http://localhost:5173` is allowed by default. A LAN origin on port
5173/5174/4173 is allowed outside production. Anything else needs
`ALLOWED_ORIGINS` in `apps/backend/.env`. The POS is not a browser and is not
subject to CORS at all.

**Firewall.** macOS will ask to allow incoming connections for `node` the first
time a device on the LAN connects. Both machines must be on the same network,
and client isolation (common on guest Wi-Fi) will block it silently.

**4. POS.**

```bash
cd apps/operations && flutter run -d macos --dart-define=APP_ROLE=pos
```

**5. Enrol.** In Platform Admin: a Venue → **Devices** → **Enrol a POS**. Name
the terminal, pick a validity, and the code is shown once.

On the POS: **Connect this POS to Vynic** on the login screen, or
**Settings → კავშირი და მონაცემები → Vynic Cloud**. Enter
`http://<backend LAN IP>:3000` and the code. The panel then names the Venue it
enrolled into, and the admin table flips to **Enrolled** within a few seconds.

**6. Prove the round trip.** Make any change on the POS — open a table, take an
order — and it appears in the backend within a sync cycle. Then, in Platform
Admin, **Send connection test**: the NOOP goes `QUEUED → CLAIMED → SUCCEEDED`
once the POS polls (2–30s depending on whether it just drained work).

**Running the integration tests.** They are skipped unless pointed at a
disposable database, and they must never point at the one you develop against:

```bash
psql -d postgres -c "CREATE DATABASE vynic_it;"
cd apps/backend
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/vynic_it" npx prisma migrate deploy
TENANT_INTEGRATION_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/vynic_it" npx jest
```

## 11. What this does not change

- **Offline-first.** Enrollment is not a runtime dependency. Stop the backend and
  the POS keeps opening tables, printing and closing the day. Start it and sync
  and Edge polling resume on their own, with no re-enrollment.
- **The credential's storage boundary.** Still `edge_device.json` in the
  per-user data directory, owner-only where POSIX allows, deliberately outside
  the Hive box a backup serializes. Still not an OS keychain — Windows DPAPI and
  macOS Keychain remain deferred, as recorded in
  [CLOUD_EDGE_TRANSPORT.md](./CLOUD_EDGE_TRANSPORT.md).
- **Step 6C.** The 18 legacy callback commands are untouched. `NOOP` is still the
  only Edge command type, and the retirement conditions for the legacy path are
  unchanged except that the fourth one — every deployed POS holding a Device
  credential — now has a path that scales past a hand-written file.
- **Venue Policy.** Not started. See [VENUE_POLICY_PLAN.md](./VENUE_POLICY_PLAN.md).

## 12. Deferred

- **QR.** The code is short enough to type, which is the requirement. Rendering a
  QR needs a library in Platform Admin; the code is returned as a plain string
  and would be trivial to encode later.
- **A trusted-proxy client IP.** Rate limiting reads `request.ip`. Behind a proxy
  that is the proxy. `TRUST_PROXY_HOST` exists for host resolution but Express's
  `trust proxy` is not set, so this is accurate on a LAN and would need attention
  before a hosted deployment.
- **Bulk enrollment.** One code, one terminal. A restaurant opening with six
  tills creates six.
