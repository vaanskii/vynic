# Current native reporting qualification — 2026-10-18

This page retains the 2026-10-18 evidence. The
[2026-10-21 continuation](../final-20261021/README.md) supersedes the process and
build state below: all three final Manager builds passed, the refreshed QA
Dashboard and 47 fixture cases passed, and a supported fresh CUA session
[completed native navigation, pagination and offline checks](../final-20261021/native-recovery-1/README.md).
Only the QA app and owned synthetic databases were cleaned up. No user action
is needed for this requested scope.

Status: backend fixture and native Dashboard verified; remaining native interactions blocked by Computer Use transport timeouts. Native macOS debug build and staged QA analysis passed. The fresh PostgreSQL runner completed with PASS and confirms its cluster was stopped and removed.

This is a separate synthetic QA executable, `Vynic Whole System QA`, bundle `ge.vynic.manager.wholesystemqa`, built in `/tmp/vynic-whole-system-native-qa-20261018/apps/operations`. Production app identities are unchanged; no normal Manager/POS launch, quit or restart was issued. The QA entry point initializes fresh private Hive storage, accepts only the exact owned loopback fixture origin, obtains fixture-generated synthetic authentication from a local bootstrap, and exposes current production Dashboard/Financials plus unchanged Creator-report/History widgets through staging-only wrapper entry points. It does not run production login, notification registration or POS startup. `source-snapshot-sha256.json` records the copied production Dart sources.

The fixture uses real Nest controllers/services and a fresh disposable PostgreSQL database. Its app-facing proxy rejects every method except GET. Synthetic POS ingress prepares 31 Sales of 12.00 GEL, 372.00 GEL total, with distinct `QA creator` and `QA closer` values. Runtime assertions verify both attributions. A historical date remains indexed after its synthetic summary is removed; authenticated `/mobile/sales-daily` must return `available:false,totalRevenue:null`. This deliberately exercises a legitimate partial-data state.

No real Venue data, credentials, PIN, payment, order or printing operation is used. Existing services are neither stopped nor restarted. The runner is responsible for stopping and removing only its newly created PostgreSQL cluster after the QA hold is released.

This qualification covers production report widgets behind an isolated startup shim. It does not qualify normal login/full production startup, physical devices, Windows, live POS/cloud delivery or live production data.

## Verified evidence

- `screenshots/dashboard-online.png`: app-generated native 800×600 screenshot, visually inspected. Current Dashboard displays 372.00 GEL with a legitimate limited-data banner and a missing prior-day chart gap.
- `native-reads.jsonl`: eight actual app GET requests, all HTTP 200: entitlements, dashboard, counted menus, sales daily, reservations, creator staff performance, product analytics and financials. No non-GET request is present.
- `runtime-validation/receipt.json`: fresh synthetic cluster init/start/create/migrate/integration/stop all exit 0; cluster stopped and removed.
- `runtime-validation/manager-sync-postgres-tests.json`: 47 tests passed, 0 failed, 0 skipped, including optional runtime creator/closer/unavailable-day assertions. This includes existing MGR04/ledger regressions and must not be added to overlapping root totals as independent new cases.
- `native-build.log`: QA macOS debug build passed. `qa-analyze.log`: QA entry point analysis passed.

## Remaining limit and process state

The initial Computer Use `getApp` on the exact QA bundle path timed out after 737 seconds despite a requested 45-second limit. The launch did execute: process PID 69979, CUA app inventory and the native Dashboard capture confirm it. Binding the already-running QA identity `ge.vynic.manager.wholesystemqa` then also timed out after 7 seconds. No further UI retry or launch occurred. Creator-report/History UI navigation, Financials cursor pagination and the offline reload transition remain unverified in this current native executable. Their backend fixture assertions passed; that does not substitute for UI qualification.

After the user's pause on further approval-dependent actions, the existing fixture hold was released by creating its `STOP` marker without escalation. The already-authorized runner then executed its planned teardown and returned PASS. The uniquely identified QA app was left running at the last verified observation because its CUA binding was unavailable and further approval-dependent actions were paused. No normal Manager/POS launch, quit or restart was issued. Existing normal POS PID 40211 was still running at the last process observation; normal Manager was independently absent.
