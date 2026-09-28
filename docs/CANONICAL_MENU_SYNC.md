# Canonical Cloud Menu, local-first POS projection, multi-device sync

Decision D030. Scope: stable Menu configuration only (categories,
subcategories, items, variants/sizes, prices, enabled, kitchen routing).
Open Orders, table occupancy, payments, Close Day, printing, recovery journals
and Edge Orders/Tables authority are untouched and remain POS/Edge-owned.

```text
Dashboard ─┐                       ┌─> SAAS website (reader)
Manager*  ─┼─ mutations ─> Cloud ──┼─> CUSTOM website (reader)
POS A..J  ─┘   (revisioned,        ├─> Manager (reader)
  ↑  local-first  idempotent)      └─> POS A..J catch-up (changes since N)
  └─ commit locally FIRST; the network is asynchronous and never gates operation
```
\* The backend accepts a `STAFF` actor; no Manager editing UI exists yet.

## Writer / reader audit (before this milestone)

| Surface | Before | Now |
|---|---|---|
| POS Admin Menu (`admin_menu_section.dart` → `MenuRepository`) | Sole writer for POS-authority Venues; legacy full snapshot mirrored to Cloud with "missing = delete" reconciliation | Legacy Venues unchanged. Canonical Venues: same local write, then journaled entity mutations |
| Legacy full snapshot (`menu-sync.service.ts`) | Mirror for POS authority; threw for CLOUD, failing the whole snapshot | Legacy mirror only; for CLOUD it ignores the menu and lets Orders/Sales/audit continue |
| Owner Dashboard (`CatalogEditor.tsx`) | `PUT catalog/:kind`, ONE Venue-wide revision (any edit conflicted with any other) | `POST catalog/mutations` with per-node revisions and conflict UX |
| Manager | Read-only `GET /mobile/menu` (Cloud rows); counted menus are packages | Unchanged; reads canonical rows |
| Website presentation (`MenuItemWebsitePresentation`) | Separate display layer | Unchanged; never writes operational fields |
| SAAS `/api/website/menu`, CUSTOM `/api/menu` | Read Cloud rows by Host → VenueDomain | Unchanged; same canonical rows, WebsiteMode has no authority meaning |
| Bootstrap v1 (`/edge/restaurant-foundation/bootstrap`) | Frozen staging snapshot, never activated | Kept for compatibility; superseded for the Menu by `/edge/menu/catalog` |
| Seeds/imports (`scripts/seed-*.ts`, `initializeMenuFromJson`) | Direct rows / unused JSON seed | Unchanged (local fixtures); rows start at revision 1 |
| Platform | Admission toggle `menuAuthority=CLOUD` + editing | Unchanged; new Venues are created CLOUD |
| Edge | No Menu role | None (future LAN coordination only) |

Identity: POS nodes already had stable UUIDs (Hive v8) and Cloud stored them
as `posMenu*Id`. The protocol identity is that UUID; Cloud row keys, website
presentation, recipes and the public `MenuItem.id` are unchanged.

## Authority model

`Venue.menuAuthority` is now transitional/compatibility-only:
- `CLOUD` — the canonical converged catalog with this protocol. New Venues
  are created CLOUD (Platform directory, customer onboarding, invitations).
  POS presence never makes the Dashboard read-only; only the commercial
  `cloudMenuEditingEnabled` permission gates the owner. Devices are not gated
  by it. WEBSITE is not required for the catalog to exist (POS-only Venues use
  it through Devices); owner Dashboard catalog access still requires WEBSITE.
- `POS` — legacy compatibility for established POS Venues (Vankisi). Nothing
  converts a Venue implicitly. Retirement: every established Venue passes the
  explicit cutover below, then the enum and the legacy menu mirror are removed.

Primary-POS containment remains for operational domains only. Any ACTIVE
Device of the Venue may submit Menu mutations.

## Schema (migration `20261011120000_canonical_menu_sync`, additive)

- `revision` (default 1) and `changeSeq` (default 0) on MenuCategory,
  MenuSubcategory, MenuItem, MenuItemVariant.
- `Venue.catalogRevision` is the Venue change sequence (catch-up cursor).
- `MenuCatalogTombstone(venueId, entityId)`: kind, seq, revision, mutationId.
- `MenuCatalogMutation(venueId, mutationId)`: kind, operation, expected and
  result revision, seq, actor type/id, source, request hash, field-level
  changes, resolution. Both cascade with the Venue; the local deletion matrix
  classifies them.
Existing rows keep their UUIDs and presentation; they appear in snapshots,
and catch-up reports only protocol changes. Money follows the existing Menu
convention (GEL major units, `Float`/`double`), refused beyond two decimals.

## Protocol

Mutation: `{mutationId, entityType, operation: UPSERT|DELETE, entityId,
expectedRevision (0 = create), patch, resolution?}`. The patch names only the
fields it changes (a POS never sends `enabled`).

Under the Venue row lock, per mutation:
1. Refuse legacy Venues (`LEGACY_POS_MENU`) and, for owners, disabled editing.
2. Same (Venue, mutationId) seen before: same content → replay the stored
   result (`duplicate: true`, no write, no audit); other content →
   `MUTATION_ID_REUSED`.
3. Revision mismatch → 409 `REVISION_CONFLICT` with the current node and
   revision, pending patch, deleted flag; nothing is written. Conflicts are
   not stored, so a stale retry re-evaluates.
4. Accept: node revision+1, Venue sequence+1, `changeSeq` = sequence, one
   ledger row (and a CustomerAuditEvent for owners). No-op patches are
   accepted without a new revision.
5. DELETE: tombstone (an item's variants too); non-empty parents are refused
   (`NOT_EMPTY`); a repeated delete is an idempotent success; an UPSERT of a
   tombstoned node conflicts with `deleted: true` (never a resurrection).

Endpoints: owner `GET|POST /customer/venues/:id/catalog[/mutations]`
(CustomerAccount → OWNER membership → Venue); Device `GET /edge/menu/catalog`
(version 2 flat snapshot: ids, revisions, sequence), `GET /edge/menu/changes?since=N`
(nodes with `changeSeq > N`, tombstones with `seq > N`; `RESYNC_REQUIRED` when N
is ahead), `POST /edge/menu/mutations` (Device → Venue). No endpoint accepts a
tenant id. A foreign node id is simply absent for the caller; creating with an
id used elsewhere returns a generic `ID_UNAVAILABLE`.

## POS: local-first projection and durable journal

`lib/core/services/menu/`: `canonical_menu.dart` (pure state, projection,
diff), `menu_mutation_journal.dart` (Hive `menuMutationJournal`),
`pos_menu_sync.dart` (engine + HTTP transport),
`pos_menu_sync_service.dart` (scheduler/UI status).

- The operational Hive `menu` box is a projection of canonical state
  (`menuCanonical` box) ⊕ unresolved journal entries. Disabled products stay
  canonical but are not sellable.
- An Admin edit commits to the operational menu first (instant, offline). It
  is captured by diffing against the projection LAST WRITTEN (the baseline),
  never against newer Cloud state, and journaled as `PENDING` before any
  network use. Crash between write and capture is recovered at the next
  capture; an interrupted projection write carries a marker and is never
  journaled as deletes. Backup restore re-projects instead of journaling.
- Sync (every 20 s, 1 s after an edit, on start): push sendable entries in
  order (offline/5xx/auth → `FAILED_RETRYABLE`, stop to keep order; lost
  replies retried with the same id; later edits of the same node rebased on
  the accepted revision), then catch up by sequence, then re-project.
  WebSocket delivery is not required.
- Statuses: `PENDING`, `SYNCED` (compacted), `CONFLICT`, `REJECTED`,
  `FAILED_RETRYABLE`. Conflicts/rejections stay applied locally and durable
  until the operator chooses **Use current** (discard my change(s) to that
  node) or **Re-apply my change** (new mutation on the current revision,
  `resolution: REAPPLY`). Later edits of that node wait behind it; other nodes
  keep syncing.
- Admin Menu shows only decisions (conflicts, rejections, a different local
  menu); routine pending/offline state stays silent as elsewhere in POS.
- Canonical POS full snapshots omit the menu.

One POS: no locks beyond the in-process serial queue; an edit is a local write
plus one journal row; reconnect replays in order; nothing is re-entered.

## Website-only → POS adoption

Owner authors the Menu in the Dashboard; the operator adds POS to the SAME
Venue; each enrolled terminal fetches `/edge/menu/catalog` into durable local
state (ids + revisions + sequence) and projects it. An empty local menu is
projected directly, an identical one adopted, a different one left untouched
(`adoptionBlocked`) until an operator explicitly chooses **Cloud მენიუს
გამოყენება**. Fresh second/third terminals create no rows.

## Multiple POS offline (honest boundary)

Ten terminals offline from Cloud each keep operating on their own projection.
Independent edits to the same node cannot be reconciled while they cannot
communicate: they diverge locally. On reconnect the first accepted wins and
every other terminal gets an explicit, durable conflict; nothing pending is
silently lost. Edits to different nodes never conflict. A future Go Edge may
coordinate terminals over LAN to reduce such conflicts, but Cloud remains the
canonical converged catalog; Edge must not become a second Menu authority.

## Historical safety

Order/Package/Sale lines freeze name, price, quantity and the nullable
`menuItemId`/`variantId`; Cloud SaleLine has no FK to Menu. Re-projection
rewrites only the menu box: open lines keep their captured price, new lines
use the new price, and deleting a product never rewrites history. Deleting a
node cascades its website presentation and consumption recipe (as the legacy
mirror always did); close-time consumption snapshots are already frozen.

## Existing POS Venues (compatibility and cutover)

Established POS Venues stay `POS`. `scripts/menu-cutover-audit.ts <venueId>`
(READ ONLY transaction) reports blockers: no active/recent primary POS, no
completed snapshot, mirrored nodes without POS identity; and warnings:
several Devices, empty catalog. Planned explicit cutover (not implemented):
1. Audit READY; announce a short Menu-edit freeze on all terminals.
2. Primary POS completes a fresh full snapshot; verify its menu hash equals
   the Cloud mirror.
3. One audited Platform action under the Venue lock: set every node's
   `changeSeq` to a new sequence (baseline) and flip `menuAuthority` to CLOUD.
4. Upgrade terminals to a canonical-capable build; each bootstraps. Identical
   local menus adopt automatically; any differing terminal is blocked for
   explicit operator adoption.
5. Legacy snapshots now ignore the menu. Rollback before step 4 = flip back.

## Validation

- Backend `src/menu-catalog/menu-catalog.integration.spec.ts` (14 tests, real
  HTTP/PostgreSQL, `CANONICAL_MENU_TEST_DATABASE_URL=…/disposable_*`).
- POS `test/unit/canonical_menu_sync_test.dart` (15, separate Hive dirs per
  terminal), `test/widget/menu_sync_banner_test.dart` (4).
- Dashboard `src/test/catalog-editor.test.tsx` (5).
- Live: `scripts/serve-canonical-menu-local.ts --confirm-local` +
  `test/live/canonical_menu_live_test.dart` with
  `CANONICAL_MENU_LIVE_PHASE=online|outage|reconnect`, stopping the backend
  process between phases.

## Windows manual proof (not performed from this environment)

1. Build/publish a POS from this commit (`apps/edge/tool/publish-local-pos.sh`),
   deploy the backend with the migration, create a new Website-only Venue,
   author a Menu in the Dashboard, enable POS, enroll the Windows POS.
2. Admin → Menu shows the Dashboard Menu; take an Order from it.
3. Stop the backend. Restart the POS: log in (offline rules), open a table,
   add items, close with cash, edit a price in Admin → Menu, add an item.
4. Restart Windows while the backend is stopped; confirm the edits remain.
5. Start the backend; within ~20 s the Dashboard and public site show the
   edits. With a second terminal, edit the same item offline on both and
   reconnect: one shows the conflict card; resolve it both ways.
