# Retained non-fiscal Sale wire compatibility

## Captured evidence

Read-only file copies of the local macOS POS `sales.hive` and `auditlog.hive`
were opened in a temporary Hive directory. No live Hive file or Vankisi database
was opened for writes. The copy contained 1,717 records (332 non-fiscal/cancelled
Sale records); its copied ACK state selected 250 rows, not the reported 54-row
batch. Consequently this proves an offending retained shape, not the identity
of the currently deployed request or a successful live retry.

The single retained non-fiscal Sale observed emitting positive current tender:

| Field | Retained value | Previous wire | Fixed wire |
| --- | --- | --- | --- |
| Hive key | `1693` | — | — |
| posSaleId | `88fe2803-d7ff-4b95-99cd-7a3ab902cca1` | preserved | preserved |
| orderId | `1764` | preserved | preserved |
| closureId | `ac74dba1-cc90-4e3c-8963-8577b1696292` | preserved | preserved |
| paymentMethod | `non-fiscal` | preserved | preserved |
| isFiscal | false | false | false |
| isCancelled | false | false | false |
| restoredToOrder | false | false | false |
| gross | 176.00 | 176.00 | 176.00 |
| advanceApplied | 0.00 | 0.00 | 0.00 |
| collectedNow | 176.00 | 176.00 | 0.00 |
| paymentBreakdown / payments | `{cash: 176.00}` | cash 176.00 | empty |

Business date is `2026-06-22`; subtotal is 160.00 and service fee is 16.00.
The linked report `audit_report_order_1764` ends with legacy type `CANCEL_TABLE`
and note `Order closed (non-fiscal)`. This establishes a historical internal
close, before the corrected `INTERNAL_CLOSE` audit semantics, rather than a
cancelled Sale or an inferred manual row. The Sale's cancellation flag is false.

`test/fixtures/retained_non_fiscal_sale.json` preserves its complete retained
shape, money, lines, dates and closure identity. Staff identifiers/names alone
are replaced with fixture actors. The corresponding wire fixture is asserted
against the actual Dart builder and consumed by the backend integration test.

## Rule and scope

At the ledger wire boundary, `!isFiscal || isCancelled` means zero collection,
no payment rows, and no revenue. Cancelled wire rows are non-fiscal. Stored
`collectedNow` wins **only when lifecycle semantics permit tender collection**.
The raw `ClosureMoney` reader remains lossless for existing local consumers.
Hive history, operational gross, advance identity and actor/context fields are
not rewritten. Restored fiscal history retains its frozen tender; restoration
continues to exclude it from revenue.

The previous fix filtered sentinel tender names and zeroed only the missing-field
fallback. This row has an explicit stored collection and a valid `cash` key,
so both bypassed that protection. The previous test even required the raw reader
to believe a stored collection on a cancelled record; it now explicitly
distinguishes raw history from ledger wire semantics.

## Verification and limits

- The captured pre-fix cash payload produces HTTP 400 with exactly
  `Non-fiscal Sales cannot collect tender` in a Nest HTTP harness calling the
  real ingest service against disposable PostgreSQL.
- The normalized captured row plus a six-Sale Dart snapshot produces HTTP 201
  and seven durable Cloud Sales. The six are cash, card, split, current and
  legacy cancellations, and a stale non-fiscal close. Their revenue is 36.00;
  the captured internal close contributes zero. This harness does not exercise
  production authentication or unrelated Manager snapshot services.
- Direct non-fiscal collection of 10.00 with cash 10.00 remains rejected.
- Fiscal cash/card/TBC/BOG, split, advance plus final tender, restored fiscal,
  current cancellation and missing-money-field legacy cases remain covered.
- Revenue remains `isFiscal && !isCancelled && !restoredToOrder`.

## Advance and full-history follow-up

The next observed 400 was `Advance payment part must equal advanceApplied`.
The full local copy contains 38 non-fiscal Sale records with nonzero advances,
including legacy `paymentMethod=advance` records (Order 948: gross 50.00,
legacy advanceAmount 50.00, no stored collectedNow). The wire preserves the
advance identity and gross while sending no payments. Requiring a payment row
for these records contradicts the non-fiscal no-payment contract.

Cloud now requires an exactly matching advance payment part only for fiscal
Sales. Non-fiscal Sales must have zero collection and no payment rows at all,
including no advance payment row. The gross = advance + due identity stays
strict for both. A previously collected advance remains historical context,
not newly collected tender. No schema or retained-Hive rewrite is necessary.

Full-history validation also exposed 33 legacy fiscal split Sales without
`collectedNow`: `ClosureMoney.collectedNothing` mistakenly treated `split` as
proof that no money changed hands. Order 250 retained gross 133.10, TBC 118.00
and cash 15.10. The fallback now distinguishes cancellation/non-fiscal lifecycle
markers from the `split` header, preserving those real tender parts. Explicit
stored collection still wins for fiscal history.

All 1,715 retained Sale payloads from the copy pass backend validation and
full disposable-PostgreSQL ingestion, with 1,715 acknowledgments. The actual
`vynic-pos` client was rebuilt and connected to `http://127.0.0.1:3000` using
its saved override. Eight consecutive full syncs succeeded, including the
follow-up batches, and the POS displayed its green synchronized indicator.
The final copied ACK state contained 1,715 acknowledged Sales and zero pending.
The Manager development command also resolved the same localhost backend.

The opt-in `local_retained_snapshot_test.dart` copies the supplied Hive file
before opening it and exports all Sale payloads without using or modifying live
ACK state. Set `POS_RETAINED_SALES_HIVE` to the source file and
`POS_RETAINED_SALES_WIRE_OUTPUT` to a private temporary output path. Feed that
output to `sale-ledger-sync.integration.spec.ts` with the same output variable
and `TENANT_INTEGRATION_DATABASE_URL` pointing **only to disposable PostgreSQL**.
The integration test verifies complete ingestion, exact acknowledgment identity,
and the absence of non-fiscal payment rows. Neither test rewrites source Hive.

Validation: 133 Flutter tests and 93 backend ledger/snapshot/controller tests
passed, including full retained-history coverage. Backend build, TypeScript
`--noEmit`, Flutter analysis and `git diff --check` passed.

No Inventory Step 4, schema, closure/cancellation transaction, or revenue
predicate change is included.
