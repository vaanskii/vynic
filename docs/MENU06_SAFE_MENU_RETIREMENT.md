# MENU-06 — safe Menu retirement and historical Sale authority

**Status: DONE — 2026-10-02.** Implementation, additive migration, real guarded
HTTP/PostgreSQL, native Flutter/Hive restart and portable recovery are proven.
Only MENU-06 was implemented. MENU-09 and all other roadmap milestones remain
outside this change. Machine-readable evidence is
[MENU06_2026-10-02.json](proofs/MENU06_2026-10-02.json).

## Baseline and scope

Branch: `codex/docker-deployment-foundation`.
Starting HEAD: `c906ee2d5e45716cc4f05411e970e2d35090f253`.
Implementation: `1b5f5b17e1fc6e0798e780c59ae579d54b593f2c`.
The documentation commit is the commit containing this report; its hash is in the
final task report, avoiding a self-referential hash in this file.

SEC-01, SEC-02, WEB-02, MENU-02, MENU-01 and MENU-03 remain DONE. Their full commit
pairs are recorded in the proof. The original stash and 267 WIP file hashes were
recorded before edits. Original WIP is preserved, including the deployment,
commercial, enrollment, website motion and historical audit work. Only MENU-06
hunks are committed from the three already-dirty agent-state documents. No push,
reset, stash manipulation, rebase, normal customer database or historical audit
rewrite was performed.

## Pre-fix reproduction

Before production edits, the original 63-migration schema and starting backend
served a real Nest listener on an isolated PostgreSQL 17 cluster. Actual issued
Device credentials passed the production Device guard and operational-primary
check. Fixtures created an item, optionally a variant, a real consumption recipe,
website presentation, and a posted Receiving of 10 kg. The unsent historical
intent captured ten sold units at 0.200000 kg each, totaling 2.000000 kg.

| Canonical DELETE | Before | After | Delayed consumption |
|---|---|---|---|
| ITEM | Item + recipe + presentation | Item, recipe and presentation physically absent | HTTP 400; no consumption movement |
| VARIANT | Variant + variant recipe + item presentation | Variant and recipe absent; parent item/presentation survive | HTTP 400; no consumption movement |

Both failures said `Recipe does not belong to this Venue/product/revision`.
`prefix.json`, embedded in the proof, records the complete requests, responses,
identities and counts. This is a service/database/HTTP reproduction, not a mock.
The native Sale path below establishes actual local close/capture behavior after
fixing the defect.

## Destructive-path map

This map was established before changing production writers and checked again
against the final implementation. It distinguishes normal business writes from
explicit destruction of an entire disposable/development installation.

| Writer / path | Affected authority and original cascades | Tombstone / history risk | MENU-06 disposition |
|---|---|---|---|
| `MenuCatalogService.apply/remove`, Device `POST /edge/menu/mutations` | CATEGORY/SUBCATEGORY/ITEM/VARIANT; item→variants/recipes/presentation; variant→recipe | Canonical tombstones existed, but relational identity and unsent Sale recipe authority disappeared | Retire rows; same wire DELETE; item retires active variants; preserve recipes/presentation |
| Owner `POST /customer/venues/:venueId/catalog/mutations` | Same service and cascades as Device | Same risk; Dashboard currently has UPSERT editing, no separate delete UI | Same retirement boundary, real owner guard/membership checks; no permanent delete endpoint |
| Parent CATEGORY/SUBCATEGORY removal | Parent relations originally cascade to descendants | Could bypass child/history retention | Reject `NOT_EMPTY` while active children exist; allow parent retirement after child retirement; keep links |
| Legacy POS `MenuSyncService.sync/applySnapshot/syncItemVariants` | Omitted POS-owned variants/items/subcategories/categories were `deleteMany` cleanup | No canonical feed in POS-authority mode; recipes/config and delayed intents at risk | Child-first retirement, same Venue/ownership protections; identity-version gate; reappearance restores original IDs; CLOUD snapshots ignored |
| POS `MenuRepository` remove methods and variant edits | Local active Hive projection, then canonical journal or legacy snapshot | Must preserve Sales, capture and pending intent independently | Existing local projection removal retained; canonical server and legacy mirror now retire; Admin copy says archive |
| `MenuLocalStore` projection/capture/recovery and cache/import replacement | Rebuilds active projection; unresolved UPSERT could recreate a tombstoned node | A retired entity could reappear for ordering while local edit conflicted | Existing-identity UPSERT is excluded when canonical node is absent; original entries and successors remain durable for explicit resolution |
| `RecipeService.save` component-set replacement | Deletes the current recipe's component rows inside its save transaction; retains header/identity and increments revision | Historical capture must never be recalculated from today's components | Existing D014 behavior retained: frozen per-unit/total quantities and stock identities remain in the Sale; retirement itself changes no recipe/components; new recipe authoring requires active Menu selection |
| Recipe disable | `isActive` flag; no recipe-header purge endpoint | Historical resolver needs inactive/historical header | Retained; historical consumption/reversal are not filtered by retirement/active projection |
| `WebsiteMenuService.savePresentation/upsert` | Updates supplied presentation rows; omission does not delete others | Item cascade previously removed custom name/description/image/order settings | Retain original row; active write selection excludes retired items; same-ID restoration reveals saved settings |
| Prisma parent Menu FKs | CATEGORY→SUBCATEGORY/ITEM; SUBCATEGORY→ITEM; ITEM→VARIANT remain relational cascades | Direct SQL/old destructive backend could reach recipe/config descendants | Recipe→item, recipe→variant and presentation→item now RESTRICT; real physical item/variant/parent deletes with these dependencies fail `P2003`; normal writers never purge |
| Venue deletion / organization deletion | Existing restrictive business FKs protect Menu/Inventory/ledger rows; presentation has a Venue cascade | Whole-restaurant destruction must not masquerade as Menu administration | No new Venue purge route or behavior; normal retirement does not touch Venue/organization |
| Historical migrations | Existing Menu parent, recipe and presentation FK definitions | Old definitions explain the reproduction | All 63 migration SQL files/checksums unchanged; new migration changes only retirement columns and three dependency FKs |
| `scripts/reset-local-data.py` | Explicit whole macOS development installation reset; enumerates and truncates business tables together | Deliberately destroys restaurant data, including history; not a Menu purge | Remains an explicit operator development wipe: `--yes`, fixed loopback DB, process ownership checks, validated pg_dump, moved local stores and dependency/table manifest. Inspected only; **not executed** |
| Integration test teardown / cleanup fixtures | Direct model deletes, then owned Venue/organization cleanup | Deliberate synthetic fixture destruction, no user history | Remain destructive, scoped to synthetic IDs/disposable DBs; recipe-dependent teardown removes fixture dependencies explicitly; MENU-06 purge tests expect rejection |
| `prisma migrate reset`, Docker/volume/DB reset, proof cleanup | Whole test/development database, not an entity remove operation | Deliberate destruction of all data | Unsupported as business purge; MENU-06 cleanup drops only six newly created, checked-absent, ownership-recorded disposable DBs |
| Scheduled cleanup / normal purge / alternate presentation delete | No additional production writer found for these Menu/recipe/presentation rows | An undiscovered writer would be a bypass | Targeted source searches found no scheduled Menu purge or normal permanent-delete route; no such feature was added |

Normal permanent Menu purge is **unsupported**. Do not infer historical safety
from the absence of current Orders, and do not downgrade to destructive backend
writers. Database owner privileges and whole-installation wipes are outside the
normal product contract; FK protection cannot prevent an operator explicitly
destroying all dependencies or truncating a whole database.

## Retirement and restoration contract

`retiredAt: null` means retained active identity; a timestamp means retired.
`enabled` remains temporary availability. Retiring/restoring a disabled item keeps
`enabled: false`; an explicit acceptance case proves that distinction.

Canonical removal continues to use wire v2 `operation: DELETE`, returning
`deleted: true, entity: null` and creating the existing tombstone. Revision and
Venue sequence advance once; item removal tombstones each newly retired variant
at the same sequence. Existing retired variants are not rewritten. The audit
uses existing actor/source metadata and an ISO retirement timestamp. Recipes,
components, presentation and historical Sale/Order values are untouched.

Parents reject active children. A local POS subtree removal already journals
children before parents; direct server parent removal cannot erase descendants.
Retired children remain attached to retired parents for history.

Authenticated recovery views are `GET /edge/menu/retired` and
`GET /customer/venues/:venueId/catalog/retired`. The owner view retains the current
commercial/membership policy; COM-01's broader POS-only owner access is separate.
Restoration submits the same stable entity ID and its retained revision:

```json
{
  "mutationId": "a-new-uuid",
  "entityType": "ITEM",
  "entityId": "the-original-stable-uuid",
  "operation": "UPSERT",
  "expectedRevision": 2,
  "patch": { "restore": true }
}
```

Restore is explicit, advances revision/sequence, clears the current projection
tombstone and emits the node again. Restore parents first. Restoring an item does
not automatically restore its variants; restore each desired variant explicitly.
An ordinary UPSERT on retirement produces `REVISION_CONFLICT` with `deleted:true`
and no current active node. Restoring an active identity is rejected. Missing old
identity produces `HISTORICAL_IDENTITY_UNAVAILABLE`, not a reconstructed product.

MENU-03's immutable `acceptedResult` is unchanged. Original retries after
restore/re-retire and process/database restart return the stored outcome; only
the already-established `duplicate:true` delivery marker differs. Changed payload
under the same mutation ID remains `MUTATION_ID_REUSED`. Removing a current
projection tombstone on restore never rewrites the accepted mutation ledger.

## Active and historical reads

Shared `menu-active.ts` predicates exclude retired entities and retired parents.
They govern canonical snapshots/feed rows, Device/bootstrap and owner catalog,
Manager Menu, Inventory Menu selection and active recipe projection, supplier
quick-add selections, public legacy Menu, shared SaaS/CUSTOM presentation and
website readiness. Selected retired variants are rejected through parent and
legacy variant-ID booking paths. `enabled`/website visibility keep their existing
independent behavior.

History/consumption/reversal and historical report attribution retain their
existing Venue-scoped resolution, including retired rows. Frozen Sale quantities,
names, prices and references do not come from an active catalog query.

A pending POS edit against a removed canonical identity stays in the journal,
including its blocked successor. It cannot recreate an ordering node. Native
restart/backup proof and a focused unit regression show both original mutation
IDs and patches survive while the item is absent from selection.

## Migration

New tip: `20261014120000_menu06_safe_retirement`; previous tip:
`20261013120000_menu03_exact_mutation_result`.
Four nullable timestamp columns and three FK replacements are additive to the
model; no identity/revision/content rewrite or historical reconstruction occurs.
Prisma remains 6.19.3; Menu wire v2, local protocol v1, Hive v9 and backup format 2
remain unchanged. Generated Prisma client was regenerated, not hand-edited.

Fresh deploy and immediate-previous upgrade both reached 64 applied migrations.
`migrate status`, all local/database migration checksums, `prisma validate` and
schema diff passed; both diffs were empty. Ten authority-table hashes before and
after upgrade matched after excluding the new nullable field. The pre-fix missing
recipes/presentation stayed missing: migration invented nothing.

Rollback is a compatible forward deployment retaining columns, rows, FKs and
immutable results. Do not drop retirement metadata or restore destructive writers.
No automatic recovery is possible for an old missing recipe/config without
trustworthy evidence. An operator may reconcile an exact backup/audit/capture
under the existing tenant boundary; this task supplies no guessed ingredients,
quantities, replacement IDs or historical data repair.

## Real HTTP/PostgreSQL acceptance

Twelve MENU-06 cases exercise item/variant retention; delayed consumption;
four concurrent consumption retries; apply/retry/retire/reverse/retry; nested parent
rejection/restoration; disabled availability; explicit recovery; original retry
immutability; FK purge rejection; retired selection rejection; two-Venue negative
matrix; legacy omission/reappearance and CLOUD isolation; unavailable old identity.
SaaS and CUSTOM cases use actual Host guards for both public Menu shapes, with
owner/Device guards and real presentation restoration.

Foreign owner membership returns 404 without disclosure; foreign Device entity
editing conflicts without modifying the other Venue; missing credentials return
401. Foreign item, variant, recipe and stock references fail 400; altered captured
Sale content fails 409. The two Venues can use identical external item/variant
IDs and the same external Sale ID without sharing authority or effects.

For both item and variant, decimal stock movements are:

```text
RECEIVING             +10.000000 kg
CONSUMPTION             -2.000000 kg   (ten × 0.200000)
CONSUMPTION_REVERSAL     +2.000000 kg
FINAL                   10.000000 kg
```

Only one consumption and one reversal movement exist after retries. Recipe and
presentation rows compare equal across retirement, and the unsent intent remains
unchanged.

## Native POS / Hive / portable recovery

The checked-in `tool/prove_menu06_recovery.py` starts the real private Nest bridge,
uses an explicitly owned disposable-cluster manifest and launches native Flutter
processes. Native PIDs 68268 and 68339 are distinct. The writer:

1. Pulls real canonical Menu and Inventory recipes over enrolled Device HTTP.
2. Closes a synthetic fiscal Sale through `SalesRepository.saveSaleRecord` with
   the production close path's explicit `captureConsumption:true` option.
3. Captures ten units, 2.000000 kg and stable item/variant/recipe/Sale IDs. The
   captured price is 7 per unit/70 total while live Menu price is 10.
4. Keeps consumption unsent, records two local price edits, makes an encrypted
   backup and flushes Hive. The orchestrator verifies process ancestry and sends
   SIGKILL only to its own native writer after Cloud retires the item.

The reader reopens the same Hive stores, catches retirement, keeps both pending
edit IDs (one explicit conflict and one successor) and removes the item from
ordering. It makes a post-retirement backup while consumption remains pending,
restores it into a fresh directory, closes/reopens stores, and verifies inactive
selection, retained recipe capture and identical Sale values. No credential is
cloned; HTTP authentication is supplied independently by the private fixture.
Actual `SaleConsumptionSyncService` applies once; a forced ACK retry reaches HTTP
again without another movement. The captured Sale SHA-256 is identical excluding
only the separate inventory ACK field.

A pre-retirement backup is also restored on another fresh installation. Its old
offline projection is necessarily stale until synchronization; catch-up removes
the retired item and retains both pending IDs, and its delayed Sale retry creates
no duplicate consumption. A post-retirement backup is inactive immediately.
This task does not claim an offline machine can know a future Cloud retirement.

The bridge then exits, PostgreSQL restarts, and a new backend PID serves retries.
The stored retirement outcome and consumption ACK survive. Real HTTP reversal
and retry produce exactly one +2.000000 movement, returning stock to 10.000000.
No historical pricing is recalculated and no MGR-06 financial feature is added.

## Validation and limits

| Validation | Result |
|---|---|
| Backend focused matrix | 16 suites / **164 tests passed**, no skips (includes 12 new acceptance cases) |
| SEC-01 trusted booking price regression | **83 passed**; mock variants include the new nullable field |
| Flutter MENU-01/02/03/canonical/consumption | **103 passed** |
| Flutter captured Menu identity, closure money/audit | **68 passed** |
| Owner Dashboard Menu | **4 passed** |
| Native MENU-06 writer kill + reader + DB/backend restart | **PASS**, expected killed-writer exit 79; reader succeeds |
| Native MENU-01 portable/interrupted restore | **PASS**, distinct processes and owned SIGKILL/replay |
| Production Nest build | **PASS** |
| Flutter analysis of changed logic/native/unit proof and Admin copy | **No issues** |
| New typed backend boundaries/proof files | **0 lint errors / 0 warnings** |
| Existing 16 touched TypeScript files | **392 existing lint errors / 9 warnings**, unchanged from starting-content baseline |
| Full backend `tsc --noEmit` | Five existing errors in three unchanged test files; no new errors |
| Fresh + previous-schema migration, status/checksums/validate/diff | **PASS** |
| `git diff --check`, staged checks, WIP/stash verification | **PASS** |

Global typecheck debt remains the original invalid UUID literal in
`edge-foundation.integration.spec.ts`, two nullable actor accesses in
`platform-control-plane.integration.spec.ts` and two incomplete test principals
in `platform-password.spec.ts`. No rules were disabled and unrelated WIP was not
edited to make checks green. These are deferred TECH-01 debt, not hidden passes.

Small synthetic catalog measurements: eight active nodes/1,792 bytes; 50 warm
samples, median 1.762 ms and p95 2.459 ms. The fixture contained 69 categories,
69 subcategories, 69 items and 57 variants at measurement time. This is correctness
fixture timing, not production capacity evidence. A non-null PostgreSQL timestamp
datum is eight bytes plus row/alignment overhead. Retirement retains original
rows/config/recipes rather than copying an entire catalog. Retry creates no new
business rows; existing full-catalog/feed work and retention scaling remain MENU-10.

All six disposable DBs were checked absent before creation and ownership-recorded
before use. They were dropped after proof; their cluster was stopped/removed,
private credential fixtures and native Hive directories removed. Normal local,
customer and `vankisi_database` data were never used.

## Reproduce the proof

Use a new absent loopback `disposable_menu06_<tag>_*` database, owned by the run,
and deploy the current chain. Never pass an existing customer/local database.
The proof JSON records migration commands, checksums, source hashes, test commands,
inputs/results, logs and environment. For native proof, prepare a private
`/private/tmp/vynic-menu06-proof-<tag>/ownership.json` and environment JSON with
`freshUrl`, `proofDir`, `cluster`, `port`, `user` and ownership entries asserting
`absentBefore` and `verificationOwned`. The runner validates those preconditions;
it restarts that owned cluster, not a normal PostgreSQL service.

```sh
cd apps/backend
MENU06_TEST_DATABASE_URL='<owned disposable URL>' \
  MENU06_HTTP_PROOF='<private proof path>' \
  node_modules/.bin/jest --runInBand src/menu-catalog/menu06.integration.spec.ts

cd ../..
python3 apps/operations/tool/prove_menu06_recovery.py \
  --environment '<private owned-cluster environment JSON>' \
  --flutter '<installed Flutter executable>'
```

Run backend Jest from `apps/backend` (the equivalent short invocation is
`node_modules/.bin/jest --runInBand src/menu-catalog/menu06.integration.spec.ts`).
For the native runner, use a new proof directory; raw authentication material is
private, removed on completion and never copied into repository proof files.
The native writer's nonzero exit is an expected SIGKILL checkpoint, not a skipped
or failed acceptance case. Proof setup iterations are not counted as acceptance.

## Changed files

27 implementation/migration/test files and five documentation files are included.
The exact source hashes are in the proof.

```text
apps/backend/prisma/migrations/20261014120000_menu06_safe_retirement/migration.sql
apps/backend/prisma/schema.prisma
apps/backend/src/customer/restaurant-foundation.controller.ts
apps/backend/src/customer/restaurant-foundation.service.ts
apps/backend/src/inventory/inventory.service.ts
apps/backend/src/inventory/recipe.service.ts
apps/backend/src/menu-catalog/menu-active.ts
apps/backend/src/menu-catalog/menu-catalog.service.ts
apps/backend/src/menu-catalog/menu-mutation.ts
apps/backend/src/menu-catalog/menu06.integration.spec.ts
apps/backend/src/mobile/services/mobile-menu.service.ts
apps/backend/src/pos/sync/snapshot/menu-sync.integration.spec.ts
apps/backend/src/pos/sync/snapshot/menu-sync.service.spec.ts
apps/backend/src/pos/sync/snapshot/menu-sync.service.ts
apps/backend/src/website/core/website-menu.service.ts
apps/backend/src/website/core/website-w3.integration.spec.ts
apps/backend/src/website/menu/menu.service.ts
apps/backend/src/website/payment/booking-payment.spec.ts
apps/backend/src/website/tenancy/website-capabilities.service.ts
apps/backend/test/menu06-server.ts
apps/backend/test/menu06.fixture.ts
apps/backend/test/onboarding-app.fixture.ts
apps/operations/lib/apps/windows_pos/widgets/admin/admin_menu_section.dart
apps/operations/lib/core/services/menu/menu_local_store.dart
apps/operations/test/live/menu06_offline_sale_test.dart
apps/operations/test/unit/canonical_menu_sync_test.dart
apps/operations/tool/prove_menu06_recovery.py
docs/MENU06_SAFE_MENU_RETIREMENT.md
docs/proofs/MENU06_2026-10-02.json
docs/agent-state/VYNIC_PROJECT_STATE.md
docs/agent-state/VYNIC_CODE_MAP.md
docs/agent-state/VYNIC_DECISIONS.md
```

## VYNIC MASTER ROADMAP STATUS

This is a report against the unchanged Master Plan/backlog, not authorization to
start another milestone. Existing product implementation does not close a release
gate without its specific proof.

| Track / gate | Status | Remaining boundary |
|---|---|---|
| Initial five + MENU-03 + MENU-06 | DONE | SEC-01/02, WEB-02, MENU-02/01/03/06 completed |
| A — controlled single POS | IN_PROGRESS | MENU-09 → POS-01/03/05 → POS-02, SEC-05, OPS-01, PROD-01 |
| B — POS + Manager release | BLOCKED | Track A core gates; MGR-01/02/05/03/04/06 not closed |
| C — Menu/contact website | IMPLEMENTED_NOT_PROVEN | WEB-02 done; OPS-01/tenant release dossier; CUSTOM WEB-05/07; relevant SEC-04/06 |
| D — paid reservation/payment stabilization | NOT_STARTED | SEC-01/02 prerequisites done; WEB-01/03/04/06, SEC-03, OPS-01 and BOG sandbox remain |
| E — dependable existing Inventory subset | IN_PROGRESS | MENU-06 retirement barrier closed; broader Sale integrity, receipts/debt/payment proof, INV-02, MGR-06, INV-04 remain |
| F — full Inventory | BLOCKED | Finish E, then INV-01 subphases and UX-02; full warehouse claim unsupported |
| G — Multi-POS, 3 before 10 | BLOCKED | Single-POS integrity, then explicit EDGE-01 authority/cutover and correctness/load proof |
| Manual subscription/commercial release | IMPLEMENTED_NOT_PROVEN | Commercial lifecycle/open-session release matrix, OPS-01 and PROD-01; original WIP untouched |
| Remaining security program | NOT_STARTED | SEC-03/04/05/06 and release-specific checks; existing encryption is not full SEC-05 qualification |
| Operations/hardware qualification | IMPLEMENTED_NOT_PROVEN | Isolated PG/native proof exists; actual Windows/printer/TLS/deployment/restore dossier and OPS-02/03 remain |
| Manager/product UX stabilization | NOT_STARTED | UX-01/02, MENU-05, MGR-03/04 and INV-04 remain scoped tasks |
| Menu/money/feed/static debt | NOT_STARTED | MENU-07/08/10, TECH-01; no broad cleanup here |
| Optional integrations / automatic collection | NOT_STARTED | PROD-02 explicitly deferred |

1. **Where are we?** Seven requested milestones are DONE. Track A has completed
   MENU-03/06; MENU-09 is the next named gate, for a separate request.
2. **Inventory subset unblocked?** Its MENU-06 retirement-specific blocker is
   closed, including delayed/retry/reversal integrity. The full subset claim still
   requires broader POS Sale integrity and receipt/debt/payment reconciliation.
3. **Safe Manager work in separate worktrees?** MGR-01 has no dependency and can
   be an isolated foundation task; MGR-04 follows it. MGR-06 can be separately
   scoped against the existing immutable finance ledger, with role/date policy
   and reversal proof. MGR-02/05 and operational MGR-03 rollout wait for POS-05/
   Track A and their command-result dependencies. None is started here.
4. **Next Inventory work?** Complete the Track E broader Sale, receipt retry and
   supplier debt/payment proof package; then INV-02 is the next named Inventory
   milestone. INV-04 is independently bounded; full INV-01 waits for E.
5. **Website/payment parallelism?** Yes, isolated worktrees can take WEB-01, then
   WEB-03/04/06 and SEC-03 with shared-contract coordination. Menu/contact release
   can pursue OPS-01 and CUSTOM WEB-05/07 independently. Paid release remains
   gated by full reconciliation and real provider sandbox proof.
6. **Multi-POS blockers?** MENU-09, POS-01/03/05, supported printing/credentials/
   deployment/product gates, then EDGE-01 Venue-local authority, epochs/fencing,
   durable results, partition denial and three-terminal correctness before ten.
7. **Before controlled single-POS pilot?** Eight Track A gates remain: MENU-09,
   POS-01, POS-03, POS-05, POS-02, SEC-05, OPS-01 and PROD-01, including actual
   Windows replacement and printer/cable/paper/power qualification.

MENU-05 administration UX, money representation, conflict resolution audit, fleet
version gates, feed scaling, broader Inventory/Manager work and Edge rollout are
deferred. **STOP after MENU-06.**
