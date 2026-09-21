# Inventory: daily restaurant workflow

Inventory is organized around receiving goods, inspecting stock, maintaining
supplier contacts, editing Menu composition, and settling receipts. The existing
[procurement engine](INVENTORY_PROCUREMENT_REWORK.md) remains authoritative for
quantity, valuation, debt, payment reversal and tenant ownership.

## Navigation and first action

Inventory is a main Manager destination directly beside Financials, with a
Dashboard entry that is available even when no warnings exist. It is no longer
nested inside Management. Main navigation order is Dashboard, Tables, Financials,
Inventory, Reservations, Management. Dashboard and notification links use that
same order.

The shell reserves the measured bottom navigation height (`extendBody: false`)
for every page, including nested scaffolds. Safe areas protect the home indicator.
Composition's final product/variant can scroll fully above the bar and be tapped.
Navigation includes visible labels and a bounded width on larger windows.

Inventory opens with one primary `ახალი მიღება` action and today's posted amount.
The home groups receiving history, current stock and settlement under daily work;
supplier assortment/contacts and Menu composition sit under catalog. Up to three current-day
receipts are secondary. Large windows place work and recent receipts side by side.
Low/negative warnings appear only when needed. The persistent section header
provides a home/back action and a menu containing every destination, without a
second horizontally hidden tab strip.

Existing Inventory numeric deep links remain compatible: stock 0, suppliers 1,
receipts 2, composition 3, home 4 (default), payments 5. Switching Inventory
sections resets vertical scroll. Reactivating either main Manager or Management
tabs resets vertical viewports while preserving loaded state and horizontal
navigation.

## Receiving is the product entry point

1. Select a supplier or `ჩემით / ბაზრიდან`. A single available supplier can be
   prefilled; multiple suppliers require selection.
2. Select the goods actually received. There is no automatic product selection
   and no preloaded list of every supplier product. Existing supplier links only
   affect search ordering; they are not prerequisites for a receipt.
3. If stock is missing, use `ახალი პროდუქტი` inside the same searchable picker.
   The typed name carries forward. Choose food/ingredient or beverage and the
   stock unit: kg, g, L, ml or piece. Optional package/box/keg setup asks how many
   stock units one package contains. The created stock is selected immediately.
4. Enter quantity and price per stock unit, price per package, or the line total.
   Exact previews show converted stock quantity, total and effective unit cost.
5. `შემდეგი · გადახდა` validates the first step and opens a separate payment/review
   step without writing anything. Choose unpaid/full/partial payment. The summary
   shows each stock increase, total, payment now and remaining debt. Returning to
   goods preserves quantities, prices and payment selection. Optional payment due
   dates use a themed date picker.

`მიღების დადასტურება` posts stock. `მონახაზად შენახვა` saves a draft without
stock/payment effects. An untouched blank line is ignored; an incomplete line
must be corrected and at least one valid line is required. Replacing a selected
product clears the old quantity and price rather than applying them to new goods.
Selecting the same product preserves them. Cancelling an extra product picker
leaves no new empty row. Errors and the next/confirm action remain above the
keyboard and outside the scrolling fields.
Dates and optional document numbers remain under a secondary disclosure. A
restaurant business day must be available or explicitly selected.

Product creation uses the existing StockItem request UUID and transaction. The
retry comparison includes the complete normalized packaging set, so a repeated
request creates one stock identity/package set, while changed intent conflicts.
Supplier linkage is not performed by this inline creation endpoint. The older
supplier-items endpoint remains compatible for older clients.

Posting and payment are separate durable transactions. The editor retains retry
identities, locks submitted fields, reloads before retry, and explicitly says
when stock posted but payment recording failed. It does not post again. No bank
transfer is initiated. The current receipt form uses the client's calendar date
for paymentDate and the selected business date for businessDate.

## Suppliers, stock and recovery

Creating a supplier opens its detail immediately. `რას გვაწვდის` contains the
supplier's assortment; `პროდუქტის დამატება` searches existing active stock and
can create missing products inline through the same stock form. Already-linked
products are excluded from selection. An existing StockItem UUID can be shared
by suppliers; this operation creates no receipt, stock movement or Menu recipe.

A failed association keeps the selected/created StockItem for explicit retry;
retrying posts the same idempotent supplier-product link without recreating stock.
Assortment removal is confirmed and removes only the association, preserving
stock and history. Long assortments show five rows with search/show-all controls.

The detail can start the existing receipt editor with its supplier selected;
linked assortment products are prioritized in the receiving picker. Quantities
and prices belong to receiving. It also retains recent receipts and filtered
payment/debt navigation. The old multi-mode Menu-to-stock setup and ingredient-
to-dish shortcut remain absent from supplier navigation.

Stock defaults to active products. `ამოღება სიიდან` asks for confirmation and
moves the product into `არქივი` using existing soft activation. Active Menu usage
is mentioned when available. Archived goods disappear from receiving selection;
`აღდგენა` restores the same UUID. Existing quantities, movements, recipes and
payment history are retained. This is recoverable archive, not physical deletion.
Archiving does not remove an ingredient from an existing recipe or zero stock.

The stock editor maintains name, classification, units, packaging, threshold and
notes. Activity is managed through archive/restore, and supplier linkage is not
edited here. Stock cards display current moving cost, last purchase price,
provisional cost and Menu usage when those read fields are available. The stock
tab links to `ჩამოწერების ისტორია`; individual stock detail retains its movements,
purchase history and reverse Menu usage.

## Menu composition

The shared `InventoryMenuBrowser` opens category tiles, then subcategories, then
products and explicit variants. `InventoryMenuPicker` uses this same component.
Global search can find a dish, drink or variant without navigating every category.
Composition status filters apply after category selection or search. Category
changes start the result list at the top. An item with variants is marked complete
only when every sellable variant has an active definition; partial setup remains
in the unfinished filter. Existing any-configured model semantics remain available
for other readers.

A food Menu product opens ingredients and amounts per sold unit. Kg ingredients
prefer grams when allowed. Beverage composition supports a direct counted product
or a volume such as 0.5 L; multi-ingredient drinks and batch yields retain their
existing editing path. Existing components, yield and revision are preserved.
Missing ingredients may be created from composition through the shared small
form; food receiving never invents a direct one-piece Menu recipe.

## Payments and debt

`SupplierPayablesView` is a separate Inventory destination; contextual links open its
full screen. It has supplier, custom date range/last-30-days/all-dates controls,
and separate debt and payment-history views.

- Debt filters by receipt business date and status: outstanding, overdue,
  partially paid, paid, unverified or all. Current debt is explicitly for all
  dates and the selected supplier. The filtered receipt total is separate.
  Unknown historical settlement is never silently counted as verified debt.
- Payment history filters by paymentDate, including payments made now against
  older receipts. It lists signed payment/reversal events and exact net totals.
  Self purchases are separately selectable as a source group.
- Cancelled receipts with payment history remain in the backend read model,
  carrying `status: CANCELLED`; their payment and refund remain visible while
  the receipt is excluded from debt. Already reversed payments have no second
  reversal action. Historical verification and existing reversal confirmations
  remain available.

All filters apply to the complete existing payables response, not a receipt
pagination window. Filtering does not change financial ledger semantics.

## Validation and rollout

Validation: 179 focused Flutter tests and 102 PostgreSQL Inventory tests pass;
Flutter analyze, backend build and TypeScript checking pass.

Focused Flutter tests cover category/variant selection, no implicit receipt
product, inline packaging creation, archive/restore, vertical tab reset, dated
payment/debt filtering, negative reversal totals, explicit source selection,
receiving retry and existing consumption behavior. Scripted HTTP widget tests
exercise real Manager navigation/serialization; PostgreSQL tests separately prove
stock/payment/tenant effects. Screenshots at 360/390/768/1280 cover the real navigation frame, last Menu product,
dark/large-text home, guided receiving and the existing daily/final flows. The
navigation proofs include a 360×640 window, 34px bottom safe inset, keyboard inset,
return-to-edit and incomplete-variant discovery. See
`test/widget/inventory_navigation_regression_test.dart` in Operations.
Supplier assortment interaction proof is in `test/widget/supplier_assortment_test.dart`,
including auto-open after creation, link/unlink, inline create with ambiguous
link-result retry, receiving priority and dark searchable lists.
The latest shell/flow and assortment changes are Flutter-only; the PostgreSQL results above cover
the unchanged procurement work.

The PostgreSQL Inventory suites include concurrent packaged-stock creation,
changed packaging retry rejection, cross-Venue identity, 10 packs × 10 pieces
received at 1.20 per piece, and cancelled-receipt payment history. No new schema
or migration is introduced. Deploy the updated backend before the Manager so
inline packaging with requestId and cancelled payment history are supported.
The earlier additive self-purchase migration is still a prerequisite for those
sources; no POS upgrade is needed for this UX change.

Known limits: validation uses scripted UI and a disposable database, not a live
restaurant/device fleet. Archive preserves historical stock rather than deleting
it. Large stock/supplier catalogs remain searchable/scrollable; payables filtering
is client-side over the existing complete response. Pending payment intent does
not survive app restart, and drafts do not persist payment choices. Inspect
recorded receipt/payment history before entering a later payment after restart.

Offline POS operation, StockMovement valuation, Sale consumption/restore,
server-owned tenancy and historical records are unchanged.
