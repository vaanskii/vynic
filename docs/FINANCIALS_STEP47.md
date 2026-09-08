# Step 4.7 — Staff payroll and recurring financial obligations

## Existing salary classification and preservation

The old Manager `FinancialsScreen` salary planner held an in-memory list of
free-text names and double amounts. Applying selected rows called
`MobileApiService.createExpense(category: 'პერსონალი')` once per name.
There was no Salary table, Staff foreign key, persisted compensation setting,
attendance record, or trustworthy worked-hours source. Payment history was the
shared Cloud `pos.Expense` table and POS Hive `expenseBox`. Staff itself had no
salary fields. Financials, Manager reports and POS Expense/report readers consumed
those generic records; there was no reliable employee or payroll-period identity.

Classification: **LEGACY_UNMAPPED_READ_ONLY**. Category aliases are `პერსონალი`,
`ხელფასი`, `ხელფასები`, `salary`, `salaries`, with trim/case normalization.
No historical record is deleted, converted, relinked by name, or copied into new
PayrollPayment rows. Legacy salary Expense rows remain included exactly once in
financial outflows and have a dedicated read-only history in Payroll. New Manager
salary-category Expense writes and deletion of legacy salary rows are refused.
The old transient salary planner is removed; ordinary Expense remains available.
Older POS snapshots/backup history stay compatible.

Whether genuine historical rows exist in the restaurant database is **unverified**:
`vankisi_database` was explicitly excluded from all access, including read-only
inspection. Repository code proves the historical storage shape, not production
row counts. Preservation is unconditional, so deployment does not depend on an
assumption that this table is empty. There is no destructive migration or backfill.

## Compensation and payroll periods

Cloud owns these Manager financial records, independently of live POS operation.
`StaffCompensation` is Venue/Staff scoped, with exact Decimal(18,2) amount, type,
effectiveFrom, isActive, notes and actor. Supported types are MONTHLY_FIXED,
DAILY_FIXED and MANUAL. HOURLY is refused: repository attendance/hours are not a
trustworthy source. Dates are validated Gregorian labels in 2000–2099.

Rules become effective on the first day of a selected month; there is no implicit
proration. Set the first rule from the intended first payable month. Changing a
rule freezes all elapsed/open months first. A future rule can be amended before
any corresponding period is opened, with a Global Audit event; identical retries
write no additional audit. Earlier effective dates and already opened period
changes are refused. Later versions naturally bound the prior rule's effective
interval; there is no mutable effectiveTo column.

`PayrollPeriod` freezes Staff name, type, rate and monthly target. It is unique by
Venue + Staff + periodMonth. Monthly expected equals the frozen monthly salary.
Daily expected starts at zero: every explicit, unique payableDate in that month
adds one frozen daily rate through an append-only PayrollAccrual. MANUAL expected
starts at zero and grows through explicit exact-amount accruals. Neither accruals
nor compensation settings count as financial outflows.

PayrollPayment references that durable period, which owns Staff identity and
periodMonth; those values need not be duplicated inconsistently on the payment.
Every payment preserves exact amount, businessDate, paymentDate, notes, actor and
createdAt. Expected, paid, remaining and overpaid are derived; payment history is
never replaced by a total. Overpayment is allowed and explicitly displayed.
The UI retains one UUID across failed payment/accrual retries. Same UUID/same
content returns the recorded entry; changed content conflicts.

Staff deletion/reconciliation preserves payroll-referenced Staff rows by setting
isActive=false; foreign keys also restrict deletion. Unreferenced Staff deletion
keeps its previous behavior. Removing a login **does not terminate a compensation
agreement**: retained Staff remain available in Payroll to settle history or set
an inactive future compensation rule. Existing compensation stays payable until
that explicit rule stops it. No PIN, PIN hash or vault content is selected by the
new payroll services or screens.

## Obligation templates and monthly cycles

FinancialObligation has a user-defined name and the small RENT/BANK_LOAN/LEASE/
UTILITY/OTHER enum. Monthly amount uses Decimal(18,2). Due day is 1–31, with
startsOn, optional endsOn, active state and notes. StartsOn is immutable after
creation. UI creation carries a UUID so retries cannot create a second template.

ObligationCycle freezes name, type, target and due date per Venue + obligation +
month. The due day clamps to the last actual day of a short month, including leap
years. A cycle is due only when its dueDate is within startsOn/endsOn. Templates
starting after that month's due day first contribute in the following month.

Cycles materialize lazily through the current Venue calendar month, including
missed months. Before a template edit/disable, its current configuration
materializes through the current month under a row lock. Configuration changes
then apply to future months; September does not change with October's settings.
`materializedThrough` records both generated and intentionally inactive months,
so reactivation cannot invent targets during the disabled gap. Existing open
cycles remain payable/reservable after template disable. Status is derived:
PAID, OVERDUE, or OPEN; no daily status/audit writer is needed.

## Reserve and payment rules

Every reserve is an append-only ObligationReserveEntry with exact amount,
businessDate, notes and actor. It is planning, never Expense or actual outflow.
Every ObligationPayment is a separate actual payment, with paymentDate,
businessDate, actor, amount and a frozen reserveConsumed amount.

Under a cycle row lock:

- available reserve = SUM(reserves) − SUM(payment.reserveConsumed)
- paid = SUM(payments)
- covered = available reserve + paid
- remaining to cover = MAX(0, target − covered)
- remaining to pay = MAX(0, target − paid)
- payment.reserveConsumed = MIN(payment amount, available reserve)

Reserve entries may not exceed remaining to cover; payments may not exceed
remaining to pay. Concurrent entries serialize, and retries write once. A reserve
of 600 followed by a payment of 500 leaves 100 reserved and 500 paid: still 600
covered, not 1,100. Fully funding a cycle does not mark it paid.

Daily recommendation divides remaining to cover by the number of calendar days
**including today and the due day**. A due/overdue target uses one day. The result
rounds upward to whole cents using Decimal; no float money is used. On September
11, September 30 is 20 inclusive days away: (3000 − 600) / 20 = 120.00 GEL/day.
A 1.00 target over three days recommends 0.34, and actual reserves remain capped
by the exact remaining target. Current Venue calendar date determines planning;
restaurant businessDate independently labels contributions/payments.

## Financials, Dashboard and Manager UX

Financials distinguishes Revenue, POSTED Receiving purchases, Other Expenses,
Payroll and Monthly Obligations. Actual daily aggregation is:

`POSTED business-day Receiving + other Expenses + legacy salary Expenses + PayrollPayment + ObligationPayment`

Each source enters once. Receiving retains Step 4.6 recognition by business date,
not an unimplemented supplier cash-payment date. `salaryPayments` remains a
compatibility sum of legacy plus new payroll; separate legacySalaryPayments and
payrollPayments expose the components. `expenses` retains the legacy general
Expense total for older readers. Neither reserves nor accruals create Expense or
Edge commands. Financials honors explicit Expense.businessDate, falling back to
timestamp only for old rows with an empty businessDate. Exact revenue/difference
strings supplement the legacy numeric API; new outflow amounts render directly
from exact text. Existing chart proportions are presentation only.

Payroll supports monthly selection, expandable Staff detail, compensation rules,
explicit day/manual accrual, recording payment, and full payment history.
Obligations support monthly selection, templates, due/overdue/paid state, available
reserve, paid amount, remaining funding/payment, daily recommendation, reserve,
payment, history and editing. Financial periods and payment/business dates are
separate visible fields. Payment copy says this records an already performed
payment; the application transfers no money.

Dashboard adds one restrained planning card: remaining payroll, remaining
obligations and total daily recommended reserve, with at most three recommendation
lines. Totals include older outstanding cycles as well as the current month.
Deep links open the corresponding Financials destination; previous months remain
selectable there. Failed loads and refreshes are explicit. No silent cached
finance mutation, optimistic success or automatic payment exists.

The screens reuse Step 4.6's spacing, bounded list layout and minimum 48px controls.
Georgian labels dominate; IDs, source enums and credentials do not appear in normal
flows. Forms scroll, actions wrap, and the obligation title can span two lines.
Payment retries retain input and identity. QA renders live widgets at 360, 768 and
1280px; screenshots under `/tmp/vynic47-qa` are local artifacts, not application
assets.

## Business date, Close Day, tenancy and Audit

The date convention is the existing Venue timezone plus Venue-owned
currentBusinessDate setting, with calendar-date fallback before first sync.
Payroll periodMonth and obligation periodMonth are independent of payment's
businessDate and paymentDate. Close Day remains a POS operation and has no writer,
deleter or automatic settlement path for these Cloud tables. POS offline operation
and local day-close/report storage are unchanged. New payroll/obligation outflows
are presently Manager/Cloud financial history, not a new offline POS report feed.

All routes are under `/mobile/finance`, guarded by the existing Manager JWT, role
and MANAGER_APP guard. There is **no new feature entitlement**. Server-resolved
Staff -> Venue supplies scope; input venueId cannot override it. Every ID lookup
and aggregate is Venue-scoped, and composite foreign keys enforce that a period,
Staff, reserve or payment cannot be attached across Venues.

Global Audit writes in the same transaction as the mutation with stable entity
IDs: STAFF_COMPENSATION_CHANGED, PAYROLL_ACCRUAL_RECORDED,
PAYROLL_PAYMENT_RECORDED, FINANCIAL_OBLIGATION_CREATED/UPDATED/DISABLED,
OBLIGATION_RESERVE_RECORDED, OBLIGATION_PAYMENT_RECORDED. The existing audit feed,
entity filters and Georgian action labels support these actions. Derived planning
and repeated reads write no audit events.

## Migration, validation and deployment

Additive migration: `20260913120000_payroll_obligations`. It adds eight finance
tables, two enums and tenant-safe relationships. It neither changes old Expense
amounts nor updates/deletes historical data. No generated wire contract or Hive
migration is needed.

Validation result: **636 backend tests passed** (59 suites; one existing skipped
test), **405 Flutter tests passed** in the widget/money/audit/inventory run. The
final finance-only rerun passed all 16 tests after the title polish. Full Flutter
analyze reported no issues; backend build and `npx tsc --noEmit` passed.

Validation uses a new `/tmp/vynic47-pg` PostgreSQL cluster on port 55447 and
`vynic_step47_test`. All 29 migrations apply from empty; Prisma validate and migrate
diff pass with no difference. Backend tests include real PostgreSQL money,
concurrency, snapshot rollover, tenant isolation, Global Audit feed, Staff
retention and financial composition. Flutter/widget tests include payment retry,
no inferred attendance, history, loading/error/empty states, actual deep-link
navigation, touch sizes and all three required widths. Backend build, TypeScript,
full Flutter analyze and diff checks are part of validation.

Deployment order: back up using the established deployment process, apply the
additive migration and generate the Prisma client, deploy backend, then deploy
Manager. Deploying Manager before backend would leave new finance actions
unavailable. Old Manager salary-category writes are intentionally refused after
backend rollout, so coordinate the Manager update. No production deployment,
remote push or database access was performed during implementation.

## Limits and next boundary

- Historical production salary existence/count remains unverified and preserved.
- No inferred attendance, hourly wages, partial-month proration, automatic salary
  accrual from shifts or retroactive editing of frozen periods.
- Entries are immutable. A general reversal/refund/correction workflow is not
  part of this step; mistakes cannot be silently edited or deleted.
- Finance history reads currently return the selected Venue's full requested
  history; keyset pagination/batched monthly materialization is a future scaling
  improvement. New finance mutations require Cloud connectivity.
- No bank transfers, automatic payments, GL, tax accounting, COGS, realized Gross
  Profit, Waste or Stocktake.
- Obligations have a dedicated service and separate Manager destination. A later
  entitlement can gate that route/UI boundary without entering domain arithmetic.
  No entitlement key, Platform Admin toggle or domain entitlement branch is added.

Stop after Step 4.7. Platform Entitlements is the next separately requested step.
