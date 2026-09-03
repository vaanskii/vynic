# Device Identity Foundation

Step 3A introduces one server-authenticated POS installation identity without
introducing tenancy. This document records the identity boundary before the
implementation so later phases do not collapse unrelated concepts together.

## Existing identity inventory

| Existing concept          | Purpose                                                                            | Identifier                                                             | Persistence                                           | Security role                                                                               | Current consumers                                 | Reuse decision                                                                                                       |
| ------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Developer terminal        | Human-readable target for offline developer unlock tokens                          | `developerTerminalId`, a venue slug plus five random base32 characters | POS Hive `settings` box                               | Binds an Ed25519-signed support token to one POS; it does not authenticate network requests | POS developer panel, CLI signer, Unlocker devtool | Keep unchanged as a support-token target; do not use as a Device credential or authoritative installation identifier |
| Developer licence/token   | Temporarily grants developer-panel scopes such as diagnostics, backup, or recovery | Signed token `jti`; optional `terminal` claim                          | Token is portable; active unlock state is memory-only | Offline authorization/entitlement verified with the public Ed25519 key shipped in the POS   | POS developer access and devtool                  | Keep distinct from Device authentication                                                                             |
| Developer one-time code   | Short-lived offline developer-panel access                                         | Hash-chain position                                                    | POS Hive `settings` stores the spent-chain tip        | Offline support authorization                                                               | POS developer access and devtool                  | Keep distinct from Device authentication                                                                             |
| Push device               | Routes manager push notifications                                                  | FCM token                                                              | PostgreSQL `PushDevice`                               | No POS sync authentication role                                                             | Manager mobile notification services              | Do not reuse; it represents a notification subscription, not a POS installation                                      |
| POS callback registration | Lets the server call the currently connected POS                                   | Callback URL and connection key                                        | PostgreSQL `Setting` plus in-process registry         | Protects server-to-POS callbacks; it does not identify the POS to the server                | POS callback client/outbox                        | Keep unchanged                                                                                                       |
| Legacy POS sync key       | Shared authentication for all POS-to-server sync calls                             | `POS_SYNC_API_KEY` sent as `X-POS-Sync-Key`                            | Server/POS environment or Dart define                 | Authenticates the deployment, but cannot identify a concrete installation                   | `PosSyncGuard`, POS sync clients                  | Preserve as a deprecated transition path                                                                             |

## Identity decision

**Device** is the one persistent server principal representing a concrete Vynic
POS installation. It owns a stable, high-entropy `installationId`, a database
identity, a credential verifier, status, metadata, and audit timestamps.

**Terminal** remains the existing human-readable developer-support label. It is
not a second server domain entity. Its random suffix is designed for reading over
a phone call, not for authentication entropy.

**Installation** is an identity attribute of Device, not another entity. A
future provisioning flow will persist it locally once in the existing POS Hive
settings store. Step 3A does not add that client provisioning flow because doing
so safely depends on later onboarding decisions.

**Licence** remains offline, signed authorization for developer capabilities.
It answers what a support session may do, not which installation is connecting
to the sync API.

No `Terminal`, `Installation`, `Machine`, `Organization`, or `Venue` model is
created. No operational record receives a `deviceId` or `venueId`.

## Transitional authentication boundary

Both authentication modes use the existing `X-POS-Sync-Key` request header so
deployed clients and the route/CORS surface remain compatible:

```text
legacy shared key --------------------\
                                       > PosSyncGuard -> typed POS auth context
versioned Device credential -> verifier/
```

The Device credential contains a public Device id for indexed lookup and a
high-entropy secret. PostgreSQL stores only an Argon2id verifier. The guard
loads the Device, verifies the secret, rejects non-active Devices, and only then
publishes the authenticated Device id. A caller-supplied id alone is never an
identity.

`lastSeenAt` is updated at the guard/verifier boundary after successful Device
authentication. Updates are throttled so normal high-frequency sync does not
write on every request. Snapshot services remain unaware of HTTP headers.

## Deferred provisioning

Step 3A exposes server-side credential issuance only to application/test code;
it deliberately adds no public provisioning endpoint or device-management UI.
Production provisioning must be designed with Venue onboarding in a later
phase. The raw secret is returned once at issuance and cannot be recovered from
the stored verifier.

**Resolved in Phase 1C.** Onboarding is now a one-time, Venue-bound enrollment
code redeemed at `POST /edge/enroll`; the raw credential is minted by the server
and never passes through a person. `installationId` gained its purpose there: it
is what makes a reinstall rotate an existing Device rather than create a second
one. Everything above about the credential itself is unchanged — one issuance,
verifier only, rotate rather than recover. See
[POS_ENROLLMENT.md](./POS_ENROLLMENT.md).
