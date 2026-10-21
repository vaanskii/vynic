# Whole-system support matrix

This matrix recovers the October 17 audit and distinguishes source coverage,
implemented repairs, current verification and product gaps. It is not a claim
that every declared route or every client flow was executed.

The preserved static inventory contains 23 Nest modules, 54 controller classes
and 292 declared routes before this phase's additive notification-page route.
It also indexes POS, Manager, generic restaurant, Vankisi and Platform/owner
client sources. Inventory counts are navigation evidence, not runtime coverage.

## Operational authority and shared data

| Flow | Audited and implemented support | Repair in this phase | Evidence and remaining boundary |
| --- | --- | --- | --- |
| Walk-In / dine-in | POS Order/Table Hive records, ownership journals and Cloud Order/OrderItem/Table mirrors; retained Manager operations are pulled by Edge | Terminal Order reconciliation only releases a table owned by that Order, including legacy/canonical aliases | Backend ownership/reconciliation cases; no live restaurant mutation or Windows qualification |
| Takeaway | Order-backed POS queue, local/Manager/Edge creation and guest/pickup projection | Stable product/variant keys through Manager selection and edit | Existing transfer/Takeaway regressions; old bookkeeping Reservation rows remain compatible |
| Packages / local estimates | POS applies local package/quick-checkout data to Orders; local estimates remain offline | Reviewed existing paths; no invented shared draft contract | POS package/estimate storage is separate from Manager Cloud counts |
| Real reservations | POS owns live bookings; Cloud mirror/retained requests and website delivery preserve IDs | Whole-day admission now checks every real blocking booking before create/date/table/status writes; concurrent creates serialize; advances/audit are not written on rejection | 30 POS admission/advance cases; existing table/identity/activation tests. Manager picker still uses legacy representable table codes; mixed-floor activation requires a product contract |
| Table move / merge / repair | POS ownership WAL and guarded repair are implemented | Reviewed tenancy and terminal ownership | Manager remote move/merge UI and remote settlement are absent capabilities; repair is not a substitute |
| Order editing | Retained Manager request, baseline/fingerprint and POS durable edit repository | Existing item identity protections retained | Existing identity/transfer tests; historical/menu-retirement compatibility preserved |
| Close, split, cash/card, advances | POS closure journal and money model preserve gross Sale, advance applied and collected now separately | Reviewed existing money and receipt semantics | No bank/fiscal-provider/physical-print qualification. Advance-edit/refund policy remains unanswered |
| Audit, history, exports | Append-only POS event sequence, Cloud scoped audit and existing local XLSX/PDF exports | Reviewed identity and snapshot support | POS export food/staff cost/net-profit values still include estimates; historical COGS and realized profit are not implemented |

## Menu and inventory

| Flow | Audited and implemented support | Repair in this phase | Evidence and remaining boundary |
| --- | --- | --- | --- |
| Shared Menu catalog | Cloud canonical revisions/tombstones and POS offline mutation WAL; legacy compatibility remains bounded | Owner create retries retain entity/mutation identity after a lost response or failed reload | 7 owner catalog cases; no historical catalog rewrite |
| Manager selection | Item and variant IDs accompany new selections; frozen display values survive reopen | Mixed categories expose direct items; duplicate names/variants do not collide; selected variant quantities are independent | 5 new widget cases and 82 existing identity/transfer/audit regressions |
| Manager counted menus | Cloud header/lines, selected service fee and save/update/read routes | Header/line writes atomic; selected rate round-trips; ambiguous/removed/changed legacy lines retained manually with their names/prices/quantities/comments | Counted-menu PostgreSQL cases and widget save/reopen. QuickOrderDraft has no trustworthy persisted Menu IDs; none were inferred |
| Stock / suppliers / assortment | Venue-owned Cloud CRUD, archival, classifications and item packaging; Manager writes; POS read-only catalog | Unit-sensitive readers/writers lock Stock Items in sorted Venue order | Inventory unit and PostgreSQL lock-barrier cases |
| Receiving / cancellation | Draft/post/cancel, frozen purchase units and append-only movement/reversal records; explicit payment documents | Concurrent first use cannot race a base-unit edit; any historical movement prevents changing the unit | Real PostgreSQL blocking/rollback cases; original quantity and money scales retained |
| Recipes / current cost | Cloud-authoritative recipe components, yield/revision, current theoretical cost; offline POS recipe projection | Per-sold-unit quantities rounding below six-decimal minimum rejected atomically | Unit and PostgreSQL cases. Current recipe/moving-average estimates are not historical POS Sale COGS |
| Sale consumption / restore | POS freezes close-time intent, independent durable ACK and immutable Cloud effects/reversal | Malformed nested shapes return 400 before locks/persistence; removed recipe components cannot free an historically used stock unit | Consumption PostgreSQL suite proves exact effects, reversals, tenancy and no partial writes |
| Supplier payments / history | Actual disbursements separate from purchases; bounded keyset histories and exports | Reviewed existing receiving/payment/history boundaries | Legacy unverified payment history remains explicit; no backfill |
| Inventory locations | F1 backend schema/history groundwork exists | No new UI or transfer authority invented | F2 allocation/transfer flows and configured POS location decisions remain incomplete |
| Stock-driven availability | Negative/low stock visible; offline catalog retains last good projection | No behavior change | No automatic stock-based Menu blocking policy is implied |

## Finance and reporting

| Flow | Audited and implemented support | Repair in this phase | Evidence and remaining boundary |
| --- | --- | --- | --- |
| Expenses | Current POS business date and shared Expense/posExpenseId identity | Cloud create and delivery intent atomic; POS echo/retry does not duplicate outflow; unsupported POS-backed deletion fails explicitly and is not offered by Manager | Full 17-case finance suite, new durable-queue PostgreSQL suite and 7 ledger widget cases. Durable POS expense deletion/correction contract remains absent |
| Payroll | Frozen monthly compensation/periods, Decimal daily accruals, signed payments/corrections and retained Staff identity | Reviewed actual-payment composition and deletion containment | Finance suite. No attendance/hour/proration inference; overpayment remains the existing rule |
| Obligations / planning | Frozen recurring cycles, reserves capped to remaining amount; payments are actual outflows | Obligation planning follows the calendar month independently of POS payroll/business month | Whole finance suite with September-business/October-calendar cases. Reserves and accruals are not cash outflow |
| Sales reporting | Existing Sale ledger, scoped dates, exact summaries, bounded pages and visible provenance | Earlier reporting repairs remain; current source provenance tested with the whole-system changes | Fresh reporting and Sale-ledger PostgreSQL suites, 46 POS/Manager ledger/sync/reporting client regressions. Incomplete/legacy data stays marked |
| Product / creator / closer | Ledger product quantities and separate recorded creator/closer analytics | Verified existing adapters against selected dates | Current isolated native reporting fixture. Recorded POS usernames are not stable Staff UUIDs and historical attribution is not inferred |
| Complete cashflow / realized margin | Purchases, signed actual payments and current costs are separately represented | No unsupported report invented | Full cashflow, realized profit, historical COGS, waste/stocktake/variance remain missing product capabilities |

## Access, transport and websites

| Flow | Audited and implemented support | Repair in this phase | Evidence and remaining boundary |
| --- | --- | --- | --- |
| Principal / Venue authority | Device→Venue; Staff→Venue; Host→VenueDomain→Venue; server-owned payment identity. PlatformUser/CustomerAccount remain separate | No permission/authentication-policy change | Existing Staff/tenant/HTTP/socket regressions on disposable databases; not a complete security certification |
| Manager Staff changes | Existing create/PIN/role/rename/delete semantics and Venue lock | Staff/vault writes and delivery intent commit together; pending/claimed Edge plus pending legacy work protect pre-ACK Cloud state from old POS snapshots | Real rollback, queue persistence, rename and cross-Venue cases; credentials are synthetic fixtures only |
| Edge / legacy delivery | Enrolled Venue work is pulled/ACKed; legacy endpoint set is frozen | Legacy persistence failure propagates; new transactional helper uses only existing Staff/expense types; nonlegacy unenrolled Venue returns explicit unavailable delivery | Dispatcher/outbox unit and PostgreSQL suites. Queue admission does not prove execution |
| Identity changes during claim | Existing provisioning/restore boundaries retained | Old successful or rejected claim responses cannot execute/ACK work under the replacement identity | Edge client/service regressions. No enrollment/security settings changed |
| Notification catch-up | Additive authenticated page route; timestamp+ID ordering, fixed server watermark and all-page drain | Checkpoint advances after all pages; failure/replay/session/origin fences; first window uses server clock | 4 PostgreSQL paging cases and 37 Flutter notification/Edge cases. Initial window remains 24 hours; panel retains 100; real FCM/background delivery unqualified |
| Manager linking guidance | Existing permanent restaurant identifier and separate one-use connection controls | Copy now directs new installations to the existing one-use linking control | 9 Platform guidance/linking cases; no access issuance performed |
| Enrollment / replacement / restore | Existing Device authority, retained commands, quarantine and operator boundaries audited | Deferred finding left unchanged | Consumed old enrollment code may reactivate a subsequently revoked Device on same-installation retry (`device-enrollment.service.ts` retry path). Separate security authorization remains required |
| Generic SaaS website | Published read-only Host-derived site, shared public info/menu and owner drafts/publication | Existing generic adapter verified | Generic booking/ordering/payments/accounts/events/banquets and guest-claim lifecycle remain absent |
| Bespoke Vankisi Menu | Intentional raw Menu adapter remains separate from SaaS presentation | Mixed direct/subcategory products remain visible | Website unit/frontend tests. Do not silently apply SaaS presentation/enabled policy |
| Website bookings / preorder | Whole-day Cloud holds, trusted canonical/retained variant pricing, immutable booking snapshot and POS delivery intent | Correct variant→POS variant mapping; frozen values including zero retained; guest count forwarded | WEB-03 27 and guest ownership 26 PostgreSQL cases, 105 backend units and 41 frontend tests. Offline/stale physical POS mirror conflict still needs operator review |
| Website payments / return | Merchant-pinned payment observations, monotonic outcomes, hold expiry/refund review and create-ACK-before-cancel delivery | Local booking/preorder state cleared only after verified confirmation | Mocked provider plus real HTTP/PG fixtures; no real bank call, payment or refund |
| Owner / Platform / subscription | Owner Organization membership and Platform audience/commercial lifecycle are distinct; trusted manual subscription receipts | Catalog retry and Manager guidance fixes only | Source audit plus current web builds and scoped tests; automatic SaaS billing/provider checkout and production hosting remain separate work |

## Qualification boundary

Current source tests and build evidence qualify the repairs named above. They do
not establish normal authenticated startup, live POS↔Cloud convergence across an
offline fleet, Windows release behavior, physical Android/iOS devices, bank
acceptance, deployment, full security certification or printer infrastructure.
Logo selection, advance-editing policy and the reported enrollment-security
issue remain separately scoped. No missing product capability is represented as
implemented merely because a route, model or component exists.
