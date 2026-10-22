# Final Manager build and isolated QA qualification — 2026-10-21

All three requested Manager development builds and the remaining isolated native
interactions passed. Initial Computer Use binding failures were resolved using
a fresh supported session; pointer scrolling was replaced with supported
keyboard navigation. See the [native recovery evidence](native-recovery-1/README.md).
The QA app is closed and both owned disposable PostgreSQL clusters were stopped
and removed. No user action is needed. This is local source/build/QA evidence,
not release, device, deployment or whole-product readiness certification.

Checkout: `e99d2ca36168b0d85f51b7812eb1dde42464846c`. Existing uncommitted work was
preserved. No production source was edited in this continuation. Earlier totals
of 304 backend unit, 212 PostgreSQL, 207 Flutter and 76 web tests are historical;
they were not rerun in full today.

## Fresh results

| Check | Result | Proof |
| --- | --- | --- |
| Manager Android debug APK, final retained-count/variant source | PASS; Gradle exit 0, existing future Kotlin compatibility warnings | `manager-android-build.log` |
| Manager macOS arm64 debug | PASS; Xcode exit 0; local deep/strict signature verification exit 0 | `manager-macos-build.log`, `artifacts.json` |
| Manager unsigned arm64 iOS Simulator debug | PASS; Xcode exit 0, `CODE_SIGNING_ALLOWED=NO`; not installed or launched | `manager-ios-simulator-build.log`, `artifacts.json` |
| Refreshed separate QA macOS arm64 debug | PASS; Xcode exit 0; local deep/strict signature verification exit 0 | `qa-macos-build.log`, `artifacts.json` |
| Full checkout Flutter analysis | PASS; no issues | `flutter-analysis.log` |
| Six focused Flutter regression files | 39 passed, 0 failed, 0 skipped | `flutter-targeted-tests.jsonl`, `flutter-targeted-summary.json` |
| Disposable PostgreSQL reporting/ledger fixture | 47 passed across 2 suites, 0 failed, 0 skipped | `runtime-validation/manager-sync-postgres-tests.json`, `runtime-validation/receipt.json` |
| Current QA Dashboard | PASS; visually inspected 372.00 GEL and a missing-history gap | `screenshots/dashboard-online.png`, `ready.json`, `native-reads.jsonl` |
| Native Creator-report/History navigation | PASS after supported session recovery; creator attribution and unavailable-day warning visually verified | `native-recovery-1/native-interaction-receipt.json` |
| Native Financials cursor pagination | PASS; real cursor GET/200, 31st sale appended, next-page button removed | `native-recovery-1/native-reads.jsonl`, recovery screenshots |
| Native offline reload/cache transition | PASS; retained 372.00 GEL, failed-refresh warning and expanded cached POS provenance after fixture removal | recovery offline screenshots |
| Owned fixture cleanup | PASS; both fresh clusters stopped and removed | `runtime-validation/receipt.json`, `native-recovery-1/runtime-validation/receipt.json` |
| Close only the QA app | PASS; initial verified-PID cleanup and later successful CUA quit; QA absent afterward | `qa-cleanup.json`, `native-recovery-1/native-interaction-receipt.json` |
| Final diff/status checks | See `final-checks.json` and `git-status-after.txt` | Recorded after proof updates |

The 39 Flutter cases cover `manager_shared_reporting_test.dart`,
`manager_financial_sync_test.dart`, `manager_financial_ledger_test.dart`,
`manager_menu_selection_test.dart`, `mgr04_data_status_test.dart` and
`edge_transport_client_test.dart`. These and the 47 fixture cases overlap earlier
coverage and are not added to historical totals as independent new tests.

## Source and build boundaries

The prepared Manager tree is
`/private/tmp/vynic-whole-system-build-20261018/manager/apps/operations`.
`stage-comparison-before.json` verifies the current production Dart/assets and
lockfile. Its only Dart difference is the intentional `main.dart` export wrapper;
the manifest intentionally excludes the product preparation tool's bundled
`data/menu.json` asset. Tests/tools absent from the product stage are not source
differences in the compiled application.

The older QA snapshot differed in three production files: `edge_transport_client.dart`,
`mobile_calculator_screen.dart` and `mobile_menu_pin_sheet.dart`. Only these were
copied into the existing isolated QA tree before rebuilding. Current production
Dart hashes are in `source-snapshot-sha256.json`; the initial comparison is in
`qa-source-comparison.json`. Existing staging-only wrappers expose the actual
production Dashboard, Financials, Creator-report and History widgets.

Apple builds used existing `Package.resolved` graphs and prepared `SourcePackages`
caches with `-disableAutomaticPackageResolution`,
`-onlyUsePackageVersionsFromResolvedFile` and `-skipPackageUpdates`. Package plugin,
macro and signature validation were not disabled. Initial failures and their
logs are retained:

- `manager-macos-invocation-error.log`: corrected an Xcode cache option spelling.
- `manager-macos-missing-filelists.log`: initialized missing empty temporary
  Flutter input/output file lists exactly as Flutter's own `build_macos.dart`
  does; Flutter Assemble then populated them.
- `manager-macos-stale-pods.log`, `manager-macos-pods.log`: the empty macOS Podfile
  had stale support/checksum files. `pod install` regenerated only staging
  integration, installing zero dependencies (`manager-macos-pods-repaired.log`).
- `qa-macos-stale-native-assets.log`: stale `/tmp` versus `/private/tmp` output
  paths left an incomplete native-assets framework. Fresh Xcode output in
  `build/macos-final-20261021` rebuilt it and passed normal signing checks.
- `manager-ios-missing-package-path.log`: the temporary Firebase Messaging iOS
  package pointed to `../firebase_core`, while the prepared dependency was
  `../firebase_core-4.10.0`. The staging-only relative-path correction matches
  the already-prepared macOS package and changes no version. Exact diff:
  `ios-staging-package-path.patch`. The global pub cache was not edited.

`artifacts.json` records exact output locations, hashes, architectures and
identities. All three compile the Manager entrypoint. macOS is
`ge.vynic.manager`; the Android manifest and iOS bundle retain the existing
`com.vanski.vynic` identity. These legacy mobile identities were observed, not
changed under this build/signing-configuration scope. Android is labeled
`Vynic Manager`. The unsigned iOS compile does not pass signed-bundle verification
and is not an installable signed release. No device installation or release
identity qualification is claimed.

## Initial native blocker, later recovery and isolation

Target:
`/private/tmp/vynic-whole-system-native-qa-20261018/apps/operations/build/macos-final-20261021/Build/Products/Debug/Vynic Whole System QA.app`,
bundle `ge.vynic.manager.wholesystemqa`.

`cua.getApp` by full path returned `Computer Use server error -10005:
timeoutReached` after about 7 seconds. Launch nevertheless executed: process PID
43497, CUA app inventory, the app-generated Dashboard capture and eight GET/200
requests confirm it. After checking that uncertain outcome, binding by the exact
running bundle ID also returned the same transport timeout after about 6 seconds.
No permission denial was reported in that initial run. A later explicit recovery
request led to a fresh CUA session, successful exact-path binding and actual
native navigation, pagination and offline checks. Details and captures are in
`native-recovery-1/`; no successful build was repeated.

The fresh fixture had 31 synthetic sales of 12.00 GEL, distinct `QA creator` and
`QA closer` attribution, and a deliberately unavailable historical day. It used a
new owned PostgreSQL cluster on loopback and an app-facing proxy accepting only
GET. The app used private temporary Hive storage and fixture-generated
authentication. The Dashboard screenshot was generated by the existing QA
RepaintBoundary timer, then copied from the separate QA container. No real
restaurant data or credentials were used.

The owned hold was released via its `STOP` marker. The runner completed its
planned assertions and teardown. With CUA window control unavailable, only the
verified QA process was terminated; a fresh command comparison guarded against
PID reuse. Existing PostgreSQL PID 8148 remained unchanged. Normal POS/Manager
apps were absent at initial observation; none was launched, closed or restarted.

No deployment, push, commit, credential/signing-setting change, live business
write or print action occurred. Printers remain deferred. The requested native
interaction checks are complete and no user action is needed.

Full backend unit, full scoped PostgreSQL/Flutter/web suites, signed mobile
release packaging, Windows and physical-device/printer checks were not rerun in
this continuation. Existing mobile package identities are a deferred release
qualification observation, not a blocker to the requested local debug compiles.
