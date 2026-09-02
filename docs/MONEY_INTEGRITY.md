# Money Integrity

**Status:** Phase 1A and 1B implemented
**Scope of this document:** the mutations that can move a number a restaurant
reports, what now constrains them, and what the next phases still owe.

Related: [SYNC_CONTRACT.md](./SYNC_CONTRACT.md),
[DEVELOPER_ACCESS.md](./DEVELOPER_ACCESS.md),
[PRODUCT_ENTITLEMENTS.md](./PRODUCT_ENTITLEMENTS.md),
[VENUE_POLICY_PLAN.md](./VENUE_POLICY_PLAN.md),
[POS_ENROLLMENT_ANALYSIS.md](./POS_ENROLLMENT_ANALYSIS.md)

---

## 1. The problem this phase addressed

Vynic could already record money accurately. What it could not do was explain a
figure after the fact. `AuditEventService` — an append-only local queue that
batches to Cloud and survives being offline — existed from the first release
with a comment saying "every action in the app should call this", and had four
callers, none of them on a money path.

The consequences were specific:

- a sale from any past date could be removed from every revenue figure behind a
  single yes/no dialog, with no actor, no reason and no record;
- the business date could be moved onto any day, re-attributing everything
  recorded afterwards, with no record;
- discounts, manual bill adjustments and per-order service-fee changes left
  nothing behind;
- `manualAdjustmentAmount` — a signed operator override of a bill total — was
  not in the POS → Cloud contract, so the Cloud's `totalAmount` could not be
  reconciled against the Cloud's own item lines;
- the POS sent `expenses: []` on every sync while separately sending a derived
  `profit`, so the Cloud's profit figure was unverifiable;
- the legacy LAN ingest server accepted every caller when the terminal held no
  connection key.

Phase 1A does not redesign the close/payment path. It makes the existing
mutations attributable and the existing Cloud figures reconcilable.

---

## 2. What is audited now

All of these write through `MoneyAudit`
(`apps/operations/lib/core/services/audit/money_audit.dart`), which is a thin
layer over the existing `AuditEventService` — one audit system, not two. Each
helper is a no-op when nothing actually changed, so reopening a dialog or
re-saving a form does not assert a change that never happened.

| Action | Written from | Carries |
| --- | --- | --- |
| `ORDER_DISCOUNT_CHANGED` | POS order detail | actor, order, previous/new discount, previous/new total |
| `ORDER_MANUAL_ADJUSTMENT_CHANGED` | POS order detail | actor, order, previous/new adjustment, previous/new total |
| `ORDER_SERVICE_FEE_CHANGED` | POS order detail, POS ingest (Manager app) | actor, order, previous/new included, previous/new percent, previous/new total |
| `SALE_CANCELLED` | `SalesRepository.cancelSaleRecord` | actor, order, business date, amount, reason, historical flag |
| `SALE_RESTORED_TO_ORDER` | `SalesRepository.restoreClosedOrderFromSale` | actor, order, business date, amount |
| `BUSINESS_DATE_CHANGED` | `BusinessDayRepository.setCurrentDate` | actor, from, to, reason, backdated flag |
| `RECEIPT_SERVICE_FEE_POLICY_CHANGED` | POS admin settings | actor, previous/new visibility of both receipt lines |
| `REPORT_COST_ASSUMPTION_CHANGED` | POS admin reports | actor, field, scope (`default` or `YYYY-MM`), previous/new value |

Manager-app service-fee changes are audited on the POS rather than on the
phone, because the POS is where the change becomes a fact: the Manager app
reaches the order through `PosIngestServer`, and the actor is the name the
mobile client identified itself with.

Order-creation defaults are deliberately **not** audited — the venue service-fee
default applied to a new order, a take-away order created with the fee off, a
package order's fee rule. Those are the system choosing an initial value, not
an operator changing a recorded one, and logging them would bury the events
that matter.

---

## 3. Sale cancellation

`SalesRepository.cancelSaleRecord` now takes a named actor and a non-empty
reason, and returns `SaleCancellationOutcome` rather than a bare boolean so the
UI can say which rule refused it.

- The record is **never** deleted or rewritten. `isCancelled` is set and
  `cancelledBy` / `cancellationReason` are added; the original amounts, items
  and payment breakdown stay exactly as they were. Existing history remains
  readable, and every reader that already filtered on `isCancelled` is
  unaffected.
- Ordinary Manager use may void **only the current business day**. The button
  is not offered for an earlier day rather than being offered and then refused.
- Reaching into a closed period requires `DeveloperScope.salesRepair`, and the
  audit event is flagged `historical: true`.

No refund system is implied or built here. A void removes a sale from revenue;
it does not model money moving back to a customer. That belongs to a later
phase.

### Storage change

The Hive `sales` box holds plain maps, so the two new keys need no migration —
absent keys read as null, exactly as `restoredAt`/`restoredBy` already did. The
typed `SaleRecord` schema gained matching nullable fields (27, 28) so its
lossless round trip with the legacy map shape still holds.

---

## 4. Business-date control

`BusinessDayRepository.setCurrentDate` takes an actor and a reason and returns
`BusinessDateChangeOutcome`.

- Selecting the date already being operated is a no-op and records nothing.
- Any real move requires a reason.
- Moving **backwards** — onto a day the restaurant has already closed and
  reported — requires `DeveloperScope.backdate`.

Close-day does not come through this path: `CloseDayTransaction` advances
`currentDate` directly as part of its own transaction, and is unchanged.

Both new scopes (`backdate`, `salesRepair`) are in `DeveloperScope.all` and in
`DeveloperScope.destructive`, so a narrow support token can omit them and the
developer panel warns about them like the other data-affecting tools.

---

## 5. Cloud reconciliation

### Orders

`OrderSync.manualAdjustmentAmount` was added to the POS → Cloud contract and
`Order.manualAdjustmentAmount` to the schema (`Float @default(0)`). The
evolution is additive: a POS build that predates the field omits it, and the
Cloud reads that as 0 — which is what those builds meant.

With it, the Cloud can now check its own arithmetic:

```text
items × (1 + serviceFeePercent/100) − discountAmount + manualAdjustmentAmount
  == totalAmount
```

### Expenses

The POS now sends its real expense records instead of `expenses: []`.

Expense identity is owned by the POS: `saveExpenseRecord` has always written a
uuid onto each record. `SalesRepository.ensureExpenseIdentities()` runs once at
startup and backfills one onto anything restored from an older backup without
one, so identity is universal before the first sync.

`BusinessDaySyncService.recordExpenses` upserts on
`@@unique([venueId, posExpenseId])`. Re-sending the whole snapshot — which is
what every full sync does — leaves one row per expense. A record arriving
without an id can only come from a POS build that predates identity; it is
inserted exactly as before, because there is no key to deduplicate on and
guessing one from the content would silently merge two genuinely separate
expenses. The unique index sits on a nullable column, so PostgreSQL treats
those NULLs as distinct and a venue can hold any number of legacy rows.

**Still POS-computed, now verifiable:** `salesSummary.totalExpenses` and
`profit` continue to be sent as the POS calculated them, because the POS's
X-report is what the restaurant treats as authoritative. The difference is that
the Cloud now holds the records those figures are supposed to come from, so the
claim can be checked. Deriving the Cloud's figures from the records instead of
trusting the POS's is a deliberate non-goal of this phase.

---

## 6. Legacy POS ingest fails closed

`PosIngestServer` returned `true` from its authorization check when the
terminal held no connection key. The intent was convenience for an
unprovisioned install; the effect was that a POS which had lost its key
accepted every caller on the LAN, on eighteen routes that create orders, delete
users and print.

Missing configuration is now a refusal, not an exemption. `start()` also
refuses to bind without a key, since a listener without one could only ever
return 403. `PosIngestServer.isRequestAuthorized` is a pure function so the
closed-by-default property is testable without a socket.

The legacy transport itself is untouched — retiring it is Step 6C
([CLOUD_EDGE_TRANSPORT.md](./CLOUD_EDGE_TRANSPORT.md)).

---

## 7. Report identity

`MonthlyReportService` had the first customer's restaurant name and
identification code as constants, so any second venue's "official" export would
have carried that restaurant's identity.

Both now resolve from the venue's own settings: `venueName` (which already
existed) and the new `venueLegalId`. A field the venue has not filled in prints
`არ არის კონფიგურირებული` — the missing configuration is stated, not
substituted with a plausible-looking placeholder, because a report is read as a
statement about a specific business and an invented value makes a false one.

`DatabaseService.adoptLegacyVenueHeader()` backfills the existing
identification code for terminals that predate the setting, using the same
mechanism that already preserved the venue's name, address, phone and logo. It
runs only for non-fresh installs; a new terminal inherits nothing.

---

## 8. Manual monthly sales: removed

`monthlyReportManualSalesByMonth` let an operator type an amount that was added
to a month's reported revenue and to its cash total. The report generator then
converted that amount into synthetic transaction rows — seeded-random chunks
with order ids continuing the real sequence, spread across days, attributed to
cash, with round numbers nudged off — and merged them into the transaction
detail of the Excel and PDF exports beside the real sales.

The setting, its UI, its persistence, its contribution to every report total,
and the row generator are gone. Hive migration **v5** deletes the stored key so
a future reader cannot resurrect the figure.

Nothing replaces it in this phase. If a legitimate outside-POS revenue
adjustment is needed — cash taken at an event, catering billed separately — it
will be designed as an explicit audited domain record with an actor, a required
justification and its own labelled line in the report, so `calculatedSales`,
`adjustments` and `totalSales` are three separate figures rather than one.

The per-month lease and staff-cost overrides remain, because they are stated
assumptions rather than claimed transactions — and they are now audited
(`REPORT_COST_ASSUMPTION_CHANGED`).

---

## 9. Deferred: the Venue Policy phase

The owner's direction is that Vankisi-specific and advanced operational
capabilities should eventually be controlled centrally from the Vynic Platform
Admin, not exposed as switches inside the POS. **That system is not built
here**, and nothing in this phase branches on venue identity.

What follows is the inventory the next phase has to migrate. Each row is a
capability that is currently either always-on or a local POS setting, and that
should become a Venue-scoped policy resolved from Cloud with a local cache.

### 9.1 Capabilities to bring under central policy

| Capability | Where it lives today | Notes for migration |
| --- | --- | --- |
| Internal / non-fiscal table close | `CloseTableTransaction.nonFiscal`, offered unconditionally in the POS close flow; sale written with `isFiscal: false` and `paymentMethod: 'non-fiscal'` | Always available today. Should become a Venue policy, default off, with enumerated approver-attributed closure reasons rather than one unnamed bucket. |
| Receipt service-fee line (customer receipt) | `receiptShowServiceFeeLine` in the POS settings box; read by `PrinterService._shouldShowServiceFeeLine` and `ReceiptPdfGenerator` | Local switch. Change is now audited; the policy itself should move to the Venue, and the default for a new Venue should be *show*. |
| Receipt service-fee line (closing check) | `closeReceiptShowServiceFeeLine`, same path via `_shouldShowCloseReceiptServiceFeeLine` | Same. Default today is hidden, which is how the closing check has always printed. |
| Per-order service-fee percentage override | `Order.customServiceFeePercentage`, set from the service-fee dialog on POS and Manager | Whether an operator may override the venue percentage at all should be policy. |
| Manual bill adjustment (`manualAdjustmentAmount`) | `Order.setManualAdjustment`, gated only by `PosPermission.applyDiscount` | Should be a Venue policy on top of the permission, with a bound on the adjustable amount. |
| Historical sale void | `SalesRepository.cancelSaleRecord(allowHistorical:)`, gated on `DeveloperScope.salesRepair` | Support-scoped today, which is the right shape; the Venue Policy phase should decide whether it is ever a venue-grantable capability. |
| Business-date backdating | `BusinessDayRepository.setCurrentDate(allowBackdate:)`, gated on `DeveloperScope.backdate` | Same. |
| Monthly report cost assumptions | `monthlyReportLeaseCost`, `monthlyReportStaffDailyCost`, `monthlyReportFoodProfitRatio`, plus the per-month override maps | Whether the "official" report may present operator-entered cost at all is a product decision, not a terminal setting. |
| Venue legal identity on reports | `venueLegalId` (new), `venueName` | Should be Cloud-owned Venue configuration with a local cache, like the rest of administrative configuration. |

### 9.2 Two rules the policy model must keep

1. **No policy may switch off an audit record.** A capability can be disabled;
   its use can never be made invisible.
2. **No policy may change what a report asserts.** A policy may change what a
   document *shows*; it may not make the document claim something that did not
   happen.

### 9.3 Where the policy should be resolved

The entitlement resolver (`VenueEntitlementsService.effectiveFeatures`) answers
"may this Venue use this product surface". Operational policy is a different
question — "may this Venue's staff do this thing" — and should not be
overloaded onto Feature keys. Expect a separate Venue policy record with the
same Cloud-authority → POS-local-cache shape described in
`docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` §3.

---

## 10. Remaining blockers before Atomic Close

Phase 1A deliberately stopped short of the close/payment path. What Atomic
Close still has to solve:

- **`CloseTableTransaction` is not atomic.** `withPayment` and `nonFiscal` are
  multi-step best-effort sequences — save order, free tables, complete
  reservation, append audit inside a try/catch that only logs. A failure
  part-way leaves the floor and the sales history disagreeing.
- **`Order.closureId` and `SaleRecord.closureId` are still schema-only.**
  Nothing writes them, so a retried close has no idempotency key.
- **`SaleRecord` is still schema-only.** The sales box holds untyped maps;
  every reader re-implements its own tolerance for missing keys.
- **`dailySalesTotal` is an incrementally maintained scalar.** It is
  recomputed on some paths and incremented on others, so it can drift from the
  records it summarizes.
- **Restore-to-table has no closure semantics.**
  `restoreClosedOrderFromSale` mutates the sale in place and re-opens the
  order; with a closure id it would instead be a reversal record.
- **Advance/deposit records** (`paymentMethod == 'advance'`) sit outside the
  close flow and are excluded from restore by a string comparison.

---

# Phase 1B — Atomic close, advances, report reconciliation

## 11. What closing a table used to do

Three call sites each wrote their own closure by hand: dine-in
(`_finalizeTableClosure`), internal (`_finalizeNonFiscalClosure`) and take-away
(`_closeTakeAwayOrder`). Each did roughly:

```text
close the order   →   write a sale   →   free the tables
→ complete the reservation → append audit → recompute the daily total
```

with no shared identity and no record that a closure had been attempted.
Consequences, all reproduced in tests before they were fixed:

- **A retry wrote a second sale.** Nothing keyed the write, so a second tap or
  a repeat after a failed step doubled the revenue.
- **A crash left an untraceable half-close.** `Order.closureId` existed in the
  schema but nothing wrote it, so a process killed between the order save and
  the sale write left a closed order with no sale — money simply gone — and no
  way to tell that from an order nobody had closed.
- **`dailySalesTotal` had two authors.** `saveSaleRecord` incremented it and
  `refreshDailySalesTotalForDate` recomputed it. Whichever ran last won.

## 12. What an advance used to do

The POS had no advance concept. The order-actions button labelled **ავანსი**
wrote `Order.discountAmount`, and `recalculateTotal` subtracted it, so a 900
order with a 50 deposit had `totalAmount == 850`.

At close, `_finalizeTableClosure` read the advance back out of
`discountAmount` and wrote **two** records:

| Record | Amount | `isFiscal` | Dated |
| --- | --- | --- | --- |
| the sale | **850** | true | closing day |
| an `advance` pseudo-sale | 50 | false | closing day |

So:

- The 900 the guest consumed existed nowhere. Revenue was understated by every
  deposit ever taken.
- Nothing was recorded when the money was actually handed over. A deposit taken
  on Monday first appeared in the records on Friday, dated Friday.
- The take-away path did none of this at all: it wrote `discountAmount` onto
  the sale and no advance record, so the same deposit behaved differently
  depending on which screen closed the order.

## 13. The accounting invariants

```text
gross              what the guest consumed — the sale
advanceApplied     money taken earlier, now spent against this order
amountDueNow       gross − advanceApplied
collectedNow       what the tender came to
```

```text
gross == advanceApplied + amountDueNow          always
collectedNow == amountDueNow                    for a closure allowed to complete
```

`ClosureMoney` (`lib/core/models/closure_money.dart`) is that split, and
`CloseTableTransaction` refuses to write anything when it does not hold.
Discounts, manual adjustments and the service-fee rule are already folded into
gross by `recalculateTotal`; the class only separates the advance from the
balance.

**A deposit changes which day money was collected on. It never changes what
the sale was worth.**

## 14. One closure, once

`CloseTableTransaction.run` replaces `withPayment`/`nonFiscal`, and all three
call sites go through it. Closure identity lives on `Order.closureId` and on
the sale the closure writes.

The **closure journal** (`closureJournal` box, plain maps) records the intent —
order, kind, and the full money split — before the first write, and the phase
after each one:

```text
started  →  saleWritten  →  completed
```

Hive has no cross-box transaction and this does not pretend otherwise. What it
gives instead is that an interrupted closure is a *known state*. The write
order is deliberate: **the sale is written first**, because a recorded sale
with an order still open is recoverable, while a freed table with no sale is
money that vanished.

Idempotency has two independent guards:

1. `saveSaleRecord` refuses to write a second record for a `closureId` that
   already has one.
2. `run` answers `alreadyClosed` from the journal when the order already has a
   live completed closure — from the journal rather than from the order's
   status, because the status is set partway through.

## 15. Recovery

`ClosureRecoveryService.recoverPending()` runs at startup, after migrations.
For each unfinished journal entry it asks the **sales box**, not the journal
phase, whether the money was recorded — the phase write is the thing a crash is
most likely to have lost.

| Sale exists? | What recovery does |
| --- | --- |
| yes | Finishes the bookkeeping: order closed, tables freed, receipt marked applied, journal completed. Never writes a second sale. |
| no | Abandons the attempt. The order stays open and its table stays occupied, which is correct for an order nobody settled. The entry is marked `abandonedAt` so it stops speaking for that order and the staff can close the table normally. |

Every recovery writes a `CLOSURE_RECOVERED` audit event.

## 16. Advances now

- **When the money is taken**, an **advance receipt** is written into the sales
  box, dated the business day it was collected, `recordType: advance_receipt`.
  Editing the amount rewrites the same receipt; zeroing it deletes it.
- **The order** carries `advanceAmount`, `advanceCollectedOn` and
  `advanceReceiptId` (Hive fields 23–25). Migration **v6** moved every stored
  advance out of `discountAmount`; totals are unchanged because
  `recalculateTotal` subtracts both.
- **At close**, one sale is written, worth **gross**. Its payment breakdown is
  the tender plus an `advance` line, so the breakdown sums to gross. The
  receipt is stamped `appliedToClosureId`.
- **The payment dialog** shows all three figures — order total, advance
  deducted, remaining to collect — so the cashier can see the order was for
  more before the money is booked.

Scenario B, tested:

| | Day 1 | Day 5 |
| --- | --- | --- |
| gross sales | 0 | **900** |
| collected | **50** | **850** |

The 900 is collected exactly once across the two days.

## 17. `dailySalesTotal` has one author

The increment in `saveSaleRecord` is gone.
`BusinessDayRepository.refreshDailySalesTotalForDate` derives the figure from
the records every time, through `SalesRepository.countsAsRevenue` — the single
predicate every revenue figure in the app now shares.

Two derived figures are exposed and used by the reports:

- `grossSalesTotalForDate` — the value of the day's sales.
- `collectedTotalForDate` — money that changed hands: the day's tenders plus
  advances taken today, and deliberately **not** an advance applied to a sale
  closed today.

## 18. Why the Z figure read high — root cause

**It was not the internal close.** Two report queries counted records the
headline total excluded:

| Surface | Filter before | What leaked in |
| --- | --- | --- |
| X report payment split | *none at all* | voided sales, restored sales, internal closures |
| Z report | `isFiscal` only | **voided sales, restored sales** |
| Monthly "official" report | `isCancelled` only | **internal closures, restored sales** |
| Manager all-time summary | `isCancelled`/`restored` only | **internal closures added to revenue** |

A voided sale keeps `isFiscal: true` and gains `isCancelled: true`. The Z
report's `_isFiscalSale` predicate let it straight through into the payment
split and the order count, while `getDailySalesTotal` excluded it. Every void
therefore pushed the Z split above the total printed above it. Restored sales
did the same.

All four now use `countsAsRevenue`, and the applied advance is excluded from
tender lines. Both reports print a control line:

```text
ნაღდი + ბარათი + სხვა + ავანსი = გაყიდვები
```

### Reconciliation table

| Line | Source | In gross sales? | In collected? |
| --- | --- | --- | --- |
| Gross sales | `countsAsRevenue` × `grossSaleAmount` | — | — |
| Fiscal/normal sales | `recordType=sale`, `isFiscal=true` | yes | tender only |
| Internal/non-fiscal closures | `isFiscal=false` | **no** | **no** |
| Advances received | `recordType=advance_receipt` | **no** | yes, on the collection day |
| Advances applied | `advanceApplied` on a sale | yes (part of gross) | **no** |
| Cash / card / other collected | tender keys of the breakdown | yes | yes |
| Voids | `isCancelled=true` | **no** | **no** |
| Restored sales | `restoredToOrder=true` | **no** | **no** |

## 19. Internal (non-fiscal) closure

Same closure identity, same journal, same recovery — it is kept out of revenue
by `isFiscal: false`, not by taking a different code path. Tested: it books one
sale, cannot double, does not move gross sales, and no summary path lets it
back into revenue.

## 20. Restore and re-close

`restoreClosedOrderFromSale` now:

- marks the closure `reversedAt` in the journal, so it stops being the order's
  live closure and a re-close is a **new** closure with its own id;
- clears `Order.closureId`;
- puts the advance back on the reopened order and un-applies its receipt.

Tested: restore then re-close leaves two records, one of which counts, gross
900 and collected 900 — not 1800.

Full refunds are still out of scope. A void removes a sale from revenue; it
does not model money going back to a customer.

## 21. Data and migration impact (1B)

| Change | Kind | Compatibility |
| --- | --- | --- |
| `Order.advanceAmount` / `advanceCollectedOn` / `advanceReceiptId` (23–25) | additive Hive fields | absent reads as 0/null |
| `SaleRecord.recordType` / `grossSaleAmount` / `advanceApplied` / `collectedNow` / `appliedToClosureId` / `advanceReceiptId` (29–34) | additive Hive fields | absent `recordType` reads as `sale`; absent gross falls back to `totalAmount`, which is what old records meant |
| `closureJournal` box | new, plain maps | no adapter, no migration |
| Hive **v6** | data migration | moves `discountAmount` → `advanceAmount`; totals unchanged; idempotent |
| POS → Cloud | **no contract change** | the sale's `totalAmount` is now gross, and the `advance` / `advance-received` keys ride in the existing `paymentBreakdown` maps |

Both `.g.dart` adapters were hand-patched rather than regenerated, per the
known build_runner behaviour with this repository's checked-in adapters.
