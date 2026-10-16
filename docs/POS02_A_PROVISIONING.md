# POS-02.A — Production printer provisioning

**POS-02.A: DONE. Overall POS-02: NOT_DONE.** The production issuance and
verification boundary is implemented and tested. No production credentials were
created, service installed/activated, printer contacted, or Flutter writer changed.

Evidence: [proof JSON](proofs/POS02_A_PROVISIONING_2026-10-09/proof.json) and
[raw proof packet](proofs/POS02_A_PROVISIONING_2026-10-09/README.md).
The accepted [printer architecture](VYNIC_PRINT_ARCHITECTURE.md) is unchanged.

## A. What was already implemented

Device credential authentication derives Venue authority from the server's Device
registration. The existing provisioning package validates printer-only candidate
grants against separately trusted state. TLS 1.3, the held local agent, station
catalog, fixed-controller model, normalized queue storage and physical safety
holds already existed. Foundation/isolated-proof authority remains separate.

## B. What was missing

There was no production printer issuer, Device-to-Go enrollment, durable production
inventory, signed Venue configuration, persistent grant high-water/revocation
cache, or production-purpose peer authorization. Candidate fixture signatures did
not provide these properties.

## C. What was implemented

The backend now registers independent Go identities through an existing
Device-authenticated HTTP endpoint, verifies private-key possession, publishes
operator-authorized configuration, issues signed Venue snapshots, and revokes
installations. Additive PostgreSQL records retain registration and configuration.

Go now provides `OpenProduction`, `Pull`, `Apply`, `Inventory`, `TLSConfig`,
`Authenticate`, and `Authorize`. The separate `printer-provision` executable makes
initialization, renewal and status runnable without starting a print service.
The existing candidate validator remains separate; exact-body signing, SHA-256,
strict JSON validation and the existing station model are reused. Production
purpose/domain are different from candidate, Foundation and isolated proof.

## D. Device / Go / Venue identity model

- POS Device and its existing POS installation retain their current lifecycle.
- Each new Go installation generates a fresh UUID, Ed25519 key and self-signed
  client/server certificate. Its production URI is
  `spiffe://vynic-printer-production/<installationId>`.
- Backend Device authentication supplies Venue and Device. Enrollment does not
  accept either as tenant authority in request JSON. The proof signs the Device
  UUID, Go UUID and certificate digest under a dedicated enrollment domain.
- The registration binds Go UUID, key, certificate digest, Device and Venue
  immutably. A composite Device/Venue foreign key prevents cross-Venue rows.
  Only one non-revoked Go installation may bind a Device. Replacement requires
  explicit revocation, a fresh Go identity and deliberate controller configuration.
- A dedicated FULL/WAL SQLite store retains the identity and authorization cache.
  An exclusive file lock prevents two owners of that store. Windows binds it to
  MachineGuid; the key uses current-principal DPAPI. A protected directory DACL
  permits the current principal, SYSTEM and administrators. A different principal
  cannot silently recover the DPAPI identity.
- Identity lives outside POS/Hive backup data. Existing portable POS restore
  excludes Device credentials/installation settings; this stage does not alter
  that code. No Go identity-import API exists. A restored fresh installation uses
  a newly enrolled Device and newly generated Go identity. Foreign-machine or
  changed-Device reuse is refused; corrupt stores never silently initialize over
  an old identity. Full OS/VM clones containing the same MachineGuid, DPAPI secrets
  and state are not distinguishable by this software alone and are unsupported
  as fresh installations; revoke and freshly enroll them.

## E. Signed configuration contract

`SignedGrant` carries base64 exact body bytes and a base64 Ed25519 signature.
The signature input is UTF-8 `vynic/printer-provisioning/production/v1\0` followed
by SHA-256 of those body bytes. Verification never reserializes signed JSON.

The v1 body contains `purpose=VYNIC_PRINTER_PRODUCTION`, Venue, stable cluster UUID,
monotonic issuance `generation`, configuration `revision`, issued/not-before/expiry
seconds, `offlineMaxSeconds=604800`, topology, complete member inventory and
base64 `catalogRaw`. The existing station Catalog supplies Venue/revision,
logical stations and LOCAL owners, routes, physical printers, capability profiles,
business routing and explicit controller/Go/Device bindings. Empty `catalogRaw`
means enrolled without configured print rights.

Generation advances transactionally on each issuance. Configuration revision
advances only through an operator CAS publication. A retry reuses exactly the
registration, while receiving a newer bounded grant; it does not mint another
installation. The cluster UUID and configured voter list survive enrollment and
ordinary refresh. Go persists the accepted generation, revision, exact signed
snapshot, revoked-member tombstones and observed time before returning authority.
Same-generation differing bodies, lower generations/revisions and unversioned
configuration changes are rejected.

Issuer private material is required explicitly in
`PRINTER_PRODUCTION_SIGNING_KEY_PEM`; absent, invalid or reused configured Foundation
signer fails closed. The Go Ed25519 public-key pin is supplied independently by
trusted deployment, never learned from the enrollment response or LAN. No key,
certificate or Device credential in the proof packet is production authority.

## F. Authenticated enrollment

`POST /edge/printer-provisioning/enroll` uses `EdgeDeviceGuard` and
`X-POS-Sync-Key`, then rechecks active Windows Device/active Venue inside the
transaction. Venue and Device rows are locked through issuance to order concurrent
revocation. An Ed25519 signature proves possession of the presented certificate
key. The certificate must use the production installation URI, correct key,
client/server EKUs, valid lifetime and canonical DER/base64. Registered Foundation
keys/identities are rejected.

The endpoint also renews and pulls the latest authorized peer inventory. Clients
never choose or publish their Venue configuration. Cloud makes no LAN connection.
The Go pull client requires HTTPS/TLS 1.3, refuses redirects and does not persist
the Device credential. The CLI reads that credential only from a caller's pipe;
it does not accept a secret in command-line flags.

Platform mutation authority guards:

- `GET /platform/venues/:venueId/printer-provisioning` — current inventory/config.
- `POST .../configuration` — `expectedRevision` plus validated configuration.
- `POST .../installations/:installationId/revoke` — idempotent scoped revocation.

Configuration and explicit revocation are audited in their transactions. An audit
write failure rolls publication back. Existing Owner/Platform PREPARED printer
settings and POS enrollment/business primary remain unchanged. This substage adds
no customer UI and no activation API.

Example provisioning executable flags, with independently deployed public key
and the service's dedicated state directory:

```text
printer-provision.exe -action init -state-dir <directory> -device-id <Device UUID> -issuer-public-key <public PEM>
printer-provision.exe -action pull -state-dir <directory> -device-id <Device UUID> -issuer-public-key <public PEM> -cloud https://<trusted-api-origin>
printer-provision.exe -action status -state-dir <directory> -device-id <Device UUID> -issuer-public-key <public PEM>
```

`init` prints only public enrollment material. `pull` reads the existing Device
credential from stdin. Use the same eventual service principal for identity
creation and reuse. This tool does not register or start a Windows service.

## G. Membership representation

Authorization, replica role and physical controller assignment are independent:

| Property | Meaning |
| --- | --- |
| `authorized=true` | Server-enrolled, currently allowed member within the grant validity window |
| `role=CLIENT` | Authorized participant without a quorum vote |
| `role=VOTER` | Configured full replica, never a witness-only participant |
| Catalog controller binding | Particular Go/Device may control particular physical routes; no leadership implication |

New POS installations join as clients. `LOCAL_ONLY` has zero voters;
`SINGLE_REPLICA` has one explicit full data host (standalone for one POS, fixed
shared mode for two, no automatic failover guarantee); `THREE_REPLICAS` has three
explicit full voters. Four, ten or more POS normally use those same three voters
plus clients. The initial inventory limit is 256 registrations including revoked
history; exhaustion refuses enrollment rather than dropping identities.

The backend never elects, promotes or removes voters in response to discovery or
absence. Revoked voters remain represented until a controlled configuration update;
revocation does not silently reduce quorum. No business master is designated by
this printer flow. The existing restaurant operational primary is untouched.

Endpoint hints are numeric addresses in signed configuration. Authentication uses
TLS 1.3 proof of the exact pinned certificate/key and current Venue membership,
not an address or discovery result. Both sides authenticate. Existing-session
operations recheck current cached authorization through `Authorize`.
A client cannot manufacture `AuthenticatedMember` from job JSON. Shared station
rights are Venue-bound; LOCAL rights require the owner Device; controller rights
require the configured Go installation. There is no physical I/O permit here.

Publication rejects foreign/unregistered controllers, invalid LOCAL ownership,
unregistered voters, incompatible routes, unsupported profiles and automatic RAW
failover. Historical physical-id/endpoint/controller bindings are retained: even a
later configuration cannot silently transfer an existing RAW printer to a new
controller. A separately qualified cutover must eventually handle replacement.

## H. Offline / revocation behavior

An already authorized installation can validate cached configuration and peer
rights without Cloud for **at most seven days from issuance**, using a trusted OS
clock. Renewal should be attempted while online before expiry; scheduling belongs
to the subsequent runtime integration. Expiry fails closed for new authorization;
it does not delete jobs or authorize replay. No business entitlement gates renewal.

Server revocation denies renewal immediately. Other installations learn it on
successful signed refresh; they deny that member on new TLS handshakes and on
subsequent authorization checks of existing connections. Learned revocation is
persisted, survives restart and cannot be undone by replaying an older grant.
Device disable/revoke also marks the Go registration revoked when inventory is
next refreshed; re-enabling a Device cannot resurrect that observed registration.

A disconnected peer cannot know a newly issued revocation. Until it learns the
revocation, its old authorization remains valid only until the signed expiry.
This explicit seven-day exposure is the offline policy, not instantaneous Cloud
revocation. Clock rollback below the last persisted observation refuses authority.
The store assumes a trusted OS clock and protected service storage; it is not a
TPM monotonic counter and does not resist an administrator restoring an entire
older OS/identity-store image. Fresh-install restore must never import that store.

## I. Real DB / HTTP proof

The final run passed **16 new HTTP/PostgreSQL integration tests**, plus **160
existing PREPARED configuration regressions** (176 total), plus 16 local-only
delete-guard/matrix tests. No mocked database,
Device guard or Platform guard was substituted. Disposable signer/JWT/Device
credentials and separate `pos02a_provisioning` / `pos02a_upgrade` databases ran on
a newly initialized loopback PostgreSQL 17 instance, then that instance stopped.
No connection to `vankisi_database` or active restaurant storage occurred.

The tests cover correct Venue/Device/Go binding, proof possession, forbidden tenant
input, wrong principals, missing/shared-purpose signer, Foundation identity reuse,
concurrent retry, cross-Venue rebind, authorized publication, configuration rights,
audit rollback, stale CAS, ownership-transfer refusal, a fourth POS joining the
same inventory without voter changes, installation/Device revocation and the
composite tenancy FK. Backend-issued grants are passed directly to Go for signature,
durable-cache, actual mutual-TLS, station-authority and revocation verification.

Fresh migration deployment and a populated previous-tip upgrade both pass.
The populated upgrade preserves the existing Device UUID, POS installation UUID,
credential verifier and runtime JSON byte-for-byte, and creates no grants.
Prisma validation passes. Schema comparison has **no POS-02.A difference**; it
retains two pre-existing `DevicePrinterRuntimeRequest` foreign-key rename
suggestions from earlier WIP. Those unrelated names were not changed.

## J. Go integration proof

- **268 passing test/subtest cases** across provisioning, held local agent and
  daemon regressions; three optional/platform test skips. The CLI package
  compiles and contains no separate unit tests.
- **24 passing production test/subtest cases under the race detector**; two
  optional real-backend fixture entries skipped in that run and executed
  separately by the real HTTP test.
- Both real-backend export/verify tests pass with no skips. Go consumes the exact
  signed HTTP body and authenticates actual loopback TLS peers before checking
  station/controller rights and learned revocation.
- **25 native Windows ARM64 cases pass**, including MachineGuid access,
  current-user DPAPI, directory DACL application, restart, real subprocess exits,
  cached high-water preservation, mutual TLS, stale/expired/foreign/tampered
  grants, clock rollback, fixed-controller rights and 1/2/3/4/10-POS representations.
  Two backend-exchange helpers are intentionally skipped in the Windows-only run.
- Go vet, formatting, TypeScript compilation and lint of the provisioning TypeScript
  sources (including tests) and changed module/deletion registration pass. The Windows provisioning executable also cross-builds.

Native Windows ran under the interactive test user, not an installed SCM service.
No printer I/O was performed. The VM is returned to its original stopped state.
The initial malformed empty-catalog fixture, initial lint findings and the
PowerShell argument-quoting failure are documented separately from final passes.

## K. Schema changes

`20261018120000_printer_provisioning` adds `PrinterInstallation` and
`PrinterVenueAuthority`, a composite unique Device `(id, venueId)` key and matching
FK, plus a partial unique index allowing only one active Go registration per
Device. The existing local-only deletion matrix classifies both new Venue-owned
tables before Device deletion; no reset was executed. No previous migration is rewritten. No existing Device/operational
membership is migrated, activated, or backfilled. Deployment to restaurant or
production databases is **NOT_RUN**.

Go's dedicated authorization store has identity and authorization tables. It does
not change the queue schema, restore old Foundation databases, or migrate Hive.

## L. Remaining limitations

Actual service/installer onboarding, credential handoff from the POS, automatic
renewal, distribution/rotation of production signer pins, service-principal/SCM
boot qualification, peer RPC/Raft wiring, runtime membership reconfiguration,
controller durability, Flutter admission, cutover and physical qualification are
later substages. A valid configuration is authority data, not service activation.
The public-key trust anchor must be deployed independently; no production keys
were invented or provisioned here. Certificate replacement requires fresh
registration; there is no in-place key-rotation API. The issuer initially accepts
canonical private/loopback/link-local IPv4 TCP routes and exact Windows queues.

Controller replacement of an already registered physical printer is deliberately
refused pending a qualified drain/cutover protocol. No RAW takeover or automatic
physical failover was added. Authorized topology is represented and authenticated;
this stage does not claim that live Raft membership changes are implemented.

## M. Files and commits

Production backend entry points: `apps/backend/src/printer-provisioning/` and the
existing Edge/Platform module registration. Additive schema/migration are under
`apps/backend/prisma/`. Go production additions are
`apps/edge/internal/printerprovisioning/production*.go` and
`apps/edge/cmd/printer-provision/main.go`. Focused documentation updates cover this
report, architecture status, project state, code map, the provisioning policy
in decisions and the roadmap. Exact hashes/change inventory are in the proof.

Branch/HEAD remain `codex/docker-deployment-foundation` /
`3463ee406184fec7f53818416e11d0e5f5602c87`. **No commit was created.** This boundary
depends on pre-existing, uncommitted printer packages and module/schema WIP;
including that work would exceed a focused POS-02.A commit. No reset, stash, push,
secret-file edit or unrelated change was made. Existing historical proof packets
remain unchanged.

## N. Final POS-02.A status

**DONE — production issuance and verification boundary implemented and proven.**
This status covers source/API behavior with isolated real infrastructure and
native Windows identity tests. It does not assert deployed credentials, service
activation, runtime print admission or paper delivery. **Overall POS-02 remains
NOT_DONE.**

## O. Exact next substage

**POS-02.B — authenticated Venue peer transport and stable queue-membership
wiring.** Consume this production cache and TLS identity in peer RPC/Raft;
revalidate rights on operations, connect clients to configured replicas, and
prove foreign/revoked/expired peer rejection plus controlled membership/rejoin
without discovery-driven promotion or physical-controller transfer. Keep Flutter
and physical writer activation held. POS-02.B was not started in this task.
