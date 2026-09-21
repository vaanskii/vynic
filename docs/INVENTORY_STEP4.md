# Inventory Step 4 — Sale consumption and restore reversal

## Authority and activation

The POS owns the close-time consumption snapshot. Cloud remains the sole
StockMovement authority. `CloseTableTransaction` opts into snapshot capture in
`SalesRepository.saveSaleRecord`; the snapshot and Sale are one atomic Hive
value. There is no network call, separate pre-Sale stock write, or new closure
journal phase. A durable Sale is the existing financial commit boundary;
recovery finishes its Order/Table/audit bookkeeping without evaluating recipes
again. A failed attempt before the Sale creates no inventory effect.

Activation is **new Sales written by the Step 4 close transaction**. Existing
Sales, imported history, cancellation sentinels and advance receipts are never
evaluated retrospectively. An older POS continues to sync its financial ledger
without producing consumption. Deploying Cloud or pulling a catalog alone does
not consume any historical stock.

Fiscal closes consume from their frozen sold lines, including Package,
Takeaway and genuine Reservation-backed Orders through the same close path.
Open Orders do not consume. Manual lines have no stable Menu identity and remain
unmapped. A financial void does not prove that physical goods returned; the
explicit restore-to-Order lifecycle is the reversal trigger in this phase.

## Internal-close policy

The current internal close has no reason that proves staff meals, complimentary
service, or physical stock use instead of bookkeeping. Step 4 therefore records
`INTERNAL_EXCLUDED` / `EXCLUDED` / `INTERNAL_POLICY`, with no ingredient movement.
This is an explicit conservative rule, readable in Manager history, and never a
revenue classification. Staff meals and other physical internal-use categories
remain outside this phase. Cancellation before close produces no snapshot.

## Immutable snapshot

The Sale's `inventoryConsumption` contains a version, policy, the last successful
catalog timestamp, and one evaluation per sold line. Each line carries its Sale
array index (`lineSeq`), POS Menu/variant IDs, frozen name, sold quantity,
`MAPPED`/`UNMAPPED`/`EXCLUDED` status and reason. A mapped line additionally carries
recipe ID/revision and components with Stock Item ID/name, base unit, exact
`baseQuantityPerUnit` and `totalBaseQuantity`.

Cloud persists `SaleConsumption`, `SaleConsumptionLine`, and
`SaleConsumptionComponent`, all Venue-scoped. The original payload is retained
for immutable-replay comparison. It is intentionally independent of CloudSale's
arrival order: the inventory upload need not wait for a financial ledger batch.
`posSaleId`, `closureId`, `orderId` and `lineSeq` provide the investigation link.
There is no live Menu-name matching, recipe recalculation, or price/cost lookup.

The POS matches only `posMenuItemId` + the exact `posMenuVariantId`. A variant
never falls back to an unvaried recipe or another size. Disabled recipes leave
the active projection. A close after the POS receives that change is unmapped;
a close made offline uses the last successfully pulled catalog, including its
old active revision. Cloud accepts that historical revision after subsequent
recipe edits/disabling, and never substitutes the current quantities. An invalid
local recipe is recorded as unmapped rather than blocking checkout.

## Exact quantities and stock status

Dart multiplies six-decimal fixed-point `BigInt` quantities by integer sold
quantities. Cloud validates with `Prisma.Decimal` that each total equals the
frozen per-unit value times the sold quantity, before creating anything.

- 400 bottles - 8 × 1 bottle = 392 bottles.
- 120 L - 4 × 0.500 L - 3 × 0.300 L = 117.100 L.
- 10 Khinkali consumes 0.350 kg beef, 0.250 kg flour, 0.080 kg onion.
- A 0.000010 kg component sold three times remains 0.000030 kg.

`StockMovement.quantityDeltaBase` becomes `Decimal(21,6)`, preserving the entire
previous 15-digit integer range and all six recipe decimals. Receiving amounts,
purchase units, costs and lifecycle are unchanged. Stock/movement output uses
three decimals when exact at that scale, otherwise six. Component quantities
cross the wire at six decimals. No binary float is durable consumption truth.

Consumption is negative; reversal is the exact positive inverse. Stock remains
`SUM(quantityDeltaBase)`. Negative balances never block close or Cloud ingestion.
`NEGATIVE` takes precedence even without a minimum; nonnegative balances retain
existing `LOW`, `OK`, and `NO_MINIMUM` codes for client compatibility. The latter
two are the normal/no-warning states. Manager shows the signed balance and an
explicit Georgian negative-stock label.

## Delivery, idempotency and crash safety

The embedded Sale is the durable outbox; `inventoryConsumptionAck` is separate
from financial ledger acknowledgements. Revision 1 means captured close; revision
2 means restored. A missing ACK stays pending across restart. The existing
Device-authenticated Inventory refresh loop independently retries consumption
through `POST /edge/inventory/consumption`, including when catalog refresh fails.
It uses at most 100 effects per pass, rotates past rejected effects, and limits a
pass to approximately 45 seconds plus the in-flight request timeout (20 seconds).
No Cloud-to-LAN operation or legacy callback was added.

A rejected effect leaves its Sale intact and does not stop another effect from
being attempted. The client checks acknowledgement identity/revision and
re-reads the Sale before writing an ACK, preserving a concurrent restore.
Failed requests remain pending and are logged with their effect identity.

Cloud serializes each Venue + POS Sale identity with a transaction-scoped
advisory lock, including the first insert. Unique constraints cover Venue +
Sale, Venue + closure, source line, component, component + movement type, and
`reversalOfMovementId`. The snapshot, all components, all movements and reversal
marker commit in one transaction. A failure after the first ingredient rolls
back the entire set. A replay with changed immutable data returns 409.

A restore before the original upload creates the original and its reversal in
one transaction, giving zero net stock while preserving both events. A delayed
close replay cannot undo a reversal. Repeated restores return stock once.
The restore records its own business date/effective timestamp; re-close creates
new Sale/closure identities and a new snapshot from the then-local catalog.

## Manager investigation and audit

Staff -> Venue routes:

- `GET /mobile/inventory/consumptions?from=YYYY-MM-DD&to=YYYY-MM-DD&unmapped=true`
- `GET /mobile/inventory/consumptions/:id`

Inventory links to consumption history and its unmapped-only filter. Results
show date, Order, products/variants, quantities, reversal/internal status and a
detail action. Detail shows Sale/closure identity, recipe revision and exact
component quantities. Stock Item recent movements label consumption and restore
with the Order number and link to the same detail. Narrow screens use wrapping
Inventory navigation choices and scrollable detail content.

History is bounded to the most recent 100 matching Sales; a date range narrows
older investigation. It is not an unlimited export or a stocktake screen.
Unmapped lines produce durable investigation metadata and no fake movement.
They are not backfilled automatically when someone later creates a recipe.

No new GlobalAudit ingredient events are emitted. StockMovement already records
the full immutable effects and reversal links, with Sale/Order/closure context;
existing CLOSE/RESTORE audit events remain the human lifecycle trail.

## Tenant and backup boundaries

The Edge Device guard resolves Device -> Venue; a supplied `venueId` is ignored.
Manager reads use the existing Staff -> Venue decorator/guard. Recipe identity,
its POS product/variant association and every Stock Item/base unit are checked
inside the transaction against the authenticated Venue. History/reversals cannot
reach another Venue. Historical quantities are trusted as the enrolled POS's
close-time snapshot, not re-derived from a mutable current recipe.

Sales already round-trip as complete maps through backup/restore. Embedded
snapshots, pending ACK state and restore markers therefore survive without a new
box or a competing stock ledger. Cloud StockMovement rows are not copied into
POS backups. Catalog data remains a re-pullable projection.

## Validation and deployment

Migration: `20260911120000_inventory_step4_sale_consumption`.

Validation completed with 197 backend tests and 189 Flutter tests passing; the
optional private retained-Sale export test is intentionally skipped. Backend
build, TypeScript `--noEmit`, Flutter analysis, Prisma validation, zero migration
drift and `git diff --check` pass.

Use disposable PostgreSQL only. Validation covers every migration from empty,
Prisma schema validation and drift comparison, exact direct/draft/ingredient
balances, variants, old recipe revisions, disabling, negative stock, unmapped
history, HTTP Device authority, cross-Venue access, concurrent replay/restore,
restore before upload, transaction failure after the first ingredient, and
Receiving/reversal alongside consumption. Flutter proofs cover the actual local
close/restore/re-close path, cancellation/ledger regressions, fixed-point math,
offline/lost-ACK/restart retry, backup, projection and narrow Manager widgets.

Deploy in this order:

1. Apply migrations and deploy the backend with consumption routes.
2. Deploy Manager with negative-stock and history views.
3. Deploy POS with close-time capture and Device-authenticated retry; confirm
   enrollment and a successful catalog pull before relying on mapping coverage.

A new POS with an older backend retains pending effects through 404/errors;
checkout remains local. Neither live `vankisi_database` nor live restaurant
Orders are used for implementation tests.

## Limits and Step 5 boundary

Offline operation cannot know a Cloud recipe was changed or disabled until the
next successful pull. The exact cached revision remains the historical truth.
An unenrolled POS cannot deliver effects until enrolled. Deleted/unresolvable
recipe or Stock Item identities are rejected and remain pending for investigation;
no guessed replacement is made. Internal closes remain explicitly excluded.
The quantity ledger is theoretical and can be incomplete where lines are
unmapped or inventory effects remain pending.

Step 4 provides immutable quantities and links needed by later costing work.
It does not establish opening stock valuation, valuation chronology or costing
policy. Weighted-average cost, FIFO, COGS, Gross Profit, Food Cost %, yield/loss,
Waste, Staff meals, Stocktake, variance, RS.ge, purchasing automation and GL are
not implemented. Step 5 has not started.
