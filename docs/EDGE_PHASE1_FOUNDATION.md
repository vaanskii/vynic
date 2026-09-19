# Edge Phase 1 — locked foundation contracts

These contracts precede implementation. Phase 1 is infrastructure only. The
Phase 0 `Venue.activeOperationalDeviceId` remains the only production operational
authority. Flutter owns business rules/Hive; NestJS owns SaaS/Cloud domains.

## Identity and authority

An Edge installation is a separate principal, never a POS `Device`. It generates
a random UUID and Ed25519 key locally. Platform-authenticated provisioning binds
that identity/public key to one ACTIVE Venue in a separate Cloud registry and
returns a Cloud-signed, ten-minute bootstrap grant. The operator supplies the
trusted Cloud public key out of band. Edge verifies the signature, purpose,
expiry, UUID, and its own public key before durably binding. Rebinding to another
Venue is forbidden. A grant is not a Cloud access token or operational lease.
The private installation key and TLS identity stay on the Edge host.

Phase 1 may register foundation installations but selects **no active Edge** and
never changes the Phase 0 pointer. Every status says `FOUNDATION_ONLY` with
`business_mutations_enabled=false`. Future authority must be explicit:
one Venue → one selected Edge with a fencing epoch → N authenticated terminals.
No polling, process restart, lost connection, or enrollment elects a leader.

## Terminal pairing and transport

Each simulator/terminal generates its own UUID and 256-bit credential, persisted
before sending a request. An operator issues a random 256-bit, ten-minute local
pairing ticket through the Edge CLI while the service is stopped. Ticket hashes
are stored in SQLite. Pairing includes the intended Venue, installation, protocol,
terminal identity, and random request UUID. Ticket consumption and terminal
creation commit together. Only an identical retry (including credential/name)
succeeds after consumption; a changed request, credential, or identity fails.
Unconsumed expired tickets fail. Terminals cannot choose their authority.

gRPC always uses TLS 1.3 and a persisted P-256 installation certificate, trusted via an
out-of-band certificate file; the certificate name is `vynic-edge.local`.
There is no insecure LAN mode or trust-on-first-use. Every authenticated RPC
checks terminal credential, immutable Venue/installation binding, and protocol.
High-entropy credentials are SHA-256 verifiers at rest. Local OS access to the
Edge state directory is administrative authority. CLI revoke preserves identity
and disables authentication. Phase 1 pairing/revocation requires service stop;
a future operator control channel is separate work.

## Protocol and compatibility

Canonical protobuf source lives in `packages/contracts/proto/vynic/edge/v1`.
Pinned generators produce standalone Go and Dart packages; Flutter production
does not depend on them yet. Protocol starts at major=1, minor=0. Major must match;
client minor must be <= server minor. Unknown required capabilities fail closed.
Optional fields are additive; field numbers are never reused. Breaking semantics
require a new major/package and explicit rollout. SQLite, protocol, Cloud grants,
and existing Cloud command contract versions are independent.

Only Pair, Handshake, Status, and WatchStatus RPCs exist. Handshake durably records
a client-generated session UUID and metadata; retries reuse that session. Status
streaming reports infrastructure liveness, never restaurant events. Sessions are
not authentication credentials. Restart retains metadata, but live connections
are process-local and all clients must reconnect/authenticate. No Cloud commands,
Orders, Tables, Payments, inventory, printing, or Sale closing RPCs exist.

## SQLite and recovery

One host/process owns one local SQLite file; never use a network share. An OS
file lock prevents a second process. WAL, foreign keys, busy timeout and FULL
synchronous durability are mandatory. Embedded numbered SQL migrations are
transactional with a checksum ledger and `user_version`. Application identity,
integrity, migration checksums, actual DDL and supported schema are checked before serving.
Unknown/newer, corrupt, altered or inconsistent schema fails closed without
deleting/reinitializing the store. An acknowledged write has committed; an
interrupted pairing/session request can safely retry with the same identities.
SQLite WAL recovery runs on reopen. Graceful shutdown drains with a deadline,
then closes streams and database. Process crash is covered by restart tests;
power-loss/hardware guarantees remain bounded by filesystem/disk durability.

Back up only a stopped store (database and any WAL together); do not copy a live
database alone. Restore only onto the same logical installation after fencing
the old process/host. Lost state means a new installation and fresh pairing,
not a silently reconstructed identity. No automatic salvage or leader failover.

## Replacement and next phase boundary

Foundation replacement registers a new installation with separate local state
and terminal credentials, revokes the old Cloud registration, stops the old host,
and explicitly pairs terminals again. Cloud revocation prevents new grants; it
cannot remotely stop an offline foundation. Phase 1 carries no business state to
merge. It neither moves the Primary POS pointer nor copies Hive.

Phase 2 must prove an explicit active Edge/epoch admission model, coordinated
intent/revision/sequence/idempotency protocol, authoritative ACK and Hive
reconciliation, replay/tombstones, partition restrictions, money/close safety,
and operator handover with uncertain-outcome reconciliation before cutover.
There must be no interval permitting independent POS operational writers.

## Development contract

macOS runs disposable NestJS/PostgreSQL provisioning, one Go Edge/SQLite, and
two separate simulator processes/state directories/terminal UUIDs. Generated
Dart also has an isolated client package, outside production Flutter. The
harness must prove authenticated Cloud binding, two identities, pairing/replay,
bad credentials, wrong Venue, version refusal, concurrent streams, graceful and
crash restart, reconnect and schema rejection. Never use `vankisi_database`.

Pure-Go SQLite and platform-neutral paths/locking keep Windows builds possible.
Windows runtime, service manager integration, ACL provisioning, certificate
distribution/firewall and physical hardware remain release validation work.
No printer, updater, fiscal or hardware code belongs in this phase.

`apps/venue-web`/BOG remain the custom one-restaurant website. The generic SaaS
website is unbuilt. Its future path stays Website → Cloud → durable Venue command
→ Edge → POS, with payment-provider callbacks and merchant authority in Cloud.


## Implemented entry points and rollout

See `apps/edge/README.md` for pinned tooling, generation, CLI, simulator and recovery
commands. Cloud registry: `EdgeFoundationInstallation` with immutable `id`,
`venueId`, unique `publicKey`, `createdAt`, `revokedAt`. No Device or business row
is created by registration. Platform routes live in
`apps/backend/src/edge-foundation/edge-foundation.ts`; registration/grant auditing
is transactional. The additive PostgreSQL migration is
`20260923120000_edge_foundation`; no historical operational backfill is performed.
Normal deployment requires migration first; provisioning additionally requires a
Cloud Ed25519 signing key. No production provisioning/deployment is implied here.

Local tables are installation, pairing_ticket, terminal, session and the migration
ledger. Local schema starts at 1. Store locks are host-local: cloned directories
on two hosts are not detected, another reason foundation credentials grant no
operational authority. Pairing/revocation CLI requires a stopped service; this is
an explicit Phase 1 operator boundary, not an online admin API.

TLS trust is an operator-distributed certificate pin. The standalone Dart consumer
handles macOS rejection of a self-signed certificate by comparing exact DER bytes,
expected authority and validity dates; different pins are refused. No general
bad-certificate bypass or insecure gRPC option is implemented.

## Exact Phase 2 prerequisites

1. Add explicit Cloud selection of one active operational Edge per Venue and an
   authority epoch, distinct from both foundation registration and POS Device
   enrollment. Define local/Cloud stale-epoch rejection and manual fencing of the
   previous host. No timer-based promotion or implicit leader election.
2. Define canonical Order/Table IDs and mutation envelopes: originating terminal,
   request ID, expected revision, authoritative Venue sequence, durable result and
   tombstone rules. Prove concurrent edits yield one accepted revision or an
   explicit conflict; retries never duplicate a side effect.
3. Keep business validation in Flutter. Specify where its validated intent becomes
   durable, what Edge ACK guarantees, when Hive commits/reconciles, and how a client
   recovers after losing an ACK or restarting mid-commit. No dual independent writers.
4. Prove reconnect catch-up/snapshot/replay, bounded retention, compaction and schema
   upgrade/rollback paths. A lagging terminal must not upload a stale authoritative
   full snapshot or erase another terminal's accepted work.
5. Define Edge-unreachable/LAN-partition behavior per operation. Preserve useful
   offline terminal UX without accepting unsafe concurrent table/order/payment or
   close intents. Do not promise automatic merging of independently operated Hive.
6. Preserve money integrity: sale/closure identity, payment/advance/refund/restore
   semantics and crash reconciliation must be exercised before any related cutover.
   Do not move payment-provider callbacks, Cloud inventory valuation or SaaS policy.
7. Prove old POS stopped, correct Hive data seeded, pending Cloud commands and local
   execution journals reconciled, and old authority fenced before explicit cutover.
   Define rollback with no simultaneous Phase 0 POS and Phase 2 Edge writers.
8. Test actual Windows POS/Go coexistence, local permissions, TLS/pairing distribution,
   restart/service lifecycle, backup/restore and disk failure. Add terminal credential
   rotation/online administration and certificate lifecycle before unattended rollout.
9. Maintain compatibility with existing Cloud snapshot/command contracts. Cloud
   command execution consolidation/durable Cloud outbox remains its separately
   authorized phase; foundation bootstrap grants must never become Device credentials.
