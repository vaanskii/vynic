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

**Decision:** Vankisi remains a bespoke `CUSTOM` site; a future `SAAS` site is a
separate data-driven frontend.
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

**Decision:** CustomerAccount → Organization → Venue is separate from PlatformUser,
Staff and WebsiteUser. Signup creates new ownership; matching email/name never
claims an existing restaurant. Customer mutations use CustomerAuditEvent.
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

## Maintenance

Add an entry only when it prevents repeated architectural debate. Update or
briefly supersede a decision when the architecture changes; do not add
implementation trivia or session history.
