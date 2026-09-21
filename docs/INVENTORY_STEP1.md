# Inventory Step 1 — Core Domain

## Boundary

A Stock Item is an ingredient, packaged product, or other inventory identity.
It is not a Menu Item. Step 1 creates no Recipe, Receiving, StockMovement,
costing, waste, or stocktake relation.

`StockItem.id` and `Supplier.id` are immutable UUID business identities. Names
are not identities and may repeat. A non-null SKU is normalized to upper case
and is unique inside one Venue.

## Units and quantity

Supported units are `kg`, `g`, `L`, `ml`, `piece`, `bottle`, `pack`, and `box`.
Mass converts through grams and volume through millilitres:

```text
1 kg = 1000 g
1 L  = 1000 ml
```

Count labels have no global conversion. A box-to-piece or pack-to-piece ratio
is item-specific purchasing/packaging data for a later step.

Every Stock Item chooses one `baseUnit`. `minimumStock` is an optional exact
three-decimal threshold. There is deliberately no stored `currentStock` field.
Until StockMovement exists, API and Manager presentation return the explicit
derived placeholder `0` / `NO_MOVEMENTS`.

## Authority and persistence

Cloud PostgreSQL is authoritative for this administrative configuration:

```text
Manager Staff -> Venue -> StockItem / Supplier
```

Manager request bodies contain no authoritative Venue field. All reads and
writes filter with the Venue re-resolved from the authenticated Staff row.
Supplier and Stock Item removal is an `isActive=false` transition, preserving
stable identities for future historical references.

The POS keeps one complete Hive projection under `inventoryCatalog/catalog`:

```text
Device credential -> Device -> Venue
GET /edge/inventory/catalog
        ↓
atomic replacement of one Hive catalog value
        ↓
offline Stock Item / Supplier reads
```

The Edge initiates this pull at POS start, after enrollment, and every minute.
It never sends a Venue identifier and it never blocks startup. A failed refresh
leaves the last good catalog intact. This is a read-only local projection: POS
code does not mint Inventory ids or edit Cloud-owned definitions.

The projection is included in POS backup/restore. Older backups omit it and
restore as an empty catalog until the next successful Device pull.

## Manager surface

The existing Manager `მართვა` console has one additive `მარაგები` tab with
Stock Items and Suppliers. It supports search, create, edit, and
activate/deactivate. Forms stay open with an inline error when a save fails.
The list never presents a fabricated quantity.

The Windows POS Admin has no Inventory editor in Step 1. Duplicating the Cloud
administration surface would create two authorities and conflict rules. The POS
only holds the offline projection needed by future operational flows. Existing
Manager-role and backend role guards keep waiter workflows unchanged.

## Global audit

Manager writes create a Venue-scoped `AuditEventLog` row in the same PostgreSQL
transaction as the business change. Actions are:

- `STOCK_ITEM_CREATED`, `STOCK_ITEM_UPDATED`, `STOCK_ITEM_DISABLED`
- `SUPPLIER_CREATED`, `SUPPLIER_UPDATED`, `SUPPLIER_DISABLED`

Rows use `entityType=STOCK_ITEM|SUPPLIER`, the stable domain id as `entityId`,
and include Manager actor/source. Supplier contact values and notes are not
copied into audit details; only the changed field and whether it is populated
are recorded.

## Deployment order

1. Deploy the backend migration and backend application.
2. Deploy Manager clients with the Inventory UI.
3. Deploy POS clients with the Hive projection pull.

Older Manager/POS builds ignore the additive tables and endpoints. Deploying
the POS before the backend is non-destructive—the background projection pull
fails and preserves its prior/empty cache—but backend-first avoids needless
errors.

## Step 2 extension point

Receiving/Waybills can reference the stable `StockItem.id` and `Supplier.id`.
StockMovement must become the authoritative quantity history; it must not be
implemented by turning the Step 1 placeholder into an editable balance.
