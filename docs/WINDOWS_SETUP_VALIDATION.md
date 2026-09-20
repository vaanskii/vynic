# Windows setup validation

Implementation validation passed on macOS. This is not a Windows release
qualification or a production deployment. Structured evidence:
[`WINDOWS_SETUP_PROOF.json`](WINDOWS_SETUP_PROOF.json).

## Automated evidence

- Full `apps/edge` Go race suite: **44 top-level tests passed**, **117 passing test
  records including subtests**. Existing updater, foundation, migration, pairing,
  replay and SHADOW coordination tests remain passing.
- Native and Windows-target `go vet ./...`: passed.
- Windows amd64/CGO-disabled Edge and GUI setup cross-builds: passed.
- `go mod tidy -diff`: no dependency/version changes.
- Python build utility compilation: passed. Its built PE inspection verified
  Windows amd64, GUI subsystem, resource relocation and the exact embedded
  `asInvoker` manifest. The fixture executable is 17,583,616 bytes, unsigned and
  configured with an intentionally unusable `.invalid` endpoint/public fixture
  key. It contains no full POS/Edge release.
- `git diff --check`: passed before commits.

The initial sandbox disallowed local test listeners; the HTTPS/race suite was run
with the approved local-network/process capability. Python bytecode cache was
redirected to a temporary writable directory. These are test-environment
constraints, not product TLS/security bypasses.

## Installer proof cases

`internal/setup/setup_test.go` uses trusted local HTTPS fixtures, real local
SQLite/WAL state and synthetic Windows ZIP contents. Its native host adapter is
simulated; downloaded fake `.exe` files are **never executed** on macOS.

| Case | Observed assertion |
|---|---|
| Fresh install | Signed Edge/POS bundles produce complete layout/config, fresh random host token and unbound persistent Edge identity/certificate. |
| Separate installations | Tokens differ; no reused local credentials. |
| Repair | Token and installation identity persist; missing config is restored from receipt. |
| Changed authority/version | Wrong product/channel/platform/schema/purpose, signatures and expiry fail; Repair cannot select a new Edge version. |
| Bad/network-interrupted artifact | No binary activation; retry reuses receipt/credentials and downloads safely. |
| Unsafe/incomplete ZIP | Traversal/Windows unsafe names and incomplete Flutter runtime are refused. |
| TLS/metadata limits | HTTPS-to-HTTP redirects and oversized metadata fail. |
| Failed integration during repair | Previous Edge/POS/setup binaries restored; retained data stays untouched. |
| Crash during binary swap | A real child exits after journaled replacement; a new installer instance recovers and repairs. |
| Offline interrupted repair | Old binary restored before the failing network request; maintenance marker released. |
| Newer updater-selected POS | Repair restores active version while preserving release high-water and updater selection. |
| Missing/corrupt state | Missing DB, identity row, updater decision row or receipt fail closed; no fresh state is substituted. |
| Uninstall | Application integration/releases removed; data, config, identity and updater history retained; repair reinstalls using retained state. |
| In-flight updater decision | Uninstall refuses INSTALLING/RESTARTING state. |
| Concurrent setup / linked root | A second setup owner and a symlink root are rejected. |

`cmd/edge/host_test.go` starts and gracefully restarts the local updater host with
an **unbound** real foundation identity. It verifies authenticated local status
and unchanged identity/Venue state. No LAN server or restaurant authority is
created.

`cmd/sign-bootstrap/main_test.go` signs metadata with a temporary generated
Ed25519 private key, verifies through the production trust policy and checks the
published artifact digest. The signed POS envelope uses the existing POS domain.
`cmd/setup/main_test.go` refuses absent build distribution and private-key/unknown
fields in supplied trust configuration.

No Flutter/Hive model, business rule, enrollment UI, backend/contract migration,
Manager or venue-web source changed. The existing POS updater's genuine
three-process Hive recovery evidence remains in `POS_WINDOWS_UPDATER_PROOF.json`;
this installer proof does not claim to execute Windows Flutter on macOS.

## Still required before distribution

Follow the full native matrix in [`WINDOWS_SETUP.md`](WINDOWS_SETUP.md). At minimum:
standard-user/UAC behavior, protected ACLs and foreign-user access, actual WinForms
UI and hardened PowerShell policy, logon/reboot/crash supervision, shortcuts and
Programs & Features, file locks and locked setup recovery, disk-full/power-loss,
firewall behavior, real signed Flutter/Edge runtime launch and health, support-path
continuity, Enrollment Code, open-order recovery, and real repair/uninstall.

Provision production HTTPS feeds, immutable repair artifacts, overlapping public
keys, offline/CI release signing, Authenticode/timestamps and AV/SmartScreen
qualification. No production private key, feed or endpoint is supplied by this
implementation. No Edge self-update or authority rollout was enabled.
