# OPS-03 — Locked composition and current advisory snapshot

Initial bounded inventory/advisory stage completed on 2026-10-14. The results
below preserve that initial snapshot. Compatible dependency/coverage fixes and
the final 5-package/11-ID source snapshot are qualified in
`OPS03_DEPENDENCY_REMEDIATION.md`. OPS-03 remains an open release gate: this is not
an exploit assessment, full image SBOM or rollout.

## Delivered tooling and scope

`scripts/release_inventory.py` reads six npm lockfile projects, four Pub locks,
two Go module declarations, the existing native Pod locks and container recipes.
It creates standard npm CycloneDX reports in isolated temporary workspaces using
lockfile-only/offline mode and no lifecycle scripts. It never installs or
upgrades dependencies. Original manifests/locks/environment files remain intact.

The tool records input SHA-256s, versions, dependency locations, direct/dev/optional
classification where the lock supports it, explicit unknown classifications,
SBOM coverage errors and digest pinning. It refuses changed inputs, unsupported
lock data, unsafe registry URLs and overwriting existing reports. Its default
network count is zero. Go rows are declared requirements, not the full resolved
MVS graph. A Pub transitive entry does not prove runtime versus development use.

```sh
python3 scripts/release_inventory_test.py
python3 scripts/release_inventory.py --output /absolute/fresh/report-directory \
  --go /absolute/path/to/existing/go
```

The prepared OSV body includes only reviewed public dependency ecosystem/name/
version values; application roots, local dependencies, unknown/private sources,
source code, `.env`, credentials and business fields are excluded. Registry
tokens, runtime overrides and proxy configuration are not forwarded by inventory
subprocesses. No global tools or security settings were changed.

Official formats/semantics: [npm SBOM](https://docs.npmjs.com/cli/v11/commands/npm-sbom/),
[OSV package queries](https://google.github.io/osv.dev/post-v1-query/),
[OSV batch queries and pagination](https://google.github.io/osv.dev/post-v1-querybatch/).

## Verified results

- 12 project/module lock scopes; **2,583 component occurrences**.
- **1,764 unique package/version queries**: npm 1,562; Pub 173; Go 29. The actual
  HTTPS query completed in 18 batches. All 107 matched public advisory records
  were fetched. Queries were not merely prepared or inferred from old scans.
- **41 package/version matches**, npm 40 and Go 1; **107 distinct advisory IDs**.
  These are database matches, not 107 confirmed exploits in Vynic. They include
  build/development/optional dependencies and several versions of some packages.
  Pub returned no matches for the queried versions; SDK/native/unqueried coverage
  remains open. The older October 4 backend-production npm count is not directly
  comparable to this cross-project OSV snapshot.
- Provider record severity labels: 4 critical, 52 high, 40 moderate, 6 low and
  5 unspecified. Four critical IDs concern `proxy-addr` 2.0.7, `handlebars` 4.7.9
  and `tar` 7.5.13. Reachability, deployed exposure and compatibility of fixes
  are still to be established; no automatic P0 or residual-risk acceptance is made.
- Go's `golang.org/x/net` v0.58.0 matched five Go advisory records. This stage
  does not replace a full effective module graph, standard-library or govulncheck
  call-path qualification.
- Tooling regression: **19 tests passed**.

Snapshot, matched dependency locations, exact IDs/fix-range evidence and input
hashes: `docs/proofs/OPS03_INVENTORY_3463ee40_2026-10-14/`.

## SBOM gaps found by verification

Eight npm CLI invocations emitted CycloneDX JSON; four failed with
`ESBOMPROBLEMS`. Coverage checking then rejected three emitted `omit-dev` reports
that omitted declared direct runtime dependencies. **Five reports qualify their
bounded lockfile scope; three have incomplete scope; four could not be generated.**

| Project | Build lock graph | npm omit-dev result |
| --- | --- | --- |
| Backend | Emitted/qualified | Incomplete: ten declared runtime dependencies missing, including Nest/Socket.IO |
| Platform web | Failed | Failed |
| Restaurant web | Emitted/qualified | Incomplete: React/React DOM missing |
| Vankisi | Failed | Failed |
| Shared website client | Emitted/qualified | Emitted/qualified; manifest has no direct runtime dependencies |
| CUSTOM template | Emitted/qualified | Incomplete: React/React DOM missing |

Platform/Vankisi failures point to the locked optional
`@tailwindcss/oxide-wasm32-wasi` dependency subgraphs lacking required emnapi/
wasm runtime edges. This does not establish that their current installed target
fails, but prevents qualifying the complete portable lock graph. No lockfile
was regenerated, dependency upgraded or missing edge silently ignored.

The raw npm omit-dev output is not used as proof that omitted libraries are
absent from a running backend or bundled website. The inventory's missing-direct
dependency check prevents that false conclusion. Frontends ship built static
bundles; package manifest scopes do not by themselves prove bundle reachability.

## Local container evidence captured during the initial audit

Read-only capture recorded six running Vynic container image IDs. Three image
objects were inspectable; three running frontend containers reference IDs not
available to `docker image inspect`. No image was pulled and no container was
restarted to repair that observation.

The runtime backend lockfile's whole-file hash differs from the checkout, while
its set of locked public name/version pairs matches the source. The Dockerfile
runs `npm prune`, which may rewrite lock metadata; a different hash alone is not
evidence of a version change. This does not attest the installed module graph,
compiled application source, image layers or release candidate. Container
environment values were not inspected. Mutable base tags and full OS/layer
vulnerability/provenance checks remain open.

## Continuation identified by the initial audit

Next: restore reproducible Platform/Vankisi lock graph completeness and qualify
a reliable runtime/build composition boundary, then trace actual exposed paths
and prepare compatible patches for matched runtime/parser/proxy dependencies.
Use a frozen candidate and record exact before/after versions and tests; do not
apply forced upgrades or npm's historical Prisma downgrade suggestion. Finish
image/OS, SDK/native-plugin and full effective Go graph/call-path checks before
the OPS-03 release gate can pass. Any accepted residual exception needs an owner,
rationale and expiry; none was accepted here.

Printer/POS-02 work remains deferred. OPS-01's denied restore remains paused.
No live user data, credentials, deployment, security setting, purchase, commit
or push occurred in this stage.
