# POS checkout, estimates and reservation advances

This is an uncommitted source change in the existing working checkout at
`3463ee406184fec7f53818416e11d0e5f5602c87`. It has not been deployed, published,
installed into the live POS, or applied to a live database.

## Operator flow

- Home opens with the right action panel collapsed. Its 44 px handle expands
  it in 200 ms; the panel occupies its own layout column. Closing returns the
  width to the floor plan. Saved table coordinates and the uniform fit remain
  intact. The service dashboard and duplicate Reservations button are removed.
- Quick sale opens the existing menu and payment flow without a physical
  table. Cancelling payment keeps the cart. A stable request identity and busy
  guards prevent repeat submission from making another Order or Sale. The
  existing virtual takeaway identity and durable creation/closure journals own
  this flow; no new money ledger or hardware print path is introduced.
- Saving a menu estimate offers optional full name and phone immediately.
  Cancelling preserves the cart. Contacts survive ordinary item/service edits,
  Hive reopen and portable backup. Search uses saved name, phone or amount.
- Estimate deletion and clear-all require the current stored Manager identity,
  including when a previously authenticated Manager is demoted. Supervisors
  retain their other existing estimate management permissions. The existing
  Cloud endpoint remains guarded by JWT, current Staff, role, feature and Venue.
- Reservation entry is bounded to 560 × 660 logical pixels and provides guest
  minus/plus controls. A future-calendar-day tentative hold has its own `hold`
  status and label, including in Management Center. It blocks the existing
  whole-day table availability rule. It must be confirmed before seating or
  kitchen submission; automatic day-open activation ignores it. An overdue
  hold stays visible and needs a revised date before confirmation.
- Takeaway entry offers optional full name/phone. The queue shows them and
  searches real saved contacts and amount. Existing payment, cancellation and
  print operations retain their authority.
- The full-screen staff lock keeps the PIN pad at 320 px. Back navigation still
  cannot unlock it; only the existing PIN authentication can exit the lock.

## Advance accounting and recovery

The advance input means money already received. It is not a promise to pay.
New additive Hive Reservation fields 15–18 carry amount, collection business
date, receipt identity and pending receipt intent. Legacy rows default to
zero/null/false; existing field numbers are unchanged.

The reservation and pending intent are flushed before its deterministic
`reservation:<id>:advance` cash receipt. Startup and complete portable restore
finish an interrupted receipt exactly once. A missing historical receipt
without pending intent is refused instead of manufacturing money.

The receipt is collection on its original business day, with no Sale revenue.
Atomic seating transfers its frozen facts to the Order. Settlement applies it
once, writes full gross revenue and collects only the remaining balance.
Repeated create, seating, close, crash recovery and restore retain identities.
A fully prepaid bill requires explicit confirmation of zero new collection.
An excess advance refuses settlement; a zero-clamped display cannot inflate
the gross Sale by adding the excess back. A receipt already used by another
closure is refused.

Cancellation keeps the original receipt, and deleting an advance-bearing
booking is refused with visible feedback. Automatic refunds, forfeiture,
transfer and hold expiry are not implemented. These remain business decisions;
no automatic money movement is inferred from cancellation.

## Cloud compatibility

Migration `20261024120000_pos_reservation_advances` adds three defaulted/nullable
mirror columns and a non-negative amount constraint. The POS remains the live
operational authority. Older snapshots that omit the new fields preserve an
existing advance. Recorded positive receipt facts cannot be replaced or zeroed
by a later snapshot. Venue row locking serializes simultaneous claims and works
inside the existing snapshot transaction without opening a nested transaction.
The mirror passes read-only advance metadata to Manager reservation reads.

The 77 historical migration files are unchanged. A populated 77→78 upgrade,
fresh 78-migration deployment and repeated no-op deployment were qualified in
private disposable PostgreSQL only. Apply this additive backend migration before
releasing a POS that emits the new fields through the normal authorized release
process.

POS estimates are local drafts; this change does not make them the same store
as the existing Cloud Manager counted menus or add a new cross-store sync flow.

## Qualification

Evidence: `docs/proofs/POS_CHECKOUT_RESERVATIONS_3463ee40_2026-10-15/`.

- Focused Flutter: 76 passed (47 money/storage/recovery, 8 form/security/search,
  21 Home layout/refresh). Disposable Hive only; fixture HTTP is refused and
  physical printing is never invoked.
- Targeted Dart format/analyze: passed, no issues in 38 source/test files.
- Real PostgreSQL reservation mirror: 6 passed, including competing receipt
  claims, old omitted fields, invalid rewrite retention, other Venue and the
  existing outer transaction.
- Real HTTP/PostgreSQL Manager deletion: 6 passed, with anonymous, supervisor,
  waiter, inactive and demoted identities refused; forged tenant inputs cannot
  redirect an authenticated Manager's deletion.
- Backend aggregate with owned MENU09/POS databases: 918 passed, 895 skipped,
  zero failed. TypeScript typecheck and Nest build passed.
- Non-printer Flutter aggregate: exact final counts and excluded file/case list
  are recorded in `qualification.json`. The one existing Dart→Go wire case
  requires `VYNIC_OPERATIONAL_PROOF_GO_FIXTURE`. No Go executable or compiled
  fixture was available on this executor; the unfiltered run failed only this
  prerequisite. The bounded aggregate excludes that one case explicitly.
- Five actual Flutter PNGs cover collapsed/expanded Home at 1024×768 and
  1440×900, plus an empty saved floor. They use synthetic layout/order data.
  They are not screenshots of live restaurant data.

Windows device acceptance, actual cash workflow/hardware checks and production
deployment remain separate release gates. All owned PostgreSQL clusters were
stopped. Existing WIP, live data, credentials and services were preserved.
