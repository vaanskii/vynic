# OPS-03 — Qualified compatible dependency changes

The compatible source changes are integrated, uncommitted and not deployed.
OPS-03 remains an open release gate. Qualification uses an isolated copy of the
current dirty checkout; concurrency checks confirmed that its application source
and integration targets still matched the checkout before copying the changes.

## Scope and before/after

Six npm projects received targeted security version bounds or overrides and lock
updates: Backend, Platform, Vankisi, Restaurant, shared Website client and CUSTOM
starter. Unaffected direct versions were frozen during resolution; their existing
manifest ranges and intentional pins were restored. Prisma 6.19.3 and the
existing UUID/Glob policy were preserved. No schema, migration, generated contract,
application behavior, printer file, environment file or live data was changed.

| Bounded check | Initial inventory | Qualified source |
| --- | ---: | ---: |
| Public package/version queries | 1,764 | 1,733 |
| Matching package/version pairs | 41 | 5 |
| Distinct advisory IDs | 107 | 11 |
| Critical advisory IDs in this scope | 4 | 0 |
| Qualified npm build/runtime SBOMs | 5 | 12 |
| Incomplete / failed npm SBOMs | 3 / 4 | 0 / 0 |

The final HTTPS OSV query completed all 1,733 queries in 18 requests. Ninety-six
initial IDs no longer match the candidate; no new final IDs appeared. Remaining
record labels are five HIGH, one MODERATE and five unspecified. These are advisory
database matches, not confirmed exploits or an attestation of deployed binaries.
The final inventory contains 2,596 component occurrences across 12 project/module
scopes. Public queries contain only ecosystem/name/version; no source, environment,
credentials or business data was transmitted.

## Fixes and coverage

Runtime/parser/transport fixes include Axios 1.20.0, proxy-addr 2.0.8, qs 6.16.0,
Multer 2.4.0, Engine.IO 6.6.10, socket.io-parser 4.2.7 and backend Sharp 0.35.5.
Firebase/Google subtree fixes include busboy, gRPC, protobuf and XML dependencies;
specific optional SDK function exposure was not assumed. Build/development fixes
include Handlebars, Tar, Babel, YAML, PostCSS, Vite, router, source-map and browser
catalog dependencies. Exact location/version changes are recorded in
`docs/proofs/OPS03_REMEDIATION_3463ee40_2026-10-14/lock-deltas.json`.

Multer's first private update to 2.3.0 exposed another advisory in the second
scan; the final lock uses the upstream fixed 2.4.0 line. See the
[upstream advisory](https://github.com/expressjs/multer/security/advisories/GHSA-3pph-fpjx-jg34).
The fflate override is restricted to its vulnerable 0.6 branch, preserving the
existing unrelated 0.8.3 dependency. The XML parser's required dependency closure
and Sharp's matching native packages are part of their vendor version updates.

Platform/Vankisi locks now include the required optional WASM dependency closure.
`scripts/npm_lock_sbom.cjs` uses the existing npm Arborist lock reader and npm's
standard CycloneDX emitter. Runtime selection uses `node.dev` flags instead of
the npm CSS `.dev` selector, which dropped dependencies shared by production and
development. Missing required edges, including development edges in build scope
and required children of optional nodes, fail explicitly. The emitter includes
its npm version and Vynic scope-helper metadata. This is a qualified lock graph,
not a claim that frontend build packages execute in a browser.

```sh
python3 scripts/release_inventory_test.py
node --test scripts/npm_lock_sbom_test.cjs
python3 scripts/release_inventory.py --output /absolute/fresh/report-directory \
  --go /absolute/path/to/existing/go
```

The helper is qualified with npm 11.13.0; npm internal reader/emitter changes must
be requalified. No global tool, registry configuration or security setting was
changed. Inventory runs remain offline and do not install packages or execute
lifecycle scripts.

## Validation

- Six clean `npm ci --ignore-scripts` installations passed. Backend and Vankisi
  were reinstalled after their final Multer/fflate changes. Prisma generation was
  explicit, isolated and did not connect to a database.
- Backend build and four web builds passed; shared Website client typecheck passed.
- Backend aggregate: **906 passed, 0 failed, 895 skipped**. Additional real HTTP,
  PostgreSQL and Socket.IO cases: **81 passed**, covering website auth admission,
  guest ownership, CUSTOM binding, Manager tenant isolation and Admin domains.
  There are **987 distinct passed backend cases**; 814 other opt-in cases were not
  executed. Repeated parameterized titles are distinguished by occurrence.
- Web: **284 passed** (Platform 256, Restaurant 19, shared client 6, starter 3).
  Website artifact-manifest tests: **7 passed**. Inventory: **19 Python + 4 Node
  cases passed**.
- Integration preserved existing source WIP and verified environment bytes. The
  checkout's installed `node_modules` and running Docker images were not replaced.
  Tests/builds used the qualified private installation.

Initial private setup failures and subsequent corrections remain in the proof
receipt: short PostgreSQL socket path, source-only cross-repository fixtures and
synthetic refresh-token test configuration. An earlier CUSTOM HTTP 403 did not
recur in the corrected candidate or original-dependency comparison; its individual
cause was not established. The final standalone CUSTOM suite passed 17/17 in both.
Only verification-owned loopback databases were used, and the owned cluster is
stopped. This is macOS/Node 24.16.0 qualification, not a Linux/Node 22 image build.

## Remaining decisions and gates

| Remaining dependency | Actual bounded scope | Next decision/work |
| --- | --- | --- |
| deepmerge-ts 7.1.5 | Declared Backend runtime graph through Prisma config; no HTTP merge call found. Advisory requires recursive object pairs, not plain JSON alone. | Choose and qualify a Prisma-supported fixed tree, or explicitly authorize/test the major 8.0.0 override. Current Prisma pins remain. |
| Sharp 0.34.5 | Vankisi development image tooling; Backend upload path is already on 0.35.5. | Authorize and qualify the 0.35 minor-boundary update and image tooling output. |
| braces 3.0.3 | Backend build and Vankisi lint/glob tooling. | No fixed-version event is recorded; track an upstream fix or separately qualify removing/replacing its consumers. |
| sprintf-js 1.0.3 | Backend test/YAML/argparse subtree; no request-controlled format path found. | No fixed-version event is recorded; qualify a fixed upstream/replacement tree. |
| golang.org/x/net v0.58.0 | Shared Edge/generated Go module requirements; five HTTP/2 records. | Full effective module/stdlib/call-path qualification, then test v0.60.0 within the approved generated/printer boundary. No Go/printer files were changed. |

No residual risk was accepted or advisory suppressed. The full 41-package/107-ID
triage records graph paths and source entry-point distinctions, with vulnerable
function reachability explicitly unproven where it was not established.

Image/OS layers and digest/provenance, effective Go graph and standard library,
SDK/native plugins and deployed candidate attestation remain release gates.
There was no deployment, service restart, commit or push. Printer work stays
deferred; OPS-01's denied restore remains paused.

Evidence: `docs/proofs/OPS03_REMEDIATION_3463ee40_2026-10-14/qualification.json`,
`remaining-advisories.json`, `triage.json`, final public OSV results and 12
CycloneDX reports in the same directory.
