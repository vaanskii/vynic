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

## Maintenance

Add an entry only when it prevents repeated architectural debate. Update or
briefly supersede a decision when the architecture changes; do not add
implementation trivia or session history.
