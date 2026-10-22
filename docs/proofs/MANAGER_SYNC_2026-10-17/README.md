# Manager / backend sync repairs

Generated captures, logs and machine receipts referenced below are local-only; see the [proof output policy](../README.md).

The authorized sync defects are fixed in source and verified with synthetic
fixtures. No live restaurant data, historical receipts, permissions, credentials,
signing settings or application identities were changed. No deployment, restart of the normal app sessions, commit or push was performed.
A separate isolated QA app was launched as documented below. Branding remains pending the logo choice.

## Before and after

| Confirmed defect | Final behavior |
| --- | --- |
| The POS retried only while its pending flag was set. An idle POS stopped attesting its source, and a failed startup upload could remain unretired. | The existing full-snapshot path refreshes idle sources every two minutes; failures and pending work retry every thirty seconds. Disposal cancels startup, retry and refresh timers. |
| A successful upload cleared pending work that arrived after snapshot construction. The shared realtime flag could also change another request's mode. | An accepted full snapshot acknowledges only the captured local revision. Realtime mode is fixed per request; partial operational uploads cannot acknowledge full reporting work. Full requests coalesced behind a partial request remain pending. |
| Dashboard popular-product quantities came from the legacy summary endpoint despite an existing ledger product API. | The card uses `product-analytics` for the dashboard's business date and its `byQuantity` values, with the corresponding bound provenance. Existing Sale revenue predicates and immutable line snapshots remain authoritative. |
| Financials' related reads and later pages independently defaulted to the server's current business date. Close Day could move a page to another day. | The financial response identifies its business date. Summary, product/staff analytics, and every Sale page use one explicit range. Older responses can use the existing procurement business-date field; a missing reporting day/range is unavailable rather than guessed. |
| Later pages did not contribute their own freshness/error status; refresh races could append an old page. | Every loaded/failed page contributes read status. Range mismatches are rejected, duplicates are removed by Sale ID, and refresh/session generations fence late responses. A partial page cannot erase an earlier partial warning. |
| Memory retention could expose a previous protected dashboard or Financials response after 401/403, even though disk cache fallback was refused. | Access denials clear retained protected values. Transient errors can retain same-query data with its original timestamps and a visible failure. |
| Abandoned page/query failures could keep the global API-error signal set after a healthy refresh. | Refresh explicitly retires the exact abandoned status objects within the current scope. New responses, other queries and other sessions are preserved. Both cached and uncached failed-page recovery are tested. |
| JavaScript normalized impossible date keys, and non-integer page limits could reach database queries. | Query and freshness paths share exact date round-trip validation. Non-integer/non-finite limits return a bad-request response before row queries. Existing integer limit clamping is preserved. |

The shared sync worker, Manager read mapping/cache status, and backend financial
response/date validation changed. The ingestion schema, receipt persistence,
financial calculations and revenue predicates did not change. The approved
responsive structure is retained; a genuine later-page warning now appears in
Sale history, without repeating an identical summary warning.

## Limits at the phase-one checkpoint

The subsequent backend-first reporting and replay repairs are documented in
[phase two](../BACKEND_SHARED_REPORTING_2026-10-17/README.md). Phase-one file hashes
and patches are a frozen checkpoint, followed by the separate phase-two delta.

The original runtime inspection confirmed **partial displayed sales history**;
it did not establish which database row or missing upload caused that Venue's
warning. The reproduced defects above must not be presented as proof that every
warning in that running restaurant was caused by them.

- The open business day remains `PARTIAL` until the existing Close Day and
  acknowledged retained-Sale completeness boundary. An upload succeeding does
  not make an open financial period complete.
- Per-waiter attribution is deliberately unsupported by the existing summary
  read model. The ledger's closer identity is a different concept and is not
  substituted for a waiter. Staff attribution can still limit the dashboard.
- Legacy reports remain partial where their breakdown completeness is unproven.
  Missing historical receipts, uncovered dates, corrupt/absent metadata, stale
  POS sources, and failed/offline reads continue to warn.
- No totals, timestamps, missing history or permissions were manufactured to
  clear a warning. Fully known, current financial responses do clear it in the
  production-widget contract test.

## Verification

- **83 focused Flutter checks passed** across seven files: POS worker liveness,
  Sale ledger selection/ACKs, legacy Sale wire compatibility, read freshness,
  Financials presentation/pagination, the production Financials HTTP contract,
  and warning states. The final failed-page recovery change was separately
  rerun with the liveness test: **2 passed**, overlapping the 83.
- **41 real PostgreSQL/HTTP integration checks passed, zero skipped**, including
  the exact synthetic Sale rows exported by Dart. A 251-Sale upload remains
  partial across its two batches and becomes complete only after the final
  declaration. Pinned keyset pages cover all 251 rows without duplicates after
  a business-date change; another Venue sees none of them. A genuinely absent
  requested date stays partial/unknown. Existing primary, tenant, rollback,
  metadata and concurrent-generation checks pass.
- **16 backend unit checks passed** for provenance and revenue predicates.
- Flutter analysis: **no issues**. Backend production compilation: **passed**.
  Typed freshness lint passes. The shared legacy date utility retains exactly
  its **8 pre-existing lint errors**: same rule/message multiset as HEAD,
  with only line offsets changed. This is not a clean whole-backend lint claim.
- Current native development builds passed: **Manager macOS**, **Manager Android
  debug APK**, **unsigned arm64 iOS Simulator**, and the shared **POS macOS
  development build**. This is not Windows release or physical-device proof.
- Responsive actual-widget renders use explicitly synthetic loopback data.
  Current results and image inventory are in `validation/summary.json` and
  `screenshots/manifest.json`; [open the gallery](index.html).

The contract test exercises a complete response, rollover pinning, a partial
later page, cached data after a failed page request, access denial, successful
recovery, and an uncached failed-page request whose error retires on refresh.
Separate tests retain old/absent metadata as unknown, isolate caches by
query/origin/principal, and fence late logout/token/session responses. No live
endpoint credentials or protected local session data were read for testing.

## Reproduction and review

Run the Flutter files named in `validation/summary.json`. To reproduce the owned
database proof from `apps/backend/`:

```sh
python3 tool/prove_manager_sync.py --postgres-bin /path/to/postgresql/bin --output /tmp/manager-sync-proof/receipt.json --sale-wire /path/to/synthetic-dart-sale-wire.json
```

Generate that optional synthetic wire file by running
`legacy_sale_ledger_compatibility_test.dart` with `SALE_LEDGER_MIXED_OUTPUT` set.
Without `--sale-wire`, the optional retained-Dart ingestion case is skipped;
this task's final run supplied it and skipped nothing. The runner creates a new
loopback-only `disposable_…` database, applies migrations there, tests it, stops
the owned cluster and removes it. No migration source was changed or applied to
a restaurant database.

`validation/changed-files.json` lists the 24 scoped source/test/tool/state files
and their hashes. `validation/owned-delta.patch` isolates this task's changes
against captured task-start working files where prior uncommitted work existed;
it does not represent the repository's much larger inherited redesign diff.
Logs, build commands/results, the owned-cluster receipt, and synthetic fixtures
are in `validation/`.

## Runtime boundary and safe next step

The normal Manager/POS sessions were inspected and left running as their original
PIDs 26303 and 40211. A separate temporary QA bundle, with private temporary Hive
storage and a loopback-only network guard, ran the production `FinancialsScreen`
against the current NestJS services and a freshly migrated synthetic PostgreSQL
cluster. It displayed **372.00** from 31 genuine fixture Sale rows; all five
financial reads and a second-page cursor GET returned 200 for the same business
date. After only that owned fixture was stopped, the native UI retained **372.00**
and visibly showed the failed-refresh/data-limited warning. The QA app was then
closed; the owned cluster was stopped and removed. No live sync writes occurred.

The runtime suite passes **42 checks, zero skipped** (41 overlap the prior backend
suite; one is the held native fixture). The first fixture timed out during an
871-second computer-use launch; its failed receipt is preserved. A clean retry
completed successfully and was cleaned up. See `runtime/phase-one-completion.json`,
`runtime/owned-session-retry/native-reads.jsonl` and `runtime/retry-validation/`.

The verified synthetic native screenshot is
`runtime/screenshots/native-financials-online.png`; its Library ID is
`libfile_64d42fce9bc0819192453b7ba38eac30` (metadata read back, 800×600, 61,281
bytes; identity metadata applied locally). See `runtime/library-screenshot.json`.
This proves the isolated production-widget/backend runtime, not the normal
production login/startup, live restaurant synchronization or Windows behavior.

Expanded lint checks cover every changed backend production file and both changed
integration files. Production baseline/current errors are 0/0 (freshness), 114/114
(legacy dashboard), 169/169 (legacy Sale ledger), and 8/8 (legacy date utility).
The pagination test had two new unsafe-array-spread errors; they were fixed and
its count returned to 8/8. The freshness integration file remains 0/0. An apparent
message difference in the legacy ledger was only reversed union-member order on
unchanged code. No new changed-code lint errors remain. Details are in the
`runtime/validation/lint-*` comparisons.

No schema migration or historical repair is required by these code changes.
When rollout is authorized separately, use the updated backend and clients and
let the POS's ordinary full uploads/ACKs converge. Investigate any remaining
missing history against retained POS records and reconciliation results before
proposing a separately approved repair. Do not close a business day merely to
hide the warning. Advance-editing policy and deferred printer infrastructure
remain out of scope; old printer failure totals are not current results.
