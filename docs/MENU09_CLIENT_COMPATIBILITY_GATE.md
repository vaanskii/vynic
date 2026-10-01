# MENU-09 — canonical Menu client compatibility

**DONE — 2026-10-02.** Scope: admission, reconnect, explicit legacy cutover and
client proof only. One linear Master Plan; STOP after MENU-09. POS-01 is next
for a separate request. No other milestone started.

Machine-readable evidence: [MENU09_2026-10-02.json](proofs/MENU09_2026-10-02.json).
Starting branch `codex/docker-deployment-foundation`, HEAD
`583d328b7f3a1dc7519310b4bcee661710d8f715`; 267 original WIP files and
`stash@{0}: On main: reorg-wip-holdout` preserved. The proof records prior
SEC-01/02, WEB-02, MENU-02/01/03/06 commit pairs. No push or customer database use.

## Reproduced defect and correction

Before production edits, the real Nest listener, enrollment/Device guards,
Prisma and disposable PostgreSQL at migration 64 admitted a client without
canonical support into a CLOUD Venue. Its local price 777 snapshot returned
HTTP 201 `success: true`; Cloud price stayed 10 while a reserved table/bill 70
persisted. This reproduced misleading aggregate success, not just a source concern.

The legacy writer deliberately protected canonical Menu by skipping snapshots.
Enrollment and full-sync lacked protocol admission. MENU-09 now rejects an
incompatible CLOUD request with HTTP 426 `MENU_UPDATE_REQUIRED`, before
enrollment/code consumption or full-snapshot writes. Even a compatible client
submitting a CLOUD Menu snapshot receives 426
`CANONICAL_MENU_SNAPSHOT_UNSUPPORTED`; it must bootstrap/adopt and use the
canonical mutation journal. Supplying Menu with `realtimeOnly: true` also rejects.
Safe realtime requests without Menu remain available. Successful full-sync
responses explicitly distinguish `LEGACY_APPLIED`, `CANONICAL_SEPARATE` and
`NOT_REQUESTED`. Canonical convergence still belongs to journal/change-feed ACKs.

## Signal and trust map

| Signal | Source / authenticated authority | Persistence / control / freshness | Admission use |
|---|---|---|---|
| Marketing app version | pubspec `1.0.0+1`; updater `VYNIC_POS_UPDATE_VERSION`; process fallback `VYNIC_APP_VERSION` | Build/process controlled; reported with Device/code; display string | Never infer protocol or order SemVer |
| Integer build | New compile define `VYNIC_APP_BUILD` | Nullable; client controlled; Device report timestamp | Compare only with configured server integer floor |
| Platform | Enrollment input; subsequently stored Device.platform | Client self-report at enrollment; authenticated Device thereafter | Runtime/retry use stored platform; supported CLOUD desktop platforms WINDOWS/MACOS/LINUX |
| Enrollment | Secret code created for a server-bound Venue | Existing DeviceEnrollment/code lifecycle; no client Venue selector | Capability checked before claim, credential rotation and primary selection under Venue lock |
| Runtime config | Device credential → server Venue/features/mode | Existing safe local cache; Device.lastSeenAt connectivity | Current capability header required for CLOUD before returning config |
| Foundation bootstrap | Device-bound protocol v1, still staged/nonactive | Existing foundation semantics unchanged | Current capability header required for CLOUD |
| Credential poll/heartbeat | Edge/Device guard | lastSeenAt persists connectivity; no capability evidence | Cannot refresh capability freshness |
| Menu check-in | POST `/edge/menu-client/check-in`; current Device credential | New JSONB report + observedAt; caller may update only itself | Typed compatibility result, including unsupported; report does not grant future requests |
| Menu requests / full sync | `X-Vynic-Menu-Client` JSON header on authenticated requests | Same normalized Device report, writes throttled to 60s if unchanged | Gate evaluates the current report each time, never cached support |
| Canonical wire | Menu protocol v2 | Existing mutations/results/revisions/change feed | Explicit capability represents this supported client implementation |
| Local Menu / Hive / backup | Local protocol v1, Hive v9, portable backup v2 | Restaurant state/journals; source capabilities and credentials not imported | No authority to admit a restored installation |
| Update readiness/version endpoints | Existing POS updater and signed release metadata | Release availability/readiness, not running Device proof | Keep existing updater; no new fleet updater or binary attestation |

Authentication binds a declaration to a Device/Venue; it does not attest the
binary. A compromised supported client can lie about its build/capabilities.
There is no new cross-Venue or build-derived tenancy. An ordinary historical
client lacking the contract fails closed. Capability/build declarations come
from the running process and are not restaurant backup data.

## Contract and build policy

One capability is sufficient: `CANONICAL_MENU_V2`. It represents the existing
canonical bootstrap, entity journal, durable exact retry and retained retirement
implementation; individual implementation details are not separate switches.

```json
{"version":1,"capabilities":["CANONICAL_MENU_V2"],"appVersion":"1.0.0+1","buildNumber":null}
```

Enrollment sends optional `menuClient`; subsequent requests send its JSON in
`X-Vynic-Menu-Client`. Reports validate shape, bounded version/capability fields
and a nonnegative safe integer build. Missing support → `CAPABILITY_MISSING`;
unknown CLOUD platform → `MODE_UNSUPPORTED`; configured missing/below-floor
build → `UPDATE_REQUIRED`; admitted → `SUPPORTED`. Malformed reports return 400.
Failure text explains in Georgian that an update is required and restaurant data
has not changed. Compatibility failures return 426, not a generic 500.

Optional server environment:
`MENU_CANONICAL_MIN_BUILD_WINDOWS`, `MENU_CANONICAL_MIN_BUILD_MACOS`,
`MENU_CANONICAL_MIN_BUILD_LINUX`. Unset means capability-only admission; no
invented minimum. Values must be strict unsigned decimal safe integers. Invalid
configuration fails explicitly for CLOUD; legacy POS admission remains independent.
Existing release packaging has no reliable integer build signal, so enabling a
floor requires stamping `--dart-define=VYNIC_APP_BUILD=<integer>` into every
supported release. Display versions and updater environment strings cannot satisfy it.
All backend instances must use the same policy. Raising a floor immediately
affects new enrollment, retained-Device retry and reconnect; readiness re-evaluates
the current deployment policy.

## Admission, recovery and client experience

CLOUD enrollment rejects before creating/reactivating a Device, consuming a code
or rotating a credential. Same-installation retry also checks the retained
Device platform under the Venue lock. An incompatible installed Device receives
426 at runtime config, foundation bootstrap, catalog/change-feed/retired reads,
mutation endpoints and full sync. Previously cached compatible metadata cannot
admit a request with a missing capability.

Current Flutter sends the process report through enrollment, shared sync headers
and Menu transport. It displays a persistent Georgian update/adoption warning
on POS routes. Failed full sync cannot clear pending work or report success;
mutation refusal leaves the original journal entry/ID untouched. A new CLOUD
snapshot rejection triggers authority refresh and existing explicit adoption.
It never silently replaces a local legacy menu. Network failures preserve the
last explicit compatibility warning and local data.

Safe recovery endpoints, credential-authenticated Edge work, audit/report sync
and realtime operational snapshots without Menu remain governed by their existing
auth/primary rules. Local backup, inspection, updates, acknowledged offline edits
and captured Orders/Sales remain available. No per-Order Cloud dependency or
new operational primary/shared-authority model is introduced. Revoked credentials
remain refused. Old binaries may show their existing generic HTTP failure; this
does not claim an upgrade to their UI. They cannot receive false Menu success.

## Explicit POS → CLOUD cutover runbook

1. Keep the Venue in POS authority. Back up restaurant data and reconcile all
   acknowledged local Menu edits on every terminal. Inventory **all ACTIVE**
   Devices, including forgotten non-primary terminals. Update each or use its
   existing DISABLED/REVOKED lifecycle with operator authorization.
2. Bring every relevant POS online. Each running client must send a fresh report
   through normal Menu/config activity or authenticated check-in. Generic
   lastSeenAt does not prove capability. Unknown/stale capability blocks cutover;
   freshness is 15 minutes, not a licence for perpetual connectivity.
3. Finish the operational primary's final legacy identity-v1 full Menu sync.
   Its server `lastLegacyMenuSyncAt` must be within 15 minutes. A legacy client
   can continue normal snapshots before cutover; current clients do not migrate
   the Venue simply by reporting support.
4. Owner GET `/customer/venues/:venueId/menu-rollout`. Readiness combines D030's
   primary/first-sync/identity checks, every ACTIVE Device's capability/current
   minimum/freshness and valid unique stable UUIDs across every retained node.
   Missing/invalid/colliding identities require explicit reconciliation/resync;
   this gate never rewrites IDs, recipes, presentation, historical prices or revisions.
5. Resolve blockers and fetch a fresh `READY_FOR_CUTOVER` preview. The token
   covers fleet lifecycle/reports/build policy, authority, primary and actual
   legacy catalog rows (legacy writes do not advance canonical revision).
6. Owner POST the following to `/customer/venues/:venueId/menu-rollout/cutover`:

   ```json
   {"readinessToken":"<fresh preview token>","allPosOnline":true,"finalLegacySyncConfirmed":true,"noPendingLocalMenuEdits":true,"reason":"Operator reconciliation evidence"}
   ```

   Within one Venue-locked transaction, the backend rechecks ownership,
   commercial POS feature, readiness and token; then switches POS→CLOUD and
   writes immutable cutover/audit evidence. Changed preview → 409; missing
   confirmations → 400; blocked fleet → 409. The authority change is never automatic.
7. Each compatible POS bootstraps and explicitly adopts Cloud using the existing
   Menu adoption workflow if its local baseline differs. Check canonical ACKs;
   generic full-sync `CANONICAL_SEPARATE` is not a Menu ACK. Retain backups/local
   pending intent until reviewed. Replacement devices require fresh enrollment;
   their operational primary activation still follows existing fencing rules.

The server cannot prove an offline terminal has no unuploaded edits. A fresh
report and primary sync alone do not establish that. The three operator
confirmations are an explicit human boundary, recorded with reason/actor/time,
not an automatic assertion that local state is empty. Non-primary pending edits
must also be reviewed; current operational policy permits only the primary's
legacy snapshot ingestion. Unsure → abort cutover and reconcile while still POS.

The owner fleet inventory shows Device identity/platform/lifecycle, primary,
lastSeenAt, report timestamp, app/build/capabilities, compatibility and final
legacy sync. It returns no Device secret. Inactive/revoked devices are retained
for visibility and excluded from ACTIVE readiness; their old credentials do not
work. Freshness expiration and any lifecycle/catalog/policy change are evaluated
again at the cutover transaction.

## Rollback and tenant boundary

Before cutover, abort and leave POS authority intact. After activation, update
clients and recover through retained journals/backups. CLOUD→POS rollback is
explicitly refused with 409 `MENU_ROLLBACK_UNSUPPORTED`: independent histories
have no safe automatic merge. Do not deploy a historical backend that silently
skips snapshots/destructively writes retirement, remove new columns, or switch
authority with direct SQL. Application rollback must retain these admission and
retirement invariants; no legacy downgrade release was qualified here.

Two real Venues prove the same old client remains allowed for POS and rejected
for CLOUD, without changing the other Venue. An Owner cannot read/cut over a
foreign Venue (404); Device-supplied foreign selectors cannot select mode or
write another Device report (400); unauthenticated metadata writes fail (401).
All authority derives from Device→Venue/code→Venue or Owner membership.

## Acceptance and validation

Real loopback Nest/production guards/services/Prisma/PostgreSQL acceptance has
**17/17 passing cases, zero skipped**: all 15 requested cases plus invalid/colliding
legacy identities and changed-catalog preview. Case 15 restarts Nest; the native
bridge additionally restarts actual PostgreSQL and a separate backend process,
proving all stored reports/cutovers identical before/after. Notification sinks
have no external workers; database/Menu/table/order ingestion is real. Revocation
uses the existing durable Device status and actual credential rejection.

Native Flutter/Hive writer 90900 → reader 90970, backend 90851 → 90919:
compatible enrollment/bootstrap, offline price edit 15 and Sale captured at 7,
durable pending mutation/backup, restart/reconnect, fresh empty-directory restore,
unsupported fresh enrollment and mutation rejection without data loss, then
supported fresh enrollment/new Device and exact retry. Sale hash remains
`c485b665494a8c52254044ab07289a23c41e5224c5d12bf1fc3dd48cc57ae1ef`.
Portable restore copied neither credentials nor admission metadata.

Targeted backend regressions: 13 suites / 192 tests, plus onboarding 1 suite /
6 tests on its required phase3-named owned database, and 4 policy unit tests.
Flutter regressions: 130 tests covering MENU-01/02/03/06, enrollment, warning UI,
canonical history and Sale consumption. Separate native MENU-01 fresh/repeated
restore and SIGKILL/startup replay pass. Backend production build and targeted
Dart analysis pass. New backend files lint clean; touched legacy-file lint debt
is unchanged. Global `tsc --noEmit` has five pre-existing errors in three
byte-identical untouched test files (recorded in proof); no broad TECH-01 cleanup.

Migration `20261015120000_menu09_client_compatibility` adds four nullable fields:
Device.report/observedAt/finalLegacySyncAt and Venue.cutover (actual schema names
`menuClientReport`, `menuClientObservedAt`, `lastLegacyMenuSyncAt`, `menuCutover`).
Fresh chain and immediate-previous empty/populated upgrades pass; ten populated
authority table hashes are unchanged. All 65 database checksums, migrate status,
Prisma validate and empty schema diff pass; original 64 migration SQL files are
byte-identical. Only five checked-absent verification databases in an owned private
PG17 cluster were used; all were removed, cluster stopped/deleted, private native
credentials/Hive removed. No normal local-prod/Vankisi/customer storage was touched.

Small loopback fixture timing: enrollment 73.00 ms total, check-in median 26.32 ms,
bootstrap median 28.48 ms; compatibility transaction alone median 1.06 ms
(10 measured samples after two warmups). Authentication/Argon2 and payload work
are included in HTTP timing. This is observational overhead, not fleet/load
qualification. Identical report writes are throttled; no per-Order lookup added.

Re-run the HTTP spec with `MENU09_TEST_DATABASE_URL` naming a newly owned
disposable migrated database; missing acceptance DB throws rather than skips.
Native runner takes its checked-absent ownership/environment manifest, Flutter
path and an owned PG17 cluster, then creates/removes fresh Hive/credential fixtures.
Run the HTTP matrix before the native runner so a real cutover exists for restart
verification. Do not point these proofs at active POS or customer storage.

No trustworthy archived historical Windows artifact was available. The exact
missing-header/legacy-snapshot protocol fixture proves the gate; it does not
qualify all old binaries. Physical Windows/replacement/printer and signed release
packaging qualification remain OPS-01. Menu/fleet load remains MENU-10/EDGE-01.

## VYNIC MASTER ROADMAP STATUS

One linear plan. Existing implementation alone does not close a milestone's proof.

| Ordered stage | Item status |
|---|---|
| COMPLETED | SEC-01 DONE; SEC-02 DONE; WEB-02 DONE; MENU-02 DONE; MENU-01 DONE; MENU-03 DONE; MENU-06 DONE; MENU-09 DONE |
| NEXT SINGLE-POS LINE | POS-01 NOT_STARTED → POS-03 NOT_STARTED → POS-05 NOT_STARTED → POS-02 NOT_STARTED → SEC-05 NOT_STARTED → OPS-01 IMPLEMENTED_NOT_PROVEN → PROD-01 NOT_STARTED |
| THEN MANAGER | MGR-01 NOT_STARTED → MGR-03 NOT_STARTED → MGR-04 NOT_STARTED → MGR-02 NOT_STARTED → MGR-05 NOT_STARTED → MGR-06 NOT_STARTED |
| THEN INVENTORY | dependable existing subset proof BLOCKED (POS Sale integrity) → INV-02 NOT_STARTED → INV-04 NOT_STARTED → INV-01 full Inventory BLOCKED (subset) → UX-02 NOT_STARTED |
| THEN WEBSITE / PAYMENTS | WEB-01 NOT_STARTED → WEB-03 NOT_STARTED → WEB-04 NOT_STARTED → WEB-06 NOT_STARTED → SEC-03 NOT_STARTED → provider sandbox/release proof NOT_STARTED → WEB-05 NOT_STARTED → WEB-07 NOT_STARTED → UX-01 NOT_STARTED (still open) |
| THEN MULTI-POS | EDGE-01 BLOCKED (single-POS gates) → 3-terminal correctness BLOCKED (active authority) → 10-terminal load/scale BLOCKED (3-terminal proof) |
| THEN REMAINING SECURITY / OPERATIONS | SEC-04 NOT_STARTED → SEC-06 NOT_STARTED → OPS-02 NOT_STARTED → OPS-03 NOT_STARTED |
| THEN REMAINING MENU / POLISH / FUTURE | MENU-05 NOT_STARTED → MENU-07 NOT_STARTED → MENU-08 NOT_STARTED → MENU-10 NOT_STARTED → COM-01 NOT_STARTED → TECH-01 NOT_STARTED → PROD-02 NOT_STARTED |

1. We have completed the eight named milestones through MENU-09; single-POS
   stabilization is the next portion of the linear plan.
2. The one next milestone is **POS-01**. It has not started.
3. Controlled single-POS pilot still requires POS-01/03/05/02, SEC-05, OPS-01 and
   PROD-01, including actual Windows replacement, printers/cable/paper/power,
   credentials, deployment/restore and product-scope/card-reconciliation qualification.
4. Manager, Inventory, Website/payments, Multi-POS, remaining security/operations
   and Menu/polish/future stages remain in the order above.
5. No parallel milestone started. **STOP after MENU-09.**
