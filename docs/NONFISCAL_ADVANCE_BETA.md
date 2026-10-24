# Nonfiscal entitlement and advance closing — beta source qualification

This change is prepared for beta review only. No release feed, installer,
deployment, automatic-update setting, tenant configuration or historical
transaction is changed.

## Source

The isolated `codex/beta-entitlement-deposit` branch combines current main
`57164fac7209e982c5e3111ae8adf843584e1d6b` with Windows beta source
`b3c405b5` (including build 16 and printer fixes). Integration base:
`1aaafed67b1db9d9cda9143b44b65ced8e4d7a4a`. The original dirty checkout
was not used as the implementation source or modified.

## Authorization and customer presentation

- `NON_FISCAL_CLOSE` remains excluded from plan grants. Only an explicit
  Venue override grants it. The existing authorized principal is a live
  `PlatformUser` with `SUPER_ADMIN`, distinct from CustomerAccount owners and
  restaurant Staff. The Platform HTTP guard rejects other principal types and
  readonly support writes; the override service also checks this role before
  database access. No principal or override is created by this change.
- Missing POS configuration previously granted every feature. Nonfiscal
  access now requires an affirmative authenticated runtime pull bound to the
  current Device, Venue, installation and credential fingerprint. Legacy feature
  lists and inventory catalogs cannot grant it. The verified decision persists
  across offline operation and restart. It is device-only state: portable backups
  exclude it and restore preserves the destination's current decision, so an old
  backup cannot undo a known revocation.
- The 15-minute/session-only cutoff introduced in `d290c96e` was new, not an
  established policy, and was removed during independent review. No timed
  business restriction has been approved or imposed. Paid closure stays offline
  regardless of this capability. Manager retains explicitly resolved session
  features during an outage and clears them on missing/malformed snapshots,
  successful revocation or logout.
- A validated revocation is persisted independently of unrelated printer/profile
  errors and native printing activity. HTTP 401/403 or an unreadable successful
  feature decision denies the capability. Transient network/503 failures preserve
  the last verified decision. Identity changes invalidate its binding. The
  authorization does not read wall-clock time; changing the clock cannot create
  a grant or resurrect a persisted denial.
- Remote revocation cannot be learned while disconnected. An already verified
  grant therefore remains usable offline until a successful revocation/auth
  denial is received. Imposing an age limit or immediate remote revocation while
  offline would require an owner-approved business policy and connectivity model.
  Upgrades carrying only legacy unbound lists require one successful verification
  before nonfiscal use; absence of evidence never grants it.
- New local internal closes require the capability and an existing enabled
  Staff member permitted to close nonfiscally. This is checked in
  `CloseTableTransaction`, before a closure identity, journal or Sale is written.
  Ordinary paid closes cannot use nonfiscal tender aliases or claim collection that
  does not equal the sum of tender parts.
- Existing durable closure intents may complete after revocation. Cloud Sale
  and audit sync remain evidence ingestion, not authorization to execute a new
  close. They must still accept historical/offline evidence after revocation;
  rejecting that evidence would lose legitimate history. No Cloud or Go Edge
  endpoint currently executes a nonfiscal close, and no new Edge operation or
  frozen legacy callback operation is added.
- POS/Manager customer views hide nonfiscal controls, figures, sale entries and
  labels when disabled. Cancellation and advance evidence stays available.
  Audit closures use neutral labels and retain their original stored events,
  amounts and notes. Manager API projection removes nonfiscal fields; ledger
  list/detail queries apply access before pagination and return 404 for hidden
  direct Sale detail requests. Already-open confirmation, X report, audit dialogs
  and internal Sale sheets also react to entitlement changes. These are read projections, never history updates.

## Accounting

For a GEL 1000 completed sale with GEL 100 collected earlier:

| Fact | GEL |
| --- | ---: |
| Gross sale / completed sale history | 1000.00 |
| Advance applied | 100.00 |
| Due and collected at closure | 900.00 |

The advance receipt remains on its collection business date. Its application
is a settlement component, not a second payment or additional revenue. Existing
closure identity and sync revision rules prevent repeated close/sync from
creating another sale. Zero, partial and full advances, cash/card split tender
and previously collected advances retain this separation.

The final transaction snapshot previously recorded the net balance as `total`;
both its builder and the authoritative journal writer now store gross and
separate settlement fields. POS history reads explicit gross/advance facts,
does not infer an advance from a discount, and no longer adds the advance to
an already-gross sale total. Advance receipts no longer receive nonfiscal
payment labels or closure badges merely because they are excluded from revenue.

This follows D010. Legacy records without explicit gross retain their established
fallback; no amount is inferred to repair historical transactions. Refund,
forfeiture and excess-advance policies are unchanged. No tax policy is invented
or changed. The stored `isFiscal` flag is the existing ordinary-sale revenue
classification; it is not evidence that a fiscal device issued a receipt. Paid
sale/close labels now say recorded sale or paid close, even for nonfiscal-enabled
customers. Operational combined gross is labeled as such. Financial profit uses
ordinary recorded revenue and all selected-month expenses, independently of the
nonfiscal presentation permission.

## Validation and limits

- Flutter focused regression set: **174 passed**, including real temporary Hive
  closure/audit recovery, entitlement missing/off/on, unauthorized Staff, exact
  GEL 1000 settlements, repeated close and wire snapshots, durable offline identity, revocation and backup replay protection,
  synthetic sales UI, payment forms and Manager financial sync.
- Backend unit/HTTP set: **29 passed**. Includes rejected owner, Manager,
  Device, anonymous and readonly support requests; admitted Platform admin;
  direct service denial; server-owned Venue projection and retained audit data.
- Flutter analysis: **no issues**. Backend TypeScript check and Nest build pass.
- Disposable PostgreSQL: fresh complete migration deployment; ledger,
  entitlement and commercial suites pass. The final cross-runtime run also
  ingests six Dart-emitted synthetic legacy payloads. Full selected run:
  **107 passed, 2 failed, 0 skipped**. The two failures are existing Platform
  hostname resolver cases, reproduced on the unchanged integration base
  (**41 passed, the same 2 failed**). They are deferred, outside this fix.
- The exact repaired Windows build-16 printing/update selection passes **161
  tests in ten suites** on this macOS source review. Its prior Windows evidence
  is `/tmp/vynic-beta-candidate-1.0.0-16-print-label-v2/qualification-receipt.json`.
  The older 151 figure preceded the fixture repair. No test is excluded here.
- The separate existing `cloud_printer_runtime_sync_test.dart` has **20 fixture
  failures**, identical on the unchanged integration base: the fixture seeds
  `menu01-venue-a` and then attempts enrollment under another Venue. The tenant
  binding guard correctly refuses before runtime configuration executes. No
  printer implementation or tenant guard was weakened to make this test pass.
- Synthetic sales UI is rendered at 1024×768 with Georgian fonts for missing,
  disabled, enabled and revoked capability states. Screenshots and full logs
  are temporary proof files; no restaurant data is used.
- Windows binary/device/installer qualification, rollout and stable promotion
  are **not run**. Existing POS/Edge processes remain untouched. Review the
  source changes and these results before any release; no new Windows artifact
  was built during this review.

Independent read-only review identified the cutoff, reactive-view, revocation
admission, backup replay, fiscal-label and permission-dependent profit gaps; the
bounded repairs have dedicated regressions. This is source qualification, not
permission to merge, deploy or promote stable.

Local review evidence: `/tmp/vynic-accounting-review-final.log`,
`/tmp/vynic-accounting-review-printing.log`,
`/tmp/vynic-accounting-review-boundaries.log`,
`/tmp/vynic-entitlement-flutter-final.log`,
`/tmp/vynic-entitlement-backend-unit.log`,
`/tmp/vynic-accounting-proof/{tests.json,baseline-platform-tests.json,receipt.json}`,
`/tmp/vynic-accounting-baseline/cloud-printer.log`, and
`/tmp/vynic-accounting-ui/`.
