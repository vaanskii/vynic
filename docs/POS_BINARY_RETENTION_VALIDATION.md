# Windows POS bounded binary retention — validation

Validated on macOS against disposable state, synthetic Windows bundles and real
simulated POS child processes. This is implementation evidence, **not native
Windows qualification or deployment**. Structured results and the rerun Hive proof
are in [POS_BINARY_RETENTION_PROOF.json](POS_BINARY_RETENTION_PROOF.json).

## Automated results

- Full Edge `go test -race -json ./...`: **58 top-level tests passed**, **146
  passing test records including subtests**. No failures or race reports.
- Native `go vet ./...` and Windows amd64 `go vet ./...`: passed.
- Windows amd64/CGO-disabled Edge and GUI VynicSetup cross-builds: passed.
  Setup PE inspection verifies GUI subsystem and embedded `asInvoker`; the
  17,627,136-byte fixture is unsigned and uses an unusable example endpoint and
  public fixture key. It embeds no POS/Edge payload.
- `go mod tidy -diff`: no dependency changes. Python build/proof tools compile.
- Existing real Hive proof rerun: three independent Dart processes reopen the
  same durable open Order/line UUIDs, occupied Table, totals and pending Cloud
  outbox after abrupt exit, simulated candidate start and rollback start.
- `git diff --check`: passed. No Flutter, Manager, business-authority, backend,
  generated contracts, custom venue website or BOG files changed by this task.

## Retention and recovery assertions

| Case | Assertion |
|---|---|
| Background candidate | Signed/hash-verified ZIP and extracted tree stay in `staging`; no execution. |
| Later + restart / ordinary launch / repair | Candidate remains READY and available; no automatic installation. |
| Repeated successful updates | Only the selected `current` release remains after each update; no version history, rollback, ZIP or partials. |
| Stabilization | Rollback retained and POS input held until repeated authenticated health and process checks pass. |
| Crash after initial health | Candidate fails probation, is removed, previous binary returns to current and restarts. |
| Process alive, health stops | Missing continued Hive-ready heartbeat causes rollback. |
| Interrupted activation | Real helper process exits at prepared, old-moved, candidate-moved and starting checkpoints; reopened SQLite recovers previous current. |
| Interrupted rollback | Crashes after candidate deletion and after rollback-to-current rename recover the previous release. |
| Stable commit / partial deletion crash | Only cleanup resumes; no attempted rollback or unexpected POS launch. |
| Cleanup refusal | Symlink/junction traversal refused, diagnostic/pending cleanup retained; retry after restart finishes safely. |
| Legacy version layout | Selected release moves to current; deferred ZIP stays; historical versions pruned only after stabilization. Explicit update migrates and activates safely. |
| Repair repetition | One original fallback retained through repeated repair before Open; setup ZIP/extracted scratch does not accumulate. |
| Interrupted setup POS swap | Journal restores the old current before a failing offline repair request. |
| Incompatible Edge baseline | Signed missing/unsupported `posBinaryLayout` rejected before changing a legacy layout. |
| Uninstall / reinstallation | All POS binary slots removed; retained state preserved; deleted staging is not advertised after reinstall. |
| Protected state | Sentinel Hive, SQLite, credential, journal, config and log files unchanged; deletion outside binary slots/data overlap rejected. |
| Trust and readiness regression | Existing signature/hash/platform/schema/expiry/network, corruption, exact process, blocked consent, idempotency and wrong-data-directory tests pass. |

The production interval is 30 seconds after initial health, with a 10-second
maximum heartbeat gap and a 90-second initial health deadline. Process fixtures
use shortened internal intervals to exercise the same state machine. Real Hive
proof and Go binary/process simulation are separate tests; fake Windows artifacts
are never executed on macOS.

## Reproduce

```sh
cd apps/edge
go test -race ./...
go vet ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go vet ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/VynicEdge.exe ./cmd/edge
go mod tidy -diff
```

From repository root:

```sh
python3 apps/edge/tool/prove-pos-updater.py --dart /path/to/dart
python3 apps/edge/tool/build-setup.py \
  --distribution /external/public-distribution.json --out /tmp/VynicSetup.exe
```

Local-network/process permission was needed for Go HTTPS/process fixtures. The
Dart launcher needed writable SDK-cache access. Neither changes product TLS or
credential policy. Temporary execution logs: `/tmp/vynic-retention-tests.jsonl`
and `/tmp/vynic-retention-hive-proof.json`.

## Native Windows work still required

Qualify exact process termination/restart; NTFS same-volume directory moves and
locked EXE/DLL behavior; ACLs/reparse rejection; disk-full/power-loss boundaries;
antivirus quarantine/deletion retry; complete Flutter DLL/plugin/assets layout;
real Hive recovery and heartbeat probation; shortcuts/logon and repair/uninstall;
Authenticode/timestamp/SmartScreen. Confirm healthy-current startup after a reboot
with partially deleted rollback. Production signing/feed publication is separate.

Existing Edge installations must not receive a falsely relabeled layout-2
capability. Setup repair pins the exact Edge baseline. Moving an incompatible
installed Edge build to this implementation still needs controlled Edge
replacement; automatic Edge self-update remains unimplemented.
