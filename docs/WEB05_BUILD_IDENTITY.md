# WEB-05 — CUSTOM build identity and operator evidence

Status: **source and local candidate qualification complete**. Production
deployment/acceptance remains separate. Evidence:
[`WEB05_IDENTITY_3463ee40_2026-10-13/qualification.json`](proofs/WEB05_IDENTITY_3463ee40_2026-10-13/qualification.json).

The previous checker treated HTTP reachability and a matching restaurant name
as evidence of the intended site. Different Venues can share a name, and the
right API can sit behind the wrong frontend. Checks now compare stable public
Venue correlation, renderer/app identity, reviewed artifact fingerprint and
the HTML actually returned by the checked host.

## Contract and workflow

`GET /api/website/venue` adds optional `identity.venue`: a deterministic,
namespaced SHA-256 of the server-resolved Venue UUID. Renaming a Venue does not
change it. It is public correlation metadata, never a tenant selector,
authentication credential or proof of authorization. Host → VenueDomain → Venue
remains authoritative. Older clients ignore the additive field; an older
server without it is explicitly `UNVERIFIED` by the operator checker.

After a Vankisi or SaaS build, the shared Node script emits
`dist/vynic-site-manifest.json` with schema v1, renderer, app key, public
`buildId`, `htmlDigest` and file count. It hashes the sorted emitted file names,
lengths and bytes, including public assets, while excluding the manifest itself.
No repository identity, filesystem path, environment, credentials or private
configuration enters the public metadata. Vankisi's reader and manifest use
the same `src/config/siteIdentity.json` app key. Future custom frontends can
call the same generator; adopting the optional starter remains unnecessary.

An operator reviews a candidate artifact, then records its public fingerprint
in `expectedBuildId` through the existing Platform-only setup route. Owners
and SUPPORT_READONLY cannot write it. A key change clears the previous
fingerprint unless a replacement is explicitly supplied. Changes produce
`venue.custom_website_build_changed` audit events in the same transaction.
Exact metadata retries neither create another event nor change `updatedAt`.

The checker fetches only `/`, `/api/website/venue` and
`/vynic-site-manifest.json` on the server-selected ACTIVE domain, on one pinned
validated address. It refuses redirects; bodies are bounded to 64 KiB, partial
responses fail, each request has an absolute five-second deadline, and one
in-flight check per Venue is allowed per service instance. Existing public-IP,
TLS, production/local/Docker destination and authorization protections remain.
Legacy/missing manifests or unrecorded fingerprints never become verified.
Context is read before and after observation; changed binding, commercial
access, mode or domain makes the observation stale. UI query cancellation,
epochs and a Venue-keyed component prevent delayed checks or another Venue's
draft from restoring old successful evidence.

| Separate fact | Meaning |
|---|---|
| Commercial access | Effective WEBSITE access |
| Domain registration | The checked hostname is an ACTIVE server-owned domain; this alone does not prove DNS/TLS |
| Renderer deployed | A valid manifest and the served HTML digest match |
| Binding identity verified | Stable Venue/app identity and independently recorded build match current context |
| Publication live | ACTIVE operator attestation plus current matching observed serving evidence |

**SETUP_PENDING/ERROR public serving behavior is unchanged.** Status remains
operator tracking; this phase does not introduce a global public ACTIVE gate,
automatically activate/deactivate a site, or gate payment return/callback
reconciliation. A different serving policy needs separate approval.

## Artifact and migration qualification

The frontend Dockerfile preserves the monorepo layout and shared imports.
Platform type/regression compilation has its actual bespoke dependencies.
Runtime public files exclude stock Nginx pages, so the served tree matches the
reviewed emitted artifact. The temporary build step runs as root to remove
stock files; every final image remains user `101`. The manifest route returns
404 rather than SPA fallback when absent, uses no-cache and retains nosniff.

Migration `20261021120000_custom_website_build_identity` adds only the nullable
column. Fresh 75-migration databases and populated 74→75 upgrade pass. The
synthetic legacy Venue/binding values, timestamps, statuses and 74 historical
migration checksum records remain unchanged; legacy fingerprints remain null.
Prisma validation passes. No live migration or data repair was performed.

| Verification | Final result |
|---|---|
| Backend aggregate | 864 passed, 0 failed, 850 opt-in skips |
| Real CUSTOM PostgreSQL/HTTP | 17 passed, including 2 new grouped identity/audit/race scenarios |
| Shared-info PostgreSQL/HTTP regression | 8 passed |
| Backend case records executed in this phase | 889 passed; 825 opt-in cases not executed |
| Runtime checker | 21 passed, included in aggregate |
| Frontend aggregate | 246 passed, including 13 new operator scenarios |
| Shared client | 6 passed, typecheck passed |
| Manifest generator | 7 passed |
| Type/build | Backend and three frontend builds/types passed |
| Lint | New code clean; existing `api.ts` explicit-any unchanged; inherited integration-fixture 167 errors/9 warnings unchanged |
| Local Docker candidates | Three built; Nginx syntax passed; final user 101 |
| Complete emitted tree fingerprint | Vankisi and SaaS image extractions match their manifests |
| Actual local artifact HTTP probe | Correct CUSTOM verified; same-context SaaS and Platform artifacts refused |
| Browser | Real panel at 375/768/1440; no overflow, visible focus, wrong-build/error/retry/save invalidation passed |

The historical CUSTOM payment fixture had anonymously held table1 on November
2 and then tried another A booking on that same whole day. The signed A case
now uses November 3; the real whole-day protection is retained. A Trial expired
by an earlier case is renewed only in the independent synthetic identity case.

Docker proof uses a whitelist of frontend code/public assets; no env, git or
credential directories are copied. Local tags are retained for review. Test
and extraction containers are removed, the owned preview/PostgreSQL are stopped,
and browser tab/viewport are cleaned up. All changes are uncommitted.

## Practical limits and next work

This is metadata/HTML consistency inspection, not signed remote attestation:
it does not download and hash every remote asset or prove application behavior
on a production host. Offline extraction proves all emitted candidate bytes;
browser QA uses a synthetic API seam around the real panel. PUBLIC_HTTPS,
LOCAL_DEVELOPMENT and LOCAL_DOCKER observations are explicitly distinguished.
No production origin, DNS/TLS, registry publication, real provider payment,
fleet/hardware or restore acceptance is claimed.

The read-only CustomWebsiteService payment badge still uses an unordered BOG
`findFirst`; moving that badge to the existing current-revision selector is a
separate safe follow-up, not part of this identity change. POS-02.C continues
independently and INV-01.F2 decisions remain pending.
