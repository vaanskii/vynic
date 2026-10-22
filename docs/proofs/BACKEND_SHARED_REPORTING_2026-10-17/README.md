# Shared Sale reporting and synchronization — phase two

Generated captures, logs and machine receipts referenced below are local-only; see the [proof output policy](../README.md).

This is the separate backend-first follow-up to [phase one](../MANAGER_SYNC_2026-10-17/README.md).
The implementation reuses the existing immutable `CloudSale`, `SaleLine`,
`SalePayment` and `SaleLedgerDay` persistence. No new migration, historical
backfill, permission change or financial policy is required. Backend contracts
and recovery responses were implemented before their POS/Manager integrations.

## Audit and resulting support

| Capability | Authoritative facts and shared backend | POS / Manager / restaurant boundary | Result |
| --- | --- | --- | --- |
| Sale history and money | POS Sale maps retain durable IDs, frozen lines/tender and lifecycle revisions. CloudSale stores them by authenticated Device → Venue. `/mobile/sales`, Sale detail and financial summary preserve fiscal/cancel/restored predicates and exact decimal money. | POS remains offline-first and owns live operation; Manager reads the Cloud projection for its Staff → Venue. The implementation is generic across Venues. | Existing working ledger retained. Phase-one range pinning, pages and tenant isolation remain covered. |
| Product quantities | SaleLine quantity and transaction-time price/name/menu/variant identities, never current OrderItem totals. Detailed product analytics aggregate only eligible Sale rows. Manual/unlinked lines remain explicit. | Manager dashboard and Financials already consume this ledger. The legacy `/mobile/top-items` adapter now consumes it too, with its ledger source metadata. POS continues to report its local immutable Sales. | Removed the permanent unsupported top-items source. Quantity and revenue rank retain their distinct meanings; line revenue is not a new allocation of fee/discount across products. |
| Staff attribution | CloudSale already persists `createdBy` and `closedById` independently. The detailed API accepts `attribution=creator|closer` (default closer preserves existing callers). Sale detail exposes both roles. | Dashboard staff rank and legacy `/staff-performance` use recorded order creators for the same displayed business date. Financials explicitly labels closing operators. `/sales-report` now supplies creator results and separate attribution provenance for today/week/month/all. | Replaced the unconditional empty staff endpoint. Names remain immutable historical facts, not lookups through today's Staff directory. |
| Identity confidence | Each actor projection reports `RECORDED_POS_USERNAME` or `UNKNOWN`, `identityStable=false`, and an explicit identity warning. The older `staffId` name selector is retained for compatibility; it is not a server Staff ID. | Manager explains creator-name grouping; a closer is never substituted as the waiter. Missing/system actors stay unknown. | Historical renames/reused usernames cannot be joined into a stable person without evidence. No fabricated IDs, identity backfill or auth mapping. |
| Detailed completeness | Detailed lists/products/actors return `PARTIAL` when receipts are missing, even if aggregate summary fallback exists. Only financial summary can actually use aggregate fallback values. | Manager retains warnings. A fully covered, fresh detail range can be complete. All-time creator results become complete only when declared day coverage is complete and retained POS all-time revenue/count agree; otherwise detail remains partial. | Removed misleading detail wording that implied aggregate-only history supplied staff or product rows. |
| Daily history | An indexed missing/corrupt daily summary carries `available=false`, `totalRevenue=null`, `profit=null`; the freshness interceptor marks the response partial. | Manager preserves the unknown day as a chart gap and displays an unavailable day card. A month with no available days shows an em dash, not zero. | Fixed false zero history without altering real zero-sale days or fiscal totals. |
| Retry and recovery | If an upload-complete declaration says the POS retained more rows than Cloud holds, ingestion returns `saleLedgerRetryDates`. Only authenticated primary ingest can initiate this existing path. | POS resets ACKs only for genuine retained Sales on those dates, queues the usual bounded follow-up and replays original IDs/revisions. Other dates and Venues remain untouched. | Repairs recoverable Cloud row loss without synthesizing receipts, changing money, deleting cloud rows, or restarting normal partial batches. |
| Restaurant websites and owner UI | Generic/custom guest websites consume host-scoped public menu, venue, booking and payment contracts; owner/control-plane operations have separate principals. | Inspected `restaurant-web/src/api/client.ts`, `packages/website-client/src`, Website controllers/guards and owner entry points. They are not consumers of private restaurant Sale/staff reports today. | Shared restaurant data does not authorize publishing private financial/staff data to guests or broadening owner/guest permissions. No new public report route was added. |

Relevant sources: `apps/backend/src/mobile/services/mobile-sale-ledger.service.ts`,
`mobile-dashboard.service.ts`, `mobile-reports.service.ts`,
`manager-data-freshness.ts`, `apps/backend/src/pos/sync/snapshot/sale-ledger-sync.service.ts`,
`apps/operations/lib/core/services/sync/sale_ledger_sync_state.dart`, and
`manager_sync_service.dart`. `validation/changed-files.json` and
`validation/owned-delta.patch` isolate this phase from phase one and inherited work.

## Warning diagnosis

**“მონაცემები შეზღუდულია” means “Data is limited.” It is not developer-only.**
It is visible to ordinary authenticated Managers. The original native inspection
observed the backend's explicit partial-sale-history warning and the plain title,
not a failed-refresh title. That proves the displayed period was partial; it does
not identify the missing database row or prove which sync defect caused it.
See the [original read-only evidence and exact trigger list](../MANAGER_BRANDING_2026-10-17/README.md).

The status combines API success, cache location/read age, POS source/receipt age
and completeness. Old/missing/future timestamps, cache/offline reads, partial or
unknown coverage and failed requests can trigger it. 401/403 are access failures
and must clear protected retained values; the plain title does not mean a role
is missing. Disabled capabilities are excluded. There is no debug-mode gate.

The prior permanently unsupported staff/top-items blocks are now supported by
existing ledger facts. The warning can still correctly appear for open days,
missing retained details, stale sources and failed reads. A successful upload
alone does not close or fully reconcile a business day. Do not close a day or
relax permissions to remove the warning.

## Verification and evidence

- Final isolated PostgreSQL/HTTP suite: **46 passed, zero skipped**. It includes
  genuine synthetic Dart wire rows, creator/closer separation, unknown historical
  actors, fiscal/internal/void/restored filtering, two-Venue isolation, supported
  adapter freshness, unauthenticated rejection, all-time matching/missing coverage,
  absent daily summaries, and replay after simulated Cloud row loss.
- Focused Flutter regression: **86 passed**. POS ACK replay is date-scoped and
  preserves the same records; dashboard staff reads pin the displayed date.
  Existing worker liveness, legacy wire, cache/access/freshness, Financials pages
  and warning checks pass with the new phone/desktop history/staff checks.
- Separate responsive render suite: **9 passed**, covering 390, 780, 834, 1440,
  1728 and 1920 widths, phone/desktop dark mode and 320-wide large text. These
  renders overlap the relevant presentation coverage, not the test count above.
- Flutter analysis: **no issues**. Backend production build and **70 focused
  backend unit tests** pass. Changed TypeScript files are compared with the
  phase-one baseline; no new lint errors remain. Existing legacy lint debt is
  documented in `validation/lint-comparison-final.json`, not claimed clean.
- Current phase-two Manager macOS and Android debug builds pass in a new temporary
  stage. Neither was launched or installed over the original running sessions.
  Phase-one iOS Simulator and POS development builds remain phase-one evidence;
  no physical iOS/Android or Windows release qualification is claimed here.

Missing daily history, phone (local: `screenshots/missing-daily-history-390.png`) ·
Recorded staff with partial history, phone (local: `screenshots/recorded-staff-partial-390.png`) ·
Recorded staff, desktop (local: `screenshots/recorded-staff-partial-1440.png`).
Screenshots use synthetic temporary data and actual production Flutter widgets.
They are widget renders, not native runtime screenshots. They were visually
inspected for overflow, wrapping and misleading values.

The separate phase-one native runtime proof (local: `../MANAGER_SYNC_2026-10-17/runtime/phase-one-completion.json`)
ran the production Financials widget against actual Nest/PostgreSQL services in
an isolated QA app. It displayed 372.00 from 31 synthetic Sales, paged the real
cursor, and retained the total with a visible warning when the owned backend
stopped. Its verified Library screenshot ID is
`libfile_64d42fce9bc0819192453b7ba38eac30`; file ID
`file_0000000091dc81f6beea252ba3a29624`, 800×600, 61,281 bytes, metadata read back.
That proof is not a phase-two live restaurant or normal-login qualification.

## Boundaries and next step

Code, isolated tests and candidate builds are complete. The normal running apps
were not restarted, and there was no deployment or live synchronization/backfill.
When rollout is authorized, ordinary POS uploads can replay genuine retained
rows after a missing-row response. Missing POS receipts cannot be recovered from
aggregate totals; investigate the affected dates against retained records before
proposing a historical repair. More Cloud rows than the POS declares, or divergent
immutable facts, stay reconciliation issues; this change does not delete or rewrite
them. Stable employee identity across historical renames remains unproven and is
explicitly reported, rather than manufactured.

Branding is still pending the user's choice between the two real application
masters. No logo assets, bundle IDs, signing, credentials or business permissions
were changed. No real orders, payments, reservations or print jobs were created.
Advance-editing financial policy and printer infrastructure remain outside scope.
There was no commit or push.
