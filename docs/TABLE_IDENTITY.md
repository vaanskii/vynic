# Canonical Table Identity Foundation

Step 3B makes one UUID the immutable identity of a physical table while all
existing floor, number, reservation, website, and display identifiers remain
compatibility aliases. It does not introduce tenancy, zones, or new booking
semantics.

## Identity inventory

| Concept | Persistence / location | Example | Meaning | Stability |
| --- | --- | --- | --- | --- |
| POS table definition ID | `RestaurantTableLayout.tables[].id` in Hive setting `activeTableLayoutJson` | UUID after Step 3B | Canonical physical-table identity, generated offline once | Stable across restart, sync, label edits, and geometry edits |
| POS live table row | Hive `TableModel` | `floor=first`, `tableNumber=3` | Occupancy state addressed through legacy aliases | Alias is mutable; canonical UUID resolves through the active table definition |
| Backend table ID | PostgreSQL `pos.Table.id` | UUID | Canonical cloud identity of the same physical table | Stable; an existing server-created ID is adopted to the first POS-supplied UUID |
| `TableRef` | Reservation Hive data and shared contract | `first/3` | Lossless floor/number compatibility reference | Stable only while those aliases remain unchanged; not canonical identity |
| Legacy table code | Reservation wire and stored compatibility data | `13` | Two-floor integer encoding (`second/3`) | Transitional and intentionally range-limited |
| Order table association | POS order `tableNumbers` plus `floor` | `['3']`, `first` | Existing dine-in association | Preserved; transitional sync may add aligned `tableIds` |
| Website table ID | PostgreSQL `website.tables.id` | autoincrement integer | Database-local reservation join key | Not a physical-table wire identity |
| Website table number | `WebsiteTable.websiteTableNumber`, mappings, SVG IDs | `table3`, `f2-table1` | Customer-site presentation/selection alias | Preserved unchanged |
| Website → POS alias | `WebsiteTable.posFloor` + `posTableNumber` | `second` + `1` | Bridge used to produce legacy reservation codes | Preserved unchanged |
| Realtime table identity | `tables_bulk_touch` payload | floor/number plus optional `tableId` | Manager notification/update routing | UUID is additive; old consumers keep using aliases |

## Canonical decision

`RestaurantTableDefinition.id` and `pos.Table.id` are the same canonical UUID.
This reuses both systems' existing persistent table entity rather than adding a
second model. The ID has no floor, table number, label, website number, or
layout coordinate embedded in it.

The POS owns generation because table configuration must work offline. Newly
placed or duplicated tables receive UUIDv4 identifiers. On the first startup
after Step 3B, presentation-era IDs such as `floor1-table1` are replaced with
UUIDv4 values and every `RestaurantLayoutObject.tableId` link is rewritten in
the same saved layout. That saved JSON is the explicit backfill mapping, so a
restart or repeated sync reuses the same values.

## Transitional sync

Old clients continue sending:

```json
{ "tableNumber": "3", "floor": "first", "isReserved": true }
```

New clients add the canonical identity:

```json
{
  "tableId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "tableNumber": "3",
  "floor": "first",
  "isReserved": true
}
```

The backend retains the historical floor/number upsert for old payloads. For a
valid UUID payload it resolves both UUID and alias, adopts an existing legacy
row when unambiguous, and rejects a collision instead of creating a second
physical table. Orders may carry `tableIds` aligned with `tableNumbers`, and
table realtime hints may carry `tableId`; every legacy field and event name
remains present.

## Deliberate boundaries

`TableRef` remains the current canonical reference *inside reservation logic*,
but it is not redefined as the physical-table UUID. Reservation storage,
availability, locking, payment, status, and bookability do not change.

`WEBSITE_TABLE_MAPPINGS`, `websiteTableNumber`, the SVG assets, and the website
API/UI remain unchanged. No `Organization`, `Venue`, `venueId`, `Zone`, or
Device-to-Venue relationship is introduced.
