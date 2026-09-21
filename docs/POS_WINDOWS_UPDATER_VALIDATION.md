# Windows POS updater validation

The original validation below predates bounded binary retention. Current layout-2
cleanup/crash evidence is in [POS_BINARY_RETENTION_VALIDATION.md](POS_BINARY_RETENTION_VALIDATION.md).

Executed on macOS against disposable state. No production release, credential,
database, Windows machine or POS installation was changed.

## Passed

- **25 Go tests** plus two child-process helpers, `go test -race ./...` in
  `apps/edge`. Includes all existing foundation/Phase 2A tests and the new
  updater/offline-signer tests. Test subcases cover signature/hash/product/OS/arch/
  schema/version/expiry/key rejection, lost network and retry, progress, staged
  restart, blocked consent, repeated/changed request, updater ownership,
  corrupt/incompatible updater state, traversal/Windows paths, successful health,
  failed candidate rollback, wrong data directory rollback and interrupted
  activation recovery. Actual child processes perform authenticated startup health.
- **170 Flutter tests across 16 files**, including 10 updater readiness/UI cases.
  The 169-case affected suite passed, then the additional restart-marker case and
  all 10 updater cases passed together. Existing Order creation, item transfer,
  cancellation, backup, money, table identity, Hive migration and Phase 2A
  coordinator tests remain passing.
- Focused Dart analysis of updater code, changed repositories/transactions,
  startup, Settings, coordination hooks, proof CLI and tests: **no issues**.
- Go vet and Windows-target vet; `GOOS=windows GOARCH=amd64 CGO_ENABLED=0`
  compilation produces a **PE32+ x86-64 Windows Edge executable**. No Windows
  binary was executed on macOS.
- Offline signing tool -> consumer signature verification round trip with a
  generated temporary development key. No signing secret persisted in the repo.
- Three separate Dart/Hive OS processes preserve the exact same open Order,
  line UUID, occupied Table, totals and pending Cloud outbox across flush/abrupt
  exit, simulated candidate start and simulated rollback start. Captured evidence:
  `POS_WINDOWS_UPDATER_PROOF.json`.
- `go mod tidy -diff`, Python proof-script syntax, `git diff --check`.

The real payment `collect()` future is tested as an active blocker until
cancellation; it is not replaced by a fake payment implementation. During test
construction, rendering the existing standalone payment-choice tile with the
Flutter test font exposed an existing fixed-height tile overflow. Payment-layout
changes are deferred from this updater task; the readiness test checks the real
pending payment operation without asserting that unrelated layout.

## Reproduce

```sh
cd apps/edge
go test -race ./...
go vet ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/vynic-edge.exe ./cmd/edge
```

```sh
cd apps/operations
flutter test test/unit/pos_update_readiness_test.dart test/widget/pos_update_ui_test.dart
```

From repository root:

```sh
python3 apps/edge/tool/prove-pos-updater.py --dart /path/to/dart
```

Logs used during implementation are in `/tmp/vynic-updater-go-final.log`,
`/tmp/vynic-updater-flutter-final.log`, `/tmp/vynic-updater-readiness-final.log`,
`/tmp/vynic-updater-analysis.log` and `/tmp/vynic-updater-analysis-final.log`.
They are temporary local logs, not required runtime files.

## Not established by these checks

Actual Windows process termination/restart, DLL locks, runtime/plugin packaging,
ACLs, interactive account/session behavior, UAC/SmartScreen/antivirus/AuthentiCode,
power-loss/disk-full behavior and a real signed new/previous POS pair against the
installed support-directory layout remain Windows qualification work. The signed
channel, production public trust keys and initial host provisioning are not set
up by this task. No automatic install, production Edge authority, Manager update,
Edge self-update, push or deployment was performed.
