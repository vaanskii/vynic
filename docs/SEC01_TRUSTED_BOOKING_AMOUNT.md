# SEC-01 — Trusted server-side booking amount

**Status: DONE — proof closed on 2026-09-29 (UTC).** Real disposable PostgreSQL,
migrations, Nest HTTP, tenancy/commercial negatives and fake-provider assertions
pass. Final SEC-01 result: 83 regressions plus 45 HTTP/PostgreSQL cases, none
skipped; six affected integration suites add 89 passing tests. Compatibility
checks pass and all disposable database resources are removed. The initial
blocked attempt is retained below as history. This is not a paid-website release
approval; no later milestone was started.

## Baseline and provenance

- Date: 2026-09-29; baseline captured at `19:14:05 UTC`.
- Branch: `codex/docker-deployment-foundation`.
- HEAD: `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b`.
- Starting worktree: 30 modified tracked files, two owner untracked files, and
  the untracked audit directory (15 documents, including the Master Plan).
- The current creation paths still contained the reported vulnerability; there
  was no partial SEC-01 implementation to preserve or finish.
- Implementation commit after proof closure:
  `cb283d9e483a2d757d845faccd2519987a0051bd`. Only SEC-01 implementation/tests were
  included; current proof documentation follows in a separate focused commit.
  No reset, stash operation, branch replacement, push or unrelated WIP commit.
- A private baseline records SHA-256 for 1,952 existing files. The historical
  audit and unrelated files are preserved. Current state/map receive only the
  SEC-01 entries described below.

Execution roadmap: [Master Plan, milestone 1](audits/2026-09-29-f7bb982/VYNIC_MASTER_STABILIZATION_AND_RELEASE_PLAN_2026-09-29.md#milestone-1--sec-01-trusted-server-side-booking-amount).
Original evidence remains in [MASTER_BACKLOG](audits/2026-09-29-f7bb982/MASTER_BACKLOG.md),
[WEB_COMMERCIAL_SECURITY](audits/2026-09-29-f7bb982/WEB_COMMERCIAL_SECURITY.md),
[SECURITY_AND_RELIABILITY](audits/2026-09-29-f7bb982/SECURITY_AND_RELIABILITY.md),
[EVIDENCE_AND_MATRICES](audits/2026-09-29-f7bb982/EVIDENCE_AND_MATRICES.md),
[IMPLEMENTATION_ROADMAP](audits/2026-09-29-f7bb982/IMPLEMENTATION_ROADMAP.md) and
[SYSTEM_AND_ARCHITECTURE](audits/2026-09-29-f7bb982/SYSTEM_AND_ARCHITECTURE.md).
Those documents were not rewritten to erase the finding.

## Entry points, root cause and new boundary

The public creation inventory found these two routes. Preorder lines are attached
as `menuItems` during the same reservation creation; there is no separate public
preorder writer. `ReservationService` contains the sole production
`websiteReservation.create` call. Callback/status/bridge updates and the explicit
payment integration import are separate existing operations.

Previous flow:

```text
POST /api/bog/create-order
  BogController -> BogService.validateAndCalculateOrder -> ReservationService
  -> WebsiteReservation -> BogService.createOrder

POST /api/tables/reservations
  TableController -> TypeScript interface + request-body spread
  -> ReservationService accepts client totalAmount and menuItems
  -> WebsiteReservation -> BogService.createOrder (minimum 1 GEL)
```

Pricing was a controller-specific prerequisite. The persistence boundary accepted
already-priced request data without proving its origin, allowing the alternate
route to persist and send 1 GEL for a 100 GEL cart plus 10 GEL service.

Current flow:

```text
Host -> WebsiteTenantGuard -> VenueDomain -> active Venue
  -> WEBSITE / launch / RESERVATIONS + ONLINE_PAYMENTS guards
  -> BogController.createOrder OR TableController.createReservation
  -> ReservationService.createReservation(tenant, unknown body, session user)
  -> bookingIntent runtime DTO / bounded quantities
  -> existing table ownership and availability checks (active tables only)
  -> BogService.validateAndCalculateOrder -> priceBookingCart [one formula]
     -> MenuService.getBookableSelection [Venue-owned canonical item/variant]
     -> integer-minor-unit BookingPaymentIntent { amountMinor, currency: GEL }
  -> preparePayment [entitlement, enabled integration, active return domain]
  -> WebsiteReservation [trusted total, canonical priced lines, integration ID]
  -> BogService.createOrder [same intent, integration revision recheck]
  -> BOG purchase_units.total_amount / currency / basket.unit_price
```

The adapter has no independent pricing/minimum formula and receives no request
money. Invalid provider order responses fail explicitly. Callback processing,
availability concurrency, POS dispatch and subscription billing are unchanged.

## Runtime request contract and client compatibility

- Both routes accept `unknown` at the controller and use the same explicit
  runtime validator inside reservation creation. A TypeScript interface is not
  relied upon for runtime validation.
- Intent: selected tables/date/time, item IDs, optional `variantId`, quantity,
  optional contact/notes/language/guest count. Table IDs and other strings are
  bounded; date/time must use `YYYY-MM-DD` / `HH:mm`.
- Legacy `totalAmount`, item `price`/`total`, service fields, currency, nested
  payment objects and display fields are accepted but discarded. The legacy
  claimed total is used only for the informational mismatch flag, never pricing.
  Browser `venueId` and `userId` are discarded; Host and session remain authoritative.
- Quantities must be numeric safe integers from 1 to 1,000; at most 100 cart
  lines and 1,000 units across the entire cart. Duplicate lines cannot bypass
  the aggregate bound. These are request-work bounds, not stock/capacity rules.
  Coercing strings, flooring fractions and replacing invalid quantities with 1
  are intentionally removed.
- Missing, foreign, disabled or website-hidden items fail before persistence or
  a provider call. Variants must belong to the selected item and Venue. A parent
  with variants requires a selection; its display minimum is not a payable price.
- Vankisi's existing `{ id: variant.id, quantity, price }` request remains valid:
  the server resolves its parent within the Venue. Explicit parent ID plus
  `variantId` is also valid. Persisted lines use canonical parent/variant IDs;
  BOG `correctedCartItems` keeps the legacy variant ID so a corrected cart can
  be submitted again. Existing response wrappers/redirect fields remain.

Inspected Vankisi callers: `pages/Menu.tsx`, `pages/Cart.tsx`,
`pages/Checkout.tsx`, `services/api.ts`. No frontend migration or dependency on
`templates/custom-site` / `packages/website-client` was introduced.
The shared client's `bookAndPay` already calls the BOG route; the starter's
table-only request remains compatible. The generic SaaS renderer is currently
read-only: its successful tests/build are not proof of a paid SaaS UI journey.

## Money and security

Server catalog prices are converted with the existing Prisma Decimal half-up
convention to integer GEL minor units. Multiplication, addition and the 10%
service calculation use `bigint`; service rounds half up to a minor unit. The
existing minimum of 100 minor units (1 GEL), including an empty cart, is retained.
For example, `0.35 × 3 = 1.05`, service `0.105 -> 0.11`, payable `1.16 GEL`.

The intent carries a safe integer and server-fixed `GEL`. Conversion to the
existing numeric persistence/provider contract is checked for exact decimal
minor-unit round-trip; unrepresentable/oversized values fail. The same trusted
amount is persisted and sent. There is no schema migration, historical repricing,
global Float conversion or new configurable deposit policy. A different service
rate/deposit/minimum would require a separate product decision.

Both public creation methods now require `RESERVATIONS` and `ONLINE_PAYMENTS` in
addition to the existing WEBSITE/Host checks. The capability guard enforces launch,
commercial inclusion and operator switches; its readiness display is not used as
authorization. Active selected tables and `preparePayment` enforce the relevant
concrete prerequisites. The WEB-06 readiness projection issue remains open.

Payment integration ownership, encrypted credential lookup and original revision
retention are unchanged. The adapter still refuses a revision change between
prepare and order creation. Browser status retains Host ownership; callback
signature and stored payment identity handling are unchanged. This does not add
the expected-amount/currency callback state machine assigned to WEB-04.

## Changed files

| File under `apps/backend/src/` | Change |
| --- | --- |
| `website/reservation/booking-request.ts` | New shared runtime intent/cart validation |
| `website/payment/booking-pricing.ts` | New single pricing formula and minor-unit intent |
| `website/menu/menu.service.ts` | Canonical, Venue-scoped bookable item/variant selection |
| `website/reservation/reservation.service.ts` | Price inside the persistence boundary; trusted user separately |
| `website/reservation/reservation.controller.ts` | Shared intent path and payment capability guard |
| `website/payment/payment.controller.ts` | Delegate to shared creation; compatible corrected carts |
| `website/payment/payment.service.ts` | Delegate pricing; consume trusted intent in BOG adapter |
| `website/payment/booking-payment.spec.ts` | 83 regression/adapter/guard tests |
| `website/payment/booking-payment.integration.spec.ts` | 45 disposable PostgreSQL / HTTP cases (39 original + 6 added for proof closure) |
| `tenancy/public-tenant-isolation.integration.spec.ts` | Existing payment stub delegates to real shared pricing |

Documentation: this note plus small current-state and code-map entries. No
generated contracts, frontend files, migrations or dependency manifests changed.

## Initial implementation validation — before proof closure

Verification used an isolated copy of current source, with existing installed
dependencies copied in; no installs/upgrades and no owner `.env` files were copied.
Database URL environment variables were excluded from the non-database runners.

| Check | Result |
| --- | --- |
| Same money-tampering regression on original creation code | 7 failures on alternate route; 7 passes on BOG route, as expected |
| SEC-01 regression suite on fixed code | **83 passed**, 39 PostgreSQL/HTTP cases skipped |
| Related backend suites: website tenancy/capabilities, entitlements, payment encryption, table identity | **91 passed** across 11 suites |
| Backend `npm run build` | Passed |
| Explicit TypeScript check including both new suites and adapted tenant-isolation suite | Passed |
| SaaS restaurant-web tests / build | **19 passed** / passed |
| Shared website-client tests / typecheck | **6 passed** / passed |
| Vankisi CUSTOM production build | Passed; no current test script or browser/bank journey claimed |
| Four new source/test files: scoped ESLint | **0 errors, 0 warnings** |
| Five modified production files: scoped ESLint | 21 existing errors, 4 existing warnings; baseline was 29 errors, 4 warnings |
| Lint diagnostics compared by file, rule, message and source line | No new remaining diagnostic |
| `git diff --check` | Passed |

The original source regression was run only in the isolated copy and restored
there afterwards. No owner checkout file was reverted. Remaining lint diagnostics
are in unchanged status/token/serialization code; no broad lint cleanup was made.

Required-case coverage:

| Requirement | Regression / proof level |
| --- | --- |
| A, B, C, N, O: normal, forged total/price, route parity, provider payload | Both real controller/service chains with mock persistence and provider; 110 GEL stored/sent despite client 1 GEL |
| D, E, F, G: foreign/mismatched/missing/disabled/hidden selection | Both routes reject before write/provider; canonical menu lookup exercised with mock rows |
| H, I, J, K: zero, negative, fractional, string/null/nonfinite, oversized quantity | Both routes reject; aggregate duplicate and line bounds covered |
| L: disabled payment capability/integration | Actual handler metadata + capability guard; fail-closed integration rejection tested; database-backed cases pending |
| M: expired/non-entitled commercial state | Existing commercial/entitlement rule suites pass; end-to-end HTTP cases for NO_PLAN, SUSPENDED, CANCELLED, expired TRIAL are written but blocked |
| Identity/revision regressions | Host/tenancy/encryption suites pass; session user overrides body user; changed integration revision rejected before bank calls; forged-callback HTTP case pending |
| Compatibility / rounding | Legacy and explicit variant IDs, corrected-cart resubmission, empty-cart minimum and exact service rounding pass |

## Initial blocked PostgreSQL / HTTP attempt — superseded below

`initdb` for a new private cluster failed during bootstrap:

```text
FATAL: could not create shared memory segment: Operation not permitted
Failed system call was shmget(...)
initdb: removing data directory .../pgdata
```

A separate loopback listener probe failed with
`listen EPERM: operation not permitted 127.0.0.1`.
No database was created, so there was no existing database to check or drop.
Neither the owner dataset nor `vankisi_database` was connected to or modified.
The failed cluster directory was removed by `initdb` itself.

The initial 39-case integration suite used real Prisma persistence and Nest HTTP controllers,
Host/feature/capability guards, synthetic CUSTOM and published-SAAS Venues,
Venue-owned menu/integration rows, and fake BOG responses. Auth is stubbed as
anonymous and availability as available because session ownership and WEB-01
concurrency are outside this fixture's proof. It accepts only an explicit
`SEC01_TEST_DATABASE_URL` for `127.0.0.1/disposable_sec01_*`; it has no default
database, migration, reset or database-drop action. The name/host guard alone is
not proof of ownership: the runner must establish ownership before supplying it.

To finish acceptance in an environment that permits PostgreSQL and HTTP:

1. Create an audit-owned local cluster, choose a fresh `disposable_sec01_*` name,
   query `pg_database` for that exact name and abort if it exists. Record absence
   and successful creation before proceeding.
2. Apply repository migrations only to that new database. Set only its URL as
   `SEC01_TEST_DATABASE_URL`, then run the new integration suite with Jest
   `--runInBand --runTestsByPath src/website/payment/booking-payment.integration.spec.ts`.
3. Run affected existing payment-integration, custom-website and public-tenant
   integration suites against separately owned disposable fixtures using their
   documented URL guards. Retain their existing credential/callback tests.
4. Record HTTP status, persisted total/menu/integration identity and fake-provider
   payload results; clean up only resources whose creation was recorded in this
   run. Real bank charges must remain zero.

**Real bank calls/charges in the initial implementation pass: 0.** All axios
provider calls were mocked. In that pass the 39 cases were collected and
type-checked, not executed against PostgreSQL or real HTTP. The subsequent real
execution and authenticated HTTP proof are recorded below; BOG sandbox and a
complete browser UI journey are not claimed.

## Proof closure — 2026-09-29 (UTC)

The execution baseline remained branch `codex/docker-deployment-foundation`,
HEAD `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b`, including the prior SEC-01 WIP.
The proof run recorded hashes for 1,957 existing files before work. Tests/builds
ran on a current-source copy, without owner `.env` files or customer database
URLs. Existing installed dependencies were copied, not upgraded.
Proof applies to the recorded HEAD plus existing WIP and SEC-01; unrelated WIP
remains outside the focused SEC-01 commits.

### Actual environment and migration evidence

- Private native PostgreSQL **17.10 (Homebrew)**, bound only to
  `127.0.0.1:62028`; cluster directory
  `/private/tmp/disposable_sec01_proof_20260929t194303z_7fc07325/pgdata`.
- Initial database: `disposable_sec01_20260929t194303z_7fc07325`.
  Final acceptance database: `disposable_sec01_7fc07325_acceptance_final`.
- Each exact name was queried in `pg_database` and confirmed absent before
  creation. Thirteen databases across initial/final attempts and separate suites
  were recorded as verification-owned. All had the `disposable_sec01_` prefix;
  no existing database was reused.
- **60 repository migrations applied successfully.** Prisma validation and
  migration status pass; schema diff against current `schema.prisma` reports an
  empty migration (exit 0). All 60 stored checksums match source. No migration
  was changed.
- Migration tip: `20261011120000_canonical_menu_sync`; SHA-256:
  `25b9cbb8d6d8590b702acdf2a35f38852c8110f7c21a752887bbbf49061049ac`.

The compact, durable result with database ownership/cleanup, migration checksums,
test names and tested source hashes is
[SEC01_2026-09-29.json](proofs/SEC01_2026-09-29.json). Raw local logs are in
`/private/tmp/disposable_sec01_proof_20260929t194303z_7fc07325/`.

### Executed tests and required HTTP/DB assertions

| Check | Final result |
| --- | --- |
| Original SEC-01 integration suite after fixture correction | **39/39 passed**, no skips |
| Expanded SEC-01 integration suite | **45/45 passed**, no skips |
| SEC-01 controller/service regressions in the final combined run | **83/83 passed** |
| Payment integrations (credentials/revision/callback/ownership) | **8/8 passed** |
| Public tenant isolation | **20/20 passed** |
| Website provisioning | **14/14 passed** |
| Custom website | **15/15 passed** |
| Commercial access | **16/16 passed** |
| Subscription/commercial lifecycle | **16/16 passed** |
| SaaS restaurant-web | **19 tests passed**, production build passed |
| Shared website-client | **6 tests passed**, typecheck passed |
| Vankisi CUSTOM | Production build passed |
| Backend | Build and SEC-01 test/source typecheck passed |
| Four new SEC-01 source/test files | ESLint **0 errors, 0 warnings** |
| Diff validation | `git diff --check` passed |

The repository Jest invocation was used with `--runInBand --runTestsByPath`.
For SEC-01 only `SEC01_TEST_DATABASE_URL` supplied the database connection to
the test suite; migration commands separately received the same owned target as
`DATABASE_URL`. No SEC-01 HTTP case was skipped or replaced by a controller mock.

Both `POST /api/bog/create-order` and `POST /api/tables/reservations` ran through
real Nest routing, runtime validation, Host/feature/capability guards, Prisma
and PostgreSQL. With canonical price 100 GEL and quantity 1, the valid and forged
`totalAmount=1` / `price=0.01` requests both persisted and sent **110 GEL**.
Currency remained **GEL** and the provider basket unit price matched the trusted
total. Legacy and explicit variant requests both produced **44 GEL** for two
20 GEL units plus service.

Foreign/missing/disabled/hidden items, foreign/mismatched variants, zero/negative/
fractional/string/null/oversized quantities, oversized carts and aggregate
duplicate quantities were denied before reservation creation or a provider call.
Disabled RESERVATIONS/ONLINE_PAYMENTS switches returned 404; missing/disabled
integration returned 403. NO_PLAN, SUSPENDED, CANCELLED and expired TRIAL were
denied under existing commercial/domain policy (403/404). Unknown/disabled Host
and disabled Venue were denied despite a body `venueId`.

The six added cases cover aggregate bounds, missing integration and session
identity on both routes. Session identity uses the real `WebsiteAuthService`,
signed JWT, encrypted cookie and cookie parser: a forged body `userId` cannot
replace the signed-in user, and an anonymous request cannot attach itself to the
body-selected account. Availability alone remains stubbed as available because
WEB-01 concurrency is outside this proof; all financial, tenant and commercial
paths are real.

Before cleanup, a separate SQL read verified **16 persisted synthetic bookings**,
totals 44/110 GEL, two authenticated bookings, every integration belonging to the
booking's Venue, fake provider IDs only, and all rows still PENDING after the
forged-callback test. Existing payment tests also passed credential rotation,
original-revision reads after disablement, cross-Host denial and mismatched
callback identity rejection. No WEB-04 callback redesign was made.

### Corrections exposed during execution

The original fixture marked a website PUBLISHED without its required publication
snapshot/revision/slug/timestamp, which the real database correctly rejected via
`website_publication_consistent`. The fixture now uses normal CUSTOM launch state
and a complete published-SAAS snapshot. The added missing-integration fixture was
also completed with required Venue timezone/currency before the final run.
**No SEC-01 application-code defect was exposed; no production correction was
needed during proof closure.**

Some existing suites initially failed because the isolated runner intentionally
had no owner `.env`: synthetic JWT refresh/cookie keys and the SaaS base domain
were then supplied. The network guard was also narrowed to permit the custom
suite's two synthetic local health checks. All affected suites then passed
unchanged; no unrelated tests or migrations were weakened.

### Provider isolation, compatibility and cleanup

**Real bank/provider network calls = 0; real charges = 0.** Axios was mocked in
payment suites, the SEC-01 suite asserts that its provider function is a mock,
and a runner-level Node socket guard blocked external destinations. The only
initial guard denials were two verification-owned `*.localhost` health checks,
not bank requests. Real Nest/Supertest loopback HTTP was allowed and exercised.

Vankisi-compatible request shapes and corrected variant carts passed. The
independent Vankisi frontend was unchanged. SaaS/shared-client checks were rerun;
the generic SaaS renderer remains read-only, so no paid SaaS UI or full browser
journey is claimed.

All **13 owned databases were dropped**, with exact-name absence checked after
each drop. The private PostgreSQL process was stopped, its port was verified
closed and its cluster directory removed. No Docker mutation command or normal
Vynic database connection was made. Before/after Docker inventory retained the
same container IDs, names, images, mount summaries and states, including the
normal local-prod PostgreSQL container. `vankisi_database` was never accessed.
Temporary copied dependencies/build outputs are removed after verification;
source snapshots and logs remain as local evidence.

**Final status: DONE for SEC-01 only.** Paid-website release still requires the
remaining roadmap gates. SEC-02 and later milestones were not started.

## Evidence and remaining scope

Private local evidence: `/private/tmp/vynic-sec01-20260929-f7bb982/`:
`baseline.json`, `original-git-status.txt`, `sec01-before-fix.{json,log}`,
`sec01-unit.{json,log}`, `final-sec01-results.json`, `verification-results.json`,
related backend/frontend reports, `scope-{baseline,current}-lint.json`,
`scope-lint-comparison.json`, `postgres-preflight.log`, `http-preflight.json`,
and final preservation/status records. This temporary directory is not a durable
CI artifact; test sources and this proof-level statement are in the repository.

Only SEC-01 was implemented. SEC-02, WEB-01, WEB-02, WEB-03, WEB-04, WEB-06 and
MENU-07 remain open; this work does not close their acceptance criteria. No live
bank/customer workflow or deployment was performed. **STOP after SEC-01.**
