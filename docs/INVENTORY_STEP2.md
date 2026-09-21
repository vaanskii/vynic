# Inventory Step 2 — Receiving / Waybills + Stock Movement Ledger

## Core principle

Current stock is never a stored, editable balance. It is derived:

```text
currentStock = SUM(StockMovement.quantityDeltaBase)
```

Step 2 introduces exactly two movement types, `RECEIVING` and
`RECEIVING_REVERSAL`. `SALE`, `WASTE` and `STOCKTAKE` are later steps; the enum
and the model are shaped so adding them changes no existing row.

## Receiving document

`Receiving` is a Venue-scoped procurement document with a UUID identity,
`supplierId`, `waybillNumber`, `invoiceNumber`, `documentDate` (`YYYY-MM-DD`),
`receivedAt`, `status`, an exact `documentTotal`, actor columns for create/post/
cancel, and `ReceivingLine[]`.

```text
DRAFT      editable, deletable, moves no stock
POSTED     frozen, has movements
CANCELLED  keeps document and movements, gains reversals
```

A posted document cannot be edited or deleted. `POSTED -> CANCELLED` with
reversal movements is the only way to withdraw a receipt, and PostgreSQL
enforces it: `StockMovement.receivingLineId` is `ON DELETE RESTRICT`.

## Receiving line

Each line freezes a purchase snapshot:

```text
stockItemId             durable identity
stockItemNameSnapshot   historical display context
enteredQuantity/Unit    what the waybill said  ("10 box")
baseQuantity/Unit       what the ledger uses   ("240 bottle")
unitPurchaseCost        cost of one entered unit
lineTotal               exact GEL
effectiveBaseUnitCost   lineTotal / baseQuantity
```

Renaming or disabling a Supplier or a Stock Item never rewrites a document that
already exists. The stable id remains the relationship; the snapshot remains the
display.

## Exact quantity and money

All durable values are PostgreSQL `DECIMAL` and cross the wire as fixed-scale
decimal strings. No JavaScript or Dart binary float is ever the source of truth.

```text
quantity                Decimal(18, 3)
GEL totals              Decimal(18, 2)
unit purchase cost      Decimal(18, 4)
effective base cost     Decimal(18, 6)
packaging multiplier    Decimal(18, 6)
```

`lineTotal = enteredQuantity x unitPurchaseCost`, rounded half-up to two
decimals once. `documentTotal = SUM(lineTotal)`, summed as decimals.

## Unit conversion

Resolution order for a receiving line, in `inventory-quantity.ts`:

1. the entered unit is the item's base unit;
2. an item-specific `StockItemPurchaseUnit` row matches the entered unit;
3. the global mass/volume table (`1 kg = 1000 g`, `1 L = 1000 ml`);
4. otherwise refuse.

```text
5000 g  -> 5 kg          global
1500 ml -> 1.5 L         global
10 box  -> 240 bottle    item-specific (1 box = 24 bottle)
kg -> L                  INVALID
piece -> kg              INVALID
box -> bottle, unconfigured for this item  INVALID
```

`box` and `pack` are never globalised. One venue's box holds 24 bottles of
lemonade and 6 of wine, so the ratio belongs to the Stock Item. A ratio for the
item's own base unit is refused rather than stored as 1.

Packaging is edited as one declared set on the Stock Item payload: sending
`purchaseUnits` replaces the whole configuration, omitting the field leaves it
untouched.

## Stock movement ledger

`StockMovement` is append-only history. A posted `+50 kg` is never edited into
`+40 kg`; a correction is an explicit reversing movement beside it.

Two database rules carry the idempotency guarantees:

```text
@@unique([receivingLineId, movementType])   one movement of each kind per line
reversalOfMovementId  @unique               one reversal per original movement
```

Future movement kinds carry a null `receivingLineId`, which PostgreSQL treats as
distinct, so neither rule constrains them.

## Posting and cancelling

Both take `SELECT ... FOR UPDATE` on the Receiving row inside one transaction.

```text
POST     lock -> validate DRAFT, Venue-owned Supplier and Stock Items,
                 unchanged base units, positive quantities, non-negative costs
              -> create one movement per line
              -> mark POSTED
CANCEL   lock -> validate POSTED
              -> one reversal per unreversed original movement
              -> mark CANCELLED
```

A repeated post returns `already_posted`; a repeated cancel returns
`already_cancelled`. Neither writes a second movement. A failure anywhere rolls
the whole transaction back: there is no partial posting.

A reversal is dated when the cancellation happened, not when the goods arrived,
so the day the stock genuinely was on the shelf keeps saying so.

## Negative stock

Step 2 deliberately defines no negative-stock policy. Receiving and its reversal
alone cannot produce an unexplained negative balance, and Sale consumption —
which is what makes the question real — arrives in a later step. Cancellation
always preserves ledger truth rather than blocking.

## Manager surface

```text
მარაგები
├── პროდუქტები   Stock Items, derived balance, low-stock, packaging
├── მომწოდებლები  Suppliers
└── მიღებები      Receiving
```

Receiving supports create, edit draft, post, cancel, search and status filters,
with a detail view that shows the frozen document and both its original and
reversal stock impact. Delete is offered for drafts only. The new-receiving form
displays the converted base quantity before posting, so "10 box" is visibly
"240 bottle" while it is still editable.

The Stock Item list shows the real derived balance instead of the Step 1
`NO_MOVEMENTS` placeholder, flags `currentQuantity <= minimumStock` as low stock
when a threshold is configured, and opens a detail with recent movements.

## POS projection

Receiving and StockMovement stay Cloud-authoritative and Manager-first. The POS
does not post documents; duplicating that surface would create two authorities.

`GET /edge/inventory/catalog` becomes version 2 and adds `currentStock`,
`stockStatus` and `purchaseUnits` to each Stock Item. The POS keeps them as
Cloud's exact decimal text and Cloud's own low-stock verdict, so the two clients
cannot disagree at the threshold boundary. A failed refresh leaves the last good
projection intact and never blocks restaurant operation.

## Backup and restore

The POS backup keeps carrying the projection under `inventoryCatalog`, exactly
as in Step 1, and Step 2's fields ride along in the same value. Receiving and
StockMovement are deliberately not in the POS backup: they are Cloud financial
history, and copying them into a terminal backup would create a second authority
that restore could put back out of date. A v1 backup restores with no balance
and no packaging and is corrected by the next Device pull.

## Global audit

Manager writes record one venue-wide row in the same transaction:

```text
RECEIVING_CREATED  RECEIVING_UPDATED  RECEIVING_POSTED  RECEIVING_CANCELLED
entityType = RECEIVING, entityId = Receiving.id
```

Details carry `supplierId`, `supplierName`, `waybillNumber`, `documentDate`,
`lineCount`, `documentTotal`, and the status transition plus movement/reversal
counts. Individual movements are not mirrored: StockMovement is already durable
ledger history. Packaging changes stay `STOCK_ITEM_UPDATED` with a
`purchaseUnits` field delta.

## Tenant safety

`Receiving`, `ReceivingLine`, `StockMovement` and `StockItemPurchaseUnit` are
Venue-scoped. The Manager resolves `Staff -> Venue`, the POS `Device -> Venue`.
Request bodies contain no authoritative Venue field. Proven against PostgreSQL:
one Venue cannot reference another's Supplier or Stock Item, read or cancel its
Receiving, or see its movements in a balance.

## Deployment order

1. Backend migration `20260909120000_inventory_step2_receiving` and the backend
   application.
2. Manager clients with the Receiving UI.
3. POS clients with the extended projection.

The migration is additive. An older Manager ignores the new endpoints; an older
POS ignores the new catalog fields. A newer POS against an older backend simply
receives a v1 catalog and reads zero balances with no packaging.

## Step 3 extension point

Recipes and technological cards can consume `StockItem.id`, the base unit and
`effectiveBaseUnitCost`. Sale consumption becomes a new `StockMovementType`
member and needs no change to Receiving. Costing must read the ledger, never a
stored balance.
