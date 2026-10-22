# Platform commercial and Website ownership UX

## A. Previous mixing

Product contained plan assignment and agreed pricing, Commercial offered one
unfiltered list of low-level lifecycle operations, and Manager provisioning
appeared below every Venue tab. Customer first-run and Website draft editing
could choose a hostname and publication claimed it. Trial timing was date-only.

## B. Commercial

Commercial owns subscription status, current plan, agreed price/period, exact
Trial and paid-period timestamps, next renewal, pending changes, scheduled
cancellation, and lifecycle history. Trial is visibly labelled TRIAL alongside
Website only. Remaining duration uses the server snapshot time and refreshes
with the subscription query. Timestamps use browser-local time with timezone.

## C. Product

Product owns effective enabled/disabled capabilities, feature overrides,
NON_FISCAL_CLOSE policy guidance, Cloud menu admission/editing and Manager
access. Plan assignment/pricing controls have been removed. A Trial capability
summary explicitly identifies its temporary commercial status.

## D. Website

Website owns entitlement/mode, provisioning/publication, current SaaS hostname,
registered domains, menu authority, mode/domain controls and pending hostname
review. No subscription action is duplicated here.

## E. Commercial actions

- NO_PLAN: Start Trial / Assign paid plan.
- TRIAL: Extend Trial / End Trial now / Convert to paid / Suspend.
- ACTIVE: Upgrade/change plan / Schedule downgrade / Cancel at renewal / Suspend.
- Legacy ACTIVE: Confirm paid agreement / Suspend; dated renewal actions require
  adopting known paid terms first.
- PAST_DUE: Confirm renewal / Suspend.
- SUSPENDED: Resume / Cancel. Resume still checks whether agreement dates permit it.
- CANCELLED: Assign new plan.
- Undo/cancel scheduled changes appear only when a corresponding change exists.

Operator mutations require reasons and UI review. Immediate suspension and
termination require explicit server confirmation, including the legacy status
endpoint. Existing server quotes and manual payment boundaries remain intact.

## F. Trial timing and termination

TRIAL stores its server start time. EXTEND_TRIAL requires a later explicit end
and preserves the start. END_TRIAL requires confirmation and reason, records
before/after status and end, and transitions immediately to CANCELLED. Entitlement
checks close Cloud Website access immediately. Restaurant data, catalog, drafts,
history and offline POS completion/settlement paths are preserved.

## G. Trial hostname

The server assigns an address during SaaS provisioning, with a locked collision
check and numeric suffix if needed. Spaces and unsupported characters are
removed; supported Georgian transliteration and Latin normalization are retained.
Reserved names get a safe restaurant prefix. Restaurant Vankisi becomes
restaurantvankisi. Restaurant display-name edits do not rename this identity.

`assignedSlug` is separate from the existing publication `slug`, preserving the
publication consistency constraint. The migration backfills published identities
and restores that identity in any pre-upgrade draft containing an unapproved
address, preserving other content and incrementing its revision. Existing
unassigned SaaS configurations are assigned once under lock when loaded.

Trial customers see the assigned address and the Georgian restriction message.
They cannot edit it or request a change, including through direct HTTP calls.

## H. Paid hostname change

An ACTIVE, commercially entitled SAAS owner can request an available address.
The current address remains unchanged while PENDING. Platform approval checks
paid entitlement/mode and availability again under Venue/config/name locks,
replaces only the old SaaS VenueDomain, synchronizes draft/published identity,
fences stale editors, and audits the change. Rejection preserves the identity.
CUSTOM domains are not deleted. Direct customer draft edits cannot rename a
hostname. The old SaaS address is released on approval; no redirect is created.

## I. SAAS/CUSTOM authority

Implementation remains operator-selected on Website-bearing assignments and
explicit mode changes. CUSTOM never exposes the generic customer editor.
Website-only SaaS still admits eligible empty Venues to Cloud menu authority;
POS evidence still prevents that admission.

## J. Deduplication

Hostname requests use a Venue lock and a PostgreSQL partial unique index for
one PENDING row per Venue. Public access requests serialize/check normalized
email; authenticated Trial requests serialize/check Venue. The customer reloads
pending Trial state and sees PENDING hostname status instead of another submit
button. Public duplicate submission returns a conflict and displays the pending
acknowledgement.

## K. Browser proof

Executed against disposable `vynic_website_provisioning_v2` on local port 55447,
API 3117, UI 5197, through real operator/customer sign-in and production guards.
Fixture entry point: `apps/backend/scripts/serve-commercial-ux-proof.ts` with
`--confirm-disposable` and its explicitly checked database URL. Test account
password: `DisposableUX-proof-2026!`; generated identities are written to
`/tmp/vynic-commercial-ux-fixture.json`. No real customer database was used.

- Operator selected Website only + SAAS and confirmed a dated Trial.
- First-run showed restaurantvankisi.vynic.localhost read-only, with no upload
  control or implementation selector. Commercial showed exact start/end with
  GMT+4 and remaining duration.
- Customer saved Monday hours (10:00–22:00) and a Cloud menu category.
- Operator used End Trial now; customer reload lost menu/Website access.
- Operator assigned ACTIVE Website; the saved menu category remained.
- Customer requested vankisireviewed; PENDING kept restaurantvankisi current and
  hid the submit control. Operator approved with a reason; only then did the
  customer and Platform show the new hostname. Duplicate pending rejection and
  direct-edit rejection were also verified by concurrent real HTTP integration.
- Operator switched to CUSTOM; customer saw the separately managed website
  notice and no generic hostname editor.
- Customer and Commercial mobile views were inspected at 390px. Their document
  width equalled the viewport width. Console inspection returned no warnings or
  errors on the inspected Commercial view.

Screenshots are in `/tmp/vynic-commercial-ux-proof/`: `trial-first-run.png`,
`trial-commercial.png`, `trial-cloud-menu.png`, `trial-ended.png`,
`paid-pending.png`, `paid-approved.png`, `custom-customer.png`,
`customer-mobile.png`, and `commercial-mobile.png`.

## L. Validation

- Backend unit/HTTP: 55 suites, 468 tests passed. Other opt-in integration suites
  are skipped by the blanket command; the relevant suites were explicitly run.
- PostgreSQL provisioning/ownership/concurrency: 12 passed.
- PostgreSQL commercial access/subscription lifecycle: 30 passed.
- PostgreSQL Website Core/W3 tenancy/publication/media: 23 passed.
- Platform/customer dashboard: 23 suites, 139 tests passed.
- restaurant-web: 4 suites, 19 tests passed.
- Backend, Platform and restaurant-web production builds passed.
- Prisma validation and fresh migration deployment passed.
- `scripts/prove-hostname-upgrade.py` passed: existing published identity and
  draft content preserved, publication constraint unchanged, duplicate PENDING
  insertion rejected by PostgreSQL.
- `git diff --check` passed.
- Full Platform lint remains blocked by existing effect/any-type lint violations;
  the Vite build also retains its existing large-chunk warning. These are deferred.

## M. Commits

Changes are split into backend ownership/lifecycle enforcement and frontend
Commercial/Product/Website UX commits. See the task's final report for hashes.

## N. Remaining gaps

The migration still needs deployment to the intended application database.
No production billing provider, DNS/TLS automation or old-host redirect is added.
Unrelated opt-in backend integration suites and physical offline POS behavior
were not exercised; the offline operational implementation is unchanged.

## O. STOP

The requested scope ends here.
