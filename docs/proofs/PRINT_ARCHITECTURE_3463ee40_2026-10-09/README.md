# Printer architecture refinement evidence

Status: **NOT_DONE**. Production integration, storage/retention and physical
qualification remain open. See `../../POS_PRINTER_ARCHITECTURE_REPORT_2026-10-09.md`
and `../../VYNIC_PRINT_ARCHITECTURE.md`. No other milestone, production activation,
commit or push occurred.

- `evidence.json`: machine-readable status, 32 software cases and 16 separately
  NOT_RUN physical cases. Software component success is explicitly distinguished
  from missing normal Flutter/service integration.
- `final-source-manifest.json`: SHA-256 for 173 Go/module/SQL/fixture inputs.
- `all-printer-regressions.jsonl`: full ten-package regression run.
- `final-affected-tests.jsonl`: the two affected packages after mixed-scope catalog
  projection. `final-local-tests.jsonl`: LOCAL alias exclusion and process recovery
  after the final lock fix. Combined, deduplicated: 519 pass records, five skips.
- `final-race-tests.jsonl`, `final-local-race.jsonl`: 42 distinct passing records,
  two explicit fixture/performance skips. `vet.log` is empty on success.
- `windows-final/`: actual native ARM64 output from Windows 11 under the logged-in
  user, with 42 passes and two fixture/performance skips. No capability skip. The
  directory-alias test passes on Windows as well as macOS. No service/printer call.
- `windows-input-manifest.json`, `run-windows.ps1`: hash-checked binaries/fixtures
  and the exact non-printing runner. `retained-artifacts.json` points to the local
  temporary archive of binaries, moved out of the working tree after testing.
- `performance.jsonl`: six measurements with synthetic outcomes, 1/3/10 sources,
  two stations, 4 KiB/512 KiB. Its source is
  `source-before-local-alias-fix.json`; the final change only adjusts LOCAL owner
  locking and its test, not the measured replicated queue path.
- `source-before-scope-projection.json`: source bridge for the earlier full
  regression run. Old checks are not silently relabeled as an exact final run.
- `initial-sandbox-test.jsonl`: failed socket setup under sandbox restrictions;
  `initial-station-test.jsonl` records the successful authorized localhost rerun.
  `earlier-performance.jsonl` and `windows-before-*`/`windows-first` retain prior
  measurements/runs without replacing the final evidence.
- `preimages.json`, `starting-status.txt`, `starting-head.txt`, `final-status.txt`,
  `diff-check.txt`: starting WIP and final source/Git checks. Preimages record hashes
  of selected already-dirty task paths; they do not claim a clean starting tree.
- `launcher-notes.json`: unsuccessful wrapper attempts, including the oversized
  encoded Windows launch followed by the successful same-script file launch.

Go used: 1.26.8 darwin/arm64. Repository dependency versions were retained; missing
pinned modules were downloaded into a temporary cache. Native Windows test
executables were cross-built with GOOS=windows, GOARCH=arm64, CGO_ENABLED=0 and
then actually executed in the VM. Cross-compilation alone is not execution proof.

The normal package selection, from `apps/edge`, is:

```sh
go test ./internal/printstation ./internal/printcluster ./internal/printqueue \
  ./internal/printeligibility ./internal/printtransport ./internal/printhost \
  ./internal/printeragent ./internal/printerdaemon ./internal/printerprovisioning \
  ./cmd/printer-agent -count=1 -json
go vet ./internal/printstation ./internal/printcluster
VYNIC_STATION_PERF=1 go test ./internal/printcluster \
  -run '^TestStationSoftwarePerformance$' -count=1 -json
```

Run `python3 collect-evidence.py` to recheck the retained logs, current source
hashes and Git diff, and regenerate the summary. It runs no tests, VM, service,
network listener or printer. It refuses source drift or failed/incomplete logs.
`ARTIFACTS.json` hashes packet contents excluding itself; rerunning the collector
may change current status metadata and requires a new explicit seal.

No automatic same-RAW-printer takeover is enabled. The synchronous proof
controller refuses real transports. The production local API still returns
HELD_PROVISIONING. The current Flutter/Hive writer is untouched.
