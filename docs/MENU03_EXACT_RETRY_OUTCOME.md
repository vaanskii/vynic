# MENU-03 — durable exact mutation outcomes

Status: **DONE**, 2026-10-01 (Asia/Tbilisi). This closes MENU-03 only. Real Nest HTTP, production owner/Device guards, Prisma, disposable PostgreSQL, database/backend restart and native Flutter/Hive lost-ACK recovery pass. Evidence: [MENU03_2026-10-01.json](proofs/MENU03_2026-10-01.json). Historical audit findings are unchanged.

## Baseline

Branch `codex/docker-deployment-foundation`; starting HEAD `a6398a9b6e5332f9865cf1e1c39ec32a859a746e`. Before edits, the dirty status, stash listing and SHA-256 hashes of **267** existing WIP files were captured. All 265 unrelated files retain their bytes; existing hunks in project state/map remain unstaged beside narrowly committed current-fact updates. No reset, stash operation, rebase, unrelated merge, push, customer database or active POS storage access occurred.

| Completed milestone | Implementation | Proof/docs |
| --- | --- | --- |
| SEC-01 | `cb283d9` | `a403637` |
| SEC-02 | `038ece4` | `64d668f` |
| WEB-02 | `f453ab7` | `102b089` |
| MENU-02 | `a6da94a` | `e5997d6` |
| MENU-01 | `7493137` | `a6398a9` |

Starting Prisma tip: `20261012120000_web02_restore_public_info_authority` (62 migrations). Canonical Menu wire version stays **2**, local Menu protocol stays **1**, Hive stays **9**. Prisma stays **6.19.3**. No generated contracts/models were hand-edited; the installed Prisma client was regenerated normally.

The current Master Plan, MASTER_BACKLOG, IMPLEMENTATION_ROADMAP, POS_MENU_EDGE, EVIDENCE_AND_MATRICES, completed MENU-01/02 reports, project state/map, D030, implementation and adjacent tests governed this work. Historical line numbers were not treated as current code.

## Pre-fix reproduction

A new loopback PostgreSQL 17.10 cluster was initialized under `/private/tmp/vynic-menu03-pg-929c76aa`, port 55439, user `menu03_verify`. Every database name was checked absent before creation and recorded as verification-owned. Only synthetic data was used.

Before production edits, `/private/tmp/vynic-menu03-prefix.cjs` exercised the current `MenuCatalogService` through a real Nest listener, Device credential verification, Prisma and the original 62-migration database. For **each** CATEGORY, SUBCATEGORY, ITEM and VARIANT:

1. Create revision 1; M1 edits to revision 2 and records its original response.
2. Immediate exact retry returns the same business outcome.
3. M2 advances the same entity to revision 3.
4. Retry M1: actual top-level revision **2**, entity revision **3**, M2 fields.
5. Delete the entity, then retry M1: actual `deleted:false`, `entity:null`.
6. Retry the accepted DELETE after unrelated activity: stable delete outcome.
7. Change M1's patch while retaining its ID: `409 MUTATION_ID_REUSED`.

All four inconsistent UPSERT outcomes were reproduced. The proof preserves the inputs/results, reproduction source and source hash. This is independent of the historical mocked audit reproduction.

Root cause: the duplicate branch had historical `resultRevision`/`seq`, but reconstructed `entity` by querying the current mutable catalog. The row's field-level `changes` audit is not sufficient to reconstruct every original response, including no-op results and later deletion.

## Complete contract and writers

`normalizeMutation` validates one mutation: UUID mutation/entity IDs, supported entity type, UPSERT/DELETE, nonnegative expected revision, allowlisted typed patch, and optional `resolution:REAPPLY`. DELETE carries no patch. SHA-256 covers the normalized content excluding only mutationId; key order, trimmed names and normalized UUID casing have their existing semantics. Expected revision, entity identity/type, operation, patch and resolution remain part of the fingerprint.

An accepted HTTP 200 response consists of:

| Field | Durable meaning |
| --- | --- |
| `status` | `ACCEPTED` |
| `mutationId` | Original stable request identity |
| `entityType`, `entityId`, `operation` | Original target and operation |
| `revision` | That mutation's resulting node revision, including 0 for an already-missing DELETE |
| `sequence` | Venue sequence at acceptance; no-op outcomes need not advance it |
| `deleted` | That mutation's deletion result |
| `entity` | Complete canonical serialized node at acceptance, or null for DELETE |
| `duplicate` | Delivery metadata: false on original acceptance, true on replay |

All business-result fields are semantically identical on replay. The established `duplicate` flag deliberately describes the new delivery. JSONB key order is not a wire guarantee, so byte-for-byte JSON ordering is not claimed.

Canonical entity serialization retains stable protocol IDs (`posMenu*Id` or Cloud row ID), `revision` and `changeSeq`, plus:

- CATEGORY: slug, nameKa/nameEn, sendToKitchen, sortOrder.
- SUBCATEGORY: categoryId, slug, nameKa/nameEn, sortOrder.
- ITEM: categoryId/subcategoryId (including nulls), nameKa/nameEn, price, enabled, sendToKitchen, sortOrder.
- VARIANT: menuItemId, size, price.

Only one response/node is stored. No tree, whole catalog, credentials, Staff data, recipes or unrelated business state is captured. Resolution/actor/source remain in the existing immutable mutation audit fields and fingerprint; they were not extra fields in the accepted response and are not invented now.

Current writers are owner `CustomerCatalogController` → membership/commercial policy → `RestaurantFoundationService.mutate`, and enrolled Device `DeviceMenuController` → `EdgeDeviceGuard` → `MenuCatalogService.apply`. Device → Venue and owner membership → Venue remain server-owned. A client's `venueId` does not choose Device authority. Any ACTIVE enrolled Device can author the canonical Menu; no new primary restriction is introduced. Manager/mobile/website paths read the catalog; no current backend Staff mutation route exists. A future permissioned Staff writer must use this same service with resolved authority.

## Persistence, migration and immutability

Additive migration `20261013120000_menu03_exact_mutation_result` adds nullable JSONB `MenuCatalogMutation.acceptedResult`. The composite primary key `(venueId, mutationId)`, requestHash, expected/result revision, sequence, changes, actor, source, resolution, timestamps and indexes remain intact.

The existing Venue row lock serializes writes and concurrent duplicate requests. After the catalog update and sequence allocation, the service calls its existing canonical node serializer and builds the complete response. It creates the mutation row with that response inside the **same transaction** as the catalog, tombstones and owner audit. It returns the same response object after commit. Failure rolls the transaction back; no failure response is made durable.

On retry, fingerprint checking still precedes replay. `replayAcceptedMutation` validates the stored result's identity/operation/revision/sequence/deletion invariants and returns it with `duplicate:true`. It has no current catalog lookup. M2 never updates M1's row. Real tests compare the complete saved row before/after later edit, deletion and retries, including actor/source/resolution/time. Concurrent requests create one row and one owner audit. Damaged stored results fail explicitly with `500 MUTATION_RESULT_INVALID`.

No pruning or retention change is introduced. MENU-10 must retain the exact result for as long as it promises that mutation ID's retry horizon. Expiring outcomes in a future design requires an explicit retention-floor/resync contract; blindly deleting rows would permit reused IDs and duplicate effects.

Deployment order: apply the additive migration, generate the matching Prisma client, then update all writer processes. Old writer processes can still create null-result rows and do not provide this guarantee. An old backend rollback would restore the original replay defect even though the column/data remain; that is not a safe exact-outcome rollback. No deployed customer database was migrated here.

## Durable versus non-durable failures; existing rows

The current ledger persists **accepted** mutations only. Revision conflicts, input validation failures, parent/policy denials, auth failures, network/server errors and aborted transactions are not stored terminal outcomes. A retry re-evaluates the current conflict/policy; it is not promised the previous conflict body. Tests prove conflict currentRevision can change and denied/invalid IDs leave no accepted row. Existing auth, Venue mode and owner editing/commercial guards still apply before replay; a revoked or currently unauthorized principal gains no historical-result access.

Historical accepted rows lack the full original entity. The migration leaves them **NULL** without backfill. Even a current matching revision is not used to guess historical exactness. An exact legacy retry returns:

```json
{"code":"MUTATION_RESULT_UNAVAILABLE","mutationId":"<original UUID>","resyncRequired":true,"message":"This legacy mutation was accepted, but its original response was not recorded. Resync the catalog and review pending edits."}
```

HTTP status is 409, with no purported accepted entity/revision response. Changed-payload reuse is still refused first. The previous-schema fixture's entire old row hash remains identical across upgrade and retry; its result remains NULL.

The current POS explicitly requests a full catalog for this error. It retains the original entry as visible `rejected` with `lastError:MUTATION_RESULT_UNAVAILABLE`, retains and blocks same-entity pending successors and does not manufacture an ACK. Here `rejected` is the existing local review state, not a claim that the historical server never accepted it. `syncOnce` continues to report reachability according to its existing boolean contract, not universal mutation acceptance. An operator compares the current catalog and uses the existing explicit resolution controls; no blind new-ID retry or automatic discard occurs. The Dashboard displays its existing save failure/reload path. Legacy reconciliation and fleet compatibility remain explicit rollout considerations; MENU-09's capability gate is not implemented here.

## POS ACK and change-feed correctness

The historical mutation ACK is separate from the current catalog projection. An ACK marks **only its matching mutation ID** synced and rebases eligible same-entity successors through the MENU-02 local commit boundary. It never advances the feed cursor. Catch-up still uses the saved cursor and current nodes/tombstones, then advances the cursor to the feed high-water.

A small client guard ignores the **entity effect** of an accepted outcome whose sequence is already covered by the complete local feed. This prevents a historical UPSERT from resurrecting a later tombstone, and an old already-missing DELETE from removing a subsequently created node. Journal ACK processing still runs. Conflict bodies have no accepted sequence and retain their existing behavior. Backend feed/tombstone serialization is unchanged.

The real cross-layer run:

| Step | Observed result |
| --- | --- |
| Native writer PID 23508 starts from real Cloud/Hive | Feed cursor 29; original item price 10 |
| Local MENU-02 edits | M1 price 12; second independent item price 21; two flushed stable IDs |
| Real HTTP accepts M1 | Revision 2, sequence 30, entity price 12 |
| Consumer drops reply; native writer SIGKILL | M1 failedRetryable; second edit pending; no graceful Hive close |
| Backend applies M2 | Same item revision 3, sequence 31, price 13 |
| PostgreSQL and backend restart | Backend PID 23461 → 23531; durable result remains |
| Native reader PID 23576 reopens the same files | Original two mutation IDs and local edits survive |
| Real engine retries M1 | Duplicate ACK has original revision 2/price 12/sequence 30 |
| Second pending edit sends; catch-up from 29 | Second item price 21; final canonical price 13; cursor 32 |
| Repeat sync | No further mutation sends, no duplicates, no conflicts, both journal rows synced |

M1 is `94e35dd6-062a-4a35-afc0-814a326d8929`; the independent pending edit is `ffd31f31-87d9-4c49-87c9-5f763f347dd5`. Exactly one server row exists for M1. The writer's runner exit 1 is expected after killing its owned native descendant; the reader exits 0. Temporary Hive directories and credential fixtures are removed.

A separate real-Dart/Hive interleaving test adds a **same-entity successor during the retry wait**. It stays pending with its original ID and rebased revision; the original M1 alone becomes synced. If M2 really changed that same entity meanwhile, the successor produces the legitimate revision-3 conflict and remains visible until explicit resolution. This is not silently relabeled as synced or dropped to manufacture convergence.

## Real PostgreSQL / HTTP acceptance and storage

All four supported entity types pass immediate retry, later revision-3 edit, later deletion, stable accepted DELETE after unrelated activity, changed-payload refusal, and replay after backend/database restart. All accepted business fields compare equal. New tests also cover no-op UPSERT, missing DELETE, concurrent duplicate owner requests, server-only replay envelopes, legacy rows, non-durable conflicts/denials and service/Prisma re-instantiation.

Two Venues independently accept the same mutationId with their own entity/payload. A first attempt to replay A's body through B gets ID_UNAVAILABLE without A's entity; after B has its own outcome, mismatched content gets MUTATION_ID_REUSED. A forged client Venue selector changes nothing, foreign owner membership gets 404, and a shared/invalid Device key gets 401.

Fresh and immediate-previous-schema upgrade databases pass **63 migrations**, migrate status, all migration SHA-256 checksums, Prisma validate and empty schema diff. Upgrade preserves the pre-existing row byte/semantic data and leaves its snapshot unavailable. Only these new absent names were created in the isolated cluster: the pre-fix DB, two initial proof DBs and two final proof DBs. The first proof attempt stopped at a nullable-price type error in its Flutter test; it is recorded as failed, not counted as acceptance. The corrected run passes every acceptance case without skips.

| Entity kind | Sample rows | JSONB result bytes avg / min / max | Complete row bytes avg |
| --- | --- | --- | --- |
| CATEGORY | 12 | 501 / 282 / 522 | 928 |
| SUBCATEGORY | 5 | 503 / 285 / 565 | 907 |
| ITEM | 10 | 552 / 278 / 590 | 971 |
| VARIANT | 105 | 479 / 281 / 481 | 839 |

An additional 100 real HTTP variant mutations measured p50 **29.53 ms**, p95 **31.18 ms**, maximum **32.63 ms** on this synthetic loopback setup. These include credential verification and SQL, not just serialization. Typical incremental snapshot storage is roughly 0.5–0.6 KB per mutation; 10,000 such results are approximately 5–6 MB before indexes/WAL/backups/TOAST overhead. This is an estimate from measured row sizes, not a 10,000-row load qualification or a production capacity promise.

## Validation and files

- **148 backend tests / 14 suites pass**, zero skips: 10 new result/fingerprint unit tests; 11 new real HTTP/PostgreSQL MENU-03 tests; existing canonical catalog, owner foundation, cloud-menu admission, Device/enrollment and tenant/public-menu suites.
- **132 Flutter tests / 7 suites pass**, zero skips: new retry tests, MENU-02 durability, canonical sync, MENU-01 restore, backup completeness, Menu and captured-line identity.
- **9 Dashboard tests pass** in catalog-editor/cloud-menu-admin files, including stable-ID network retry and current-catalog reload.
- Native two-process POS proof and separate backend/PostgreSQL restart proof pass.
- Backend build and scoped typecheck pass. Six critical/new TypeScript files have **0 lint errors/warnings**; all four Dart files analyze cleanly.
- Two older test fixtures now explicitly provision SAAS, preserve the operator-assigned hostname, and assign an ACTIVE Website plan where required. Assertions and production guards are retained. Existing lint debt in these files: foundation 54 errors/6 warnings unchanged; Admin 9 errors/8 warnings versus 55/8 baseline (formatting reduces existing debt). No new lint debt.
- Broad all-test TypeScript check still reports five errors in three byte-identical starting-HEAD files: edge-foundation integration (`"bad"` UUID type), platform-control-plane integration (two nullable audit actors), platform-password tests (two incomplete principals). They are documented/deferred; no rules or unrelated tests are weakened.
- `git diff --check` passes; original WIP/stash survive. No push.

Implementation/migration/tests/tool files (15):

1. `apps/backend/prisma/schema.prisma`
2. `apps/backend/prisma/migrations/20261013120000_menu03_exact_mutation_result/migration.sql`
3. `apps/backend/src/menu-catalog/menu-catalog.service.ts`
4. `apps/backend/src/menu-catalog/menu-mutation-result.ts`
5. `apps/backend/src/menu-catalog/menu-mutation-result.spec.ts`
6. `apps/backend/src/menu-catalog/menu03-exact-retry.integration.spec.ts`
7. `apps/backend/test/menu03.fixture.ts`
8. `apps/backend/scripts/serve-menu03-local.ts`
9. `apps/backend/scripts/prove-menu03.py`
10. `apps/backend/src/customer/restaurant-foundation.integration.spec.ts`
11. `apps/backend/src/platform/cloud-menu-admin.integration.spec.ts`
12. `apps/operations/lib/core/services/menu/canonical_menu.dart`
13. `apps/operations/lib/core/services/menu/pos_menu_sync.dart`
14. `apps/operations/test/unit/menu03_retry_test.dart`
15. `apps/operations/test/live/menu03_ack_loss_test.dart`

Implementation commit: `f720bbc` (`fix(menu): replay durable original mutation outcomes`). Docs are this report, the JSON proof and narrow current state/map updates in a separate commit identified in the final report. No unrelated WIP is included.

Reproduce the new real proof with a newly initialized MENU03 loopback cluster and:

```sh
PGHOST=127.0.0.1 PGPORT=<owned-port> PGUSER=<test-user> \
  python3 apps/backend/scripts/prove-menu03.py \
  --tag <new-8-hex-tag> --proof-dir <new-temp-directory> \
  --cluster /private/tmp/vynic-menu03-pg-<tag> \
  --flutter <isolated-sdk>/bin/flutter
```

The harness guards cluster identity, verifies names absent, deploys fresh/previous chains, seeds synthetic identity records, exercises real HTTP, kills only its native child, restarts only its owned cluster, and cleans its databases by default. It never points to vankisi_database or normal local-prod databases. --keep was used during this task to permit focused regressions; all five verification-owned databases are subsequently dropped and the isolated cluster stopped.

## VYNIC MASTER ROADMAP STATUS

Reporting snapshot from the current original Master Plan/backlog and completed proof documents. Historical plans retain their audit-time text; completed proof documents establish the six closed milestones below. Existing code alone does not close a stabilization milestone. No percentage score is assigned.

| Milestone / Track | Status | Evidence / blocker | Next action |
| --- | --- | --- | --- |
| SEC-01 | DONE | SEC01 report/proof; trusted server booking amount | Preserve guard |
| SEC-02 | DONE | SEC02 report/proof; guest ownership isolation | Preserve binding |
| WEB-02 | DONE | WEB02 report/proof; safe publication upgrade | Preserve publication authority |
| MENU-02 | DONE | MENU02 report/proof; local WAL/native restart | Preserve local durability |
| MENU-01 | DONE | MENU01 report/proof; complete backup/native restore | Windows qualification under OPS-01 |
| MENU-03 | DONE | This report/proof; real HTTP/PG + native ACK loss | Next authorized milestone MENU-06 |
| Single-POS — MENU-06 | NOT_STARTED | Hard delete loses recipe/presentation authority | Implement retirement/historical references |
| Single-POS — MENU-09 | NOT_STARTED | Old-client capability gate missing | Version/enrollment/cutover matrix |
| Single-POS — POS-01 | NOT_STARTED | Close Day lacks durable transition | Journal + shared admission proof |
| Single-POS — POS-03 | NOT_STARTED | Transfer destination/source crash gap | Atomic recovery/conservation |
| Single-POS — POS-05 | NOT_STARTED | Concurrent table create can duplicate | Authoritative create serialization |
| Single-POS — POS-02 | NOT_STARTED | In-memory print jobs; uncertain TCP outcome | Durable jobs + physical printer tests |
| Single-POS — SEC-05 | NOT_STARTED | Backup encryption exists; local PIN/keystore/key custody incomplete | Secret storage/recovery qualification |
| Single-POS — OPS-01 | IMPLEMENTED_NOT_PROVEN | Release foundation/partial DB/native proofs; complete Windows/hardware/artifact dossier open | Qualify exact pilot release |
| Single-POS — PROD-01 | NOT_STARTED | Supported package/limitations not fully gated | Enforce one-primary/manual payment/scope |
| Manager — MGR-01 | NOT_STARTED | Hardcoded 9+4 layout | Generic Venue floors/tables |
| Manager — MGR-02 | NOT_STARTED | Free-table Cloud-only action | Authoritative POS result |
| Manager — MGR-05 | NOT_STARTED | Non-atomic line replacement | Durable command/atomic edit |
| Manager — MGR-03 | NOT_STARTED | Delivery states ignored by UI | Typed visible command lifecycle |
| Manager — MGR-04 | NOT_STARTED | Cache source/freshness/completeness missing | Explicit stale/partial states |
| Manager — MGR-06 | NOT_STARTED | Financial corrections lack reversal workflow | Immutable signed corrections |
| Inventory — existing subset integrity | IMPLEMENTED_NOT_PROVEN | Receiving/debt/recipe code exists; retirement/replay matrix open | MENU-06 + quantity/debt/cash/consumption proofs |
| Inventory — INV-02 | NOT_STARTED | Current cost/COGS/cashflow provenance unclear | Labels + costing provenance |
| Inventory — INV-04 | NOT_STARTED | Silent 100-row history limit | Cursor pagination/export |
| Inventory — INV-01 full Inventory | NOT_STARTED | Locations/transfers/waste/count/full domain incomplete | F1–F7 after subset integrity |
| Inventory — UX-02 | NOT_STARTED | Daily-work IA/novice-user acceptance open | Redesign after correctness |
| Website/payment — WEB-01 | NOT_STARTED | Transactional hold/late-payment race open | Hold + 20-client race proof |
| Website/payment — WEB-03 | NOT_STARTED | Paid link/dispatch durability gap | Transactional outbox/replay |
| Website/payment — WEB-04 | NOT_STARTED | Provider event ordering/amount/state ledger incomplete | Event ledger/reconciliation |
| Website/payment — WEB-06 | NOT_STARTED | Current integration selection nondeterministic | Rotation/readiness regression |
| Website/payment — SEC-03 | NOT_STARTED | Wider session/revocation/throttle matrix incomplete | Account lifecycle hardening |
| Website/payment — provider sandbox / OPS-01 proof | BLOCKED | Paid-booking gates and real provider acceptance unclosed | After WEB-01/03/04/06 + SEC-03 |
| Multi-POS — EDGE-01 | NOT_STARTED | Phase 2A is shadow; active shared authority absent | Authority/epochs/cutover after single-POS gates |
| Multi-POS — 3-terminal correctness | BLOCKED | Single-POS gates + EDGE-01 unclosed | Full race/partition/settlement matrix first |
| Multi-POS — 10-terminal scale/load | BLOCKED | 3-terminal correctness unproven | Bounded load after correctness |
| Security/operations — SEC-04 | NOT_STARTED | Public-media retention/removal policy open | Policy + cache/removal proof |
| Security/operations — SEC-06 | NOT_STARTED | Privacy/retention/rights/legal governance open | Before broad real personal-data collection |
| Security/operations — OPS-02 | NOT_STARTED | Local/LAN exposure hypothesis unqualified | Authorized port/firewall verification |
| Security/operations — OPS-03 | NOT_STARTED | Current SBOM/advisory/provenance matrix open | Scans + reachable-advisory triage |
| Polish/future — MENU-05 | NOT_STARTED | Same-ID inactive item restore workflow absent | After MENU-06 |
| Polish/future — MENU-07 | NOT_STARTED | Float/double monetary contract remains | Versioned money design/proof |
| Polish/future — MENU-08 | NOT_STARTED | Use-current resolution audit gap | Durable actor/reason/discard evidence |
| Polish/future — MENU-10 | NOT_STARTED | Unbounded feed/history; result retention now material | Pagination + retry horizon/retention floor |
| Polish/future — COM-01 (MENU-04 alias) | NOT_STARTED | POS-only owner editing still WEBSITE-gated | Authoring policy if offered |
| Polish/future — TECH-01 | NOT_STARTED | Broader static debt, including unchanged tsc errors | Separate targeted cleanup |
| Polish/future — PROD-02 | NOT_STARTED | Later integrations/automatic billing/KDS/themes | Only after core gates |
| CUSTOM website — WEB-05 | NOT_STARTED | Deployed build identity/readiness proof missing | Manifest + honest readiness |
| CUSTOM website — WEB-07 | NOT_STARTED | Shared hours/contact/gallery promise unclosed | Supported shared reads |
| Acquisition — UX-01 | NOT_STARTED | Demo request persistence gap from backlog | Approved durable request flow |

1. **Where are we?** The original first five milestones are closed. We are in Phase 6, Track A (single primary POS), with its first dependency MENU-03 now closed.
2. **Next milestone:** MENU-06, then MENU-09 → POS-01 → POS-03 → POS-05 → POS-02 → SEC-05 → OPS-01 → PROD-01. This report does not authorize or start it.
3. **Before a controlled single-POS pilot:** the nine remaining Track A gates above, plus exact Windows/printer/offline/restart/restore/tenant evidence and enforced product limitations. MENU-01/02/03 are closed. If POS-only owner editing or Inventory/Manager/website functionality is offered, its additional gates also apply.
4. **Can remain deferred:** Manager writes, full Inventory/UX, paid website/accounts, active multi-POS/10-terminal scale, broad polish and PROD-02 when excluded from the pilot through enforceable scope. MENU-10 scaling can wait for a small bounded pilot; exact-result history must not be pruned meanwhile. Scope-relevant privacy/security/operations obligations still apply.
5. **After single-POS stabilization:** Manager; existing Inventory integrity then full Inventory/UX; menu/contact Website qualification and paid reservations/provider proof; active three-terminal authority then ten-terminal load; wider security/operations; polish/future capabilities.

Deferred findings: MENU-06 retirement, MENU-09 rollout, MENU-10 feed/retention, SEC-05 local secret custody, OPS-01 Windows/hardware/release dossier, COM-01 authoring policy and unchanged broad static debt. **STOP after MENU-03. MENU-06 has not begun.**
