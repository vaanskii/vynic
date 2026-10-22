# MGR-04 — Manager data freshness and completeness

Status: **DONE** from runtime `4a46db340e9b29d0da95dd11ed75e6a379099e30`, qualified in a fresh exact-commit export. [Source-identified proof](proofs/MGR04_COMMITTED_4a46db3_2026-10-07.json).

Manager reads distinguish API availability, displayed data location, API read time,
POS source time, Cloud receipt time and completeness. Cached values keep their
original times and refresh failures; a successful API response does not imply that
an offline POS recently uploaded data. Empty, zero, disabled and unavailable states
remain distinct. The milestone changes read confidence, not POS ownership.

## Server provenance

The authenticated Device → Venue snapshot transaction writes existing Venue
`Setting` rows under `manager:data-freshness:` after the corresponding blocks have
actually been applied. There is no schema or migration change. `syncedAt` must carry
an explicit UTC/offset instant; missing, ambiguous or future source times remain
unknown. The POS sender now emits UTC. Cloud receipt time is recorded separately.
Existing snapshots without stamps are unknown until an accepted upload establishes
provenance. A primary-device change invalidates the previous device's stamps.

`X-Vynic-Data-Freshness` adds provenance without changing existing list/map response
shapes. Dashboard `snapshotAt` now represents its accepted POS source time, or null;
it never substitutes the time of a Manager GET. Full-dashboard stamps require the
applied tables, orders, daily summary and history. Partial realtime uploads, omitted
blocks and today-only summaries cannot advance unrelated full/all-time reads.

Accepted detailed ledger uploads establish per-business-date stamps from the actual
reconciled day completeness. Dashboard/Financials use the oldest applicable summary
and ledger source. A new summary cannot freshen an unchanged ledger. Ledger history,
summary, product and staff endpoints require coverage for every requested date;
uncovered ranges are unknown. Partial ledger values remain partial, including zero.
Before/after generation checks prevent concurrent uploads or primary replacement
from labeling a mixed response as known. Source markers roll back with failed sync.

Cloud-authoritative menu and counted-menu reads identify Cloud as their source;
unknown source-change time is displayed explicitly. Legacy report breakdowns remain
partial. Staff-performance attribution is unavailable in the existing read model. Top-items
is conservatively unavailable because completeness is unproven; analytics
enhancements remain separate deferred work. MGR-06 covers immutable payroll,
obligation and reserve corrections.

## Client cache and visible state

Each response and provenance are flushed as one Hive envelope, scoped to API origin,
authenticated Staff/Venue and the complete query. The cache cannot cross accounts,
origins, dates or periods. Late requests after logout, token/session replacement or
scope changes cannot publish or persist stale results. Unauthorized responses never
fall back to protected cached values. Unavailable/corrupt/closed caches are explicit.
A cache persistence failure leaves valid remote data visible with a warning and
invalidates the uncommitted fallback; it cannot manufacture a durable cached success.

Dashboard captures each subrequest independently. Failed history/reservation/menu
blocks retain prior same-query data with their original timestamps or show an
unavailable placeholder. They do not become empty successful lists. Each screen binds
status to the actual displayed response, so another query's successful read cannot
clear its error. Financials exposes all ledger-dependent reads; reservation query
changes fence old successes and failures. Dashboard loading recovers after login.

Dashboard, Live Status/Tables/Takeaway, Financials, Reservations, Counted Menus and
Menu Calculator show an expandable Georgian status panel. It distinguishes API
availability, cache/memory location and age, exact source/receipt/read UTC times,
completeness and per-block errors. Unknown source ages are explicit. Five-minute
source/read age is the UI stale threshold; it is not a sync guarantee. Panel age
updates every thirty seconds, and app resume refreshes the current screen. Guarded
Manager operations still complete only through the existing authoritative POS result.

## Verification

Exact committed verification passed 492 Flutter tests across 37 suites (31 MGR-04
cases and 461 regressions), 88 backend cases and 44 authenticated HTTP/PostgreSQL
cases. Coverage includes warm cache/API down, API up/POS stale, partial ledger,
one failed subrequest, new business day query failure, durable cache reopen, app
resume, account/origin/query fencing, concurrent generations, primary replacement,
atomic rollback and an actual COMPLETE-ledger → summary-only upload. Widget checks
include 360/640/1440 widths and 1×/2× text scales with repository Georgian fonts.

The synthetic runner is `apps/backend/tool/prove_mgr04_postgres.py`; it creates a
fresh loopback PostgreSQL cluster, replays migrations, exercises authenticated HTTP
requests and removes the owned cluster. No restaurant/customer database is used.
Dart analysis/format (19 files), TypeScript production compilation, new typed server
lint, unchanged-contract checks, Prisma validation and Manager/POS macOS development
builds all passed. Existing touched server lint debt remains unchanged (147 errors,
12 warnings); it is not reported as a clean legacy lint result. Independent source
and exact-commit evidence review found no open blocker.

Every tracked Git blob and symlink matched the runtime before and after verification.
Only build-generated CocoaPods checksum metadata was recorded and restored inside
the isolated export. Pre-existing WIP was excluded from verification and commits;
branch/stash and original shared documentation changes were preserved.

Windows VM operations remain HELD. macOS builds are development proof only.
POS-02 physical printer/driver/paper acceptance and broader release/production gates
remain pending and do not block this read-confidence milestone. No deployment,
credentials, privileged settings or live data changes are included.
