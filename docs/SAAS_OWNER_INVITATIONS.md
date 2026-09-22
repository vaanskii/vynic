# SaaS owner membership and assisted onboarding

## Previous limitation and ownership

The pilot used CustomerAccount.organizationId as both identity and ownership.
Signup always created an Organization; Platform could not hand a prepared Venue to
an owner without a password. OrganizationMembership(customerAccountId,
organizationId) now grants OWNER access. Multiple Organizations per account and
multiple owners per Organization are supported. Organization owns Venues.

The legacy nullable account Organization field is provenance only. Owner routes
and website preview authorization query live membership; JWTs contain no tenant
authority. POS, Manager, Edge, Vankisi CUSTOM and BOG flows are unchanged.

## Flows and website default

Self service remains /portal signup → account + Organization + OWNER membership →
restaurant creation → policy plan + TRIAL. The one-Venue-per-Organization pilot
restriction remains. Multi-Organization accounts specify a membership-authorized
organizationId for restaurant creation.

Platform /admin/onboarding separates pilot policy, customer preparation and owner
invitations. Preparation atomically creates Organization, Venue, plan assignment,
TRIAL (1–90 days) or ACTIVE subscription, website setup and invitation. It works
even when self-registration is closed. Platform Venue pages retain feature,
subscription and website-mode controls before or after acceptance. Existing
Organizations can also receive invitations.

New invitees choose their own name and 15–128-character password, using Argon2id
and the current signup policy. Existing accounts must sign in normally and then
accept with a Customer JWT whose normalized email exactly matches the invitation.
Email matching alone grants nothing. Acceptance creates no Organization or Venue.
The portal selects the prepared Venue, offers a selector for multiple restaurants,
and shows the website editor before operational setup.

OnboardingPolicy.defaultWebsiteMode uses a separate NONE/SAAS enum, default NONE.
Only SAAS plus effective WEBSITE creates VenueWebsiteConfig(SAAS, DRAFT), inside
the provisioning transaction using the shared feature resolver. Policy changes
do not retrofit existing Venues. CUSTOM is never automatic. Publication remains
explicit; Platform retains mode authority.

## Invitation security

- 32 random bytes / 256 bits; only SHA-256 verifier stored. Raw token is returned
  once at issuance/regeneration; list/status/audit omit both secret and hash.
- Seven-day expiry; accepted/revoked timestamps and actors retain history.
  Platform issuance/revocation and customer acceptance are audited.
- Acceptance, issuance, revoke and regeneration serialize on the Organization.
  Account, membership, acceptance and audit commit atomically; concurrent
  acceptance has exactly one winner.
- Regeneration creates a fresh invitation and revokes previous unused links for
  that Organization/email. Accepted invitations cannot be changed; regeneration
  never undoes membership.
- Links use /portal/invite#token=… so tokens never enter HTTP URLs. The portal
  clears the fragment and keeps it only in memory; reload requires reopening the
  link. Tokens are submitted in bodies, never logged by this implementation.
  Deployments must not enable request-body logging for auth/invitation endpoints.
- Inspection/acceptance have per-IP throttling; login retains IP/email throttling.
  Secret/context responses are no-store. Platform, Customer, Staff, Device and
  preview audiences remain separate. SUPPORT_READONLY cannot mutate invitations.
- Acceptance does not mark emailVerifiedAt. A manually copied link is not a claim
  of verified email ownership. Password recovery/email verification remain absent.

## API

Platform routes require Platform JWT; invitation acceptance requires Customer JWT
when an account already exists.

| Method / path | Behavior |
| --- | --- |
| PUT /platform/onboarding/policy | Adds defaultWebsiteMode NONE/SAAS |
| POST /platform/onboarding/customers | organizationName, name, email, planId, trialDays, subscriptionStatus TRIAL/ACTIVE |
| GET /platform/onboarding/organizations | Organizations and Venue references |
| GET /platform/onboarding/invitations | Latest 200 records; no secrets |
| POST /platform/onboarding/invitations | organizationId + email; one-time invitationPath |
| POST /platform/onboarding/invitations/:id/revoke | Revoke unused invitation |
| POST /platform/onboarding/invitations/:id/regenerate | Fresh link; previous unused links revoked |
| POST /customer/invitations/inspect | token; context and existingAccount flag |
| POST /customer/invitations/register | token, displayName, password; new accounts only |
| POST /customer/invitations/accept | token + normal Customer JWT, exact email match |

The invitation path is relative to the portal origin. Acceptance returns the
existing organizationId and first venueId for selection, not a client-controlled
redirect. All subsequent access is membership-checked.

## Migration and rollout

Migration 20260927120000_organization_owner_invitations adds the two relations and
restricted website-default enum. Backfill copies each pilot account's existing
Organization to an OWNER membership, without matching email, changing passwords,
moving Venues or touching website/subscription data. Old columns remain.

Pause account creation briefly while deploying the migration and new backend,
then reopen registration. Old application instances do not write memberships;
do not leave them serving signup after backfill. Deploy portal after backend.
Generated Prisma clients are generated normally, never hand-edited or committed.

Existing-row proof, from repository root:
~~~sh
PG_BIN=/opt/homebrew/opt/postgresql@17/bin python3 apps/backend/scripts/prove-onboarding-backfill.py
~~~
This intentionally creates a fresh vynic_owner_backfill_disposable database and
refuses to reuse one. It applies prior migrations, inserts pilot accounts in two
Organizations and an existing CUSTOM draft, applies the new migration, then
asserts membership, hashes, ownership, website data and safe NONE policy default.

## Local end-to-end harness

Only isolated PostgreSQL is permitted. The harness and new HTTP suite require
127.0.0.1:55439/vynic_onboarding_phase3_disposable and never select
vankisi_database. No operational workers, bank clients or email service start.

From repository root, once (use equivalent PostgreSQL paths on other systems):
~~~sh
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/initdb -D /tmp/vynic-onboarding-pg -A trust -E UTF8
/opt/homebrew/opt/postgresql@17/bin/pg_ctl -D /tmp/vynic-onboarding-pg -l /tmp/vynic-onboarding-pg/server.log -o '-h 127.0.0.1 -p 55439' start
/opt/homebrew/opt/postgresql@17/bin/createdb -h 127.0.0.1 -p 55439 vynic_onboarding_phase3_disposable
~~~

Backend terminal:
~~~sh
cd apps/backend
export ONBOARDING_TEST_DATABASE_URL="postgresql://YOUR_LOCAL_USER@127.0.0.1:55439/vynic_onboarding_phase3_disposable"
DATABASE_URL="$ONBOARDING_TEST_DATABASE_URL" npx prisma migrate deploy
npx prisma generate
node -r ts-node/register/transpile-only scripts/serve-onboarding-local.ts --confirm-local
~~~

Portal terminal:
~~~sh
cd apps/platform-web
VITE_API_BASE_URL='' npm run dev -- --host 127.0.0.1
~~~

Restaurant terminal:
~~~sh
cd apps/restaurant-web
VYNIC_WEBSITE_API=http://127.0.0.1:3000 npm run dev
~~~

Backend: 3000; portal: 5173; restaurant-web: 5175.
The isolated harness sets SAAS_WEBSITE_BASE_DOMAIN=vynic.localhost and preview
origin http://preview.vynic.localhost:5175. Vite preserves browser Host.
Chromium resolves *.localhost to loopback. Other clients may need an explicit
resolver mapping (curl --resolve hostname:5175:127.0.0.1).

Open http://127.0.0.1:5173/admin/onboarding. Local fixture credentials:
admin@onboarding.test.invalid / Local onboarding admin password!
Seed creates that admin, Local website trial plan and initial open SAAS policy,
but no owner or Venue. Repeat launches preserve policy edits; enable registration
and select the local plan if earlier tests changed it.

Assisted proof: create a customer restaurant, copy its link into a fresh browser
context, accept, edit website slug/title, save, open Publication → Preview in real
restaurant-web, then publish. Visit http://<slug>.vynic.localhost:5175.
Self proof: fresh /portal session → signup → create restaurant → save/preview/publish.

Automated real-browser proof from repository root:
~~~sh
node apps/backend/scripts/prove-onboarding-browser.cjs
~~~
Requires Playwright and Chromium. PLAYWRIGHT_MODULE can name a shared installation;
ONBOARDING_BROWSER_PATH can name an installed Chromium-based executable.
Screenshots and a token-free result manifest go to /tmp/vynic-onboarding-proof
(or ONBOARDING_PROOF_DIR). Secret fields are masked. Both paths use real forms,
including invitation acceptance, draft editing, preview and publication. The
proof also checks the 390px owner portal for horizontal overflow.

## Validation and remaining gaps

The new HTTP suite covers concurrent single use, existing/wrong accounts,
expiry/revoke/regeneration, principal separation, membership revocation,
cross-Venue writes, default website modes, draft secrecy, disabled WEBSITE and
CUSTOM marker-only responses. The existing Website Core/W3 tests cover broader
preview and Host isolation in their separately pinned vynic_w3_disposable database.

~~~sh
cd apps/backend
ONBOARDING_TEST_DATABASE_URL="postgresql://YOUR_LOCAL_USER@127.0.0.1:55439/vynic_onboarding_phase3_disposable" npm test -- --runInBand owner-invitations.integration
~~~

Remaining pilot limits: manual link delivery, no password recovery/email
verification/MFA, no membership-removal UI or general RBAC, one self-created Venue
per Organization, latest-200 invitation history without pagination, no billing
provider, production DNS/TLS/media hosting remains deployment work. Provisioning
has no client retry key: after a lost create response inspect Organizations before
submitting again. Invitation regeneration safely revokes older pending links.

## Verified result

Local validation completed on 2026-09-22:

- 36 backend PostgreSQL/HTTP tests passed across owner invitations, existing
  onboarding, Website Core and W3 suites.
- 50 portal tests and 16 restaurant-web tests passed.
- Backend, portal and restaurant-web builds passed; Prisma schema validation and
  existing-row migration/backfill proof passed.
- The real Playwright/Brave browser proof completed both onboarding paths,
  rendered both real previews and both Host-scoped published pages, and passed
  the 390px no-overflow check. Screenshots were visually inspected.
- Targeted lint for new production code and harness passed. Repository-wide
  portal lint still reports existing any-type/effect issues; the touched legacy
  files were compared with HEAD and have unchanged error/warning counts.
  The portal build retains its existing bundle-size warning.
- All database accesses used the explicitly named disposable loopback databases.
  No live vankisi_database access, migration, commit of secrets or push occurred.
