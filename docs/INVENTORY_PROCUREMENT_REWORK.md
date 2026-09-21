# Inventory procurement rework

Implemented and validated locally. No production migration, deployment or push was performed.

## Investigation

The former receiving editor saved a DRAFT and dismissed itself. It did not post
stock. Posting was a second action inside a separate detail dialog. Menu goods
also needed a separately-created StockItem and recipe: a same-name Menu Item
never supplied the missing identity or consumption mapping. These are real
workflow gaps; the existing positive-quantity ledger posting is retained.
The former price input meant price per entered package, which is different from
price per piece. Financials added receipt totals to outflow regardless of payment.
Current cost divided all posted purchase values by all purchased quantities,
ignoring consumed stock.

## Design rationale and sources

[ERPNext Purchase Receipt](https://docs.frappe.io/erpnext/purchase-receipt)
distinguishes receiving goods into stock from supplier billing/payment, and
normalizes purchase quantities into stock units. Vynic keeps one receiving
payable rather than adding purchase orders, invoices, or a general ledger.

[ERPNext FIFO and Moving Average](https://docs.frappe.io/erpnext/fifo-and-moving-average)
describes a running quantity/value average. Vynic uses the existing movement
ledger, extended with frozen value deltas; it does not add FIFO or another
consumption engine. Backdated ERP posting may require forward revaluation;
Vynic's offline-first contract instead values in Cloud acceptance order and
keeps original effective/business dates as reporting labels.

Supplier is the counterparty. SupplierProduct is a many-to-many catalog link.
StockItem remains the physical identity, separate from MenuItem. Direct goods
create/reuse one piece-stock recipe atomically. Ingredients use kg and recipes;
bulk drinks use L, with keg only an item-specific purchase unit. Existing
multi-ingredient recipes cannot be silently overwritten by direct linking.

## Payments and history

POSTED Receiving is the frozen payable. SupplierPayment is append-only, allocated
to a receipt, with exact GEL, request identity, actor, payment date, business date,
method, notes/reference. Paid and remaining are derived. Actual outflows sum
supplier payments (including explicit negative reversals), other expenses,
payroll payments and obligation payments. Receiving itself is not cash outflow.

Cancellation is blocked while net payments remain or historical settlement is
unverified. An explicit reversal records an actual refund or payment correction;
it is never created by cancellation. Original payment rows survive.

Existing receipts migrate with paymentHistoryKnown=false. No payment is invented.
Their possible outstanding balance is separately labelled unverified, excluded
from confirmed debt. Managers can enter evidenced historical payments with their
actual dates, then explicitly confirm there are no unrecorded payments. New
receipts begin with known empty payment history.

## Quantity and value authority

PostgreSQL computes each new StockMovement value under its StockItem lock.
Receiving adds frozen line value. Consumption freezes the current remaining
value/quantity cost; draining the full balance removes its exact value. Restore
negates the original quantity and value exactly once. Item locks are acquired in
sorted order by multi-item writers. An out-of-stock issue uses the last known
cost and is marked provisional; absent cost remains null. Provisional history
is visible and is not advertised as realized COGS. Current recipe costs use the
current movement-derived average, not all-time receipt averages.

The additive migration reconstructs historical value fields in deterministic
createdAt/type/id order. Reconstructed values are labelled; existing quantity,
recipe and Sale snapshots are never rewritten. New values are ordered by a
durable valuation sequence. Historical physical order cannot be recovered from
equal timestamps, so reconstructed values are not original close-time evidence.

## UX gate

Vynic is a working restaurant operations app. Managers start at a supplier,
choose supplied goods, enter today's quantity/value, post, and optionally record
payment. Supplier detail exposes goods, recent receipts, debt and payments.
The existing Flutter Manager theme/responsive system is retained. Georgian
restaurant vocabulary dominates; internal IDs, StockMovement and BOM do not.
Primary mobile actions are add goods, receive, and record payment. Failures keep
entered values and offer retry; stock confirmation follows successful posting.
Phone screens use vertical forms/list details rather than squeezed tables.
Balances remain available for inspection and correction; POS stays read-only.


## Current model and API

- Supplier still requires only name. Optional contact/tax/address fields are retained.
- `POST /mobile/inventory/suppliers/:id/items` atomically creates or reuses stock,
  packaging, supplier link and direct recipe. Existing counted bottle mappings
  remain valid. A Manager may explicitly reuse an existing counted StockItem;
  display-name matching never joins identities. Direct Menu variants are explicit.
- Supplier detail exposes catalog, recent receipts and settlement totals. Stock
  detail exposes independent dated purchase lines, current cost/value, and the
  existing reverse recipe usage. Recipe setup retains inline ingredient creation.
- Receiving accepts either entered-unit price, base-unit price, or exact lineTotal.
  The Manager defaults to base-unit price and shows converted quantity and cost.
  Editing a draft loaded from history starts from its exact line value, avoiding
  regeneration from a rounded unit price. Optional due date belongs to the receipt.
- `GET /mobile/inventory/payables` supports a supplier filter. Payments, reversals
  and explicit historical verification are receipt subresources. All routes use
  the existing Staff authentication, role and Manager feature guards.
- New goods and receipt creation use stable client request IDs. Payments use a
  Venue-unique request ID and compare retry contents; changed reuse is a conflict.
  Cancellation, post and restore retain the existing movement uniqueness rules.
- Receipt value is Decimal(18,2); frozen movement unit cost/value are Decimal(30,12).
  Quantity remains Decimal(21,6). PostgreSQL numeric and local Decimal/BigInt
  arithmetic perform calculations. Wire values remain decimal text.
- Audits include SUPPLIER_ITEM_LINKED/UNLINKED, SUPPLIER_PAYMENT_RECORDED,
  SUPPLIER_PAYMENT_REVERSED and SUPPLIER_SETTLEMENT_VERIFIED. Receipt and recipe
  audits remain; derived balances do not write audits.

## Financial and Close Day semantics

Purchases are posted receipt values. Supplier payments are signed actual
cash/bank payments on their own payment/business dates. Confirmed debt and
unverified historical balances are separate. Financials outflow equals supplier
payments + other expenses + payroll/legacy salary payments + obligation payments.
No receipt is duplicated as an Expense. POS Admin's existing read-only daily
procurement excerpt includes purchases, supplier payments and the remaining
balance of that business day's receipts. Close Day neither settles nor deletes
procurement. No local payment editor or new checkout dependency was added.

## Validation evidence

- All 33 migrations applied from empty on disposable PostgreSQL 17, localhost
  port 55439. Final database: `manager_phase1_procurement_vynic_step47_test`.
- Prisma validate passed; migrate diff against the model returned an empty migration.
- A second disposable pre-migration copy preserved an existing receipt and
  movements +10/-5/+5 kg, reconstructing +100/-50/+50 GEL. Every value was labelled
  RECONSTRUCTED, the receipt stayed 100 GEL, settlement remained unverified, and
  no SupplierPayment was fabricated.
- Full backend: 62 suites, 657 passing tests, one pre-existing optional retained
  POS Sale snapshot fixture skipped. Final focused inventory rerun: 99 tests
  across 10 suites passed. TypeScript and Nest builds passed.
- Procurement end-to-end proof covers Borjomi and Bakuriani independently,
  packs, ingredient totals, khinkali consumption, changing prices, the 12 GEL
  average example, kegs/pours, exact restore/reclose, payment retries, partial/paid
  states, cancellation/reversal, historical verification, tenant isolation and
  separate purchase/payment summaries. Existing multi-ingredient recipe and
  POS close-time snapshot/restore/retry regressions also pass.
- Flutter: 78 targeted Manager/Inventory/Receiving/Recipe/consumption and POS
  projection tests passed; analyzer reports no issues. Ten of those tests cover
  new workflows and exact previews at 360, 768 and 1280 pixels. Georgian-font
  screenshots were captured and inspected; payment spacing was corrected after
  visual review. Existing POS inspection remains read-only.

## Migrations and rollout

1. Preserve the separately committed SaaS Phase 1 (`d9168b6`). Its rollout still
   follows `MANAGER_SAAS_PHASE1.md`; no auth/realtime changes belong to this rework.
2. Stop Cloud inventory writers during migration. Back up the target database
   using the deployment procedure; this task accessed disposable databases only.
3. Apply `20260916120000_inventory_procurement` (payment history and value writer)
   and `20260916123000_procurement_request_identity` (retry identities). Generate
   Prisma and deploy the backend before the new Manager. The value trigger is
   required, not an optional schema decoration. Historical reconstruction is a
   one-time, potentially long migration and should be timed on a staging copy.
4. Deploy Manager UI. Supplier-first setup and explicit posting are immediately
   available. Confirmed historic payments must be entered with their actual
   dates before a Manager verifies an old receipt's settlement.
5. Deploy POS when convenient for enriched read-only inspection. Existing catalog
   v5 fields are additive; older POS quantity snapshots/checkout continue working.
6. Rollback must retain migrations and financial rows. Do not run an older
   Financials backend after recording supplier payments: it has wrong outflow
   semantics. Prefer a forward fix; reverting a client alone does not erase history.

## Remaining boundaries

- No live `vankisi_database` access, hosted deployment, supplier bank calls or
  automatic payments. No FIFO, tax/GL accounting, purchase orders, waybill import,
  stocktake, waste or sub-recipes.
- Payment reversals are full, explicit corrections/refunds; partial refunds,
  supplier credits/advances and cross-document payment allocation are outside
  this smallest model. One payment may be split into explicit receipt allocations.
- Packaging remains item-specific. Conflicting same-label packaging for another
  supplier is rejected rather than silently changing other suppliers' ratios.
- Old payments have no inferred dates/amounts. Unknown settlement needs review.
- Provisional negative/unknown stock costs remain visibly provisional. There is
  no fabricated COGS recovery or automatic retrospective repricing. Cloud issue
  cost is not a guarantee of the price known at the earlier offline checkout.
- Existing internal-close consumption exclusion and unmapped-line behavior are
  unchanged. This is a foundation for later realized COGS, not a profitability GL.
