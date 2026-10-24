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
  access now requires an affirmative authenticated runtime pull for the current
  Device and Venue. Persisted feature lists, inventory catalogs and restored
  backups alone cannot grant it. The grant is session-only, bound to the open
  settings store, and expires after 15 minutes of monotonic elapsed time.
  Successful pulls renew it; offline/invalid pulls cannot renew it. Restart
  starts disabled until a successful pull. Ordinary fiscal operation remains
  offline-first. This bounds disconnected revocation latency at 15 minutes.
- Manager snapshots similarly fail closed on absent/malformed features and
  expire nonfiscal presentation after 15 minutes without a successful refresh.
- New local internal closes require the capability and an existing enabled
  Staff member permitted to close nonfiscally. This is checked in
  `CloseTableTransaction`, before a closure identity, journal or Sale is written.
  Fiscal closes cannot use nonfiscal tender aliases or claim collection that
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
  direct Sale detail requests. An already-open internal Sale sheet also reacts
  to entitlement changes. These are read projections, never history updates.

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
or changed.

## Validation and limits

- Flutter focused regression set: **120 passed**, including real temporary Hive
  closure/audit recovery, entitlement missing/off/on, unauthorized Staff, exact
  GEL 1000 settlements, repeated close and wire snapshots, Manager expiry,
  synthetic sales UI, payment forms and Manager financial sync.
- Backend unit/HTTP set: **29 passed**. Includes rejected owner, Manager,
  Device, anonymous and readonly support requests; admitted Platform admin;
  direct service denial; server-owned Venue projection and retained audit data.
- Flutter analysis: **no issues**. Backend TypeScript check and Nest build pass.
- Disposable PostgreSQL: fresh complete migration deployment; ledger,
  entitlement and commercial suites pass. The final cross-runtime run also
  ingests six Dart-emitted synthetic legacy payloads. Full selected run:
  **105 passed, 2 failed, 0 skipped**. The two failures are existing Platform
  hostname resolver cases, reproduced on the unchanged integration base
  (**41 passed, the same 2 failed**). They are deferred, outside this fix.
- The broader existing `cloud_printer_runtime_sync_test.dart` has **20 fixture
  failures**, identical on the unchanged integration base: the fixture seeds
  `menu01-venue-a` and then attempts enrollment under another Venue. The tenant
  binding guard correctly refuses before runtime configuration executes. No
  printer implementation or tenant guard was weakened to make this test pass.
- Synthetic sales UI is rendered at 1024×768 with Georgian fonts for missing,
  disabled, enabled and revoked capability states. Screenshots and full logs
  are temporary proof files; no restaurant data is used.
- Windows binary/device/installer qualification, rollout and stable promotion
  are **not run**. Existing POS/Edge processes remain untouched. Review the
  15-minute disconnected-access policy and these results before any release.

Local evidence: `/tmp/vynic-entitlement-flutter-final.log`,
`/tmp/vynic-entitlement-backend-unit.log`,
`/tmp/vynic-accounting-proof/{tests.json,baseline-platform-tests.json,receipt.json}`,
`/tmp/vynic-accounting-baseline/cloud-printer.log`, and
`/tmp/vynic-accounting-ui/`.
