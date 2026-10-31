# Windows beta release pipeline

`windows-candidate.yml.example` is an **inactive candidate-build template**, not
an enabled publisher. It reuses the product preparation, Go build and public
trust configuration already used by beta19. Worker deployment is a separate
workflow and cannot publish installers.

The intended entry point is one explicit dispatch for an exact reviewed main
commit, a strictly newer semantic version and a strictly increasing build
counter. For example, beta19's `1.1.0 / 19` needs at least `1.1.1 / 20` under the
current updater contract. Raising only the build counter is rejected. The
checked-in floor is a historical minimum, not a substitute for checking the
currently active release immediately before publication.

## Implemented candidate gate

1. Check the exact requested SHA and public policy; run policy regressions and
   the portable Go installation/update engine tests.
2. On pinned Windows/Python/Go/Flutter, export only tracked source at that SHA
   into a new directory. Build jobs receive no signing or publishing secrets.
3. Enforce Pub lockfiles, run the ordinary Flutter unit/widget suite, prepare
   the production POS and compile it with the approved public licensing pin.
   Any baseline failure remains a failure; the script does not skip failures.
4. Build Edge, Setup and the explicit `asInvoker` native core harness. Check
   the compiled POS pin and native version. Record file hashes, toolchain
   identities and command-log hashes only after all preceding steps succeed.

The result explicitly says **unsigned candidate, native acceptance pending,
not uploaded, not promoted**. Candidate output is local to the runner. The
template deliberately does not use public-repository Actions artifacts for
private installer binaries. Enabling this template alone would not deliver a
release and is not the complete automation requested by the user.

Hosted Windows runners run with administrative privileges. They cannot prove
ordinary-user Setup behavior. `least_privilege_windows_test.go` refuses elevated
core qualification; do not remove that test, disable UAC or relabel compilation
as execution. A normal-user Windows run must still prove clean install,
enrollment, startup/restart, POS/Edge integration, simulated printer transport,
license outage/reconnect/revocation and compatible update/recovery. Do not use
real restaurant or physical printer data for this gate.

## Remaining publication gates

The signing/publication job is intentionally not wired until these dependencies
are qualified. It must consume the exact candidate bytes, not rebuild them in
a job containing production credentials.

| Stage | Required behavior / existing implementation |
| --- | --- |
| Windows publisher signature | `apps/edge/tool/sign-windows-release.py`: sign payload executables before ZIP/hash generation, sign Setup, verify exact trusted certificate and timestamp. No paid certificate has been selected or provisioned. Existing beta19 Setup is unsigned. |
| Package trust | Reuse `cmd/sign-pos-release` and `cmd/sign-bootstrap` with the existing approved Ed25519 release identity. These signatures do not establish Windows Authenticode publisher trust. CI access to its private key needs a separate approved destination and custody method. Never copy the licensing server key. |
| Final qualification | Verify signed nested payloads, metadata, source identity and final installer lifecycle; bind evidence to the final hashes. Signing changes bytes, so unsigned-candidate hashes are not final artifact hashes. |
| Private staging | Existing `tool/publish_private_r2.py` validates one offline ZIP, conditionally creates its immutable object, and verifies full readback. It does not publish the separate update/repair feeds. New CI publisher access requires exact bucket/destination/expiry approval. |
| Runtime equivalence | Complete and verify authenticated installer, update, bootstrap and repair paths; GET/HEAD/Range, expiry and revocation must work against actual clients. The current Worker access route alone does not cover every legacy release URL. |
| Promotion | Recheck active version/counters and remote object hashes; publish immutable payloads and version-specific signed metadata first. Activate the actual consumer manifest last, with a stale-state/concurrent-publication guard. Do not invent a `latest` object unused by the application. Preserve old immutable assets and monotonic counters. |

Until runtime equivalence and promotion are implemented, no job may report a
release as active. Failed checks must leave live pointers unchanged. A failure
after an uncertain remote write requires readback before retry, never an
unconditional overwrite or automatic downgrade. Native acceptance and
production credential-incident remediation remain distinct release gates.

## Credential inventory (names only)

| Credential | Destination / status |
| --- | --- |
| `CLOUDFLARE_INSTALLER_WORKER_DEPLOY_TOKEN` | Existing protected `installer-worker-production` GitHub environment. Only the named Worker; not the installer publisher. |
| `VYNIC_R2_PUBLISH_ACCESS_KEY_ID`, `VYNIC_R2_PUBLISH_SECRET_ACCESS_KEY`, optional `VYNIC_R2_PUBLISH_SESSION_TOKEN` | Proposed separate protected Windows publisher environment; **not configured or approved for CI yet**. Bucket-limited publisher access, expiry checked before release; no automatic renewal. |
| Ed25519 package signer | Existing local signer has not been copied into CI. Existing signing commands accept a private-key file; any CI/HSM integration and storage need an explicit grant and safe secret handling. |
| Authenticode signer | No credential provisioned. Select a verified eligible signing provider and approve cost/access separately. |
| `VYNIC_LICENSE_SIGNING_KEY` | Render server only. Never a build, signer or publisher job input; installer contains only the public pin. |

The historical GitHub release-read token cannot be removed until all live
bootstrap/repair/update dependencies have moved and been verified. Cloudflare
Worker CI neither needs that token nor renews any other credential.

## Local source checks

```sh
cd apps/edge/tool
python3 -m unittest windows_release_candidate_test -v
```

Run actionlint against the inactive YAML template. Cross-compiling
`build-windows-core-tests.py` verifies the PE resources but is not native test
execution. Retain separate evidence for every passed and never-run stage.
