# Local Windows installer release lab

Run `apps/edge/tool/local-windows-release-test.sh run` on the Mac. This is a local
release server only; it does not deploy Cloud, change production configuration,
start NestJS, or enable Edge business authority. No production keys are used.

Default external root: `/Users/vaanskii/VynicLocalReleases` (generally
`~/VynicLocalReleases`). Default endpoint: `https://10.10.10.3:8443`.
Go 1.26+, Python 3, mkcert with its CA already installed, and OpenSSL with
Ed25519 support are required. `--go`, `--root`, `--ip`, `--port` and
`--api-origin` can override the development inputs. Release downloads remain
HTTPS-only. The API permits private HTTPS origins or the exact local-only HTTP
exception `http://10.10.10.3:3000`. Never use a production release root.

## Layout and trust

- `private/`: mkcert leaf certificate/key and development Ed25519 PKCS8 key.
  The directory/files are private to the Mac account. It is **not served**.
- `public/`: downloadable Setup, public CA copy, distribution, source/build command,
  artifact ZIPs and, once a real POS exists, signed bootstrap/feed/repair metadata.
- `input/vynic-pos.zip`: real Windows build supplied by the user.
- `work/`: prepared source, descriptor inputs, caches and intermediate builds.
- `bin/`: native offline signers and local HTTPS contract verifier.
- `logs/https.log`, `server.pid`: detached HTTPS server diagnostics/identity.

The server publishes only `public`, refuses path escape and directory listing,
and uses TLS 1.2+ with the mkcert certificate for the LAN IP, localhost and
127.0.0.1. The mkcert CA private key never leaves its existing CA directory.
Copy only `public/rootCA.pem` to Windows. Install with
`certutil -user -addstore Root rootCA.pem` from the Windows directory containing
that public certificate; this adds it to the current user's Trusted Root
Certification Authorities. Run Setup as that same normal Windows account.

The distribution channel/key ID are explicitly local-development. Setup embeds
that exact public distribution; the script checks the embedded bytes. The
existing `sign-pos-release` and `sign-bootstrap` tools enforce the established
signature domains, compatibility, layout 2, digest and size contracts. There is
no unsigned fallback. `verify-local-release` fetches the bootstrap, feed, repair
metadata and artifacts over CA-validated HTTPS and runs the production verifier
and safe ZIP extraction without executing a Windows artifact.

## One-command local POS publishing

From the Mac repository root, run:

```sh
./apps/edge/tool/publish-local-pos.sh
```

This is for the already initialized development lab. It chooses the one active
registered Mac LAN address (`10.10.10.3` or `172.20.10.2`), starts/reuses the HTTPS
server, prepares a source snapshot/version, builds POS in the local Parallels
`Windows 11` VM, copies the completed ZIP back, validates it, signs the existing
feeds and verifies the HTTPS publication. The selected development API remains
HTTP port 3000, independent of the HTTPS release server. It does not start NestJS.

The VM needs Parallels Tools, a signed-in Windows account, Flutter, Visual Studio
Desktop development with C++, trusted lab CA and Mac Home folder sharing. It
starts a stopped/suspended VM; a paused VM needs to be resumed. Override selection
with `--ip 172.20.10.2` or `--vm "Windows 11"`. If both LAN addresses are active,
select one explicitly. Installed API/feed configuration is not migrated. The
build reuses an existing `FIREBASE_CPP_SDK_DIR` or an extracted SDK from earlier
local builds; the Firebase plugin still validates its required version. This
avoids downloading the large SDK again for every new source snapshot.

The command prints five stages and elapsed build time. Detailed Flutter output
is in `~/VynicLocalReleases/logs/publish-pos-<timestamp>.log`. A build failure
keeps the old feed/input ZIP and leaves a pending release that the same command
can retry. A duplicate simultaneous invocation fails instead of queuing another
version. Retrying unchanged published source verifies/renews the same release
without compiling or incrementing its version. Both the manual and automated
publish paths reject changed ZIP bytes under an already issued version, and
refuse a feed reset to an older version/release. Prepare a new update before
publishing changed binaries; do not overwrite a signed release. Publication renews development
metadata expiry while preserving each pinned version/release/artifact digest;
changed historical artifact bytes are refused. HTTPS preflight does not require
old feed metadata to be unexpired, but final signature/compatibility checks do.
Candidate transfers use a unique
unpublished file; receipt, safe ZIP paths and Windows PE layout are checked before
it replaces the input ZIP. The existing signature/hash verifier is unchanged.

All private release keys remain on the Mac. PowerShell/cmd are used only inside
the developer build VM by the existing build command, never as installer/updater
runtime. The automation neither installs the release nor stops POS/Edge. It
publishes only to the local-development lab, not production, and does not push.
After `READY`, use POS → **მართვის ცენტრი → პროგრამის შესახებ → შემოწმება**.
Go downloads in the background; **განახლება ახლა** is still required to install.
No new Setup or Edge binary is needed for normal POS updates.

The manual Windows build/copy procedure below remains an alternative when a
local Parallels build VM is unavailable.

## Windows build

macOS cannot compile the Windows Flutter release. Until a real Windows POS ZIP
is supplied, the HTTPS home page/status and real Edge ZIP/Setup are available,
and `bootstrap.json` remains unavailable. A validated real ZIP enables signed
publication; no fake POS or incomplete bootstrap is published.

After importing the CA, download `build-pos.cmd` from the HTTPS home page. On a
Windows machine with Flutter and Visual Studio **Desktop development with C++**,
run `%USERPROFILE%\Downloads\build-pos.cmd` (assuming Downloads was chosen).
Re-download this command after packaging-tool changes. It creates ZIP entries
explicitly relative to the release root with forward slashes, rejects reparse
points, and transports the build receipt as base64 to preserve JSON quotes through
`cmd.exe`. The Mac validator continues rejecting backslash entry names, unsafe
Windows paths, symlinks, case collisions and file/directory collisions.

It downloads the exact current, credential-free POS source snapshot, checks its
SHA-256, restores Flutter dependencies and builds the POS Windows release.
The snapshot uses existing product preparation and includes the relative generated
Dart contract dependency. It neither modifies the repository nor builds Manager.

Copy `%USERPROFILE%\Downloads\vynic-pos.zip` to
`/Users/vaanskii/VynicLocalReleases/input/vynic-pos.zip` on the Mac. Copy the ZIP
itself, not its enclosing directory. The server watches for a complete stable
file, checks its build receipt/version/source identity, complete Flutter layout
and amd64 PE headers, then automatically signs/publishes/verifies it. Inspect
`status.json` for READY and `logs/https.log` for errors. All signing remains on
Mac; no release private key is sent to Windows.

The generated POS release uses `VYNIC_ENV=development`, the explicit
`VYNIC_LOCAL_WINDOWS_LAB=true` define, and API origin `http://10.10.10.3:3000`.
The runtime HTTP exception requires all three settings plus Windows; staging
and production still require HTTPS. That backend is **not started by this tool**. Installer,
startup, offline recovery and local updater tests are the purpose here; online
Enrollment Code operations require a real development NestJS endpoint.
Pass its local API origin via `--api-origin` before generating the POS source
bundle if enrollment testing is needed. Do not point POS API requests at the
8443 file server or a production API.

Then download `VynicSetup.exe`, launch normally, and select Open Vynic. This local
build is not Authenticode signed; mkcert trusts the test HTTPS server, not an
executable publisher. Native Windows/SmartScreen qualification is still separate.

## Reuse and verification

- `...sh run`: prepare/cached builds, renew metadata, start/reuse server and verify.
- `...sh prepare`: prepare inputs/builds only.
- `...sh publish`: explicitly retry POS validation and signing after a failed copy.
- `...sh start`: start/reuse the prepared HTTPS server without rebuilding.
- `...sh verify`: download and verify local HTTPS contents/contracts.

Leaf/key/distribution identity is reused; Go and Setup outputs are cached by
source/configuration hash. Source ZIP generation is deterministic. Metadata lasts
7 days; rerun to renew it while retaining the same immutable artifacts/trust.
A published baseline's binary/source identity is immutable: changed code requires
a fresh `--root` for Edge baseline changes. For a POS-only change, use
`...sh prepare-pos-update`: it preserves the Edge/repair baseline, increments the
POS version/release, and regenerates the Windows source/build command. The old
signed release remains available until the matching Windows ZIP is supplied.
Then the watcher signs the new POS feed and bootstrap, preserving existing
per-version metadata and pinned repair metadata. Existing installed POS clients
receive this through their explicit Update Now flow; Setup need not be rebuilt
when its distribution is unchanged. This is
not an Edge self-update tool. No Windows POS artifact executes on Mac.

POS 1.0.4 exposes Program Update on Windows login/first-run as well as Admin
Settings, with percentage/MB download feedback. Go startup stabilization runs
without a full-screen progress overlay; admission to restaurant operations still
waits for verified health. The real Windows lab confirmed the signed candidate
with isolated Hive data and the installed updater reported `SUCCESS`, current
`1.0.4`, `startupVerified: true`. This POS-only update retains Setup 1.0.7.0
and the pinned Edge baseline.

Verification on the Mac covers TLS hostname/CA validation, Setup distribution,
byte-identical artifact downloads and isolation of public content. Once the real Windows ZIP arrives, the watcher also verifies signed bootstrap,
POS feed, repair metadata, artifact hashes and ZIP extraction using production
contracts. The corrected supplied Windows bundle passed these checks on macOS;
its executable/runtime/asset bytes were preserved during packaging repair.

## Setup startup diagnostics

A normal `VynicSetup.exe` launch opens the installer/maintenance GUI. `--launch`
opens the installed POS through Edge; only explicit `--host` runs the background
supervisor. Invalid/conflicting arguments are reported rather than exiting into
an invisible GUI-subsystem stderr stream.

Setup uses an in-process native Win32 GUI and native Shell Link APIs. There is
no PowerShell UI child or script protocol. Startup failures go to
`%LOCALAPPDATA%\Vynic\logs\setup.log` and a native error message box for interactive
modes; host failures remain log-only. See `WINDOWS_DEFENDER_REVIEW.md` before
running the new unsigned test artifact: Defender classification is unresolved.

After downloading a rebuilt Setup, check these separately on real Windows:

- Double-click: visible Vynic Setup window; Cancel exits both UI and parent.
- `VynicSetup.exe --launch`: installed POS opens through Edge.
- `VynicSetup.exe --host`: background supervisor only, no installer window.

macOS validates mode parsing and installer regressions and cross-compiles native
Windows UI/shortcut tests. Window visibility, Shell Link COM behavior and process
lifetime still require execution on Windows.


## Published release versus installed POS

A READY Mac feed does not change an installed Windows binary. The lab now publishes
an already-copied, matching pending ZIP during `run`, rather than merely printing
that it is waiting. Its output names the published POS version explicitly.

For the local API correction, the supplied real POS 1.0.1 ZIP was verified: its
receipt and compiled `data/app.so` contain `http://10.10.10.3:3000`; release downloads
remain on HTTPS 8443. Existing Windows Repair requests were observed fetching the
pinned 1.0.0 bundle, which explains why repairing did not change that API URL.
Use the rebuilt Setup's **Update POS**, then confirm **Update Now** in POS. Fresh
installs use the current bootstrap; repair metadata stays pinned for existing
installations. Setup 1.0.4.0 retains the native wizard and explicit Update entry, adds the
Vynic icon, and permits Uninstall without completing an interrupted update.
Close POS, run the new downloaded Setup, select More options → Uninstall, then
run that same downloaded Setup again and select Reinstall if desired. Data and
identity remain; no new Windows POS ZIP is needed for this installer-only fix.

A Venue UUID is not a POS enrollment credential. POS requires a short-lived,
server-issued `XXXX-XXXX-XXXX` device enrollment code. The local Prisma check
confirmed the UUID in the reported screenshot was the Vankisi Venue ID. Invitations
must be issued through the existing enrollment service; do not bypass tenant
binding or consume the invitation in a diagnostic request.

Setup 1.0.5.0 removes the Setup progress window from ordinary POS launches,
while preserving startup health checks and visible failure reporting. Close POS
and use More options → Repair in the new downloaded Setup to replace an older
installed launcher. The POS release stays unchanged; no Windows rebuild is needed.

Setup 1.0.6.0: run the new downloaded Setup → Update POS to see real percentage,
received/total MB, verification and elapsed time. No Repair is needed to use this
update screen from Downloads. POS only opens when recovery requires it or the
operator chooses Open POS after the verified download. Later retains staging.
The POS ZIP and installed Edge baseline do not change for this UI improvement.

The startup fix is POS 1.0.3 + Setup 1.0.7.0. A real Windows VM was discovered on
this Mac and used to build the POS and validate the pinned Hive-directory health
handshake. No manual Windows compilation is needed for this release. For a
1.0.1 installation stuck in startup, close POS, use the newly downloaded Setup
to Uninstall, then run it again and choose **Install**. Local data is retained;
Install selects the current signed POS while preserving the existing Edge
baseline. This avoids restoring the obsolete client through version-pinned Repair.


## Two development LANs and normal POS updates

The lab trusts both `10.10.10.3` and `172.20.10.2` in its mkcert certificate.
Run `./apps/edge/tool/local-windows-release-test.sh networks` once to generate
independently signed network profiles (same external development key). The
profiles live at `/networks/10.10.10.3/` and `/networks/172.20.10.2/` on the HTTPS
server. Each has its own Setup/distribution/bootstrap/feed; artifact bytes are
shared. Historical signed repair metadata is mirrored too. Existing installed
clients keep their configured feed: downloading another Setup alone does not
migrate an existing installation or replace Edge.

On the second network, start/verify with:

```sh
./apps/edge/tool/local-windows-release-test.sh start --ip 172.20.10.2
./apps/edge/tool/local-windows-release-test.sh verify --ip 172.20.10.2
```

The first network uses `--ip 10.10.10.3`. Only the currently connected LAN address
is expected to be reachable. Restart the lab HTTPS process after regenerating
its certificate, since an already-running server has the old certificate loaded.
No TLS bypass is used. The same public `rootCA.pem` trusts both addresses.

To publish subsequent POS changes:

1. Run `./apps/edge/tool/local-windows-release-test.sh prepare-pos-update --ip 172.20.10.2 --api-origin http://172.20.10.2:3000` on the Mac.
2. Download/run `https://172.20.10.2:8443/build-pos.cmd` on Windows. It builds the
   real POS with the generated source receipt; Windows build number matches the
   monotonic signed release number.
3. Copy `%USERPROFILE%\Downloads\vynic-pos.zip` to
   `/Users/vaanskii/VynicLocalReleases/input/vynic-pos.zip` on the Mac.
4. Run `./apps/edge/tool/local-windows-release-test.sh publish --ip 172.20.10.2`,
   then `verify --ip 172.20.10.2`. The watcher also publishes a stable copied ZIP.

For the first network, replace both IP arguments with `10.10.10.3`. NestJS stays
on port 3000; signed releases stay on HTTPS 8443. The API is selected at build
time, so changing Wi-Fi alone does not rewrite the installed POS API or Edge
feed. Only opt-in Windows development builds permit either exact HTTP API;
production, staging and Manager HTTPS policy is unchanged.

Go checks on startup, periodically, and when POS requests a check. It downloads
and verifies in the background. The operator explicitly chooses Update Now;
Later keeps the staged release. Publishing on the Mac does not itself install
on Windows. Normal POS updates do not require a new Setup or Edge binary.

POS administration now uses **მართვის ცენტრი** on Home, with separate
**რესტორნის პარამეტრები** and **პროგრამის შესახებ** sections. About contains
installed/candidate versions, progress, update controls, terminal/restaurant
information and clean Quit. Feed lookup failures and local Edge connection
failures are distinguished from installation failures; connection loss never
fabricates a successful install or destroys the last known release state.


The About/update UI and fullscreen/clean Quit bundle was built in the Windows VM
and published as POS **1.0.5**, signed release **6** (Windows build number 6).
Its compiled development API is `http://172.20.10.2:3000`. Both LAN feeds publish
the same verified artifact, so use a build for the intended API network rather
than assuming the feed address rewrites the compiled API. No installed POS or
Edge connection settings were changed during publication.


### Switching an existing development installation

`apps/edge/tool/lab-network/main_windows.go` is an explicit development-only
maintenance tool, not part of the distributed installer. Build it for
Windows/amd64 and run unelevated with `--ip 172.20.10.2` or `--ip 10.10.10.3`.
POS must be closed. It acquires Setup admission, verifies the signed mirrored
baseline/feed using the installed public keys, gracefully quiesces the host,
updates the receipt/config URL pair with a recovery journal, and restarts the
same Edge binary. It does not change keys, identity, data, release versions or
install consent. On an interrupted pair write, rerun the tool to restore the
saved pair before retrying. Do not manually delete its maintenance/journal files.
The tool refuses production channels and unregistered addresses.

The Windows lab connection was switched to the 172.20.10.2 profile and a check
returned `READY_TO_INSTALL`: installed POS 1.0.4, candidate 1.0.5, 18,474,311 of
18,474,311 bytes downloaded. Edge executable SHA-256 was unchanged. Installation
was not requested; the operator must still select Update Now in POS.


### Update admission and visible progress

POS 1.0.6 / release 7 distinguishes a refused install request from an active
installation. Named payment/close/write blockers explicitly say installation
has not started; the readiness message is reevaluated on the status poll and
clears when the blocker ends. The operator retries explicitly; clearing a
blocker never installs automatically. The UI shows preparation/data flush,
request dispatch, Edge installation and restart with indeterminate progress;
only byte-counted downloads show a percentage. Blocked-operation identifiers
are included in POS startup diagnostics without business payloads.

The Cloud transport admission token now covers command execution and its
local journal, rather than the whole claim/ack network cycle. An offline claim
or a durable acknowledgment can therefore coexist with update readiness.
A claim returning after freeze cannot execute; its lease is replayable. Actual
execution, payments and non-durable Hive writes continue blocking admission.

Validation for 1.0.6: 40 focused Flutter tests pass (including late claim after
freeze, actual execution, durable ack, active payment, persisted Orders/Tables,
blocker clearing without auto-install and visible preparation/restart states).
Static analysis is clean; real Windows build and HTTPS signed-artifact checks
pass. Runtime installation still requires the operator's explicit action.

The pinned Edge Check implementation retains an already READY_TO_INSTALL/BLOCKED
candidate. In the live Windows check, 1.0.4 remains installed and 1.0.5 staged;
publishing 1.0.6 does not replace that candidate. Complete the operator-approved
1.0.5 installation, then check for 1.0.6. Do not edit SQLite or synthesize a
`ready: true` install request to bypass the Flutter readiness barrier.
