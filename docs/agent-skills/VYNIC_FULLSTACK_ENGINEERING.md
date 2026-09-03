# Vynic Full-Stack Engineering Protocol

This is the canonical, tool-neutral engineering protocol for work in the Vynic
repository. It describes the current cross-stack system and the reasoning
required before changing it. It is not a generic style guide and it does not
authorize work beyond the task at hand.

Vynic currently spans Flutter, Hive, NestJS, Prisma, PostgreSQL, React, shared
generated contracts, multi-tenant Cloud services, and an offline-first POS
Edge. Historical instructions that describe Vynic as merely a single-restaurant
application or say that the SaaS migration has not started are stale.

## Source-of-truth hierarchy

When sources disagree, use this order of authority:

1. current production code;
2. current Prisma schema;
3. applied migrations and current repository migrations;
4. tests;
5. generated and shared contracts;
6. current architecture documentation;
7. git history;
8. older prompts, old agent reports, stale comments, and stale instructions.

Previous task summaries are useful discovery context, not repository authority.
Do not blindly obey a document that conflicts with implemented and tested
architecture. Trace the live path, compare the schema and migrations, inspect
tests, and report the conflict. Do not silently choose whichever source is most
convenient.

## 1. Inspect before editing

For every non-trivial task, establish the following before implementation:

- the runtime entry point and current implementation;
- the domain's data owner and persistence layer;
- the authentication principal and authorization boundary;
- the authoritative tenant-resolution path;
- all callers and consumers, including background workers and scripts;
- every network boundary crossed;
- compatibility obligations for deployed clients and existing data;
- relevant unit, integration, migration, and end-to-end tests;
- configuration and deployment implications.

Do not begin an architecture change by immediately writing code. Search from
the entry point through controllers, services, persistence, contracts, clients,
and tests until the ownership and failure semantics are clear.

For substantial work, record at least:

```text
Current state
Target state
Affected modules and layers
Compatibility constraints
Security implications
Tenant implications
Migration implications
Validation plan
Explicit non-goals
```

If the requested design conflicts with repository reality, investigate and
surface the conflict before implementing it.

## 2. Mandatory cross-stack impact analysis

Before changing code, explicitly assess whether the task affects each of these
areas. “No impact” is a valid and often correct result; consideration does not
mean every layer should be modified.

- PostgreSQL data and constraints;
- Prisma schema and migrations;
- NestJS domain/application services;
- controllers and DTOs;
- authentication and authorization;
- Organization/Venue tenancy;
- plans, features, and entitlements;
- shared or generated contracts;
- Flutter POS;
- Flutter Manager;
- Hive persistence and migrations;
- Cloud↔Edge transport;
- React Platform Web;
- React Venue Web;
- environment variables and secrets;
- deployment and existing installations;
- tests and architecture documentation.

Use the result to limit the change to necessary layers, not to justify a broad
refactor.

## 3. Data authority is domain-specific

Vynic has no single universal source of truth for every domain.

### Operational state

The POS/Edge remains authoritative during restaurant operation for live
operational state, including:

- orders and live tables;
- local checkout and payment flow;
- the business-day boundary;
- LAN printing and local peripheral execution.

PostgreSQL is a tenant-scoped Cloud mirror and coordination store for many of
these concerns. Do not turn that mirror into a mandatory dependency of service
at the restaurant.

### Administrative configuration

The long-term direction is:

```text
Cloud administrative authority
        ↓
complete POS local/offline cache
```

This applies to configuration such as menu, staff, roles, permissions, Venue
settings, and printer configuration. Some of these paths remain transitional
or locally editable today. Do not invent merge, precedence, or conflict rules
inside an unrelated task. Preserve the current behavior until a dedicated
architecture phase defines and migrates the authority model.

## 4. Offline-first POS invariant

The following must not require a successful Cloud request:

- creating or editing orders;
- opening or closing tables;
- the local payment workflow;
- printing;
- business-day close;
- reading the cached menu;
- reading cached staff and settings.

Network loss may delay synchronization, control-plane work, remote visibility,
or other Cloud-dependent features. It must not stop normal restaurant
operation. Never block POS startup waiting for Cloud. Background Edge transport
must fail independently of operational workflows.

Hive is production persistence. It is not a disposable cache or temporary UI
state merely because PostgreSQL also contains a representation of the data.

## 5. Multi-tenant architecture

The persistent ownership hierarchy is:

```text
Organization
└── Venue
```

An Organization is the customer or business account. A Venue is one physical
restaurant/location and is the operational tenant boundary. Tenant-owned
identifiers and uniqueness constraints are generally Venue-scoped where the
domain requires it.

Do not introduce global-single-restaurant assumptions. The deterministic
Vankisi bootstrap Organization and Venue preserve an existing installation;
they are compatibility data, not evidence that the architecture remains
single-tenant.

## 6. Tenant authority

Resolve tenancy only through a server-owned relationship:

```text
POS:
Device credential → Device → Venue

Manager:
authenticated Staff → Staff.venueId

Public website:
Host → VenueDomain → Venue

Payment callback:
server-owned reservation/payment identity → Venue

Platform Control Plane:
authenticated PlatformUser → explicit cross-tenant authority
```

Never trust a client-supplied `venueId` or `organizationId` as authority. A
route may accept an ID as the object being addressed, but authentication and
server-owned relationships must decide whether the actor may address it.

Production public website resolution fails closed for unknown, malformed,
disabled, or unregistered hosts. Development-only localhost fallback is not a
production tenancy mechanism. Payment-provider callbacks derive ownership from
the server-owned booking referenced by the provider, not from Host or a request
field.

The legacy shared POS sync key is transitional compatibility. It can resolve
the bootstrap tenant but cannot identify a Device and therefore cannot
authorize Device-specific Edge leases.

## 7. Principal separation

Keep these principals distinct:

| Principal | Meaning | Tenant relationship |
| --- | --- | --- |
| `PlatformUser` | Vynic operator | Explicit authority above restaurant tenants; no Staff/Venue membership |
| `Staff` | Restaurant employee using POS/Manager capabilities | Owned by exactly one Venue |
| `WebsiteUser` | Restaurant website customer | Separate website identity; bookings establish Venue-owned domain data |
| `Device` | One POS installation | Owned by exactly one Venue; machine credential, not human session |

A Platform administrator is not “powerful Staff.” A restaurant Owner/Admin
must not become a `PlatformUser`. A Device credential must not be accepted as a
human session. Manager and Website identities are not interchangeable.

Tokens and guards must prevent principal confusion even when signing-secret
compatibility exists. Use audience, principal type, subject lookup, and the
appropriate guard for the boundary. Re-resolve mutable authority from
server-owned records where the current implementation does so; do not trust
stale role or tenant claims merely because they are signed.

## 8. Plans, features, and website mode

The product model is conceptually:

```text
Plan → bundled Features
VenuePlanAssignment
VenueFeatureOverride → ENABLED | DISABLED
effectiveFeatures(venueId)
```

Rules:

- a Plan is commercial packaging, not technical authorization;
- never branch product behavior on a plan name or key;
- ask the authoritative entitlement resolver, currently
  `VenueEntitlementsService`/`effectiveFeatures`;
- a Venue override wins over the plan default;
- frontend clients must not reimplement entitlement precedence;
- retirement of a Plan does not implicitly revoke existing assignments;
- POS authentication, POS→Cloud sync, and Edge transport infrastructure must
  not be disabled by a commercial entitlement.

The `WEBSITE` Feature and `WebsiteMode` answer different questions:

```text
WEBSITE feature: may this Venue use a restaurant website?
WebsiteMode: NONE | SAAS | CUSTOM — which implementation is configured?
```

Configuration is not proof of deployment, health, or entitlement. Use the
authoritative website-access result when those concepts must be combined.

## 9. Website architecture

`apps/venue-web/` is the current custom Vankisi website. Its bespoke branding,
layout, floor plans, and booking UX are not scaffolding for a generic product.
Do not silently convert it into the future multi-Venue SaaS website.

The generic SaaS restaurant website is a separate future product surface unless
an explicit architecture decision changes that. Custom runtime/deployment
ownership also remains an open design area even though public API tenant
resolution is implemented.

Both custom and future SaaS website traffic use the authoritative backend
boundary:

```text
Host → VenueDomain → Venue
```

Neither website may select its own Venue through a request body, query, or
client-controlled tenant header.

## 10. Cloud↔Edge architecture

The target direction is:

```text
POS / Edge initiates connections to Cloud
```

Cloud must not require routable access to private restaurant LAN addresses.
For Cloud-originated work, use the persistent lifecycle:

```text
persistent command
→ Edge claim/lease
→ local execution
→ durable local execution journal
→ acknowledgment
```

Delivery is **at least once**, not exactly once. A lease can expire after local
execution but before acknowledgment, so every production command must be
idempotent or have an explicit, durable safe-execution boundary. The shared
command contract and handler catalogue must declare and enforce that property;
do not assume an operation such as printing is naturally safe to replay.

`EdgeCommand` is Venue-owned and may target a specific Device. The authenticated
Device determines which Venue and Device can claim work. Do not widen queue
filters from request fields. `CLAIMED` means leased, not completed;
`SUCCEEDED`/`FAILED` require an Edge-reported outcome.

The v2 contract currently contains `NOOP` plus seventeen real business command
types. All have POS handlers; mutations converge through `PosCommandApplier`,
and interrupted physical prints use the explicit no-repeat boundary. See
`docs/EDGE_COMMAND_MIGRATION.md` for the catalogue and rollout state.

## 11. Legacy callback infrastructure

Direct Cloud/server→POS LAN callback code and `PosCallbackOutbox` still exist as
a frozen fallback for Venues without an enrolled Device and for compatible
rollout. They are transitional compatibility, not the long-term Cloud
architecture.

- Preserve them until explicit retirement conditions are met.
- Do not add new command types to the legacy mechanism.
- Do not remove or rewrite them opportunistically.
- Route new operations only through the Edge command catalogue and its
  idempotency boundary.
- Keep POS→Cloud snapshot ingestion; it already follows the correct
  Edge-initiated direction and is separate from command delivery.

Synchronous reservation reads now use the Cloud-side `PosReservation` mirror.
Legacy removal still requires a Device credential on every deployed POS; the
existence of enrollment code does not prove the fleet has enrolled.

## 12. Synchronous Edge reads

A persistent command queue is not automatically a synchronous request/response
transport. Do not implement this shortcut:

```text
HTTP request → enqueue command → wait indefinitely for POS
```

It couples request latency and availability to a possibly offline restaurant.
Choose an explicit design appropriate to the domain, such as a Cloud-side
mirror, a bounded request/result job, or another specified protocol. Define
timeouts, ownership, retry behavior, and what a stale result means.

## 13. Printer boundary

The printer boundary is:

```text
Cloud → command/configuration → POS Edge → LAN printer
```

Cloud must not connect directly to a printer's private IP address. Printer
discovery, reachability, execution, retry safety, and local failure reporting
belong at the Edge. A Cloud command being queued or leased is not evidence that
anything printed.

## 14. Platform Control Plane and Restaurant Backoffice

### Vynic Platform Control Plane

The authenticated `PlatformUser` boundary and the Platform Admin Panel exist.
They may manage platform-level resources such as:

- Organizations and Venues;
- Plans and Venue feature overrides;
- domains and `WebsiteMode`;
- Devices and one-time Device credential lifecycle;
- platform audit records;
- explicitly designed future platform integrations.

Control-plane mutations are cross-tenant by design and must remain authenticated
and audited. Platform audit is separate from Venue operational audit.

### Restaurant Backoffice

The Restaurant Backoffice is a future restaurant-facing administration surface
for menu, staff, roles, permissions, Venue settings, printers, and reports. It
is scoped to the restaurant's Organization/Venue. It is separate from the
Platform Admin Panel and must not authenticate restaurants as `PlatformUser`s.

The Backoffice is also distinct from the optional Manager App. Current product
direction requires restaurant administration to remain available independently
of `MANAGER_APP`; exact feature packaging is a later commercial decision.
Offline-critical controls must not simply disappear from POS when Backoffice is
introduced.

## 15. Restaurant roles and permissions direction

The intended model is:

```text
Vynic-controlled permission catalogue
              +
Venue-owned custom role names and permission sets
```

Vynic owns the permission vocabulary because permissions map to enforced code
paths. A Venue may eventually own role names and selected permissions. Do not
assume the final RBAC model is permanently limited to a hardcoded set such as
`OWNER`, `MANAGER`, `WAITER`, or `CASHIER`.

The current fixed `StaffRole` enum and current role checks remain authoritative
until an explicit migration phase replaces them. Future direction is not
permission to partially introduce custom roles.

## 16. Prisma and PostgreSQL safety

Before a schema change, inspect:

- relations, deletion behavior, and tenant ownership;
- primary keys, unique constraints, and scoped indexes;
- every existing migration and the likely applied production state;
- bootstrap data and compatibility identifiers;
- all readers, writers, scripts, and generated clients;
- existing-row implications, including nullability and backfills.

Prefer additive, staged migrations. Never reset a user's real database. Never
casually rewrite an applied migration. Use disposable PostgreSQL for destructive
migration verification.

An empty-database migration test is insufficient when existing data is
backfilled, re-keyed, constrained, made non-null, or deleted. Verify a
representative pre-migration dataset and assert its post-migration ownership and
constraints. Mocked Prisma tests do not prove database-level isolation.

## 17. Tenant ownership in data models

Tenant-root records should carry explicit Venue ownership when the domain
requires it. Child records may inherit ownership through an authoritative
parent when that relationship makes cross-tenant access impossible and queries
remain clear.

Do not add `venueId` to every child merely for convenience. Redundant ownership
can drift. Conversely, do not leave a root globally scoped when its identity or
uniqueness is restaurant-specific. Decide ownership deliberately and reflect it
in relations, constraints, indexes, service filters, and tests.

## 18. Shared contracts

For real cross-stack boundaries—NestJS↔Flutter, NestJS↔React, and Cloud↔Edge—
evaluate whether the contract belongs in `packages/contracts/`.

Use one canonical schema with generated language representations when the same
wire format has independent producers/consumers and drift would be dangerous.
Run the repository generator/check after changes and modify the schema rather
than hand-editing generated files. Preserve version and compatibility semantics
across a deployed fleet.

Do not move internal backend-only DTOs into the shared package merely because
the package exists. Sharing is warranted by an actual boundary, not by type
similarity.

## 19. API evolution

Before changing an endpoint, find every consumer:

- Flutter POS and Flutter Manager;
- Platform Web and Venue Web;
- backend internal callers and background workers;
- scripts, tests, and external provider callbacks.

For a breaking change, deliberately choose among backward-compatible evolution,
versioning, coordinated migration, or a temporary adapter. State how older
deployed POS versions behave during rollout. Never silently break existing
installations or interpret absence of a new field as proof that every client
has upgraded.

## 20. Flutter and Hive persistence

Before changing a persistent Flutter model, inspect:

- box names and where each box is opened;
- stable adapter and field identifiers;
- generated `*.g.dart` adapters and repository generation conventions;
- existing records and default behavior for missing fields;
- `HiveMigrationService` versioning and idempotence;
- backup/restore coverage and whether secrets are intentionally excluded.

Old POS data must remain readable after an upgrade. Test migration from a
representative legacy store, rerun safety, and backup/restore behavior when the
change affects them. Never treat deletion and recreation of a box as a migration
strategy for real installations.

## 21. NestJS boundaries

Controllers should normally:

```text
authenticate and resolve actor
validate DTO/request shape
delegate to an application/domain service
return the result
```

Do not place major Prisma orchestration, tenant policy, entitlement precedence,
or business logic directly in controllers. Reuse authoritative services such
as `VenueEntitlementsService`, `DeviceCredentialService`,
`WebsiteTenantService`, and `EdgeCommandService` where applicable. Do not create
a second implementation of an existing calculation because the current caller
needs a slightly different shape; adapt the authoritative result.

Service methods that touch tenant-owned data should require authoritative
context or an already-authorized object relationship, and Prisma filters should
make the tenant boundary visible.

## 22. React frontend rules

React frontends may own presentation, interaction state, obvious form
validation, query caching, and refetch/invalidation behavior. They are not
authoritative for:

- tenant resolution;
- authentication or authorization decisions;
- effective entitlements;
- ownership of payments or provider callbacks;
- persistence or recovery of one-time secrets.

Use centralized API and session layers where the application already has them.
Do not scatter raw `fetch` calls or duplicate error/auth handling. A hidden
button is not authorization. Never ship fake production metrics or sample rows
that can be mistaken for live platform state.

Treat one-time credentials as ephemeral UI state: show only the issuance/rotate
response, avoid durable caches, clear raw values on dismissal, and never imply
that a hash or masked display makes a secret recoverable.

## 23. Secret handling

Never commit, log, expose, or overwrite:

- JWT or platform-token secrets;
- raw Device credentials;
- database credentials;
- passwords or password hashes;
- payment-provider secrets;
- private keys.

Never return `passwordHash`, `credentialHash`, or equivalent verifier material
to a frontend. Never place secrets in audit metadata.

The Device credential lifecycle is:

```text
issue → show once → persist verifier only → rotate if lost
```

Do not build secret recovery. Provisioning files and local credential stores
must follow the existing exclusion, permission, absorption, and cleanup rules;
do not move Device secrets into Hive settings or backups.

## 24. Payment architecture

Keep two payment domains separate.

### Restaurant customer payment integrations

The future model is Venue-owned:

```text
Venue → PaymentIntegration → Provider → protected Venue credentials
```

Browser requests resolve Venue from Host. Provider callbacks resolve Venue from
server-owned reservation/payment identity. The client must not select another
Venue's merchant account. Stored provider secrets must be protected, write-only
from external clients, and independently rotatable.

Current process-wide BOG environment configuration is transitional and belongs
to the bootstrap deployment. Do not pretend it is safe for multiple merchant
Venues or silently fall back to it for a Venue without configured credentials.

### Vynic SaaS billing

Restaurant subscription billing is a separate product/domain. A `Plan` or
`VenuePlanAssignment` is not a subscription lifecycle. Do not mix restaurant
merchant credentials, diner payments, refunds, or callbacks with Vynic's future
billing provider and account data.

## 25. Environment variables

Every new environment variable must be documented with:

- exact name and owning service;
- required versus optional status;
- local-development expectation;
- production expectation;
- fallback behavior and its safety;
- whether it is build-time or runtime configuration.

Update the appropriate `.env.example` when the repository uses one. Never read,
overwrite, normalize, or replace a user's real `.env` as part of routine work.
Never add an undeclared environment dependency or a development fallback that
can silently operate in production.

## 26. Authorization before mutation

Every mutation must answer:

```text
Who is the actor?
What principal type are they?
What authority do they have?
Which tenant and object may they mutate?
What prevents a cross-tenant mutation?
How is the action audited when required?
```

Backend enforcement is authoritative. Frontend route protection, disabled
controls, and button visibility improve UX but do not secure a mutation.

For Platform APIs, authenticate `PlatformUser` and audit the action. For
restaurant APIs, derive Venue from the restaurant principal/host relationship.
For Device APIs, derive Venue and machine identity from the verified Device
credential. Never use one principal's guard as a convenient substitute for
another.

## 27. Error and isolation semantics

Preserve meaningful HTTP and domain semantics:

```text
400 malformed input
401 missing or invalid authentication
403 authenticated but not authorized
404 missing resource or intentionally hidden scoped resource
409 uniqueness or state conflict
```

Prefer a scoped `404` when acknowledging existence would leak another tenant's
resource. Do not expose production stack traces or raw provider/database errors
to clients. Internally retain enough structured context to diagnose the real
failure; never turn errors into ambiguous `null`, false success, or empty
catch-all behavior.

## 28. Git safety

Before substantial work inspect:

```bash
git status --short
git stash list
git log --oneline --decorate
```

Treat pre-existing changes and stashes as user-owned. Do not apply, pop, drop,
rename, or otherwise manipulate an existing stash unless explicitly requested.
Do not reset unrelated work, amend unrelated commits, or use destructive cleanup
to make validation pass.

Keep commits focused when commits are authorized by the task. Do not push,
deploy, publish, or open external changes unless explicitly requested.

At completion run:

```bash
git status --short
git diff --check
```

and account for every changed file.

## 29. Scope discipline

Classify discoveries as:

```text
BLOCKER  — prevents safe completion of the requested task
IN-SCOPE — required for the requested outcome
DEFERRED — real but belongs to another phase/task
```

Do not opportunistically fix unrelated architecture, historical sync bugs,
reservation behavior, security findings, or UI issues. If an in-scope change
reveals a broader migration requirement, implement only a safe compatible slice
or stop and report the blocker.

## 30. Avoid premature infrastructure

Vynic currently favors one modular NestJS deployment and one PostgreSQL
database. Do not introduce Kafka, RabbitMQ, NATS, Redis, microservices, or
distributed event infrastructure without concrete evidence that the existing
architecture cannot meet the requirement.

Operational complexity, deployment burden, failure modes, and offline behavior
are product costs. A durable PostgreSQL row, a NestJS service, or the existing
Edge contract is often the correct boundary until measured needs prove
otherwise.

## 31. Validation matrix

Validate every stack actually changed, using the repository's current scripts
and reporting baseline failures honestly.

### Backend

Use the appropriate combination of:

```text
Prisma generate
Prisma validate
build
unit/integration tests
lint
git diff --check
```

Schema work additionally requires migration verification and real PostgreSQL
integration where tenant ownership, constraints, or existing data matter.

### Flutter

When `apps/operations/` changes, run the applicable repository commands for:

```text
format/analyze
flutter test
appropriate desktop build and APP_ROLE
```

Build the role actually changed. Do not claim Windows validation from a macOS
build, or POS validation from only the Manager role.

### React

When a React frontend changes, run its actual scripts for:

```text
typecheck
tests
lint
production build
```

Exercise critical routing/auth/configuration behavior in a browser when static
checks cannot prove it.

### Shared contracts

When contract schemas or generated outputs change, run the generator in check
mode and any consumer tests. Generated files must match their canonical schema.

Do not run unrelated expensive validation merely to produce a longer report;
select checks in proportion to the affected runtime and risk.

## 32. Test system properties

Prefer tests that prove an authoritative property through the real boundary,
for example:

- Venue A cannot read or mutate Venue B;
- a Manager token cannot enter Platform APIs;
- Device A cannot claim or acknowledge Device B's command;
- a feature override changes the actual `FeatureGuard` result;
- a Host resolves through a real `VenueDomain` to one Venue;
- duplicate Edge delivery does not repeat the local side effect;
- a revoked Device credential no longer authenticates;
- a one-time raw credential cannot be retrieved after issuance.

Tests that only assert a mocked helper was called can support local logic, but
they do not prove authorization, tenancy, persistence, or delivery semantics.

## 33. Real PostgreSQL evidence

Use real PostgreSQL integration where practical for tenancy, unique/foreign-key
constraints, migrations, and authorization queries. Mocked Prisma calls are
useful for branching and orchestration tests, but they are not sufficient
evidence that a database-level multi-tenant boundary holds.

For migration tests, use disposable databases and representative pre-migration
rows. Never point destructive verification at a developer's or production
database.

## 34. No fake success claims

State the strongest property actually proven. Do not claim “production ready,”
“online,” “connected,” “delivered,” or “fully migrated” without evidence of
that exact property.

In particular:

- “Edge command queued” does not mean the POS claimed or executed it;
- “claimed” does not mean acknowledged or successful;
- `lastSeenAt` does not automatically mean `ONLINE` now;
- a frontend build does not prove its deployment or environment;
- a macOS build does not prove a Windows build;
- a migration file existing does not prove it was applied in a particular
  environment;
- a transitional path coexisting with its replacement does not mean migration
  is complete.

## 35. Documentation is architectural state

When a task establishes or changes a long-term boundary, update the appropriate
canonical documentation with:

```text
decision
reason
current implementation
transitional compatibility
deferred work
what must not be inferred
```

Do not leave high-authority entry documents directing future agents toward
obsolete architecture. When an older document must remain for historical
context, label stale sections clearly or link to the current authority rather
than letting incompatible statements coexist without explanation.

## 36. Pre-implementation reasoning gate

Before substantial implementation, verify that the written current/target
analysis answers all of these:

- Which domain owns the data now and after the change?
- Which principal and server-owned relationship establish authority?
- Can restaurant operation continue with Internet disconnected?
- Does any persisted data require a compatible migration?
- Which deployed consumers could observe the contract change?
- Does the change extend a transitional path or advance the target path?
- Which security and cross-tenant properties require tests?
- What evidence will support the final claims?
- Which adjacent findings are explicit non-goals?

If an answer is unknown, inspect further. If it cannot be determined safely,
report the blocker rather than hiding it behind an assumption.

## 37. Completion reporting

For a major phase, report evidence for:

- baseline repository state and existing implementation;
- architecture decision and changes made;
- authentication, authorization, and tenant impact;
- persistence and migrations;
- frontend/client and backward-compatibility impact;
- environment and deployment changes;
- tests, builds, and known baseline failures;
- commits, if authorized and created;
- manual user/deployment actions;
- deferred findings and the recommended next step.

Avoid “everything works.” Name the checks that passed, the properties they
prove, and the environments or platforms not tested.

## 38. Canonical Vynic invariants

Unless an explicit architecture phase changes and migrates them:

- POS remains offline-first.
- Hive remains local operational persistence.
- POS/Edge owns live operational state.
- Cloud must not require direct restaurant-LAN access.
- Printers are Edge/LAN resources.
- Device→Venue is authoritative for POS Cloud identity.
- Staff→Venue is authoritative for Manager identity.
- Host→VenueDomain→Venue is authoritative for public website tenancy.
- Payment callbacks derive Venue from server-owned reservation/payment identity.
- `PlatformUser` is separate from restaurant `Staff`.
- `WebsiteUser`, `Staff`, `Device`, and `PlatformUser` are distinct principals.
- Plans and Features are separate concepts; code authorizes by effective
  Feature, not plan name.
- `WEBSITE` entitlement and `WebsiteMode` are separate concepts.
- Manager App remains optional.
- Restaurant Backoffice is separate from Manager App and Platform Admin.
- The Vankisi custom website remains separate from the future generic SaaS
  website.
- Cloud→Edge target transport is Edge-initiated persistent work delivery with
  at-least-once semantics.
- Legacy compatibility is removed only through an explicit migration phase.
- POS→Cloud synchronization and Device transport are not commercial feature
  gates.
- Restaurant payment integrations and Vynic SaaS billing remain separate
  domains.
- One modular NestJS deployment and one PostgreSQL database remain the default
  infrastructure until evidence requires more.
