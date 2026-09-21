# Edge Phase 1 validation

Validated on macOS arm64 with Go 1.27.1, Dart 3.12.1, PostgreSQL 17,
`modernc.org/sqlite` 1.59.0 and protoc 36.2. Reproduce with the commands in
`apps/edge/README.md`. The machine-readable process proof is
[`EDGE_PHASE1_PROOF.json`](EDGE_PHASE1_PROOF.json).

## Process-level proof

The disposable run started a real Nest application using the production
provisioning controller, Platform guard/JWT resolver, service and Prisma, against
a new PostgreSQL cluster. It applied migrations from empty and reported **no
schema difference**. No live database or custom website/BOG process was used.

It then ran Go Edge against SQLite and two Go simulator subprocesses, plus an
isolated generated Dart client. All three persisted separate identities:

| Simulator | Terminal UUID |
| --- | --- |
| A | `f7d073d6-03f6-458e-9f8b-d4ff6286c5de` |
| B | `11376e38-bc39-44f3-aee6-2ffadfaeea99` |
| Dart | `135299e6-2170-4c85-8b98-9a2a862a7d45` |

All **16 process checks passed**, including simultaneous A/B status streams,
valid pairing and exact retries, changed-identity replay rejection, invalid
credential, wrong Venue, protocol mismatch, same-store lock exclusion, SIGKILL
with a populated WAL, restart/reconnect, Go/Dart TLS interoperability, wrong
certificate pin refusal, clean stop/start, stable session counts, bad schema,
terminal revocation and Cloud registration revocation. Every successful status
remained `FOUNDATION_ONLY`; no business mutation authority was granted.

## Automated checks

- **8 Go test cases** passed with the race detector, including nested scenarios;
  the crash-worker entry point is intentionally skipped in the parent process
  and invoked by the crash-recovery test in a separate process. Tests cover
  committed WAL recovery/uncommitted rollback, atomic pairing failure, concurrent
  ticket consumption, immutable grants, sessions, revocation, protocol/capability
  rejection, actual schema/checksum validation and bounded active-stream shutdown.
- **21 HTTP/PostgreSQL tests** passed: 8 new foundation tests plus the 13 existing
  Phase 0 authority tests. Cloud audit failure rolls registration back; concurrent
  requests create one binding; revoked/cross-Venue identities are refused. Phase 0
  snapshots, claims, replacement, legacy containment and tenant fencing remain.
- **386 existing backend unit tests / 42 suites** passed. Backend build passed.
- Go vet, standalone generated Go module build, both Dart package analyses and
  existing/new generated-contract drift checks passed.
- Windows amd64 service and simulator cross-compilation passed with CGO disabled.
- Prisma generation/validation, migrations from empty and schema diff passed.
- Final whitespace/diff checks passed; unrelated working changes were preserved.

Logs from the final disposable run are in `/tmp/vynic-edge-dev.adH3Wh`; its
PostgreSQL cluster and all harness subprocesses were stopped. These paths are
local evidence, not dependencies of the implementation.

## Limits of this evidence

This proves infrastructure behavior on macOS, not production cutover, concurrent
restaurant mutations, physical power-loss durability, actual Windows runtime,
Windows service lifecycle, filesystem ACL provisioning, certificate renewal or
hardware behavior. Phase 0 stays authoritative. No production migration,
provisioning, deployment or push was performed.
