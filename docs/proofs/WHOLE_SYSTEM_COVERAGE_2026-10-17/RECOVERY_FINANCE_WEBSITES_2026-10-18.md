# Finance and websites recovery verification

Scope: verify the saved October 17 integration patches, recover uncertain
validation, and adapt finance integration fixtures to the transactional Cloud
mutation API. This is one domain contribution to the whole-system audit.

## Current checks

| Check | October 18 result | Evidence in `validation/` |
| --- | --- | --- |
| Website service and booking/payment rule units | 5 suites, 105 passed | `websites/backend-unit-20261018.log` |
| Vankisi checkout, mixed menu, payment return and shared information | 4 suites, 41 passed | `websites/frontend-20261018.log` |
| Finance rules and revenue classification | 2 suites, 15 passed | `finance/backend-unit-20261018.log` |
| Manager Financials ledger widgets | 7 passed | `finance/financial-ledger-widget-20261018.log` |
| Platform/owner TypeScript and production bundle | Exit 0; large-chunk warning | `websites/platform-build-20261018.log` |
| Vankisi TypeScript, production bundle and build manifest | Exit 0; large-chunk warning | `websites/vankisi-build-20261018.log` |
| Complete backend TypeScript, including integration tests | Exit 0 | `websites/backend-typecheck-20261018.log` |
| Finance disposable PostgreSQL | 17 passed, 0 skipped | `postgres-recovery-20261018/finance-tests.json` |
| SEC-02 guest ownership disposable PostgreSQL | 26 passed, 0 skipped | `postgres-recovery-20261018/guest-tests.json` |
| Scoped `git diff --check` | Exit 0 | Executor result |

Both client builds execute `tsc -b`. Vankisi's generated CUSTOM build fingerprint
is `3c5311f26824590e72a3d7d88b5801eb6f4a1f68765cbb46ba53c1601f70f36e`.
No website production changes were required during this recovery pass.

## Saved behavior verified in source and focused tests

| Surface | Implemented behavior | Database qualification |
| --- | --- | --- |
| Manager expense creation | Cloud and POS share the expense identity and business date; atomic delivery-intent persistence rejects a failed queue write | Fresh finance suite passed |
| Expense deletion | POS-backed and legacy salary records remain read only; Cloud-only eligible records expose `canDelete` | Widget and fresh finance suite passed |
| Financial planning | Obligation calendar month is independent of the payroll business month and PAYROLL availability | Fresh finance suite passed |
| Paid website preorder | Resolve retained Cloud item/variant under its Venue and parent item to stable POS IDs; unresolved variant becomes explicit attention | Unit checks passed; WEB-03 fresh suite required |
| Guest booking history | Preserve paid name, variant and exact price, including zero; fill missing legacy snapshot fields only | Unit and fresh SEC-02 suite passed |
| Vankisi checkout | Send selected guest count as `numberOfGuests`, preserving missing-count compatibility | Frontend regression passed |
| Vankisi payment return | Clear current reservation/preorder/cart keys only after successful server-confirmed booking | Frontend regression passed, including pending/error retention |
| Bespoke menu | Include direct and subcategory items together; retain existing raw operational presentation | Backend and frontend regressions passed |

The recovery edit in `apps/backend/src/finance/finance.integration.spec.ts`
updates Staff and expense dispatcher fixtures to `recordCloudMutation` and
`kickRecordedDelivery`, and adds a rollback regression for rejected expense
delivery-intent persistence. It does not substitute unit stubs for real queue
durability qualification.

The first fresh WEB-03 run passed 26 cases and failed one new variant case
because the test attempted to replace an already frozen booking snapshot. The
database correctly rejected that write. The fixture now creates its retained
catalog identity and variant snapshot before `websiteReservation.create`; the
illegal update is removed. Production rules and database triggers are unchanged.
The corrected WEB-03 suite awaits the parent's fresh rerun.

## Fresh PostgreSQL handoff

Run each complete suite on its own newly created verification-owned database:

| Suite under `apps/backend/` | Environment variable | Database guard |
| --- | --- | --- |
| `src/finance/finance.integration.spec.ts` | `TENANT_INTEGRATION_DATABASE_URL` | URL contains `vynic_step47_test`; use `disposable_vynic_step47_test_*` |
| `src/website/reservation/web03-delivery.integration.spec.ts` | `WEB03_TEST_DATABASE_URL` | `127.0.0.1`, `disposable_*` name, pathname contains `web03` |
| `src/website/user/guest-booking-ownership.integration.spec.ts` | `SEC02_TEST_DATABASE_URL` | `127.0.0.1`, exact database-name pattern `disposable_sec02_[a-z0-9_]+` |

Fresh database evidence above covers finance and guest ownership; WEB-03's
corrected suite remains pending. Normal production startup/runtime is not
certified by this domain report. No live database writes, bank calls, service
restarts, credential changes, publication or deployment were performed here.

## Supported boundaries and genuine remaining gaps

The generic SaaS website remains a published read-only site. Generic booking,
ordering, online payments, customer accounts and guest-claim lifecycle are
outside its implemented scope. The bespoke Vankisi routes retain their existing
Host-derived tenant and payment/ownership checks. There is no private website
consumer of Manager finance reports. Historical POS COGS and realized profit,
durable POS expense deletion/correction, and advance-edit policy are separate
capability or decision gaps. Source and isolated fixture tests do not establish
live POS mirror freshness, physical-device operation or production deployment.
