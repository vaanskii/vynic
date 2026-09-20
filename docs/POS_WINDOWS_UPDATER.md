# Windows POS updater — first production-oriented implementation

The updater is implemented, with macOS simulation evidence. It is **not deployed
or certified on Windows**. It requires an explicitly provisioned host and trusted
release channel; no production signing keys/feed are invented or enabled.

## Ownership and boundaries

Go Edge checks, downloads, verifies, stages, activates, starts, health-checks and
rolls back **vynic-pos / windows / amd64** bundles. Flutter owns business rules,
Hive, operation admission and recovery readiness. Edge remains running throughout
POS replacement. Manager's entrypoint/update behavior is unchanged.

Phase 0 fencing and Phase 2A SHADOW authority remain unchanged. This does not
select an operational Edge, authorize additional POS writers or enable production
Orders/Tables authority. No payment, close, Sale, inventory, printer, updater of
Edge, Cloud transport ownership or website domain moves to Go.

The host-local updater is an opt-in part of `edge serve`, beside the existing TLS
gRPC foundation. It uses a separate loopback-only HTTP IPC `/v1` API with a random
host credential. It is deliberately unavailable through LAN terminal pairing:
one remote terminal must never stop another machine's POS. No business mutation
or competing coordination protocol is added. Go foundation protocol 1.1, SQLite
schema 2, and POS Hive schema 9 remain unchanged.

## Signed release contract

An envelope has exactly `keyId`, base64 `payload`, base64 `signature`. The signature
is Ed25519 over the exact bytes `VYNIC-POS-RELEASE-v1\n` followed by decoded payload.
Verification happens **before** parsing/accepting the payload. This avoids implicit
JSON canonicalization between publishers and clients. Unknown envelope/payload
fields and trailing JSON are refused.

Payload example (digest/size computed by the signing tool):

```json
{
  "product": "vynic-pos",
  "version": "1.9.0",
  "release": 19,
  "os": "windows",
  "arch": "amd64",
  "channel": "stable",
  "url": "https://releases.example.invalid/pos/1.9.0/windows-amd64.zip",
  "sha256": "64-lowercase-hex-digits",
  "size": 123456,
  "expires": "2026-10-01T00:00:00Z",
  "updaterProtocol": 1,
  "hiveSchema": 9,
  "edgeSchema": 2,
  "dataPolicy": "hive9-no-migration"
}
```

Version must be a strictly newer numeric `major.minor.patch`; no prereleases,
build-suffix ambiguity, forced downgrade or cross-channel switching. Release is a
monotonic publisher number above the durable high-water mark. The key and manifest
must be unexpired; manifest expiry may be at most 31 days away. Product/platform,
channel, updater protocol, Hive/Edge schema and data policy must match exactly.
The high-water mark survives binary rollback, preventing automatic reinstallation
of a failed release. A repaired build requires a newer version/release number.

The external host configuration contains **public Ed25519 keys only**, indexed by
key ID and expiry. Trust changes/rotation are explicit privileged provisioning:
overlap public keys before signing with the new key; remove compromised keys.
Downloaded metadata cannot add trusted keys. Signing private keys live in the
release owner's offline/CI secret system, never in this repository, POS or Edge.
HTTPS plus an unsigned checksum is not accepted.

`apps/edge/cmd/sign-pos-release` is a separate offline/CI tool; do not distribute it
with POS. It reads an external Ed25519 PKCS8 PEM, hashes the ZIP, validates the
metadata policy and emits the signed envelope. Example from `apps/edge`:

```sh
go run ./cmd/sign-pos-release --manifest /release/metadata.json \
  --artifact /release/windows-amd64.zip --key-id pos-release-2026 \
  --private-key /secure/offline/pos-release.pem > /release/manifest.json
```

The release publisher must prove both candidate and previous POS can read/write
the unchanged Hive 9 data. This phase refuses schema-changing releases; a signed
`hive9-no-migration` assertion is a release-policy commitment, not an instruction
to restore data. Authenticode signing and Windows reputation checks are additional
release validation, separate from the portable manifest signature.

## Host layout and initial provisioning

Use one interactive Windows account for POS and the current Go Edge process.
Starting an interactive POS from a Windows LocalSystem/session-0 service is not
implemented. A per-user startup task can run Edge; its long-running instance is
not replaced by this updater.

Provision the first **updater-aware** POS baseline manually through the trusted
initial distribution. Existing older POS executables without the readiness
barrier cannot be remotely opted in. Keep existing product identity and the
host's existing application-support Hive path. Do not copy data into release
folders. Provision a complete baseline at:

```text
<managed-root>/
  updater.lock
  updater.sqlite (+ WAL/SHM)
  staged.zip
  releases/1.8.0/vynic_pos.exe
  releases/1.8.0/flutter_windows.dll
  releases/1.8.0/data/...
  releases/1.9.0/...  (created only after explicit install)
```

Every release ZIP contains the **entire Windows Flutter release directory** at
its root, including `vynic_pos.exe`, plugin/runtime DLLs and `data/`. It is not an
installer; no downloaded script, MSI, command line or arbitrary entrypoint runs.
The normal product-specific build preparation remains in `tool/product.py`.
Build POS with the intended version/build number and preserve `ge.vynic.pos` and
its existing support-directory identity. Do not use a Manager bundle.

Provision a config outside the repository (illustrative values, not usable keys):

```json
{
  "root": "C:\\Vynic\\POS",
  "feed": "https://releases.example.invalid/pos/stable/manifest.json",
  "channel": "stable",
  "initialVersion": "1.8.0",
  "initialRelease": 18,
  "listen": "127.0.0.1:7444",
  "token": "at-least-64-random-characters-generated-on-this-host",
  "keys": {
    "pos-release-2026": {
      "public": "base64-encoded-32-byte-Ed25519-public-key",
      "expires": "2027-01-01T00:00:00Z"
    }
  }
}
```

Installer/operator must apply Windows ACLs to config, root, DB, staged ZIP and
release directories: only the designated POS/Edge account and administrators may
write/read the host credential; other users cannot replace binaries or keys.
POS necessarily reads its host IPC credential, which is not a release-signing
secret. Local administrator/same-account malware is outside this credential's
security boundary. Never expose this port on a LAN proxy.

Start the existing bound foundation with:

```text
edge.exe serve --data C:\Vynic\Edge --pos-updater-config C:\Vynic\pos-updater.json
```

The initial POS process needs `VYNIC_POS_UPDATER_CONFIG` set to that same config.
Go-launched children inherit it automatically. Point the Windows POS shortcut to
`edge.exe launch-pos --pos-updater-config C:\Vynic\pos-updater.json`; it requests
launch from the already-running Edge and resolves the current release from the
durable updater DB. It does not run a second Edge daemon or pin the old binary.
Startup shortcuts must not independently launch a release during activation.

`initialVersion`/`initialRelease` seed a new updater DB only. Never delete/restore
that DB to downgrade releases; it contains install consent, results, active
version and the anti-replay high-water mark. A file lock refuses a second updater
owner even if another Edge uses a different foundation data directory.

## Background download and UI

Edge checks on start and every 30 minutes; Settings can request a check. It fetches
a bounded signed envelope over HTTPS, verifies policy, then downloads into
`staged.zip.part`, exposing byte progress. The download is limited to the signed
size (maximum 512 MiB), flushed and SHA-256 verified before durable
`READY_TO_INSTALL`. Partial/network-failed downloads never become executable;
retry starts a fresh download. HTTP downgrade redirects are refused. Staged data
survives Edge/POS restart. A staged valid release is not automatically installed
or replaced by polling.

The POS presents:

```text
ახალი ვერსია ხელმისაწვდომია
1.9.0
[ განახლება ახლა ] [ მოგვიანებით ]
```

Later persists dismissal for that version in Hive. It does not send an install
request or discard the ZIP. Settings contains `პროგრამის განახლება` with the
version, state/progress and an explicit `განახლება ახლა` action. All supported
states are rendered: UP_TO_DATE, CHECKING, DOWNLOADING, READY_TO_INSTALL, BLOCKED,
INSTALLING, RESTARTING, SUCCESS, FAILED, ROLLED_BACK. Technical errors are logged;
operator-facing Georgian messages remain short. `lastOutcome` retains successful
install/rollback evidence across later checks.

## One UpdateReadiness contract

`core/services/pos/update/update_readiness.dart` returns `READY` or
`BLOCKED(reason)`. UI has no Order-count/table-occupancy safety predicates.

Blockers are startup not ready, tracked active payment/close/cancel/restore or
multi-write operation, unfinished local writes, uncertain persistence/transaction
failure, pending closure journal recovery, running/interrupted Cloud-command
execution (not pending delivery/ACK), active/unready/closed Edge projection,
unresolved Phase 2A intent, or an already-acquired install barrier.

The coordinator readiness registry observes the existing Phase 2A `ready`, busy
and `pendingRequestId` signals. A reopened coordinator supersedes the previous
instance at its same box path; closing a registered projection does not clear its
blocker. Any explicitly attached coordinator must be reattached/opened during
startup before reporting readiness. The ordinary production app still has no
Phase 2A authority/observer attachment. Isolated development projection stores
are not searched or adopted into production.

Repository/transaction entry scopes preserve tracking across multiple awaited
writes. Hive box decorators and model save/delete scopes cover direct writes.
Full payment/close orchestration retains its scope between payment selection and
commit. These scopes are disabled for Manager and for an unconfigured updater.
Persistence failures and caught partial financial-transaction failures block until
recovery/reconciliation and restart establish certainty.

**Durable open Orders, occupied Tables, reservations and queued Cloud sync/outbox
records do not block.** Cloud acknowledgments are not required for updating.

On explicit Update Now, POS persists a release-bound request UUID, reevaluates
readiness, synchronously freezes new operations before its first await, and
flushes its open local boxes, closure journal, Edge execution journal and active
coordination metadata. Operator input is disabled. Failed flush never reaches
Go install. An install marker also survives POS restart: startup waits for Go to resolve
that decision before resuming operational services/input. A lost install ACK
retains the barrier/request ID; repeated clicks
retry that same request. A definitive rejection can release the barrier only
after reading a state showing that request was not accepted. It never assumes a
network timeout means the request failed.

## Activation, health and crash recovery

Go checks the requested release/version, exact managed POS process path, original
signature/key/expiry, artifact size/hash and compatibility **again at install**.
Consent and `(requestId, version, pid, dataPath)` idempotency are committed atomically before
stopping anything. Replays cannot install a later staged version; changed inputs
are refused. Another install/launch/check cannot overlap the activation worker.

ZIP extraction rejects traversal, absolute/drive/ADS paths, Windows reserved
names, symlinks, duplicate case-insensitive paths and oversized expanded content
(1.5 GiB / 20,000 entries). It extracts into a new immutable version directory.
There is no in-place overwrite of the running Windows executable.

After the POS readiness barrier:

1. Go stops only matching `vynic_pos.exe` processes at the exact current managed
   path. Windows image-path validation and termination use the same kernel
   process handle, avoiding PID reuse/name-wide termination. Go waits for exit.
2. SQLite/WAL/FULL records the active release and release high-water mark.
3. Go starts the candidate with a random startup nonce and version in its child
   environment, using its release directory as working directory.
4. POS opens existing Hive, runs existing recovery and renders a first frame.
   Candidate input and Cloud polling remain paused. It reports readiness through
   authenticated IPC with nonce, PID, version, Hive schema and data directory;
   Go verifies the process path and that both candidate/rollback open the same
   directory as the original POS. A fresh/incorrect data path cannot pass health.
5. Go durably records SUCCESS/startup verification before POS resumes operation.

Missing/invalid health within 90 seconds or failed launch causes Go to stop the
candidate, restore the **binary pointer only**, restart the previous POS, verify
its health and report ROLLED_BACK. If even the previous POS cannot start, report
FAILED with the previous release selected and an actionable diagnostic. A later
explicit launch retries that selected binary. Previous version directories are
retained; automatic release garbage collection is deferred.

Restarting Edge while only staged never grants consent. Restarting after durable
INSTALLING/RESTARTING consent conservatively stops interrupted candidate/current
processes and restores/health-checks the previous release. Updater SQLite integrity
and schema are checked; corrupt/incompatible state refuses startup instead of
resetting release history. Restaurant Hive and foundation Edge SQLite are never
restored, deleted, copied or rolled back by the updater.

## Development proof and validation

- `go test -race ./...` in `apps/edge`: signed HTTPS fixtures, actual child process
  startup/health, failure/rollback, staging/restart, changed/repeated requests,
  wrong process/authentication, corrupt hash/signature/schema, download loss/retry,
  path traversal and single updater ownership. Synthetic `.exe` is not executed
  on macOS; the process adapter runs a known test child.
- Flutter readiness/UI tests exercise Later/Settings, real Hive adapters,
  payment/close barriers, failed flush, lost ACK, existing Edge pending/readiness,
  pending closure recovery and Manager-disabled behavior.
- `python3 apps/edge/tool/prove-pos-updater.py --dart <dart>` launches three actual
  Dart processes against one temporary Hive directory. Seed/flush/abrupt exit,
  simulated candidate restart and simulated rollback restart must yield identical
  open Order/Table/UUID/total/outbox data. Captured report:
  `docs/POS_WINDOWS_UPDATER_PROOF.json`. No real Windows binary executes in this
  data proof.
- Validation results: `docs/POS_WINDOWS_UPDATER_VALIDATION.md`.

Real Windows release qualification remains required: actual process handles and
termination, Flutter/plugin cleanup, executable/DLL locks, atomic directory
visibility and SQLite durability under power loss, filesystem ACLs and disk-full,
interactive account/session launch, installed Flutter runtime/DLL/assets layout,
POS support-directory continuity, UAC, Authenticode/SmartScreen/antivirus quarantine,
and an actual signed candidate/previous pair with open restaurant state. Test
secondary POS/Manager/Edge processes survive untouched. macOS simulations and a
Windows cross-build do not establish those properties.

## Edge self-update boundary

No Go replacement, bootstrap/helper, Windows service replacement, automatic
installation or forced restart exists. Edge self-update needs a separately
reviewed privileged lifecycle, signed Edge releases, SQLite compatibility,
operational fencing/intent drain, host recovery and helper/service rollback proof.
It is not enabled by this POS updater or by Phase 2A readiness.

## Host IPC v1 wire surface

All routes require `Authorization: Bearer <host-token>`, bind only to
`127.0.0.1`, and return a no-cache JSON status. Requests are bounded to 4 KiB.

| Route | Request | Effect |
|---|---|---|
| `GET /v1/status` | none | status/version/current/progress/reason/lastOutcome/attempt/startupVerified; no nonce/signature secrets |
| `POST /v1/check` | `{}` | background check/download only |
| `POST /v1/install` | `requestId`, `version`, `pid`, `dataPath`, `ready: true` | explicit POS consent after its held readiness/flush barrier; atomically journal and start install |
| `POST /v1/health` | `nonce`, `version`, `pid`, `dataPath`, `hiveSchema: 9` | candidate/rollback startup report, accepted only for the current process/nonce/path/schema |
| `POST /v1/launch` | none | explicit shortcut request to start the DB-selected POS release |

The host token is given only to the managed POS/Edge account. `ready` is a report
from the trusted local POS controller holding the admission barrier, never from
a LAN terminal or Cloud principal. Other authenticated terminal pairing credentials
are not accepted here. Status/schema/signature errors do not authorize execution.
