# Whole-system integration recovery

Generated captures, logs and machine receipts referenced below are local-only; see the [proof output policy](../README.md).

## Current outcome

The interrupted source-repair checklist is implemented. On 2026-10-21, final
Manager Android debug, macOS arm64 debug and unsigned arm64 iOS Simulator builds
passed, along with fresh Flutter analysis, 39 focused Flutter tests and the
47-case disposable PostgreSQL reporting/ledger fixture. The earlier full scoped
test totals below remain historical. The remaining native navigation, pagination
and offline checks subsequently passed after a supported fresh Computer Use
session recovered window binding and keyboard scrolling. The QA app is closed;
both fresh synthetic databases were stopped and removed. No user action is needed.

See the [final build/QA results](validation/final-20261021/README.md),
[successful native recovery](validation/final-20261021/native-recovery-1/README.md)
and artifact identities, hashes and locations (local: `validation/final-20261021/artifacts.json`).

See [support matrix](SUPPORT_MATRIX.md),
[Computer Use permission clarification](APPROVAL_CLARIFICATION.md), and the
[machine-readable results](validation/summary.json).

## Recovery checklist

| Item | Implemented result | Current proof |
| --- | --- | --- |
| Uncertain files/typechecks | Confirmed reservation test existed and menu-selection test was absent. Corrected inventory `observe<unknown>`, stock text `1.000` and counted-menu test payload typing. Preserved initial baselines. | Full backend typecheck, 30 reservation/advance tests, five new menu widgets |
| Reservation admission | Real whole-day blocking bookings now guard create, table/date edits and reconfirmation inside existing mutation serialization, before advance/audit effects. Same-ID retry and historical/activated/technical exclusions remain. | 30 isolated POS tests; concurrent create and reopen cases |
| Staff / delivery durability | Existing Staff mutations and queue intent commit atomically. Pending/claimed Edge and pending legacy changes protect Cloud identities/roles/PINs against older snapshots. Expense create is also atomic with its delivery intent. Legacy outbox persistence failure propagates. | Queue/rollback/Venue PostgreSQL cases, Staff/access regressions and unit tests |
| Inventory protections | Historical StockMovement prevents base-unit edits after old recipe components disappear. Sorted Venue-scoped locks protect first use. Rounded-zero recipes and malformed nested consumption reject explicitly without partial writes. | Real PostgreSQL lock barriers, history and consumption cases; inventory units |
| Menu / counts | Stable owner retry IDs, atomic Cloud count writes, chosen service fee, new selection IDs, visible mixed-category direct items, variant quantities and frozen ambiguous/historical count lines. | 7 owner, 5 new widget and 82 existing client regressions; counted-menu PostgreSQL |
| Finance | Shared expense echo identity, deletion eligibility/containment and calendar-month obligation planning. No advance-edit/refund decision invented. | Full 17-case stateful finance suite, seven Financials widget cases |
| Websites | Variant mapping, frozen booking values, guest count, confirmed-only local cleanup and mixed Menu sections retained and verified. | 27 WEB-03 and 26 guest-ownership PostgreSQL cases; backend/frontend tests and current builds |
| Notifications / claims | Stable paging with fixed server watermark, durable all-page checkpoint/replay and session/origin fences. Initial catch-up uses server time. Old successful/rejected claim responses cannot run under a new credential. | Four PostgreSQL notification cases and 37 Flutter cases |
| Platform guidance | Permanent restaurant identifier is distinguished from the existing one-use Manager linking control. | Nine guidance/linking tests; no access issuance performed |

The initial 23-module / 54-controller / 292-route inventory is retained in
`inventory/`. This phase adds one notification page route. These counts are
static inventory, not execution coverage for every route.

## Historical validation — 2026-10-18

| Check | Result |
| --- | --- |
| Backend unit suites | 304 passed across 20 suites |
| Disposable PostgreSQL suites | 212 distinct passed across 14 suites; no skipped case in the accepted selections |
| Flutter scoped regressions | 207 passed across 18 files |
| Web scoped regressions | 76 passed across 12 files, including 19 generic-site cases |
| Full backend TypeScript / Nest build | Passed |
| Full Flutter analysis after final menu changes | No issues |
| Platform/owner, Vankisi and generic-site TypeScript / production builds | Passed; existing chunk-size warnings only |
| Generic-site manifest | Generated successfully |
| New backend test lint | Three files, zero errors/warnings |
| Seven repaired backend source files lint versus working-copy baseline | Errors 236→227, warnings 13→11; no per-file increase. Existing lint debt is not claimed resolved |
| `git diff --check` | Passed |

The first database run exposed a missing Jest dependency stub and a new website
fixture attempting to mutate an immutable paid booking. Both test fixtures were
corrected; no payment trigger or business rule was weakened. A subsequent
SaaS run required its dedicated database-name guard; it then passed all ten
cases. Initial failed receipts are preserved beside accepted results. The
accepted PostgreSQL selections and exact files are in `validation/summary.json`.
Every root-owned test cluster was stopped and removed.

The 47-case separate native fixture overlaps the root reporting/ledger suites
and is **not added** to 212 as new independent coverage. Warning-render tests
from the earlier mistaken branding detour are not added to the Flutter count.

Domain evidence:

- [Menu/counts](validation/menu-counts/RECOVERY.md)
- [Finance/websites](RECOVERY_FINANCE_WEBSITES_2026-10-18.md)
- [Notifications/transport](validation/access-transport/NOTIFICATIONS.md)
- [Current native reporting](validation/native-reporting/README.md)

## Builds and native evidence

| Target | Exact boundary |
| --- | --- |
| Backend and three web clients | Current scoped builds passed; no service was restarted or deployed |
| POS macOS development | Build passed in an isolated prepared tree after POS admission changes; this does not prove Windows or hardware behavior |
| Manager Android debug | Final rebuild after retained-count/variant UI edits passed on 2026-10-21; not installed or launched |
| Manager macOS | Final arm64 debug build and local signature verification passed on 2026-10-21 using pinned packages and repaired temporary build preparation |
| Manager arm64 iOS Simulator | Unsigned debug compile passed on 2026-10-21 after a staging-only pinned Firebase relative-path correction. Existing `com.vanski.vynic` bundle identity retained; not installed or launched |
| Reporting QA macOS | Refreshed QA arm64 build/signature verification passed on 2026-10-21. Current production Dashboard rendered 372.00 GEL and a missing-day gap using fresh synthetic Nest/PG responses |

Open the 2026-10-21 Dashboard capture (local: `validation/final-20261021/screenshots/dashboard-online.png`).
The initial fresh app session issued eight recorded API GET requests, all 200.
After supported CUA session recovery, the same built app issued 26 recorded API
GET/200 requests, including the Financials next-page cursor. Native
Creator-report/History navigation, pagination and offline reload/provenance
checks passed; see the [native captures and receipt](validation/final-20261021/native-recovery-1/README.md).
Both fresh fixture runs passed the same overlapping 47 reporting/ledger cases;
these repeated cases are not added to historical totals as independent coverage.

The fresh runner stopped and removed only its own synthetic cluster; see its
receipt (local: `validation/final-20261021/runtime-validation/receipt.json`). No stale
QA/build process was present when this continuation began. After final checks,
only QA PID 43497 was terminated, guarded by its exact executable path;
cleanup proof (local: `validation/final-20261021/qa-cleanup.json`) and the subsequent app
inventory confirm closure. The later recovery fixture was also stopped/removed,
then its QA app was quit through CUA and confirmed absent. Normal Manager/POS
were initially absent and were never launched, closed or restarted. Existing
PostgreSQL PID 8148 remained present.

## Reviewable changes and remaining work

Owned changes (local: `validation/owned-changes.json`) and
scoped patch (local: `validation/owned-delta.patch`) compare 71 source/doc paths against
the pre-edit working copies under
`/tmp/vynic-whole-system-baseline-20261017/`. This avoids representing unrelated
uncommitted work as this task's edits. No `.env`, secret, migration source or
generated contract/model output was changed. Git status snapshots are retained.

Final build and cleanup work resumed under the user's explicit continuation.
Creator-report/History navigation, Financials cursor pagination and offline
reload/provenance checks are now complete in `ge.vynic.manager.wholesystemqa`.
A supported fresh CUA session recovered binding; keyboard Page Down navigation
worked when pointer scrolling reported `noWindowsAvailable`. No permission
denial or permission bypass occurred. No successful build was repeated for that
recovery. Its fresh fixture was removed before the offline check, then only the
QA app was quit through CUA. No normal Manager/POS app or real data was targeted.
No signature/plugin validation was disabled during the accepted builds.

Stable historical employee IDs, inventory transfer/allocation UI, historical
COGS/realized profit, full cashflow and generic SaaS booking/payment/account
flows remain product gaps, detailed in the support matrix. Advance-editing
policy and logo selection remain pending. The separately reported consumed
enrollment-code/revoked-Device issue is unchanged under the security exclusion.
Printer infrastructure remains deferred. No live business write, credential or
security-setting change, normal service restart, deployment, commit or push was
performed. These source repairs and isolated checks are not whole-product
production-readiness certification.
