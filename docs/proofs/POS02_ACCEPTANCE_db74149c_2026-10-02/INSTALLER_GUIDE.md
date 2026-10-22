# Existing Windows installer path and revised POS-02 candidate

Read-only inspection completed for this task. No release server/publisher/VM was
started, no upload/install/update was requested, and no certificate or trust was
changed. The current task ends with this guide and waits for the user.

## Exact existing address and saved release

The local release root is `/Users/vaanskii/VynicLocalReleases`, serving only
`public`. The Mac's verified active `en0` address is **10.10.10.3**.

| Purpose | Address |
|---|---|
| Primary release home | `https://10.10.10.3:8443/` |
| Primary installer | `https://10.10.10.3:8443/VynicSetup.exe` |
| Public HTTPS CA | `https://10.10.10.3:8443/rootCA.pem` |
| Primary signed POS feed | `https://10.10.10.3:8443/pos/manifest.json` |
| 10.x profile installer | `https://10.10.10.3:8443/networks/10.10.10.3/VynicSetup.exe` |
| Alternate network installer | `https://172.20.10.2:8443/networks/172.20.10.2/VynicSetup.exe` |
| Windows source build command | `https://10.10.10.3:8443/build-pos.cmd` |

The alternate IP is a configured supported LAN profile, not the presently active
Mac address. Both profiles use the same public CA; their Setup/distribution URLs
are distinct. Existing installs keep their configured feed; another profile's
Setup alone does not migrate the installed endpoints.

**Current blockers:** no process is listening on 8443; CA-validated
`https://localhost:8443/status.json` returned connection refused. The saved
`status.json` says READY, but saved signed feed/bootstrap expiration is
**2026-09-28 21:08:18 UTC**. READY on disk is not current server availability or
valid unexpired metadata. Starting the server and renewing metadata require a
later explicit action; neither was done here.

The saved published build is **POS 1.0.13 / signed release 14**, Windows `amd64`,
Edge **1.0.1 / bootstrap 3**, local-development channel and Hive 9.
The artifact `local-build.json` proves compiled configuration:
`VYNIC_ENV=development`, API `http://10.10.10.3:3000`.
Port 3000 is the separate development backend; 8443 is only release distribution.
The release server does not start the backend or provide Enrollment Codes.

Published source ZIP SHA-256:
`fe53104f5d18b3e0408e311b72795731b82ae8fdfe90dd739e3a197c83f58047`.
POS artifact ZIP SHA-256:
`f79a780c3eca7d82e027871709fc48dcdd0d9000a68c0f2fb8f4ac275aefeda3`.
Primary Setup SHA-256:
`a23432b5955abb26c946dbc0fb9a0ee43a16bdeb83ffedb54b55bd888a357d91`.
The artifact and public source bytes match those hashes. The published source
has no new durable `print_job.dart`, `print_reconciliation.dart` or
`local_printer_catalog.dart`: **this installer does not contain this POS-02
candidate**. No current installed Windows version was inspected; the VM is held.

## Certificate and installer steps for the later approved Windows window

The certificate is a **mkcert development HTTPS root CA**, valid September 20,
2026 through September 20, 2036. It trusts the local release server. It is not an
Authenticode executable-publisher certificate, a POS enrollment credential or
Edge's separate generated TLS identity certificate. Ed25519 public keys embedded
in Setup separately verify signed release metadata/artifact hashes.

Public CA PEM file SHA-256:
`0d31b94c7820b7c2c7a8dc83066742f348bb538bbd654f42178b5725be244613`.
Certificate DER SHA-256 fingerprint:
`D1:2C:1A:7E:0B:65:91:E8:24:11:6E:B3:DF:6C:56:6A:71:E1:C3:FE:64:13:E8:ED:5C:09:00:B4:35:BA:E3:05`.
These are different hashes of different encodings of the same public certificate.

1. Once the lab server/metadata have been explicitly restored and verified,
   copy **only** `/Users/vaanskii/VynicLocalReleases/public/rootCA.pem` to the
   existing isolated Windows test account via a trusted local copy. This handles
   initial HTTPS trust without bypassing TLS or sending any private key.
2. Inspect the copied public file/fingerprint and current-user trust. The
   documented import, **only if the owner approves and trust is not already
   present**, is `certutil -user -addstore Root rootCA.pem` from its directory.
   It adds this development CA to the current user's Trusted Root Certification
   Authorities. No `-f`, machine-root import, security bypass or policy change is
   part of this guide. Do not copy any `.key`, PFX/P12 or `private` directory.
3. Under the same normal Windows account, open the primary HTTPS page and download
   the verified current `VynicSetup.exe`. Run it normally, **unelevated**. The
   per-user installer refuses an elevated token and installs under
   `%LOCALAPPDATA%\Vynic`. It does not relocate/delete restaurant Hive data.
   Use an existing clean synthetic test profile; an installer launch is not a
   way to isolate live restaurant data or impose the one-shot print budget.
4. For a fresh installation choose Install, then Open POS. For an existing
   compatible installation use POS **მართვის ცენტრი → პროგრამის შესახებ →
   შემოწმება**, or downloaded Setup's **Update POS**. Download/verify can occur
   first; **განახლება ახლა / Update Now** is explicit installation consent.
   **Later** leaves the candidate staged. Repair restores the selected installed
   version and is not an upgrade path. Do not delete updater SQLite/high-water
   state or manually swap binaries to force an update.
5. After installation, record the running About version/release/source identity
   and updater startup verification, rather than relying on the Mac READY file.
   Logs are `%LOCALAPPDATA%\Vynic\logs\setup.log` and `edge.log`; public build
   identity is `pos\current\.vynic-release.json`. Avoid sharing host tokens from
   installation/updater config or real restaurant data.

The development Setup is not Authenticode-signed. Existing Defender/SmartScreen
qualification is separate from HTTPS trust. If Windows blocks execution, retain
the diagnostic and resolve it through the approved signing/qualification path;
no Defender, reputation or trust bypass is instructed here.

## How the revised candidate can later be tested through this installer

A new Windows artifact and signed local publication are required. Downloading
the current installer or its current `build-pos.cmd` still selects **1.0.13 /
release 14 / fe53104f**. It cannot test the revised candidate.

The existing publisher is `apps/edge/tool/publish-local-pos.sh`; it starts/reuses
the local server, may start the Parallels VM, snapshots the working tree, builds,
copies, signs and publishes. **Do not run it against this WIP workspace now.**
The manual path is documented in `LOCAL_WINDOWS_RELEASE_TEST.md`:
`prepare-pos-update` → newly generated Windows `build-pos.cmd` → copy the matching
`vynic-pos.zip` to the Mac input → signed `publish` → `verify`. Copying to the
watched input can itself cause publication. These are future actions requiring
the user's explicit continuation and applicable authorization.

The concrete next release input must be an isolated clean export of HEAD
`275688e1`, overlaid only with the sealed 883-file candidate. Existing Edge
publisher tooling must come from that clean export. Verify all 44 integrated
runtime paths against the sealed candidate before product preparation. The
existing `tool/product.py` preparation selects `main_pos.dart` / `vynic_pos.exe` /
`ge.vynic.pos`, changes only product-native metadata and removes seed menu data.
Preserve that approved preparation delta and a new locked source/build receipt.
Do not incorporate unrelated WIP or relabel an older Windows artifact.

Choose the next **monotonic unused** version/release from the then-current lab
state; do not overwrite issued 1.0.13/14 bytes. Keep Edge 1.0.1/bootstrap 3 pinned.
Use the intended current API network, existing cached SDK/dependencies and
existing signing custody. The current generic build command uses online
`flutter pub get`; a cached, `--offline --enforce-lockfile` build handoff must be
prepared before execution under this task's no-install/no-download boundary.
No replacement source receipt or Windows artifact has been prepared/published
here, so an exact final new installer build hash cannot yet be provided.

Before accepting installer-based results, bind candidate source → prepared POS
source/receipt → Windows ZIP hash → signed feed → installed identity. Run revised
Windows synthetic/native GUI tests in the approved isolated profile. The
one-shot physical budget applies to the standalone runner in
`POS02_ONE_SHOT_ACCEPTANCE.md`; the normal installed POS does not import its
guard. Leave real printer settings and operational print actions unused until a
separate explicit model/window/paper allowance is granted. Receipt/paper policy
and physical cable/paper/power/kill/copy acceptance still block POS-02 DONE.

Read-only evidence is archived alongside the runner proof as
`installer-readonly.json`. Relevant established procedures:
`docs/LOCAL_WINDOWS_RELEASE_TEST.md`, `docs/WINDOWS_SETUP.md`,
`docs/POS_WINDOWS_UPDATER.md`, `docs/WINDOWS_DEFENDER_REVIEW.md`.
