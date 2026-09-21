# Vynic Windows first-install bootstrapper

`VynicSetup.exe` implements first install, Update POS, Open, Repair and Uninstall for
**Windows amd64 POS**. It is implemented and cross-built, not Windows-qualified
or deployed. A release owner must supply actual HTTPS endpoints, pinned public
keys, signed manifests/bundles and Authenticode signing. No production URL or key
is invented. No POS/Edge artifact is embedded in the setup executable.

## Installer wizard and update entry point

Fresh installation uses native Welcome -> Destination -> Review -> Install ->
Finish pages, Back/Next navigation, a folder browser and native progress control.
The default is `%LOCALAPPDATA%\Vynic`; a fresh install may select an empty,
dedicated descendant of the current user's LocalAppData. The location is recorded
in HKCU `Software\Vynic\Setup` (`InstallRoot`). Subsequent Setup/host/shortcut
launches resolve that same location. Invalid, linked, reserved and outside-user
paths fail closed; existing/removed installations cannot relocate retained data.
Only one interactive wizard is allowed per user session. No elevation is added.

Existing installations expose **Update POS** separately from **Repair**. Update
connects to Edge and requests a release check/download before opening POS. If
Edge reports an unfinished activation or startup, Setup completes that existing
health gate first and reports the stage plus elapsed time. Download progress uses
Edge's observed bytes: percentage, received/total MB and a determinate native bar.
Unknown totals and startup/manifest checks use a marquee; receiving 100% never
means verification succeeded. A completed download remains on a result page with
**Open POS / Later**. Later leaves the release staged and does not launch/install.
The existing authenticated loopback API and pinned Edge binary are unchanged. POS retains explicit
Update Now consent and its exclusive readiness barrier. Setup never calls the
install endpoint or supplies a made-up readiness result. Repair still restores
the exact installed version and does not upgrade it.

The wizard build displays/logs Setup's own version, distinct from the POS release.
Native Windows behavior remains a qualification requirement.

## Runtime boundary

- **VynicSetup**: first install, same-version repair, application removal,
  per-user logon integration and a minimal local Edge process supervisor.
- **Vynic Edge**: existing POS updater, consent/readiness, install/health/rollback.
- **VynicBootstrap/helper**: future Edge replacement/recovery; not implemented.

The Go installer lives in `apps/edge/cmd/setup` and `internal/setup`. It reuses
`internal/updater` signature/hash/ZIP validation and existing SQLite initialization.
POS signature and readiness contracts remain unchanged. Binary layout 2 adds
a signed bootstrap compatibility declaration and durable updater cleanup state.
`cmd/sign-bootstrap` is an offline publisher, not distributed to POS machines.

The earlier `edge serve` requires a Cloud-signed Venue binding. First installation
has no such binding. New **`edge host`** opens the existing installation identity
and runs only the authenticated loopback POS updater. It does not start gRPC,
issue pairing tickets, select a Venue, authorize business writes, or enable
Phase 2A authority. `serve` still requires binding. The POS's existing Enrollment
Code onboarding establishes Device/restaurant identity; it does not silently bind
the distinct Go foundation identity. Any future LAN binding remains the existing
Cloud grant workflow.

## Installation context and layout

This version is **per-user, unelevated**, under the Windows Known Folder
`FOLDERID_LocalAppData`, not a hardcoded username or environment-derived system
path. It requires the designated interactive POS Windows account. Setup refuses
an elevated token, preventing accidental installation under another administrator
or execution of user-writable releases with administrator rights. Its embedded
manifest requests `asInvoker`. No LocalSystem/session-0 service is installed.

```text
%LOCALAPPDATA%\Vynic\
  bin\VynicSetup.exe                  stable launcher/repair UI/supervisor
  edge\releases\<version>\VynicEdge.exe
  pos\
    current\vynic_pos.exe            complete active Flutter release
    staging\                        one candidate ZIP/tree; temporary setup files
    rollback\                       temporary previous POS until stabilized
    updater.sqlite (+ WAL/SHM)       existing updater schema 1
    updater.lock
  state\edge\edge.db (+ WAL/SHM)     foundation schema 2, identity/TLS keys
  state\edge\edge-cert.pem          public certificate export
  state\host.lock
  state\maintenance                 blocks launch while setup owns maintenance
  state\stop-host                   graceful host stop request
  state\swap.json                   interrupted binary repair journal, temporary
  config\installation.json          receipt/schema 1; retained repair/trust/config
  config\pos-updater.json           existing updater config incl. host token
  logs\setup.log
  logs\edge.log
  staging\                          temporary Edge/setup downloads only
  setup.lock
```

**Restaurant data remains in the POS's existing application-support `Vpos_Data`
location.** Setup never chooses, migrates, backs up, restores or deletes that
location. Preserve the POS product identity/build configuration so the Flutter
runtime resolves the same existing support directory. Edge SQLite and updater
SQLite are separate; neither lives in a replaceable release directory. Within the
`pos` root, mutable SQLite remains outside `current`, `staging` and `rollback`.
Only POS binaries/runtime/assets occupy these replaceable slots. In steady state,
only `current` contains a POS release. One deferred update may remain in `staging`
until explicit Update Now. Logs follow their separate retention policy.

ACLs are protected DACLs granting full control only to the current Windows user,
SYSTEM and Administrators, with container/object inheritance. Setup applies them
before writing secrets and to the extracted tree. Symlinks/reparse points in the
install tree or its ancestors are refused. Other accounts cannot replace keys or
binaries/read host credentials. As in the updater contract, the same Windows user
and local administrators are outside this credential isolation boundary.

## Signed release/download contract

`Distribution` is embedded into an Authenticode-signed release build. A support
operator can explicitly supply the same public JSON via `--distribution FILE`
for a fresh install. It contains exactly:

```json
{
  "bootstrapURL": "https://example.invalid/windows/bootstrap.json",
  "channel": "stable",
  "keys": {
    "release-key-id": {
      "public": "base64-32-byte-Ed25519-public-key",
      "expires": "2027-01-01T00:00:00Z"
    }
  }
}
```

The `.invalid` domain is illustrative and intentionally unusable. The same shape
supports a future release domain without a code change. CDN/object-storage URLs
are signed artifact metadata; NestJS is not required to serve binary bytes.
Nothing contacts the custom venue website/BOG integration.

Bootstrap uses the **same Ed25519 envelope** as POS: `keyId`, base64 `payload`,
base64 `signature`, external pinned public keys and key expiration. A purpose
prefix `VYNIC-BOOTSTRAP-v1\n` separates bootstrap metadata from the unchanged
`VYNIC-POS-RELEASE-v1\n` domain. It is the same crypto/trust implementation, not a
second signing/key-distribution system. The signature covers exact payload bytes.
The POS manifest is the existing signed POS envelope, independently verified.

Decoded bootstrap payload:

```text
product: "vynic-bootstrap"
protocol: 1
posBinaryLayout: 2  # the exact signed Edge artifact supports current/staging/rollback
release: positive baseline sequence
os: "windows"
arch: "amd64"
channel: configured channel
expires: future timestamp, at most 31 days away
edge: existing Manifest-shaped artifact metadata
  product: "vynic-edge"
  version: numeric major.minor.patch
  release: positive release sequence
  os/arch/channel/url/sha256/size/expires: signed artifact properties
  updaterProtocol: 1
  hiveSchema: 9
  edgeSchema: 2
  dataPolicy: "edge2-no-migration"
pos: existing signed vynic-pos envelope (hive9-no-migration)
posFeed: HTTPS current POS manifest URL used by the existing updater
repairBase: HTTPS directory for /<bootstrap-release>.json
posReleaseBase: HTTPS directory for /<active-POS-version>.json
```

The Edge descriptor is authenticated by the outer bootstrap signature. POS's own
signature/policy also must pass. Both artifacts use SHA-256 and exact signed
length. Only HTTPS, bounded metadata (128 KiB bootstrap / 64 KiB POS), at most
5 HTTPS redirects, existing 512 MiB artifact and ZIP expansion limits are accepted.
TLS uses platform roots; tests add only their local HTTPS server's CA. There is no
TLS bypass, unsigned fallback, network-provided trusted key, downloaded script,
MSI, arbitrary entrypoint or user-provided execution command.

Downloads stream to `.part`, flush, verify, and rename into setup staging. A
verified cached ZIP can be reused; partial transfers restart, not execute.
Signatures/key expiry/manifest policy are rechecked after downloads. Both packages
must verify/extract before any active binary replacement. ZIP traversal, reserved
Windows names, symlinks, alternate streams, duplicate names and expansion limits
use the existing updater checks. POS must include `vynic_pos.exe`,
`flutter_windows.dll`, `data/icudtl.dat` and `data/flutter_assets`.

Release publishers must renew signed repair metadata before expiry, retain
immutable artifact bytes and provide signed per-version POS repair manifests.
A same-version manifest must always identify the original immutable release.
Repair pins the installed bootstrap release, Edge version/hash, baseline POS
version/release and original feed locations. It never adopts the latest Edge.
After a POS update, Repair fetches the updater-selected current POS version and
requires its release number not exceed the retained updater high-water mark.
There is no downgrade/reset to the original baseline after an update.

Public-key overlap must be provisioned before key expiration. This phase does not
download trust rotations or rewrite the receipt's trust roots during Repair. A
future explicit trust reprovisioning mechanism is required for a fleet that has
outlived every pinned key. Keep production private keys only in offline/CI signing
infrastructure; neither setup nor Edge/POS contains them.

## Release build and publication

1. Build the normal product-specific Windows POS bundle, including all runtime
   DLLs/plugins/assets and existing updater/readiness integration. Keep its product
   identity and Hive 9 compatibility. ZIP the release directory contents at root.
2. Build Edge from a revision that implements `host` and binary layout 2, into **`VynicEdge.exe`**, and
   ZIP it at root. Use Windows amd64/CGO disabled. The signed `edge2-no-migration`
   declaration requires validation against retained foundation schema 2. Set
   `posBinaryLayout: 2` only for that compatible Edge artifact. Metadata without
   this declaration is rejected before provisioning or migrating POS binaries.
   An older pinned Edge baseline cannot be upgraded by Repair.
3. Authenticode-sign Windows executables as required by the distribution policy
   **before** hashing/zipping. Publish the existing signed POS manifest with
   `cmd/sign-pos-release`.
4. Put that POS envelope into bootstrap metadata and sign it:

```sh
# from apps/edge; all paths are external release inputs
 go run ./cmd/sign-bootstrap \
   --manifest /release/bootstrap-metadata.json \
   --edge-artifact /release/edge-windows-amd64.zip \
   --private-key /secure/offline/release.pem \
   --key-id release-key-id --distribution /release/distribution.json \
   > /release/bootstrap.json
```

5. Publish bootstrap/repair/per-version POS envelopes and artifact URLs on HTTPS
   control-plane/CDN endpoints. The newest bootstrap controls *fresh* installs.
6. Build the GUI setup using the release tool (not a bare `go build`):

```sh
python3 apps/edge/tool/build-setup.py \
  --distribution /release/distribution.json --out /release/VynicSetup.exe
```

The build script embeds the public distribution JSON, generates a temporary
Windows amd64 resource object with an `asInvoker` manifest, strips Go debug data,
and verifies the resulting PE GUI subsystem and relocated resource contents.
The temporary object is removed; no generated resource is hand-maintained.
Authenticode-sign and timestamp `VynicSetup.exe` **after** building it. The build
script does not sign or claim SmartScreen reputation. The fixture cross-build is
about 17.6 MB; no restaurant/Edge/POS release payload is embedded.

## Provisioning and first launch

Setup generates a distinct 32-byte CSPRNG host token (64 hex characters). Existing
`store.Init` generates the persistent installation UUID, signing key pair and TLS
certificate/key. The updater DB is seeded from the verified POS baseline. Secrets,
public trust and config are persisted before application launch.

A stable `VynicSetup.exe --launch` target is used for Start Menu and Desktop
**Vynic POS** shortcuts. HKCU `Run` registers `VynicSetup.exe --host`, which owns
one `host.lock`, starts the pinned Edge baseline in the same interactive session,
redirects logs and retries a failed host at most five times with backoff. It
supervises the baseline; it never chooses/replaces another Edge version.

`Open Vynic` starts the host if necessary, then calls the existing authenticated
updater launch path. Edge resolves the current POS from SQLite and performs the
shared startup/health flow: initial authenticated Hive-ready health within 90
seconds, then 30 seconds of continued health (maximum 10-second heartbeat gap)
and live-process checks. Input remains held during this probation. Setup waits
for the complete stabilization, including rollback stabilization if needed, and
reports failed launch/health, rather than treating the launch ACK as success.
An already-running matching POS is not duplicated.
Definitive `updater busy` replies may be retried briefly; a lost launch ACK is not
blindly resubmitted. The shortcut never pins a POS release directory. Existing POS
Enrollment Code onboarding runs afterward; setup asks for no Venue UUID, database
credentials, API secret or printer IP.

The Setup GUI is native Win32 inside VynicSetup.exe. A locked OS thread owns the
window/message loop and controls; installation work runs separately and reports
progress to that window. Closing cannot abandon an active mutation. Native Shell
Link COM APIs create/validate shortcuts without an interpreter or target resolution.
No runtime scripts, cmd.exe or powershell.exe are launched. Explicit --host is the
only background mode; process starts use absolute owned executable paths and the
current unelevated token. See `WINDOWS_DEFENDER_REVIEW.md` for native qualification,
PE metadata, external Authenticode signing and unresolved Defender analysis.

## Existing installation, repair and uninstall

The protected receipt detects a managed installation and offers **Open Vynic /
Repair / Uninstall**. Known legacy deployment locations (`C:\Vynic\App`,
ProgramData `Vynic\Deployment`) and orphaned managed registration/state refuse
fresh adoption and direct the operator to support. Running `vynic_pos.exe` also
blocks setup. Unknown portable installs elsewhere cannot be reliably discovered;
legacy migration needs an explicit fleet procedure. No legacy scheduled task,
share, Manager integration or deployment script is changed automatically.

Repair requires POS to be closed normally. It stops the local Edge host via a
shutdown marker, waits for its lock, validates retained SQLite and refuses an
unresolved INSTALLING/RESTARTING decision. An interrupted binary journal is recovered before fetching fresh repair metadata,
so offline failure can still restore the previous release. It restores exact trusted binaries,
updater config from the receipt, ACLs, startup/shortcuts and repair metadata.
Credential and installation identity never rotate as a side effect. A corrupt or
missing retained DB/receipt is an error, not a reason to initialize a new one.
When run from a downloaded setup, its trusted invoking binary can also restore
the stable setup path. A running installed setup does not replace itself.

Binary replacements use a persisted journal and same-volume old/new renames.
A failure restores old binaries; an interrupted journal is recovered on Retry /
Repair. A process that is running the installed setup cannot recover a journal
that replaces that same executable: use the original downloaded setup, as the
error directs. Metadata/registry/shortcut registration is idempotent, but is not
one OS-wide atomic transaction; failure requires retry and reports diagnostics.
POS repair uses the same `current / staging / rollback` slots as the updater.
Downloads/extraction use `pos/staging/setup.zip` and `setup-release`, separate from
any deferred updater candidate. The setup journal records the POS rollback slot;
Edge receives a persisted `repair_ready` decision before setup commits its swap.
Explicit Open starts probation; success permanently deletes rollback and setup
scratch. Failed repaired POS startup restores the previous binary and runs the
same health checks. Repeated repair before Open first restores the retained
fallback, so unproven copies never accumulate. Edge/setup repair backups remain
transaction-local and are removed after setup commit. Installer downloads are
removed on completion; interrupted scratch is reused/removed on Retry/Repair.
The detailed cleanup/recovery contract is in `POS_WINDOWS_UPDATER.md`.

After a failed repair the UI attempts to restart the previous host. It never
force-kills POS/Edge/Manager or rolls back a database.

Uninstall explicitly confirms **application removal with restaurant data kept**.
It requires POS closed and waits for the host to stop, but **does not require
startup health or recovery of an interrupted update**. The updater ownership
lock must be free before removal; a live/locked process still blocks deletion.
It removes only owned startup/shortcuts/uninstall registration and Edge/POS release
slots (including temporary rollback and staging). It retains Hive, Edge DB/identity, updater DB/high-water,
credentials, receipt and diagnostics. A small setup utility remains for Repair.
There is intentionally **no data-deletion button**; permanent operational-data
removal is a distinct support procedure. Repair after removal reuses retained
state. Install after explicit removal selects the current compatible signed POS
release, subject to the retained version/high-water checks; installed Repair
remains version-pinned and Edge always retains its pinned baseline. Only after all release slots are removed does
Reinstall reset abandoned binary activation/health fields; data paths, credentials,
release high-water and consent rows remain. Interrupted setup swap journals are
archived under `state/uninstalled-swap-*.json`, never replayed after removal.
Repeated removal is safe, and incomplete removal can be retried from the wizard.

Setup 1.0.4.0 embeds the existing Vynic brand icon at seven resolutions. Native
windows and POS Shell Links explicitly use that resource; the shortcut target
remains the updater-aware Setup launcher. Reinstall with the new downloaded
Setup installs the icon-bearing launcher and recreates the owned shortcuts.
No Flutter rebuild or Edge self-update is needed for these fixes.

Setup 1.0.5.0 launches POS without an installer/progress window, including
`--launch`, Open POS and Launch after installation. The launcher still waits for
authenticated startup health; failure is written to `logs/setup.log` and shown
in a native error dialog. Normal no-argument Setup remains the visible wizard;
install/repair/update actions keep their progress UI. To update an existing
launcher, close POS and run the new downloaded Setup → More options → Repair.

## Windows/network/security qualification

This installer opens no firewall port. The current host exposes only existing
bearer-authenticated `127.0.0.1:7444` updater IPC. Future LAN gRPC requires explicit
Cloud binding/pairing and an approved firewall rule restricted to the chosen
binary, private network/subnet and gRPC port. It must not expose updater IPC.

Native Windows validation remains mandatory:

- Standard-user install and rejected elevation; correct Known Folder/account,
  protected ACLs and inherited file permissions on NTFS.
- Logon startup, sign-out/reboot, duplicate launches, host crashes/retry exhaustion,
  graceful shutdown while updater state is active, and orphaned Edge processes.
- Native Win32 UI, progress/failure handling, DPI/localization, shell shortcuts,
  Programs & Features Repair/Uninstall and AppLocker/WDAC environments.
- Locked exe/DLL directory moves and eventual rollback deletion, including cleanup
  retry without reverting healthy current; installed-setup recovery using the
  external setup; disk full,
  antivirus quarantine and power loss at every journal/rename/receipt boundary.
- Real complete Flutter runtime/plugins/assets, Enrollment Code onboarding,
  same application-support directory and existing open-order recovery.
- Real updater candidate/previous health, explicit consent, rollback and exact
  process isolation; Manager and other applications remain running/unmodified.
- Authenticode chain/timestamp, SmartScreen and antivirus behavior; manifest
  authenticity and file hashes do not replace OS publisher/reputation testing.
- No unexpected firewall prompt/listener, ACL access from another account, and
  uninstall/reinstall preserving actual Hive and SQLite content.

Microsoft documents [per-user unelevated application installations](https://blogs.windows.com/windowsdeveloper/2025/05/19/enhance-your-application-security-with-administrator-protection/)
and [UAC process behavior](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/how-it-works).
Those OS constraints are the reason for the interactive-user design, not evidence
that this implementation has passed Windows qualification.

## Exact prerequisites for future Edge self-update

1. Explicit signed Edge release/version/compatibility policy and immutable
   per-version artifacts, including forward/backward SQLite compatibility.
2. A separately trusted small helper with its own lifecycle and recovery journal;
   if it needs elevation, install its executable/config in a machine-protected
   location. Never elevate this per-user writable release tree.
3. Helper authorization/IPC, trusted-key provisioning/rotation and service/session
   ownership; separation from POS install consent and current local host token.
4. Drain/fence unresolved intents, sessions, projections and any future operational
   authority using established readiness/handover contracts, never leader election.
5. Stop supervisor/Edge, durably select candidate, start it, authenticate health,
   and restore only previous binaries on failure; preserve Edge/Hive data and
   identity. Reserve helper code under a separate `bin` entry; keep versioned Edge
   directories and existing state/config paths stable.
6. Real Windows crash/power-loss/ACL/lock/AV qualification and controlled rollout
   with previous-version recovery. None of these enable Phase 2A authority.

Setup 1.0.6.0 includes update progress and download-first monitoring. It does not
shorten Edge's 30-second startup stabilization or modify production authority.
Checks and downloads may run with POS closed; installation still requires POS
readiness and explicit consent. Monitoring is bounded to 30 minutes; a monitoring
timeout is an error and does not claim the background download was cancelled.

## Startup data identity regression (Setup 1.0.7.0 / POS 1.0.3)

Windows `path_provider` derives its default application-support directory from
PE CompanyName/ProductName. Branding changed CompanyName from `vanski` to `Vynic`;
POS 1.0.1 consequently opened a different Hive folder, while Edge correctly
rejected its health heartbeat against the previously pinned data directory.
The client hid the rejection behind indefinite startup probation.

POS now obtains the persisted `dataPath` over authenticated loopback IPC **before
opening Hive** and passes that exact directory through DatabaseService/DatabaseCore.
Missing/unreachable pinned storage fails visibly; it never falls back to empty
restaurant data. New installations without a pinned path retain normal initial
provisioning. Manager storage selection is unchanged. No folders are moved, merged
or deleted by this fix.

The client bounds complete IPC requests, reports readiness/health errors, logs
them in `logs/pos-startup.log`, and replaces endless probation with an error at
150 seconds. Input stays fenced until verified health. Window close during
probation does not open a confirmation dialog beneath the blocking overlay.
Setup releases its admission lock after Edge accepts launch, before observing
health, so a slow launch no longer monopolizes the uninstall lock.

After uninstall the wizard says **Install**, preserving local data and trust.
That explicit action can install the newer signed POS fix; ordinary Repair does
not upgrade an installed app. Signed artifact/hash/compatibility checks and the
pinned Edge baseline remain mandatory.

Windows 11 Parallels validation used the real signed POS bundle with an isolated
updater and copies of the legacy Hive files. The original failure was confirmed
as a `vanski` vs `Vynic` data-path mismatch. The corrected bundle sent accepted
heartbeats with the pinned legacy-copy path and completed the full 30-second
stabilization. Original Hive/state and the installed Edge were not replaced by
this diagnostic. Native installer UI and upgrades still require normal rollout
qualification; this does not classify the earlier Defender report.
