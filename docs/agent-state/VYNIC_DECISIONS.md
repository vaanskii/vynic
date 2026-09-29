# Vynic Decision Index

Short reminders for boundaries that agents otherwise reconsider. Detailed rules
remain in `docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md`.

## D001 — POS remains offline-first

**Decision:** POS live operation and Hive persistence must work without Cloud.
**Reason:** Restaurant service cannot depend on Internet availability.
**Implication:** Orders, tables, payments, printing, cached configuration, and
business-day close cannot wait on a network request.

## D002 — Cloud work is pulled by Edge

**Decision:** POS/Edge initiates Cloud connections; Cloud does not dial the LAN.
**Reason:** Hosted services cannot safely or reliably route to private restaurant
addresses.
**Implication:** Use persistent commands, claim/lease, local execution journal,
and acknowledgment with at-least-once semantics.

## D003 — Tenant authority is principal-specific

**Decision:** Device -> Venue, Staff -> Venue, Host -> VenueDomain -> Venue, and
payment identity -> Venue are the authoritative paths.
**Reason:** Client-supplied tenant IDs permit cross-tenant access.
**Implication:** Request `venueId`/`organizationId` may identify a target but can
never grant authority.

## D004 — Multi-tenancy uses shared schemas

**Decision:** One PostgreSQL database with shared `pos`/`website` schemas and
explicit Organization/Venue ownership remains the default.
**Reason:** Current scale does not justify per-tenant databases or services.
**Implication:** Tenant roots, uniqueness, service filters, and tests must be
Venue-scoped; do not introduce microservices or brokers without evidence.

## D005 — Platform administrators are not restaurant staff

**Decision:** `PlatformUser` is a cross-tenant principal separate from `Staff`,
`WebsiteUser`, and `Device`.
**Reason:** Platform operations have no restaurant membership and require their
own authentication and audit boundary.
**Implication:** Manager or website sessions never enter `/platform/*`; restaurant
owners must not be promoted into Platform identities.

## D006 — Entitlement is not operational policy

**Decision:** Plan/Feature answers product access; Venue Policy answers how a
Venue may operate.
**Reason:** A commercial package change must not silently alter receipts,
accounting, or staff capabilities.
**Implication:** Use `VenueEntitlementsService` for product access. Build policy
through a separate Cloud authority plus complete offline POS cache.

## D007 — Platform Admin is not Restaurant Backoffice

**Decision:** The Vynic operator control plane and restaurant administration are
separate products and principals.
**Reason:** Cross-tenant platform authority must not leak into restaurant-owned
configuration.
**Implication:** Backoffice remains a future Venue-scoped surface and must be
available independently of optional Manager App packaging.

## D008 — Device identity is lifecycle/audit state

**Decision:** Device rows are disabled/revoked and credentials rotated; they are
not normally hard-deleted or recoverable.
**Reason:** Commands, audit history, and credential-compromise evidence must keep
their identity.
**Implication:** Raw credentials appear once, only verifier hashes persist, and a
lost credential is rotated rather than read back.

## D009 — Printers remain Edge/LAN resources

**Decision:** Cloud sends commands/configuration to POS; POS talks to printers.
**Reason:** Printer reachability and physical side effects exist inside the
restaurant network.
**Implication:** A queued/claimed command is not proof of printing. Interrupted
prints fail visibly rather than replaying blindly.

## D010 — Sale value differs from money collected

**Decision:** Gross sale, advance applied, amount due now, and collected now are
separate persisted facts tied to a `closureId`.
**Reason:** Deposits move collection timing, not the value of what was sold.
**Implication:** Closing is journaled/idempotent; revenue reports and collection
reports use their respective fields and shared inclusion rules.

## D011 — Custom and SaaS websites stay distinct

**Decision:** Vankisi remains a bespoke `CUSTOM` site; the `SAAS` site
(`apps/restaurant-web`) is a separate data-driven frontend. See D026 for how
further CUSTOM sites are built.
**Reason:** Custom layout/booking behavior is not generic product scaffolding.
**Implication:** Both use Host -> Venue authority, but neither is silently
converted into the other.

## D012 — Legacy callback is a frozen rollout fallback

**Decision:** Existing LAN callback/outbox infrastructure remains only for
unenrolled Venues and older deployment compatibility.
**Reason:** Repository support for enrollment does not prove every deployed POS
has enrolled.
**Implication:** Add no new callback operations. Retire the fallback only after
fleet enrollment and compatibility evidence.

## D013 — Restaurant payments and Vynic billing are separate

**Decision:** Diner payments use Venue-owned merchant integrations; future Vynic
subscription billing is a different domain.
**Reason:** They have different payers, recipients, credentials, and lifecycles.
**Implication:** Never treat a Plan assignment as a subscription or reuse a
restaurant merchant account for Vynic billing.

## D014 — Sale owns consumption intent; Cloud owns stock effects

**Decision:** Freeze new close-time inventory intent atomically inside the local
Sale and deliver it independently of financial ledger ACKs. Cloud transactionally
materializes immutable consumption/reversal movements from that snapshot.
**Reason:** Checkout and crash recovery cannot depend on Cloud or a later live
recipe. A restore must reverse the original quantities, not today's recipe.
**Implication:** No historical backfill, no stock writes on open Orders, no
second POS StockMovement authority. See `docs/INVENTORY_STEP4.md`.

## D015 — Stock valuation follows Cloud acceptance order

**Decision:** Freeze stock issue cost when Cloud accepts the movement, under the
same item lock used by receipts and reversals. Preserve effective/business dates
without revaluing prior issues when offline activity arrives late.
**Reason:** POS checkout cannot know later Cloud receipts, and immutable issue
values must survive restore. Historical reconstruction is labelled separately.
**Implication:** These are Cloud inventory cost snapshots, not guaranteed
historical POS close-time COGS. Negative/unknown bases stay provisional. See
`docs/INVENTORY_PROCUREMENT_REWORK.md`.

## D016 — Platform access overrides operational Staff mirroring

**Decision:** Platform-created/reset/disabled Manager Staff are explicitly
Platform-managed. Snapshot sync and restaurant Manager CRUD cannot reverse that
access state. Venue locks serialize snapshot ingestion and Platform writes.
**Reason:** An offline terminal must not reactivate a disabled Manager or restore
an old PIN while its Edge commands are pending.
**Implication:** Keep the actual Staff UUID and historical links. Queue the
existing STAFF commands atomically with Cloud access/audit; the Phase 2 POS
rejects older revisions and disables future login without destroying local
identity or interrupting already-open operation. See `SAAS_PHASE2_CONTROL_PLANE.md`.

## D017 — Customer owners have Organization-scoped authority

**Decision:** CustomerAccount → OrganizationMembership(OWNER) → Organization → Venue
is separate from PlatformUser,
Staff and WebsiteUser. Public requests grant no ownership; matching email/name never
claims an existing restaurant. Platform-issued invitations attach membership only
after single-use token validation and owner-created credentials or normal sign-in
with the exact invited email. The legacy account Organization field is provenance,
never access authority. Customer mutations use CustomerAuditEvent.
**Implication:** Reuse Staff/enrollment operation bodies with explicit actor types;
do not manufacture a Platform principal for customer work. Device printer config
is pulled and cached locally. Build environment selects only the deployment,
while fixed entrypoints/native metadata select POS or Manager.

## D018 — One operational Device before Go coordination

**Decision:** Phase 0 selects one `Venue.activeOperationalDeviceId` to publish
operational snapshots and claim Venue-wide commands. Enrollment is not authority.
**Reason:** Separate Hive stores cannot safely reconcile a common Cloud mirror.
**Implication:** Server-side fencing and replacement share a Venue transaction
lock; ambiguous historical fleets need explicit operator selection. Preserve old
Device identity, stop/restore locally before replacement, and hold uncertain
command outcomes. This does not enable multiple working POS terminals. Phase 1
builds Go foundations; Phase 2 introduces Venue-local multi-POS authority. See
`docs/EDGE_PHASE0_PRIMARY_DEVICE.md`.

## D019 — Foundation Edge identity grants no operational authority

**Decision:** Go installations are separate from POS Devices and carry an immutable
Cloud-signed Venue binding. Phase 1 admits authenticated terminals for infrastructure
only; it neither selects an active Edge nor changes the Phase 0 Primary POS.
**Reason:** Transport, enrollment and durable local storage are prerequisites, not
proof that multiple independent Hive stores can safely write restaurant state.
**Implication:** TLS pairing, version/schema checks, metadata and crash recovery can
ship separately. Phase 2 requires explicit fenced authority, coordinated mutation
ACK/replay and operator handover proof. No automatic failover or business-domain
rewrite in Go. See `docs/EDGE_PHASE1_FOUNDATION.md`.

## D020 — Shadow coordination is not production authority

**Decision:** Phase 2A commits proposed ordinary Order/Table post-images with
revision checks, a durable event/result and replay into isolated Hive projections.
Production observers compare before-write proposals to actual Primary results;
Phase 0 remains the sole operational authority. Local shadow epochs never grant
Cloud operational authority.
**Reason:** Clean isolated convergence does not fence remaining payment/closure,
reservation, package or remote writers. A partial gate would admit dual writers.
**Implication:** Production cutover stays unavailable until full shadow coverage,
Cloud-selected Edge/epoch, every writer boundary and handover/rollback are proven.
No automatic leader election or independent terminal writes during partitions.
See `docs/EDGE_PHASE2A_ORDERS_TABLES.md`.

## D021 — POS update readiness is durable recoverability, not empty tables

**Decision:** Windows POS installation requires explicit operator action and one
readiness/admission barrier. Persisted open Orders/Tables and pending Cloud sync
are safe. In-flight/uncertain work and unresolved Edge/projection recovery block.
Go switches signed POS binary bundles and health-checks/rolls back binaries only.
**Reason:** Closing restaurant business to replace software is unnecessary when
its state is durable, while a check followed by unguarded writes is unsafe.
**Implication:** Release signatures bind product/platform/version and unchanged
Hive compatibility. No data rollback, Manager updater, Edge self-update or
production Orders/Tables authority cutover is implied. See
`docs/POS_WINDOWS_UPDATER.md`.

## D022 — First install uses a local interactive-user Edge host

**Decision:** Windows setup provisions a per-user, unelevated host with versioned
Edge binaries and bounded POS current/staging/rollback slots, separate durable
state, updater-aware shortcuts and signed
baseline repair. An unbound `edge host` exposes only local updater IPC; the
existing Venue-bound gRPC server and Phase 2A authority remain unchanged.
**Reason:** First installation precedes Enrollment Code onboarding; an interactive
POS cannot be launched safely by assuming a LocalSystem/session-0 service.
**Implication:** Setup never requests Venue secrets or invents a binding. Repair
pins the installed Edge baseline and preserves data/identity/update history.
POS rollback is temporary until authenticated stabilization; permanent binary
cleanup is journaled and never restores/deletes restaurant data. Deferred updates
remain staged until explicit consent. Edge self-update requires a separate helper
and qualification, not an extension
of POS update consent. See `docs/WINDOWS_SETUP.md`.

## D023 — Catalog authority is explicit and enrollment is not handover

**Decision:** Existing Venues retain their menu authority. New shells default
to POS with Cloud editing off; operators admit empty Website Venues to CLOUD. The package decides (Website without POS → CLOUD), never the SAAS/CUSTOM renderer. One canonical catalog serves all channels. Owner catalog writes
and POS snapshots enforce opposite authority under the Venue row lock.
**Implication:** Dashboard editing can be switched off independently; disabling
editing retains CLOUD authority so POS snapshots cannot overwrite that catalog.
Device enrollment never changes menu authority. Bootstrap v1 is
frozen, Device-bound and staged outside operational Hive; activation stays disabled
until all local writers, availability/media projections and transition recovery
are fenced. See `docs/CLOUD_RESTAURANT_FOUNDATION.md`.

## D024 — Commercial access is separate from customer ownership

**Decision:** New customer shells use NO_PLAN. Approval/invitation acceptance grants
membership, never automatic products. Only operator assignments activate dated
TRIAL or ACTIVE plans. Missing subscriptions grant compatibility only to rows marked
by the migration; new missing rows fail closed. Effective features are suppressed
when commercial access ends, while local POS completion, sync, frozen effects and
server-owned payment settlement remain independent.
**Reason:** Account creation, package selection and permission to operate a product
are distinct decisions; an absent row must not become a new customer's free plan.
**Implication:** Reuse the shared commercial resolver inside Venue-locked mutations.
Trials expire server-side; domains have a 30-day reservation grace. Media requires
ACTIVE Website access and quotas. See `docs/COMMERCIAL_ACCESS_HARDENING.md`.

## D025 — Subscription transitions require trusted commercial authority

**Decision:** VenueSubscription owns access timing; VenuePlanAssignment owns the
current package/agreed snapshot. Quotes and receipt events are work/history, not
competing access models. Trusted server payment results or explicit audited manual
agreements activate paid access. Upgrades retain the anchor; downgrades and customer
cancellation wait until renewal. Feature additions dominate price-only classification;
mixed changes require operator review. Timed unpaid renewals fail closed.
**Reason:** Browser claims, catalog edits and background timers cannot prove payment
or alter an agreed billing schedule. Historical unknown terms must remain unknown.
**Implication:** Lock the Venue, fence quotes with subscription versions, deduplicate
provider events and keep restaurant merchant payments separate. Legacy manual grace
is preserved until explicitly adopting dated terms. See
`docs/COMMERCIAL_SUBSCRIPTION_LIFECYCLE.md`.

## D026 — CUSTOM websites are frontends over one backend

**Decision:** A CUSTOM website is a per-client static frontend served behind a
host-preserving same-origin `/api` proxy to the shared NestJS backend. Tenancy
stays Host -> VenueDomain -> Venue; `CustomWebsiteBinding.siteKey` records which
frontend build serves the Venue (deployment identity, not authority) and the
shared client refuses to render on a mismatch. Mode, frontend identity, domains
and setup status are operator-only and audited. Data, public routes and
capabilities are the shared website foundation (D028); CUSTOM uses the same
canonical catalog and menu authority rules as SAAS (D023). Runtime
availability is an on-demand server check of the Venue's own domain, separate
from the attested setup status.
**Reason:** Cross-origin API hosting loses the Host and SameSite cookies, and a
browser-supplied Venue/site identity cannot be trusted; per-client backends
would duplicate tenancy, menu, booking and payment logic.
**Implication:** No per-customer backend, no Venue ids in frontends, no CORS
allow-list per domain (same-origin rule), no `X-Venue-Id`-style headers. See
`docs/CUSTOM_WEBSITES.md`.

## D027 — One vendored skill set serves Claude Code and Codex

**Decision:** Third-party agent skills are vendored unmodified in
`.agents/skills/`, pinned in `.agents/skill-sources.txt`; `.claude/skills/`
holds relative symlinks to them. Routing lives only in
`docs/agent-state/VYNIC_SKILL_ROUTING.md`.
**Reason:** Codex reads `.agents/skills`, Claude Code reads `.claude/skills`;
copies per agent drift and give the two agents different advice.
**Implication:** No second skill tree and no hand edits to vendored skills;
refresh with `scripts/sync-agent-skills.sh`. Skills stay advisory and never
override the decisions above.

## D028 — Website mode selects the renderer, never data or features

**Decision:** SAAS and CUSTOM share one Venue-level website backend. Venue
public information (hours, contact, socials, gallery) is `VenuePublicProfile`,
edited live and projected into the SAAS page payload; the SAAS page document
holds only renderer content. Shared capabilities go Features (commercial) →
`VenueWebsiteCapability` (operator policy, no row = on) → readiness, and
`WebsiteCapabilityGuard` gates public routes by capability. The only
renderer-specific gate is launch (published SAAS, provisioned CUSTOM).
**Reason:** Mode-based gates made CUSTOM and SAAS diverge in data and features,
and would have needed a second hours/gallery/booking backend per renderer.
**Implication:** No custom menu/hours/gallery/booking/payment backend; a new
website capability is a Feature (if sold separately) plus a key in
`website-capabilities.ts`, never a mode check. Moving content into live
storage is never publication consent: a migration keeps published authority and
an unpublished draft private (WEB-02). See `docs/WEBSITE_FOUNDATION.md`.

## D029 — Domains carry no port; local frontend ports are dev config

**Decision:** `VenueDomain.hostname` is a bare hostname. Where a CUSTOM
frontend's dev server runs is backend environment configuration keyed by
frontend identity (`CUSTOM_WEBSITE_LOCAL_FRONTENDS=<siteKey>=<port>,…`),
combined with the Venue's own `.localhost` domain, read only outside
production, with no default port.
**Reason:** A single global dev port pointed every CUSTOM site at one port;
a port on the domain or a binding column would put machine-local state into
tenant identity and the production database.
**Implication:** No port/origin columns for local development; unmapped
frontends report NOT_CONFIGURED; production views and checks never include
local configuration. An explicit isolated Docker HTTP deployment instead checks
registered `*.vynic.localhost` domains through its fixed trusted ingress, with no
site-key port registry; its backend still uses NODE_ENV=production. See
`docs/DEPLOYMENT.md` and `docs/CUSTOM_WEBSITES.md` §3c.

## D030 — Cloud-canonical Menu with local-first POS projections

**Decision:** Menu configuration is one canonical Cloud catalog changed only
by revisioned, idempotent entity mutations from any writer (Dashboard, any
enrolled POS Device, a future Manager). Each POS commits edits locally first,
journals them durably, and keeps a projection of canonical state plus its
unresolved journal; catch-up is by Venue change sequence with tombstones.
`menuAuthority` is transitional: CLOUD = this protocol (all new Venues),
POS = legacy compatibility until an explicit, audited cutover.
**Reason:** POS-owned authority locked the Dashboard once POS was added, and a
single catalog revision or primary-POS writer does not scale to many
terminals; Cloud-first writes would break offline operation.
**Implication:** No Cloud acknowledgement on the POS edit path; no
last-write-wins (explicit conflicts); no omission-means-delete for canonical
Venues; primary-POS containment stays for operational domains only; Edge may
coordinate over LAN later but is never a second Menu authority. See
`docs/CANONICAL_MENU_SYNC.md`.

## Maintenance

Add an entry only when it prevents repeated architectural debate. Update or
briefly supersede a decision when the architecture changes; do not add
implementation trivia or session history.
