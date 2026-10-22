# OPS-03 — Remaining dependency, image and native qualification

This bounded read-only follow-up made no dependency, printer, credential,
environment, live-data or service changes. No software was installed, no image
was pulled/built and no deployment/push occurred. The Mac command interface
temporarily stopped responding; after recovery, the previously unstarted image
scans completed. Evidence is under
`docs/proofs/OPS03_REMAINING_3463ee40_2026-10-15/`.

## Concrete dependency decision

Recommended bundle, **not implemented or approved by this report**:

1. Qualify a scoped `@prisma/config -> deepmerge-ts: 8.0.0` override while retaining
   Prisma/client/config 6.19.3. Test config loading, generate/validate, fresh
   disposable migrations and the relevant aggregate/HTTP regressions before
   integration. No schema/data migration is inherent in this library override.
2. Remove Vankisi's unused direct Sharp devDependency after an isolated clean
   install/build and artifact check. Its lock node has only the Vankisi root dev
   edge; no import, Vite plugin or application script call was found. Backend
   Sharp and its real upload path are separate and remain on qualified source
   0.35.5.

Deepmerge's HIGH advisory affects 7.1.5. Vynic's entry is
`apps/backend/prisma.config.ts:2`, importing `@prisma/config`. In its installed
6.19.3 implementation, `loadConfigTsOrJs` imports Deepmerge at `dist/index.js:894`
and passes `deepmerge` to c12's config loader at line 917. Vynic HTTP handlers
do not call it. The advisory requires recursive object pairs; ordinary JSON
does not create those cycles. The local config uses strings for schema/URL,
not Maps/custom merge metadata. This limits the observed surface without
accepting risk or claiming exploit impossibility.

Version 8 preserves ESM/CJS exports and Node >=16, but changes default nested Map
merging, custom merge metadata/types and mutation behavior, while fixing circular
handling. [Upstream release](https://github.com/RebeccaStevens/deepmerge-ts/releases/tag/v8.0.0),
[advisory](https://github.com/RebeccaStevens/deepmerge-ts/security/advisories/GHSA-ggr8-5vv4-36mx).
The queried latest `@prisma/config 7.10.0` still pins Deepmerge 7.1.5; upgrading
Prisma alone is not a verified fix and would widen scope into adapters/ESM/runtime
changes. The scoped major override remains a compatibility decision.

Vankisi Sharp 0.34.5 has three HIGH matches involving native libvips/libheif/
librsvg decoding. No Vynic call site in that frontend was found; this is installed
build tooling, not a demonstrated browser/request decoder. If retained/upgraded,
0.35 requires Node >=20.9, changes AVIF output tuning, removes legacy constructor/
metadata/sharpen options and the install fallback, and updates native binaries.
[Sharp breaking changes](https://sharp.pixelplumbing.com/changelog/v0.35.0/).
Removing the unused dependency is the smaller candidate; confirm with a clean
build rather than introducing those native/API changes unnecessarily.

## Upstream blockers

- **braces HIGH:** published latest remains 3.0.3, affected. Backend ts-loader/
  micromatch and Vankisi lint/glob paths use it; no HTTP-controlled pattern path
  was found. The depth-fix [PR 72](https://github.com/micromatch/braces/pull/72)
  is closed without a fixed release. A local fork/backport needs its own review,
  ownership and compatibility proof; it is not a normal supported version bump.
- **sprintf-js MODERATE:** published latest 1.1.3 is also affected. Backend
  ts-jest/coverage -> js-yaml 3 -> argparse 1 brings in 1.0.3. The
  [upstream precision issue](https://github.com/alexei/sprintf.js/issues/237)
  remains open. Do not force a Jest downgrade or YAML/argparse major override.
  No request-controlled format call was found. No exception was accepted.

## Existing image checks

Docker Scout 1.24.0 analyzed exactly the existing local IDs with `local://`; no
registry image lookup or suppression filter was used. These are installed-package
matches, not exploit reachability. Critical/high labels below are derived from
SARIF `security-severity` score thresholds, rather than counting unspecified tags.

| Running image | Finding instances | Unique advisory rules | Critical / High |
| --- | ---: | ---: | ---: |
| Backend | 122 | 121 | 5 / 40 |
| Reverse proxy | 63 | 55 | 6 / 35 |
| PostgreSQL | 157 | 157 | 9 / 47 |

Backend SBOM has 667 components and reports Node 22.23.3. Its application packages
remain pre-remediation (proxy-addr 2.0.7, Multer 2.1.1, Axios 1.18.0, Sharp 0.35.4).
The qualified checkout changes are not deployed. Critical examples include Perl
updates to Debian `5.36.0-7+deb12u4`, proxy-addr 2.0.8, OpenSSL distro updates and
third-party Traefik/Go stdlib packages. Exact IDs/fix versions are in the evidence;
no live patch or shared repository Go change was made.

The three running frontend image objects remain unavailable to image inspection.
Their read-only installed OS/package inventory was obtained from the containers:
nginx 1.28.2 and Alpine 3.23 are present. Full image CVE/layer/provenance qualification
for those three remains open. Scout's attestation message alone is not a verified
signature or approved candidate provenance. Deployment recipe tags remain mutable.

## Native and SDK coverage

The nearly empty CocoaPods locks omit the main native dependency mechanism:
SwiftPM workspace locks contain 13 macOS and 19 iOS pins (32 occurrences), including
Firebase 12.14.0 and gRPC binary 1.69.1. Three iOS dependencies are commit/branch
pins. Installed metadata identifies Flutter 3.44.1, Dart 3.12.1, Xcode 27.0 and
Apple SDK 27.0; plugin registrant metadata was read without building/installing.

An actual OSV request queried 26 distinct native-version/source-commit/SDK entries
using the schema's `SwiftURL` ecosystem and public commits. No matches returned.
The historical Swift control also returned no match, so this run does not
independently validate lookup coverage and **does not qualify native/SDK clean**.
Swift package wrappers do not attest their embedded C/C++ binary contents.
Android's resolved Maven graph and Windows release native artifacts were not
qualified. [OSV ecosystem semantics](https://ossf.github.io/osv-schema/).

Shared Edge/generated Go graph, stdlib and call-path work is deferred under the
printer-last instruction. No repository Go build, print service or printer test
was run. The independent current-image scan of third-party Traefik is separate.

## Continuation

OPS-03 remains open for the bundled dependency decision, upstream blockers,
frontend image coverage, SDK/native binary coverage and approved Linux release
artifact/digest/provenance qualification. Source package findings and current
image findings are different snapshots and must not be added together.

The user's newly requested POS checkout/reservation/estimate UX and accounting
work is now the next non-printer implementation milestone. Preserve existing
advance accounting and offline ownership; hold expiry/refunds/cancellation/excess
advance require existing policy or an explicit decision. Breaking upgrades remain
unapproved and are not part of that POS milestone.
