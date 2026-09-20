# Vynic Edge — foundation and Phase 2A shadow

The Phase 0 Primary POS remains the production operational authority. Go adds
SHADOW Order/Table commit/replay/snapshot APIs, without an operational authority
grant, Cloud command execution or POS Device credential. Phase 2A scope and
rollout prerequisites: [Orders/Tables](../../docs/EDGE_PHASE2A_ORDERS_TABLES.md). See the locked
[contracts](../../docs/EDGE_PHASE1_FOUNDATION.md) and captured
[validation](../../docs/EDGE_PHASE1_VALIDATION.md).

## Layout

- `cmd/edge`: explicit init/bind/admin/start commands.
- `cmd/terminal-sim`: isolated Go terminal, durable credentials and session.
- `internal/store`: SQLite/WAL, embedded migrations, identity/pairing/session state.
- `internal/server`: authenticated TLS gRPC infrastructure APIs.
- `tool/dart_sim`: standalone Dart protocol consumer; no Flutter/Hive imports.
- `tool/mac-dev.sh`, `tool/prove.py`: disposable full-stack process proof.

## Build and check

Go 1.26+ (validated with 1.27.1), Dart 3.8+ (validated with 3.12.1), Node/backend
existing dependencies, Python 3 and PostgreSQL 17 are needed for the complete
macOS proof. No Go installation is needed by the existing production apps.

```sh
cd apps/edge
go mod download
go test -race ./...
go vet ./...
go build -o bin/ ./cmd/...
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -o bin/windows/ ./cmd/...
cd tool/dart_sim
dart pub get
dart analyze
cd ../../../../..
```

The SQLite driver is pure Go. Native SQLite libraries, a Windows C compiler and
CGO are not required. `go.sum` and both Dart lockfiles are committed.

## Generated protocol

Canonical sources: `packages/contracts/proto/vynic/edge/v1/*.proto`.
Generated outputs are standalone Go/Dart packages under `packages/contracts`.
Do not hand-edit them. Flutter imports them for explicitly attached shadow
observers and the isolated Hive client; normal startup does not attach Edge.

Install `protoc` **36.2** from the official protobuf release for your OS
([releases](https://github.com/protocolbuffers/protobuf/releases/tag/v36.2)).
The macOS arm64 zip SHA-256 is
`9cd98a532c5c5e0c4161314de0225de27e4c8a323917b6ea7b1b714d3ae23466`.
Put its `bin` directory, `$GOPATH/bin` and `$PUB_CACHE/bin` on PATH, then:

```sh
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.11
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.6.2
dart pub global activate protoc_plugin 25.0.0
packages/contracts/scripts/generate-edge.sh
packages/contracts/scripts/generate-edge.sh --check
node packages/contracts/scripts/generate.mjs --check
```

The original JSON/TypeScript/Dart Cloud command generation is unchanged.
Protocol major/minor and SQLite migration version are separate contracts.

## macOS development proof

Install backend dependencies using the repository's existing workflow first.
Resolve the isolated Dart simulator dependencies as above. From repository root:

```sh
apps/edge/tool/mac-dev.sh
# Add the separate-process Terminal A/Hive A + Terminal B/Hive B proof:
apps/edge/tool/mac-dev.sh --phase2a
```

`PG_BIN` optionally selects PostgreSQL 17 binaries (default Homebrew path).
`DART` optionally selects a Dart executable. The script creates a private temp
PostgreSQL cluster/database, applies migrations from empty, checks schema drift,
runs real Nest/PG Phase 0 and foundation tests, builds Go, and invokes the proof.
It stops its PostgreSQL cluster on exit. It never loads an application `.env`,
connects to the live database, starts website/payment bootstrap, or starts a production Flutter application. The Phase 2A option runs Dart
terminal processes using the real Order/Table models and Hive adapters.

The isolated Nest process uses **production** provisioning controller/service,
Platform guard/JWT resolver and Prisma against the disposable database. It seeds
synthetic Venues/operator/Primary POS and cleans them up. It does not substitute
mock HTTP responses. Terminal A and B are separate subprocesses/directories with
separate UUIDs and credentials. Dart pairs as a third distinct terminal.

The proof tests ticket replay/reuse, invalid credentials, wrong Venue, protocol
mismatch, simultaneous streams, exclusive store ownership, SIGKILL while WAL is
populated, restart/reconnect with the same sessions, clean shutdown, incompatible
and corrupt stores, local terminal revocation and Cloud registration revocation.
Go tests additionally interrupt an uncommitted transaction, inject a pairing write
failure and race two terminals for one ticket. Logs and a JSON proof report remain
in the printed temporary directory; its credentials are synthetic test-only data.

## Manual foundation lifecycle

Use a private local data directory, never a network share. POS terminals must not
open this database. On macOS/Linux use an owner-only directory; on Windows grant
only the dedicated service/operator accounts access with filesystem ACLs.

```sh
apps/edge/bin/edge init --data /private/path/edge > installation-request.json
```

Send the returned `installationId` and `publicKey` with an authenticated Platform
operator request to `POST /platform/venues/:venueId/edge-foundations`. Cloud needs
an Ed25519 PKCS#8 `EDGE_FOUNDATION_SIGNING_KEY_PEM`; without it provisioning is
503 and normal POS routes continue unchanged. The response is returned only after
registration and audit commit. Same binding can be reissued; another Venue/key or
revoked installation is refused. Supply the Cloud SPKI public key out of band.
Save only the response's `grant` string into the grant file, then:

```sh
apps/edge/bin/edge bind --data /private/path/edge \
  --grant-file grant.txt --cloud-key trusted-cloud-public.pem
apps/edge/bin/edge ticket --data /private/path/edge > terminal-a-ticket.json
apps/edge/bin/edge ticket --data /private/path/edge > terminal-b-ticket.json
apps/edge/bin/edge serve --data /private/path/edge --listen 127.0.0.1:7443
```

`init` is repeatable and does not replace identity. `bind` is explicit and accepts
only a ten-minute signed grant for that local public key. Initial grants are not
runtime credentials: an already bound Edge can start without Cloud or a current
grant. Cloud revocation prevents subsequent grants, not offline startup. This is
safe only because Phase 1 has **no operational authority**.

Copy `edge-cert.pem` to each terminal through the trusted pairing channel. TLS
uses a persisted P-256 self-signed certificate named `vynic-edge.local`; installation
and Cloud signing keys are Ed25519. The Dart simulator explicitly compares the
certificate's DER bytes with that out-of-band pin if macOS platform validation
rejects the self-signed certificate; it also checks authority and validity dates.
A different pin is tested and refused. No insecure TLS mode exists.

```sh
apps/edge/bin/terminal-sim --data /private/path/terminal-a \
  --address 127.0.0.1:7443 --cert /private/path/edge/edge-cert.pem \
  --venue VENUE_UUID --installation EDGE_UUID \
  --ticket-file terminal-a-ticket.json --name A --watch 10s
```

Run B with a **different data directory and ticket**. Reconnect using the same
terminal directory and omit `--ticket-file`. Never copy one terminal's directory
to simulate another terminal. The simulator refuses concurrent use of its state.
The Dart simulator accepts positional data/host/port/cert/Venue/installation/ticket
arguments; use `-` for the final ticket argument on reconnect.

Administration is deliberately offline in Phase 1. Stop Edge before issuing
another pairing ticket, inspecting state, or running:

```sh
apps/edge/bin/edge revoke --data /private/path/edge --terminal TERMINAL_UUID
```

Terminal identity and historical metadata are retained. A revoked UUID cannot
re-pair; provision a new terminal identity. Sessions are audit/reconnect metadata,
not bearer credentials or live-presence claims. Streams are process-local.
`grpc.health.v1.Health` exposes only infrastructure serving status over TLS;
authenticated `Status` exposes binding, protocol/schema, boot ID and mode.

## Recovery and replacement

A successful response means the relevant SQLite transaction committed with WAL
and FULL synchronous durability. Retry the **same** pairing request/terminal/secret
or session after an unknown response. A changed replay fails. An expired unused
ticket fails, while the exact already-consumed pairing retry remains idempotent.

On corrupt/newer/altered schema, startup fails without serving or resetting. Keep
all database/WAL/SHM files for diagnosis. Do not delete them to make startup pass.
Back up a stopped directory, including any remaining WAL. Restore only after the
old host has been fenced; copied identity must never run simultaneously. The OS
file lock prevents duplicate processes on one host, not cloned stores on two hosts.
No distributed failover or automatic Edge election exists.

Foundation replacement uses a new installation and fresh terminal pairing. Revoke
old registration with `POST /platform/venues/:venueId/edge-foundations/:id/revoke`,
stop the old host, and preserve its metadata. Neither this operation nor Go startup
changes `activeOperationalDeviceId`, recovers Hive or transfers business authority.

Windows x64 cross-compilation is checked. Actual Windows runtime/locking/TLS tests,
service installation, shutdown integration, ACLs and firewall deployment remain
release checks. Certificate renewal/keychain provisioning are not an updater or a
hardware implementation. Phase 2 requirements are listed in the architecture doc.

## Windows POS updater

`serve --pos-updater-config <external-config.json>` enables signed background
POS staging and explicit user installation. `launch-pos --pos-updater-config
<external-config.json>` asks the running Edge to launch its selected POS release.
No Edge self-update or production Order/Table authority is enabled. Provisioning,
release signing, readiness, recovery and Windows qualification requirements:
[Windows POS updater](../../docs/POS_WINDOWS_UPDATER.md).

macOS Hive process proof: `python3 tool/prove-pos-updater.py --dart <dart>`.
Go tests include HTTPS download and actual child-process health/rollback simulation.

## Windows first install

`cmd/setup` builds the small `VynicSetup.exe` bootstrapper. It provisions a
same-user Windows host from signed Edge/POS downloads, with ACLs, logon startup,
updater-aware shortcuts and data-preserving repair/uninstall. `edge host` runs
only local POS updater IPC before any Venue binding; `serve` remains bound-only.
No Edge self-update or business-authority change is enabled.

Build with `tool/build-setup.py --distribution <public-config.json> --out <VynicSetup.exe>`;
the tool embeds the required unelevated GUI manifest. Publish metadata with
`cmd/sign-bootstrap`, reusing the POS Ed25519 envelope/trust implementation.
See [Windows setup](../../docs/WINDOWS_SETUP.md) for release inputs, layout,
repair endpoints and mandatory real-Windows qualification.
