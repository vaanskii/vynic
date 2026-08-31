# Platform control plane

**Item 1 is built (Step 7A) — see
[PLATFORM_CONTROL_PLANE_API.md](PLATFORM_CONTROL_PLANE_API.md). Items 2 and 3
remain roadmap only.**

Three related things are recorded here because the architecture keeps arriving at
them and then correctly declining to build them early: a trusted platform
administrator, a restaurant Backoffice, and custom roles.

---

## 1. Platform administrator

Vynic needs a trusted administrator identity, separate from restaurant staff,
able to manage:

```
Organizations · Venues · Plans · Feature overrides
Devices · Domains · Payment integrations · WebsiteMode
future support controls
```

### Why its absence keeps showing up

Every phase so far has hit the same wall and stopped at it deliberately:

| Phase | Mutation deferred | Because |
|---|---|---|
| 5A | plan assignment, feature overrides | `POST /venue/:id/enable-manager` without an admin boundary is a hole |
| 4B2B | domain registration and disabling | same |
| 6A | enqueueing Edge commands | same — `EdgeCommandService.enqueue` has no HTTP route |
| 6B | issuing Device credentials | same — provisioning is a shell script, not an endpoint |
| future | payment credentials | worse: it writes merchant secrets |

**All of these are now unblocked** except payment credentials, which are
deferred on their own merits rather than for want of a boundary. Step 7A built
the principal, the authentication, and the control-plane API for plans, feature
overrides, website mode, domains, devices and device credentials.

In each case the read path, the schema and the service exist and are tested; only
the authenticated write is missing. Step 6B added device provisioning to the
list: `npm run device:issue` requires shell access to the server, which is a real
authorization boundary and deliberately one that self-service onboarding cannot
be built out of. That is the deliberate shape — the control
plane is one boundary to build once, not four half-boundaries scattered across
phases.

### Requirements — all met in Step 7A

- ~~A distinct principal.~~ `PlatformUser`: no `venueId`, no `organizationId`, no
  Staff relation. **Not** a `Staff` row with a bigger role. This is the opposite
  of the Step 4B2A decision, and for the opposite reason — there, `Staff` already
  correctly modelled a restaurant employee.
- ~~Auditable.~~ `PlatformAuditEvent`, deliberately separate from the Venue
  operational audit log.
- ~~Strong authentication.~~ Argon2id passwords; tokens separated from Manager and
  customer tokens by audience, principal type and subject resolution.
- ~~Never reachable from a Manager or website session.~~ Test-proven, including
  for tokens signed with the same secret.

---

## 2. Restaurant Backoffice

A browser-based Backoffice for the restaurant itself, eventually managing:

```
menu · staff · roles · permissions · Venue settings
devices · printer configuration · basic reports
```

**Available to POS Core customers who never buy Manager App.** Manager App stays
an optional mobile product; a restaurant that only bought POS still needs to
administer its own configuration from something other than a POS terminal.

That means the Backoffice is not gated on `MANAGER_APP`. Whether it is gated on
anything at all — a `BACKOFFICE` feature, or simply included with `POS` — is a
commercial decision, and `Feature` rows exist precisely so it can be answered
without a schema change.

**The equivalent controls must not be removed from the POS.** A restaurant with
no Internet still has to be able to change its menu and its staff.

---

## 3. Custom roles

Restaurants must eventually be able to name their own roles.

```
Permission catalogue     controlled by Vynic — the vocabulary
        ↓
Role                     Venue-owned — arbitrary name, selected permissions
        ↓
Staff                    holds a Role
```

Vynic controls the permission catalogue because permissions map to code paths; a
restaurant that could invent a permission would be inventing a capability that
nothing enforces. Role *names* and their permission sets are the restaurant's.

**Nothing may hardcode the eventual system to `OWNER` / `MANAGER` / `WAITER` /
`CASHIER`.** The current `StaffRole` enum and every existing `RolesGuard` check
stay exactly as they are in Step 6A — this is a note about what must not be
assumed, not a change.

Custom RBAC comes **after** the platform-admin and Venue-admin boundaries exist.
Letting a restaurant define roles before there is a trusted boundary deciding who
may define them would just move the missing authorization one level down.

---

## Order

```
Platform administrator identity            ← Step 7A, done
        ↓
control-plane writes                       ← Step 7A, done
(plans, feature overrides, website mode,
 domains, devices, device credentials)
        ↓
Vynic Admin Panel                          ← Step 7B, next
        ↓
Venue administration boundary
        ↓
Restaurant Backoffice
        ↓
custom roles and permissions
```

Each step is the prerequisite for the next, which is why none of them was built
out of order. Payment credentials sit alongside the control-plane writes and are
deferred on their own merits, not for want of a boundary.
