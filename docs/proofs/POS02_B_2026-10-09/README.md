# POS-02.B proof packet

POS-02.B is DONE for authenticated Go peer transport and logical queue membership.
Overall POS-02 remains NOT_DONE. See `../../POS02_B_PEER_TRANSPORT.md` for the full
contract, supported transitions, offline policy, limits and next stage.

## Final evidence

- `process-final.jsonl`: 37 passing tests/subtests, one subprocess entrypoint skip.
- `race-final.jsonl`: 14 passing records, no skips. Children execute the same
  race-instrumented test binary; parent cleanup checks child stderr for race reports.
- `regression-final.jsonl`: 400 passing records. Six named opt-in/child/backend
  fixture entrypoints are skipped; this stage changes no backend issuer or schema.
- `performance-final.jsonl`: separate 1/3/10-source run with the VM stopped and no
  other test suite; actual TCP/TLS admission, distinct payloads. Raw samples retained.
- `windows-native.log`, `windows-result.json`: 37 passing native ARM64 records,
  one child-entrypoint skip, real MachineGuid/DPAPI, executor account SYSTEM.
- `binary-manifest.json`: final Windows ARM64 test binary and ARM64/amd64 foreground
  runtime binaries; exact test executable hash equals the Windows execution result.
- `vet.log`: final focused Go vet completed with exit 0 and no diagnostics.
- `source-manifest.json`, `ARTIFACTS.json`, `verify.py`: read-only source/artifact
  verification. Older source evidence is not relabeled as this implementation.

Real processes communicate over loopback TCP. The fault relay forwards opaque TLS
bytes and closes actual connections; it is not an in-memory Raft transport.
These are software tests on one Mac and one Windows VM, not multi-PC LAN or physical
printer qualification. No production signer/credential, database, restaurant data,
service registration, firewall rule, driver or printer configuration was used.
The existing VM began stopped and ended stopped. No physical print writer exists
in the runtime's exposed RPC. Physical dispatch stays HELD.

## Reproduction

Use the pinned Go module/dependencies (this run: Go 1.26.8). From `apps/edge`:

```text
go test -tags printerfixture ./internal/printpeer -count=1 -json
go test -race -tags printerfixture ./internal/printpeer -run '^TestPeerProcess(Recovery|JoinAndExpansion|Security|OpenConnectionRevocation|TCPPartition)$' -count=1 -json
go test ./internal/printcluster ./internal/printstation ./internal/printerprovisioning ./internal/printeragent ./internal/printerdaemon ./cmd/printer-peer -count=1 -json
go test -tags printerfixture ./internal/printpeer -run '^TestPeerProcessPerformance$' -count=1 -json
go vet -tags printerfixture ./internal/printpeer ./internal/printcluster ./internal/printerprovisioning ./cmd/printer-peer
```

Loopback listener permissions are required. The `printerfixture` tag supplies only
an isolated non-Windows machine binding; it is not included in distributable
binaries. Tests generate disposable keys in memory and use fresh temporary state.
Never substitute a restaurant directory. Windows test executables must be compiled
for the VM architecture and run in a new guest temporary directory. The retained
`windows-run.ps1` records the original hash-checked execution; its host staging path
was removed after verification. Native execution is not SCM qualification.

## Intermediate attempts

`process-first.jsonl` retains two failed ten-source performance admissions after
short retries and immediate slot refusal. `race-first.jsonl` retains a query that
ran before the dropped-response admission finished. Neither exposed a false ACK.
Bounded slot waiting and six retry rounds inside a 12-second deadline corrected
these cases. Later `*-second` / `race-third` logs and Windows first/second/third logs
are intermediate passing builds, preserved separately from final evidence.

Early development also corrected a fixture catalog's null Rules and non-LAN
placeholder destination, a compile-time reprint field typo, and a misplaced
cross-build output directory. The first sandboxed loopback run was denied by the
sandbox; the authorized listener runs use the normal local TCP stack. No automatic
approval rejection occurred. A final join review added opening the first signed
endpoint for an initially endpoint-less client. Final Mac/race/Windows runs include
that path and graceful source exit. No private key is included in this packet.

## Scope and Git

`changed-existing-files.json` records 11 files changed from the starting WIP;
`new-stage-files.json` records eight new source/report files. All 1,233 previous
proof files are unchanged. Broad pre-existing WIP remains user-owned. No commit,
reset, stash, rebase or push. Focused commits could not safely include this stage
without depending on the pre-existing uncommitted printer implementation.
