# Commercial subscription lifecycle

This milestone extends the existing VenueSubscription and VenuePlanAssignment.
It does not implement card charging, deploy code, or access the live database.
All database validation uses disposable PostgreSQL on 127.0.0.1:55437.

## A. Why approved owners were asked again

Public request approval always prepared a NO_PLAN shell, even when the applicant
had selected a trial package. The dashboard also rendered TrialRequest unconditionally.
The acquisition request and commercial subscription were separate, but the approval
workflow never connected them for new customers.

## B. Request → approval → Trial

Review explicitly offers NO_PLAN or TRIAL. Trial approval requires an active plan
and future end date; the operator can supply a note. A locked transaction prepares
the Organization/Venue and invitation, assigns the plan/agreed snapshot, sets TRIAL,
approves the request, and writes audits. Any failure rolls everything back.
Acceptance grants membership without resetting dates or commercial access.

A request is single-use. An existing Venue is reused only through its server-stored
requestedVenueId and is locked before checking access. New public requests create
isolated shells; email/name alone is never used to attach an applicant to someone
else's Organization. The invitation system handles an existing invited account.
Eligible current access prevents a second trial request/approval; a pending request
also prevents another pending request under the Venue lock.

## C. Approval without a package

NO_PLAN provisions identity/invitation only. It grants no paid products. Owners may
request a trial or contact Vynic. This is an explicit alternative to Trial approval.

## D. Trial controls

Operators choose a plan/end date to start, extend or change a Trial. Suspension
ends usability immediately; resume requires an unexpired Trial. Expired Trials
fail closed by time comparison even before the timer, then reconcile once to
SUSPENDED with a SYSTEM audit. Extension can reactivate an expired Trial explicitly
(confirmed, audited `reactivated`); an expired Trial can also be replaced by a new
Trial or converted to a paid plan directly, without cancelling first.
A manual activation may be marked as a gift (`complimentary`): the first billing
period is free, `paymentState=COMPLIMENTARY`, audit source `COMPLIMENTARY`, no
billing operation; the agreed plan price is due at the next renewal.
A paid agreement must be ended before a new Trial can replace it.

## E. Paid model

VenuePlanAssignment remains the current plan and agreed price/currency/period.
VenueSubscription owns status, currentPeriodStart, existing currentPeriodEndsAt,
billingAnchorAt, billingManaged, version, Trial history, suspension origin,
pending plan/price/currency/period/effective date, cancellation flag and payment state.

SubscriptionBillingOperation is an immutable server quote/work item, not an access
model. SubscriptionBillingEvent is an idempotent receipt ledger. Neither independently
grants features. Successful first purchase activates immediately and establishes a
paid period. A deliberate operator manual agreement is labelled MANUAL and audited;
it does not fabricate a payment receipt.

## F. Billing anchor and renewal

UTC calendar months/years preserve the original anchor day and time. Sep 25 monthly
renews Oct 25. Jan 31 clamps to February's final day, then returns to Mar 31. Leap-day
annual anchors clamp in non-leap years. Normal changes preserve the anchor.
MONTH → YEAR is scheduled at the existing renewal, where that boundary becomes the
new interval anchor. ONE_TIME plans cannot enter this recurring billing lifecycle.

A timed period is paid only through its end. At renewal, a scheduled lower package
becomes current; absent a verified renewal payment the subscription is PAST_DUE
with no commercial access. Confirmed renewal restores the new plan through the next
anchored boundary. No timer invents a charge or paid extension. Multi-period arrears
require explicit operator reconciliation instead of silently skipping debt.

Historical manual agreements keep billingManaged=false and their existing grace
behavior until an operator explicitly establishes terms. Unknown anchors/prices
remain unknown. No migration changes historical access or invents payment history.

## G. Upgrades and change classification

A strict capability superset is immediate even at a promotional lower price.
A strict subset with non-increasing price is deferred. Same-capability price increases
are immediate; decreases/equal-price package changes are deferred. Feature swaps,
capability additions combined with currency/period changes, and removals combined
with higher prices require operator review. Currency/period changes without added
capabilities are deferred. NON_FISCAL_CLOSE is excluded from classification.
An operator can explicitly classify a mixed swap with a reason; immediate upgrades
still require matching currency and billing period. Classification overrides are audited.

A quote alone grants nothing. Successful upgrade payment applies the new plan and
price immediately, keeps the period/anchor unchanged, and clears pending changes.
Old unrestricted assignment/status APIs cannot bypass a managed billing agreement.

## H. Proration

Let D = max(new price − current agreed price, 0), R = periodEnd − quoteTime,
and T = periodEnd − periodStart, all in integer minor units/milliseconds.
Charge round-half-up(D × R / T). BigInt arithmetic avoids intermediate floating
point rounding. Dates must satisfy start ≤ quoteTime < end.

50 GEL → 150 GEL, Sep 25–Oct 25, quote Oct 10 at the same UTC time:
D=10000, R/T=15/30, charge=5000 minor units (50 GEL).
One minor-unit difference with half a period remaining rounds to one minor unit.
A negative difference produces zero, never a cash refund.

Quotes use server time and expire after 15 minutes or the period boundary, whichever
comes first. Payment confirms the quoted amount, not a browser-calculated price.
The subscription version fences every quote; a new quote supersedes earlier ones.
A stale/expired receipt cannot grant access and requires payment reconciliation.

## I. Downgrades

Selection snapshots the next agreement, leaving current products/price intact until
currentPeriodEndsAt. The owner can cancel the pending change before renewal. The
boundary applies the lower plan, and the renewal quote uses its frozen lower price.
A catalog edit after scheduling cannot rewrite the pending agreement. A stale preview
price/version is refused before customer confirmation can schedule different terms.
There are no automatic negative refunds.

## J. Cancellation

Customer cancellation schedules the current period end and clears pending plan changes.
Features remain available through the paid period. Keep subscription undoes it before
renewal. At the boundary CANCELLED suppresses access with no renewal charge.
Immediate cancellation is a separate operator action requiring reason and confirmation.
It changes commercial state only and retains data and receipts.

## K. Suspension and resume

Suspend requires an operator reason, records the prior status and denies commercial
features immediately. Resume requires valid dates; expired paid periods must first
be renewed. Renewal can settle a suspended subscription but does not silently remove
operator suspension. Resume then restores ACTIVE explicitly. CANCELLED is not SUSPENDED.

## L. Trial → paid

A successful purchase ends Trial authority at the server activation time, records
trialEndedAt, activates the purchased plan, and establishes a fresh paid anchor.
An Oct 8 Trial converted Sep 30 renews Oct 30. Earlier Trial dates/changes remain in audit.

## M. Customer subscription UX

The page reads server subscription details and effective features. It displays current
plan, status, agreed renewal price, dates, current/next package and cancellation state.
TRIAL/ACTIVE/SUSPENDED/CANCELLED/PAST_DUE never display the Trial request form.
Owners can inspect server quotes, schedule/cancel a downgrade, schedule/undo cancellation,
and contact Vynic. Paid quotes explain that completion requires payment confirmation;
there is no fake card checkout or customer success endpoint. Georgian owner copy and
existing Vynic styles are retained. The dashboard continues refreshing its entitlements.

## N. Platform controls

Review approval previews the resulting Trial or no-package state before confirmation.
Venue Commercial groups current/pending terms first, followed by a selected action:
Trial changes, manual ACTIVE agreement, purchase/upgrade/renewal quote, deferred change,
undo, suspend/resume, and immediate cancellation. Writes require reasons and are audited.
Verified manual payment additionally requires an external reference and confirmation.
Pending customer quotes and commercial history are inspectable. SUPPORT_READONLY
cannot invoke any mutation endpoint. Existing admin/public host separation is preserved.

## O. Access timing and data

Every shared commercial read/mutation resolver checks the paid period and trial end.
Late sweeps cannot extend access. Pending downgrade/cancellation does not remove paid
features early. Overrides cannot revive expired/suspended/cancelled products.
NON_FISCAL_CLOSE remains default-off, Venue-only and independent of package changes.
No lifecycle transition deletes restaurants, drafts, media, devices, sales, menus,
payments or audit. Existing domain grace/media cleanup are unchanged. Offline POS
safe completion, Device sync, frozen effects and restaurant payment callbacks stay
outside commercial denial.

## P. Provider boundary

SubscriptionService.applyTrustedResult is an internal server API, with no customer
HTTP exposure. Future adapters must authenticate signatures, merchant identity and
receipt authenticity before invoking it. Events: payment_succeeded/payment_failed,
renewal_succeeded/renewal_failed, refund and credit. Server receipt time is authoritative.
Provider+eventId deduplicates; Venue locking, operation state and subscription version
prevent double settlement or stale authority. Amount/currency must match the quote.
Refund/credit receipts are bounded by the settled amount and do not silently cancel access.

Platform's manual-success endpoint requires a SUPER_ADMIN session through PlatformAuthGuard,
a reason, external reference and explicit confirmation. Restaurant BOG integrations,
merchant secrets and diner-payment callbacks are not used by this domain.

## Q. Migration

20261004120000_subscription_lifecycle adds fields and quote/event tables only.
53 migrations replay from empty. prove-subscription-upgrade.py replays the preceding
schema, inserts historical ACTIVE/TRIAL/missing-row and known/unknown-price fixtures,
applies the new migration and proves preservation. No backfill fabricates dates or prices.
Apply the new migration to an authorized non-live target before running the updated backend.
No non-disposable database was migrated during this task.

## R. Validation

See the final task response for final counts. The suite covers the original public
request, invitation acceptance, duplicate trial refusal, NO_PLAN API denial, time-based
expiry, suspension/resume, purchase/conversion, upgrade proration/anchor, deferred/undo
changes, cancellation/data retention, price snapshots, product combinations, explicit
NON_FISCAL_CLOSE, tenant ownership, HTTP privilege boundaries, concurrent receipts,
refund bounds, retired renewals and billing-period changes.

Commands (backend directory, disposable cluster already initialized):

```sh
DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test npx prisma migrate deploy
COMMERCIAL_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
W1_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
W3_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
FOUNDATION_TEST_DATABASE_URL=postgresql://vaanskii@127.0.0.1:55437/vynic_commercial_test \
npm test -- --runInBand subscriptions/subscription.integration.spec.ts customer/commercial-access.integration.spec.ts customer/restaurant-foundation.integration.spec.ts website/core/website-core.integration.spec.ts website/core/website-w3.integration.spec.ts payment-integrations/payment-integrations.integration.spec.ts
npm test -- --runInBand --testPathIgnorePatterns=integration.spec.ts
python3 scripts/prove-subscription-upgrade.py
npm run build
```

Frontend: `npm test -- --run`, `npm run build`, targeted lint, plus isolated fixture
browser QA at desktop 1280×900 and mobile 390×844. Fixture mode never contacts a backend.
The existing large-bundle warning remains; this milestone does not restructure bundling.

## S. Commits and preserved work

Milestone commits are reported in the task response. Pre-existing working-tree work is
preserved separately, including public acquisition styling, admin host routing and auth UI.
No push or deployment.

## T. Remaining provider work

Real provider selection, merchant configuration, signature-verifying adapters, automatic
renewal charging/retries, checkout, invoices/tax, dunning/grace policy, chargeback handling,
credit application, multi-period arrears reconciliation, and production monitoring remain.
Provider adapters must reconcile late/stale receipts explicitly and must never make a
browser claim authoritative. Public catalog ONE_TIME pricing is outside recurring billing.

## U. Stop

Stop after implementation, validation and coherent local commits. No live database access,
production billing, push or deployment is included.
