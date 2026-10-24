# Windows beta test installation

The test installer is published: POS **1.0.0 build 16**, beta, for Windows 10/11
amd64, with the printer-header fix. It is not production-qualified.

- Download: https://releases.vynic.ge/
- Installer: https://github.com/vaanskii/vynic-releases/releases/download/v1.0.0-beta.1/VynicSetup-1.0.0-build16-beta.exe
- Release notes: https://github.com/vaanskii/vynic-releases/releases/tag/v1.0.0-beta.1
- Hashes: https://releases.vynic.ge/windows/beta/SHA256SUMS.txt
- Qualification: https://releases.vynic.ge/windows/beta/qualification.json

Installer SHA-256:
`2809ab6c9c83bda44c34ffc418b3bbb3cc5fd9fde974a41b0bda989268ca72ca`

## Start on a new test PC

1. Use a new Windows test PC with no working Vynic installation. A separate
   Windows user on the existing VM does not isolate TCP port 7444 or all-process
   POS checks. The owner creates the test user; no account or process changes
   were made by this release task.
2. Request access at https://vynic.ge/request-access. Operator approval and an
   owner invitation precede sign-in at https://vynic.ge/login. For an existing
   restaurant, retain the correct venue identity; do not provision a duplicate
   based only on its name. The owner handles historical-data import separately.
3. Download the EXE and compare its SHA-256 with the published value, for example
   `Get-FileHash -Algorithm SHA256 .\VynicSetup-1.0.0-build16-beta.exe`.
4. Run Setup as the ordinary user. Initial installation requires internet and
   downloads the signed, hash-verified POS/Edge archives. Setup is unsigned;
   the already-disclosed Windows publisher warning remains. Do not disable
   protection or install a development trust root. App-local Microsoft-signed
   x64 CRT DLLs are included; no separate C++ runtime installation is intended.
5. Sign in to the owner dashboard, open **Devices / POS**, issue a device code
   for the correct restaurant and enter it in POS. First-manager setup is an
   explicit choice when eligible; do not recreate existing Manager history.
   A live owner dashboard session and enrollment were not exercised by this task.

The build uses `VYNIC_ENV=staging`, `VYNIC_APP_VERSION=1.0.0`,
`VYNIC_APP_BUILD=16`, and **https://api.vynic.ge**. The staging label does not
create an isolated cloud database. Use synthetic test data in the intended
restaurant identity; do not assume a restore merges tenants or old histories.

## Record the real-PC results

- Setup completes, shortcuts work, POS opens and reconnects after normal restart.
- The issued device code connects only the intended restaurant; no local venue
  mismatch is bypassed. Check existing versus first-manager flow deliberately.
- Create synthetic orders and cash/check-close records, restart, work offline,
  reconnect and confirm no duplicate/lost records in the supported sync paths.
- Print one deliberate test on the intended queue/TCP printer and verify receipt
  text and explicit copy labeling. Physical output is still unqualified.
- Record exact build, Windows version, visible errors and relevant logs without
  sharing credentials, enrollment codes or restaurant/customer data.

Do not test this by replacing the existing POS 1.0.14 installation. Version 1.0.0
is lower in SemVer even though build/release 16 is higher; ordinary antirollback
checks correctly refuse the downgrade. Do not reset updater high-water state.

## Distribution state and remaining gates

Fresh-install `bootstrap.json`, pinned `bootstrap/16.json` and per-version
`pos/1.0.0.json` are public. **`pos/manifest.json` remains absent (HTTP 404)**:
automatic updates are not activated. The app may report an update-check failure
while that feed is held; this is separate from clean-install qualification.

Signed metadata expires **2026-11-23T15:28:45Z**. Renew bootstrap and both retained
repair envelopes before expiry while preserving exact artifact identities. Do
not overwrite released EXE/ZIP bytes. Pinned beta trust expires 2027-10-24.

Component tests, signatures, hashes, schemas, safe ZIP extraction and public
HTTPS downloads pass. The published POS ZIP preserves all 20 prior runtime files
and adds only three Microsoft-signed x64 CRT DLLs (version 14.44.35211.0).
Ordinary-user clean install/runtime, real enrollment/offline-reconnect,
update/repair/uninstall/recovery and physical printers remain release gates.

The live Admin download field remains unverified. Reading the existing Admin
session was denied by automatic approval review because private administrative
session access was not clearly authorized. No Admin write was attempted. An
authorized operator can set `releaseLinks.posWindows` to
`https://releases.vynic.ge/`, preserving every other onboarding policy value.
The current source's broad Save-policy form can change other policy fields;
review those before using it. The direct release download is available now.

See `WINDOWS_PRODUCTION_DISTRIBUTION.md` for provenance, full hashes and hosting.
