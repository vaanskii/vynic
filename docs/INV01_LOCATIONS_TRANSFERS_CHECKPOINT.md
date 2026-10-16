# INV-01 — Locations and transfers checkpoint

Status: **partial backend F1 candidate; F2 blocked on product decisions**.
This checkpoint does not complete Phase 9, full Inventory, transfers or the
mandatory flour scenario. Nothing was deployed or applied to real databases.

## Scope implemented

- A Venue owns stable `StockLocation` identities. Every existing and newly
  inserted Venue has one default `ძირითადი მარაგი`; a partial unique index
  prevents duplicate defaults. Locations can be created and renamed through
  the existing Manager + `MANAGER_APP` + `INVENTORY` authority.
- `20261017120000_inventory_locations` assigns all old Receiving documents and
  movements to their own Venue's default. It changes no old quantities, values,
  timestamps, valuation sequences, payments or receipt status.
- New receipts optionally select a location; omitted legacy draft updates
  preserve their existing selection. Posted/cancelled receipt locations and
  movement locations cannot be reassigned. Receipt movements inherit their
  document, and reversals inherit their original movement.
- Composite `(venueId, locationId)` foreign keys enforce ownership. SQL insert
  triggers plus non-null CHECK constraints preserve old Prisma insert shapes
  while requiring an actual location in committed records.
- `GET /mobile/inventory/locations`, `POST /mobile/inventory/locations`,
  `PATCH /mobile/inventory/locations/:id` and
  `GET /mobile/inventory/stock-items/:id/locations` are additive. Creation needs
  a UUID request ID; a locked, persistent fingerprint prevents duplicate
  creation or different-intent reuse, including after a process restart.
- Location quantities come from the existing movement ledger. The per-item
  response derives the Venue sum and every location quantity within one
  repeatable-read snapshot. It includes zero locations and signed quantities;
  there is no editable balance or second ledger.
- Receipt/movement history and audits include location identity. The existing
  child-first deletion matrix includes StockLocation after its references.

## Preserved accounting and client boundaries

D015 still uses the Venue-wide StockItem moving average and Cloud acceptance
order. The valuation function and item-lock protocol are unchanged; this does
not introduce separate per-location cost accounting or historical POS COGS.
Old version-1 POS snapshots keep their default location, even when received
goods are at another location, and existing POS negative-quantity behavior is
preserved. A later settings change must never reinterpret an old/offline Sale.
Older Manager/POS clients ignore the additive response fields. Their receipt
inserts still get the default. No Flutter/Hive source, adapters, packages or
backup format changed in this checkpoint. Deploy the migration before the new
backend. This candidate has not been deployed.

## Decisions still required

The master plan specifies `approval/handoff as product requires` but does not
choose these rules. The following questions were sent to the user; no option
is authorized merely by its preselection:

1. **POS issue location:** one restaurant-selected location (recommended), or
   all Sales from the default for this checkpoint. Old version-1/offline intents
   keep the default either way. Configurable issue routing has not been added.
2. **Transfer workflow:** immediate one-step Manager confirmation
   (recommended), or sending plus destination receipt as separate steps.
3. **Insufficient source quantity:** reject manual transfer and reversal
   (recommended), or allow a negative balance with a required reason. Existing
   POS consumption behavior is separate and remains unchanged.

F2's immutable document, paired quantity/value effects, source availability
checks, idempotent approvals and reversal workflow have **not been started**
while these decisions are pending. No transfer enum/table/API/UI was invented.
Location lifecycle/default reassignment and new warehouse roles are also not
part of this candidate. The existing SKU normalization and D015 cost policy
already answer those requirements and need no new product decision.

## Verification and exact source

The final qualification, source hashes, migration proof, lint baseline,
test overlap and owned-cluster cleanup are in
[`proofs/INV01_LOCATIONS_3463ee40_2026-10-08/`](proofs/INV01_LOCATIONS_3463ee40_2026-10-08/).
Qualification is for this uncommitted working-tree source, not HEAD alone.
Final checks for this source: Backend aggregate **870 passed / 713 skipped /
0 failed**; isolated Inventory regressions **89 passed / 0 failed**, including
the **12 new location cases**. The two sets overlap by 19 cases (the 12 location
and 7 INV-02/04 cases), so they establish **940 distinct Backend cases**.
The five existing Flutter Inventory consumer suites passed **27 cases**.
Backend typecheck/build, new-file lint, touched-file formatting, Prisma validation
and migration retry passed. The five touched Backend files retain **180 existing
lint errors / 4 warnings**, with **zero added diagnostics** against exact starting
sources. No full Flutter/Web or Windows release qualification is claimed here.
The new location suite uses owned loopback PostgreSQL and real HTTP and child
processes; it proves concurrent requests, retry after a lost response, receipt
posting/reversal, tenant/feature/role denial, audit rollback, original-location
immutability, quantity conservation and rollback of scoped deletion.

The populated immediately previous schema contains two Venues, four movements,
two receipts and a payment. After migration, every original movement, receiving
and payment field remains equal, and D015's SQL function is byte-identical.
Fresh migration, re-delivery and baseline-aware Prisma drift checks are separate
proofs. Two pre-existing DevicePrinterRuntimeRequest FK-name differences remain
unchanged; they are unrelated printer work, not new Inventory schema drift.

Existing skipped aggregate tests, touched-file lint debt, the earlier MGR-05
default-concurrency timing failure, and real enrollment/login and Windows /
hardware qualification remain open. No earlier candidate counts substitute for
this checkpoint's checks. Waste, stocktake, returns, production and F7 historical
costing have not been started.
