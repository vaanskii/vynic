# POS-02.A sealed software proof

Status: **DONE for POS-02.A only; overall POS-02 NOT_DONE**.
Scope and A–O report: [POS02_A_PROVISIONING.md](../../POS02_A_PROVISIONING.md).
`proof.json` maps acceptance requirements to retained evidence; `source-manifest.json`
pins the tested source and its local dependencies. `ARTIFACTS.json` hashes this
packet, excluding itself. `verify.py` checks both manifests and successful final
outcomes; later source changes must produce new proof rather than relabel this one.

## Final executions

- `backend-final.json` / `.log`: 16 real HTTP/PostgreSQL provisioning tests and
  160 existing PREPARED configuration cases; 176 pass, no skips/failures.
- `deletion-matrix.json` / `.log`: 16 existing local-only guard/matrix tests pass.
- `TestProductionBackendExport.jsonl` and `TestProductionBackendVerify.jsonl`:
  separate Go processes export public enrollment material, then consume the exact
  HTTP-issued snapshots, open actual mutual TLS, and verify scoped/revoked rights.
- `initial.json`, `configured.json`, `joined.json`, `revoked.json`: exact signed
  response envelopes from that final disposable issuer. They contain public test
  identities, not production credentials. `exchange-path.json` identifies the
  temporary test stores; private keys and Device/JWT secrets are not in this packet.
- `go-regression.jsonl`: 268 passing test/subtest cases; three test skips
  (two optional real-backend entries and the opt-in daemon process harness).
  The CLI package compiles with no unit-test files. No failures.
- `go-race.jsonl`: 24 passing production cases; optional backend helpers skipped
  here and run by the HTTP suite instead. No race failures.
- `windows-native.log`, `windows-result.json`: 25 native ARM64 cases, two optional
  exchange-helper skips, exit 0. `windows-run.ps1` is the actual launcher;
  `binary-manifest.json` pins retained binaries outside the checkout.
- `migrate-deploy.log`, `populated-upgrade.log`: fresh and populated previous-tip
  upgrade on dedicated PostgreSQL 17.10. `schema-diff.sql` shows only two earlier
  DevicePrinterRuntimeRequest FK-name differences; no POS-02.A schema difference.
- `database-environment.json`, `database-shutdown.log`: isolated test instance,
  no active restaurant database used, stopped afterward. `db-setup.py` and
  `db-upgrade.py` retain this run's setup/rehearsal commands. The Windows VM also
  returned to its original stopped state.
- TypeScript, ESLint, Go vet, formatting and diff-check logs are empty on success.

## Reproduce

Use a new loopback database whose name starts `pos02a_`, deploy the repository
migrations there, and set `POS02_A_DATABASE_URL` explicitly. The test refuses any
other database name/host. It generates disposable signing and authentication
material in memory. Set `POS02_A_GO` to Go 1.26.8 (or compatible Go 1.26 toolchain),
and optional `POS02_A_PROOF_DIR` to a new output directory. From `apps/backend`:

```text
node node_modules/jest/bin/jest.js --runInBand --runTestsByPath src/printer-provisioning/provisioning.integration.spec.ts
```

The integration suite invokes Go itself, so both Node and Go dependencies must be
available. From `apps/edge`, run `go test ./internal/printerprovisioning` and the
held-agent/daemon regressions; `go test -race ... -run '^TestProduction'` covers the
new boundary. Loopback listeners need ordinary local networking permission.
Windows-only DPAPI/MachineGuid tests require actual Windows, not cross-compilation.
The test binary never starts a service, scheduler or printer transport.

## Earlier outcomes, not final failures

`go-initial-failed.jsonl` records two negative-fixture expectations corrected from
JSON null to the contract's empty base64 catalog; malformed null was correctly
refused. `lint-initial-failed.log` records loose initial types; final provisioning
sources and tests pass lint. `backend-first.*` is an earlier successful HTTP run,
not the final source proof. The injected audit exception in backend logs is an
expected rollback test. No exception is swallowed by production code.

The first native launcher used unquoted PowerShell test flags and failed with
`flag provided but not defined: -test`; the corrected launcher and final native
results are retained. One disposable PostgreSQL restart omitted its original
listener options, failed to bind the occupied default port, and exited without
connecting to another database. It was restarted explicitly on its original
isolated port; `database-restart.log` retains both attempts. No production service
registration, signing-key creation, print activation or restaurant migration ran.

## Limits

Loopback peers prove the identity/authentication boundary, not deployed Venue LAN
RPC/Raft integration. Native Windows tests use the interactive test principal;
SCM boot and the eventual service principal remain separate. No physical printer
or Flutter writer is involved. Offline peers can use an old valid grant until
refresh or its seven-day expiry; learned revocation persists. Protected storage
and a trusted OS clock are required; full OS/VM clones are not fresh installations.
