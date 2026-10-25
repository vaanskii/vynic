# Private R2 Windows beta publisher

`apps/edge/tool/publish_private_r2.py` is the final, manually approved upload
stage for a qualified **complete offline Windows beta ZIP**. It does not build,
sign, install, deploy, publish a GitHub release, activate downloads or updates,
modify bucket access, or delete files. The existing local LAN publisher remains
development-only. There is no checked-in Windows release CI workflow at base
`bf7bd647`; this adds a callable release stage without silently turning every
build into a distribution event. No source or binary was pushed by this change.

## Current storage and delivery boundary

On 2026-10-25 the user activated R2. The separately authorized bucket
`vynic-installers` was created with Standard storage and Automatic location
(Cloudflare chose Eastern Europe/EEUR). Dashboard verification showed 0 B,
Public Access disabled, public development URL disabled and no custom domain.
No object, publisher credential, Worker binding or billing add-on was created.

The current backend still reads a protected GitHub draft asset. Its provider
HEAD 403 remains a separate delivery blocker. A new bucket alone cannot repair
that route. `releases.vynic.ge` currently uses Render as a technical origin:
only `/windows/access/*` forwards the selector to the backend; the root/catalog
and public artifacts remain closed. Do not delete this Render site or change
the public `vynic-releases` repository visibility: the repository also supplies
the site. No DNS migration is part of this publisher.

The proposed later route is authenticated download request -> live issuer,
membership, expiry/revocation and POS entitlement check -> fixed private R2
object stream. An authorization Worker may use a **Worker custom hostname**;
that is distinct from a public R2 bucket custom domain, which stays disabled.
Preserve the current capability/CSRF/cookie, HEAD/Range and no-store semantics,
and recheck authority for every admitted transfer/range. Do not redirect users
to a public object URL or long-lived presigned storage URL. Before replacing the
Render origin, qualify anonymous denial, revocation, entitlement loss, complete
and resumed download, safe errors and old-link behavior. Source wiring is now implemented in `apps/installer-worker` and the backend
`installer-worker-gateway` controller. It is opt-in and has not been deployed.
No additional subscription is assumed.

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
does not silently activate or install the held Go printer daemon. Licensing integration awaits its final reviewed handoff; its new behavior is
not qualified by build18 evidence.
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

## Opt-in runtime wiring (source only)

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

Reviewed deployment settings, still **unapplied**:

- Dedicated Worker `vynic-installer-downloads`, main `src/index.mjs`, compatibility
  date `2026-07-01`, no public workers.dev or preview URLs.
- `INSTALLERS` R2 binding to only `vynic-installers`. This standard binding can
  write at the platform level; reviewed source uses only `head`/`get`. Limit who
  can deploy code. No R2 publisher credential in this Worker.
- Dedicated random 32-byte machine secret encoded as 43-character base64url,
  stored in **Worker secret `DOWNLOAD_GATEWAY_SECRET`** and **Render backend
  secret `VYNIC_DOWNLOAD_GATEWAY_SECRET`**. Not yet generated or configured.
  Possession permits calling the machine gateway, but does not remove the need
  for a live grant token and authority checks. Logging request bodies, cookies,
  Authorization headers, full invitation URLs or secrets is prohibited.
- Backend opt-in env: `VYNIC_INSTALLER_STORAGE=r2-worker`,
  `VYNIC_INSTALLER_R2_KEY=<approved immutable key>`,
  `VYNIC_INSTALLER_BYTES=<verified size>`, `VYNIC_INSTALLER_SHA256=<verified SHA>`,
  `VYNIC_INSTALLER_WORKER_ORIGIN=https://releases.vynic.ge`.
  The default remains GitHub. Unknown modes fail closed. Existing GitHub grants
  do not match new `r2:` identities and require a fresh issued link.
- Only after upload/readback, staging checks and approval: attach the Worker
  custom hostname and update DNS/routing. Retain Render until rollback is
  qualified. A bucket custom domain remains disabled.

Publisher credentials belong in the approved release runner's protected secret
store (or a temporary process environment for one supervised local upload).
They do not belong in Codex MCP config, a checked-in `.env`, Windows installer,
Flutter defines, browser, Render, or runtime Worker. No such secret was created.
The local upload command is a manual release gate; automatic Windows CI and
protected-environment wiring remain unconfigured. Client installers contain
compiled Go binaries/public trust only, never Google SMTP or R2 secrets.

Local verification: `npm test` in `apps/installer-worker` includes Node denial,
CSRF, range, wrong metadata and truncated-stream tests plus actual workerd/R2
fixture GET/HEAD/Range/revocation. The isolated Miniflare test dependency has
patched `undici`/`sharp` overrides; npm audit reports zero findings. Backend
regressions cover machine-secret validation, retained live authority, pinned
artifact selection, atomic quota, HEAD, legacy provider and safe failures.
