# Printer-agent authority boundary

This package implements an authenticated, loopback-only printer infrastructure
API. `Health` observes the current host and retained queue holds. `SubmitLocal`
validates immutable v1 job bytes and configured identity/revisions;
`GetLocalResult` validates immutable lookup identity. Both return
`FAILED_PRECONDITION HELD_PROVISIONING`, without creating a job, result, effect,
claim, attempt or successful receipt. Physical dispatch is separately `HELD`.
Infrastructure readiness does not mean printing readiness.

The client certificate registry authorizes local observations only. Its exact
DER pin, TLS 1.3 chain, canonical host/client URI, purpose and current validity
are checked on every RPC. The server leaf's validity is also checked on every
RPC, including established channels. Dart uses an explicit out-of-band leaf
pin, empty trust roots and exact DER/time/SNI verification; the Go server
constructor preflights its sole server-auth purpose and SAN. Neither side
generates, discovers, enrolls or installs a production credential.

## Distinct installations

The readonly client profile has eleven exact keys. Its
`currentDeviceInstallationId` names the current Flutter Device enrollment
installation. `pins.installationId` names the distinct Go service/Foundation
installation. They may differ; the real cross-language fixture intentionally
uses unequal UUIDs. The UI rechecks the former against the current Device
credential getter and checks all server pins against the latter. These context
checks establish neither signed Device authority nor a terminal/origin
registration. There is no implicit identity rewrite.

## Existing authority does not supply the admission bridge

The following source was inspected without changing it. Backend paths refer to
the original monorepo, which is not part of this detached source export.

| Existing source | Present authority | Missing printer admission claim |
| --- | --- | --- |
| `apps/backend/src/auth/device-credential.service.ts` (`DEVICE_CREDENTIAL_PREFIX`, `formatCredential`, `verifyCredential`) | Cloud verifies the opaque `vynic-device-v1.<Device UUID>.<secret>` against the server-held Argon2id verifier and current Device/Venue state. | No offline signed Device-to-Venue certificate, host/terminal/origin binding or current offline revocation record. |
| `apps/backend/src/edge/device-enrollment.service.ts` (`present`) | Returns Device installation, Venue and opaque credential fields after Cloud enrollment. | No signed local printer-service installation, certificate or terminal/origin registration. |
| `apps/operations/lib/core/services/edge/edge_device_credential_store.dart` (`venueId`) | The Venue getter is expressly display-only; the raw credential is for the Cloud `X-POS-Sync-Key` header. | A local getter or profile UUID cannot grant production tenancy. |
| `apps/backend/src/edge-foundation/edge-foundation.ts`, `apps/edge/internal/store/identity.go` (`Grant`) | Signed `vynic-edge-foundation` / `FOUNDATION_ONLY` installation, Venue and public-key binding. | No Device, terminal, origin, route, physical alias or production printer permission. |
| `apps/backend/src/customer/printer-runtime-config.ts`, `printer-runtime-persistence.ts`; `apps/operations/lib/core/services/printing/cloud_printer_runtime.dart` | Authenticated HTTP v2 Device/Venue route preparation, retained as `PREPARED` until controlled activation. | No offline signed Go-host/service-installation/terminal/origin registry, protected authorization high-water mark or cutover attestation. |
| `apps/edge/internal/store/operational_authority.go`, `operational_origin.go` | Explicit isolated-fixture signed `ISOLATED_PROOF` operational grants and origin pins. | Proof authority cannot become production printer authority through a role or mode flag. |

## Implemented candidate validation

`Config.Candidate` accepts the separately owned `printerprovisioning.Validator`
interface. It receives freshly authenticated client leaf DER, client ID,
server-owned host pins and the strictly decoded frozen job. The candidate
validator checks an Ed25519-signed printer-only body against separately trusted
current issuer, exact Device/Venue/service-installation/host/terminal/origin
registration, authorization generation/revocation, validity and exact
route/alias/endpoint/profile bytes. It rereads trusted state for each call.

The candidate has no issuer deployment, protected persistent current-state
source, queue admission or dispatch conversion. A valid candidate still returns
`HELD_PROVISIONING` here. This seam demonstrates strict validation mechanics
without inventing an active production enrollment policy or promoting proof
grants.

## Required production bridge

Production admission requires an explicit printer-only issuer/key provisioning
path; current signed Device/Venue plus both installations and terminal/origin
client-certificate registration; a protected persisted authorization generation
and revocation source with a chosen offline freshness policy; authoritative
physical printer/alias/route/config/profile revisions; and controlled cutover
that fences old writers/readers. Those decisions and their actual enrollment
implementation remain pending. Installing a service or qualifying physical RAW
output is a separate boundary and cannot supply this missing authority.

No CLI, profile boolean, sender label or successful health response enables
admission in this API. No normal POS business writer, proof coordinator startup
or legacy print queue is attached by this package.
