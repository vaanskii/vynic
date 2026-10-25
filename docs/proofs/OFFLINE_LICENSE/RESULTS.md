# Licensing validation and integration handoff

Base: `bf7bd64793c7cdca261e5198030b5f37791f87aa`.
Branch: `codex/offline-subscription-lease` (uncommitted by repository policy).
Checkout: `/Users/vaanskii/Documents/Codex/2026-10-25/task/vynic-licensing`.
No production service/database, operational POS installation, release feed,
Cloudflare resource or mail configuration was changed.

## Final applicable checks

- `restart-applicable.log`: **250 passed, zero failed** against the final restart
  revision. Includes the earlier signed expiry/nonce/malformed/binding coverage,
  accounting (1000/100/900), immutable existing-bill settlement, no reopened/new
  items, nonfiscal separation, backups, transfer/recovery, sync and localized UI.
  New coverage restores same-boot sessions without moving the original deadline;
  counts suspended/closed time; preserves trial and paid cutoffs; rejects reboot,
  rollback, decreasing elapsed time, malformed/missing/locked anchors, tampering,
  changed device/tenant/install/pin; preserves protected denials despite restored
  app data; renews only on a fresh online response; tests in-flight vault writes
  and startup restoration versus revocation. Missing clock cannot erase a known
  revocation. No live data or production credentials are used.
- `restart-focused.log`: **69 passed** before the final additional missing-clock
  revocation test; all 70 focused cases are included in the final 250 aggregate.
- `restart-analysis.log`: **no issues** in revised source and tests.
- `restart-native-vault.log`: exact macOS helper compiles and passes across
  separate processes: write, same boot/elapsed continuity, size bound, replacing
  positive state with received revocation, persistence of that denial, cleanup.
  The random Keychain fixture was deleted. Reproduce with
  `python3 apps/operations/tool/test_license_native_continuity.py` on macOS.
- `restart-native-build.log`: final synthetic macOS preview builds successfully.
- `restart-backend-focused.log`: **7 passed** on unchanged endpoint source.
- `backend-focused.log`: **7 passed**, including real loopback HTTP authentication,
  ignored client tenant/device/installation fields and verifiable Ed25519 output.
- `backend-build.log`: Nest build passes. TypeScript `tsc --noEmit` passes.
- `macos-build.log`: synthetic preview/native channel compiles successfully.
  Only existing dependency deprecation warnings were emitted.
- `native-preview.log`: `LICENSE_PREVIEW_NATIVE_CLOCK_OK`; native UI inspected
  with supported computer-use tooling. Temporary unique preview identity was
  stopped afterwards. The Dart VM service URL was removed from retained logs.
- `expired-ka-{1024,800,480}.png`: actual Flutter surface with POS theme and
  Georgian font, reviewed for text wrapping and visible actions. Widget tests
  cover workspace/draft retention, Back, repeated purchase clicks and no automatic
  browser launch. No restaurant data appears in these captures.
- `git diff --check` passes.

## Aggregate diagnostics and baseline comparison

These results are **not** a claim that the entire repository is green.

- Backend final aggregate: **998 passed, 1 failed, 3 skipped** (84 suites).
  The remaining `local-docker-guard.spec.ts` deletion-matrix completeness failure
  also fails on untouched bf7bd647: **15 passed, same 1 failed** in that suite.
  See `backend-final-aggregate.log` and `backend-baseline-failure.log`.
  Database-opt-in integration suites were not enabled; persistence for the new
  endpoint HTTP fixture is stubbed. No PostgreSQL deployment proof is claimed.
- Whole-tree Flutter diagnostic run: **2,883 passed, 40 failed, 18 skipped**.
  This broad run preceded the last narrow action-scope review. The pre-restart-revision
  core aggregate (all unit tests plus selected relevant UI suites) was
  **2,091 passed, 33 failed, 3 skipped**; the final applicable aggregate above
  passed all 226 after settlement-scope narrowing. The restart revision now
  passes all 250 applicable cases. The whole-tree diagnostic suite was not rerun
  after the restart revision; its existing failures remain release caveats.
- The final core failures are 20 `cloud_printer_runtime_sync`, 8
  `printer_route_catalog`, 1 `printer_agent_client`, 1 `operational_proof_wire`,
  and 3 Manager navigation cases. **32 exact cases reproduce on the unchanged
  baseline**. The extra Manager case appears only under aggregate concurrency.
  A direct isolated run of `mgr03_operation_navigation_test.dart` on candidate
  and baseline gives the identical **11 passed / 2 failed**, and that extra case
  passes in both. The whole-tree run also has two aggregate-only Manager cases
  that pass in the isolated comparison. Do not describe these intermittent cases
  as fixed or silently accept them for release.
- `flutter-baseline-failures.log`: unchanged-baseline selected suites,
  **118 passed / 38 failed**. These also include unrelated Inventory, Admin,
  print-configuration and Close Day presentation failures in the whole-tree run.
- `flutter-final-manager-isolated.log` and
  `flutter-baseline-manager-isolated.log` preserve the exact direct comparison.

Earlier focused/applicable logs are retained as historical evidence. Use the
`restart-*` logs above for the latest revision, not the old process-restart policy.

## Integration-sensitive files

Coordinate these with the installer/Edge/printer task; do not overwrite its
changes wholesale:

- `apps/operations/windows/runner/flutter_window.{cpp,h}`: adds a separate
  `ge.vynic/license` channel for boot/elapsed continuity, credential-vault access
  and explicit pricing launch. Windows now also links `advapi32.lib` in
  `apps/operations/windows/runner/CMakeLists.txt` for Credential Manager.
- `apps/operations/macos/Runner/MainFlutterWindow.swift`: same isolated channel.
- `apps/operations/lib/startup_pos.dart`: starts licensing and installs its UI host.
- `apps/operations/lib/core/services/pos/update/update_readiness.dart`: adds
  licensing admission without changing disabled/Manager scheduling behavior.
- `apps/operations/lib/core/services/edge/runtime_config_sync.dart`: forwards
  authentication denial to the separate license while retaining nonfiscal logic.

Other changes are the new backend controller/module registration and tests,
`core/services/licensing/`, operational creation/transfer/settlement boundaries,
device-only backup classification, one localization entry, regression tests,
synthetic preview, native continuity fixture and documentation. No updater manifest, installer, printer
protocol, mail sender, release-upload or Cloudflare file is changed.

## Remaining gates

No signing credentials were created for production. A separately approved
Ed25519 signer (`VYNIC_LICENSE_SIGNING_KEY`) and matching Flutter public pin
(`VYNIC_LICENSE_PUBLIC_KEY`) are mandatory before a usable connected beta build.
Missing configuration fails closed. Existing file-provisioned/legacy identities
need a matching server enrollment before licensing can succeed. A first
installation must verify online. Ordinary **same-boot app restart now restores
the original signed lease** from OS-protected storage, without extending its
deadline. Reboot, uncertain continuity, rollback, changed bindings/pin, or an
unavailable/malformed anchor still require online verification. Received negative
decisions remain restrictions until a fresh authenticated positive response.

Windows compilation/device sleep/reboot, the internal boot-GUID API on each
supported Windows build, stable macOS signing/Keychain update access, clean
installer/enrollment, real HTTPS
backend/disposable PostgreSQL deployment and provider workflows still need
qualification. No Windows binary/device proof, production rollout, printer proof
or instant offline remote revocation is claimed. The old operational POS remains
untouched. Same-user arbitrary code/OS-vault rollback/full VM snapshots are
outside the local-software threat boundary. If both persistence stores fail,
current-process denial is retained, but crash durability cannot be guaranteed.
These are pending rollout gates/explicit limitations, not permission denials; there is no
remaining denied or uncertain tool action. Temporary test launches are stopped.
