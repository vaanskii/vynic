# Verified Windows development POS-02 update

On October 4, 2026, the explicitly authorized recovery window built the sealed
POS-02 candidate, refreshed signed development metadata, migrated the existing
installation feed and updated the **Windows 11 ARM Parallels VM at 10.10.10.9**.
POS **1.0.14 / release 15** is running at PIN login for user testing. This is the
existing VM; no separate physical Windows machine was updated.

**POS-02 remains NOT_DONE and uncommitted.** Windows product tests pass, but the
standalone acceptance runner has one Windows path-validation failure. Physical
model/driver acceptance and the owner reconciliation policy remain pending.
No Staff login, operational print action or physical job was performed.

Evidence: `docs/proofs/POS02_WINDOWS_RECOVERY_2026-10-04/proof.json`, archived
logs/checksums and `installed-pos-1.0.14.png` in the same directory. The earlier
October 3 server-only proof and sealed source/proof kits remain unchanged.

## Current release and source identity

| Item | Verified value |
|---|---|
| Source base | Clean export of HEAD `275688e1`, with exactly the sealed 883-file candidate overlay |
| Candidate manifest SHA-256 | `db74149c4680d05e16a3a1f53906b269bf76be3d1d71e78796119633d15ff51a` |
| Prepared POS source ZIP SHA-256 | `0bf6dd5beeb9f4ff9533aea5babaae03f27790f56471099a1184cf6e27994db7` |
| Windows POS artifact SHA-256 | `4534e35e68c19a59871c04476f03dc13205d7f705e83209253b2fd693a8f6fb0` |
| Installed POS | 1.0.14 / signed release 15; native version 1.0.14+15 |
| Updater | SUCCESS; startupVerified=true; high-water=15 |
| Edge | 1.0.1 / bootstrap 3; installed executable unchanged |
| Channel / API | development / `http://10.10.10.3:3000` |
| Toolchain | Existing Flutter 3.44.2 / Dart 3.12.2; cached Firebase C++ SDK 13.5.0 |
| Signed feed expiration | 2026-10-11 20:20:59.657262 UTC |

Product preparation uses the existing `tool/product.py`: it selects
`main_pos.dart` / `vynic_pos.exe` / `ge.vynic.pos`, changes seven product/native
metadata files and removes seed menu data. All 550 prepared file hashes were
verified before and after the Windows build. The dependency lockfile and all
other Dart files are unchanged. The release build used offline enforced-lockfile
resolution and `--no-pub --target=lib/main_pos.dart`; no tools were installed.
Independent review checked clean-source provenance, the preparation delta,
artifact identity and publication verification.

The source/build receipt, all 24 installed artifact files, native version and
visible PIN screen match the reviewed release. Installation used the actual POS
**განახლება ახლა / Update Now** consent and normal readiness/startup checks.
Issued 1.0.13 / release 14 bytes were retained. Existing Setup binaries, signing
keys and Edge were not replaced; the refreshed signed feed selects the new POS.

## Current addresses and feed migration

The local release root is `/Users/vaanskii/VynicLocalReleases`, serving only
`public`. The existing HTTPS server remains at **10.10.10.3:8443**, with its
publication watcher disabled.

| Purpose | Address |
|---|---|
| Release home | `https://10.10.10.3:8443/` |
| Existing primary installer | `https://10.10.10.3:8443/VynicSetup.exe` |
| Public HTTPS CA | `https://10.10.10.3:8443/rootCA.pem` |
| Primary signed POS feed | `https://10.10.10.3:8443/pos/manifest.json` |
| Installed VM's signed POS feed | `https://10.10.10.3:8443/networks/10.10.10.3/pos/manifest.json` |
| 10.x profile installer | `https://10.10.10.3:8443/networks/10.10.10.3/VynicSetup.exe` |

The installed receipt/config previously selected the 172.20.10.2 profile.
With POS closed, the retained supported `VynicLabNetwork.exe --ip 10.10.10.3`
verified signed mirrored baseline/feed metadata and migrated the receipt/config
pair through its normal journal. The per-user operation was unelevated. Both
files now select the current feed; no maintenance marker or migration journal
remains. Historical POS 1.0.7 / release 8 repair metadata was refreshed without
changing its artifact or Edge 1.0.1 / bootstrap 3 identity.

The retained network utility has SHA-256
`924c1ae1564deb9097f78c9f97a1d7a5a17bb239d287e0e72006c1c05ba24fea`.
Its embedded VCS metadata is `ca984da3`, modified=true; no retained receipt binds
its exact source. It was not freshly compiled from the current clean export.

All 23 original data files matched byte-for-byte immediately after feed migration.
The app still uses `C:\Users\vaanskii\AppData\Roaming\vanski\Vynic POS/Vpos_Data_vanski`.
After launch, all original files remain present, but active Hive locks prevent a
complete hash comparison and startup can append/migrate local rows. No
byte-identical post-launch data claim is made. Leave POS open for user testing.

Port 3000 is the separate development backend; 8443 only distributes releases.
The release server does not provide Enrollment Codes or start the backend.

## Test results and remaining gates

Seven Windows product/preview suites pass **96 checks**. The standalone runner
has **39 passes / one failure**, and the physical entry is skipped; the nine-suite
aggregate is **FAILED**. `AcceptanceRequest.requireOwnedOutput` compares raw
Windows backslash `entry.path` with mixed-separator `marker.path`, rejecting a
valid owned result directory before storage/transport. The runner is absent from
the prepared product and is not imported by installed POS. Its source was left
sealed and unchanged; correcting/resealing it is separate follow-up work.

Windows also refused an inspection `.ps1` file because script execution is
disabled. Policy was unchanged; the bounded build/tests used existing EXE/BAT
and direct commands. The sealed PowerShell acceptance launcher is unqualified.
These limitations block Windows standalone/physical acceptance, while the
reviewed product update and launch have completed.

The user still needs to test the open app. Supported-model Georgian output,
cut/driver behavior, cable/paper/power/kill recovery and explicit labeled copies
require approved isolated physical windows. Current physical allowance is zero.
The owner must also decide Receipt copies, paper confirmation and no-byte retry
policy. Normal installed POS does not import the one-shot runner's budget guard.
See `docs/POS02_ONE_SHOT_ACCEPTANCE.md`; this update grants no physical allowance.

## Existing trust and future installation boundaries

The existing mkcert development CA and Ed25519 verification keys were retained.
No certificate/trust, Defender/SmartScreen, execution-policy or credential change
was made. CA-validated HTTPS and the production Setup/updater signature/artifact
policy verifiers passed. The development Setup is not Authenticode-signed;
physical Windows signing/driver qualification remains a later release gate.

Public CA PEM SHA-256:
`0d31b94c7820b7c2c7a8dc83066742f348bb538bbd654f42178b5725be244613`.
Certificate DER SHA-256 fingerprint:
`D1:2C:1A:7E:0B:65:91:E8:24:11:6E:B3:DF:6C:56:6A:71:E1:C3:FE:64:13:E8:ED:5C:09:00:B4:35:BA:E3:05`.

For another explicitly authorized installation, use the existing unelevated
per-user Setup and approved synthetic data. Check current signed expiration and
existing trust first. A different network profile's Setup alone does not migrate
an installed feed. Never delete updater high-water state, manually swap binaries,
change security policy or copy private signing/TLS keys to force success.

Relevant procedures: `docs/LOCAL_WINDOWS_RELEASE_TEST.md`,
`docs/WINDOWS_SETUP.md`, `docs/POS_WINDOWS_UPDATER.md`,
`docs/WINDOWS_DEFENDER_REVIEW.md`. The parent coordinates the requested subsequent
plan/deployment-readiness audit; no later roadmap implementation was started.
