# Inventory: daily restaurant workflow

The Manager Inventory destination now starts with today's receiving and stock
state. Supplier setup and Menu composition remain secondary management tasks.
The procurement rework remains the accounting baseline; see
[Inventory Procurement Rework](INVENTORY_PROCUREMENT_REWORK.md).

## Why the previous interface was confusing

Four equally prominent sections made internal objects look like four mandatory
setup stages. Receiving put document metadata ahead of goods, draft/post wording
required interpretation, and paying required another dialog. The recipe editor
presented a mode choice before the manager could enter a dish's ingredients.
Some controls inherited colors independently of the Manager appearance setting.

## Daily entry and information hierarchy

- `მარაგი` opens with one primary `ახალი მიღება` action.
- Today's received amount includes posted receipts only. Low/negative counts use
  the existing server stock status and active items. Attention items appear first.
- Today's documents explicitly say `მარაგში ჯერ არ დამატებულა` or
  `მარაგში დაემატა`. The home queries the current restaurant business day, so
  pagination or future documents cannot displace that day's information.
- Searchable stock cards say `მარაგშია`. History, suppliers, Menu composition,
  payments/debt, and consumption history remain accessible below the daily work.
- Existing numbered deep links remain compatible: stock 0, suppliers 1,
  receiving 2, composition 3. Default navigation opens home (4).

## Supplier and goods setup

Supplier cards offer `საქონლის დამატება` directly, without opening detail first.
The same action remains in supplier detail. The form starts with explicit choices:
`ნედლეული`, `მზა პროდუქტი`, and `ჩამოსასხმელი სასმელი`, with restaurant examples.
No Menu item is selected by default. Save stays visible below the scrollable form.

Ready-made products open a dedicated Menu browser with name/category search,
category filters, and explicit variant rows. Choosing a packaged Menu product uses
the existing atomic supplier-items API: create/reuse an inventory identity and
direct consumption mapping, then record packaging such as 10 pieces per pack.
Menu and stock identities remain separate. Existing counted stock can be chosen
through a searchable picker. Existing non-direct recipes are not overwritten.

Ingredient and bulk modes search existing goods before creating a new identity;
creation carries the typed search name forward. An existing ingredient can belong
to several suppliers; receipts affect the same quantity and moving value. Bulk
beverages retain liters and item-specific keg packaging. Creating or reusing beef
sends no Menu identity and does not create a one-piece khinkali mapping.

Each supplied good has `გამოყენება კერძში`: choose a dish and variant in the Menu
browser, then edit its composition with that ingredient included. Existing
components, quantities and batch yield remain loaded; an already-present ingredient
is not duplicated. New ingredients start with an empty quantity (grams for kg
ingredients), requiring the manager to enter the real amount. Failed recipe loads
block saving and offer retry. This flow does not require changing Inventory tabs.

Inventory themes explicitly set popup canvas colors alongside surface and text
colors. Supplier choices, ingredient search, Menu categories and save controls have
responsive widget coverage at 360, 768 and 1280 pixels, plus dark-theme inspection.

## Receiving and payment

Supplier selection preloads its usual goods and packaging. Unentered usual lines
are omitted when saving; a half-filled or invalid line must be corrected. At
least one valid line is required. Goods can also be selected from existing stock,
and a missing ingredient can be created inline.

The form supports price per stock unit, price per package, or a whole-line total.
Exact fixed-point previews show converted quantity, line amount and effective
unit cost. Document dates/numbers are under a secondary disclosure. A current
business day must be available or explicitly selected.

`მიღების დადასტურება` posts stock. `მონახაზად შენახვა` saves working data with
no stock or payment effects. Unpaid/full/partial payment choices are on the same
form, including amount remaining and cash/bank method. The current flow records
payment on the client's current calendar date and the selected business date.
Later or historical payments remain available in the payment history flow.

Posting and payment are **separate durable transactions**, using the existing
endpoints. The form retains request IDs and locks submitted values while retrying.
If posting succeeds but payment fails, it explicitly reports that stock was added
and offers payment retry. It reloads the receipt before retrying and does not post
it again. The same payment UUID prevents duplicate partial payment. Closing the
receiving flow refreshes the home. No bank transfer is initiated.

## Market / self purchase: additive domain change

Receiving accepts `sourceType: SUPPLIER | SELF_PURCHASE` (default SUPPLIER).
SELF_PURCHASE has a null supplier FK and optional `sourceLabel` (maximum 200
characters). The label is stored in the existing immutable name snapshot; the
fallback is `ჩემით / ბაზრიდან`. No Supplier is created. Posted snapshots cannot
be edited. Self-purchase payments use the same SupplierPayment ledger, with a
Receiving audit target when there is no Supplier.

Migration `20260917120000_receiving_self_purchase` makes the existing supplier FK
nullable, adds the source type and adds a check coupling source type to supplier
presence. Existing documents remain SUPPLIER. Foreign keys, lines, movements,
valuation, payment constraints and tenancy remain intact.

Inline ingredient creation accepts an optional UUID requestId backed by the
existing StockItem creation request key. Concurrent/repeated creation returns one
identity; changed values with that key conflict. This simple endpoint does not
combine requestId with supplier/packaging setup; that work uses the existing
atomic supplier-items endpoint. Ingredient detail also returns linked supplier
names, scoped through its existing Venue-safe supplier relations.

## Menu composition

The existing Menu is searchable and filterable by dishes/drinks. A dish opens its
ingredients directly, normally per one sold unit. Grams are preferred when the
item advertises them. Batch yield stays available under a disclosure and existing
batch quantities are preserved. Ingredient search selects existing stock; inline
creation uses a small name/unit form and returns to the current composition.

Packaged and draft drinks open as one stock quantity: one piece or, for example,
0.500 liters. An explicit secondary action permits multi-ingredient drinks;
switching mode never silently discards existing components. Cost context follows
the editable quantities. Reverse ingredient usage shows kitchen-friendly grams
for kilogram stock and lists linked suppliers.

## Visual and responsive behavior

The existing Manager palette controls surfaces, text, borders, chips and actions.
The foreground on a colored action is chosen from the existing neutrals according
to luminance; the lighter dark-mode blue cannot use white normal-size text.

Spacing uses the existing 8/12/16/24 rhythm. Phone content stays vertical, with
48px minimum controls and a full-width receiving confirmation. Wider layouts use
summary columns and bounded dialog widths. Management screens keep secondary
navigation and actions visually distinct from the daily primary action.

## Verification

- Backend: 10 focused Inventory suites / 101 tests, including existing Borjomi,
  beef/khinkali, keg, moving average, restore, tenant and payment proofs.
- New domain proofs cover self-purchase without a Supplier, immutable source,
  shared stock across two suppliers, partial payment retry, inline ingredient
  retry, and one ingredient used by multiple Menu products.
- Prisma: all 34 migrations from an empty disposable PostgreSQL 17 database,
  schema validation and empty migrate diff. Backend TypeScript and build pass.
- Flutter widget tests capture home, supplier detail, Receiving, Menu composition,
  dish, packaged-drink and draft-drink editors at 360/768/1280, plus payment and
  dark-theme views. The dark appearance test checks action/surface contrast.
- Interaction tests cover partial payment in receiving, market draft with no
  payment write, ingredient search, and a lost payment response after stock posts.
- Focused Flutter Inventory/POS consumption regressions: 104 tests passed;
  Flutter analyzer reported no issues.
- Screenshot artifacts are generated under `/tmp/procurement-ux-*.png` by
  `test/widget/inventory_daily_ux_test.dart` and visually reviewed.
- No live `vankisi_database`, deployed service, POS Hive data, push or banking
  action is involved in validation.

## Rollout and boundaries

Apply the additive migration, deploy the backend, then the Manager. No POS
upgrade is required for the workflow. Older Manager versions should not edit
self-purchase drafts; they have no source-choice control. Retain the schema and
historical source/payment data on rollback. An old backend requiring a supplier
on every receipt is not suitable once self-purchase has been adopted.

The UI has been verified with widget screenshots, not a real restaurant service
or device fleet. Long supplier catalogs and long compositions remain scrollable.
There is no automatic matching by ingredient name; reuse is explicit. There is
no persisted pending-payment intent across an app restart: check the durable
Receiving/payment history before recording a later payment. Drafts do not persist
payment choices. Full payment reversals, legacy settlement verification and
Cloud acceptance-time valuation retain the procurement baseline's limitations.

No StockMovement valuation algorithm, Sale consumption materialization, restore
reversal, recipe revision history, offline checkout, or tenant authority was
rewritten. There is no GL, FIFO, waste, stocktake, bank integration or deployment.
