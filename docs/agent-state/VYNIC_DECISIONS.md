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

Initial Manager activation follows the same authority boundary. A short-lived
POS enrollment code may explicitly include first Manager setup. Redemption binds
that permission to the enrolled Primary Device; the person chooses a name and
PIN there without entering a second activation code. Ordinary/additional POS
codes grant no setup permission. Issuer authority, POS/Manager entitlements,
expiry and absence of Manager history are rechecked under the Venue lock. Legacy
invitation codes remain compatible, but cannot redeem a Device-bound setup grant.
Manager has ordinary login only; Platform cannot create the initial Manager to
bypass POS registration.
There is no shared production default PIN. Owners may issue an invitation only
before any Manager exists; existing Manager recovery belongs to Vynic Platform
Admin, not the owner cabinet. Authenticated POS/Manager operational permissions
remain unchanged. Invitation verifiers and audit contain no readable credentials;
normal authentication still requires exactly one matching active Manager. New
Manager installations redeem a Platform Admin-only, expiring one-use linking
code to remember a Venue. It creates neither Staff nor a session and cannot
replace PIN authentication. The public per-origin installation UUID permits
same-code lost-response retry, not authentication or attestation. Existing
remembered selections, sessions and legacy lookup remain compatible; owners
cannot mint linking codes. See `docs/SINGLE_POS_ONBOARDING.md`.

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

## D031 — Native clients use their own API origin; Host never selects their Venue

**Decision:** POS and Manager reach the backend only through `api.<base domain>`
(local `http://api.vynic.localhost`, production `https://api.vynic.ge`), where
Traefik forwards an allowlist of native route families and answers everything
else with a backend 404. A LAN listener for other machines is opt-in
(`start-lan`), bound to one private IP, native paths only.
**Reason:** Native routes mixed into website hosts fall through to frontends, and
`.localhost` resolves to the calling machine; a dedicated origin keeps Platform,
Customer and restaurant sites independent of native clients.
**Implication:** New native route prefixes must be added to the allowlist in
`deploy/traefik/routes.yml` and the inventory in `docs/DEPLOYMENT.md`. Venue on these
routes stays Device/Staff authenticated (D003); never add Host- or header-based
tenancy or widen browser CORS for native apps. Never combine `compose.lan.yaml`
with production.

## D032 — Menu removal retires identity; tombstones remove only active projections

**Decision:** Normal Menu removal retains Category/Subcategory/Item/Variant rows
with `retiredAt`, independently of availability. Recipes and website presentation
remain attached to the same identities. Canonical DELETE still emits tombstones;
restoration is an explicit revisioned UPSERT with `restore: true`, with active
parents required. Parents reject active children. No normal permanent purge is
supported. Legacy POS-authority omission retires claimed rows; reappearance keeps
their IDs. A POS edit against a removed canonical node stays recoverable in the
journal but cannot recreate it in the ordering projection.
**Reason:** An already-closed offline Sale must retain recipe authority for delayed
consumption and reversal. Projection deletion cannot destroy that authority.
**Implication:** Active reads exclude retirement and inactive parents; historical
resolution remains Venue-scoped and includes retained rows. Physical recipe and
presentation dependencies restrict item/variant purge. Old missing rows require
trustworthy evidence, never invented reconstruction. Downgrading to destructive
writers is unsupported. See `docs/MENU06_SAFE_MENU_RETIREMENT.md`.

## D033 — Menu admission uses current Device capability; cutover is explicit

**Decision:** CLOUD Menu requires `CANONICAL_MENU_V2` on the authenticated
current request and enrollment code. An optional deployment-owned integer build
floor supplements it; marketing versions and cached Device reports never grant
admission. Reports are authenticated self-reports, not binary attestation.
Legacy POS Venues retain snapshot behavior until an Owner explicitly confirms
fleet readiness, final primary sync and reconciled offline edits. All ACTIVE
Devices must have fresh compatible reports; DISABLED/REVOKED lifecycle excludes a Device.
**Reason:** Silently skipping old snapshots creates false full-sync success, and
primary-only readiness misses forgotten terminals. Cloud cannot prove absence
of local offline edits or merge independent histories on rollback.
**Implication:** Canonical snapshot requests fail before writes, incompatible
Menu work holds local intents, safe recovery/offline operation stays available,
and CLOUD-to-POS downgrade is unsupported. Stable identities and explicit POS
adoption survive cutover. See `docs/MENU09_CLIENT_COMPATIBILITY_GATE.md`.

## D034 — Printer scope and physical authority are separate from quorum

**Decision:** The selected printer migration target keeps Flutter's business
planning, Georgian raster rendering and operator UI, with one independent Go
service per Windows host. LOCAL uses one exclusive local durable spool;
VENUE_SHARED uses explicit stable membership and full data-bearing replicas,
normally three voters plus client agents. A third participant for two POS is a
full replica, never a metadata-only witness. Business routing names a configurable
logical station, independently of source POS. Logical jobs retain station,
origin, configuration snapshot/digest and bytes; physical printer/controller and
outcome belong to separate attempts. Each physical route has one explicitly
configured controller, independent of queue leadership. Membership is never
discovered or reduced to standalone during an outage.
**Reason:** A Flutter-window lifetime cannot own shared background availability.
Consensus preserves durable logical admission/order but cannot revoke an old
socket or make an ordinary RAW printer enforce a leadership epoch. Short leases
and missed heartbeats do not prove physical exclusion.
**Implication:** Fixed-controller shared printing does not require a transferable
RAW fence; it requires exclusive configured ownership and a qualified cutover.
Automatic takeover of the SAME RAW printer remains held without downstream
enforcement. Primary/backup fallback uses a different configured physical printer
only after definitive non-submission. Uncertainty pauses that station's FIFO and
holds the affected physical printer; unrelated stations may progress. A controller
timeout after dispatch reservation never authorizes fallback. The new isolated
proof APIs do not change current Hive/Device authority, attach production writers,
install a service, qualify rollback or activate Cloud Windows routes. The existing
interactive-user installer remains D022 until a separate qualified cutover.
See `docs/VYNIC_PRINT_ARCHITECTURE.md` and
`docs/POS_PRINTER_ARCHITECTURE_REPORT_2026-10-09.md`. October 6 proofs remain
historical evidence, including the RAW counterexamples.

## D035 — Printer authority has its own identity and bounded offline grant

**Decision:** Production printer enrollment binds a fresh Go key/installation to
an existing server-authorized Windows Device and Venue. Foundation/candidate/proof
credentials are not production printer authority. Cloud-signed inventory grants
last at most seven days; learned revocation and generation high-water persist in
protected service storage. That identity store never travels in POS backups.
**Reason:** Offline printing needs cached authority, while a disconnected peer
cannot observe new Cloud revocations. A finite signed validity window makes that
tradeoff explicit rather than claiming instant offline revocation.
**Implication:** New members are clients; voter and fixed-controller assignments
require controlled configuration. Discovery supplies hints only. Expiry or clock
rollback fails closed for authorization and never authorizes job replay. Service
installation, authenticated queue integration and physical activation remain
separate gates. Full OS/VM identity clones are unsupported fresh installations.
See `docs/POS02_A_PROVISIONING.md`.

## D036 — Peer discovery cannot bootstrap or reconfigure a printer queue

**Decision:** Production Go peer RPC and Raft share POS-02.A certificate/inventory
verification. Client sources have no vote. The signed desired membership is
committed into the existing queue before controlled 1-to-3 voter expansion;
startup, reconnection and observed machine counts never change quorum.
**Reason:** Recreating a queue or changing membership during an outage can lose
acknowledged jobs, even when the returning machines belong to the same Venue.
**Implication:** Explicit initialization is restricted to configuration revision 1.
A protected identity-store marker refuses silent recreation of a lost queue.
Voter removal/replacement/endpoint movement require later qualified transitions.
Logical leadership grants no physical writer rights. See `docs/POS02_B_PEER_TRANSPORT.md`.

## Maintenance

Add an entry only when it prevents repeated architectural debate. Update or
briefly supersede a decision when the architecture changes; do not add
implementation trivia or session history.

## D037 — Website domains are managed by Platform Admin

**Decision:** Customers contact support for every website hostname change; no
owner request/mutation path remains. Platform Admin may register Vynic subdomains
or external domains for SAAS/CUSTOM and rename existing domain identities with
an expected hostname and reason. SAAS keeps one assigned identity plus optional
Admin-managed aliases.
**Reason:** Domain selection is a Vynic operator responsibility, including bespoke
sites hosted below the Vynic base domain. A generic namespace refusal prevented
this operator workflow without protecting against an unauthorized customer.
**Implication:** Preserve Platform principal separation, globally unique/retained
names, reserved platform origins, atomic audit and canonical SAAS mirrors.
Owners cannot bypass policy through draft/publication or direct API calls.
DNS/TLS and CUSTOM frontend routing stay separate deployment tasks. Existing
requests/history are retained; no data migration or live rename is implicit.
See `docs/WEBSITE_SAAS_HOSTNAMES.md` and `docs/CUSTOM_WEBSITES.md`.

## D038 — Whole-day payment holds and restaurant-owned financial exceptions

**Decision:** Preserve whole-day physical-table booking. New website holds and
BOG order TTL each use ten minutes; replies never extend the frozen website
window. Verified late/unproved expired payments require manual review with no
automatic restore or refund. Partial refunds preserve the confirmed booking.
The restaurant owner decides financial exceptions; Vynic support assists with
technical evidence. Hourly slots and automated exception-resolution operations
require a later approved product policy.
**Reason:** These five rules were explicitly approved for WEB-01/04; matching a
callback-send timestamp with a payment-completion timestamp would invent proof.
**Implication:** Preserve signed/pinned receipt authority, exact money and
immutable observations; keep read-only owner history accessible after access
loss. Causal proof of timely payment can finish the original unconflicted hold,
never steal reassigned occupancy. Old history is not inferred or replayed.
See `docs/WEB0104_BOOKING_HOLDS_PAYMENT_LEDGER.md`.


## D039 — Subscription offline access is a signed bounded lease

**Decision:** Overall beta POS subscription access uses a Device/installation/
Venue-bound signed lease no later than verified server time + 24 hours and known
trial/paid expiry. It is separate from nonfiscal authorization. New sales require
same-boot, OS-vault-backed continuity across normal app restart; uncertain boot,
clock or anchor continuity requires fresh online verification. Preserve
read/export/sync and only unchanged, previously admitted bill settlement.
**Reason:** The user approved bounded outage operation and explicit expiry UX;
client wall time and cached feature lists cannot extend commercial authority.
**Implication:** The central server alone activates/history-tracks trials. Native
suspend-aware elapsed time, nonce replay protection, action-time checks, retained
revocation and device-local consumed settlement permissions are required. No
instant offline remote revocation or administrator/VM snapshot resistance is
claimed. See `docs/OFFLINE_SUBSCRIPTION_LICENSE.md`.
