# Inventory Step 4.5 — catalog, daily receiving and current menu cost

## Implemented boundary

Cloud owns inventory administration. POS operation, the StockMovement ledger,
Receiving posting/cancellation, recipe definitions and Sale consumption retain
one authority each. This step adds catalog organization and a current procurement
cost read model. It creates no sale valuation, profit, waste or stocktake ledger.

## Catalog and suppliers

- `StockItem.classification`: `FOOD` / `BEVERAGE`, stored as a PostgreSQL enum,
  carried by the catalog and preserved in Hive and backups. Existing rows and
  older clients default to FOOD; operators should review existing beverages.
  No inference from item names or units is used to migrate data.
- `SupplierProduct` has the composite primary key
  `(venueId,supplierId,stockItemId)`. Composite foreign keys to Supplier and
  StockItem enforce matching Venue ownership even for direct database writes.
  A product can have many suppliers; a supplier can have many products.
- Supplier name is required; contact fields, including email, remain optional.
  Links can be set in the Stock Item editor or the Supplier detail. Unlinking
  deletes only the catalog relation. Receiving has no dependency on that relation.
  Old receipt supplier names, item names and prices remain frozen.
- Link, unlink and full supplier-set changes use the existing transactional
  Global Audit writer. Repeated identical changes produce no audit row. Derived
  cost reads create no audit events.

## Daily receiving and business dates

Receiving remains the only procurement document. `businessDate` is now distinct
from `documentDate`. New Manager forms use the current POS-synced business date,
show it explicitly, and allow an operator to select a different business date.
The invoice date remains independently editable on a draft.

The backend defaults a new document to the Venue's `currentBusinessDate` setting.
A supplied business date is validated as a calendar date; it is never a tenant
identifier. Older clients without the field use the synced date, or the document
date if the Venue has never synced one. Draft edits preserve their existing
business date unless explicitly changed. Posted documents remain immutable.
Legacy documents are populated from `documentDate`, which was already the date
used for their original RECEIVING movements; this is compatibility metadata,
not an inferred historical open-day reconstruction.

Multiple receipts can belong to one business date. Manager daily history filters
and groups by this field, including after Close Day. Its full-day posted count
and total are database aggregates, independent of pagination; drafts and cancelled
receipts remain inspectable. Day totals represent all Venue receipts for that
business date, including when text or status filtering narrows the visible list.
Close Day retains its offline behavior and does not delete these Cloud documents.
Procurement reporting lives in Manager daily receiving; the local POS Close Day
printout is not given a second or stale procurement ledger.

Supplier-linked products appear first and as quick choices. Links express the
usual catalog, not exclusivity: another active StockItem from the same Venue is
permitted without automatically changing supplier relationships. A price is
entered per selected purchase unit. For 10 packs of 10 pieces at 12 GEL/pack,
Receiving freezes 100 pieces and 120 GEL; its effective cost is 1.20 GEL/piece.

`keg` is a purchasing label only: configure, for example, 1 keg = 30 L on that
StockItem. It cannot be a new base unit or a recipe consumption unit. Count
packages have no global conversion. Manager units use Georgian labels; wire
codes remain `g`, `kg`, `ml`, `L`, `piece`, `bottle`, `pack`, `box`, `keg`.

## Current weighted purchase cost

The explicitly named method is `POSTED_PURCHASE_WEIGHTED_AVERAGE`:

```
SUM(frozen ReceivingLine.lineTotal)
---------------------------------
SUM(frozen ReceivingLine.baseQuantity)
```

Both sums include only receipts currently POSTED in the authenticated Venue,
for the StockItem and matching frozen base unit. Drafts contribute nothing.
Cancellation atomically changes the status and writes complete reversal
movements, so a cancelled receipt contributes neither value nor quantity. There
is no partial Receiving reversal in the existing engine. Repeated cancellation
has no additional valuation effect.

This is an average over valid procurement history, not a perpetual weighted
valuation of the stock still on hand. Consumption does not remove purchase
weights. The answer remains a current theoretical reference even when current
stock is zero or negative. Last purchase price is separately derived from the
latest posted business date, posting time and stable receipt/line ordering.

All cost arithmetic uses a local Prisma Decimal constructor with 60 digits of
precision and half-up rounding; there is no Float computation. Calculations use
frozen line totals rather than re-averaging the rounded effective unit costs.
Unit costs and component costs are presented as six-decimal strings, but menu
cost multiplication uses the unrounded quotient. The final menu total is rounded
once to two GEL decimals, with a twelve-decimal total also supplied for inspection.
No repeating decimal has a finite exact representation; calculations retain the
specified precision until presentation.

No valid purchase history yields `NO_PURCHASE_HISTORY` and a null cost, explicitly
shown in UI. A genuinely zero-price posted receipt is valid history. A recipe
with any missing ingredient price has `MISSING_COMPONENT_COST`, not a misleading
partial or zero total. Missing/disabled definitions have `NO_ACTIVE_RECIPE`.
Items with posted/cancelled receipt history or recipe use cannot change their
base unit through the catalog editor. Open-draft unit changes still trigger the
existing posting validation.

## Menu workflow

The existing Menu hierarchy supplies the food/drink filter. Explicit Georgian
and English category names are recognized; ambiguous categories remain in
“All” and “Other categories”. No MenuItem identity is duplicated or rewritten.
Category naming remains free text, so this is a conservative presentation rule,
not authoritative restaurant menu taxonomy.

Food starts with a technological card; drinks can use the direct link mode.
Both save the existing `MenuConsumptionRecipe`. One piece of packaged Borjomi,
0.500 L of draft beer, and a dish with several ingredients use the same
normalized `baseQuantityPerUnit` multiplied by each current purchase cost.
Existing variants and yield handling remain intact.

The editor displays sale price, current theoretical cost and an expandable
component breakdown. It labels the calculation as using the saved composition;
unsaved edits take effect after saving/reopening. Creating a missing StockItem
from a direct link suggests the Menu Item name; an ingredient starts with a blank
name. Stock and Menu identities remain independent.

## API and compatibility

- Existing Manager Stock Item CRUD accepts `classification` and optional
  `supplierIds` (full replacement only when supplied).
- `GET /mobile/inventory/suppliers/:id` returns linked products and recent receipts.
- `POST` / `DELETE /mobile/inventory/suppliers/:id/products/:stockItemId` link/unlink.
- Existing Receiving reads/writes carry `businessDate`; list `from`/`to` now filter
  business dates, and `businessDays` carries full-day status/count/value summaries.
- Stock detail exposes `currentCost`; Menu recipe detail exposes `currentCost` and
  component prices. Every query derives its Venue from Manager Staff authority.
- `GET /edge/inventory/catalog?version=4` is Device -> Venue scoped and includes
  new catalog fields and keg packaging. Older clients omit the version and get
  v3-compatible units/purchase units, while still receiving every active recipe.
  This prevents a new keg label from breaking their strict unit decoder.

## Migration and deployment

Migration: `20260912120000_inventory_step45_catalog_cost`.
Apply migrations, deploy the backend (regenerate Prisma Client/build), then deploy
the operations app to Manager/POS clients. Old POS clients retain recipe sync via
catalog version negotiation. Do not deploy a new Manager against an old backend:
it cannot persist the new classification/relationship/business-date fields or
supply current costs. No commits, push or production deployment are part of this
change.

Validation uses a disposable `/tmp` PostgreSQL cluster on port 55445 and database
`vynic_step45_test`. No command targets `vankisi_database`.
All migrations were applied from empty, Prisma validation passed and migrate diff
reported no difference. Backend tests cover catalog/relationships, audit,
business dates, immutable prices, packaging, exact cost examples, cancellation,
missing prices, tenant isolation, old/new projections and existing inventory
engines. Flutter tests cover filters, Georgian forms, supplier links, receiving,
food/drink separation, cost visibility, phone layouts and Hive restart/restore.
Validation result: 126 backend tests and 106 Flutter tests passed; backend build
and targeted Flutter analysis passed. The UI QA tests rendered the catalog, Stock
Item editor, Supplier detail, daily receiving and cost detail at 390 px with the
Georgian font, and the images were visually inspected. They can be regenerated
when `INVENTORY_QA_DIR` is set.

## Next phase boundary

Historical Sale COGS, realized gross/net profit, FIFO, waste/write-off, stocktake,
variance, tax integrations and sub-recipes remain unimplemented. No historical
Sale is valued or rewritten. Step 4's immutable quantity snapshots and Step 4.5's
current procurement reference are foundations for a later explicitly designed
valuation snapshot phase; today's average must never be joined onto past Sales
and presented as their historical COGS.
