# Platform control plane API

**Step 7A.** The trusted boundary five previous phases stopped at, and the
control-plane API it unlocks.

Companion documents: [PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md)
(the roadmap this closes the first item of),
[PLATFORM_ADMIN_PANEL.md](PLATFORM_ADMIN_PANEL.md) (the Step 7B consumer),
[PRODUCT_ENTITLEMENTS.md](PRODUCT_ENTITLEMENTS.md),
[PUBLIC_TENANCY.md](PUBLIC_TENANCY.md),
[CLOUD_EDGE_TRANSPORT.md](CLOUD_EDGE_TRANSPORT.md),
[PAYMENT_INTEGRATIONS.md](PAYMENT_INTEGRATIONS.md).

---

## The principal

```
Platform Admin
      ↓  platform authentication
Control Plane authorization
      ↓
Organizations · Venues · Products · Domains · Devices
```

A Vynic administrator is **not** a `Staff` row, a restaurant MANAGER or OWNER, a
`WebsiteUser`, or a `Device`. `PlatformUser` holds no `venueId`, no
`organizationId` and no Staff relation, because a platform administrator sits
above every tenant. Giving one a restaurant membership would invent an ownership
that does not exist and would let tenant-scoped code mistake an operator for an
employee.

This is the opposite of the Step 4B2A decision, for the opposite reason: there,
`Staff` already correctly modelled a restaurant employee, so no new entity was
invented. Here nothing correctly models a Vynic operator, so one exists.

| | `PlatformUser` | `Staff` | `WebsiteUser` | `Device` |
|---|---|---|---|---|
| Belongs to a Venue | **no** | yes | no | yes |
| Credential | password (Argon2id) | PIN (bcrypt) | password (Argon2id) | secret (Argon2id) |
| Token audience | `vynic-platform` | none | none | n/a |
| Reaches control plane | **yes** | no | no | no |

`PlatformRole` has one value, `SUPER_ADMIN`. It is an enum rather than a boolean
because finer Vynic support/operator roles are expected and must not arrive as a
second flag column. Authorization never depends on a hardcoded email or id.
Restaurant custom roles are a **different domain** and are not this.

---

## Authentication

```
POST /platform/auth/login   { email, password }  → { access_token, expiresIn, actor }
GET  /platform/auth/me                           → the principal
```

Every other control-plane route carries `PlatformAuthGuard` and
`Authorization: Bearer <token>`. There are no unauthenticated convenience
endpoints in the module: one would be the hole this phase exists to close.

### Why a Manager token cannot be replayed here

Manager and website tokens are both signed with `JWT_SECRET` and neither carries
a principal type, so *route prefixes are not a security boundary*. Three
independent barriers are:

1. **Audience.** Platform tokens are issued for `vynic-platform` and verified
   with `audience` set, so the JWT library itself rejects a token that lacks it.
2. **Principal type.** `typ: 'PLATFORM'`, which no other token has.
3. **Subject resolution.** The subject is looked up in `PlatformUser`, so a
   Staff id or a WebsiteUser id names nothing.

A Manager token fails all three. A disabled administrator is refused on their
**next request**, not when their token expires, because everything but the
subject is re-read.

Session length is 8 hours — an administrative session, not a POS shift.

---

## First administrator

There is no Admin Panel to create one from, and a seeded default password would
be a worse hole than the missing boundary. So:

```bash
npm run platform-admin:create -- --email you@example.com --name "Your Name"
```

- The password is **never** an argument — arguments land in shell history and the
  process table. It is prompted for with echo disabled and typed twice.
  `PLATFORM_ADMIN_PASSWORD` covers a non-interactive run.
- Minimum 12 characters; hashed with Argon2id, the same primitive the rest of
  the backend uses.
- **Refuses to touch an existing account.** Silently resetting a password from a
  script is how an account is taken over by whoever can run it twice. A
  deliberate reset mechanism can be added when there is an authenticated
  administrator to authorize it.
- Prints the id, email, name and role. Never the password, never the hash.

Requiring shell access is an authorization boundary that already exists, and one
self-service onboarding cannot be built out of.

---

## API surface

Everything below requires a platform token.

| | |
|---|---|
| `GET /platform/organizations` | paginated (`limit` ≤ 200, `offset`) |
| `POST /platform/organizations` · `GET`/`PATCH /:id` | |
| `GET /platform/venues` | paginated, `?organizationId=` |
| `POST /platform/venues` · `GET`/`PATCH /:venueId` | |
| `PUT /platform/venues/:venueId/status` | ACTIVE / DISABLED |
| `GET /platform/plans` · `GET /platform/features` | catalogue |
| `GET /platform/venues/:venueId/product` | plan, overrides, effective features, website access |
| `PUT /platform/venues/:venueId/plan` | |
| `PUT`/`DELETE /platform/venues/:venueId/features/:featureKey` | override / inherit |
| `PUT /platform/venues/:venueId/website` | WebsiteMode |
| `GET`/`POST /platform/venues/:venueId/domains` | |
| `PUT /platform/venues/:venueId/domains/:domainId/status` · `DELETE …/:domainId` | |
| `GET /platform/venues/:venueId/devices` · `GET …/:deviceId` | never a hash |
| `POST /platform/venues/:venueId/devices` | **returns the credential once** |
| `PUT /platform/venues/:venueId/devices/:deviceId/status` | ACTIVE / DISABLED / REVOKED |
| `POST /platform/venues/:venueId/devices/:deviceId/credential` | rotate |
| `POST /platform/venues/:venueId/test-command` | NOOP only |
| `GET /platform/venues/:venueId/test-command/:commandId` | read NOOP lifecycle and Edge result |
| `GET /platform/audit` | the platform's own trail; `limit`, `offset`, optional `targetId` |

Controllers validate and delegate; the rules live in the services next to the
invariants they protect. Nothing untyped reaches Prisma: UUIDs, enums, feature
keys, hostnames, text lengths and currency codes are all checked first.

Pagination is a bounded `limit`/`offset` (default 50, hard ceiling 200). The
backend has no pagination abstraction to reuse, and a cursor scheme or a search
layer would be building for a scale that does not exist yet.

### No delete

Organizations and Venues have no delete route. They are referenced by orders,
tables, staff, devices, bookings and domains under **restrictive** foreign keys,
so a delete either fails or would have to cascade through a restaurant's entire
history. Disabling a Venue is the reversible operation that answers the real
need, and it is what the API offers instead.

### Venue creation creates a Venue

No tables, no menu, no device, no domain, no plan. Each of those is a separate
deliberate act with its own audit row. The id is generated: the deterministic
bootstrap ids belong to the existing Vankisi installation and are never handed to
a second customer.

---

## Product configuration

Entitlement is **never** recomputed here. Every answer comes from
`VenueEntitlementsService` — the same resolver `FeatureGuard` uses in
production. A second implementation inside the control plane would be a second
truth, and the one an administrator saw would be the one nobody enforces. This
is test-proven: an override set through the API changes what the production
guard decides.

Precedence is unchanged: **a Venue override always wins over its plan.** That is
why exceptions do not require inventing a plan that then has to be maintained
forever. Deleting the override row is the third state — defer to the plan.

`WebsiteMode` and the `WEBSITE` entitlement stay independent. Setting `CUSTOM`
on a Venue without `WEBSITE` is allowed and reported as `consistent: false`
rather than refused or silently rewritten. The administrator is told what they
have, not corrected.

---

## Domains

Step 4B2B deferred domain mutation until exactly this boundary existed.

Hostnames are normalized by `normalizeHostname` — the same function the public
request path uses — so what is stored is exactly what an incoming `Host` is
compared against. A second normalizer would eventually disagree, and the
disagreement would look like a domain that simply does not work.

- Globally unique: registering a hostname already taken is a **409**, because
  silently re-pointing a live domain at another restaurant is the failure the
  constraint exists to prevent.
- `DISABLED` stops serving while keeping the name reserved.
- Releasing frees it for anyone.
- Another Venue's domain reads as **404**, not 403.
- Production still fails closed on an unknown Host.

No DNS management, TLS provisioning, registrar integration or wildcards.

---

## Devices

`credentialHash` is **never selected**, so no serialization mistake can leak it —
absence by construction rather than deletion afterwards.

`lastSeenAt` is returned raw. Deriving an `ONLINE` flag would require choosing a
freshness window, and an unstated window is a claim the API cannot back up.

### Credentials

```
POST .../devices              → { device, credential }   ← the only time it exists
GET  .../devices/:deviceId    → no credential, no hash, ever
POST .../devices/:id/credential → a new credential, the old one already dead
```

Only the Argon2id verifier is stored, so a lost credential is **rotated, not
recovered**. Rotation overwrites the verifier in the same write that returns the
new secret: there is never a window where two credentials are valid, which is the
point when one is believed exposed.

`DISABLED` and `REVOKED` both stop `verifyCredential` immediately. The
distinction is intent — a terminal out of service versus a credential believed
compromised — and it is kept because an audit trail that cannot tell them apart
is worth less.

Delivery to the machine is unchanged: the Admin Panel will later display the
one-time credential, and the `edge_device_provision.txt` drop file remains the
manual path. Nothing installs a credential remotely.

---

## Edge test command

`POST /platform/venues/:venueId/test-command` queues a `NOOP`, addressed to a
Device or to the Venue.

There is deliberately **no way to name a type or a payload**. Arbitrary command
creation would route straight around the declared registry and the idempotency
rule the queue depends on; this route *is* the NOOP, so there is nothing to
bypass. The 18 legacy callback command types are not migrated here — that is 6C.

---

## Audit trail

`PlatformAuditEvent`: who, what action, what target, when, and safe metadata.

Kept apart from `AuditEventLog`, which records what restaurant staff did inside a
Venue. Writing a platform action there would claim an employee changed a plan or
revoked a device — precisely the wrong answer to "who did this?". Test-proven:
control-plane mutations write no operational audit rows.

Audited: organization create/update · venue create/update/status · plan
assignment · feature override set/removed · website mode · domain
registered/status/released · device created/status · **credential issued and
rotated** (the event, never the credential) · edge test command.

Recording never blocks the action it describes — a mutation that succeeded must
not be reported as failed because its audit row could not be written. Metadata
never carries a password, a credential or a hash, which is asserted in tests.

---

## Not in this phase

Deliberately absent, with reasons already recorded:

- **Support access to restaurant data** — orders, payments, customer PII. When it
  exists it must be explicit and separately audited, not a side effect of being
  an administrator.
- **Payment credentials.** BOG stays process-wide `.env` for the Vankisi
  deployment; nothing was migrated into PostgreSQL. Platform Admin will own
  per-Venue encrypted provider credentials later — see
  [PAYMENT_INTEGRATIONS.md](PAYMENT_INTEGRATIONS.md).
- **Billing and subscriptions.** Plan assignment is not a subscription and did
  not become one.
- **Restaurant Backoffice.** A different product for a different audience.
  Restaurants must never log in as a `PlatformUser`.
- **Restaurant custom roles.** Vynic-controlled permission catalogue plus
  Venue-owned role names, after a Venue administration boundary exists.
- **Admin Panel UI.** Built in Step 7B; see
  [PLATFORM_ADMIN_PANEL.md](PLATFORM_ADMIN_PANEL.md).
