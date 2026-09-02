# POS registration and device lifecycle

> **Superseded by [POS_ENROLLMENT.md](./POS_ENROLLMENT.md).** Section 3 below
> was the recommendation; Phase 1C built it, with two deliberate departures —
> no placeholder Device is created at invitation time, and the canonical backend
> URL is returned only when the deployment declares one, because a server's own
> idea of its address is loopback in local development. Sections 1 and 2 remain
> accurate as a description of the **file-drop path**, which still works and is
> now the support path rather than the onboarding path.

**Status:** the analysis that Phase 1C was built from.

What it took to put a new Vynic POS on a venue's counter before enrollment
existed, and the smallest self-service flow that could replace it.

Related: [POS_ENROLLMENT.md](./POS_ENROLLMENT.md),
[DEVICE_IDENTITY.md](./DEVICE_IDENTITY.md),
[CLOUD_EDGE_TRANSPORT.md](./CLOUD_EDGE_TRANSPORT.md),
[PLATFORM_CONTROL_PLANE.md](./PLATFORM_CONTROL_PLANE.md)

---

## 1. How a brand-new POS was registered before Phase 1C

```text
Platform Admin ──► POST /platform/venues/:venueId/devices        (creates the Device row)
                   POST .../devices/:deviceId/credential         (mints the secret, shown once)
                          │
                          │  the raw credential leaves the browser by hand
                          ▼
operator ──► writes  edge_device_provision.txt  next to the POS data directory
                          │
POS start-up ──► EdgeDeviceCredentialStore.load()
                   ├─ creates installationId on first run
                   ├─ absorbs the provision file
                   ├─ writes edge_device.json
                   └─ deletes the provision file
```

Step by step:

1. **Create the Device.** `PlatformVenuesController` exposes
   `POST /platform/venues/:venueId/devices`, authenticated as a `PlatformUser`
   and written to `PlatformAuditEvent`. `apps/backend/scripts/issue-device-credential.ts`
   does the same from a shell, and its own header says it is transitional and
   deliberately not an endpoint.
2. **Mint the credential.** `POST .../devices/:deviceId/credential` returns the
   raw secret **once**. Only an Argon2id verifier is stored. There is no
   recovery — a lost secret means rotate.
3. **Manual file step.** The operator saves the raw credential into
   `edge_device_provision.txt` in the POS data directory. This is the only
   channel: there is no endpoint that hands a credential to an unauthenticated
   POS, and no UI that accepts one.
4. **Absorption.** On the next start, `EdgeDeviceCredentialStore.load()` reads
   the file, validates the `vynic-device-v1.<deviceId>.<secret>` shape, writes
   `edge_device.json` (owner-only where the platform supports it), and deletes
   the provision file. A malformed value is rejected rather than persisted.

### Answers to the specific questions

| Question | Answer |
| --- | --- |
| **Manual file steps** | Exactly one: place `edge_device_provision.txt` in the data directory. |
| **Where the backend URL comes from** | `ApiConfig.baseUrl`, in priority order: the admin-saved Hive override, then `BACKEND_URL_<PLATFORM>` / `BACKEND_URL` from `.env`, then the same as `--dart-define`, then a localhost fallback. It is **not** part of enrollment — a new terminal needs its URL set separately, by hand, in the developer/connection panel. |
| **How `installationId` is created** | A v4 UUID minted by the POS on first `load()` and stored in `edge_device.json`. It survives credential rotation; it is not a hardware id. |
| **How the credential is absorbed** | Read once from the provision file, validated, stored, and the source file deleted. Never in the Hive settings box, so it cannot end up inside `BackupRepository.createDataBackup` output. |
| **How success is visible** | Indirectly. The POS logs a resolved URL and the Device's `lastSeenAt` starts moving (throttled, updated at the guard). There is no "enrolled" confirmation on either side — the admin sees a Device that has been seen recently, or one that never has. |
| **If provisioning fails** | Silently, by design. `load()` never throws: the POS starts and takes orders with no Cloud identity. A malformed credential is not saved. Nothing tells the operator; they discover it when sync does not work. |
| **Can a terminal be reprovisioned?** | Yes. `POST .../devices/:deviceId/credential` rotates: a new secret replaces the verifier, the old one stops authenticating, and dropping a new provision file overwrites the stored credential. `installationId` is unchanged. |
| **How a terminal is disabled** | `PUT .../devices/:deviceId/status` with `DISABLED`. The guard rejects non-`ACTIVE` Devices, so authentication stops immediately. Reversible. |
| **How a terminal is revoked** | The same route with `REVOKED`. Identical enforcement; the difference is intent and what the audit trail says. |
| **Why hard delete does not exist** | There is no delete route, and that is correct rather than an omission. `Device` is referenced by `EdgeCommand.deviceId` and by `PlatformAuditEvent` targets, and it is the subject of a security history — which terminal authenticated, when, and what it was sent. Deleting the row would orphan queued work and erase the record of a device that may have been compromised. |

## 2. What is wrong with it

- **It cannot be self-service.** Every path requires either a `PlatformUser`
  session plus a human copying a secret, or shell access to the server.
- **The secret travels by copy-paste** through whatever the operator uses to
  get it onto the machine.
- **Two unrelated manual steps.** The credential and the backend URL are
  configured through different surfaces, and getting one right without the
  other produces a terminal that looks configured and does not sync.
- **Failure is invisible on both ends.** No enrollment confirmation, no error
  the operator can act on.

## 3. Recommended self-enrollment flow

```text
Platform Admin
  └─ "Enrol a terminal" for a Venue
       └─ generates a one-time enrollment code (short, typeable) + QR
          · bound to one Venue
          · single use, short TTL (minutes)
          · stored as a verifier, like the Device credential
                    │
POS first run ──────┤  registration screen: enter code (or scan)
                    │
       POST /edge/enroll  { code, installationId, platform, appVersion }
                    │   ── unauthenticated by design, but the code is the credential
                    ▼
       backend ─ validates code, marks it spent
               ─ creates or reuses the Device for this installationId
               ─ mints the credential, returns it once
               ─ returns the canonical backend URL for this Venue
                    │
POS  ───────────────┤ stores the credential in edge_device.json
                    │ stores the backend URL
                    └ shows "Enrolled — <Venue name>"
                    │
Platform Admin ─────┘ sees the Device flip to enrolled, with its first contact
```

Design points that matter:

- **The code is the only secret the human handles**, it is short-lived, and it
  is useless once spent. The long-lived credential never passes through a
  person.
- **`installationId` carries reuse.** Enrolling a terminal that already has one
  should rotate its credential rather than create a second Device — that is
  what makes a reinstall safe.
- **The URL comes back with the credential.** One step, not two.
- **The enroll route is the only unauthenticated write.** It must be rate
  limited per code and per IP, and every attempt — success or failure — must be
  written to `PlatformAuditEvent`.
- **Enrollment is not entitlement.** A Device belongs to a Venue; what that
  Venue may do is still `effectiveFeatures`.

### Should Device hard-delete exist?

**No.** `DISABLED` and `REVOKED` are the correct lifecycle and the current
model already has both:

- `DISABLED` — temporarily out of service. Reversible, and the intent is
  operational.
- `REVOKED` — this credential must never authenticate again. The intent is
  security, and the row is the evidence.

A hard delete would orphan `EdgeCommand` rows that reference the device, break
the `PlatformAuditEvent` trail that names it, and destroy exactly the record
someone investigating an incident needs. If the admin list becomes cluttered,
the answer is a filter, not a `DELETE`. The one legitimate case — a Device
created by mistake that never authenticated — is better served by a narrowly
scoped rule (no `lastSeenAt`, no commands, created within the hour) if it ever
proves necessary, and even then it should leave an audit event behind.
