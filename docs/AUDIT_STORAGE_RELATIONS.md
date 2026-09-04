# Vynic Audit Storage / Relation Integrity Investigation

Investigation and architecture report. **No production schema, migration, Hive
format, ingestion path, or historical row was changed.** No live Venue data was
read; every statement below comes from tracing this repository state.

Paths are relative to `apps/operations/lib/` (POS/Manager Flutter) unless
prefixed with `backend/` (`apps/backend/src/`) or `prisma/`
(`apps/backend/prisma/`).

Product question: *can an Order's full audit lifecycle be navigated and
understood as one ordered timeline?*

**Short answer: the events are all there and correctly parented, but the
timeline is not durably ordered and cannot be reached from the Order.** Two
defects are real (one confirmed by execution), the rest is ergonomics.

---

## A. Current Prisma audit graph

### A1. Model-by-model facts

**`Order`** (`prisma/schema.prisma:29`)

| Property | Value |
| --- | --- |
| Primary key | `id String @id @default(uuid())` — Cloud row identity, unknown to the POS |
| Business key | `posOrderId Int`, unique as `@@unique([venueId, posOrderId])` |
| Tenant | `venueId String`, `venue Venue @relation(... onDelete: Restrict)` |
| Other unique | `closureId String? @unique` — **globally** unique, not venue-scoped |
| Relations | `items OrderItem[]` (child, `onDelete: Cascade`) |
| Indexes | `@@index([venueId, businessDate])` |
| Audit link | **none** — no relation field to `AuditReport` in either direction |

**`OrderItem`** (`:65`) — PK `id` uuid, `orderId` FK → `Order.id`
`onDelete: Cascade`, `@@index([orderId])`. No venueId (tenant via parent).

**`AuditReport`** (`:226`)

| Property | Value |
| --- | --- |
| Primary key | `id String @id @default(uuid())` — row identity |
| Sync key | `reportId String`, unique as `@@unique([venueId, reportId])` |
| Order link | `posOrderId Int` — **a plain integer column, no foreign key** |
| Tenant | `venueId String`, `venue Venue @relation(... onDelete: Restrict)` |
| Snapshots | `tableNumbers String[]`, `floor String @default("first")` |
| Envelope | `openedById/Name`, `openedAt`, `status String`, `closedAt?`, `closedById?`, `closedByName?`, `locked Boolean @default(false)` |
| Sync state | `syncRevision String?` (null = "revision unknown", forces rewrite) |
| Children | `events AuditEvent[]` |
| Indexes | `@@index([venueId])`, `@@index([posOrderId])`, `@@index([status])` |
| Nullable relations | none; `venueId` is required |

`@@index([posOrderId])` is **not** venue-scoped, so it indexes an integer that
is only meaningful inside a Venue.

**`AuditEvent`** (`:258`)

| Property | Value |
| --- | --- |
| Primary key | `id String @id @default(uuid())` — **regenerated on every ingest** |
| Parent | `reportId String`, `report AuditReport @relation(fields: [reportId], references: [id], onDelete: Cascade)` |
| Ordering | `seq Int @default(0)` — present since `20260618150314_init` |
| Payload | `type`, `itemName`, `previousQty`, `newQty`, `waiterId`, `waiterName`, `eventTime DateTime`, `note String?`, `details Json?` |
| Indexes | `@@index([reportId])` only |
| Tenant | **none** — no `venueId`; tenancy is inherited through `report` |
| Order link | **none** — no `orderId` / `posOrderId` column |
| Unique constraints | none |

`details` was added by `20260904120000_audit_closure_semantics`; `seq` has
existed since the initial migration.

**`AuditEventLog`** (`:277`) — PK `id String @id @default(uuid())`, but
ingestion writes **the POS's own UUID** into it
(`backend/pos/sync/application/ingest-audit-reports.service.ts:ingestEventLogs`),
dedupes on `(id, venueId)` and never updates an existing row. Columns:
`venueId` (FK → Venue, Restrict), `action String`, `userId String`,
`data Json`, `deviceType String`, `createdAt`. Indexes
`@@index([venueId, createdAt])`, `@@index([createdAt])`, `@@index([action])`.
**No `entityType` / `entityId`** — a reservation's identity lives inside the
`data` JSON.

**`PosReservation`** (`:196`) — PK `id` uuid, business key
`@@unique([venueId, posReservationId])`, `linkedOrderId Int?` (**no FK**),
`tableNumbers Int[]`, `tableRefs String[]`, `@@index([venueId, reservationDate])`.
No audit relation.

**`Venue`** (`:519`) — back-relations `auditReports AuditReport[]` and
`auditEventLogs AuditEventLog[]`. **No `auditEvents` back-relation** (there is
no `AuditEvent.venueId` for one to attach to).

**`Staff`** (`:167`) — PK `id` uuid, `@@unique([venueId, username])`. Audit
actors are stored as free strings (`AuditEvent.waiterId` / `waiterName`,
`AuditEventLog.userId`); **there is no FK from any audit row to `Staff`**.

**`Sale`** — **does not exist in Prisma.** There is no `Sale` model, and
`grep "model Sale"` on `schema.prisma` returns nothing. Sales reach Cloud only
as day-aggregate JSON blobs written into `Setting` rows
(`salesSummary:<YYYY-MM-DD>`, `salesSummary:all_time`,
`salesSummary:history_index`) by
`backend/pos/sync/snapshot/business-day-sync.service.ts:135-205`. The Sale is a
Hive-only record on the POS.

### A2. Direct answers

```text
Does AuditReport have a real Prisma relation to Order?   NO
Does AuditEvent have a real Prisma relation to AuditReport?  YES (Cascade)
Does AuditEvent also store orderId directly?             NO (only inside details JSON,
                                                            and only on Phase-2/3 event types)
Can Prisma Studio navigate Order -> AuditReport -> AuditEvents?
                                                         PARTIALLY: report -> events yes,
                                                         Order -> report NO
```

`AuditEvent.details.orderId` is written by the Phase-2/3 emitters
(`services/audit/order_audit_details.dart:base`) for creation, transfer, close,
cancel, advance and adjustment events. It is **absent** from the plain
`ADD_ITEM` / `REDUCE_QTY` / `DELETE_ITEM` diff rows, which carry no `details`
at all, and absent from every pre-Phase-2 historical row.

---

## B. Why nested AuditEvents are hard to see

The relation is not missing. Ranked by actual impact:

1. **`Order` has no relation field at all.** Neither `Order.auditReport` nor
   `AuditReport.order` exists, so a Studio row for `Order` shows `items` and
   `venue` and nothing else. Reaching the report means reading `posOrderId`,
   switching to the `AuditReport` table and filtering by hand. **This is the
   primary reason.**
2. **`AuditReport.events` renders as a linked-record cell, not inline rows.**
   Studio never expands a one-to-many inline; it shows a chip that opens a
   filtered child view. So "AuditReport → AuditEvent items" is always a
   deliberate second click, never something visible while scanning reports.
3. **The child view is not ordered by the timeline.** Studio's default sort is
   the model's `@id` — a random uuid. `seq` exists but Studio does not use it,
   and there is no `createdAt`. The Manager endpoint sorts explicitly
   (`backend/mobile/services/mobile-reports.service.ts:60`,
   `events: { orderBy: { seq: 'asc' } }`); Studio does not.
4. **Browsing the `AuditEvent` table directly is useless per Order.** It has no
   `orderId`, no `venueId`, and no human-readable column — only a uuid
   `reportId` pointing at a uuid `AuditReport.id`. `AuditReport.reportId` *is*
   readable (`audit_report_order_123`) but the children do not carry it.
5. **Rows are rewritten on every revision.** Ingestion runs
   `auditEvent.deleteMany({ where: { reportId } })` followed by `createMany`
   (`ingest-audit-reports.service.ts:230-256`), so **every `AuditEvent.id`
   changes on each push**. A row noted yesterday no longer exists.
6. **The interesting fields are inside `details` JSON**, which Studio collapses.

Explicitly **not** the cause: missing report↔event relation fields (they
exist), and multi-schema (Prisma 6.19 has multiSchema GA and Studio handles
`pos`/`website` fine).

---

## C. Current sync/storage lifecycle — one traced example

`CREATE_WALKIN → ADD_ITEM → RECORD_ADVANCE → CLOSE` for POS Order **123**,
report key `audit_report_order_123`, Venue `V`.

### C1. POS / Hive

Storage: one Hive row, `auditLogBox['audit_report_order_123']`, holding the
entire report as a map (`models/audit_report.dart:AuditReport.toMap`).

| Stage | Written by | Identifier | Parent | orderId | venueId | type | timestamp | details | revision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| create | `order_repository.dart:createOrder` → `_appendCreationAudit` | *(none — array position)* | report key | `123` | *(none locally)* | `CREATE_WALKIN` | `order.createdAt` | `orderId, orderKind=WALK_IN, tableNumbers, tableRefs, floor, source, actorId, actorName, businessDate, includeServiceFee` | sha256 of whole report |
| initial lines | same call, same list | *(none)* | report key | `123` | — | `ADD_ITEM` ×n | **same `order.createdAt`** | *(none)* | same |
| advance | `services/audit/money_audit.dart:390` `_mirrorToOrderReport` | *(none)* | report key | `123` | — | `RECORD_ADVANCE` | `getCurrentDateTime()` | base + `previousAmount, newAmount, receiptId, collectedOn` | changes |
| close | `close_table_transaction.dart:_closureDetails` → `audit_repository.dart:581 finalizeOrderClosureAudit` | *(none)* | report key | `123` | — | `CLOSE` | close time | base + `closureId, isFiscal, grossAmount, paymentMethod, paymentBreakdown, cashAmount, cardAmount, advanceApplied, collectedNow, serviceFee, discountAmount, manualAdjustmentAmount` | changes; report becomes `CLOSED` + `locked` |

The POS event has **no id and no ordinal**. Its only identity is its position in
the `events` array, and that position is re-derived by sorting on every read
(§E).

### C2. Sync payload

`services/sync/manager_sync_service.dart:1015` selects dirty reports via
`AuditSyncState.selectDirty(DatabaseService.getAuditReports())`, batches them,
and POSTs to `/sync/audit-reports`
(`manager_sync_service.dart:1112`). The wire shape is
`DirtyAuditReport.toPayload()` = `report.toMap()` plus `revision`
(`services/sync/audit_sync_state.dart`):

```jsonc
{ "reportId": "audit_report_order_123", "orderId": 123, "tableNumbers": [...],
  "floor": "first", "openedById": ..., "openedAt": ..., "status": "CLOSED",
  "locked": true, "closedAt": ..., "updatedAt": ...,
  "revision": "<sha256 of canonicalized report>",
  "events": [ { "type": "CREATE_WALKIN", "itemName": "ORDER", "previousQty": 0,
                "newQty": 0, "waiterId": ..., "waiterName": ...,
                "timestamp": "...", "details": { ... } }, ... ] }
```

`venueId` is **not** on the wire. Events carry **no id and no sequence** — the
JSON array order is the only ordering signal.

### C3. Backend ingestion

`backend/pos/sync/application/ingest-audit-reports.service.ts:persistReport`:

1. `venueId` comes from the authenticated Device / legacy sync principal
   (`TenantContext`), never from the payload.
2. `auditReport.findUnique({ venueId_reportId })`; if `syncRevision ===
   revision`, **return early, events untouched**.
3. Otherwise `auditReport.upsert` on `(venueId, reportId)` writing
   `posOrderId = payload.orderId`.
4. `auditEvent.deleteMany({ reportId: dbReport.id })`.
5. `auditEvent.createMany(...)` with `type` through `normalizeAuditEventType`
   and `seq` = **the array index**.

### C4. Prisma rows

| Table | Identifier | Parent | orderId | venueId | type | timestamp | details | revision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `AuditReport` | `id` uuid (server) + `reportId` `audit_report_order_123` | `venueId` | `posOrderId=123` (no FK) | yes | — | `openedAt` / `closedAt` / `updatedAt` | — | `syncRevision` |
| `AuditEvent` #1 | `id` uuid, **new on every push** | `reportId` → report uuid | none | none | `CREATE_WALKIN` | `eventTime` | `details` JSONB | none |
| `AuditEvent` #2..n | same | same | none | none | `ADD_ITEM` | same instant as #1 | null | none |
| `AuditEvent` | same | same | none | none | `RECORD_ADVANCE` | advance time | JSONB | none |
| `AuditEvent` | same | same | none | none | `CLOSE` | close time | JSONB | none |

**Is parent-child identity preserved end-to-end?**

- *Report* identity: **yes.** `audit_report_order_123` is stable from Hive key
  to wire to `(venueId, reportId)`.
- *Report → Order*: **by convention only.** `posOrderId` is an unenforced
  integer; nothing guarantees a matching `Order` row exists.
- *Event* identity: **no.** The POS never assigns one; Cloud invents a uuid and
  throws it away on the next revision.
- *Event ordering*: **partially.** `seq` records the array order the backend
  received, but that array order is itself re-derived by an unstable sort on the
  POS (§E).

---

## D. Event identity stability

```text
Does ingestion DELETE existing AuditEvent rows and recreate them?  YES
Does AuditEvent identity survive sync?                             NO
Are event IDs stable across revisions?                             NO
Can a database consumer safely reference one AuditEvent row over time?  NO
```

`ingest-audit-reports.service.ts:230-256` deletes every event of the report and
recreates the whole list on any revision change. Same for the reconcile path
(`:302`), which deletes reports the POS no longer lists, and their events.

Consequences of delete-and-recreate:

| Area | Consequence |
| --- | --- |
| Foreign keys | Nothing may FK to `AuditEvent.id`. Any future table doing so would break on the next sync of that report. |
| External references | A Manager deep-link, a support ticket, a BI extract, or an export keyed on `AuditEvent.id` becomes a dangling id after one edit to the Order. |
| Event IDs | Non-durable. They are storage artefacts, not identifiers. |
| Sequence / order | `seq` is positional and correct **for the array it received**. It is re-assigned wholesale, so `seq=2` can mean a different event before and after a re-push. |
| Prisma Studio | Row-level inspection is not repeatable; ids churn. |
| Future audit APIs | An event-level API must expose `(reportId, seq)` or a POS-assigned key, never `AuditEvent.id`. Cursor pagination on `id` would be unstable. |
| Cost | Every touched open Order rewrites its whole event list on each sync. |

There is a **second writer**: `backend/mobile/services/mobile-orders.service.ts:380-437`
appends `AuditEvent` rows directly on Cloud for Manager-originated order edits,
continuing `seq` from `existing.length`, creating the `AuditReport` if absent
with `openedAt = now`. Those rows are **destroyed** by the next POS push of that
report (which rewrites the events from the POS's own copy). Until then, Cloud
holds events the POS does not have.

Behaviour is unchanged by this report.

---

## E. Event ordering — a confirmed defect

### E1. Where order comes from today

| Stage | Mechanism | Stable? |
| --- | --- | --- |
| POS append | `audit_repository.dart:539` `mergeSort` by `timestamp` over existing + new | **yes** (`package:collection` merge sort is stable) |
| POS read/deserialize | `models/audit_report.dart:AuditReport.fromMap` → `..sort((a,b) => a.timestamp.compareTo(b.timestamp))` | **NO** — `List.sort` is documented as not stable |
| POS UI | `AuditReport.sortedEvents` → `sorted()` (also `List.sort`), descending | **NO** |
| Wire | JSON array order | inherits the read order |
| Backend | `seq` = array index | faithful to what it received |
| Manager read | `orderBy: { seq: 'asc' }` | faithful |
| Studio read | default `@id` (uuid) | random |

### E2. Can two events share a timestamp?

**Yes, by design.** `order_repository.dart:620 _appendCreationAudit` builds the
creation event and every initial `ADD_ITEM` with the *same* `order.createdAt`,
and the comment at `audit_repository.dart:536` states the merge is stable
precisely because of this. `OrderAuditDetails.strictlyAfter` was added to force
`APPLY_PACKAGE` after the creation event — evidence the tie problem is already
known and was patched case-by-case rather than structurally.

### E3. Confirmed failure

Dart's `List.sort` uses insertion sort (stable) only for ranges ≤ 32 elements
and dual-pivot quicksort (unstable) above that. Executed probe modelling
`_appendCreationAudit`'s exact tie pattern (one `CREATE_WALKIN` followed by N
`ADD_ITEM`s at one timestamp):

```text
items=5   first event after sort = CREATE   OK
items=31  first event after sort = CREATE   OK
items=32  first event after sort = CREATE   OK
items=33  first event after sort = ADD10    REORDERED
items=40  first event after sort = ADD13    REORDERED
items=60  first event after sort = ADD19    REORDERED
items=100 first event after sort = ADD33    REORDERED
```

So: **an Order opened with more than 32 initial lines — a Package with a long
line list, or a large table's first submit — loses `CREATE_WALKIN` from
position one as soon as its report is read back.** The permutation then
persists: `appendOrderAuditEvents` merges onto the permuted list and writes it
back, the revision changes, the report re-syncs, and the backend stamps `seq`
in the permuted order. The Manager and Studio then show a timeline that opens
mid-item-list.

The revision still *settles* (quicksort is deterministic for a given input), so
this is not the "dirty forever" failure mode — it is a silently wrong order.

Existing tests (`test/unit/order_creation_audit_test.dart`) assert
`report.events.first` is the creation event, but only with small item counts, so
they pass.

### E4. Is an explicit `sequence` necessary?

Split by side:

| Side | Verdict | Reasoning |
| --- | --- | --- |
| **Prisma / Cloud** | `NOT_NEEDED` | `AuditEvent.seq` already exists, is populated, and is what the Manager orders by. Adding another ordering column would be redundant. |
| **POS report + wire** | **REQUIRED** | Order is currently *re-derived by sorting a mutable key on every read*, and that derivation is provably wrong above 32 events. An ordinal recorded at write time is the only representation that survives ties, clock adjustments, and reads. |

Desired shape, expressed on the wire and stored in `seq`:

```text
orderId=123
sequence=0  CREATE_WALKIN
sequence=1  ADD_ITEM
sequence=2  RECORD_ADVANCE
sequence=3  CLOSE
```

Not implemented here.

---

## F. Order ↔ AuditReport relation

| Criterion | A: relations only (`Order → AuditReport → AuditEvent[]`) | B: A + denormalized `AuditEvent.orderId` / `venueId` | C: no report parent, events on Order | D: keep report as the durable root, **no** FK to Order |
| --- | --- | --- | --- | --- |
| Audit integrity | **breaks** — an FK ties audit life to the operational row | same break | worst — audit dies with the Order | **safe** — audit outlives the Order |
| Queryability | good via join | best (single-table filters) | good | good via join; best with `AuditEvent.venueId` |
| Studio readability | best | best | good | needs an explicit convention or an optional relation |
| Tenant safety | via `AuditReport.venueId` | direct `venueId` on events | via Order | via `AuditReport.venueId`; improved by `AuditEvent.venueId` |
| Sync simplicity | **worse** — ingestion must resolve/await the Order row | worse still (two extra columns to populate) | much worse | **unchanged** |
| Historical compatibility | **fails** — legacy synthetic reports and reports for long-gone Orders cannot satisfy the FK | fails | fails | works |
| Manager API perf | fine | best for cross-order event scans | fine | fine |
| Future analytics | fine | best | poor (loses the report envelope) | good with `AuditEvent.venueId` |
| Global entity timeline | neutral | neutral | blocks it | neutral |

**Recommendation: Option D, plus the one denormalized column from B that pays
for itself — `AuditEvent.venueId`.**

Concretely: keep `AuditReport` as the durable parent, keep `posOrderId` as an
indexed *snapshot* rather than a foreign key, keep the existing
`AuditReport → AuditEvent[]` cascade, and add `AuditEvent.venueId` for
tenant defence-in-depth and single-table analytics indexes.

Do **not** add `AuditEvent.orderId`: `AuditReport` is already one-per-Order and
carries `posOrderId`, so the column would be a second copy of a fact with no
query that needs it and a backfill that must be kept in step forever.

Option C is rejected outright: the report envelope (`status`, `locked`,
`openedBy*`, `closedBy*`, `syncRevision`) is the unit the POS locks and the unit
sync acknowledges. Dissolving it would destroy both the immutability guard and
the revision contract.

---

## G. Order relation and Close Day archival

**Should `Order` expose `auditReport AuditReport?` — i.e. a real FK?**

**No, not as a required or cascading relation.** Four independent facts in this
codebase make it unsafe:

1. **Audit and orders arrive on different endpoints with no ordering
   guarantee.** Reports go to `/sync/audit-reports`; orders arrive in the
   snapshot. A required FK would reject a report whose Order has not been
   ingested yet.
2. **Backfill uploads reports for Orders that no longer exist on Cloud.** The
   first sync after upgrading pushes the POS's entire audit history
   (`manager_sync_service.dart:1004`), including reports for Orders deleted from
   Cloud months ago.
3. **The POS also pushes synthetic legacy reports.**
   `AuditRepository.getAuditReports` appends `_buildLegacyAuditReports` output,
   keyed `legacy_report_order_<id>`, derived from old log rows. There may be no
   Order behind them at all.
4. **The Manager creates `AuditReport` rows itself.**
   `mobile-orders.service.ts:396` creates a report keyed
   `audit_report_order_<posOrderId>` before the POS snapshot has necessarily
   created the Order row.

**And if the Order row is deleted:** with `onDelete: Cascade` the audit history
would be destroyed. This is not hypothetical — `order-sync.service.ts:266-302`
runs `order.deleteMany` for the current business date against rows the snapshot
omits. One restore-driven reconcile would silently erase that Order's entire
audit trail. `onDelete: Restrict` is equally wrong: it would make the reconcile
throw and block sync.

**The durable hierarchy is therefore:**

```text
Venue
└── AuditReport (posOrderId snapshot, orderKind, status, locked)
    └── AuditEvent[]  (seq-ordered)
```

with the Order relation **optional at most**. If Studio navigation is judged
worth it, the only acceptable form is:

```prisma
// Ergonomics only. NEVER Cascade, NEVER Restrict, NEVER required.
orderId String?
order   Order?  @relation(fields: [orderId], references: [id], onDelete: SetNull)
```

`posOrderId` remains the correctness-bearing link; `orderId` is a convenience
pointer that is allowed to be null and allowed to go null.

---

## H. Close Day archival impact — verified

**POS (`database/transactions/close_day_transaction.dart`)**

| Store | Effect |
| --- | --- |
| `Order` | closed rows **deleted** from `orderBox` (`:214-220`) |
| `Sale` | untouched — `salesBox` is the durable financial record |
| `AuditReport` / events | **untouched** — `auditLogBox` is never purged by Close Day |
| `Reservation` | status-transitioned to `completed` / `no-show`, never deleted |
| tables | freed |

**Cloud**

| Table | Effect |
| --- | --- |
| `Order` | **survives.** The reconcile in `order-sync.service.ts:258-302` is scoped to `businessDate: currentBusinessDate`; once the day rolls forward, yesterday's rows are outside its filter. |
| `AuditReport` / `AuditEvent` | **survive.** `knownReportIds` still lists every report the POS holds, so the reconcile finds nothing stale. |
| `Sale` | **does not exist.** Only `Setting['salesSummary:<date>']` aggregates. |

Desired invariant, measured:

```text
Order operational row may disappear                       ✔ (locally; Cloud keeps it)
BUT Sale + AuditReport + AuditEvents remain queryable
    AuditReport + AuditEvents                             ✔
    Sale                                                  ✘ on Cloud — no per-Sale row exists
```

Two conclusions:

- **Current Prisma relations do not obstruct the invariant** — precisely
  because there is no FK from `AuditReport` to `Order`. Adding one would create
  the obstruction that does not exist today.
- **The real gap is `Sale`, not the audit graph.** Cloud can show an Order's
  audit timeline for a past day, but cannot show the Sale that settled it; only
  a day aggregate. That is a separate piece of work and is deliberately out of
  scope here. `Order.closureId` and `AuditEvent.details.closureId` are the only
  per-closure facts Cloud holds.

---

## I. Table-reference strategy

**Table must not be the audit parent. Verified reasons:**

1. A physical table hosts many Orders over time; `Table.activeOrderId Int?` is a
   *current* pointer with no FK and no history.
2. Takeaway has no physical table at all: `createTakeAwayOrder`
   (`order_repository.dart:197-211`) synthesises `TA-<orderId>` on floor
   `takeaway`. That identifier is not in the `Table` table.
3. Table configuration is mutable — `@@unique([venueId, tableNumber, floor])`
   means renaming or re-flooring a table changes its identity. Audit read
   through an FK would silently re-label history.

The conceptual rule holds and is what the code already implements:

```text
Table       = context / reference
Order       = business lifecycle
AuditReport = Order timeline
```

**Recommendation: keep the snapshot, add no relation.** Today's storage is
already right:

- `AuditReport.tableNumbers String[]` + `AuditReport.floor` — envelope snapshot.
- `AuditEvent.details.tableNumbers` and `details.tableRefs`
  (`"first/7"`, from `OrderAuditDetails.tableRefs`) + `details.floor` — per-event
  snapshot, lossless across floors.

`tableRefs` is the form to prefer in any future query or UI, because bare
`tableNumbers` collide across floors. No schema change is needed.

---

## J. Order-kind strategy

Today, the kind of an Order is knowable from the audit alone **only** by:

1. reading `events[0].details.orderKind` (`WALK_IN` / `TAKEAWAY` / `PACKAGE` /
   `RESERVATION`, set by `OrderAuditDetails.base`), or
2. the event *type* itself (`CREATE_WALKIN` / `CREATE_TAKEAWAY` /
   `ACTIVATE_RESERVATION`, with `APPLY_PACKAGE` following a `CREATE_WALKIN`
   whose `orderKind` is `PACKAGE`).

Both depend on identifying the *first* event — which §E shows is not reliable
above 32 events — and on a JSON path in SQL. Reports created before Phase 2 have
**no creation event at all**, so their kind is recoverable only from the
fragile `floor == 'takeaway'` string.

**Assessment: `AuditReport.orderKind String?` is RECOMMENDED, not yet
implemented.** It turns "join events, order them, read JSON" into an indexed
column, and it is the natural place for a fact that is a property of the report,
not of one event. Event `details` stay as they are (they are the provenance).

Backfill is **only partially deterministic**: derivable where a Phase-2+
creation event exists, and `TAKEAWAY` is derivable from `floor` for the rest;
`WALK_IN` vs `PACKAGE` vs `RESERVATION` is **not** recoverable for pre-Phase-2
reports. A nullable column with a partial backfill is the honest shape.

---

## K. Snapshot vs append-only assessment

| Criterion | Snapshot / revision rewrite (current) | Append-only event rows |
| --- | --- | --- |
| Offline-first POS | **strong** — the POS owns the report and offers it whole; no per-event ack state to keep in Hive | needs per-event sync state, a second acknowledgment box |
| Conflict handling | trivial — POS wins, whole report | needs merge rules for Manager-originated events |
| Idempotency | **total** — any redelivery converges | needs a stable per-event key to dedupe on |
| Event deletion risk | **high** — a rewrite can silently drop events | **none by construction** |
| Restore / reopen | already handled (`RESTORE` appended, report unlocked) | same |
| Manager-originated changes | currently broken: Cloud-appended rows are destroyed by the next POS push | natural fit |
| Audit immutability | weak (see §L) | strong |
| Prisma row stability | **none** | strong |
| Historical correction | easy (arguably too easy) | requires a compensating event |

**Answer: yes, Vynic should keep revision-based `AuditReport` sync.**

The rewrite model is what makes an offline-first POS with at-least-once delivery
simple and correct, and it is load-bearing for the acknowledgment contract in
`AuditSyncState`. Moving to append-only would require per-event identity, a
per-event ack box, and a merge policy — a large change that buys immutability
Vynic can get more cheaply.

The cheaper path to the same guarantee: **make the rewrite a no-op when nothing
changed, and make it order-preserving and identity-preserving when it does.**
That is a POS-assigned `sequence` plus (optionally) a POS-assigned event key,
after which "delete and recreate" becomes an implementation detail rather than a
semantic one. The one genuinely append-only behaviour worth adopting is on the
Cloud side: replace `deleteMany` + `createMany` with an upsert keyed
`(reportId, seq)` once `seq` is POS-authoritative.

---

## L. Immutability assessment

```text
Classification: SNAPSHOT_REWRITABLE
```

Evidence that historical rows can disappear or change through sync alone:

| Operation | Path | Effect |
| --- | --- | --- |
| Revision change | `ingest-audit-reports.service.ts:230` | every `AuditEvent` of the report deleted and recreated |
| Reconcile | `:296-308` | whole reports and their events deleted when the POS stops listing them |
| Manager edit | `mobile-orders.service.ts:417` | events appended on Cloud that the next POS push destroys |
| POS restore | backup restore writes rows under canonical keys | report contents replaced wholesale |
| Reorder | §E | tied events permuted on read, then persisted and re-pushed |

Guards that do exist: `AuditReport.locked` makes the POS refuse appends
(`audit_repository.dart:532`, `StateError`), with one deliberate exception
(`allowLocked` for `VOID_SALE`), and the reconcile refuses to honour an **empty**
report set (`:288-295`), so a POS whose audit box failed to open cannot wipe the
Venue's history.

Implications:

- Nothing may hold a foreign key or an external reference to `AuditEvent.id`.
- A regulator-grade "this row has never changed" claim cannot be made today.
- The system *is* trustworthy at report granularity (`reportId` is stable,
  `locked` is honoured, empty-set wipes are refused) — it is untrustworthy at
  row granularity.
- `LOGICALLY_IMMUTABLE` is reachable without redesign: POS-assigned `sequence`
  + upsert-on-`(reportId, seq)` instead of delete/recreate makes a re-push
  incapable of removing an event that still exists locally.

---

## M. Generic entity audit recommendation (Phase 4)

Phase 4 needs timelines for Reservations, Staff, Expenses, Menu, Package
configuration, Close Day and backup restore.

Current state: `AuditEventLog` is the right *shape* — append-only, id = POS
UUID, dedup on id, never updated, `data Json`, indexed on `action` — and it
already carries the Phase-3 Reservation timeline
(`services/audit/reservation_audit.dart:ReservationAuditAction`). Its one
structural gap is that **entity identity is buried in `data` JSON**
(`data.reservationId`), so "everything that happened to reservation X" is a JSON
scan, not an index seek.

| Option | Assessment |
| --- | --- |
| One universal `AuditEvent` model for Orders and everything else | **Rejected.** The Order report has an envelope (status, locked, openedBy/closedBy, `syncRevision`) with no meaning for a Staff edit; the sync units differ (whole-report revision vs append-only row); and merging forces a migration of live history plus a rewrite of the acknowledgment contract. |
| **Specialized Order `AuditReport` + generic `AuditEventLog` with `entityType`/`entityId`** | **Recommended.** Additive, no migration of Order audit, keeps the two sync models that are each correct for their data, and makes the generic timeline indexable. |

Recommended additive columns on `AuditEventLog`:

```prisma
entityType String?   // 'RESERVATION' | 'STAFF' | 'EXPENSE' | 'MENU' | 'PACKAGE' | 'CLOSE_DAY' | 'BACKUP'
entityId   String?
@@index([venueId, entityType, entityId, createdAt])
```

Backfill is deterministic for the Reservation actions (`data.reservationId` is
present on every `ReservationAuditAction` row) and not needed for the rest,
which have no entity today. Nullable is correct: global actions
(`developer.*`, `BUSINESS_DATE_CHANGED`) genuinely have no entity.

A **reader** remains the larger missing piece: `AuditEventLog` is still
write-only end to end (no POS caller for `getAuditLogs`, no backend endpoint).
Columns without a reader change nothing the user can see.

---

## N. Tenant / index strategy

**Current chain, verified safe:**

```text
Device credential / legacy sync principal
  → TenantContext.venueId (server-owned; the payload is never trusted)
    → AuditReport.venueId          (unique on (venueId, reportId))
      → AuditEvent via reportId    (the report's uuid PK)
```

Every read path filters on the parent: the Manager endpoint queries
`auditReport.findMany({ where: { venueId } })` with `include: { events }`
(`mobile-reports.service.ts:56`), and the Manager-side writer resolves the
report by `venueId_reportId` before touching events
(`mobile-orders.service.ts:388`). The integration proof
`audit-incremental-sync.integration.spec.ts` asserts that the same `reportId` in
two Venues is two separate reports. **No current query reaches `AuditEvent`
without going through a venue-scoped parent.**

`AuditEvent.venueId` would therefore be **defence-in-depth, not a fix**. It is
still worth it, for two reasons:

- a future event-level query (analytics, a global timeline, an export) would
  otherwise be one forgotten `where` away from cross-tenant leakage;
- it enables `@@index([venueId, type, eventTime])`, which turns "every `CLOSE`
  this month for this Venue" from a join-then-filter into an index range scan.

Index recommendations:

| Index | Purpose | Status |
| --- | --- | --- |
| `AuditEvent @@index([reportId, seq])` | the timeline read the Manager already performs | replaces the bare `[reportId]` |
| `AuditEvent @@index([venueId, type, eventTime])` | cross-order event queries | needs `venueId` first |
| `AuditReport @@index([venueId, posOrderId])` | Order → report lookup | **replaces the current non-tenant `@@index([posOrderId])`**, which indexes an integer that is only meaningful per Venue |
| `AuditReport @@index([venueId, status])` | open/cancelled listings | replaces the bare `@@index([status])` |
| `AuditEventLog @@index([venueId, entityType, entityId, createdAt])` | generic entity timeline | needs §M columns |

Also noted, not in scope: `Order.closureId` is `@unique` **globally** rather
than `@@unique([venueId, closureId])`. `closureId` is POS-generated, so two
Venues' POS instances collide in principle; the current uniqueness would reject
the second rather than isolate it.

---

## O. Prisma Studio usability

Split as requested:

**`DATABASE_CORRECTNESS` — worth doing regardless of Studio**

1. POS-assigned `sequence` on each report event, carried on the wire into the
   existing `AuditEvent.seq`. Fixes the confirmed >32-event reordering (§E).
2. Stable sort on the POS read path (`AuditReport.fromMap`, `sortedEvents`) —
   `mergeSort`, as `appendOrderAuditEvents` already uses. This alone fixes the
   observed defect; the `sequence` field makes it structurally impossible to
   recur.
3. `AuditEvent.venueId` + `@@index([venueId, type, eventTime])` — tenant
   defence-in-depth and analytics (§N).
4. Venue-scoping the `AuditReport` indexes (§N).
5. `AuditReport.orderKind` — a report-level fact currently only reachable
   through an ordered JSON path (§J).

**`DEVELOPER_ERGONOMICS` — only if the cost is accepted**

6. `AuditReport.orderId String?` + `order Order? @relation(onDelete: SetNull)`.
   The single change that makes Studio navigate `Order → AuditReport → events`.
   Costs a lookup during ingestion and a nullable column; **must** be
   `SetNull` (§G).

**Not worth doing:** cosmetic label columns. Studio cannot be told to sort a
child view by `seq`, so no schema change makes the timeline read correctly there
by default. A read endpoint or a small internal view is the right answer to
"open the DB and understand it", not more columns.

What the user asked to see, and where it comes from after 1–6:

| Question | Answer |
| --- | --- |
| which event belongs to which Order | `AuditReport.posOrderId` (+ optional `order` relation) |
| which event happened first | `AuditEvent.seq`, once POS-assigned |
| which actor caused it | `waiterName` / `details.actorName`, `details.source` |
| how the Order was created | first event type + `AuditReport.orderKind` |
| how it closed | `CLOSE` / `INTERNAL_CLOSE` / `TRANSFER_CLOSE` / `CANCEL_TABLE` + `details` |

---

## P. Recommended target schema

```text
Venue
└── AuditReport                    (the durable root; survives the Order)
    ├── reportId                   "audit_report_order_<posOrderId>"   [have]
    ├── posOrderId                 snapshot, indexed, NOT a foreign key [have]
    ├── orderId?                   optional convenience FK, SetNull     [MISSING, ergonomics only]
    ├── orderKind?                 WALK_IN|TAKEAWAY|PACKAGE|RESERVATION [MISSING]
    ├── status / locked            OPEN|CLOSED|CANCELLED                [have]
    ├── tableNumbers / floor       snapshot, never an FK to Table       [have]
    ├── syncRevision               acknowledgment contract              [have]
    └── events AuditEvent[]        cascade from the report only         [have]
        ├── venueId                denormalized tenant                  [MISSING]
        ├── seq                    POS-assigned ordinal                 [column exists; POS does not assign it]
        ├── type                   canonical enum-as-string             [have]
        ├── eventTime              wall clock, NOT the ordering key     [have]
        ├── waiterId / waiterName  actor                                [have]
        └── details Json           orderKind, tableRefs, source,
                                   closureId, payment breakdown, …      [have]

Venue
└── AuditEventLog                  (append-only, POS-UUID identity)
    ├── entityType? / entityId?    RESERVATION|STAFF|EXPENSE|…          [MISSING]
    ├── action / userId / data     [have]
    └── createdAt                  [have]
```

```text
WHAT WE ALREADY HAVE
  - AuditReport -> AuditEvent[] as a real, cascading Prisma relation
  - AuditEvent.seq, and a Manager endpoint that orders by it
  - AuditEvent.details JSONB carrying orderKind, tableRefs, source,
    closureId and the full payment breakdown
  - venue-scoped report identity (venueId, reportId) with server-owned tenancy
  - AuditEventLog as a genuinely append-only store with stable POS-UUID ids
  - audit history that already survives Close Day, because there is no FK to Order

WHAT IS MISSING
  - a POS-assigned per-report event sequence (Cloud has the column; the POS
    never fills it, and re-derives order by an unstable sort)
  - a stable sort on the POS read path
  - AuditEvent.venueId (tenant defence-in-depth + analytics index)
  - AuditReport.orderKind as a queryable column
  - entityType/entityId on AuditEventLog, and any reader for it at all
  - a per-Sale Cloud record (out of scope; the largest real archival gap)

WHAT SHOULD NOT BE ADDED
  - a required or cascading FK from AuditReport to Order  (destroys history)
  - any FK from audit rows to Table or Staff              (rewrites history when
                                                            config changes)
  - AuditEvent.orderId                                    (second copy of a fact
                                                            AuditReport already holds)
  - one universal AuditEvent model replacing AuditReport  (destroys the envelope
                                                            and the revision contract)
  - any external reference to AuditEvent.id               (not durable)
  - label/display columns purely for Prisma Studio
```

---

## Q. Migration / backfill safety

| Change | Class | Notes |
| --- | --- | --- |
| Stable sort in `AuditReport.fromMap` / `sortedEvents` | `NO_MIGRATION` | Dart-only. Changes existing reports' serialized order once, so those reports re-sync — expected and bounded. |
| POS assigns `sequence`; wire carries it; ingestion uses it for `seq` | `NO_MIGRATION` | `seq` already exists. Additive on the wire; an older backend ignores the field, a newer backend falls back to array index for an older POS. |
| `AuditEvent.venueId` | `ADDITIVE_SAFE` + `BACKFILL_REQUIRED` | Nullable first, then backfill `UPDATE ... FROM AuditReport WHERE AuditEvent.reportId = AuditReport.id`. **Fully deterministic.** Make it required only after the backfill and after ingestion writes it. |
| `AuditEvent @@index([reportId, seq])`, `@@index([venueId, type, eventTime])` | `ADDITIVE_SAFE` | Index creation only. Use `CREATE INDEX CONCURRENTLY` on a live database. |
| `AuditReport @@index([venueId, posOrderId])`, `@@index([venueId, status])` | `ADDITIVE_SAFE` | Replaces the non-tenant `[posOrderId]` / `[status]` indexes. |
| `AuditReport.orderKind` | `ADDITIVE_SAFE` + **partial** `BACKFILL_REQUIRED` | Deterministic where a Phase-2+ creation event exists (`events` where `seq = 0` / earliest, `details->>'orderKind'`), and `TAKEAWAY` from `floor = 'takeaway'`. **Not** deterministic for pre-Phase-2 `WALK_IN` vs `PACKAGE` vs `RESERVATION` — those stay null. |
| `AuditReport.orderId` + `order Order? @relation(onDelete: SetNull)` | `ADDITIVE_SAFE` + `BACKFILL_REQUIRED` | Deterministic from `(venueId, posOrderId)` → `Order.id`; null where no Order row exists (legacy synthetic reports, archived Orders). Requires ingestion to resolve the Order per report — one extra query. Ergonomics only. |
| `AuditEventLog.entityType` / `entityId` | `ADDITIVE_SAFE` + **partial** `BACKFILL_REQUIRED` | Deterministic for Reservation actions (`data->>'reservationId'`, actions in `ReservationAuditAction.all` + `reservation_cancelled`). Nothing else has an entity today. |
| Ingestion upsert on `(reportId, seq)` instead of delete/recreate | `RISKY` | Requires a real unique constraint `@@unique([reportId, seq])`, which existing data may violate if any report was ingested with duplicate `seq` (possible via the `mobile-orders.service.ts` append path racing a POS push). Must be preceded by a duplicate audit. Do not attempt before POS-assigned `sequence` is deployed and settled. |
| Any FK `AuditReport.orderId` with Cascade/Restrict | `RISKY` — **do not do** | Cascade destroys audit history on the current-day order reconcile; Restrict blocks sync. |
| `@@unique([venueId, closureId])` on `Order` replacing global `@unique` | `RISKY` | Correct in principle, but touches the money-integrity idempotency key. Separate task, separate evidence. |

No backfill was performed. No live Vankisi data was accessed.

---

## R. Query examples (design only — nothing implemented)

Assuming the recommended shape (`AuditEvent.venueId`, POS-assigned `seq`,
`AuditReport.orderKind`).

**One Order's full timeline**

```ts
prisma.auditReport.findUnique({
  where: { venueId_reportId: { venueId, reportId: `audit_report_order_${posOrderId}` } },
  include: { events: { orderBy: { seq: 'asc' } } },
});
```

Works today, minus the `seq` guarantee.

**All cancelled Orders today**

```ts
prisma.auditReport.findMany({
  where: { venueId, status: 'CANCELLED',
           events: { some: { type: 'CANCEL_TABLE',
                             details: { path: ['businessDate'], equals: today } } } },
  include: { events: { orderBy: { seq: 'asc' } } },
});
```

**All CLOSE events paid by TBC**

```ts
prisma.auditEvent.findMany({
  where: { venueId, type: 'CLOSE',
           OR: [ { details: { path: ['paymentMethod'], equals: 'card-tbc' } },
                 { details: { path: ['paymentBreakdown', 'card-tbc'], gt: 0 } } ] },
  orderBy: { eventTime: 'desc' },
});
```

The `OR` is required because a split close records `paymentMethod: 'split'` and
puts the provider in `paymentBreakdown`. Needs `AuditEvent.venueId` +
`@@index([venueId, type, eventTime])` to be efficient.

**All events by one staff member**

```ts
prisma.auditEvent.findMany({
  where: { venueId, waiterId: staffUsername },
  orderBy: { eventTime: 'desc' },
});
```

`waiterId` is a free string, not an FK to `Staff` — deliberately, so a renamed
or deleted staff member does not rewrite history. Cross-reference by
`Staff.username`.

**Reservation → activation → Order → close**

```ts
// 1. the booking's own timeline (needs entityType/entityId from §M)
prisma.auditEventLog.findMany({
  where: { venueId, entityType: 'RESERVATION', entityId: reservationId },
  orderBy: { createdAt: 'asc' },
});
// 2. the Order it became
prisma.auditEvent.findFirst({
  where: { venueId, type: 'ACTIVATE_RESERVATION',
           details: { path: ['reservationId'], equals: reservationId } },
  include: { report: { include: { events: { orderBy: { seq: 'asc' } } } } },
});
```

The close is inside that report; `CLOSE.details.reservationId` (Phase 3) closes
the loop in the other direction.

**Table 5's historical Orders**

```ts
prisma.auditReport.findMany({
  where: { venueId, tableNumbers: { has: '5' }, floor: 'first' },
  orderBy: { openedAt: 'desc' },
});
```

Snapshot query, not a relation — correct by design (§I). Prefer the per-event
`details.tableRefs` form (`"first/5"`) where cross-floor precision matters.

**One Sale → matching CLOSE**

```ts
prisma.auditEvent.findFirst({
  where: { venueId, type: { in: ['CLOSE', 'INTERNAL_CLOSE'] },
           details: { path: ['closureId'], equals: closureId } },
});
```

`closureId` is the join key. **Note:** there is no `Sale` row on Cloud to start
from — the caller must already hold the `closureId`, from `Order.closureId` or
from the POS.

---

## S. Implementation plan (not implemented)

Three phases; only these are necessary.

**Phase A — event ordering integrity** *(the only phase with a confirmed bug)*

- Replace the unstable `List.sort` in `AuditReport.fromMap` and
  `AuditReport.sortedEvents` with `mergeSort`, matching
  `appendOrderAuditEvents`.
- Add a POS-assigned per-report `sequence` to `AuditEvent`, serialize it, and
  have ingestion prefer it over the array index for `seq` (falling back to the
  index for older POS builds).
- Add `@@index([reportId, seq])`.
- Regression test: a report with >32 events sharing one timestamp keeps its
  creation event first through a save/load/re-push cycle.
- Class: `NO_MIGRATION` (Dart) + `ADDITIVE_SAFE` (index).

**Phase B — tenant, order-kind and index integrity**

- `AuditEvent.venueId` (nullable → backfill → required), with
  `@@index([venueId, type, eventTime])`.
- Venue-scope the `AuditReport` indexes.
- `AuditReport.orderKind` with the partial backfill described in §Q.
- Optionally, if Studio navigation is wanted: `AuditReport.orderId` +
  `order Order? @relation(onDelete: SetNull)`.
- Class: `ADDITIVE_SAFE` + deterministic `BACKFILL_REQUIRED` (orderKind partial).

**Phase C — generic entity timeline (Phase 4 prerequisite)**

- `AuditEventLog.entityType` / `entityId` + the composite index.
- POS writers set them; deterministic backfill for the existing Reservation
  rows.
- Build the **reader** — without one, `AuditEventLog` stays write-only whatever
  its schema.
- Class: `ADDITIVE_SAFE` + partial `BACKFILL_REQUIRED`.

Deliberately **not** phased in: converting ingestion to upsert-on-`(reportId, seq)`.
It is the right destination for immutability, but it needs a unique constraint
that current data may not satisfy, and it should follow Phase A by at least one
settled rollout.

---

## T. Files changed

- `docs/AUDIT_STORAGE_RELATIONS.md` (this report).

No Prisma schema, migration, Hive adapter, sync protocol, ingestion path,
historical row, or Phase 1/2/3 semantic was modified.
