# Vynic Project State

Compact snapshot of implemented facts. This is not a changelog or an
architecture manual. Current code, schema, migrations, contracts, and tests win
if this file becomes stale.

Some phase documents preserve the state at the time they were written. In
particular, older deferred lists for enrollment, tenancy, and Platform Admin
predate Step 6C; use this snapshot and `docs/EDGE_COMMAND_MIGRATION.md` for the
current transport status.

## Current Product Shape

- `apps/operations/` is one Flutter codebase for the offline-first desktop POS
  and the mobile/desktop Manager client.
- `apps/backend/` is the modular NestJS service over PostgreSQL through Prisma.
- `apps/platform-web/` contains the public Vynic product site and the
  authenticated Platform Admin under `/admin`.
- `apps/venue-web/` is the bespoke Vankisi customer website. It is not the
  generic multi-Venue SaaS website.
- `packages/contracts/` owns the generated Cloud/Edge command, table-identity
  and Go/Dart foundation protobuf wire contracts.
- `apps/edge/` provides the non-authoritative Go foundation and Phase 2A shadow
  Order/Table coordination. Explicit Flutter observers compare proposals/results;
  production operation remains owned by the Phase 0 Primary POS.

## Current Architecture

- The POS owns live restaurant operation and persists it in Hive. Cloud mirrors
  operational state and coordinates Manager, website, and Edge work.
- PostgreSQL uses shared `pos` and `website` schemas with explicit
  `Organization -> Venue` ownership; Venue is the operational tenant boundary.
- Tenant authority is server-owned: Device -> Venue for POS, Staff -> Venue for
  Manager, Host -> VenueDomain -> Venue for public website requests, and booking
  identity -> Venue for payment callbacks.
- `PlatformUser` is a separate cross-tenant principal. It is not Staff and has
  no Venue membership.
- The staff plain-PIN vault (`staff:plain_pins`) is one encrypted `setting` row
  per Venue, and every read/write requires a resolved tenant. There is no
  bootstrap-Venue default: an unestablished Venue raises rather than being
  served the bootstrap Venue's credentials.
- Cloud-originated POS work uses a persistent pull queue. The Edge initiates the
  connection, executes locally, journals the outcome, and acknowledges it.

## Current Phase

- POS touch input shares TEXT/NUMBER/DECIMAL/PIN modes, controller-backed fields,
  one text keyboard and one numeric/PIN pad. Login, lock and Staff authentication
  pads remain available when the optional operational keyboard is off. PIN digits
  update masked displays immediately; submission is explicit by action/Enter.
  Reservations, Menu, Packages, settings and Inventory search edit their actual
  controllers live; keyboard docks keep the focused field visible. Standalone
  prompts own one visible input, while form keyboards have no second text box.
  Inventory remains read-only apart from search/filter controls. Management Center
  persists `posOnScreenInputEnabled` (default on); Manager does not load it.
  The POS locale observes the persisted language above its Navigator, with SDK
  locale delegates and a shared UI catalog for navigation, authentication, input,
  settings and the affected operational surfaces. Open routes/dialogs update without
  discarding drafts. Menu's language action uses the same persisted setting.
  Quit uses a responsive Vynic modal and the existing safe shutdown coordinator.
  Login/lock date and time sit at the right edge; Home keeps a neutral work-date
  indicator visible at compact/fullscreen widths. Regression proof:
  `test/widget/pos_interaction_pass_test.dart` under `apps/operations/`.


- Windows POS uses native borderless fullscreen with monitor/DPI refitting;
  Manager keeps its normal window. Settings and Alt+F4 share confirmed clean Quit:
  the existing readiness barrier excludes active transactions/startup probation,
  POS workers stop and local journals/Hive flush before only POS exits. Durable
  open Orders/Tables and Cloud backlog remain recoverable and do not block Quit.
  Next POS publication is 1.0.5 / signed release 6; see
  `docs/WINDOWS_POS_FULLSCREEN_QUIT.md`.

- Windows POS has an opt-in Go Edge updater: signed Ed25519 release manifests,
  silent verified ZIP staging, explicit Georgian Update Now/Later and Settings,
  one readiness/admission barrier, startup health and binary-only rollback.
  Durable open Orders/Tables and Cloud outboxes do not block; uncertain intents,
  projection recovery and in-flight payment/close/write operations do. Manager,
  Phase 0 fencing and Phase 2A production authority remain unchanged. macOS
  simulations pass. `VynicSetup.exe` provisions a per-user Windows host from
  signed Edge/POS bundles, with restricted ACLs, local-only Edge host startup,
  updater-aware shortcuts and data-preserving repair/uninstall. POS binaries use
  bounded `current/staging/rollback` slots: 30-second authenticated stabilization
  precedes permanent rollback/temp cleanup; cleanup crashes retry deletion only.
  Signed bootstrap metadata requires a layout-2-capable Edge; repair never changes
  its pinned baseline. Deferred updates stay staged. Real signing/feed
  publication and Windows qualification remain required. See
  `docs/POS_WINDOWS_UPDATER.md` and `docs/WINDOWS_SETUP.md`.

- Edge Phase 2A adds SHADOW Order/Table revisions, request idempotency, a durable
  event sequence, tombstones and replay/snapshots over Phase 1 TLS pairing.
  Two separate terminal processes/Hive stores converge against one Go Edge.
  Hive v9 adds stable Order/OrderLine UUIDs; existing Table UUIDs are reused.
  Explicit observers capture supported proposals before primary Hive writes and
  compare the result. They are unattached by default. Production authority remains
  Phase 0: no operational Edge selection or cutover gate is enabled. Remaining
  writer coverage and cutover prerequisites: `docs/EDGE_PHASE2A_ORDERS_TABLES.md`;
  foundation/fencing: `docs/EDGE_PHASE1_FOUNDATION.md`, `docs/EDGE_PHASE0_PRIMARY_DEVICE.md`.
- The latest completed sequence covers Money Integrity 1A/1B, POS enrollment
  1C, incremental audit sync, Edge Step 6C, Menu Identity Phases 4.5/4.6, and
  the Phase 5 Cloud Sale Ledger/Manager financial experience.
- Inventory Steps 1, 2, 3 and 4 are implemented after the Cloud Sale Ledger. Stock
  Items, Suppliers, Receiving/waybill documents, the StockMovement quantity
  ledger, Menu consumption definitions and automatic Sale consumption/restore
  reversal are present. Step 4.5 adds food/beverage catalog classification, supplier
  product links, business-date daily receiving and current weighted purchase /
  theoretical Menu costs. The procurement rework supersedes historical-purchase
  averaging with moving stock valuation and separates supplier payments from receipts.
  Step 4.6 consolidates procurement Financials, responsive
  Manager Inventory and read-only POS Admin inspection; historical Sale COGS,
  waste and stocktake remain later steps. Step 4.7 adds Staff payroll and recurring
  obligations/reserve planning; module entitlements and manual Platform commercial control are implemented in SaaS Phase 2.

## Completed Foundations

- SaaS Manager Phase 1 is implemented: stable Venue login codes + PIN,
  Staff-resolved socket rooms, tenant-carrying notifications/push/presence,
  Venue-local echo suppression and removal of unused `/sync/diff`.
  Old Vankisi PIN-only clients require an explicit expiry setting capped at
  2026-12-01; migration/client rollout is not established by repository code.
  Manager now validates and remembers Venue selection per device/API origin:
  first launch is Restaurant Code entry, subsequent launches are PIN-only.
  Logout retains selection; restaurant switching clears session/cache/selection.
  Production login/settings hide API controls. Platform and owner Manager setup
  display/copy the existing immutable code. See `docs/MANAGER_SAAS_PHASE1.md`.

- Organization/Venue foundation and Venue-scoped operational data are
  implemented (Steps 4A and 4B1).
- Manager Staff -> Venue resolution and `MANAGER_APP` enforcement are
  implemented (Step 4B2A).
- Public Host -> Venue resolution, Venue-owned website tables/bookings, and
  `WEBSITE` enforcement are implemented (Step 4B2B).
- Plan, Feature, Venue assignment/override, and WebsiteMode are implemented
  (Step 5A). Effective features come from `VenueEntitlementsService`.
- Edge queue/backend transport, POS claim/execute/journal/ack, and real command
  migration are implemented (Steps 6A-6C).
- Platform principal/API and the authenticated Platform Admin UI are implemented
  (Steps 7A-7B).
- One-time, Venue-bound POS self-enrollment is implemented (Phase 1C).
- Inventory Step 1 is implemented: Venue-owned Stock Items and Suppliers use
  immutable UUIDs, optional Venue-unique normalized SKUs, soft activation, and
  exact minimum-stock thresholds.
- Inventory Step 2 is implemented: Venue-owned `Receiving` documents
  (`DRAFT`/`POSTED`/`CANCELLED`), frozen `ReceivingLine` purchase snapshots,
  item-specific `StockItemPurchaseUnit` packaging ratios, and the append-only
  `StockMovement` ledger with the `RECEIVING` and `RECEIVING_REVERSAL` types.
- Inventory Step 3 is implemented: `MenuConsumptionRecipe` +
  `MenuConsumptionComponent` define what one sold Menu Item consumes. One
  generalized model covers direct bottled products, draft pours by volume and
  multi-ingredient recipes; editing a definition writes no `StockMovement`.
- Inventory Step 4 snapshots new close-time consumption inside the durable POS
  Sale, then independently retries Device-authenticated effects to Cloud.
  Cloud atomically materializes `CONSUMPTION` and exact
  `CONSUMPTION_REVERSAL` movements; restore/re-close preserves old snapshots
  and uses a new Sale identity. No historical Sale backfill occurs. Internal
  closes are explicitly excluded because current data cannot distinguish
  physical internal use from bookkeeping. Unmapped lines never block close and
  remain visible in Manager history. See `docs/INVENTORY_STEP4.md`.

- Inventory Step 4.5 is implemented: `SupplierProduct` uses composite Venue-safe
  foreign keys; Stock Items persist FOOD/BEVERAGE classification; Receiving has a
  separate businessDate and full-day procurement summaries. The procurement
  rework now uses movement-derived remaining quantity/value for current
  theoretical Menu costs. Historical phase context: `docs/INVENTORY_STEP45.md`.

- Inventory Step 4.6 makes POSTED Receiving the sole purchasing entry point.
  Known legacy Market Expense categories are rejected and excluded from Expense
  reporting; shared Expense storage/audit remain. Legacy salary Expense history
  is retained read-only after Step 4.7. Financials separates purchases,
  supplier payments, other expenses, payroll and obligation payments. Only actual
  payments enter outflows; receipt totals are purchases. Dashboard links
  procurement/stock warnings into Inventory. POS
  Admin exposes read-only stock, recent movements/receipts, recipe status and
  unmapped sold products from catalog v5. See `docs/INVENTORY_STEP46.md`.

- Inventory procurement rework is implemented: supplier-first creation supports
  existing Menu goods, ingredients and bulk beverages, retaining StockItem and
  generalized recipes. Receiving has explicit Post/Draft actions, exact price or
  line-value entry, and retry identities. SupplierPayment is append-only with
  derived debt/partial/paid states and explicit reversal. Old settlement is
  unverified until reconciled; cancellation requires verified zero net payments.
  StockMovement freezes current moving-average issue costs and exact reversal
  values under item locks, in Cloud acceptance order. Historical values are
  explicitly reconstructed; negative/unknown bases are provisional. Manager
  and read-only POS inspection show current values; checkout is unchanged.
  Manager Inventory now opens a daily dashboard with secondary supplier/Menu
  management. Receiving includes payment choices and supports self-purchase
  source snapshots without fake Suppliers. Dish/drink composition reuses the
  existing recipe engine; inline ingredient creation has retry identity. Supplier
  cards open goods creation directly; Menu selection has category/subcategory/search
  browsing. Supplied ingredients can open a dish composition with existing components
  preserved. Receiving shows explicit unit/package/total price choices and a stock /
  payment / debt confirmation summary. Supplier detail records payments directly;
  the stock catalog shows current moving cost and active Menu usage counts.
  See `docs/INVENTORY_PROCUREMENT_REWORK.md` and `docs/INVENTORY_DAILY_UX.md`.

- Financials Step 4.7 adds Venue/Staff compensation rules, frozen PayrollPeriod
  snapshots and append-only payroll accrual/payment history. Daily wages require
  explicit payable dates; no hours/attendance are inferred. Legacy salary Expense
  rows stay unmapped/read-only with no destructive migration. Payroll references
  retain Staff identities when login removal/sync deactivates them.
- Manager Payroll separates overview, daily staff, monthly staff and payments.
  Salary-type selection shows only the relevant rate input. The daily sheet
  defaults to the Venue business date (including its month across midnight),
  excludes monthly/manual periods, and rejects future days. Worked toggles use
  request UUIDs, a period lock and linked append-only signed accrual adjustments;
  reversals cannot reduce accrued pay below paid pay. Original day identity,
  period rate snapshots and audit history survive reversal and Close Day.
  Totals use exact Decimal; only payments enter Financials outflows. Compensation
  changes still take effect in an unopened month, not midway through a frozen one.
- Recurring obligations use monthly snapshots and exact Decimal reserves/payments.
  Payments consume available reserve under a cycle lock; reserves are planning,
  never outflows. Daily recommendations include today and the due date, clamp
  overdue divisors to one, and round upward to cents. Changes preserve opened
  periods. Dashboard deep-links into the separate Payroll/Obligations screens.
  Global Audit and Staff -> Venue authority cover every new mutation; no new
  entitlement or POS/Close Day dependency is introduced. See
  `docs/FINANCIALS_STEP47.md` for rules, preservation and rollout.

## POS / Edge State

- A Device credential resolves the Device and Venue; the legacy shared POS key
  cannot claim Device-specific Edge work.
- Enrollment is available through Platform Admin and `POST /edge/enroll`; the
  POS stores the issued credential outside Hive in `edge_device.json`.
- Contract v2 declares 18 types: `NOOP` plus 17 real commands covering orders,
  dine-in/takeaway, reservations, expenses, staff, and three print operations.
- All declared command types have POS handlers. Mutations converge on
  `PosCommandApplier`, shared by Edge and the legacy LAN adapter.
- Delivery is at least once. The Hive `edge_command_journal` prevents replay of
  completed work; interrupted print commands fail visibly instead of printing
  a possibly duplicated check.
- Enrolled Venues use Edge dispatch. The old callback client/outbox/listener are
  frozen fallback only for a Venue with no enrolled Device and for rollout
  compatibility; no new operations belong there.
- Fleet-wide enrollment is not established by repository code. Until every
  deployed POS has a Device credential, the fallback cannot be retired.

## Money Integrity State

- Phase 1A and 1B are implemented: material money mutations are locally audited,
  expense and adjustment data reaches Cloud, and legacy POS ingest fails closed.
- Supported fiscal and internal payment closes use `CloseTableTransaction` with
  a durable `closureId` and Hive closure journal. Cancellation, hard-delete,
  emptied-by-transfer, and Close Day paths are separate. Startup recovery
  treats the Sale as the financial boundary and never recreates it. A shared,
  journaled post-Sale step idempotently completes the Order, physical Table
  where applicable, genuine linked Reservation, and typed/locked closure audit
  before the journal becomes complete; crash-before-Sale recovery still
  abandons the attempt without revenue or closure effects.
- Successful fiscal closes emit the typed `CLOSE` audit event, while internal
  closes emit `INTERNAL_CLOSE`; `CANCEL_TABLE` remains cancellation-only. Close
  events carry structured closure identity and money details locally and in the
  Cloud audit mirror. Every close event also carries `details.source`
  (`AuditSource` wire values `POS`, `MANAGER`, `EDGE`, `SYSTEM`,
  `SYSTEM_RECOVERY`, `DEVELOPER`); a close finished by startup recovery keeps
  its type and operator actor but records `source=SYSTEM_RECOVERY` and
  `recoveryAction=finished`. A closure already finalized is never re-stamped.
- Every genuine Order cancellation goes through `CancelOrderTransaction`: the
  POS detail screen, the Takeaway home panel, the Admin close-day repair list,
  and the Manager commands `ORDER_CANCEL` and `ORDER_STATUS_UPDATE
  status=cancelled`. It writes exactly one `CANCEL_TABLE` event (with
  `orderKind`, `tableRefs`, `source`, `actorId`, `actorName`, `approvedBy`,
  `reason`, `businessDate`), locks the report as CANCELLED, writes one
  non-fiscal `isCancelled` record with zero collection, moves a genuine linked
  Reservation to cancelled without touching its identity or link, frees
  physical tables (never for Takeaway), and writes the Order status last so a
  crash retry or a repeated Manager delivery converges on one cancellation. A
  closed Order is not cancellable until restored.
- Normal operations no longer hard-delete business Orders or their audit
  reports. `ORDER_CANCEL` is a cancellation, not a delete. The only physical
  delete of a live Order is the repair primitive
  `OrderRepository.hardDeleteOrderForRepair`, which has no operational caller,
  preserves the audit report, and logs `ORDER_HARD_DELETED`. Close Day still
  deletes already-closed Order rows because their Sale is the durable record.
- Every Order audit report opens with a typed creation event carrying
  `orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`, `RESERVATION`), `tableRefs`,
  `source`, `actorId`, `actorName`, `businessDate`: `CREATE_WALKIN` for POS
  and Manager table Orders (and the carrier of a Package), `CREATE_TAKEAWAY`
  for POS and Manager Takeaway (report exists from creation, guest details in
  `details`), `ACTIVATE_RESERVATION` for a seated genuine booking
  (`reservationId`, `customerName`; `source=SYSTEM` at day-open), followed by
  `APPLY_PACKAGE` (package fields and lines) for a Package Order. Initial
  `ADD_ITEM` rows follow the creation event at the same instant and are ordered
  by the report's `sequence`, not by that instant. Moving items between open Orders writes
  `MOVE_ITEMS` on both reports (`direction`, `fromOrderId`, `toOrderId`,
  quantities still set so older readers degrade to add/remove). An Order
  emptied by transfer closes its report with a locked `TRANSFER_CLOSE`
  (`closeReason=EMPTIED_BY_TRANSFER`, `transferredToOrderId`) and still writes
  no Sale. The backend normalizer stores all of these as themselves; it must be
  deployed before a POS build that emits them. Manager `DELETE
  /mobile/takeaway-orders/:id` now marks the Cloud row cancelled instead of
  deleting it before dispatching `ORDER_CANCEL`.
- Close payment semantics are structured, not textual: `CLOSE` /
  `INTERNAL_CLOSE` stay the only closure types and `details.paymentMethod`,
  `paymentBreakdown`, `cashAmount`, `cardAmount`, `advanceApplied`,
  `collectedNow`, `isFiscal`, `closureId` are the truth; a close of a genuine
  linked booking also carries `details.reservationId`. Both audit UIs render
  payment chips (`Cash`, `Card — TBC`, `Cash 40.00 + TBC 60.00`, advance
  shown separately, provider derived from the method) through
  `CloseEventPresentation` and fall back to the historical `note` only when
  an event has no structured details. The Manager endpoint returns `details`.
- Reservations have their own append-only timeline written by the repository
  (`ReservationAuditAction`: `CREATE_RESERVATION`, `UPDATE_RESERVATION`,
  `CONFIRM_RESERVATION`, `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`,
  `COMPLETE_RESERVATION`, `DELETE_RESERVATION`) with `reservationId`,
  customer, date/time, `guestCount`, `tableRefs`, `previousStatus`,
  `newStatus`, `source` (`POS`, `MANAGER`, `WEBSITE`, `SYSTEM`), actor,
  `businessDate`, `reason`. Every POS, Admin, Manager, website-bridge, Close
  Day, activation, close, cancel, restore, delete path goes through it; a
  status already in force, an existing id, or an absent row writes nothing.
  Seating writes `UPDATE_RESERVATION` (to `in-progress`) beside the Order's
  `ACTIVATE_RESERVATION`; a delete writes the booking's last snapshot first.
  Legacy `reservation_cancelled` rows are read as `CANCEL_RESERVATION` and
  never written again.
- Current stock is derived, never stored: `SUM(StockMovement.quantityDeltaBase)`
  per Stock Item, computed in PostgreSQL as `Decimal`. There is no editable
  balance column. Receiving quantities are `Decimal(18,3)`, GEL totals `Decimal(18,2)`,
  unit purchase cost `Decimal(18,4)`, effective base-unit cost `Decimal(18,6)`;
  every value crosses the wire as fixed-scale decimal text.
- StockMovement quantities are `Decimal(21,6)` so six-decimal recipe amounts
  are preserved without narrowing the previous integer range. Derived negative
  stock is allowed and explicitly shown as `NEGATIVE`, including without a
  minimum. Receiving quantity/cost scales remain unchanged.
- A posted Receiving is inventory history: it cannot be edited or deleted, and
  cancelling it adds reversal movements beside the originals rather than
  removing them. Posting and cancelling both take `SELECT ... FOR UPDATE` on the
  document, and two database rules make them idempotent under concurrency —
  `@@unique([receivingLineId, movementType])` and a unique
  `StockMovement.reversalOfMovementId`. A repeat returns `already_posted` /
  `already_cancelled` and writes nothing.
- Receiving unit conversion resolves base unit -> item-specific
  `StockItemPurchaseUnit` -> global mass/volume, then refuses. Count packaging
  (`box`, `pack`) is never globalised: one venue's box is 24 bottles of lemonade
  and 6 of wine, so the ratio belongs to the Stock Item.
- Recipe conversion is deliberately narrower than receiving conversion: base
  unit or the global mass/volume table only, then refuse. Item packaging is
  never a consumption unit — a box is how a venue buys lemonade, never how it
  serves it. `recipeUnitsFor` is the one authority and offers `g`/`kg` for mass,
  `ml`/`L` for volume and the base unit itself for a counted item.
- There is exactly one active consumption definition per Menu Item + variant,
  enforced by `@@unique([menuItemId, variantKey])` where
  `variantKey = variantId ?? ''`. PostgreSQL treats NULLs as distinct, so the
  non-null discriminator is what makes the rule a database rule. Identity is
  `MenuItem.id` / `MenuItemVariant.id`; names are display snapshots only.
- Each component stores `baseQuantityPerUnit` (`Decimal(18,6)`), already divided
  by the recipe yield, so a batch definition ("100 khinkali from 3.5 kg beef")
  and the per-sale-unit number can never disagree. Recipes carry no purchase
  cost: a definition is physical consumption, not procurement price. Editing,
  creating or disabling one writes no `StockMovement` and leaves current stock
  unchanged; close-time snapshots preserve its `revision` instead of joining
  today's recipe onto a past sale.
- Manager Inventory labels are Georgian (`კგ`, `გ`, `ლ`, `მლ`, `ცალი`,
  `ბოთლი`, `შეკვრა`, `ყუთი`; `მინიმალური მარაგი`, `როგორ ვითვლით?`) while
  storage and the wire keep the stable English enum codes, so no persisted value
  depends on language.
- Venue-wide accountability lives in the append-only `AuditEventLog`, which is
  now readable. Every row carries `entityType`/`entityId`
  (`STAFF`, `MENU_ITEM`, `MENU_CATEGORY`, `MENU_VARIANT`, `PACKAGE`, `EXPENSE`,
  `CLOSE_DAY`, `BACKUP`, `RESERVATION`, `ORDER`, `SALE`, `BUSINESS_DATE`,
  `SETTINGS`, `DEVELOPER`, `STOCK_ITEM`, `SUPPLIER`, `RECEIVING`, `RECIPE`),
  written by
  `GlobalAudit`
  and additive in Hive, on
  the wire and in Cloud. Rows written before those fields existed are never
  rewritten: both
  the backend (`audit-log-entity.ts`) and the POS
  (`global_audit_registry.dart`) derive the entity from the action name and the
  row's own details at read time, and an action outside the registry stays
  unclassified rather than being guessed at.
- Audited venue-wide actions: `STAFF_CREATED` / `STAFF_UPDATED` /
  `STAFF_ROLE_CHANGED` / `STAFF_PIN_CHANGED` / `STAFF_DELETED` (a PIN change
  records only that it happened — never a PIN value), `MENU_ITEM_*` and
  `MENU_CATEGORY_*` and `MENU_VARIANT_*` (a subcategory is a category node with
  `details.nodeKind=SUBCATEGORY`; price, availability and kitchen routing come
  through as `changes` field deltas, never a menu snapshot), `PACKAGE_CREATED` /
  `PACKAGE_UPDATED` / `PACKAGE_DELETED` (definitions only — applying one to an
  Order stays `APPLY_PACKAGE` on that Order's report), `EXPENSE_CREATED`,
  `RECEIVING_CREATED` / `RECEIVING_UPDATED` / `RECEIVING_POSTED` /
  `RECEIVING_CANCELLED` (document summary and status transition only —
  StockMovement is already ledger history and is never mirrored row by row),
  `RECIPE_CREATED` / `RECIPE_UPDATED` / `RECIPE_DISABLED` (Menu Item, variant,
  yield, component count and revision — a summary, never the card itself),
  `CLOSE_DAY_COMPLETED` / `CLOSE_DAY_BLOCKED`, and `BACKUP_RESTORED`. Each
  writer is a no-op when nothing moved, and a redelivered Manager command
  produces no second row. `BACKUP_RESTORED` is written after the payload is
  applied, because `clearExisting` empties the box it lives in.
- The Manager reads that feed at `GET /mobile/audit-log` (filters: date range,
  action, `entityType`, `entityId`, actor; keyset pagination by
  `createdAt desc, id desc`) with `GET /mobile/audit-log/facets` for the
  actions a Venue has actually recorded. Both are Staff -> Venue scoped; an
  entity filter also matches the actions that mean that entity, so history with
  no `entityType` is still found. The POS reads the same rows locally in the
  Admin "აქტივობა" section. A single Order's lifecycle is deliberately not in
  this feed — it has its own report.
- Both Admin audit screens render one Order's report chronologically: ordered
  by `sequence` ascending and numbered `sequence + 1`, so the creation event
  reads as step 1 and the close as the last step. The venue-wide feed stays
  newest-first.
- A Manager upsert that lands on an existing Order now diffs its items against
  storage and writes the same `ADD_ITEM` / `REDUCE_QTY` / `DELETE_ITEM` events a
  POS edit would, with `source=MANAGER`, through the one
  `AuditOrderDiffService`. A redelivered identical payload writes nothing.
- Every persisted POS Menu node has stable offline identity: category,
  subcategory and variant IDs are UUID v4 fields alongside `MenuItemDB.id`.
  Hive migration v8 runs `MenuRepository.ensureStableMenuIds` once for legacy
  rows; older backups run the same idempotent pass after restore. IDs are never
  minted while decoding. Renames, slug/size/price edits, Manager edits,
  restart, backup and repeated sync preserve them. New `MENU_CATEGORY_*`,
  `MENU_ITEM_*` and `MENU_VARIANT_*` audit rows use the stable ID as
  `entityId`; mutable paths and labels remain details. Historical audit is not
  rewritten.
- Cloud preserves POS identity beside its public row keys as
  `posMenuCategoryId`, `posMenuSubcategoryId`, `posMenuItemId`, and
  `posMenuVariantId`. Menu ingestion matches identity first, adopts only an
  unclaimed legacy row through its prior natural key, and updates only changed
  fields. Snapshots carrying `menuIdentityVersion >= 1` reconcile absent
  POS-owned variants/items/subcategories/categories in one child-first
  transaction; Venue scoping and explicit non-null POS ownership protect
  foreign, website/custom, and unclaimed legacy content. Older snapshots never
  trigger deletion. `MenuItem.id` remains the Cloud/public website key.
- `OrderItem` and `PackageItem` carry additive nullable `menuItemId` and
  `variantId` references. POS/Manager selection, Edge/LAN commands, reservation
  activation, Takeaway, Walk-In, package application, quick drafts, transfer,
  sync and backup preserve them. Manual and legacy lines remain null. Names,
  prices, quantities, comments and package contents remain frozen transaction
  snapshots and are never refreshed from the live Menu. Order item audit
  details carry the IDs when available. This makes future per-product
  SaleLine attribution ready without name inference.
- New Reservation ids are uuids. Two bookings taken in the same millisecond used
  to collide on a clock-derived id. Cloud-supplied ids are still used verbatim
  and historical numeric ids are untouched; nothing parses a reservation id.
- Money mutations on an open Order are mirrored into its visible report:
  `RECORD_ADVANCE` (`previousAmount`, `newAmount`, `receiptId`,
  `collectedOn`), `ADJUST_ORDER` (`field` `manualAdjustment` or `serviceFee`,
  `previousValue`, `newValue`, totals). A Sale void appends `VOID_SALE`
  (`saleId`, `closureId`, `grossAmount`, `reason`) to the closed, locked
  report without changing its status or lock; it is not `CANCEL_TABLE`. The
  log rows (`ADVANCE_RECORDED`, `ORDER_MANUAL_ADJUSTMENT_CHANGED`,
  `ORDER_SERVICE_FEE_CHANGED`, `SALE_CANCELLED`) are still written; they are no
  longer write-only duplicates but the Order-entity content of the venue-wide
  feed, which the per-Order report cannot serve. Cancellation stores `approvedById` /
  `approvedByName` beside the note.
- Restore-to-order keeps the original close and Sale as history, marks closure
  A reversed, clears the Order closure identity, and emits `RESTORE` in the same
  unlocked audit report; re-close creates closure B and appends a new `CLOSE`.
  The restored Sale retains its tender detail but is excluded by the existing
  revenue predicate. A consumed advance is put back on the open Order and is
  applied to closure B only.
- Restoring a table Order occupies its tables locally again. Takeaway restore
  has no physical-table dependency, Package fields remain on the existing
  Order, and a genuine linked Reservation moves from completed back to
  in-progress without changing its identity or Order link, then completes on
  re-close.
- Internal/non-fiscal close preserves operational gross and advance identity
  while recording `paymentMethod=non-fiscal`, zero cash/card, and
  `collectedNow=0`; the transaction boundary normalizes legacy caller input so
  it cannot masquerade as collected tender.
- Advances are receipts on the collection day and are applied at close; they do
  not reduce the sale's gross value.
- Gross sales and money collected are separate derived figures. POS X/Z/monthly
  totals continue to use the local Sale store and its one revenue predicate;
  open-table payable remains a separate operational metric.
- Each genuine retained local Sale now has a backup-stable `posSaleId` and
  monotonic lifecycle revision. Full (never realtime) manager snapshots upload
  at most 250 unacknowledged Sale revisions at a time and keep retrying until
  Cloud acknowledges them. Closing remains entirely local/offline: the ledger
  is an asynchronous mirror and an old backend can ignore the additive payload
  without losing the Sale.
- Sale Ledger wire normalization gives non-fiscal/cancelled lifecycle semantics
  precedence over stale retained `collectedNow` and `paymentBreakdown`: it sends
  zero collection and no payments, preserving operational gross and history
  without rewriting Hive. Cancelled wire rows are non-fiscal. Stored collection
  wins only for fiscal, non-cancelled Sales; restored fiscal snapshots retain
  tender while the revenue predicate excludes them. Cloud permits preserved
  non-fiscal advance context with no payment rows; fiscal advances still require
  an exactly matching advance part. Any non-fiscal payment row is rejected.
  Legacy fiscal `split` rows without stored collection derive their balance
  normally: `split` describes tender parts, not a no-collection lifecycle.
- `CloudSale`, `SaleLine`, and `SalePayment` are the durable Venue-scoped Cloud
  financial mirror. Ledger money is `Decimal(18,2)` and crosses the wire as
  fixed two-decimal strings. `(venueId,posSaleId)` is the primary idempotency
  key and `(venueId,closureId)` is the secondary audit/closure link. Frozen
  line names/prices stay transaction truth; nullable POS `menuItemId` and
  `variantId` provide attribution without live-Menu joins or name inference.
  Revision updates mutate only legitimate void/restore lifecycle state, never
  frozen financial snapshots or child rows.
- `SaleLedgerDay` records `COMPLETE`, `PARTIAL`, or
  `LEGACY_SUMMARY_ONLY` provenance and `MATCHED`, `MISMATCH`, `INCOMPLETE`, or
  `LEGACY_ONLY` reconciliation. Close Day plus a fully acknowledged retained
  Sale set is the completeness boundary; Cloud independently compares count
  and revenue before marking a day complete. Aggregate settings never create
  fake Sales. Manager ranges use complete ledger days, non-overlapping legacy
  daily fallback where only summaries exist, and an explicit warning for any
  partial range.
- Tenant-safe Manager endpoints provide exact financial summary, keyset Sale
  history/detail, stable-ID product aggregation, and honest closer attribution.
  Dashboard/Financials use ledger values when complete, preserve operational
  occupancy from its existing source, and surface stale/legacy/partial status.
  A disconnected Venue continues operating locally and Manager catches up on
  the next successful full sync.

## Platform / Admin State

- SaaS Phase 2 adds Inventory, Payroll, Financial Planning, Profitability,
  Manager Reservations and Advanced Audit to the existing entitlement engine.
  Manager consumes effective features; optional POS sections use cached catalog
  keys. Controller and route feature requirements intersect. Existing Manager
  plans/Vankisi retain all previously bundled modules at migration.
- Manual VenueSubscription is separate from operational Venue status. Trial,
  active and manually managed past-due grace allow commercial Cloud access;
  suspended/cancelled deny Manager/Website access. POS critical/offline work and
  Device sync remain independent. Dates do not auto-expire access.
- Platform can create/reset/disable real Manager/Admin Staff with atomic audit,
  PIN-vault and durable Edge writes. Platform-managed rows resist stale POS sync;
  the Phase 2 POS handles revision ordering and retains disabled login identities.
  Upgrade POS before using these access actions. Platform user management supports
  SUPER_ADMIN and SUPPORT_READONLY with server-enforced read-only authority.
  See `docs/SAAS_PHASE2_CONTROL_PLANE.md` for policy, tests and deployment order.

- Platform Admin can manage Organizations, Venues, plan assignment, feature
  overrides, WebsiteMode, domains, Devices, credentials, enrollment codes, and
  platform audit records. It can issue a fixed `NOOP` connection test.
- Device credentials and enrollment codes are one-time values; verifier hashes
  are never returned by normal reads.
- SaaS Phase 3 adds a limited CustomerAccount owner portal, separate from
  PlatformUser/Staff/WebsiteUser. Pilot signup is closed until Platform selects
  an active trial plan and enables it. Owners create their own restaurant,
  Manager access and POS enrollment; email remains explicitly unverified.
- POS/Manager use fixed product entrypoints and isolated native build metadata.
  Manager supports Windows/macOS/Android/iOS; POS is Windows only. New builds
  use VYNIC_ENV/VYNIC_API_URL, ship no .env and read no shared POS sync key.
  Manager never initializes POS persistence/printing/ingest/sync.
- Device printer config is Cloud-authored, Device-authenticated pull and durable
  local cache. The owner portal configures printers without a developer token.
  First successful full sync records Device.firstSyncAt for onboarding readiness.
  See `docs/SAAS_BUILD_RUNTIME_ONBOARDING.md` for commands, rollout and limits.
- Venue Policy is documented in `docs/VENUE_POLICY_PLAN.md` but not implemented.
  Current operational switches/settings remain local to the POS.
- Custom restaurant roles/permissions, SaaS billing, and per-Venue
  payment integration configuration do not exist.

## Website State

- Public APIs resolve registered hostnames through `VenueDomain`; production
  fails closed for unknown or disabled hosts.
- `WebsiteUser` remains global; each `WebsiteReservation` is Venue-owned.
- Payment callbacks derive Venue from the server-owned reservation.
- The Vankisi site remains `CUSTOM`. The generic data-driven `SAAS` restaurant
  frontend and custom-site runtime/deployment control are not implemented.
- The current process-wide BOG merchant integration belongs to the custom
  Vankisi deployment, not the unbuilt SaaS website product. It is not a SaaS
  tenancy template. Future SaaS operational work follows Website -> Cloud ->
  durable Venue command -> Edge -> POS; payment callbacks and merchant authority
  remain Cloud-side and website payments do not move through Go Edge.

## Current Transport and Sync State

- POS -> Cloud snapshot ingestion remains Edge-initiated and is not gated by a
  commercial feature. Phase 0 admits only `Venue.activeOperationalDeviceId` for
  authoritative snapshots, audit and sale-consumption intents. HTTP writes and
  replacement serialize under one Venue lock/transaction; success broadcasts
  follow commit. The primary alone claims untargeted Edge work; secondaries may
  claim only their targeted NOOP diagnostics. No multi-POS coordination exists.
- One Venue + one POS works normally. Multiple enrolled Devices require the
  selected primary as sole operational authority. Migration selects only a sole
  ACTIVE historical Device; multiple historical Devices require operator choice.
  First enrollment selects the first Device transactionally, never on polling.
  Platform replacement is audited, preserves old identity, and holds uncertain
  attempted work for reconciliation. Customers can see primary/secondary roles.
- Legacy shared-key sync/callback fallback remains only for zero-Device Venues.
  Revoking all Devices does not restore that fallback. Local secondary Hive
  operation is not remotely disabled: stop the old POS and restore/verify the
  replacement before switching. This is Cloud containment, not replication.
- Inventory administrative configuration is Cloud-authoritative. An enrolled
  POS pulls a complete Device -> Venue catalog through
  `GET /edge/inventory/catalog` into one atomically replaced Hive value at
  startup, after enrollment, and periodically. Failure leaves the last good
  offline projection intact and never blocks POS startup. Catalog version 5 adds
  a read-only inspection excerpt; version 4
  adds food/beverage classification and supplier links and carries each item's derived `currentStock`, `stockStatus`
  (`NEGATIVE`/`LOW`/`OK`/`NO_MINIMUM`) and `purchaseUnits`. New POS clients request
  catalog v5 for Admin inspection and item-specific keg packaging; older
  clients receive v3-compatible purchase units with all active recipes. The POS keeps exact
  decimal text and Cloud's own low-stock verdict; it never recomputes a balance
  and never posts a Receiving. Receiving and StockMovement stay Cloud
  financial history. The POS backup carries only the catalog's cached inspection
  excerpt (20 movements per item, up to 100 current-business-day receipts and
  derived totals), never an authoritative history ledger. The catalog
  additionally carries the active Menu consumption definitions — both identities (`menuItemId`/`posMenuItemId`,
  `variantId`/`posMenuVariantId`), the recipe `revision` and each component's
  `baseQuantityPerUnit` — for close-time offline snapshots. The POS authors no
  recipe; it multiplies frozen six-decimal per-unit quantities by sold integers using fixed-point
  arithmetic. Recipes ride inside the existing `inventoryCatalog` backup value,
  so no second recipe authority appears, and a pre-Step-3 backup restores with an empty list corrected by the
  next Device pull.
- Reservations now sync into `PosReservation`; Manager and website reads no
  longer make a synchronous LAN call to the POS.
- Audit reports sync incrementally in batches using content revisions and
  acknowledgments. Legacy `fullSync` remains accepted for older POS builds.
- The order of a report's events is a zero-based `sequence` the POS assigns
  when it appends them, not a sort of `timestamp` — a creation event and the
  initial `ADD_ITEM` rows share one instant deliberately. Events are appended
  at the next free sequence and never re-sorted, so a backdated clock, a
  reopen, or a re-close extends the timeline instead of rewriting it.
  `sequence` is serialized in Hive, carried on the wire, and included in the
  revision hash; it survives backup/restore because the backup stores the
  report row verbatim. Backend ingestion writes it straight into
  `AuditEvent.seq` when every event in a report carries one, and falls back to
  array position for an older POS build. `AuditReport.fromMap` numbers a
  report written before sequences existed from its stored array order (stable
  by timestamp), deterministically, so its revision still settles; the numbers
  reach the wire immediately and reach Hive on the report's next write.
  Historical rows are not rewritten eagerly.
- Cloud `AuditEvent` carries a denormalized `venueId`, copied from the parent
  report — that is, from the authenticated Device or Staff — and never from the
  payload. It is not a relation: the report's own foreign key is the tenant
  authority. `AuditReport.orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`,
  `RESERVATION`) is derived at ingestion from the report's own creation event
  and is null when no creation event proves one; `floor` is never used as
  evidence. Both are query metadata; the events remain the semantics.
- `AuditReport` still has no foreign key to `Order`, deliberately: Close Day
  deletes the operational Order row and the report, its events and their
  sequences have to outlive it.
- Audit report deserialization resolves missing times from the record itself,
  never from the clock, and reports are listed once per id. Both are required
  for a revision to settle; without them a report is dirty on every sync.
- Backups carry the audit box's keys (`auditLogKeys`, additive) and restore
  files each row under its canonical key, so a repeated restore updates rows
  instead of duplicating them. Keyless older backups still restore.
- Tables, orders, menu, staff, and `salesHistoryByDate` still use broad snapshot
  payloads; further sync windowing/scaling is deferred.
- The home takeaway panel is Order-backed. `TakeawayTickets.forBusinessDate`
  builds the queue from takeaway orders (`isTakeawayOrder`, the one definition
  of the floor/`TA-` rule), and list, counts, items, totals, status and actions
  all come from `Order`. A takeaway order with no reservation row renders
  completely, including guest name, phone and pickup time when supplied. Those
  three are additive Hive fields on `Order`; local, mobile, remote and Edge
  Takeaway creation/upsert paths populate the values they carry. A legacy
  Reservation lookup remains only as a display fallback when an old Order's
  new fields are empty.
- Routine Order sync sends Takeaway guest/pickup metadata directly from
  `Order`; it does not join the bookkeeping Reservation. Close Day likewise
  derives pending Takeaways from the centralized Order-backed source, excluding
  completed, cancelled, Walk-In and Package Orders.
- New Takeaway Orders no longer create Reservation bookkeeping rows; local,
  mobile, remote and Edge paths are Order-only. Historical `isTakeAway` rows
  remain supported and backup/restore preserves them unchanged.
- New Walk-In and Package Orders likewise no longer create Reservation
  bookkeeping rows. Walk-In remains Order + Table, Package remains package data
  applied to an Order, and only genuine advance-booking flows create new
  Reservation records. Real Reservation activation creates the operational
  Order while preserving and linking the existing booking.
- Reservations are only status-transitioned, never purged, so local reservation
  storage stays deliberately mixed: bookings alongside Walk-In, Package and
  historical Takeaway bookkeeping rows. Nothing rewrites old history, and
  backup/restore preserves all of it verbatim.
- Home refreshes counts, table state and Order-backed cards immediately from
  completed local POS mutations. Close publishes an Order lifecycle event only
  after the local transaction completes; this UI refresh is independent of
  Cloud acknowledgement and the periodic sync scheduler.
- Cloud `PosReservation` is real-advance-bookings-only. The POS projects its box
  through `ReservationClassification.projectForCloud` when it builds a full
  snapshot, and the mirror's existing "the list is the authoritative set"
  contract reconciles previously mirrored bookkeeping rows away. The canonical
  rule is `isTakeAway` or a `notes` prefix of `Order #`; `linkedOrderId` is
  deliberately not part of it, because an activated booking is still a booking
  and close-day nulls that field on past rows. An unclassifiable legacy shape is
  sent, not dropped. Each full snapshot logs a `[ReservationProjection]` count
  line carrying no reservation content.
- The narrower three-clause predicates that do consult `linkedOrderId`
  (`isRealTableBooking`, `isRealPosTableBooking`, the Manager `getReservations`
  filter) answer "is this an un-activated table booking" and are unchanged;
  Cloud consumers now receive an already-clean mirror.
- `ReservationSyncService` still issues one `posReservation.upsert` per record
  sequentially plus one reconciling `deleteMany`, so its cost tracks the number
  of rows sent. Measured before the projection at Vankisi: 2004 records,
  617-685ms, under 10ms of which is enumeration and mapping. `preOrderItems`
  stays on the wire unread by the backend; the POS needs it because the home
  takeaway panel renders and totals from those rows.
- `salesHistoryByDate` and `MenuSyncService` have the same shape: one
  sequential upsert per business day and per menu node.
- A POS edit only marks pending. The single automatic push is a 30-second
  periodic flush, and it sends the full snapshot rather than the realtime fast
  path, so an ordinary edit waits 0-30s and then re-sends menu and history.
- The realtime path is built but unreached: `syncRealtimeToManagerApp()` has no
  caller in `apps/operations`, and the `...Debounced()` helpers that edits do
  call are deliberate no-ops that only mark pending ("manual-first mode"). The
  backend already honours `realtimeOnly`, skipping menu, staff, reservations,
  all-time and per-day history.
- A routine snapshot carries staff identity and role but no PINs. The POS sends
  `pin` only for a member whose credential the backend has not acknowledged, and
  records the acknowledgment in `staff_credential_sync_state`; a server that
  reports `staffNeedingPin` gets those PINs back on the next snapshot. Ingest
  additionally skips bcrypt for a supplied PIN that already matches the vault
  entry of an existing member, so an older POS that still sends every PIN costs
  no re-hashing either. Only a genuine create or PIN change runs bcrypt now.
- Both POS and backend print one `[SyncTiming]` line per sync, from monotonic
  timers, splitting trigger wait / build / encode / network / ingest / audit.

- The Order statuses this system writes are `pending`, `confirmed`, `closed`
  and `cancelled`. `preparing`, `served` and `paid` have no writer and are
  read-only: they stay parseable because historical rows carry them.
- `ORDER_STATUS_UPDATE` no longer forwards arbitrary strings. One rule,
  `RemoteOrderStatusRule` in `core/models/order_status.dart`, decides every
  remote request before anything is written, and both transports share it:
  only `confirmed` and `cancelled` are remotely assignable, `cancelled` is
  delegated to `CancelOrderTransaction` rather than assigned, `closed`/`paid`
  and the legacy `preparing`/`served` are refused (400), a closed or cancelled
  Order is not reopened by a status string (409), a request the Order already
  satisfies is a no-op success, and an unrecognized value is refused and never
  persisted or mapped onto a business state. `OrderRepository.updateOrderStatus`
  refuses an unparseable status outright and stores the canonical spelling, so
  no unreadable status reaches Hive from any caller.

## Known Blockers

- Website reservation availability has no transactional hold; simultaneous
  bookings can still allocate the same table.
- Local POS diagnostics/error-log/restore-wipe remain developer-gated. Customer
  printer setup is available through the owner portal; physical remote test-print
  and real Windows coexistence/hardware validation remain release checks.
- Production Cloud deployment foundations (origins, HTTPS, CORS, runtime
  secrets, hosting, and deployment verification) are not established.
- Full legacy callback retirement depends on real fleet enrollment, not merely
  the existence of enrollment code.

## Deferred Work

- General Restaurant Backoffice, Venue Policy, custom roles/RBAC, Inventory
  historical Sale COGS / realized Gross Profit / Waste / Stocktake / inventory variance / expected
  yield and pour loss, cash management,
  reservation holds, generic SaaS venue web, SaaS billing, and per-Venue
  payment credentials.
- Physical printer-test command, lower-latency Edge long polling, OS
  keychain credential storage and production Venue-local multi-POS authority
  (Phase 2A is shadow/isolated proof only).
- Legacy shared sync key/callback removal after rollout evidence permits it.

## Current Migration Versions

- Prisma migration tip:
  `20260923120000_edge_foundation`.
- Immediately preceding state migrations:
  `20260922120000_operational_primary`,
  `20260919120000_customer_onboarding_runtime`,
  `20260918120000_saas_phase2_control_plane`,
  `20260917120000_receiving_self_purchase`,
  `20260916123000_procurement_request_identity`,
  `20260916120000_inventory_procurement`,
  `20260915120000_manager_login_code`,
  `20260914120000_payroll_day_adjustments`,
  `20260913120000_payroll_obligations`,
  `20260912120000_inventory_step45_catalog_cost`,
  `20260911120000_inventory_step4_sale_consumption`,
  `20260910120000_inventory_step3_menu_consumption`,
  `20260909120000_inventory_step2_receiving`,
  `20260908120000_inventory_step1_core`,
  `20260907120000_cloud_sale_ledger`,
  `20260906140000_complete_menu_identity`,
  `20260906120000_menu_item_pos_identity`,
  `20260905140000_audit_event_log_entity`,
  `20260905090000_audit_event_sequence_tenancy`,
  `20260904120000_audit_closure_semantics`,
  `20260903140000_pos_reservation_mirror`, and
  `20260903120000_audit_report_sync_revision`.
- Flutter Hive database target version: `9` in
  `apps/operations/lib/core/database/hive_migration_service.dart`.
- A migration file in the repository does not prove deployment to any database.

## Important Recent Commits

- `1526db6` — wire the shared POS command module into backend consumers.
- `41cb9af` — remove unused callback operations and freeze the remaining fallback.
- `4c841bd` — complete Step 6C real-command migration and reservation mirror.
- `d3cc1a7` — add acknowledged, incremental audit-report sync.
- `89a38b9` / `f2f25e3` — add POS enrollment UI/client and backend redemption.
- `79ad18f` / `879084a` — implement atomic close/money integrity and Cloud fields.

## Maintenance

- Update this file only when a represented current fact changes. Replace stale
  facts; do not append session notes, dates, or a task history.
- Keep it compact. New detail belongs in task docs or the canonical engineering
  protocol, not here.
