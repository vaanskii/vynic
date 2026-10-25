# Beta subscription licensing — source qualification

This is a local, uncommitted beta change based on `bf7bd647` on
`codex/offline-subscription-lease`. It does not publish, install, deploy, migrate
production data, configure Cloudflare, or promote stable. The original dirty
checkout and the operational POS were not used for implementation or testing.

## Authority and protocol

`POST /edge/subscription-lease` uses the existing `EdgeDeviceGuard` and
`Device -> Venue` relationship. The server reads the Device's installation ID;
request tenant/device/installation IDs are not authority. Under the existing
Venue commercial lock it calls `commercialState`, so central trial approval,
trial history, plan capabilities, suspension and cancellation remain authoritative.
No client starts, extends or resets a trial. No schema migration is added.

The response signs the exact UTF-8 JSON payload with Ed25519. The envelope carries
base64 payload/signature; claims include version, Device, Venue, installation,
32-byte request nonce, authenticated server issue time, commercial kind/status,
commercial expiry and the absolute lease deadline. Deadline is the earlier of
server verification + 24 hours and the known trial/paid-period end. Existing
manual/legacy agreements with unknown period end retain that server policy, with
at most a 24-hour offline lease; the client does not invent a paid end date.

The POS pins a raw public key at build time. It verifies signature, types,
identity, nonce, maximum duration and the commercial cutoff before using the
response. Requests use fresh cryptographic nonces and a 15-second HTTP timeout;
responses with more than 30 seconds elapsed transit are rejected. A replay cannot
renew a lease, including after restart or reinstall. A normal app close/reopen
**can continue offline during the same OS boot**, using the original deadline.
The app reads the current signed envelope and original request-time anchor from
macOS Keychain or Windows Credential Manager, verifies the signature again, and
checks Device/installation/Venue, credential/public-pin fingerprint and boot ID.
Neither the issue time nor the elapsed anchor is reset. Time closed and suspended
continues to consume the original allowance. No positive lease is loaded from
Hive, portable backups or ordinary application files.

The clock anchor uses signed server time plus native elapsed time, conservatively
including the full request transit. macOS uses `mach_continuous_time` with the
read-only `kern.bootsessionuuid`; Windows uses `GetTickCount64` with the boot GUID
from dynamically resolved `NtQuerySystemInformation(SystemBootEnvironmentInformation)`.
Both elapsed clocks include sleep; Dart `Stopwatch` is not used. Every guarded
operational action checks the clock. A changed/missing boot ID, backwards elapsed
reading, missing/malformed/locked vault record, identity or trusted-pin change,
or wall-clock rollback exceeding the 2-second tolerance requires online
verification. Wall progression is compared to elapsed progression from the
original accepted sample as well as the previous sample, so repeated small
rollbacks cannot cumulatively reset the allowance. Clock advancement cannot
extend the signed deadline. Reboot continuity is never guessed.

The current protected record is replaced on a fresh verified response or a
restriction, with serialized writes preventing stale success from overtaking a
received denial. The vault holds the actual current record, not a key for an old
replayable file. Startup and in-flight verification also check a denial generation.
Legacy device-local negative settings remain a conservative fallback; they cannot
grant sales. A valid restored session does not rewrite its anchor on startup.
Missing/unavailable protected storage fails closed for a new positive session.

Native references: [Apple continuous time](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time),
[Apple boot-session sysctl source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c),
[Microsoft elapsed clocks](https://learn.microsoft.com/en-us/windows/win32/sysinfo/windows-time),
[Credential Manager bounds and persistence](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentiala).
The Windows boot-information class is an internal OS interface; Microsoft warns
that [NtQuerySystemInformation can change or become unavailable](https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntquerysysteminformation).
The implementation fails closed rather than guessing a boot ID. Its compatibility
must be qualified on supported Windows builds before shipping; Mac evidence is
not a Windows compatibility claim.

Transport failures, malformed responses and server 5xx leave a still-valid lease
usable only to its original deadline. Signed EXPIRED/REVOKED decisions and
confirmed 401/403 authentication failures restrict immediately. Runtime-config
authentication rejection also revokes the separate license. An older in-flight
successful response cannot clear a newer authentication rejection. Received
negative decisions survive restart and portable restore; successful fresh online
verification may clear them. Early remote cancellation cannot be learned while
fully offline: it becomes effective on a confirmed response or the original
lease/entitlement deadline. No claim is made against administrator patches,
modified executables, arbitrary same-user code that can modify the credential
vault, OS/vault rollback or full VM snapshots. Copying ordinary restaurant/app
files does not restore a positive lease or erase the vault's received denial.
If **both** protected and local storage cannot persist a received decision, the
current process remains restricted and reports a storage fault, but persistence
across a crash cannot be guaranteed; no software can durably save to unavailable
storage. This is distinct from a normal network outage.

## Operational admission and data preservation

Licensing starts only in POS startup; Manager and isolated tests do not implicitly
enable it. `UpdateReadiness.mutate` retains its existing local transaction gate,
then checks sale-producing operations. Creation, edits, reservation activation,
new advance receipts, cancellation, reopen and table/item transfers are covered.
An already admitted transaction may finish. Its scoped permission expires when
its callback finishes and cannot authorize a delayed asynchronous sale.

A verified session durably checkpoints hashes of active bill images under the
current Device/installation/Venue binding. These device-only settings are excluded
from portable backups and preserved at the destination during restore. Restricted
settlement requires an exact unchanged bill hash, matching gross and advance,
and matching sale items (including package items). A new/restored/edited bill is
not eligible. The settlement entitlement is consumed durably after the closure
journal starts and before its Sale is written. Existing journaled closes/recovery
remain idempotent. A failed checkpoint fails closed; existing records remain for
online revalidation and controlled recovery.

The narrow exemption is in `CloseTableTransaction`, not a UI flag. Selecting
“Records and existing bills”, pressing Back, or dismissing a payment dialog cannot
authorize new sales. History, export, transport, menu/sale evidence sync and
existing recovery paths remain available. Close Day retains its original
active-order guard. Nothing rewrites history or fiscal classification.

The nonfiscal grant is a separate decision. Its earlier 15-minute outage lease is
not restored. It stays default-off unless explicitly granted, retains received
revocation, and is checked independently at internal close. The ordinary gross /
advance / collection invariant remains 1000 / 100 / 900.

`TablePaymentService` records operator-confirmed cash or external bank-terminal
tender. It does not execute a card authorization API. Offline licensing does not
make a disconnected bank terminal/provider work and does not create a billing
provider or automatic checkout integration.

## Customer experience

The existing POS theme and Georgian/English locale are used. EXPIRED, REVOKED and
VERIFICATION_REQUIRED have different messages; connectivity is not called unpaid.
An automatic restriction surface offers Retry verification, Purchase / renew,
and access to records/unchanged existing bills. The existing Navigator/drafts are
retained beneath it. Busy retry/purchase actions cannot be double-submitted.

Verification refresh runs once per minute; UI/clock checks run once per second
and again at operational actions. Warnings start within 72 hours of known
commercial expiry, within one hour of offline deadline, or immediately when a
verification request fails. The offline countdown shows hours/minutes/seconds.
The external browser opens only on a user click, to `https://vynic.ge/pricing`.
The existing public route points at the contact section; this change does not
invent a checkout URL. Embedded browser and AI assistant are deferred.

## Rollout gates — not performed

1. Approve a separate licensing Ed25519 production key and its custody/rotation
   plan at action time. No persistent production key was generated or configured.
2. Configure backend `VYNIC_LICENSE_SIGNING_KEY` with the Ed25519 PKCS#8 PEM in
   the secret store. Pin the corresponding raw 32-byte public key as base64 via
   Flutter `--dart-define=VYNIC_LICENSE_PUBLIC_KEY=...`. Never ship the private
   key, reuse release-signing credentials, or put secrets in the repository.
3. Use the enrolled-device HTTPS API origin. Missing/unusable signer or public
   pin fails closed. Coordinate key rotation with a new beta client; this version
   has one pinned key, not a remotely replaceable trust root.
4. Qualify the real Windows binary, Credential Manager and boot GUID on every
   supported Windows version, Win32 sleep/hibernate/resume, reboot and
   network transitions, installer/enrollment, and provider/manual tender workflows
   on an isolated restaurant fixture. Mac source/preview proof does not establish
   Windows binary/device qualification. Qualify stable macOS code-signing identity
   and Keychain access through an update; denied/locked access requires online
   revalidation after access is restored. Vault records are non-roaming and bounded
   to 2,560 bytes; no licensing private key is stored in them.
5. Run deployment/real PostgreSQL integration against a disposable approved
   environment before release. Current endpoint HTTP tests stub persistence;
   no production migration or database was accessed.
6. Review the known baseline regression failures and the existing protected
   artifact delivery 403 separately. None is silently accepted for stable rollout.

No commit was created: repository instructions require an explicit commit request.
Local comparison/merge can use this checkout; nothing was pushed.

## Validation evidence

See `docs/proofs/OFFLINE_LICENSE/` for focused and aggregate logs, static analysis,
backend/native build logs, and synthetic Georgian screenshots at 1024×768,
800×600 and 480×480. A separate `/tmp/VynicLicensePreview.app` used the unique
`ge.vynic.license.preview` identity, ad-hoc test signing and the synthetic
`tool/license_preview.dart` entry point: no database, enrollment, HTTP or POS
startup. Native clock success was observed and the real native UI inspected.
The temporary preview was then stopped; no operational process was restarted.
The restart revision additionally compiles the exact `LicenseNative` helper and
runs separate synthetic native processes to write an anchor, confirm same boot
and increasing elapsed time, overwrite with revocation, and confirm that denial
in another process. `tool/test_license_native_continuity.py` always deletes its
random test Keychain account; its successful cleanup is logged. Hardware reboot
and machine suspend were not performed on the user's working Mac.

Final counts and baseline comparison are recorded in `docs/proofs/OFFLINE_LICENSE/RESULTS.md`.
