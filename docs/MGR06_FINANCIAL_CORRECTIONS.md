# MGR-06 — Immutable financial-entry corrections

Manager can correct an incorrectly recorded payroll payment, obligation payment
or obligation reserve by appending one linked full negative reversal. The
original row, its notes, dates and actor remain unchanged. A replacement amount
is recorded separately through the existing positive entry form, after correcting
the mistaken entry. No bank transaction or physical refund is executed.

## Authority and dates

The existing authenticated current Manager Staff -> Venue authority and
MANAGER_APP plus PAYROLL/FINANCIAL_PLANNING feature guards apply to fresh requests
and retained retries. Platform accounts and supplied tenant IDs grant no access.
The request contains only a UUID and required trimmed reason (1–1000 characters).
The server derives amount, original, parent, Venue, actor and dates.

The reversal inherits the original business date and, for payments, payment date.
Signed net amounts therefore reconcile the original historical payroll period,
obligation cycle and business-date outflows. Reserves never become outflows.
`correctionBusinessDate` uses the current server-owned Venue business date;
`createdAt` records correction chronology. History labels both separately.

## Endpoints and transaction behavior

- `POST /mobile/finance/payroll/:id/payments/:entryId/reversal` requires PAYROLL.
- `POST /mobile/finance/cycles/:id/payments/:entryId/reversal` requires FINANCIAL_PLANNING.
- `POST /mobile/finance/cycles/:id/reserves/:entryId/reversal` requires FINANCIAL_PLANNING.

Body: `{ "id": "<UUID v4>", "reason": "<correction reason>" }`.
A successful response is the committed signed linked row; failure remains an
explicit HTTP error. Finance completion belongs to the Cloud transaction.
POS operations keep their existing POS-confirmed completion semantics.

Existing payroll-period or obligation-cycle row locks serialize positive entries
and reversals. The signed reversal and its Global Audit event commit together.
One original accepts at most one reversal, and reversal rows cannot be reversed.
Same-Venue/parent composite foreign keys, unique links, correction-shape checks
and insert validation supplement service guards. Decimal amounts remain exact.

An obligation-payment reversal negates both amount and its original
`reserveConsumed`, restoring that allocation to the reserve pool. Fresh reserve
reversal is refused while signed net reserve consumption in the cycle is nonzero,
even if remaining pooled reserves cover that particular entry. There is no
per-entry allocation evidence permitting safe reallocation. Correct the relevant
payment records first; there is no automatic allocation rewrite.

Exact retained UUID/target/reason replay returns the original result before
fresh business-date or reserve-consumption guards. A later day change or later
consumption cannot change or reject an already accepted result. Conflicting
identity reuse returns HTTP 409. Authorization is rechecked on every request.

## Manager history and recovery

Positive entries expose the original amount/dates/actor, eligibility and any
consumption block. Corrected originals and negative rows display their link,
reason, actor and correction chronology. Legacy expense history is read only.

The reason, target, original snapshot and UUID are flushed to a dedicated Hive
box before HTTP. Requests are scoped to API origin, Staff principal and Venue
namespace; no credential is stored. A reopened form recovers the same frozen
reason/UUID. A lost response retains an explicit unconfirmed state and a resume
action even after refreshed history shows the original already reversed.
Concurrent identical taps share a submission; changed reasons cannot replace it.
Known completion requires a valid linked signed receipt and a successful receipt
flush, including when returning an in-memory receipt from a previous failed flush.
History reads, displayed selection and POST completion fence session/origin
changes. A changed session requires reloading history before any correction.

Storage corruption/failure, malformed 2xx receipts, connection loss and server
rejection never report saved success. Retry uses the retained identity. An
unconfirmed correction should be checked in current history and retried with that
same identity; do not insert a replacement until the correction is confirmed.

## Migration and qualification

`20261007170000_finance_entry_corrections` is additive: nullable link/date columns,
indexes, foreign keys and reversal validation. No old migration or original row
is rewritten. Existing positive and zero legacy rows retain all previous fields.
Deploy the migration and generate the Prisma client before the backend, then
update Manager. A rollback to the old backend must retain this migration and its
rows: old signed aggregates still include corrections, while old UI has no new
action. Do not delete negative entries or drop populated columns to roll back.

`apps/backend/tool/prove_mgr06_postgres.py` creates and removes its own synthetic
loopback PostgreSQL cluster. It runs actual HTTP/JWT/feature/tenant/transaction
and concurrency cases plus existing finance regressions. A second database
replays all unchanged previous migrations, seeds historical finance/audit rows,
then applies the additive migration and checks every original field before and
after PostgreSQL restart. Prisma drift is checked against the resulting database.

Client tests exercise retained identities, storage put/flush fault boundaries,
response validation, account/Venue/origin isolation and captured HTTP sessions.
Widget tests cover history, lost-response reopen/resume, required frozen reasons,
changed displayed sessions, consumed blocks and small/large text at phone,
tablet and desktop widths. Existing Manager/POS regressions, static checks and
macOS development builds are qualified from clean Git source without user WIP.
Final exact-source receipts accompany the milestone proof under `docs/proofs/`.

No live financial record, bank action, customer restaurant, production database,
push or deployment is involved in these proofs. Windows VM work remains HELD;
physical printer/driver/paper acceptance remains NOT_DONE/deferred under POS-02.
Those release gates are separate from this Cloud/Manager correction milestone.
