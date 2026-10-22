# Commercial Access Hardening

Implemented against the current working tree; all database validation used an
isolated local PostgreSQL cluster on port 55437. No live `vankisi_database` access,
push, production migration or deployment was performed.

## A. Previous commercial-access problems

Pilot signup created ownership and restaurant preparation applied a configured
trial package. Missing subscriptions implicitly allowed access, including for
new rows. Trial deadlines did not expire access. Several owner mutation paths
lacked commercial guards; uploads had no persisted ownership/quota accounting.
Plan grants could supply non-fiscal close, and public names had no bounded
commercial retention lifecycle. Catalog pricing/feature editing was incomplete.

## B. Acquisition and approval

Public “გამოსცადე Vynic” → request → Platform review → approved NO_PLAN
Organization/Venue + owner invitation → account acceptance/live OWNER membership
→ account dashboard. Requests store applicant/business/contact information,
optional plan/note, review status/actor/time/note and approved Venue identity.
Submission creates no account, session, tenant, subscription, plan, domain,
Device enrollment, Manager credentials or media storage.

`/request-access` is the public request form; `/signup` and `/start` redirect there. The old `POST /customer/auth/signup`
refuses self-registration. Existing customer sign-in and invitations remain.
Approval/review is transactional, serialized and audited. Re-review conflicts.

## C. NO_PLAN and legacy compatibility

New Venue subscriptions default to NO_PLAN; absent new subscription rows also
fail closed. Dashboard membership is independent: account/business identity,
subscription status, package discovery and trial requests remain available.

The additive migration marks **only Venues already missing a subscription** with
`legacyCommercialAccess=true`. Only those marked rows may use the historical
missing-row rule. Existing plan grants/overrides are still required to resolve
features; the marker itself does not invent a package. No API lets customers set
it. Creating a subscription supersedes missing-row compatibility. Existing ACTIVE
and TRIAL rows, assignments, owners and domains retain their stored identities.

## D. Trial request and approval

Customers can submit a Venue-authorized trial request, with one pending request
per Venue. Only Platform operators approve/reject. Trial approval requires a
chosen active Plan and future end date; the requested package is advisory.
Approval alone for a **new customer** always prepares NO_PLAN and an invitation.

Assisted onboarding can explicitly assign a chosen TRIAL (1–90 days) or ACTIVE
package. Venue Commercial controls support assignment, extension, suspension,
cancellation and conversion. All these commercial writes are audited. Read-only
support cannot mutate requests, packages or commercial access.

## E. Expiry

TRIAL allows access only while `trialEndsAt > server time`. Missing/elapsed trial
end dates deny immediately. Reads and a 60-second scheduled sweep reconcile to
SUSPENDED under the Venue lock, emitting one `venue.trial_expired` SYSTEM audit.
Repeated and concurrent reconciliation is idempotent. The service accepts an
explicit clock value in tests; no real-time waiting is required.

ACTIVE and manually managed PAST_DUE grace allow assigned access; NO_PLAN,
SUSPENDED and CANCELLED deny. Existing enrolled transport, local POS completion,
frozen inventory/Sale effects and server-owned payment settlement are unchanged.

## F. Product-specific trials

There is no special all-products trial. Plans and explicit overrides resolve the
same way for an eligible trial or active subscription. WEBSITE_ONLY grants
WEBSITE; POS grants POS. A full package must be chosen deliberately. Plan grants
before subscription gating and effective usable features are separate projections.

## G. Server-side enforcement

Shared commercial state is checked on reads and inside Venue-locked mutations:
website draft/preview/menu presentation/publication, Cloud catalog authoring,
media, domain claim/activation, BOG credential writes, Manager create/reset and
POS enrollment/setup. Owner routes first resolve live membership; client Venue
IDs never establish authority. New missing subscription/plan rows deny access.

Manager login and existing JWT resolution require MANAGER_APP and allowed state.
Suspended client projections contain no optional usable module keys. Existing
BOG callbacks/settlement retain their encrypted, server-owned original integration
revision after disconnection or entitlement removal. The explicit audited legacy
credential-import CLI remains a compatibility exception; it cannot start a new
payment without current payment access.

## H. Media and quotas

NO_PLAN and TRIAL cannot upload any image, including logos. Logos are optional in
first-run setup. ACTIVE + effective WEBSITE is required. Plans default to 50 MiB
and 50 files, editable by Platform. Every new file records Venue, immutable storage
key, purpose, byte count, creation time and unused-since state. Unattached files
count; quota checks and writes serialize under the Venue lock.

PNG/JPEG/WebP input is decoded, metadata stripped, capped at 5 MiB/16 megapixels,
resized and written as WebP. Existing referenced local files are adopted with
metadata/byte accounting before uploads or during hourly cleanup. Draft, published
and menu references protect owned files. Copying another Venue's local image is
denied, including absolute-URL aliases. Previously persisted unmanaged references
are preserved until adoption; new unmanaged references are refused.

Unused assets and untracked crash-orphan UUID files have 24-hour retention.
Filesystem errors are surfaced/logged. `storageKey` separates ownership metadata
from the local storage root; an object-store adapter can replace disk later.
Production still requires durable `WEBSITE_MEDIA_DIR`; existing public URL paths
are compatible.

## I. Domains

NO_PLAN cannot claim/publish a hostname. Both SAAS and CUSTOM domains require
WEBSITE/commercial eligibility to claim/activate and serve. Losing WEBSITE access
stops public serving immediately. Lifecycle reconciliation starts an explicit
30-day reservation grace (normally within 60 seconds), then deletes the domain
mapping with an audit. Historical audit remains.

Restoring access during grace cancels retention. After release, publishing even
unchanged content reclaims the address only if available; it cannot take a name
assigned to another Venue. DNS/TLS provisioning remains deployment-owned.

## J. Manager and POS

Without MANAGER_APP, owner responses omit the login code and usable Manager
setup data; create/reset endpoints deny. Disabling an existing Manager remains
allowed for security/support, with the existing durable Edge action and audit.
Accepted owners use memberships rather than legacy account provenance.

Without POS, enrollment issuance/redemption, new Platform Device setup and owner
printer setup deny; download/onboarding links are filtered. Historical enrolled
credentials, Device sync, offline operations and local recovery are not disabled
by the commercial resolver. No new Cloud-to-LAN operation was introduced.

## K. NON_FISCAL_CLOSE

Default OFF. Existing migration removes PlanFeature grants while retaining
explicit Venue overrides and all historical records. Catalog API and resolver
exclude it from plan inheritance; a database trigger rejects PlanFeature inserts
or updates granting it. An explicit operator Venue override can enable it, subject
to overall commercial eligibility, without affecting any other Venue.

## L. Plan and price controls

Platform can create/edit name, description, key, integer minor-unit price,
currency, MONTH/YEAR/ONE_TIME period, ACTIVE/RETIRED status, included features and
media quotas. Retired packages cannot be newly assigned. Existing agreed price,
currency and period snapshots survive catalog edits and reselecting the same
plan. A deliberate different-plan assignment snapshots that package's list terms.
Unknown historical agreements stay NULL rather than inventing a price.

## M. Platform controls

Existing Organization, Venue, customer membership/invitation, product override,
WebsiteMode, domain, Device, payment-status, Manager and audit screens are reused.
Onboarding adds customer/trial request review; Plans adds package editing; Venue
Commercial adds explicit plan/date selection; Product shows agreed pricing.
SYSTEM lifecycle audits render safely without a PlatformUser actor. Invitation
links remain manually copied, single-use secrets; no email provider was added.

## N. Customer dashboard

NO_PLAN has a clear no-active-package message and Website/POS/Manager cards with
contact actions. Only identity, subscription and account settings navigation is
available. Direct paid-section URLs render a locked state without active forms.
Website data is not fetched for unentitled accounts. Trial users can author/publish
entitled website content without being forced to upload a logo. Photo controls
require the server's media-upload capability.

## O. Cloud Restaurant Foundation compatibility

The in-flight Website-only plan, Cloud menu admission/editing controls and their
migrations are preserved. New `cloudMenuEditingEnabled` defaults false; existing
stored values survive migration. Operator enablement requires effective WEBSITE
and conservative first-use admission. Turning editing off preserves CLOUD
ownership; POS snapshots cannot overwrite it. POS-authoritative venues remain
protected. Device bootstrap stays frozen/staged; operational handover is not added.
`apps/operations`, Go Edge, `apps/vankisi-custom-web`, Sale and payment history are unchanged.

## P. Migrations and rollout

Preserved original migrations 20260929–20261002, including the existing payment
FK correction and non-fiscal grant removal. Added:

- `20261003120000_commercial_access_hardening`: legacy marker, quotas/media,
  requests, catalog prices, agreement snapshots, retention, SYSTEM audit and
  non-fiscal trigger; existing cloud editing values retained.
- `20261003120100_no_plan_default`: applies the new enum default in a separate
  transaction, after PostgreSQL has committed the enum value.
- `20261003120200_customer_trial_requests`: existing-Venue/account request links.

All 52 migrations replayed successfully from empty through Prisma migrate deploy.
`apps/backend/scripts/prove-commercial-upgrade.py` constructs and destroys only a
random disposable database on 127.0.0.1:55437. It proves preservation of existing
ACTIVE/TRIAL/missing-row Venues, plan assignments, explicit non-fiscal overrides,
domains, account hashes/memberships and safe new defaults.

For deployment: back up the deployment database, apply migrations before starting
the matching backend/frontend, keep the media directory durable, and review old
expired/undated trials and their pending domain grace. Old expired trials now deny
immediately. Historical agreed prices need operator business review; no values are
fabricated. This task did not run production migrations.

## Q. Validation

Working-tree validation (including preserved WIP):

- Backend: 52 suites / 445 tests passed; 34 database-dependent suites skipped by
  the generic run's existing environment gates.
- Explicit disposable PostgreSQL run: 4 suites / 40 tests passed (commercial,
  W1 payments, Website Core and restaurant foundation). Covers all 17 requested
  access/isolation cases, quota races, legacy media adoption, domain release and
  reclaim, price preservation, trial extension and settlement after removal.
- Platform/customer: 20 files / 105 tests passed, including request forms,
  no-plan direct routes, operator review, package feature/price editing and
  read-only support controls.
- Generic restaurant-web: 4 files / 19 tests passed; production build passed.
- Backend and Platform production/type builds passed; Platform retains its
  existing bundle-size warning.
- Browser: public request submission, approved NO_PLAN dashboard, subscription
  requests, Platform plan editor and review queue inspected using disposable data.
  NO_PLAN phone layout verified at 390 pixels without horizontal overflow.
- Exact staged backend independently rebuilt and passed the same 40 PostgreSQL
  checks without unrelated auth/password WIP. The isolated staged frontend also
  built and passed 104 tests (excluding the unrelated password-visibility WIP test).
- Empty migration replay, upgrade/backfill proof and diff whitespace checks passed.

Reproduce the targeted integration run from `apps/backend` after preparing the
isolated port-55437 cluster/database and applying migrations:

```sh
COMMERCIAL_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
W1_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
W3_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
FOUNDATION_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
npm test -- --runInBand commercial-access.integration.spec.ts payment-integrations.integration.spec.ts website-core.integration.spec.ts restaurant-foundation.integration.spec.ts
python3 scripts/prove-commercial-upgrade.py
```

The menu snapshot characterization harness lacked the existing authority lookup;
its fixture/expected trace was corrected without changing operational sync code.

## R. Commits and WIP

1. `f367ba6` — Finalize Cloud menu controls and explicit non-fiscal policy.
2. `5478ff0` — Separate customer ownership from commercial product access.
3. UI/documentation commit — Align acquisition and dashboards with commercial access.

Unrelated password-policy, authentication throttling, login-page styling,
Platform-user and local reset WIP remains uncommitted. Exact staged variants were
constructed from the initial snapshot, preserving working files; nothing was
stashed, pushed or overwritten to perform commit checks.

## S. Remaining boundaries

No automatic billing, email delivery, password recovery/verification, object
storage/CDN, DNS/TLS provisioning or production POS authority handover was added.
Request lists are bounded to the latest 200; dedicated search/pagination and a
distributed abuse limiter remain future scaling work. Scheduled expiry/cleanup
requires a running backend and access to its persistent media root. Existing
public media URLs remain public assets. These are explicit deployment/product
boundaries, not alternative activation paths.

## T. STOP

Milestone implementation and local validation complete. No push or live rollout.
