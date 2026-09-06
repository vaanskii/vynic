# Inventory Step 4.6 — procurement and Inventory UX

Step 4.5 remains the catalog, Receiving, recipe, quantity and current-cost engine.
This phase consolidates its product surfaces. It introduces no new stock writer,
valuation method, Sale COGS, payroll model or accounting ledger.

## One purchasing entry point

The authoritative repository had no separate Market model, table, endpoint or
screen. Its legacy purchasing path was the Financials Expense composer's free
category field, explicitly suggesting `ბაზარი`. The purchasing suggestion is
removed. Known procurement categories (`market`, `ბაზარი`, `მარკეტი`,
`შესყიდვა`, `შესყიდვები`, with case/whitespace normalization) are refused at
Manager Expense creation and the POS Expense repository write boundary with a
message directing the operator to Inventory → daily receiving.

Those obsolete categories are excluded from Manager Financials, Manager sales
reports/daily expense totals and local POS expense readers. The shared Expense
table/Hive box and historical audit records remain intact. No schema field,
migration, production data deletion or backup rewrite is needed: none was
exclusive to Market. Other categories and the existing salary flow continue to
use Expense. Receiving never creates an Expense or an EXPENSE_CREATE command.

## Procurement financial read model

`inventory/procurement-summary.ts` reads only Venue-scoped POSTED Receiving
`documentTotal` values using PostgreSQL aggregation and Decimal strings. DRAFT
and CANCELLED receipts contribute nothing. The date dimension is Receiving's
businessDate, independent of invoice date and posting timestamp:

- Today: the calendar date in the Venue's configured timezone.
- Business day: the current POS business date mirrored in Venue settings,
  falling back to the Venue calendar date before the first sync.
- Month: the current calendar month in that timezone, including every business
  date in the month. A backdated invoice does not move a purchase to that month.

`GET /mobile/financials` adds `procurement`, `otherExpenses`, `salaryPayments`
and `totalOutflows`. It resolves the reporting business date once. Existing
Expense categories `პერსონალი`, `ხელფასი`, `ხელფასები`, `salary` and `salaries`
are salary payments; remaining non-procurement categories are other expenses.
The existing salary composer still writes `პერსონალი`; payroll is unchanged.

`totalOutflows = business-day purchases + other expenses + salary payments`.
The compatibility `expenses` field remains the general Expense total, including
salary records once. Financials uses totalOutflows and labels its subtraction
from sales as a difference, not realized profit. Receiving does not track a
supplier-payment date; the UI explicitly says these purchases follow confirmed
receipts. This is procurement recognition, not a cash-basis payment ledger.
No derived read writes audit events.

## Manager experience

Inventory has products, suppliers, daily receiving and recipes. The selector
uses two columns below 680px of available content width and four above it.
Search and the one primary create action stack below 620px; list content uses
up to 1280px. Filters wrap at natural widths. VynicSpacing supplies the existing
4/8/12/16/24/32 scale. Inventory's scoped Material theme standardizes button
heights (48px minimum), radii and dialog actions without changing other screens.

Product names occupy their own full-width line; quantities and stock alerts are
prominent. Supplier counts, minimum stock and last valid purchase price are
secondary. Packaging appears in detail/forms. The Manager stock list requests
last-price metadata in one query (latest POSTED line per item and unit), using Step 4.5's ordering and frozen base-unit price.

Stock forms use restaurant vocabulary, Georgian labels for every supported
unit, optional supplier links and an explicit `1 package = quantity unit`
relationship. Supplier email remains optional. Supplier detail retains linked
products, add/unlink and recent receiving navigation. Receiving retains supplier
product prioritization, item-specific packaging, independent business/invoice
dates and multiple documents per day. Recipe/direct/draft workflows and exact
costs retain their Step 4.5 behavior.

`InventoryScreen` is the shared destination for Dashboard and Financials. It
accepts a section, stock-status filter and receiving business date. Dashboard's
small Inventory summary refreshes independently, reports load/refresh failure
and links today's purchases, low stock, negative stock and unmapped sold
products. It does not make the rest of Dashboard depend on Inventory requests.

## Offline POS inspection

Only POS Admin's manager sections gain `მარაგები`. No waiter screen changes.
`AdminInventorySection` reads Hive and listens for atomic catalog replacement;
opening a section or item never makes a network request. It shows the catalog
refresh timestamp and explains that displayed values are from that refresh.
It offers classification/search/status filters and read-only item details.

Catalog v5 adds `inspection` to the existing projection:

- Procurement summary and full counts/totals.
- The last 20 movements per Stock Item, with original movement kinds/quantities.
- The latest 100 POSTED receipts for the mirrored current business day; the
  full-day total/count is independent of this display limit.
- Menu and variant mapping status. Active recipe components already in the
  catalog supply each Stock Item's reverse usage.
- Distinct unmapped sold product identities/names over unreversed consumption
  history. This is the frozen status at sale time; configuring a recipe later
  does not rewrite or erase the historical warning. It is not a count of units.

These are bounded recent history excerpts and derived read models, not a second
Receiving or StockMovement ledger. The atomically stored catalog, including its
inspection excerpt, survives Hive reopen and backup/restore. An unsuccessful
pull preserves the last complete snapshot. Older snapshots display missing
inspection data explicitly. The POS has no Receiving/Supplier/Recipe editor.

## Compatibility and deployment

Deploy backend first, then Manager/POS. New POS requests `version=5`; v3/v4
payloads remain compatible and receive no inspection field. An old backend may
return its older catalog to a v5 request; the new UI renders its available stock
and explains that inspection data requires a refresh. The Prisma migration tip
remains `20260912120000_inventory_step45_catalog_cost`.

## Validation

138 backend tests and 168 Flutter tests passed. Backend build and targeted Flutter
analysis passed; `git diff --check` passed.

- PostgreSQL integration: independent dates and Venue boundaries; POSTED-only
  purchases; cancellation/draft exclusion; no automatic Expense; 500 purchases
  + 25 other expenses + 75 salaries = 600 total outflows; rejected Market writes;
  unchanged audit counts; v5 inspection/v4 compatibility and last purchase price.
- Inventory/Receiving/Recipe/consumption and audit backend regression suites.
- Manager rendered at 360, 768 and 1280px; forms, section navigation, touch sizes,
  supplier priority, Georgian labels and no layout exceptions.
- POS Admin after failed network pull and Hive close/reopen; read-only detail,
  movement and recipe usage, projection restore and Admin navigation regression.
- Dashboard summary refresh failure and actual destination/filter navigation;
  Financials purchase/Expense/salary distinction and Receiving deep link.
- Existing Manager financial, POS Admin, money guardrail and audit tests.

QA screenshots are local test artifacts under `/tmp/vynic46-qa`, not repository
assets. The existing disposable PostgreSQL instance on localhost:55445 was used;
`vankisi_database` was not accessed. No schema migration was introduced.

## Next phase boundary

Payroll still uses the existing category-based salary workflow. There are no
monthly obligations, rent, banks, loans, reserves, feature entitlements, waste,
stocktake, realized COGS, historical Sale profit or accounting GL changes.
Procurement is now a separate financial source that a later obligations/payroll
phase can compose without duplicating purchases. Payment scheduling and salary
obligation identities still need their own design.
