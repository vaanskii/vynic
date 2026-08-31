# Product entitlements and website mode

Step 5A introduces the commercial layer that sits **above** the Step 4A/4B
tenancy foundation. Ownership answers *who* a row belongs to. Entitlement
answers *what that Venue has bought*.

```text
Organization
    └── Venue
          ├── Plan assignment ──→ Plan ──→ Features
          ├── Feature overrides
          ├── Website configuration (mode)
          └── Device(s)
```

## Four separate concepts

Keeping these apart is the whole point of the model. Collapsing any two of
them is what forces a schema redesign later.

| Concept | Question it answers | Persistence |
| --- | --- | --- |
| **Plan** | Which commercial package was sold? | `pos.Plan`, `pos.PlanFeature` |
| **Feature** | Which capability exists in the product? | `pos.Feature` |
| **Entitlement** | May *this* Venue use that capability? | resolved: plan features + `pos.VenueFeatureOverride` |
| **Configuration** | How does an enabled capability behave? | `pos.VenueWebsiteConfig` |

A Plan is commercial packaging and carries no application logic. Nothing in
the backend branches on a plan key. Code asks for a **feature**; the plan is
only one of the inputs that decides whether the Venue has it.

## Features

Features are rows, not an enum, so a later capability (`RESERVATIONS`,
`ADVANCED_REPORTS`, `INTEGRATIONS`, …) is a seed insert rather than a schema
migration. Step 5A seeds only the three capabilities the product actually
sells today:

| Key | Meaning |
| --- | --- |
| `POS` | The point-of-sale product itself. |
| `WEBSITE` | The Venue has a restaurant website product. |
| `MANAGER_APP` | The Venue has the mobile Manager product. |

`Feature.key` is the stable identifier used by code. `Feature.name` is a
display value and may be changed freely.

## Plans

Step 5A seeds the four packages the business requires today:

| Key | Features |
| --- | --- |
| `POS` | `POS` |
| `POS_WEBSITE` | `POS`, `WEBSITE` |
| `POS_MANAGER` | `POS`, `MANAGER_APP` |
| `POS_WEBSITE_MANAGER` | `POS`, `WEBSITE`, `MANAGER_APP` |

These names describe feature composition. They are **not** marketing names and
carry no pricing. The relational `Plan → PlanFeature → Feature` shape means a
fifth or fiftieth package is data, not a code change, so nothing here should be
read as "Vynic sells exactly four things".

`Plan.status` (`ACTIVE` / `RETIRED`) lets a package stop being sold without
breaking the Venues already assigned to it. Retiring a plan does not revoke
anything — resolution ignores plan status deliberately, so a grandfathered
customer keeps working.

## Venue plan assignment, and why it is not a subscription

A Venue receives a package through `pos.VenuePlanAssignment`, which holds one
row per Venue (`venueId` is unique) pointing at one Plan, with `assignedAt`.

This is deliberately **not** a Subscription model. No billing lifecycle has
been decided, so none was invented: there is no price, currency, period,
renewal, trial, invoice, payment-provider customer ID, or status machine
anywhere in this schema. The boundary is:

- **Plan assignment** — an operational fact about what a Venue may use. Exists now.
- **Billing subscription** — the commercial agreement that pays for it, with
  its own lifecycle. Explicitly deferred.

When billing arrives it can reference the assignment (or supersede it) without
touching feature resolution. Billing ownership may well settle at Organization
level; access evaluation stays Venue-aware regardless.

Assignment is per Venue, not per Organization. One Organization may own a
`POS_WEBSITE` Venue and a `POS_MANAGER` Venue at the same time.

A Venue with no assignment row has no plan features. That is a valid state
(newly provisioned), not an error.

## Venue feature overrides

`pos.VenueFeatureOverride` is one row per (Venue, Feature) with an explicit
effect:

| Effect | Meaning |
| --- | --- |
| `ENABLED` | Venue has the feature even if its plan does not include it. |
| `DISABLED` | Venue does not have the feature even though its plan includes it. |

**Precedence: an override always wins over the plan default.** The absence of a
row is a third state — "defer to the plan" — which is why the column is an
enum rather than a boolean.

This exists so a special agreement, a temporary beta, a manual enable, or a
grandfathered customer does not require inventing a new Plan. `note` records
why the exception exists.

## Effective feature resolution

One authoritative implementation:
`apps/backend/src/entitlements/venue-entitlements.service.ts`.

```text
Venue
  ↓
VenuePlanAssignment → Plan → PlanFeature → Feature.key      (base set)
  ↓
VenueFeatureOverride                                        (ENABLED adds, DISABLED removes)
  ↓
effective feature keys
```

Examples:

| Plan | Overrides | Effective |
| --- | --- | --- |
| `POS_WEBSITE` | — | `POS`, `WEBSITE` |
| `POS_WEBSITE` | `MANAGER_APP` = `ENABLED` | `POS`, `WEBSITE`, `MANAGER_APP` |
| `POS_WEBSITE_MANAGER` | `WEBSITE` = `DISABLED` | `POS`, `MANAGER_APP` |
| none | `POS` = `ENABLED` | `POS` |
| none | — | *(none)* |

No controller, guard, or service may re-derive this. There is deliberately no
`if (plan === 'FULL')` anywhere in the codebase, and adding one would be a bug.

## Website entitlement versus website mode

Two different questions, two different fields:

```text
WEBSITE feature      → is the Venue entitled to a restaurant website at all?
VenueWebsiteConfig   → if so, which website implementation serves it?
```

`WebsiteMode`:

| Mode | Meaning |
| --- | --- |
| `NONE` | No restaurant website product. |
| `SAAS` | The future generic Vynic SaaS restaurant website. |
| `CUSTOM` | A restaurant-specific custom website build. |

`CUSTOM` and `SAAS` are **configuration of one feature**, not two commercial
features. Selling "the website" is one line item; which implementation serves
it is an operational detail that can change without changing the package.

Website mode lives in its own model rather than a `Venue` column because
`Venue` currently holds tenant identity only (name, status, timezone,
currency), and because later SaaS website configuration (branding, menu
presentation, domain) has an obvious home to grow into without another
migration against the operational tenant root.

### Consistency

The expected pairing is:

```text
WEBSITE not entitled  → mode NONE
WEBSITE entitled      → mode SAAS or CUSTOM
```

This is **validated, never silently repaired**. The resolution service reports
`configuredMode` (what is stored), `effectiveMode` (`NONE` unless entitled),
and `consistent`. An inconsistent pair is visible to a future control plane
rather than being mutated behind an administrator's back — losing a stored
`CUSTOM` because an entitlement lapsed for a day would be worse than
reporting it.

Entitlement is also not deployment. "This Venue is entitled to a custom
website" says nothing about whether that website is built, deployed, or
healthy. Deployment status is a later concern — see
[CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md).

## Manager App entitlement rule

`MANAGER_APP` governs **product access only**. It must never reach the
synchronization path.

Disabling `MANAGER_APP` may eventually deny Manager product access, Manager
Cloud API access, and Manager notifications. It must **never**:

- stop POS → Cloud synchronization,
- stop Device authentication,
- stop the Cloud operational mirror or core data storage,
- delete or stop retaining historical data,
- affect platform/device health.

A customer who buys Manager six months late must find their history already
there. That is only true if sync ran the whole time, so entitlement sits
strictly above sync.

## Cloud sync is infrastructure

The same invariant stated generally:

```text
POS → Device auth → Venue → Cloud sync        (infrastructure — always on)
─────────────────────────────────────────────
Plan / Feature / Entitlement                   (commercial — optional, above)
```

No optional commercial feature may gate Device authentication, POS sync,
required operational data mirroring, tenant ownership, or sync health.
`WEBSITE = false` likewise must not break POS sync. Product access is a layer
above core synchronization infrastructure, never inside it.

POS itself stays offline-capable. Taking an order, printing, managing and
closing a table, and closing the business day must keep working while Cloud is
unreachable; they are never gated on a live entitlement check. Offline
commercial licensing is a separate, deferred problem and was not redesigned
here.

## Not the developer licence

The repository already has an Ed25519 developer/support licence with its own
scopes (`DeveloperScope` in `apps/operations/`, signed by `apps/devtool/` — see
[DEVELOPER_ACCESS.md](DEVELOPER_ACCESS.md)). It is unrelated and was reused for
nothing:

| | Developer licence | Product entitlement |
| --- | --- | --- |
| Grants access to | Support/diagnostic tools on one terminal | Commercial product capabilities |
| Audience | Vynic staff | The paying customer |
| Lives | Offline, POS-local, signed token | PostgreSQL, Venue-scoped |
| Answers | "May this engineer wipe this terminal?" | "Did this restaurant buy the Manager app?" |

## Bootstrap Venue (Vankisi)

The Step 4A bootstrap Venue is the existing Vankisi installation. It is
grandfathered so the migration disables nothing it can do today:

| | Value |
| --- | --- |
| Plan | `POS_WEBSITE_MANAGER` |
| Effective features | `POS`, `WEBSITE`, `MANAGER_APP` |
| Website mode | `CUSTOM` |

`apps/venue-web/` is that custom website and is untouched by this step. Step 5A
*records* product access and configuration; it does not change any frontend
runtime, and nothing in `apps/venue-web/` reads these tables.

## Enforcement status

`@RequiresFeature(...)` and `FeatureGuard` (`apps/backend/src/entitlements/`)
are a working, tested primitive.

Since Step 4B2A they are applied to the Manager product API (`/mobile/*`),
whose requests now carry an authoritative Venue resolved from the authenticated
Staff identity — see [MANAGER_TENANT_AUTH.md](MANAGER_TENANT_AUTH.md). They
remain attached to no POS sync route, no device route, and no website route:
sync must never be gated on entitlement, and website requests still lack
authoritative Venue identity (Step 4B2B).

The guard fails closed when no authenticated tenant is present, which is why it
may only be attached to routes that have one.

There are no product-management mutation APIs. Creating them would require a
platform-admin authorization boundary that does not exist yet; a
`POST /venue/:id/enable-manager` without one would be a hole, so plan
assignment and override writes are deferred to the platform control plane.
