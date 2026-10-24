# Windows POS distribution: preparation and remaining release gates

The approved free beta release site and a dedicated beta metadata signing key
now exist. The candidate installer and signed feed remain unpublished pending
clean-install qualification and DNS/TLS verification. `releases.vynic.ge` is
bound in Render, but its DNS record is still pending. No trusted Authenticode
certificate was purchased. See the current beta status at the end of this file.
Do not run the LAN publisher to publish production: it prepares a development API,
private HTTPS origin and development trust.

## What exists

| Responsibility | Current implementation |
| --- | --- |
| First install, repair, shortcuts, per-user host | `apps/edge/cmd/setup`, `internal/setup`, `tool/build-setup.py` |
| POS download, signature policy, activation and binary rollback | `apps/edge/internal/updater` |
| Explicit Update Now/Later and business/Hive readiness | `apps/operations/lib/core/services/pos/update`, POS About UI |
| Offline manifest publishers | `apps/edge/cmd/sign-pos-release`, `cmd/sign-bootstrap` |
| Windows publisher signing | `apps/edge/tool/sign-windows-release.py` (external Windows SDK SignTool and existing certificate) |
| Local Windows VM development publisher | `apps/edge/tool/publish-local-pos.sh`, `publish_local_pos.py` |
| Owner installer download link | Admin Customer onboarding, `releaseLinks.posWindows`; `OnboardingPage.tsx`, backend `customer.controller.ts` and `customer.service.ts` |

The Admin field stores an HTTPS download URL. The Owner portal exposes it when
POS is enabled. It neither uploads installers nor signs/releases software and
does not change an installed client's update feed. No Windows release/signing
GitHub Actions workflow is checked in at the inspected `7898d58f` revision.
There is no public binary-serving or release-manifest backend endpoint in this
flow; static HTTPS distribution is already supported by the Setup contract.

`VynicSetup.exe` embeds public distribution configuration. Its verified bootstrap
pins Edge, initial POS, `posFeed`, `repairBase` and `posReleaseBase`. Edge polls the
POS feed at startup and every 30 minutes, and on an explicit check. An installed
host retains its feed/trust in its receipt/config; changing the Admin download URL
only changes future downloads. Existing LAN installations need a separately
qualified data-preserving reprovisioning plan; pointing them at a public URL or
resetting their updater DB is not a supported migration.

## Hosting proposal

For the initial budget-limited beta, the proposed route is a Render static site
for a release landing page and small signed JSON envelopes, with immutable ZIP/EXE
assets in a separate public, binaries-only GitHub repository. This keeps DNS at
domenebi.ge: only the release subdomain's provider-directed record is needed.
Both provisioning and a dedicated beta manifest key await approval. Check the
workspace's domain, bandwidth and pipeline quotas before claiming zero cost; do
not enable paid overages. The existing runtime downloader permits bounded HTTPS
cross-host redirects, so GitHub's release asset redirects fit its current policy.
See [Render static sites](https://render.com/docs/static-sites) and
[GitHub release assets](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

HTTPS object storage/CDN is a later alternative, subject to a concrete budget.
R2 custom domains require Cloudflare-managed DNS; retaining external authoritative
DNS through a partial zone requires an eligible paid plan. Do not recommend this
as a free CNAME-only setup for the current domain, and do not point the production
name at the development-only `r2.dev` endpoint. See
[R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
and [partial DNS setup](https://developers.cloudflare.com/dns/zone-setups/partial-setup/).
S3/CloudFront provisioning would be billable and is not approved. Vercel's current
Hobby account is not the chosen route for commercial product distribution.

Keep the API at `https://api.vynic.ge` and the product/Admin web apps on Vercel.
Do not store uploaded installers on the Render Free web service filesystem:
it is ephemeral and the service spins down after idle periods. See
[Render Free limitations](https://render.com/docs/free).

Proposed logical public paths under `https://releases.vynic.ge` (the initial beta
uses `beta` in place of `stable`; artifact URLs may instead point directly to the
immutable GitHub release assets):

| Object | Path | Retention/cache |
| --- | --- | --- |
| Setup linked from Admin | `/windows/stable/setup/<setup-version>/VynicSetup.exe` | Immutable bytes; versioned URL |
| Current fresh-install bootstrap | `/windows/stable/bootstrap.json` | Short cache/revalidate; signed expiry |
| Current POS feed | `/windows/stable/pos/manifest.json` | Short cache/revalidate; signed expiry |
| Retained bootstrap repair metadata | `/windows/stable/bootstrap/<bootstrap-release>.json` | Renew signatures/expiry; retain exact pinned artifact identities |
| Retained POS repair metadata | `/windows/stable/pos/<pos-version>.json` | Renew signatures/expiry; same version always same artifact |
| Edge ZIP | `/windows/stable/artifacts/edge/<edge-version>/windows-amd64.zip` | Immutable, retain for installed baselines |
| POS ZIP | `/windows/stable/artifacts/pos/<pos-version>/windows-amd64.zip` | Immutable, retain for repair |

Give mutable JSON a short cache lifetime (e.g. 60 seconds with revalidation),
and immutable versioned bytes a long lifetime. Do not cache 404s during release
publication. Use application/json, application/zip and application/octet-stream
respectively; set a download filename for Setup. No cookie, browser login or
short-lived presigned download token belongs in this feed: installed clients
fetch unattended and older artifacts must remain repairable. If downloads must
be private, design that authorization first; never embed a storage access token.

Publish immutable artifacts first, then per-version/repair metadata, then latest
POS/bootstrap manifests, and only then the Admin link. Validate the final HTTPS
responses with ordinary system trust, including cache behavior and HTTPS-only
redirects. Never overwrite released ZIP/EXE bytes. Keep the previous feed until
all referenced objects exist. A rollback is a local binary recovery, not a feed
downgrade: issue a newer version and monotonically larger release for a fix.

## Signing choice

The existing EXE path is the smallest change to current architecture, not a final
purchase decision. Direct distribution needs a trusted Authenticode publisher
identity for Setup and Vynic-owned executables. The legal publisher displayed by
Windows comes from the certificate, not the `CompanyName: Vynic` PE resource.
Use a CA-supported hardware token/HSM/cloud signer. The existing tool supports
a current-user certificate store identity backed by the provider's key service;
no PFX password or private key is embedded or passed on a command line.

There are two separate signatures:

- Authenticode and RFC3161 timestamp: verified by Windows for the executable
  publisher. The release script checks SignTool trust, requires timestamping and
  inspects the actual embedded signer against the approved certificate thumbprint.
- Ed25519 manifest signature: verified by Setup/Edge against pinned public keys;
  binds product, architecture, channel, version/release, SHA-256, size, expiry and
  unchanged data policy. It does not provide Windows/SmartScreen publisher trust.

Microsoft Store **MSIX** handles package signing, hosting and updates and does not
require buying a separate code-signing certificate. Store **EXE/MSI** submissions
still require publisher signing and the publisher's hosted installer/update path.
OV/EV certificates do not guarantee absence of SmartScreen warnings. Microsoft
[code-signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
describes these distinctions. Do not recommend Azure Artifact Signing to a
Georgia-based individual/business without checking eligibility: Georgia is absent
from the current [Public Trust eligibility list](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart).

Current production printing uses TCP ESC/POS or Windows RAW queues through the
Flutter native adapter (`windows_spooler_native.cpp`); it does not install printer
drivers. Existing drivers/queue identities remain the operator's responsibility.
A separate Go printer service/SCM installer is present but held from production
activation (`apps/edge/packaging/windows/printer-agent/INSTALLATION_PLAN.md`).
The current Setup starts a same-user Edge helper and logon supervisor, not a
machine service. These facts do not rule out Store MSIX, but MSIX needs a separate
proof for package identity, persistent Hive path, subprocess/logon behavior,
update ownership and RAW/TCP printer access. Driver installs are unsupported;
restricted `packagedServices` capability approval cannot be assumed. See
[MSIX preparation](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-prepare)
and [capabilities](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations).
Do not add a second updater or install the held printer service to solve packaging.

## Local preparation commands

1. Copy `apps/edge/packaging/windows/distribution.example.json` to an external
   release workspace. The example intentionally has an unusable origin and no
   keys; it cannot build. Supply the approved HTTPS bootstrap URL, fixed `stable`
   or `beta` channel and **existing approved public** Ed25519 keys with RFC3339
   expiry. This task generates no production key. Validate without building:

   ```sh
   python3 apps/edge/tool/windows_distribution.py --production \
     --distribution /release/distribution.json
   ```

   This is an offline configuration check, not proof of DNS, domain ownership,
   endpoint availability, manifests or a Windows signature. The production gate
   rejects LAN/development/example endpoints, credentials/query tokens, malformed
   or expired keys, duplicate/unknown fields, and requires a key covering at least
   the next 31 days. A long-lived fleet needs an explicit key-overlap and
   reprovisioning plan well before expiry; downloaded manifests cannot add trust.

2. Build a clean POS product snapshot with `apps/operations/tool/product.py`,
   preserving its sibling generated-contract package dependency. On Windows use
   the product-specific metadata and complete release directory, an explicit
   new numeric version/build number, `VYNIC_ENV=production` and
   `VYNIC_API_URL=https://api.vynic.ge`. Do not use `local-development`, LAN API
   exceptions, developer unlock or development TLS roots. Build compatible Edge
   through `apps/edge/tool/build-edge-windows.py`. Record source commit, lockfiles,
   tool versions, build inputs and output hashes. Qualify unchanged Hive 9,
   Edge schema 2 and layout 2 before asserting those signed policies.

3. On the approved Windows release host, sign **payload** executables first.
   These commands use placeholders and do not select a certificate for you:

   ```text
   python apps/edge/tool/sign-windows-release.py --stage payload --signtool <absolute-SDK-signtool.exe> --thumbprint <approved-cert-thumbprint> --timestamp-url <approved-HTTPS-RFC3161-URL> --report <new-payload-report.json> <absolute-VynicEdge.exe> <absolute-vynic_pos.exe>
   ```

   Review third-party runtime DLL provenance/signatures separately. The helper
   signs the two Vynic-owned payload executables, not every dependency. ZIP the
   exact signed complete Flutter/Edge directories with portable forward-slash
   paths. Never sign again after hashing/packaging an issued artifact.

4. Use existing `cmd/sign-pos-release` and `cmd/sign-bootstrap` with the separate
   externally managed Ed25519 key, as documented in `WINDOWS_SETUP.md`. Hash
   the final signed ZIPs. Bind the stable channel, exact URLs, new POS version,
   increasing release number and unchanged schema/data policy. Generate both
   current and retained repair manifests. Manifest validity is at most 31 days;
   arrange renewal of every retained baseline/version before expiry. Expired
   metadata should fail closed while the installed POS keeps operating offline.

5. Build Setup with the production gate and an explicit Setup version:

   ```sh
   python3 apps/edge/tool/build-setup.py --production \
     --distribution /release/distribution.json \
     --version <four-part-setup-version> --out /release/VynicSetup.exe
   ```

   Then sign Setup separately:

   ```text
   python apps/edge/tool/sign-windows-release.py --stage setup --signtool <absolute-SDK-signtool.exe> --thumbprint <approved-cert-thumbprint> --timestamp-url <approved-HTTPS-RFC3161-URL> --report <new-setup-report.json> <absolute-VynicSetup.exe>
   ```

   `--stage all` retains the original three-file mode. For already signed final
   files, `--verify-only --stage payload|setup|all` performs no signing and requires
   no timestamp URL. It still requires the expected public certificate thumbprint.
   Reports record exact SHA-256, observed certificate thumbprint, subject and
   timestamp certificate. Existing report paths are refused. Windows SDK
   [SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)
   warnings/failures and wrong/catalog/unsigned publishers fail the operation.
   Read-only [Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature?view=powershell-5.1)
   runs only in this release script; no interpreter is added to the installer.

6. Obtain approval for the concrete provider, legal publisher/certificate cost,
   public visibility, chosen domain and exact candidate hashes. Provisioning,
   certificates, DNS, CI credentials, uploads and the production Admin link update
   remain separate approved operations. Review the native qualification below
   before calling the candidate production-ready.

## Safety and qualification

Keep the current updater contract (`POS_WINDOWS_UPDATER.md`, D021/D022):

- Checking/downloading never restarts POS. Update requires explicit operator
  consent plus one exclusive readiness barrier. Durable open Orders/Tables can
  survive a restart; in-flight payments/closing/writes and uncertain recovery
  block it. Do not infer readiness from a zero order count.
- An interrupted transfer remains `.part`, cannot execute, and restarts on retry.
  Signed size/hash, safe ZIP paths, channel, expiry, product/version/release,
  data policy and high-water mark are rechecked before activation.
- Binary slots are current/staging/rollback. Startup health authenticates actual
  Hive readiness. Failed candidates recover the previous binary, never a stale
  database snapshot. Retain the rollback until stabilization; keep all restaurant
  data and print journals outside replaceable binary slots.
- Uninstall/repair preserves data/identity. Edge is pinned; this is not Edge
  self-update, a printer service rollout, or an automatic key-rotation mechanism.

Before public release, execute a Windows amd64 clean-install/upgrade/repair/
uninstall matrix under an ordinary user. Verify legal publisher, signatures and
timestamps on the exact downloadable bytes, Defender/SmartScreen behavior, same
Hive directory and data after restart, explicit Later behavior, blocked active
transactions/printing, interrupted download, crash recovery, failed-candidate
rollback and offline launch. Native physical printer and legacy-data migration
qualification cannot be replaced by mocked process tests or macOS cross-builds.

## Evidence for this preparation

The task fetched `origin/main` and inspected `7898d58f7c2f24fc370d9a32467a29dc0224eb77`
in `/tmp/vynic-windows-release-distribution`. The original checkout/index/stash
and `/tmp/vynic-domain-onboarding-routing` were not edited. Parallels inventory
executed successfully. With later authorization, the existing `Windows 11` VM
was started and the isolated source snapshot `1.0.0-16-707d8be5` was copied to a
new `VynicBetaBuilds` directory. Offline dependency resolution and 14 Flutter
readiness/UI tests passed on Windows 10.0.26200.9457 with Flutter 3.44.2 / Dart
3.12.2. Native release compilation completed successfully in 139.7 seconds;
Windows read-back confirms `Vynic POS`, `Vynic`, `1.0.0+16`, and an unsigned EXE.
The complete runtime was exported and candidate ZIPs/receipt are kept separately
in `/tmp/vynic-beta-candidate-1.0.0-16-707d8be5`. The printer-header fix was then compiled in the separate
`1.0.0-16-print-label-v2` snapshot: 151 focused Flutter printing/update tests passed
on Windows and native compilation completed in 111.9 seconds. Native Go updater
and Setup suites also passed with an explicit asInvoker test resource (including
the native shortcut roundtrip). Earlier unmanifested test executables were blocked
by Windows elevation detection; no elevation or security bypass was used.
These component tests are not clean-installer UI or physical-print qualification.
The existing Edge process and installed POS/data are not test targets.

The beta's displayed version is `1.0.0`, with independent app build number `16`.
Both `VYNIC_APP_VERSION` and `VYNIC_APP_BUILD` must be defined for the cloud menu
compatibility report. The live backend's optional
`MENU_CANONICAL_MIN_BUILD_WINDOWS` policy has not been verified. Existing lab
`1.0.14` / release `15` installs cannot receive `1.0.0` through the ordinary
updater: it requires both a strictly newer SemVer and a larger release number.
Do not reset existing high-water state or point old receipts at the beta feed;
a data-preserving migration requires separate qualification. Existing working
POS/Edge processes and real restaurant data were not modified. No trust root was
installed. The public setup described below was explicitly approved separately.

Python validation: `python3 -m unittest windows_distribution_test
sign_windows_release_test windows_pe_test publish_local_pos_test
local_windows_release_test_test` from `apps/edge/tool` passed 43 tests.
Windows subprocesses are mocked; the printed VM
build messages in the publisher regression are fixtures. Configuration/publisher
policy and fail-closed ordering are covered, not native Windows certificate trust.

The existing `go test ./internal/updater ./internal/setup` suites also passed on
macOS, covering signature/policy rejection, partial/corrupt downloads, staged
consent, process/activation crash recovery, binary rollback, and repair/data
retention simulations. Go was initially absent from PATH and the earlier lab's
documented toolchain path; an official Go 1.26.10 darwin/arm64 archive was fetched,
checked against its published SHA-256
`0b5183492292ada170f9b561a834863808dd02edba599e4ad0e89899330020b3`,
and extracted only into `/tmp/vynic-release-test-toolchain`, with module/build
caches also in `/tmp`. No system compiler installation or repository dependency
change was made. These tests do not certify native Windows or physical printers.

## Approved free beta distribution status

- Public binaries/metadata repository: `https://github.com/vaanskii/vynic-releases`.
  Landing commit `32dfa086b714655deb5c654636f45663653978c6` contains only public
  page files; no app source, executable, update feed or private key.
- Render static site: `https://vynic-releases.onrender.com`, service
  `srv-dbebg2vavr4c73acdgq0`, workspace `tea-cspa7ujgbbvc73bad3lg`.
  First deploy `dep-dbebg37avr4c73acdhqg` is live. Auto-deploy/previews are off.
- Dashboard verified Hobby, no payment card, 1/2 domains before adding releases,
  8 MB/5 GB bandwidth and 7/500 pipeline minutes. The new hostname uses domain
  2/2. No plan upgrade, paid service or billing method was added.
- `releases.vynic.ge` is bound in Render but waiting for DNS and verification.
  Required record: `CNAME releases -> vynic-releases.onrender.com`.
  Domenebi.ge requires the user to sign in. No DNS record has been changed yet;
  TLS issuance is pending DNS verification, not a confirmed certificate.
- Dedicated Ed25519 key ID `vynic-beta-20261024`, public trust expiry
  `2027-10-24T00:00:00Z`. Private material is outside all repositories in an
  owner-only directory/file; never copy it into the release repository or ZIPs.
  Secure backup has not yet been established. This is beta metadata trust, not
  an Authenticode publisher certificate or SmartScreen reputation.
- Local candidate: `/tmp/vynic-beta-candidate-1.0.0-16-print-label-v2`;
  Setup has asInvoker metadata, amd64 architecture and no Authenticode signature.
  Locally signed POS/bootstrap envelopes have a 30-day expiry; renew before expiry.
  Retained repair metadata also needs renewal, without replacing artifact bytes.
- Final release publication is gated on DNS/TLS, exact artifact hash/signature
  verification and clean installer/runtime qualification. The current Windows VM
  has a working POS; Setup uses the real user's known LocalAppData path and refuses
  active POS processes. Do not install over that host or override its paths.

Printer regression evidence: 137 focused tests passed on macOS, 151 including
update suites on Windows, and targeted Dart analysis passed. Five pre-existing
cross-Venue fixture cases were excluded; two failures were reproduced on the
unchanged parent commit. Full printing-suite success is not claimed.
