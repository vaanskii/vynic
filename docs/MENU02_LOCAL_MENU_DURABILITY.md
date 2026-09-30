# MENU-02 — local menu mutation durability

Scope: only MENU-02 from the Master Stabilization Plan. MENU-01 and all other
Menu/Edge roadmap items remain deferred. Historical audit files are unchanged.

## Current baseline

Branch: `codex/docker-deployment-foundation`. Starting HEAD:
`102b089886ac771a2d30eb94d122cd78fd388d5d`.

Completed milestones: SEC-01 `cb283d9` + proof `a403637`; SEC-02 `038ece4` +
proof `64d668f`; WEB-02 `f453ab7` + proof `102b089`. Existing WIP was captured
before implementation, including hashes of 153 tracked/untracked files.

Flutter package version `1.0.0+1`, SDK constraint `^3.9.2`, Hive dependency
`^2.2.3`; Hive database target **9**. Canonical Menu wire protocol is version
**2**, with JSON-string `menuCanonical` and `menuMutationJournal` boxes beside
the nested `MenuCategoryDB` projection in `menu`. D030 remains authoritative.

## Writer map (inspected before production changes)

| Writer | Stores | Previous journal/baseline/projection interaction | Previous crash window |
|---|---|---|---|
| POS Admin through `DatabaseService` / `MenuRepository` category add/update/delete | `menu`, global audit | Direct add/save/delete; menu event triggers unawaited capture; baseline unchanged until capture | Successful UI save before intent; sync rewrite can erase it |
| Category item add/update/delete, including variants | containing category in `menu`, global audit | Same direct category save; variants are nested, not independently stored | Same race; one edit can generate several entity intents |
| Subcategory add/update/delete and subcategory item/variant CRUD | containing category in `menu`, global audit | Same direct category save | Same race and interrupted multi-intent capture |
| Seed JSON importer | `menu` | Direct add, no canonical coordination | Concurrent bootstrap or projection replacement |
| Kitchen defaults upgrade | `menu`, settings version | In-place category save before sync starts | Startup recovery can mistake incomplete projection for a local edit |
| Stable item/node identity upgrades (Hive v7/v8; post-restore) | `menu`, schema metadata | In-place category save; no canonical boundary | Partially assigned nested identities; concurrent restore/projection |
| Canonical capture | journal, baseline | Append+flush each intent, then baseline+flush | Crash after append can mint another ID on the next diff |
| Canonical bootstrap/adoption | canonical state, baseline, `menu` | State first; rebuilding marker then clear/addAll | State durable before marker; interrupted replacement |
| Canonical push ACK/conflict/rejection and pull/resync | journal, canonical state, baseline, `menu` | Entire sync queue holds network awaits; repository writers bypass it | Stale projection erases concurrent edit; synced entry precedes canonical state |
| Projection rebuild/startup recovery | baseline/rebuilding, `menu` | Rebuild marker handles clear/addAll, but uncoordinated writers still enter | New edit can be mistaken for interrupted projection |
| Reapply | journal | Flush remove, then replacement at old sequence, then later rebase | Neither old nor replacement exists after remove→put crash |
| Use current | journal, baseline, `menu` | Remove each same-entity successor, then rewrite | Partial discard can leave a successor accidentally reapplied |
| Menu JSON import and full backup restore | `menu` plus other backup stores | Service suspends event capture, writes raw rows, then reprojects canonical+journal | Suspension does not serialize against an already-running sync; no pre-write marker |
| Developer wipe | `menu` plus other operational boxes | Direct clear; canonical state/journal retained | No projection recovery marker/coordination |
| Legacy POS-authority compatibility | `menu`; legacy Cloud snapshot | Direct local writers; no canonical journal | Must retain local-first legacy behavior |
| Owner Dashboard / Manager / website | Cloud / read-only clients | Owner writes Cloud mutations; Manager and websites read; no other local Hive menu writer found | No local mutation boundary to modify |

Repository-wide searches covered `menuBox`, category `save/delete`, all
`MenuRepository` callers and restore/wipe wrappers. Menu-screen and Manager
code read projections; open-order and historical prices are captured elsewhere.

## Original defects

The sync engine's queue serialized only engine tasks, including HTTP waits.
Repository writers saved directly and notified an asynchronous capture. A
paused pull therefore allowed a successful price edit, followed by an older
projection clear/rewrite and a capture that could no longer see the edit.
Reapply independently removed and flushed the conflicted entry before putting
its replacement.

Implementation and proof results are recorded below after validation.

## Recoverable local protocol

`MenuLocalStore` is attached to the operational menu box before Hive migrations
and default seeding in `DatabaseCore.open`. The repository, sync engine and
external import/restore/wipe paths share it. The queue covers only local Menu
work. A separate sync queue owns HTTP exchanges and never reserves the local
queue while waiting for Cloud.

Repository writers read and modify a detached `MenuDraft`, including nested
categories, subcategories, items and variants. The draft must commit before
success, menu notifications and ordinary audit calls. Identity and routing
maintenance and seed import use the same boundary. Legacy Venues retain direct
local persistence and the legacy snapshot protocol, through the local queue.
Only active, nested restore writers can share their restore scope; asynchronous
callbacks after that scope finishes must enter the normal mutation queue.

Canonical commit ordering:

1. Under the local queue, diff the desired draft against canonical state plus
   the durable unresolved journal. Allocate exact IDs and ordered sequences.
2. Put and **flush one `localCommit` record** in `menuCanonical`. It includes
   protocol version, base/next generation, canonical state, complete desired
   projection, journal puts and journal removals. This is recovery authority.
3. Persist the journal puts/removals and flush. Reapply overwrites its original
   sequence key; it never removes the old entry before writing the replacement.
4. Persist and flush canonical state, generation and local protocol version.
5. Materialize the projection. Before clear/addAll, persist the existing
   `rebuilding` marker. Flush the menu, then write baseline and clear that marker.
6. Delete and flush `localCommit` only after all effects are durable. Return
   repository success. No Cloud call belongs to any of these steps.

The commit record is a write-ahead transaction descriptor, not a second Menu
business authority. Restart replays it idempotently before interpreting the
projection as operator input. Partial journal/state/projection writes are
therefore recognized as unfinished work. Recovery reuses the descriptor's IDs;
it never invents replacement IDs. A commit cannot overwrite an unfinished
record. Unrecognized protocol versions fail explicitly.

Projection generation is checked under the queue. A staged projection with an
older generation is refused. Sync never commits a projection captured before a
network await: it reacquires the local queue, loads current canonical state and
current entries, merges the response, and builds a new generation. ACK handling
rebases later edits, including those created while the ACK was pending. A
response cannot resurrect an entry removed/replaced during its network wait.

Compatibility capture is retained for old-format installs and existing raw
write fixtures. It compares against canonical state **plus already-durable
entries**, rather than an outdated baseline, preventing another ID for an intent
whose journal write completed before baseline. All discovered production local
menu writers now use the shared boundary; capture is not the race fix.

## Journal lifecycle and conflict resolution

No new journal status enum is needed. Intent first exists in the flushed commit
record, then as `pending`; transient delivery failure becomes `failedRetryable`.
Cloud outcomes produce `synced`, `conflict` or `rejected`. Conflict and rejected
patches remain part of the local unresolved projection until explicit resolution.
The accepted canonical state, terminal journal status and successor revision
rebases share one recovery descriptor, removing the old ACK/state gap.

Reapply records its new ID and revision, replacement at the same sequence, and
all later same-entity rebases together. An interruption can leave the old row,
the replacement row, or a partially rebased journal; the flushed descriptor
replays the complete intended replacement, with the same new ID.

Use current records deletion of the target and every same-entity successor in
one descriptor before deleting any row. Recovery finishes that exact discard
and projects the current canonical value, so a surviving successor cannot be
mistaken for a new local edit or accidentally reapplied. Full actor/reason/
immutable resolution-event audit remains **MENU-08**, not part of this task.

Cleanup still retains the latest 50 synced entries and never deletes unresolved
entries. The descriptor exists only while a commit is unfinished, and no extra
in-flight state or permanent duplicate catalog is introduced. Pending/conflict/
rejected entries necessarily grow while unresolved; bounded feed/history scaling
remains MENU-10.

## Local schema, migration and rollback

Global Hive schema target remains **9**, menu adapters/type IDs 5–8 are unchanged,
and existing journal JSON fields/status names/wire version **2** are unchanged.
The additive local storage protocol is **v1** (`localProtocolVersion`), adding
`generation` and `localCommit` beside the existing state/baseline/rebuilding keys.

Migration is lazy on opening an existing-format canonical store: replay any old
rebuilding marker; preserve the original journal rows and IDs; capture genuine
uncaptured edits against canonical plus journal; establish the v1 baseline and
version through the same descriptor. The checked-in original-format fixture
`test/fixtures/menu02_legacy_journal.json` opens with a stale baseline and retains
its ID, pending state, patch and revision without duplication.

At a completed boundary, old readers can still parse the unchanged state,
baseline and journal. A rollback must first finish recovery with the new binary
and verify `localCommit`/`rebuilding` are absent; old binaries do not understand
an unfinished v1 descriptor. Preserve all three boxes, do not downgrade by
clearing them, and do not claim that reverting the implementation preserves the
new durability guarantee. A future local protocol version is rejected rather
than treated as empty state. Fleet/client rollout gates remain MENU-09.

## Pre-fix reproduction and fault proof

Before production changes, two new deterministic Flutter tests failed against
starting HEAD `102b089` using real Hive files in temporary directories:

- Pull captures a Cloud response and stops at a completer. Admin repository
  price save to **12 succeeds**. Release the response and queued capture: actual
  local price becomes **10**, with no recovered intent. The invariant assertion
  fails (`Expected 12; Actual 10.0`).
- After a real revision conflict, fault the replacement journal put. The old
  implementation had already deleted/flushed the old intent. Reopen Hive and
  rebuild: unresolved entries are **empty** (`Expected length 1; Actual []`).

The fixed tests assert the intended invariant and pass. Their production code
was not changed to make pre-fix injection possible: the test delegates interrupt
real Hive operations, and transport completers determine the interleaving.

| Point | Proof and expected recovered result |
|---|---|
| A — before local persistence | Fault before commit-record put; repository returns false, old view remains, no acknowledged intent |
| B — save/journal gap | Detached drafts remove this acknowledged gap; faults at descriptor put/flush and journal put cannot report success; durable descriptor recovers pending intent |
| C — journal/baseline/state interruption | Fault after journal put/flush, before/after canonical state, after generation/version, at baseline; two reopen/rebuilds preserve one exact ID |
| D — second edit during Cloud wait | Pull and mutation ACK barriers; local success occurs before release; latest patch survives and later revision rebases |
| E — projection interruption | Before/after clear/addAll/flush/baseline/marker cleanup, plus actual process SIGKILL after clear; restart reconstructs canonical plus intent |
| F — Cloud commit, lost ACK | Restart retains original mutation ID; retry adds no fake-Cloud side effect and becomes synced; exact original server response is MENU-03 |
| G — conflict then restart | Fault before canonical state write after conflict journal write; descriptor reconstructs visible conflict/current revision and local patch |
| H — interrupted reapply | Fault before replacement, after replacement and before successor rebase; never neither; recovery uses the recorded replacement ID |
| I — interrupted use current | Kill-equivalent fault after first deletion of a multi-entry discard; replay removes all intended entries; no accidental capture/reapply |
| J — rapid same-entity edits | 12 simultaneous submissions serialize in order; 12 unique IDs survive restart, rebase, and converge without conflicts |
| K — independent entities | Both edits commit and converge with their own revisions; no catalog-wide conflict |

Additional checks cover every Admin CRUD node kind, interrupted bootstrap,
external restore with nested identity migration, delayed callbacks after restore,
stale generations, unknown protocol versions, old-format migration, and journal
cleanup. A final regression check caught and fixed a nested **legacy restore**
deadlock introduced while tightening queue scope lifetime; no timeout was relaxed.

## Native Flutter/Hive kill and restart

`tool/prove_menu02_restart.py` starts the real Flutter test runner twice, with
only its own `/private/tmp/vynic_menu02_process_*` files and synthetic menu data.
The native writer pauses a Cloud pull, acknowledges local price **12**, then
resumes a pull that changes another item to **24**. A real Hive delegate signals
after projection clear and flush, while both the descriptor and journal are
already durable. The orchestrator verifies process ancestry and sends SIGKILL
to that exact Flutter tester process. No box close/shutdown handler runs.

A second native process confirms that Hive actually reopened with an empty menu
and an unfinished descriptor, then recovers **offline**. It verifies prices
**12 / 24**, **one pending entry with the exact original mutation ID**, zero
recaptured duplicates, and cleared commit/rebuilding markers. Writer failure is
expected after SIGKILL; reader test success is required. The orchestrator removes
only the temporary directory it created. All actual HTTP is disabled in this
harness; Cloud responses are deterministic synthetic protocol responses.

Reproduce with an isolated writable SDK:

```sh
python3 tool/prove_menu02_restart.py \
  --flutter /path/to/isolated/flutter/bin/flutter \
  --output /private/tmp/MENU02_process_proof.json
```

The executed environment is macOS arm64, Flutter **3.44.1**, Dart **3.12.1**,
Hive **2.2.3**, with a writable copy of the installed SDK. This is actual native
process-restart proof and real Hive fault testing; it does not claim physical
Windows hardware or power-loss/filesystem-corruption qualification.

## Unchanged product boundaries and deferred work

No backend, Prisma, generated contracts/models, authentication, tenant authority,
website presentation, open orders or historical OrderLine/Sale prices changed.
Per-entity conflicts, Cloud authority, stable identities, mutation retry IDs and
legacy POS-authority compatibility remain. Owner Dashboard is still a Cloud
writer; Manager/website still have no local Hive writer. SEC-01 / SEC-02 / WEB-02
commits and their proof files remain present and untouched; no PostgreSQL suite
was unnecessarily rerun for this Flutter/local-only change.

MENU-01 backup completeness/machine replacement, MENU-03 exact original server
retry outcome, MENU-05 disabled-item UI, MENU-06 retirement/recipes, MENU-07
money, MENU-08 resolution audit, MENU-09 rollout gates and MENU-10 feed/history
scaling remain deferred. MENU-04 is the COM-01 alias. EDGE-01 operational
multi-POS authority is unchanged. Backup exports still lack the canonical and
journal recovery package; serializing restore in this task does not implement
MENU-01. No normal local-prod/customer database or active POS storage was used.

## Final validation and performance

Status: **MENU-02 DONE**. The final implementation passed **96 tests** (no
failures/skips): 41 durability/fault tests, 15 existing canonical Menu tests,
24 menu identity tests, 3 order/menu-line identity tests, 9 existing backup
regressions and 4 conflict-banner widget tests. The canonical suite includes
bootstrap/adoption, pull/catch-up, offline local editing/reconnect, conflicts,
tombstones/deletion, exact-ID retry, parent-first create, disabled-item behavior,
3/10 independent device stores, and captured open/historical prices.

Targeted Dart analysis reports **No issues found**. `git diff --check` passes.
Final native process proof passes with real SIGKILL and a different reader PID.
The detailed machine-readable results, exact mutation ID, expected writer exit,
reader success, runtime versions, source/log hashes and commands are in
`docs/proofs/MENU02_2026-09-30.json`.

Measured in that final Flutter run on macOS arm64, with **500 items** and **20
offline edits**: local edit p50 **21.129 ms**, p95 **25.825 ms**, maximum
**26.944 ms**; complete physical projection recovery/rebuild **20.142 ms**.
Menu network attempts during these edits: **0**. Twenty pending entries remain
recoverable. Cleanup separately verifies 50 accepted diagnostic entries plus
all unresolved entries. These are a bounded synthetic local measurement, not a
fleet/10k-history capacity claim.

Changed implementation/test files (all under `apps/operations/`):

- `lib/core/database/database_core.dart`
- `lib/core/database/repositories/menu_repository.dart`
- `lib/core/database/repositories/backup_repository.dart`
- `lib/core/services/menu/menu_local_store.dart`
- `lib/core/services/menu/menu_mutation_journal.dart`
- `lib/core/services/menu/pos_menu_sync.dart`
- `lib/core/services/menu/pos_menu_sync_service.dart`
- `test/unit/menu02_durability_test.dart`
- `test/live/menu02_process_restart_test.dart`
- `test/fixtures/menu02_legacy_journal.json`
- `tool/prove_menu02_restart.py`

Documentation: this report, `docs/proofs/MENU02_2026-09-30.json`, and narrow
current-fact/entry-point updates to `docs/agent-state/VYNIC_PROJECT_STATE.md`
and `VYNIC_CODE_MAP.md`. The historical audit is unchanged. All **151 unrelated
WIP files** retain their starting bytes; the other two WIP files are those shared
docs, whose existing changes are preserved and excluded from the focused commits.

Focused implementation commit: `a6da94a`.
The separate documentation/proof commit contains this report and only MENU-02
hunks in the shared docs. No push. **STOP after MENU-02; MENU-01 was not started.**
