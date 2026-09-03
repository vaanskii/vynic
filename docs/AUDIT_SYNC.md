# Audit report synchronization

**Step 6C.** Why a single order change used to re-upload a restaurant's entire
audit history, and what replaced it.

Companion documents: [SYNC_CONTRACT.md](SYNC_CONTRACT.md),
[MONEY_INTEGRITY.md](MONEY_INTEGRITY.md),
[EDGE_COMMAND_MIGRATION.md](EDGE_COMMAND_MIGRATION.md).

---

## What it did

```
[ManagerSync] Syncing 1091 / 1091 audit reports.
[ManagerSync] Sending payload with 1091 reports to server...
```

That line appeared after any ordinary operation. `_syncAuditReports()` read every
report the POS held and sent all of them with `fullSync: true`, every time, and
the audit box is written on every item added, quantity reduced, table cancelled
and report closed — each of which schedules a sync.

It was not a bug in a filter. There was no filter, because there was nothing to
filter *on*: the POS had no durable answer to "which of these does the server
already have". `fullSync` conflated two questions — *upload what changed* and
*delete what I no longer hold* — and answering the second required sending
everything, so the first never got an answer of its own.

Cost, at Vankisi's ~1091 reports: every audit change re-serialized and re-sent
the whole history, and the backend re-upserted 1091 rows and deleted and rewrote
every one of their events.

## What it does now

The POS keeps a durable record of what the backend acknowledged, in its own Hive
box (`audit_sync_state`), beside the audit data rather than inside it. An audit
report is the restaurant's record of what happened; cloud bookkeeping has no
business being a field on it.

```
local report content  ──hash──▶  revision
                                    │
                    revision ≠ acknowledged revision  ──▶  DIRTY
```

### A content revision, not a timestamp

A wall-clock cursor ("send everything changed since T") loses records. It moves
backwards, it cannot separate two edits in the same second, and a restored backup
carries old timestamps that a cursor reads as already-sent.

The revision is a SHA-256 of the report's own serialized map, canonicalized so
map iteration order can never make an unchanged report look dirty. It answers the
only question that matters — is what I hold different from what the server took —
without consulting a clock at all. It also works for the reports
`AuditRepository` *derives* from legacy event logs rather than storing, which
have nowhere to keep a counter.

### The acknowledgment rule

A revision becomes clean only when the backend says it persisted **that**
revision.

```
POS sends report R at revision N
backend persists N, echoes {reportId: R, revision: N}
POS records acknowledged[R] = N
```

The revision recorded is the one that was **sent**, never the report's content at
acknowledgment time. So:

```
R is at revision N, sent
R is edited to N+1 while N is in flight
ack for N arrives  →  acknowledged[R] = N
current hash is N+1 ≠ N  →  R is dirty  →  R is sent again
```

Marking it clean there is the one bug this whole mechanism exists to prevent: an
audit edit would disappear silently. An acknowledgment naming a revision other
than the one sent is refused outright, not applied.

### Batching and resumability

`auditSyncBatchSize = 100`. A report carries its whole event list, so the bound
that matters is serialized size rather than row count; 100 keeps a batch in the
same order of magnitude as an ordinary manager-data push.

Each batch's acknowledgments are written before the next is sent. A backend that
stops answering ends the pass, everything unacknowledged stays dirty, and the
next push resumes where it stopped rather than starting over.

### Reconciliation, separated

Removing reports the POS no longer holds is a different question and now has its
own answer: `knownReportIds`, a list of ids and no contents, sent once per process
after the upload backlog drains. That is what stopped every push carrying the
whole history.

Both that and the legacy `fullSync` refuse to empty a Venue. A POS reporting that
it holds zero reports is far more likely to be a store that failed to open than
an instruction to delete a restaurant's audit history.

---

## Upgrading an existing installation

On the first run after upgrading, nothing is acknowledged, so every report is
dirty and the whole history uploads once, in batches, checkpointing after each.

**That is deliberate, and it is the point.** Marking existing reports synced
without proof would assume the backend holds them; a bounded backfill reconciles
against what it actually has. So a terminal with 1091 reports sends them one
final time after the upgrade. What must not happen — and no longer does — is one
new order tomorrow resending all 1091 again.

The box is not included in backups. A restored install has no acknowledgments and
re-uploads what it holds, which is the safe direction. Nothing here is audit
authority: deleting the whole box costs one re-upload, not one record.

---

## Backend

`AuditReport.syncRevision` stores what was persisted. A report offered at a
revision the server already stores is acknowledged **without** rewriting its
events — which is what makes a redelivered batch cheap rather than merely
harmless.

Ownership never comes from the payload. Reports are keyed `(venueId, reportId)`
with `venueId` from the authenticated Device or legacy sync principal, so a
`reportId` belonging to another Venue addresses a different row rather than that
Venue's. Proved against real PostgreSQL, along with: a redelivered batch leaving
one logical history, and one Venue being unable to reconcile away another's
reports.

### Compatibility, both directions

- An **old POS** sending `fullSync` with everything is honoured exactly as
  before.
- A report offered **without a revision** is written rather than skipped:
  "unknown" must never mean "current", or an upgraded backend would silently stop
  ingesting from an un-upgraded terminal.
- An **upgraded POS** talking to an **older backend** gets a 2xx with no
  `acknowledged` list, and treats it as the acknowledgment it used to be, rather
  than resending forever.

---

## What it logs

```
[ManagerSync] Audit sync: dirty=3 sending=3 acked=3 remaining=0
[ManagerSync] Audit backfill: acked=250 remaining=841
```

Nothing when there is nothing to do. No payload contents.

---

## Scaling still open

This phase deliberately did not touch the rest of the snapshot. Tables, orders,
menu and staff are still sent in full on every push, and
`salesHistoryByDate` still carries the whole history. Those are real and are a
later sync-scaling phase; audit reports were addressed here because their growth
is unbounded in the number of orders a restaurant has ever taken, which made them
the one that got worse every day.
