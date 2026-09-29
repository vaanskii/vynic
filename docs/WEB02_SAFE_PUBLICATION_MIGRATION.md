# WEB-02 — Safe publication migration (unpublished draft protection)

**Status: DONE.** Closed 2026-09-30 Asia/Tbilisi (2026-09-29 UTC).
Database migration is not publication consent. The unsafe historical behaviour
was reproduced on real PostgreSQL/Nest HTTP. The current chain now keeps
published authority and private drafts on every not-yet-upgraded database.
Already-upgraded data is reported and decided explicitly, never guessed.
SEC-01 and SEC-02 remain DONE. MENU-02 and later items were not started.

## Baseline and scope

- Branch `codex/docker-deployment-foundation`; starting HEAD
  `64d668fe20f43dd822e5ae31dbdef78cad5bcfa9` (SEC-02 docs).
- SEC-01: `cb283d9` (fix) / `a403637` (proof). SEC-02: `038ece4` / `64d668f`.
- Migration tip before WEB-02: `20261011120000_canonical_menu_sync` (60
  migrations). After: `20261012120000_web02_restore_public_info_authority` (62).
- WEB-02 implementation/tests: `f453ab75728088a7b497880457e8a441d6a97b91`.
- Initial worktree: 30 modified tracked files, two owner untracked files and
  the untracked audit directory, plus stash `reorg-wip-holdout`. All of it is
  user-owned and was preserved byte-for-byte (tracked WIP diff SHA-256
  `7e8e687d…450c`, untracked content manifest `6d7dd439…ef91`, before and after).
  No reset, stash, rebase, history rewrite or push.
- Audit sources: `docs/audits/2026-09-29-f7bb982/` (MASTER_BACKLOG,
  IMPLEMENTATION_ROADMAP §3, WEB_COMMERCIAL_SECURITY, SECURITY_AND_RELIABILITY,
  SYSTEM_AND_ARCHITECTURE, EVIDENCE_AND_MATRICES, Master Plan Milestone 3).
  The historical audit was not edited.

## The historical migration

`20261010120000_shared_website_foundation/migration.sql` (SHA-256
`88e74063…8c50`, unchanged):

| | Before (≤ `20261009120000`) | After |
| --- | --- | --- |
| Private draft | `VenueWebsiteConfig.draft` (`revision`) | page fields only |
| Approved public | `VenueWebsiteConfig.published` (`publishedRevision`, `status`, `publishedAt`) | page fields only |
| Moved fields | hours, `contactEmail`, `mapUrl`, `socials`, `gallery` inside both documents | `VenuePublicProfile` (live, Venue-owned) |
| Public readers | SAAS bootstrap served `published` only; CUSTOM had no source for these fields | SAAS bootstrap projects the live row into `content`; `/api/website/venue` (CUSTOM and SAAS) returns it as `info` |

Algorithm: for each `VenueWebsiteConfig`, `src = COALESCE(draft, published)`
over the whole document; if it is a JSON object, insert
`COALESCE(src->'workingHours','[]')`, `NULLIF(src->>'contactEmail','')`,
`NULLIF(src->>'mapUrl','')`, `COALESCE(src->'socials','[]')`,
`COALESCE(src->'gallery','[]')`. Then delete those five keys from **both**
`draft` and `published`.

Consequences:

- A saved draft always wins, even when a different version was published.
- A never-published draft is copied into live storage. A CUSTOM Venue is
  "launched" by mode alone, so it becomes public immediately with no publish
  action; a SAAS Venue exposes it at its next publish.
- A legacy draft missing a key erases the published value (`[]`).
- A non-object, non-null draft (e.g. JSON `null`) produces no row and still
  deletes the published values (code analysis; not a reachable app state).
- After it runs, the published values of the moved fields exist nowhere in
  the database.

Provenance that remains after it: `revision`, `publishedRevision`, `status`,
`publishedAt`, `published IS NULL`, the settings row's `updatedAt`, audit
events (`website.draft_saved` / `website.published` carry revision numbers
only; `website.public_info_saved` lists changed fields), and the ledger's
`finished_at`. Lost: every published value of the moved fields and whether the
draft's values differed from them.

## Reproduction (original chain)

Ten synthetic Venues in separate Organizations, built on the real
pre-foundation schema (58 repository migrations) from
`apps/backend/test/web02-public-info.fixture.ts`. Each value names its Venue
and whether it is published (A) or draft (B).

| Fixture | Class | Pre-upgrade | Original chain live result |
| --- | --- | --- | --- |
| `pubonly` | A published only | published A, no draft | A — safe |
| `synced` | A published, draft identical | A / A | A — safe |
| `draftonly` | B draft only (SAAS) | draft B | **B copied live** |
| `customdraft` | B draft only (CUSTOM) | draft B | **B public at once** |
| `divergent` | C published A, draft B | A / B | **B public, A deleted** |
| `customdiv` | C (CUSTOM) | A / B | **B public, A deleted** |
| `disabled` | C, Website entitlement withheld | A / B | **B stored live, A deleted** |
| `partial` | C, legacy draft without socials/gallery | A / partial | **published socials/gallery deleted** |
| `empty` | D both empty | ∅ / ∅ | empty — safe |
| `blank` | D no documents | — | no row — safe |

The reproduction suite passes 6/6 on the original 60-migration chain: SAAS
visitors of `divergent` receive `b-divergent@web02.test` and never the
published address, the CUSTOM `customdraft` site serves its never-published
draft, `partial` serves empty socials/gallery, and no moved key remains in any
document. Unsafe fixtures: `customdiv`, `customdraft`, `disabled`, `divergent`,
`draftonly`, `partial`.

## Repair design

Classes: **A** provably published, **B** provably unpublished draft,
**C** ambiguous / provenance lost.

**Not-yet-upgraded databases (automatic, provable).** The historical file
cannot change and Prisma would still run it, so evidence is captured before it:

- `20261010110000_web02_capture_public_info_evidence` (ordered just before the
  foundation) creates `VenuePublicInfoReview` and, only when
  `VenuePublicProfile` does not exist yet, records per Venue: the normalized
  draft (`draftInfo`), the published values (`publishedInfo`), exactly what the
  foundation will write (`migratedInfo`), both revisions and the provenance
  class (EMPTY / PUBLISHED / DRAFT_ONLY / DIVERGENT). On a database where the
  foundation already ran, Prisma applies this migration late (verified: after
  `20261011…`); it then only creates the table and records nothing.
- `20261012120000_web02_restore_public_info_authority` (after the tip), per
  evidence row, compare-and-set: while the live row is still exactly what the
  foundation wrote (same values, revision 0) it becomes the published values;
  a row created from a never-published draft is deleted (no public
  information); a published version with no row gets one. The review becomes
  `NOT_REQUIRED` when live equals the approved values and no differing draft
  exists, otherwise `PENDING`. Anything edited since stays untouched and
  `PENDING`.

`VenuePublicInfoReview` is private: no public or owner route reads it. A
differing draft becomes live only through an explicit decision.

**Already-upgraded databases (report + explicit decisions).** Without evidence
the published values cannot be recovered from the database, so nothing is
changed automatically. `publicInfoReviewReport` (`scripts/web02-public-info.ts
report`, inside a READ ONLY transaction) classifies each Venue from remaining
provenance:

- a non-empty live field not listed in any audited owner save can only come
  from the migration (owner saves always audit changed fields);
- `published IS NULL` proves the values came from a never-published draft →
  **DRAFT_ONLY (B)**, action `WITHHOLD_RECOMMENDED`;
- draft/published at the same revision and the settings row unwritten since
  the migration finished → **PUBLISHED (A)**, no action;
- anything else → **AMBIGUOUS (C)**, action `CONFIRM_OR_WITHHOLD`, with the
  reasons (unpublished changes existed, settings changed afterwards, migration
  time unknown).

Safe policy for C: keep serving the current value until a decision. Reason:
the values are restaurant business information, not personal data; they have
been public since that upgrade, so hiding them now retracts nothing, while
blanking hours/contacts could remove approved information from a live site.
No automatic restoration is claimed.

Decisions (`decide <venueId> <action> --actor <active platform user> --note`),
one transaction under the Venue row lock owner saves use, audited as
`website.public_info_<action>` with fields and revisions:

- `apply-draft` — publish the private draft (or withheld values) through the
  current field parsers and media ownership checks; refused if a field it
  changes was edited live since the review was recorded.
- `dismiss` — discard the private draft; live values stay.
- `confirm-live` — (C/B without evidence) record the owner's confirmation.
- `withhold` — (C/B without evidence) move only the migrated fields into a
  private `PENDING` review and clear them live; audited owner edits stay.

With a pre-migration backup, restore it into a disposable database and run the
current chain: its evidence (`report --values`) proves A and B per Venue. The
owner then re-enters approved values through the live editor; there is no
cross-database write tool.

## Live shared information policy

Unchanged (D028): owners edit `VenuePublicProfile` live from either Dashboard,
SAAS and CUSTOM read the same row, the SAAS page keeps its own draft/publish.
WEB-02 governs only the historical move of drafts into live storage. Current
live edits are explicit owner actions and are never treated as migration
artifacts. Any draft/publish flow for shared information is an owner/product
decision (below), not part of this fix.

## Media / gallery

Venue ownership is unchanged. `referencedMedia` also counts `draftInfo` and
`publishedInfo` of `PENDING` reviews, so private draft images are neither
collected nor exposed; after `dismiss` they return to the ordinary 24-hour
unused retention (proved through `WebsiteLogoService.cleanup`). Restored
published galleries are referenced again in the same deploy, before any
cleanup can run. On databases upgraded earlier, files referenced only by lost
published values may already be collected; nothing is deleted or duplicated by
WEB-02. The local deletion matrix classifies the new Venue-owned model.
SEC-04 public-media policy is untouched.

## Changes

- Migrations (new, additive): `20261010110000_web02_capture_public_info_evidence`
  (SHA-256 `08e3b087…90e8`), `20261012120000_web02_restore_public_info_authority`
  (`62035f02…03ac8`). Schema: `VenuePublicInfoReview` + three enums, Venue relation.
- `apps/backend/src/website/core/public-info-review.ts` (+ unit spec);
  `website-media.ts` (pending review media); `local-tools/deletion-matrix.ts`;
  `website-media-test-fixture.ts` (mock delegate).
- `apps/backend/scripts/web02-public-info.ts` (operator CLI);
  `apps/backend/scripts/prove-web02-upgrade.py` (proof runner).
- Tests: `public-info-upgrade.integration.spec.ts`,
  `public-info-upgrade.reproduction.integration.spec.ts`,
  `public-info-already-migrated.integration.spec.ts`; fixtures/harness
  `apps/backend/test/web02-public-info.{fixture,harness}.ts`.
- No frontend, dependency, contract or historical-migration change.

## Executed proof

Private native PostgreSQL **17.10** on `127.0.0.1:64611`, initialized in the
session scratchpad, TCP only. Every database name was checked absent before
creation; only verification-owned `disposable_web02_8487f20d_*`,
`disposable_sec01_web02_8487f20d_sec01` and `disposable_sec02_web02_8487f20d_sec02`
databases were created. `prove-web02-upgrade.py --tag 8487f20d` (final run
2026-09-29T20:50:54Z, **PASS**) builds the fixtures, takes a `pg_dump -Fc`
pre-upgrade backup and runs:

| Path | Result |
| --- | --- |
| Migration chains | 62 total, original 60, pre-foundation 58; **0 historical migrations edited** (byte-compared with HEAD) |
| Original chain (restore → 60) | checksums 60/60; reproduction **6/6** |
| Already migrated (restore → 60 → 62) | capture applied late, 0 evidence rows, live values unchanged; CLI report read-only, 6 Venues need a decision; suite **6/6**; CLI `decide` confirm-live audited, unknown actor refused |
| Pre-upgrade restore → current chain | checksums 62/62, schema diff empty; suite **11/11** |
| Fixture database upgraded in place | checksums 62/62, schema diff empty; suite **11/11**; database and public snapshots **identical** to the restore path |
| Fresh install | 62/62, `migrate status` up to date, migration history ≡ schema (shadow diff empty), 0 review/profile rows |

Upgrade results (Nest HTTP, production host resolution):

- **J. Published only** (`pubonly`, `synced`): SAAS and `/api/website/venue`
  serve A; evidence `PUBLISHED`, `NOT_REQUIRED`.
- **K. Draft only** (`draftonly`, `customdraft`): live row removed; SAAS stays
  404 (unpublished); the CUSTOM site serves empty info; B private, `PENDING`.
- **L. Divergent** (`divergent`, `customdiv`, `disabled`, `partial`): A served
  (`disabled` fails closed 404/403); B private, `PENDING`; `partial` regains its
  published socials/gallery.
- **M. Empty** (`empty`, `blank`): empty defaults / no row; nothing pending.
- No response for any host contains any private draft value (≥ 20 markers) or
  another Venue's markers; unknown and DISABLED hosts fail closed; forged
  `?venueId=` / `X-Venue-Id` are ignored (Host → VenueDomain → Venue).
- Owners see the approved values with revision 0; a live owner edit then
  succeeds, and an older draft can no longer overwrite it (`apply-draft` 409).
- `apply-draft` makes B public only by an audited decision; on an unpublished
  SAAS Venue it stays private until the site is published.

Regressions on fresh owned databases (current chain), 0 failed, 0 skipped:
W3 website 13, website core 10, public tenant isolation 20, provisioning 14,
CUSTOM 15, W1 payment integrations 8, entitlements 12, **SEC-01** 83 unit +
45 PostgreSQL/HTTP, **SEC-02** 14 unit + 25 PostgreSQL/HTTP. Full backend Jest:
66 suites / 645 tests pass (43 database-gated suites skip without a database).
Backend production compile (`tsconfig.build.json`) passes. SaaS
`restaurant-web` 19 tests + build, standalone Vankisi CUSTOM build, and
`packages/website-client` 6 tests + typecheck pass (built in scratch copies;
Vankisi was not moved onto the shared client). New and changed TypeScript is
lint-clean; `website-media-test-fixture.ts` keeps its unchanged baseline
diagnostics. Three pre-existing type errors in untouched specs remain.
`git diff --check` passes.

## Cleanup

All 19 distinct owned database names (25 creations, including the final
runner re-creating six absence-checked names) were dropped and verified
absent; the cluster was stopped, its port verified closed and its data
directory removed. No connection to `vankisi_database`, the normal local
databases, port 5432 or Docker was made. Frontend build copies and compiled
outputs were removed; the copies linked the existing `node_modules`, so only
ignored caches there (`.tmp/*.tsbuildinfo`, vitest results) were refreshed from
identical sources, and no `dist/` was overwritten. Compact evidence:
[WEB02_2026-09-30.json](proofs/WEB02_2026-09-30.json).

## Operator runbook

```bash
DATABASE_URL=… npx ts-node -T scripts/web02-public-info.ts report [--values] [<venueId>]
DATABASE_URL=… npx ts-node -T scripts/web02-public-info.ts decide <venueId> \
  <apply-draft|dismiss|confirm-live|withhold> --actor <platform-admin-email> --note "<owner request>"
```

Run `report` after upgrading any existing database. Decide every entry whose
`action` is not `NONE` with the owner; `WITHHOLD_RECOMMENDED` entries that are
`launched` are currently public.

## Owner decisions still needed

- Whether owners should see and decide pending private drafts in the
  Dashboard (today: operator CLI on owner request).
- Whether shared public information should gain its own draft/publish flow
  or stay live (D028).
- How to inform owners of already-upgraded Venues flagged `DRAFT_ONLY` /
  `AMBIGUOUS`, and whether to recover from a pre-migration backup where one
  exists.
