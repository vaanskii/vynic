# Private R2 Windows beta publisher

`apps/edge/tool/publish_private_r2.py` is the final, manually approved upload
stage for a qualified **complete offline Windows beta ZIP**. It does not build,
sign, install, deploy, publish a GitHub release, activate downloads or updates,
modify bucket access, or delete files. The existing local LAN publisher remains
development-only. There is no checked-in Windows release CI workflow at base
`bf7bd647`; this adds a callable release stage without silently turning every
build into a distribution event. The integrated source was published separately; this upload command never pushes code.

## Current storage and delivery boundary

The private Standard `vynic-installers` bucket contains the beta19 offline ZIP
at `windows/beta/1.1.0/build19/Vynic-Windows-1.1.0-build19-beta-offline.zip`
(46,835,519 bytes; SHA-256
`f46c1075a0b9dd8f388938dfebd3a13ef512b5509ce22a1abba114b51e685b79`).
Public bucket access, r2.dev and bucket custom domains remain disabled. Upload
and historical full readback do not establish successful customer installation.

The reviewed Worker source is deployed with `INSTALLERS` bound to that bucket,
compatibility date `2026-06-16`, and an encrypted `DOWNLOAD_GATEWAY_SECRET`.
Workers Paid is active. workers.dev and preview URLs remain disabled. The matching
Render secret is saved, but that new environment has not been deployed and R2
selection remains inactive. The DNS inventory/parity gate is still pending;
there is no active Worker route or authenticated production R2 download proof.

The intended route is **only** `releases.vynic.ge/windows/access/*`. Preserve the
existing Render origin for other bootstrap/repair paths and as a rollback target.
Do not delete the Render site or privatize its `vynic-releases` source repository.
The approved DNS migration still requires complete authoritative export, backup,
mail/validation/DNSSEC review and parity before nameserver changes. A public DNS
sample cannot establish completeness.

Every admitted transfer/range must recheck issuer, membership, entitlement,
expiry and revocation. Never redirect to a public object or durable presigned URL.
Before activating the new selection, prove anonymous denial, expired/revoked
requests, full and resumed downloads, safe errors and old-link behavior.

## Release integration

1. Build from the reviewed source snapshot on the qualified Windows build host;
   run the required native tests. Keep the complete build/test evidence in an
   external release workspace, never in a public source repository with binaries.
2. Build/sign/package matching POS, Edge and Setup with the existing tooling.
   Keep approved public distribution keys separate from the archive. Keep all
   private signing material outside the publisher. Produce the complete offline
   ZIP containing Setup, `bundle-index.json`, signed bootstrap and signed POS
   metadata, and both payload ZIPs. The publisher does not execute any of them.
3. Create and review a qualification receipt for those exact outputs. Run the
   default offline publisher command; review its object identity and plan hash.
4. Only after explicit approval, run the same command with `--upload` and the
   reviewed `--approve-plan` hash, using the approved publisher credentials.
5. A full private readback must match before any later runtime selection or
   release announcement. Those changes require their own reviewed rollout.

Use Python **3.10+**, with an isolated environment containing the pinned packages
in `apps/edge/tool/r2-publisher-requirements.txt`:

```sh
python3 -m venv /path/to/private-release-tools
/path/to/private-release-tools/bin/python -m pip install -r apps/edge/tool/r2-publisher-requirements.txt
/path/to/private-release-tools/bin/python apps/edge/tool/publish_private_r2.py \
  --artifact /release/Vynic-Windows-1.0.1-build18-beta-offline.zip \
  --distribution /release/approved-beta-distribution.json \
  --qualification /release/qualification-r2.json \
  --account-id <reviewed-cloudflare-account-id>
```

The default command makes **zero network requests** and reads no upload
credentials. Its `planSha256` binds account, bucket, immutable version/build key,
archive size/hash, source commit, qualification evidence, public trust and
signature expiry. Do not blindly pipe that hash into an upload command: a human
must review the complete plan. After approval, repeat the command with
`--upload --approve-plan <reviewed-plan-sha256>`.

Receipt schema (replace placeholders with measured values; this example is not
an approved receipt):

```json
{
  "schema": 1,
  "channel": "beta",
  "sourceCommit": "<40 lowercase hex characters>",
  "version": "1.0.1",
  "build": 18,
  "artifactName": "Vynic-Windows-1.0.1-build18-beta-offline.zip",
  "artifactBytes": 47038575,
  "artifactSha256": "<64 lowercase hex characters>",
  "setupFile": "<actual VynicSetup filename inside the archive>.exe",
  "setupSha256": "<64 lowercase hex characters>",
  "authenticode": "unsigned-beta",
  "checks": {
    "build": {"status": "passed", "file": "build.log", "sha256": "<evidence SHA-256>"},
    "tests": {"status": "passed", "file": "tests.log", "sha256": "<evidence SHA-256>"}
  }
}
```

Evidence paths are relative to the receipt, and their exact bytes are hashed.
This is a reviewed build record, **not a cryptographic build attestation**:
the publisher cannot infer passing tests from free-form logs or prove a claimed
source commit produced a binary. Review provenance independently. Setup's hash
must come from that review. The Authenticode field records the reviewed state;
this Mac-side tool does not run Windows SignTool. Unsigned beta remains explicit;
stable promotion is rejected. Ed25519 verification is performed cryptographically
for both metadata domains, followed by compatibility/expiry and payload hashes.

Single-object uploads are bounded to 512 MiB. Larger releases require a separately
reviewed multipart implementation. The tool snapshots the candidate to a local
temporary file, so concurrent source-file changes cannot replace approved bytes.
It sends `PutObject` with `If-None-Match: *`, Standard class and private/no-store
metadata. A pre-existing key is never overwritten; a 412 response is followed by
complete readback, which succeeds only for the identical hash/length. A transport
failure can leave an uploaded object; rerun the same reviewed plan to verify it.
No failure deletes anything, changes a latest pointer or promotes a release.

## Credentials and approval bundle

Publisher: **Object Read & Write on only `vynic-installers`**, not Admin, all
buckets, DNS or Workers deployment. Read is needed for complete readback. This
credential is stronger than the tool: treat it as capable of replacing/removing
bucket objects; the tool's conditional writes are not a provider-enforced
append-only permission. Choose an expiry/rotation owner before creation. A
short-lived key scoped to the exact object is preferable where available, using
the optional session-token input. Do not create a broad token speculatively.

The publisher accepts only `VYNIC_R2_PUBLISH_ACCESS_KEY_ID`,
`VYNIC_R2_PUBLISH_SECRET_ACCESS_KEY`, and optional
`VYNIC_R2_PUBLISH_SESSION_TOKEN` in its process environment. It does not discover
ambient AWS credentials, write credential files, accept alternate endpoints or
print provider response bodies. Configure approved credentials through the
secret manager/release runner UI, never chat, source, build logs or CLI arguments.
No CI secret or protected environment has been created here.

Runtime: a separate read-only R2 credential or a specifically approved Worker
binding/access design. Never reuse the publisher secret in the backend, client
or Worker. Do not claim an ordinary Worker R2 binding is inherently read-only;
review the runtime binding and deployment permissions separately.

Before the first real upload approve one concrete bundle: source artifact path,
expected archive size/SHA, verified signed metadata and trusted key identity,
destination account/bucket/key, reviewed plan hash, publisher scope/expiry and
secret destination. Later runtime access/configuration, deployment, hostname
routing and public release announcements remain separate decisions.

Build18 was located locally and verified offline against the approved public
distribution, both Ed25519 metadata signatures and exact native evidence; it was
not uploaded by this task. Historical GitHub draft asset: GitHub draft asset `673319647`,
`Vynic-Windows-1.0.1-build18-beta-offline.zip`, 47,038,575 bytes,
SHA-256 `3065c95c77012bbb5f421f83bb3118fe250f4c9f8ba4099e89a67c4e7ddcd4f7`.
The intended key is
`windows/beta/1.0.1/build18/Vynic-Windows-1.0.1-build18-beta-offline.zip`.
The inspected local source is `/tmp/vynic-beta-candidate-1.0.1-18-entitlement/`
and the public trust file is `/tmp/vynic-beta-distribution-20261024.json`.
The external task evidence includes `build18-r2-upload-plan.json` and
`build18-r2-qualification.json`; native build/test logs verify 335 historical
Windows tests, not qualification of the new integrated candidate.
Setup SHA-256 is `72fdefa2d155a1ebbf3b086fb3acfec229f01f2910593ea12f13d294c0067464`.
Reviewed-plan candidate digest is
`2052aa966fff4ac508918a5c3c67e621b97b1c10e20400b2c8a43c653891cec7`
(pending approval, not executed). Metadata expiration and
fresh-install-only restrictions from `WINDOWS_BETA_TEST_INSTALL.md` still apply.

## Go/Windows integration audit

| Component | Source/build proof | Current behavior |
| --- | --- | --- |
| Setup | `tool/build-setup.py` builds `./cmd/setup` for Windows/amd64, CGO disabled | Go compiled into Setup EXE; pinned public distribution embedded; no Go toolchain needed on customer PC |
| Edge | `tool/build-edge-windows.py` builds `./cmd/edge`; `internal/setup/metadata.go` requires `VynicEdge.exe`; `setup.go` extracts the signed Edge ZIP | Same-user local host; signed package/compatibility checks; retained Edge baseline |
| POS | Signed POS manifest and ZIP; `setup.go` requires `vynic_pos.exe` | Flutter application, not a Go executable |
| Startup/shortcuts | `internal/setup/native_windows.go` and `shortcuts_windows.go` | HKCU Run launches Setup `--host`; desktop/Start menu link launches Setup `--launch`; unrelated registrations refused |
| Update/rollback | `internal/updater`, `internal/setup/setup.go` | Explicit POS update, health/readiness checks and binary-only rollback; separate explicit signed POS+Edge upgrade with probation journal; no restaurant-data rollback |
| Uninstall | `Installer.Uninstall` and `NativeHost.RemoveIntegration` | Stops local processes safely, removes owned startup/shortcuts/binaries, retains Hive/identity/history/config; no data-deletion option |
| Printer agent | `cmd/printer-agent`, `packaging/windows/printer-agent/INSTALLATION_PLAN.md` | Separate **held** executable/bundle; absent from the current Setup build path; physical calls and mutating RPCs held |
| Backend | `apps/backend` | Remote NestJS service, not shipped as a Go executable |

Build18 publication evidence records Setup and Edge 1.0.1.18, POS 1.0.1 build18,
and exact packaged hashes. The exact local archive was inspected and verified offline in this task.
Current production printing stays on Flutter TCP/Windows RAW; this storage task
does not silently activate or install the held Go printer daemon. Licensing integration is included in beta19; build18 evidence does not qualify it.
Existing setup/updater regression sources cover interrupted swap, retained data,
wrong signatures, pinned Edge repair, startup health and rollback. They were rerun using the existing isolated Go toolchain; new coordinated
upgrade tests also passed. New publisher
tests use only synthetic ZIPs/keys and stubbed SDK calls. None proves real Windows
startup, driver/service permissions, clean install, licensing or printer output.

## Validation

```sh
python -m unittest discover -s apps/edge/tool -p publish_private_r2_test.py -v
python -m unittest discover -s apps/edge/tool -p windows_distribution_test.py -v
git diff --check
```

Official references:
[R2 S3 compatibility and atomic conditional writes](https://developers.cloudflare.com/r2/api/s3/api/),
[R2 bucket-scoped permissions](https://developers.cloudflare.com/r2/api/tokens/).

## Opt-in runtime wiring and activation gates

The Worker accepts only `https://releases.vynic.ge/windows/access/<grant-id>`
and its `/session` and `/file` children. Fragment capability exchange produces
an HttpOnly/Secure/SameSite=Strict cookie scoped to the grant. Every page,
session, HEAD and GET asks the existing backend for current issuer, ownership,
POS entitlement, expiry and revocation decisions. GET consumes the existing
atomic 16-request quota; HEAD does not. A single bounded Range is supported.
The machine endpoint is fixed to
`https://api.vynic.ge/customer/downloads/worker/authorize`; redirects are refused.
It receives only bounded JSON decisions, never installer bytes. The Worker uses
conditional R2 reads and validates pinned length/hash metadata, then streams
with workerd's fixed-length stream. Completed/failed audits contain no tokens.
A transfer admitted before revocation may finish; each subsequent range is
re-authorized. The publisher cryptographically hashes complete object readback;
runtime metadata checks do not claim to hash a whole ZIP on each range request.

Reviewed deployment settings (remote state verified separately from local configuration):

- Dedicated Worker `vynic-installer-downloads`, main `src/index.mjs`, compatibility
  date `2026-06-16`, no public workers.dev or preview URLs.
- `INSTALLERS` R2 binding to only `vynic-installers`. This standard binding can
  write at the platform level; reviewed source uses only `head`/`get`. Limit who
  can deploy code. No R2 publisher credential in this Worker.
- Dedicated random 32-byte machine secret encoded as 43-character base64url,
  stored in **Worker secret `DOWNLOAD_GATEWAY_SECRET`** and **Render backend
  secret `VYNIC_DOWNLOAD_GATEWAY_SECRET`**. Configured in Worker; saved in Render with its process redeploy still pending.
  Possession permits calling the machine gateway, but does not remove the need
  for a live grant token and authority checks. Logging request bodies, cookies,
  Authorization headers, full invitation URLs or secrets is prohibited.
- Backend opt-in env: `VYNIC_INSTALLER_STORAGE=r2-worker`,
  `VYNIC_INSTALLER_R2_KEY=<approved immutable key>`,
  `VYNIC_INSTALLER_BYTES=<verified size>`, `VYNIC_INSTALLER_SHA256=<verified SHA>`,
  `VYNIC_INSTALLER_WORKER_ORIGIN=https://releases.vynic.ge`.
  The default remains GitHub. Unknown modes fail closed. Existing GitHub grants
  do not match new `r2:` identities and require a fresh issued link.
- Only after upload/readback, staging checks and approval: activate only the approved Worker
  path route after complete DNS parity and cutover. Retain Render until rollback is
  qualified. A bucket custom domain remains disabled.

Publisher credentials belong in the approved release runner's protected secret
store (or a temporary process environment for one supervised local upload).
They do not belong in Codex MCP config, a checked-in `.env`, Windows installer,
Flutter defines, browser, Render, or runtime Worker. The approved seven-day local publisher is held in macOS Keychain, separate from runtime access. It expires on 2026-11-01; renewal is not automatic.
The local upload command is a manual release gate; automatic Windows CI and
protected-environment wiring remain unconfigured. Client installers contain
compiled Go binaries/public trust only, never Google SMTP or R2 secrets.

Local verification: `npm test` in `apps/installer-worker` includes Node denial,
CSRF, range, wrong metadata and truncated-stream tests plus actual workerd/R2
fixture GET/HEAD/Range/revocation. The isolated Miniflare test dependency has
patched `undici`/`sharp` overrides; npm audit reports zero findings. Backend
regressions cover machine-secret validation, retained live authority, pinned
artifact selection, atomic quota, HEAD, legacy provider and safe failures.

## Repeatable Worker deployment and CI access

`apps/installer-worker/wrangler.json` pins the account, Worker, private bucket,
compatibility date and intended path route. It deliberately disables workers.dev
and preview URLs. The route is prepared configuration, not proof of live DNS.
The local exact Wrangler dependency is installed from the lockfile. `npm run check`
runs 23 tests (including local workerd/R2) and a deployment dry run without account
credentials. Runtime tests read the same compatibility date and binding names.
`npm run deploy` uses only version upload and exact-version activation, with strict
configuration and preserved remote variables. It verifies the returned deployment
and its latest 100% traffic assignment. It never runs route, DNS, R2 object or secret
mutation commands. `npm run deploy:dry-run` packages that exact version-only path.
Route bootstrap remains a separate operator action (`npm run deploy:bootstrap`),
requiring its own zone permission; never run it before the DNS/parity gates pass.

GitHub Actions is the selected Worker code deployment service. Cloudflare Builds
remains unconnected/off: its user-token flow cannot provide the approved narrow
account-owned grant. Do not activate a second Worker deployment pipeline.

`.github/workflows/installer-worker.yml` runs only by explicit workflow_dispatch
on main with an approved full SHA equal to the run/checkout SHA. Its default
check-only mode has no environment secrets. A deployment needs passing checks,
`deploy=true`, and approval in `installer-worker-production`. That environment
allows only main, requires the owner reviewer and disables administrator bypass.
The owner may approve their own explicitly initiated release; this is not a
two-person approval policy. Official actions are commit-pinned and Node is pinned
to 22.23.4. Dependency installation and checks finish before credential injection.

The version-only command requires `WORKERS_CI_BRANCH=main`, a clean committed
checkout and the environment variable `VYNIC_WORKER_DEPLOY_ENABLED=true`.
It first checks deployment-read permission, uploads a version, rejects a changed
remote deployment before activation, deploys the exact returned UUID and verifies
that deployment at 100% traffic. Test/preflight/upload failures do not activate.
An ambiguous activation/readback failure requires dashboard inspection, not an
automatic retry or rollback. No distributed compare-and-swap is supplied by the
provider: avoid manual concurrent changes during a run; Actions serializes its
own runs without cancelling an in-flight deployment.

Credential `CLOUDFLARE_INSTALLER_WORKER_DEPLOY_TOKEN` belongs only in the protected
GitHub environment. The actual account-token review form supports exactly
Specified Workers -> vynic-installer-downloads -> Individual Workers Editor.
No other Worker, DNS/routes, KV or R2 administrative permissions are selected.
Editor can replace code/settings/secrets and operate through the existing private
R2 binding; this is a significant production credential, not read-only access.
A 90-day expiry is prepared; replacement requires deliberate secure handoff,
never automatic renewal. Token creation/storage and a successful live CI run
must be verified separately. Never print or capture the token in a tool record.

The route is a separate approved bootstrap operation. Ordinary CI cannot change
DNS/routes and may qualify/deploy the existing unrouted Worker before DNS cutover.
This does not make company download or Windows updates live. Full authoritative
DNS inventory, protected download GET/HEAD/Range/revocation proof, coordinated
Render configuration and installer acceptance remain their own activation gates.

Windows installer build/test/sign/upload is still separate and not implemented
by this Worker workflow. Artifact publication must preserve exact source/build
provenance, native install/enrollment/update qualification, package signatures,
explicit Authenticode status, immutable upload, full readback, and manifest-last
activation. Tests or Worker CI success alone do not qualify a Windows installer.

References: [Account-owned tokens](https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/),
[Worker permissions](https://developers.cloudflare.com/workers/authorization/workers/).

### Retiring the legacy GitHub download credential

`VYNIC_RELEASE_GITHUB_TOKEN` is consumed only by the legacy GitHub installer
provider and its startup storage diagnostic. With `VYNIC_INSTALLER_STORAGE` set
to `r2-worker`, configuration and startup return before reading that credential;
missing R2 configuration fails closed instead of falling back to GitHub. The
installer's bootstrap, POS feed, Edge archive and repair paths use the existing
Render release origin and do not consume this backend token. Preserve those
paths when routing only `/windows/access/*` to the Worker.

Before removing the backend variable and revoking the old token, prove a newly
issued company download link through the live Worker: authenticated GET, HEAD,
Range, full checksum, expiry, revocation and unauthorized denial. Check bootstrap,
POS feed, referenced archives and repair availability independently. Existing
GitHub grants are tied to their old artifact identity and require new links.
Only after that cutover is verified can the legacy token be retired; it has not
been revoked and no replacement is required merely to configure Worker CI.
