# Platform control plane

**Roadmap only. Step 6A built none of this.**

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
| future | payment credentials | worse: it writes merchant secrets |

In each case the read path, the schema and the service exist and are tested; only
the authenticated write is missing. That is the deliberate shape — the control
plane is one boundary to build once, not four half-boundaries scattered across
phases.

### Requirements when it is built

- A distinct principal. **Not** a `Staff` row with a bigger role: restaurant
  staff belong to a Venue, and a platform administrator belongs above all of
  them. This is the opposite of the Step 4B2A decision, and for the opposite
  reason — there, `Staff` already correctly modelled a restaurant employee.
- Auditable: who changed which Venue's plan, domain, or credentials, and when.
- Strong authentication, since it reaches every tenant.
- Never reachable from a Manager or website session.

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
Platform administrator identity
        ↓
control-plane writes (plans, domains, devices, payment credentials)
        ↓
Venue administration boundary
        ↓
Restaurant Backoffice
        ↓
custom roles and permissions
```

Each step is the prerequisite for the next, which is why none of them was built
out of order.
