# Closure + Payment + Audit Integrity Audit

Date: 2026-09-04
Scope: investigation and characterization only; no production behaviour changed.

## Executive conclusion

The durable Money Integrity close is financially idempotent for supported
fiscal cash, card, split, and advance combinations. The reported inconsistency
is real and universal: every successful shared close constructs
`AuditEventType.cancelTable`. The parent report is marked `CLOSED`, so local
revenue is not reversed, but the event itself and every legacy projection of it
say cancellation.

The audit also found two P0 reporting/integrity exposures: Manager per-day and
monthly history adds internal/non-fiscal sales to revenue, and Manager raw-Order
fallbacks can add open, restored, internal, or cancelled orders while using the
net balance rather than gross sale value. No live or historical database was
opened or modified.

## A. Closure-path inventory

| Terminal path | Exact production call chain | Result |
| --- | --- | --- |
| POS order-detail fiscal close | `order_detail_screen.dart::_finalizeTableClosure` -> `DatabaseService.closeTable` -> `CloseTableTransaction.run` | Sale, journal, closed Order, free table, completed genuine booking, locked `CLOSED` audit report |
| POS Takeaway-home fiscal close | `home_take_away_section.dart::_closeTakeAwayOrder` -> `DatabaseService.closeTable` -> `CloseTableTransaction.run` | Same close without a Reservation dependency |
| POS internal close | `order_detail_screen.dart::_finalizeNonFiscalClosure` -> `CloseTableTransaction.run` | Non-fiscal Sale and journal; currently records invented cash/current collection |
| POS order-detail cancellation | cancellation handler in `order_detail_screen.dart` -> typed `CANCEL_TABLE` report + synthetic cancelled/non-fiscal Sale -> status `cancelled` -> table release | Audited cancellation; package quantity audit omits `packageItems`; advance disposition is not modeled |
| POS Takeaway-home cancellation | `home_take_away_section.dart::_cancelTakeAwayOrder` -> `DatabaseService.updateOrderStatus` | Status-only cancellation and pseudo-table release; no Sale and no audit |
| Manager cancellation | mobile order detail/editor -> backend `MobileOrdersService.cancelOrder` -> `ORDER_STATUS_UPDATE` -> `PosCommandApplier.updateOrderStatus` -> repository status update | Cloud and POS status become cancelled and table frees; no typed cancellation audit and no linked-booking cancellation |
| Manager Takeaway hard delete | Manager Takeaway view -> backend `MobileOrdersService.deleteTakeawayOrder` -> `ORDER_CANCEL` -> `PosCommandApplier.cancelOrder` -> `deleteOrderAndCleanup` | Order is deleted, table freed, linked booking cancelled if present, typed audit report deleted, no durable cancellation event |
| Close-Day admin permanent delete | `admin_close_day_section.dart` -> `DatabaseService.deleteOrderAndCleanup` | Same destructive cleanup; no durable audit |
| Empty source after item transfer | `OrderItemTransfer.releaseEmptiedOrder` | Zero-value Order is marked `closed`, table frees, genuine booking completes; no Sale/journal/closureId and audit report stays open |
| Close Day | `DatabaseService.closeDay` -> `CloseDayTransaction.run` | Refuses while active orders remain; finalizes bookings, records operated date, advances business date, deletes closed Orders, frees table state; no Close Day audit and no atomic journal |
| Sale cancellation/void | `SalesRepository.cancelSaleRecord` | Sale retained but `isCancelled=true`; revenue/takings excluded; Order/table stay closed/free; append-only `SALE_CANCELLED` action |
| Restore/reopen | `SalesRepository.restoreClosedOrderFromSale` | Same-day physical-table Sale only; journal reversed, Sale `restoredToOrder`, Order/table reopened, advance returned; typed audit and linked booking are not reopened |
| Startup recovery | `ClosureRecoveryService.recoverPending` | No Sale: abandon journal and retain active Order. Sale exists: finish same closure, close Order/free table; misses typed close audit and linked booking completion |
| Generic status `paid` | `OrderRepository.updateOrderStatus` primitive | Frees table but creates no Sale/journal/audit; no active production caller found for settlement — unsafe/dead as a payment path |
| Bulk delete open Orders | `OrderRepository.deleteOpenOrdersForDate`, exposed by `DatabaseService` | No production caller found; repeats unaudited hard-delete cleanup |

`cancelled` is always an Order status, never a Table status. Table state is
derived separately from `isReserved`, `activeOrderId`, and `reservationId`.

## B. Payment-path inventory

`TablePaymentService` supports cash, bank card with provider, and split. Its
builders produce `cash`, `card-tbc`/`card-bog`, or both. The Order already holds
the balance after advance; `ClosureMoney.fromOrder` reconstructs gross as:

```text
gross = order.totalAmount + advanceApplied
gross = advanceApplied + collectedNow
```

`CloseTableTransaction` checks the second identity, adds `advance` to the Sale
breakdown, and writes the same gross/advance/now tuple to the journal and Sale.
It does **not** validate that the supplied tender-breakdown sum equals
`collectedNow`; `TableClosureHelper.describeBreakdownMismatch` exists but is not
enforced at the transaction boundary.

The supported UI builders supply correct fiscal tender maps. The internal caller
deliberately supplies `{cash: gross}` even though no collection occurred.

## C. Why successful close emits `CANCEL_TABLE`

The exact emitter is `CloseTableTransaction._finish`, step 6. It constructs a
single `AuditEvent` with:

```text
type = AuditEventType.cancelTable
itemName = ORDER
previousQty = 0
newQty = 0
note = "Order closed ..."
statusOverride = CLOSED
lockReport = true
```

The enum has no close/payment/internal/restore event. The close code reused the
only terminal-looking event instead of using a semantically neutral/custom
event or introducing a close event. All three shared callers inherit it: normal
order-detail payment, Takeaway-home payment, and internal close. Cash/card/split,
advance, Walk-In, Package, and genuine Reservation linkage do not alter the
emitter.

This is not currently a Sale calculation bug: the parent report is `CLOSED` and
`SalesRepository.countsAsRevenue` ignores audit type. It is nevertheless a P1
accountability defect because the event and legacy action projection assert the
opposite business action.

## D. Audit-event taxonomy

### Typed order-report events

| Event | Producers | Actual action | Assessment |
| --- | --- | --- | --- |
| `ADD_ITEM` | Order creation/item mutation audit | Item added | Correct |
| `REDUCE_QTY` | Item mutation/admin action | Quantity reduced | Correct |
| `DELETE_ITEM` | Item mutation/admin action | Item removed | Correct |
| `CANCEL_TABLE` | POS cancellation/admin `cancel_table` | Genuine cancellation | Correct there |
| `CANCEL_TABLE` | `CloseTableTransaction._finish` | Successful fiscal or internal close | Wrong |
| `CUSTOM` | Generic/legacy actions | Unclassified action | Semantically weak but reachable |

There are no typed report events for table/order close, payment, cash, card,
split, advance, internal close, restore/reopen, Sale void, Close Day, or
reservation activation/completion/cancellation.

### Append-only action events

The separate `MoneyAudit`/`AuditEventService` stream contains
`ORDER_CREATED`, `TAKEAWAY_ORDER_CREATED`, money adjustment actions,
`ADVANCE_RECORDED`, `SALE_CANCELLED`, `SALE_RESTORED_TO_ORDER`,
`CLOSURE_RECOVERED`, and several settings/date changes. Reservation admin
cancellation emits `reservation_cancelled`. There is no ordinary payment-close
or Close Day action. These actions do not repair the typed Order report.

The legacy audit projection maps every typed `cancelTable` event back to the
action string `cancel_table`, even when its parent report status is `CLOSED`.

## E. Cash correctness

For gross 100/cash 100, the shared fiscal close writes one revenue Sale with
gross 100, advance 0, collected-now 100, breakdown `{cash: 100}`, and the same
closureId as the completed journal. Order closes and a physical table frees.
X/Z gross and tender reconcile. Audit type is wrong (`CANCEL_TABLE`).

## F. Card correctness

For gross 100/card 100, the Sale and journal preserve the provider key
(`card-tbc` or `card-bog`) at 100 with no cash. Revenue and X/Z arithmetic are
correct. Audit type is wrong.

## G. Split correctness

For gross 100/cash 40/card 60, the Sale and journal preserve both amounts and
their sum is exactly gross. No duplication or drop was reproduced through the
supported UI contract. The transaction boundary would accept an inconsistent
tender map if another caller supplied one. Audit type is wrong.

## H. Advance combinations

The matrix reproduced advance 20 plus cash 80, card 80, and split cash 30/card
50. Each close writes:

```text
grossSaleAmount = 100
advanceApplied = 20
collectedNow = 80
paymentBreakdown = current tender entries + {advance: 20}
```

The advance receipt stays on its collection business date; the Sale recognizes
gross revenue on closure date. Same-day collected money is receipt plus current
tender, while a prior-day receipt remains on the prior day. Audit notes include
gross/advance/collected when advance is nonzero, but the event lacks structured
amounts and still uses `CANCEL_TABLE`.

## I. Non-fiscal/internal close

The Order closes, table frees, a closureId and completed journal exist, and one
Sale is written with `isFiscal=false`; local `countsAsRevenue`, gross daily total,
collected daily total, printed X/Z revenue, and current-day/all-time Manager
summary exclude it.

The source record is financially misleading: `_finalizeNonFiscalClosure` creates
an automatic cash selection for the balance, passes `collectedNow=gross`, and
writes `{cash: gross}`. Thus the internal Sale and journal claim cash collection
even though report filters later suppress it. Its typed audit is also
`CANCEL_TABLE`. Manager per-day/month history does not exclude it and counts its
gross as revenue/profit.

Restore is allowed only when its table is configured and date is current; the
same restore audit defects apply.

## J. Cancellation

The semantically correct POS-detail cancellation uses `CANCEL_TABLE`, marks the
report `CANCELLED` and locked, writes a non-revenue synthetic cancellation Sale,
sets Order status cancelled, frees tables, and cancels only a genuinely linked
booking. It records a reason in the event note. Its cancellation quantity uses
ordinary `items` only and can omit Package items. Advance refund/forfeit state is
not represented; the advance receipt remains unapplied while the synthetic Sale
says `advanceApplied`.

Three other production cancellation/removal paths are inconsistent:

- POS Takeaway shortcut: status/free only, no Sale and no audit.
- Manager status cancellation: status/free only; no audit and no genuine linked
  Reservation cancellation.
- Manager/Close-Day hard delete: removes the Order and its typed audit report;
  no durable cancellation event survives.

All excluded or absent cancellation Sales are excluded from local X/Z revenue.
Cloud receives cancellation status for Manager cancellation, but audit evidence
is absent.

## K. Restore/reopen

The money path is correct for a current-day Sale on a configured physical table:
the old journal is marked reversed, the old Sale is flagged `restoredToOrder`,
the Order becomes confirmed with closureId cleared, the table is occupied by the
same Order, the advance becomes available again, and revenue/takings exclude the
old Sale. Re-close creates a new closureId and a second Sale row, but exactly one
row counts as revenue.

The lifecycle trail is broken. Restore leaves the original typed report
`CLOSED` and locked and appends no restore event. Re-close then catches and
suppresses the locked-report exception, so no second closure event is added. A
genuine linked Reservation remains `completed`, and restored table reservation
identity is not reattached. Takeaway restore is unsupported because the restore
routine requires at least one configured physical table. If reconstruction is
needed, Package metadata is flattened into ordinary Sale items.

## L. Crash recovery/idempotency

The durable sequence is `started -> saleWritten -> completed`. A closureId is
written before the Sale and `saveSaleRecord` deduplicates by that closureId.

- Crash before Sale: recovery clears the attempted Order closureId, marks the
  journal completed/abandoned, leaves Order and table active, creates no Sale,
  and emits `CLOSURE_RECOVERED`.
- Crash after Sale: recovery finds the Sale by closureId, applies the advance
  receipt, closes the same Order, frees tables, and completes the same journal.
  It does not duplicate revenue.

Post-Sale recovery contradicts its own contract comment: it does not complete a
linked genuine Reservation and does not close/append the typed Order audit
report. Normal close also swallows any typed-audit append error and then marks
the journal completed. Therefore an audit failure is not retryable. Append-only
recovery events use UUIDs for Cloud idempotency, but local event persistence
errors are swallowed by `AuditEventService`.

## M. Walk-In / Takeaway / Package / Reservation-linked comparison

| Shape | Close | Cancel | Restore | Specific concern |
| --- | --- | --- | --- | --- |
| Walk-In = Order + Table | Shared close; table frees | POS detail correct; Manager status path lacks audit | Supported same day on configured table | Typed close event wrong |
| Takeaway = Order only | Shared fiscal close; no Reservation | Home shortcut lacks audit; Manager delete is destructive | Unsupported by physical-table gate | Typed close event wrong; no fake Reservation created |
| Package = Order + package fields | Gross Package price and combined Sale items preserved | POS cancellation audit quantity omits package items | Existing Order preserves package data; reconstructed Order would lose it | `finalTransaction.items` omits package items and its `total` is balance-due, not gross |
| Genuine Reservation-linked Order | Shared close completes booking | POS detail cancels booking; Manager status cancellation does not | Booking stays completed and table link is not restored | Recovery also leaves booking in progress |

`TableClosureHelper.buildFinalTransactionRecord` serializes only `order.items`,
not `packageItems`, while using the net `order.totalAmount`. The canonical Sale
items/gross fields are correct; the nested diagnostic transaction is incomplete.

## N. X/Z and Manager reporting

| Consumer | Revenue predicate/result | Defect |
| --- | --- | --- |
| POS derived daily gross | `countsAsRevenue` | Correct |
| Printed X | Revenue rows only; tender excludes applied advance and reconciles with advance | Correct |
| X waiter summaries | Excludes cancelled/non-fiscal, not restored | Restored Sale leaks |
| X sold-items view | Excludes cancelled only | Restored and internal items leak |
| X closed-tables view | Displays all rows | Advance receipts appear as fake closed tickets; restored row is not visually reversed |
| Printed/admin Z | Revenue rows only, internal/advance displayed separately | Correct |
| POS monthly | `countsAsRevenue` | Correct |
| Manager current-day snapshot | POS-derived gross and filtered counts | Correct when snapshot exists |
| Manager all-time snapshot | Skips cancelled/restored; separates internal/advance | Correct |
| Manager per-day history | Skips cancelled/restored/advance receipt but adds non-fiscal gross before classification | **P0: internal close counted as revenue/profit/order/items** |
| Manager monthly | Sums per-day history settings | Inherits the P0 leak |
| Manager today fallback | Sums raw non-cancelled Orders | Can include open/internal/restored and uses balance-due |
| Manager yesterday dashboard | Always sums raw yesterday Orders | Can include cancelled/open/internal/restored and uses balance-due |
| Manager report `byWaiter` | Raw Order aggregation even when headline uses summary | Can disagree and include non-revenue/non-terminal Orders |
| Manager daily fallback | Raw Order aggregation | Same classification and gross-vs-net defect |

Gross revenue truth remains distinct from money collected now in the POS Sale
model. The Manager raw Order mirror cannot reproduce that truth because it lacks
the reconciliation fields.

## O. Historical-data exposure

Historical typed reports created through the current shared close can already
contain successful closes recorded as `CANCEL_TABLE`.

Repair classification is **PARTIALLY SAFE** overall:

- High-confidence typed row: parent `AuditReport.status == CLOSED`, event note
  begins `Order closed`, and a matching Sale/Order closureId exists. This can be
  deterministically classified as a successful close.
- Genuine typed cancellation: parent status `CANCELLED`, usually cancellation
  reason, with a cancelled Order/synthetic cancelled Sale or no fiscal closure.
- Unsafe/needs review: detached legacy `cancel_table` rows, missing/corrupt
  parent status, absent Sale/Order after cleanup/Close Day, or conflicting
  timestamps. The event payload itself has no closureId or structured money.

A future backfill should update only the high-confidence typed cohort and emit a
review list for the rest. No historical row was changed in this audit.

## P. Full integrity matrix

| Flow | Order status | Sale? | Revenue? | Payment breakdown | Audit type(s) | Table result | Reservation result | X/Z | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Walk-In cash | closed | one gross Sale | yes | cash 100 | `CANCEL_TABLE` | free | none | included correctly | MISLEADING AUDIT ONLY |
| Walk-In card | closed | one gross Sale | yes | provider card 100 | `CANCEL_TABLE` | free | none | included correctly | MISLEADING AUDIT ONLY |
| Walk-In split | closed | one gross Sale | yes | cash 40/card 60 | `CANCEL_TABLE` | free | none | included correctly | MISLEADING AUDIT ONLY |
| Advance + cash | closed | gross 100 | yes | cash 80/advance 20 | `CANCEL_TABLE` | free | shape-dependent | gross/tender correct | MISLEADING AUDIT ONLY |
| Advance + card | closed | gross 100 | yes | card 80/advance 20 | `CANCEL_TABLE` | free | shape-dependent | gross/tender correct | MISLEADING AUDIT ONLY |
| Advance + split | closed | gross 100 | yes | cash 30/card 50/advance 20 | `CANCEL_TABLE` | free | shape-dependent | gross/tender correct | MISLEADING AUDIT ONLY |
| Takeaway cash | closed | one gross Sale | yes | cash 100 | `CANCEL_TABLE` | no physical table | none | included correctly | MISLEADING AUDIT ONLY |
| Takeaway card | closed | one gross Sale | yes | card 100 | `CANCEL_TABLE` | no physical table | none | included correctly | MISLEADING AUDIT ONLY |
| Takeaway split | closed | one gross Sale | yes | cash/card exact | `CANCEL_TABLE` | no physical table | none | included correctly | MISLEADING AUDIT ONLY |
| Takeaway advance combinations | core transaction supports them; UI support not proven | gross Sale if invoked | yes | advance + tender | `CANCEL_TABLE` | no physical table | none | arithmetic correct | UNCLEAR |
| Package fiscal | closed | gross/package items preserved | yes | tender exact | `CANCEL_TABLE` | free | none | headline correct | BUG |
| Package internal | closed | non-fiscal Sale | no locally | invented cash | `CANCEL_TABLE` | free | none | local excluded, Manager history leaks | BUG |
| Reservation-linked fiscal | closed | one gross Sale | yes | tender exact | `CANCEL_TABLE` | free | completed | local correct | MISLEADING AUDIT ONLY |
| Internal/non-fiscal | closed | one non-fiscal Sale | no locally | falsely cash/gross | `CANCEL_TABLE` | free | completed if linked | local excluded, Manager history includes | BUG |
| POS-detail cancel | cancelled | synthetic cancelled Sale | no | none/current 0 | `CANCEL_TABLE` | free | genuine linked cancelled | excluded | CORRECT, with advance/package caveats |
| POS Takeaway cancel | cancelled | no | no | none | none | no physical table | none | excluded | BUG |
| Manager status cancel | cancelled | no new Sale | no local Sale | unchanged | none | free | incorrectly unchanged if linked | Cloud status excluded | BUG |
| Manager/Close-Day hard delete | deleted | no new Sale | no | none | report deleted | free | genuine linked cancelled | absent | BUG |
| Emptied by transfer | closed, total 0 | no | no | none | item events only | free | completed if linked | no Sale | BUG |
| Sale void | Order stays closed | retained, cancelled | no | retained historical | `SALE_CANCELLED` action | free | unchanged | excluded correctly | CORRECT |
| Restore | confirmed | old Sale restored | no | retained historical | `SALE_RESTORED_TO_ORDER`; report remains closed | occupied | wrongly stays completed if linked | excluded correctly | BUG |
| Re-close after restore | closed | new Sale; old restored | exactly one | new tender exact | no new typed event | free | remains completed | revenue correct | BUG |
| Crash before Sale | active | no | no | journal intent only | `CLOSURE_RECOVERED` | remains occupied | unchanged | excluded | CORRECT |
| Crash after Sale | closed by recovery | same Sale | yes | preserved | recovery action only; typed report open/missing | free | wrongly in progress | revenue correct | BUG |
| Close Day | active Orders block; closed Orders later deleted | existing Sales retained | unchanged | unchanged | none | all free after success | completed/no-show finalization | prior date retained | BUG |
| Generic `paid` status | paid | no | no | none | none | free | unchanged | missing | DEAD/LEGACY PATH |
| Bulk open-Order delete | deleted | no | no | none | report deleted | free | genuine linked cancelled | absent | DEAD/LEGACY PATH |

## Q. Bugs ranked P0–P3

### P0 — money/revenue corruption

1. **Manager historical revenue includes internal Sales.** Root:
   `manager_sync_service.dart`, `salesHistoryByDate` builder, adds gross/order/
   item totals before using `isFiscal` only to label breakdown. Affects daily,
   monthly, profit, order count, closed tables, and top items. Historical
   settings may already be wrong. Backfill: regenerate affected per-day summary
   settings from POS Sale truth. Smallest fix: gate all revenue fields with
   `SalesRepository.countsAsRevenue` and keep internal totals separate.
2. **Manager raw-Order fallbacks are not revenue truth.** Root:
   `MobileDashboardService.getDashboard` yesterday/fallback calculations and
   `MobileReportsService.getSalesReport`/`getSalesDaily`/`byWaiter` queries.
   They include non-terminal/internal/restored or cancelled shapes depending on
   query and use net `Order.totalAmount`. Historical displayed values may be
   wrong; source Orders need not be mutated. Smallest fix: consume authoritative
   per-day summaries exclusively or mirror/query explicit closure fields.
3. **Close transaction does not enforce tender-map reconciliation.** Root:
   `CloseTableTransaction.run` validates `ClosureMoney` but not tender sum;
   helper validation is caller-only. Existing fiscal UI is correct, while the
   internal caller demonstrates that inconsistent semantic input is accepted.
   Historical internal Sale/journal payment maps are affected. Smallest fix:
   validate tender sum at the transaction boundary after defining the explicit
   zero-collection internal contract.

### P1 — audit/accountability wrong

1. Every successful shared close emits `CANCEL_TABLE`.
2. Internal close writes fake cash/current-collection metadata.
3. Normal close swallows typed-audit failure and completes the journal, making
   missing audit non-retryable.
4. Recovery never completes the typed closure report.
5. Restore/re-close leaves a locked report and loses restore/re-close events.
6. POS Takeaway and Manager status cancellations have no cancellation audit.
7. Manager/Close-Day hard deletes erase the typed audit report.
8. Close Day has no auditable terminal event/journal and is best-effort across
   multiple boxes despite an all-or-nothing comment.
9. Empty-by-transfer closes an Order but leaves its audit report open.
10. Typed close payload lacks businessDate, closureId, structured money,
    fiscal classification, service fee, discount, and adjustment.
11. Cloud Order sync omits closure/money reconciliation fields even though the
    schema has `Order.closureId`.

Historical backfill is needed for items 1/2 and possibly missing-audit cohorts;
missing events cannot always be reconstructed safely after Order cleanup.

### P2 — lifecycle/state wrong

1. Post-Sale recovery does not complete a linked genuine Reservation.
2. Restore does not reopen/relink the genuine Reservation.
3. Manager status cancellation does not cancel the genuine linked Reservation.
4. Takeaway restore is rejected by the physical-table requirement.
5. Package reconstruction after a missing Order loses package metadata.
6. Close Day can partially update boxes if a later step fails; there is no
   rollback or durable Close-Day journal.

### P3 — misleading logs/naming only

1. Legacy audit views translate successful-close `CANCEL_TABLE` to the literal
   action `cancel_table` without considering parent report status.
2. Manager dashboard comment says current summary includes non-fiscal revenue,
   but the current snapshot builder excludes it.
3. Project-state claims that all Manager summaries share the revenue predicate
   and that Cloud mirrors closure fields were stale; corrected by this audit.

No log matching `Freed table ... order cancelled` was found as a hard-coded
state claim. The backend free-table log prints the actual terminal Order status
and is descriptive, not the source of the lifecycle defect.

## R. Smallest safe fix sequence

1. Add explicit typed audit events for successful fiscal close, internal close,
   restore, and re-close; never reuse cancellation. Include structured closureId,
   businessDate, gross/advance/now, tender, fiscal flag, fees/discount/adjustment.
2. Make typed audit completion a journaled/idempotent close step and recovery
   responsibility; do not swallow it as “done.”
3. Define internal close as zero collection with no tender, then enforce tender
   reconciliation inside `CloseTableTransaction`.
4. Fix Manager per-day history filtering and regenerate its summary settings;
   then remove or harden raw-Order fallbacks.
5. Make restore reopen the typed audit lifecycle and genuine booking/table link;
   ensure re-close appends a distinct closure event.
6. Complete genuine booking and typed audit during post-Sale recovery.
7. Route every cancel/delete entry point through one audited semantic
   cancellation operation; preserve audit reports on hard delete.
8. Add Close Day audit/durable phase tracking and address empty-by-transfer.
9. Extend Cloud Order projection with proven closure reconciliation fields.
10. Run a high-confidence historical audit-event repair; quarantine ambiguous
    legacy rows for manual review.

## S. Tests added/run

Added `apps/operations/test/unit/closure_audit_integrity_test.dart` with:

- fiscal Walk-In cash/card/split;
- advance + cash/card/split;
- Takeaway cash/card/split;
- Package split;
- genuine Reservation-linked cash close;
- genuine cancellation semantics;
- internal close collection semantics;
- restore/re-close lifecycle;
- post-Sale crash recovery.

Every scenario inspects the relevant typed AuditEvent. The focused run compiles
and executes. One cancellation test passes. Four regression specifications fail
for the discovered production defects:

1. all 11 successful matrix closes emit `CANCEL_TABLE`;
2. internal close records collection/cash and cancellation;
3. restore retains a `CLOSED`, locked report, adds no restore event, and re-close
   adds no new closure event;
4. recovery leaves the genuine booking `IN_PROGRESS` and typed report open.

These are intentional red tests; expectations were not weakened to bless wrong
behaviour. The pre-existing Money Integrity suite already proves Sale
idempotency, advance-day accounting, void/restored revenue exclusion, and X/Z
reconciliation.

## T. Files changed

- `apps/operations/test/unit/closure_audit_integrity_test.dart` — focused
  regression specifications only.
- `docs/CLOSURE_PAYMENT_AUDIT_INTEGRITY.md` — this report.
- `docs/agent-state/VYNIC_PROJECT_STATE.md` — corrected stale represented facts
  about Manager filtering, Cloud closure fields, and recovery completeness.

No production implementation, schema, migration, generated file, sync schedule,
policy, backup, or database row was changed.

## U. Commit

Tests/docs changed, so the work is eligible for a commit under the task's
conditional instruction. Commit status is reported in the handoff.

## V. STOP

Stop here. Do not implement any production fix or historical repair as part of
this audit.
