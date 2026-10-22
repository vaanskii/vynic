# WEB-01/04 — Whole-day holds and verified booking payments

Status: **implemented and qualified with isolated data; not deployed**. The five product rules were approved: whole-day table booking; ten-minute website and bank windows; genuinely late payment after expiry requires restaurant review with no automatic restore/refund; partial refund preserves the booking; the restaurant owner decides financial exceptions and Vynic support assists technically.

## Behavior

New bookings freeze the server-priced GEL minor-unit amount, merchant revision, physical table identities and calendar day. Venue locking and a partial unique active table/day index serialize competing website requests. Twenty simultaneous requests for one physical table/day admit one hold and one bank order; table aliases and different requested hours cannot bypass whole-day occupancy. Separate Venues and days remain independent. All availability/menu/mirror reads within admission or queue recording use the same transaction connection, including under a four-connection pool.

The website hold starts at transactional admission and ends exactly ten minutes later. BOG receives `ttl: 10` and automatic capture. A slow, lost or duplicate create reply cannot extend the hold. These are equal configured durations, not a claim that two independent systems create their clocks at the same instant. The provider's order creation/expiry fields remain observation facts. An expiry releases only website occupancy; it never asserts that money was not taken. Unknown order-creation outcome remains visible and the same signed callback can recover its stored booking identity; no second bank order is generated as recovery.

Callback RSA verification and Host/booking/merchant ownership protections remain. A pinned authenticated receipt, exact expected amount/currency and supported capture facts gate confirmation. Authorized/blocked/preauthorization/partial-completed states cannot masquerade as fully paid. Immutable sanitized observations retain references, exact amounts and relevant provider timestamps, without raw receipts, guest details, PAN, bank authorization data or credentials. Money outcome, occupancy confirmation and durable delivery intent commit together. Duplicate/out-of-order receipts cannot reduce known gross paid/refund amounts, undo a refund or revive a completed POS command.

BOG's documented full-refund receipt has remaining transfer zero and refund equal to requested amount: gross processed amount is therefore recorded as remaining transfer plus cumulative refund. Partial refund retains confirmed whole-day occupancy; a refund request alone does not cancel. An actual full refund releases occupancy and uses the existing durable cancellation handoff. Historical rows lacking the exact snapshot remain explicitly untracked/reviewable; old Float prices are never promoted into financial proof or automatically replayed/cancelled.

## Timing and operator review

BOG documents `zoned_request_time` as callback-send time, order creation/expiry separately, and action dates as initiation dates. None is an ordinary payment-completion timestamp. As a causal inference from the signed snapshot (not a provider completion timestamp), a verified fully paid snapshot sent before the hold deadline proves payment was complete **by** that send time, even if delivery is delayed. That causal proof survives a receipt outage and a new reconciliation service instance. With a free original occupancy it may finish the original timely booking; if the table was reassigned it requires review and never steals the new hold. A provider order demonstrably created after the hold deadline proves genuinely late payment; otherwise unproved timing is labelled separately. Neither late nor unproved expired payment automatically restores a booking or initiates a refund.

Owner `/customer/venues/:venueId/website-payment-reviews` and Platform `/platform/venues/:venueId/website-payment-reviews` are bounded, tenant-authorized, read-only projections. Owner history remains readable after payment entitlement ends; merchant configuration retains its existing write gate. The panels display booking outcome, exact requested/paid/refunded money and safe bank references. No refund/rebooking/replay action is exposed. The restaurant owner resolves the financial exception through its authorized restaurant/bank process; Vynic support can inspect technical evidence. This task does not introduce an in-app financial resolution command.

New holds' frozen service date drives the financial review and delivery snapshot, independently of a stored UTC timestamp. Existing durable outbox snapshots retain their historical compatibility fallback. General historical timezone conversion is not rewritten.

Vankisi's success **and** failure redirect pages now read the server outcome. Pending, review, missing identity or API failure preserves the cart and shows a visible unconfirmed state. Only a successful `CONFIRMED` response displays success and clears the cart. Read-only retry is available; a redirect/referrer/local checkout marker is never proof. Unsupported automatic email/call promises were removed from the confirmed view. The shared Website SDK accepts `REVIEW`.

## Verification on the final source

| Check | Result |
|---|---|
| New WEB-01/04 actual HTTP/PostgreSQL cases | **32 passed**, 0 failed |
| Existing price/guest-ownership/durable-delivery regressions | **179 passed**, 0 failed; 83 overlap with aggregate |
| Original merchant revision + public tenant isolation | **28 passed**, 0 failed |
| Backend aggregate | **851 passed**, 0 failed, **840 opt-in skipped** |
| Distinct backend cases after accounting for overlap | **1007 passed**; 156 aggregate skips run separately, **684 not run** |
| Frontend aggregate | **208 passed**, 0 failed, including 22 new UI/return-route cases |
| Website SDK | **6 passed**, types passed |
| Backend types/build; Platform and Vankisi builds; contracts | passed |
| New backend/frontend source and tests lint | 0 errors, 0 warnings |
| Touched implementation lint versus private pre-edit snapshots | 19 existing errors, 0 added; no initial snapshot of the prior PaymentSuccess file, whose current lint is clean |
| Changed existing fixtures lint | W1 retains 79 existing errors and 16 warnings, 0 added; other changed fixtures clean |
| Migration | fresh databases + populated upgrade passed; 74 SQL checksums verified; historical IDs/dates/statuses/prices/duplicate legacy references preserved |
| Website schema alignment | new website models match migration; full-schema diff retains the same two pre-existing `DevicePrinterRuntimeRequest` FK-name differences |
| Browser QA | real components with synthetic adapters/cart; KA/EN, 375/768/1440, keyboard read retry, unavailable/pending/review/confirmed and owner table scrolling |
| Final whitespace/status | `git diff --check` passed; WIP left uncommitted |

Machine-readable evidence and source hashes: [qualification.json](proofs/WEB0104_3463ee40_2026-10-13/qualification.json). Browser screenshots in the same folder include the restored owner table and the preserved cart on review/error. Signed-provider acceptance is stubbed only in the new fixture; missing signature/reference failures and existing security regression coverage remain. Real bank operations, credentials, user data and hardware were not used.

The same-calendar-day race, partial/full refunds, stale completion/pending callbacks, malformed money/currency, lost replies, provider outage/reconciliation restart, rollback at hold/observation/intent/queue boundaries and callback-before-create-reply identity race were exercised. Existing WEB-03 cases retain queue/ACK/Primary/legacy/tenant containment proof after the new receipt semantics.

## Migration and release limits

`20261020120000_website_payment_holds_ledger` is additive. Existing rows receive `UNTRACKED`, without invented money or holds. New physical occupancy and observation rows use composite booking/Venue foreign keys. Exact snapshots/window/reference and observation identities are guarded against mutation. A scoped or full local reset uses the existing deletion matrix with child records before bookings; no reset was run.

Cloud holds serialize website bookings, not independent offline POS bookings. A stale Cloud mirror can still disagree with a physical POS; existing delivery attention/ACK evidence must be reconciled, and a real fleet/bank acceptance run remains a release gate. No physical multi-POS/hardware or live bank certification is claimed. Full-schema printer FK-name drift is pre-existing and was not changed. 684 opt-in backend cases were not run. Preview and PostgreSQL processes created for these tests are stopped; live services/images/data are unchanged.

For rollback, stop new booking admission first and retain receipt/callback processing and durable history. Do not drop ledgers/holds or revert migrations over paid history as an automatic rollback. Existing overlaps, old payment conflicts or real late payments require owner review; code prevention does not repair live history.

Primary provider references: [BOG receipt](https://api.bog.ge/docs/payments/standard-process/get-payment-details/), [callback](https://api.bog.ge/docs/payments/standard-process/callback/) and [create order](https://api.bog.ge/docs/payments/standard-process/create-order/). The proof records hashes of the public documentation read; no provider credentials were requested.
