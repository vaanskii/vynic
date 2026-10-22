# INV-02 / INV-04 — Inventory provenance and complete history

The Inventory subset remains receiving, supplier debt/payment records, recipes
and theoretical Sale consumption. This change does not implement full warehouse
Inventory, historical close-time COGS, realized profit or a complete cashflow.
D014/D015 remain the costing and restoration rules.

## INV-02

- Current Stock Item cost/value comes from remaining frozen StockMovements in
  Cloud acceptance order. Recipe cost is a current estimate using the saved
  recipe; it is not historical COGS at POS close time.
- Current values carry `provenance.basis`, `ordering`,
  `historicalCloseTimeCogs: false` and `includesReconstructedHistory`.
  Unknown and negative bases remain provisional; recipe components now preserve
  `PROVISIONAL` instead of describing those cases as missing purchase history.
- Movement details retain exact frozen unit/value strings, valuation sequence,
  effective/business date and server creation date. `valueOrigin` distinguishes
  Cloud acceptance, reconstructed recorded-order values, and restoration of the
  original frozen movement. Subsequent purchases/recipe changes never reprice it.
- Financials explicitly distinguishes fiscal Sale revenue (including applied
  advance), payments collected on those closes, recorded outflows, supplier debt
  and current stock value. Applied advance is not collected again at close.
  The revenue-minus-outflows difference is labelled accordingly, including its
  percentage. Existing legacy response fields remain compatible.
- Payment distribution uses the displayed ledger's collected channels when
  available; an older summary cannot supply contradictory cash/card amounts.
  Existing incomplete-history and stale-data warnings remain visible.
- Profitability projection removes derived valuation and its new sequence/origin
  fields when the Venue lacks that feature.

## INV-04

Authenticated Manager routes (resolved Staff -> Venue, current role/activity,
Manager subscription and Inventory feature) add:

- `GET /mobile/inventory/consumptions/page`
- `GET /mobile/inventory/stock-items/:id/movements`

Both accept `from`, `to`, `cursor`, and `limit` (1–100, default 50).
Consumption also accepts `unmapped=true|false`. Responses contain `items`,
`nextCursor` and `window`. Consumption pages include frozen components/movements
so exports preserve the investigation evidence. Existing array-shaped
`GET /mobile/inventory/consumptions` remains capped at 100 for older clients.
POS inspection remains a clearly labelled bounded offline excerpt.

Cursors bind kind, resolved Venue/Stock Item, filters, creation cutoff and the
last timestamp/ID. The query always enforces the server-owned tenant independently
of the cursor. Dates, range, limits, malformed cursors and changed contexts fail
explicitly. Descending keyset ordering handles tied timestamps without offsets.

`window.recordsCreatedBefore` excludes arrivals after the first request, including
late backdated closes. Refresh opens a new creation window. This is **not an MVCC
snapshot across HTTP requests**: restoration/payment state may reflect a later
request. The response states `CURRENT_AT_EACH_REQUEST`; the UI and CSV explain
this limit. Records accepted in the cutoff's current millisecond appear on a
subsequent refresh, rather than being admitted unpredictably between pages.

Manager uses lazy lists and load-more. A failed continuation keeps displayed rows
and the same cursor for retry. Filter/refresh/disposal/session changes fence stale
results. Stock detail labels its recent 20 rows as an excerpt and opens complete
movement history. Date filters can return to all dates.

Full CSV export independently downloads every page for the selected filters in
one creation window. All pages must succeed before a save/share dialog receives
the file. Repeated cursors, duplicate IDs, changed windows, a legacy truncated
source and cancelled sessions fail; an interrupted retry starts from page one.
CSV carries filters, window and full record JSON (including frozen components),
quotes multiline/user text and prefixes identities to prevent spreadsheet
formula execution. Desktop uses the existing native save dialog; mobile uses
the existing share sheet. No new dependency was added.

## Verification

Exact source hashes, outcome counts, preserved baseline, artifact hashes and
screenshots: `docs/proofs/INV02_INV04_3463ee40_2026-10-08/`.

The new real HTTP/PostgreSQL suite uses only a newly initialized loopback
disposable cluster. It proves late Sale cost (10@10 then 20@13 => frozen issue
12/unit), new-price/recipe restoration at the original value, concurrent retries,
immutable intent, delayed close ACK, provisional/reconstructed provenance, 205
tied records, intervening current/backdated arrivals, tenant/feature/role/activity
denials, and gross 100 / close cash 80 / applied advance 20 / receipt 800 /
payment 300 / debt 500 reconciliation. Payment reversal is exact and idempotent.

Focused Flutter tests cover record 101, interruption/retry, complete 205-row CSV,
stale filters, no partial export, source mismatch, provisional/reconstructed
labels, real Georgian fonts and 320/390/768-pixel layouts. Aggregate tests retain
real Go mTLS/process fixtures and the actual MENU-09 HTTP/PG writer/restart proof.

The existing 53 Inventory PG tests and the 141 Auth/Commercial/MGR-01/Platform/
foundation PG tests are disjoint. The focused Inventory total is 60: those 53
plus 7 new cases. Those 7 also run in the Backend aggregate and must not be
counted twice. Repeated runs are validation, not additional distinct tests.

No live financial/credential data was written, and no deploy, commit, push,
hardware operation or live-service restart occurred in this milestone.
Real user enrollment/registration/login and Windows qualification remain separate
open gates. Existing lint debt and opt-in skipped suites are reported in the proof;
this checkpoint does not claim those checks passed.
