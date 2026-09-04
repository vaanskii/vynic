# Vynic Audit Event / Action / Status Taxonomy Audit

Investigation and reporting only. No enum, event name, status, row, or UI
label was changed. Findings are from code tracing on this repository state;
no live Venue data was read.

Paths are relative to `apps/operations/lib/` (POS/Manager Flutter) unless
prefixed with `backend/` (`apps/backend/src/`).

## A. Executive summary

- The POS has **two unrelated audit stores in one Hive box** (`auditLogBox`):
  the per-Order `AuditReport` (typed `AuditEventType`, synced to
  `pos.AuditReport/AuditEvent`, shown in POS Admin and Manager) and the
  append-only `AuditEventLog` (free-string `action`, synced to
  `pos.AuditEventLog`). **Nothing reads `AuditEventLog`**: the POS reader
  `AuditRepository.getAuditLogs` has no caller, and no backend or Platform
  Admin endpoint queries the table. `ORDER_CREATED`, `TAKEAWAY_ORDER_CREATED`,
  every `MoneyAudit` event, `CLOSURE_RECOVERED`, and all `developer.*` actions
  are therefore **write-only history**.
- The per-Order report has **no creation semantics**. Walk-In creation emits
  only `ADD_ITEM` rows (or an empty report), Takeaway creation emits **no
  report at all** until the first later edit or close, Package application
  emits **no report event**, and Reservation activation is indistinguishable
  from a Walk-In except by `openedByName`.
- Closure semantics are correct after the recent integrity work: `CLOSE`,
  `INTERNAL_CLOSE`, `CANCEL_TABLE`, `RESTORE` carry structured `details`
  including `closureId`, `businessDate`, `paymentMethod`, `paymentBreakdown`,
  `cashAmount`, `cardAmount`, `advanceApplied`, `collectedNow`, `isFiscal`.
- **Card provider is already durable.** The payment dialog selects `tbc` or
  `bog`; it is persisted as the Sale `paymentMethod` (`card-tbc` / `card-bog`)
  and as `paymentBreakdown` keys, and both reach `AuditEvent.details`. A split
  can hold cash plus **one** bank provider (`TablePaymentSelection.bankProvider`
  is a single value); two providers in one close are not representable today.
  Any provider other than `bog` collapses to `card-tbc`; Credo does not exist.
- **P0 accountability gaps**: a Manager-originated cancel
  (`ORDER_STATUS_UPDATE status=cancelled`) and a Takeaway cancel from the home
  panel free the table/queue and set `cancelled` with **no `CANCEL_TABLE` event
  and no cancelled Sale row**; Manager `ORDER_CANCEL` and the Admin close-day
  fixer **hard-delete the Order and delete its audit report**; an Order emptied
  by a table move is closed with **no closing event and its report stays
  `OPEN`/unlocked forever**; startup closure recovery writes the report `CLOSE`
  attributed to the original operator with no recovery marker.
- Recommendation: keep one business event per type (`CLOSE`, not
  `CLOSE_CASH`/`CLOSE_CARD_TBC`), keep payment specificity in `details`, and
  add additive creation/lifecycle types (`CREATE_WALKIN`, `CREATE_TAKEAWAY`,
  `APPLY_PACKAGE`, `ACTIVATE_RESERVATION`, `MOVE_ITEMS`, `DELETE_ORDER`) plus a
  `source` detail. Deploy the backend normalizer **before** any POS emits a new
  type, because unknown types are stored as `CUSTOM` with the raw string lost.

## B. Current AuditEvent inventory

### B1. Per-Order `AuditReport` events (`core/models/audit_report.dart`)

Storage: `auditLogBox['audit_report_order_<orderId>']`. Cloud:
`pos.AuditReport` + `pos.AuditEvent` via `backend/pos/sync/application/ingest-audit-reports.service.ts`
(events are deleted and rewritten per revision; `type` passes through
`normalizeAuditEventType`). Readers: `windows_pos/widgets/admin/admin_audit_log_section.dart`,
`mobile_app/.../mobile_admin_audit_tab.dart` (via `GET /mobile/audit`,
`backend/mobile/services/mobile-reports.service.ts`).

| TYPE | Emitted by | Business action | Payload | POS label | Status |
| --- | --- | --- | --- | --- | --- |
| `ADD_ITEM` | `OrderRepository.createOrder` (initial items), `menu_screen.dart` diff, `AuditOrderDiffService` (Edge/LAN `ORDER_UPDATE`), `OrderItemTransfer.apply` (destination), backend `mobile-orders.service.ts` (Cloud-side mirror), legacy import | new line **or** quantity increase **or** line moved in from another table | `itemName`, `previousQty`, `newQty`, `note` (comment diff / "გადმოტანილია — <src>") | დამატება | active, TOO_GENERIC |
| `REDUCE_QTY` | same diff paths, `OrderItemTransfer.apply` (source) | quantity decrease **or** line moved out | same | რაოდენობის შემცირება | active, TOO_GENERIC |
| `DELETE_ITEM` | same diff paths | line removed (qty to 0) | same | პოზიციის წაშლა | active |
| `CLOSE` | `CloseTableTransaction` -> `AuditRepository.finalizeOrderClosureAudit` | fiscal close (cash/card/split), also crash recovery completion | `itemName='ORDER'`, `details` (B1a) | ფისკალური დახურვა | active, CORRECT |
| `INTERNAL_CLOSE` | same | non-fiscal close | same, `isFiscal=false`, `paymentMethod='non-fiscal'` | არაფისკალური დახურვა | active, CORRECT |
| `RESTORE` | `SalesRepository.restoreClosedOrderFromSale` -> `reopenOrderAuditReport` | operator reopened a closed Order | `originalClosureId`, `originalSaleId`, `restoredGrossAmount`, `originalIsFiscal`, `advanceAmount`, `businessDate`, tables | შეკვეთის აღდგენა | active, CORRECT |
| `CANCEL_TABLE` | `order_detail_screen.dart` (POS cancel with password), `logAdminAction('cancel_table')` (no remaining caller) | operator cancelled an Order (any kind, including Takeaway) | `previousQty`=total item qty, `note`=comment + "Approved by" | მაგიდის გაუქმება | active, MISLEADING for Takeaway |
| `CUSTOM` | never written by current code; parser fallback | unknown/legacy | — | ჩანაწერი | fallback only |

B1a. `CLOSE`/`INTERNAL_CLOSE` `details` (`close_table_transaction.dart:_closureDetails`):
`orderId`, `tableNumbers`, `tableRefs`, `floor`, `actorId`, `actorName`,
`businessDate`, `closureId`, `isFiscal`, `grossAmount`, `paymentMethod`,
`paymentBreakdown`, `cashAmount`, `cardAmount`, `advanceApplied`,
`collectedNow`, `serviceFee`, `discountAmount`, `manualAdjustmentAmount`,
optional `customPaymentLabel`.

Report envelope: `status` `OPEN | CLOSED | CANCELLED`, `locked`,
`openedById/Name`, `closedById/Name`, `closedAt`. `locked` reports reject
appends (`StateError`), except `reopenOrderAuditReport`.

Accepted aliases (POS `auditEventTypeFromString` and backend
`normalizeAuditEventType`): `ADDITEM`, `ADD`, `REDUCE_QUANTITY`, `REDUCEQTY`,
`DELETEITEM`, `REMOVE_ITEM`, `CLOSED`, `NON_FISCAL_CLOSE`, `NONFISCAL_CLOSE`,
`RESTORED`, `REOPEN`, `REOPENED`, `SALE_RESTORED_TO_ORDER`, `CANCELTABLE`, plus
lowercase snake forms. Unknown -> quantity inference -> `CUSTOM`.

### B2. Append-only `AuditEventLog` (`core/models/audit_event_log.dart`, `core/services/audit/audit_event_service.dart`)

Storage: `auditLogBox[<uuid>]` with `action`, `userId`, `data` (JSON string),
`deviceType` (`windows|mobile|web`), `synced`. Cloud: `POST /sync/audit-logs`
-> `pos.AuditEventLog` (dedup by id). **Readers: none** (POS
`getAuditLogs` unused; backend has only ingestion; Platform Admin does not
query it).

| ACTION | Emitted by | Business action | Data | Status |
| --- | --- | --- | --- | --- |
| `ORDER_CREATED` | `OrderRepository.createOrder` (Walk-In, Package, Reservation activation, move-to-free-table, legacy LAN create) | Order created | `orderId`, `tableNumbers`, `total`, `floor` | active, write-only, TOO_GENERIC (does not say Walk-In vs Package vs activation) |
| `TAKEAWAY_ORDER_CREATED` | `OrderRepository.createTakeAwayOrder` (POS only) | Takeaway created | `orderId`, `customerName`, `total` | active, write-only |
| `ORDER_DISCOUNT_CHANGED` | `MoneyAudit.orderDiscountChanged` | — | — | **dead** (no caller; no UI writes `discountAmount`) |
| `ORDER_MANUAL_ADJUSTMENT_CHANGED` | `order_detail_screen.dart:1295` | manual adjustment | prev/new adjustment and totals | active, write-only |
| `ORDER_SERVICE_FEE_CHANGED` | `order_detail_screen.dart:780,859`, `PosCommandApplier.updateOrder` | service fee toggle/percent | prev/new included, percent, totals | active, write-only |
| `SALE_CANCELLED` | `SalesRepository.cancelSaleRecord` (Admin sales void) | Sale voided | `orderId`, `businessDate`, `totalAmount`, `reason`, `historical` | active, write-only |
| `SALE_RESTORED_TO_ORDER` | `SalesRepository.restoreClosedOrderFromSale` | duplicate of report `RESTORE` | `orderId`, `businessDate`, `totalAmount` | active, DUPLICATE |
| `BUSINESS_DATE_CHANGED` | `BusinessDayRepository` (Admin re-date) | business date changed | prev/new date, reason, backdated | active, write-only |
| `RECEIPT_SERVICE_FEE_POLICY_CHANGED` | `admin_screen.dart:2019` | receipt line visibility | prev/new flags | active, write-only |
| `REPORT_COST_ASSUMPTION_CHANGED` | `admin_screen.dart` (5 sites) | monthly report inputs | field, scope, prev/new | active, write-only |
| `ADVANCE_RECORDED` | `order_detail_screen.dart:1092` | advance taken/changed | prev/new amount, `businessDate`, `receiptId` | active, write-only |
| `CLOSURE_RECOVERED` | `ClosureRecoveryService` | startup completed/abandoned an interrupted closure | `closureId`, `orderId`, `businessDate`, `grossSaleAmount`, `recoveryAction` (`finished|abandoned|orphaned|deferred`) | active, write-only; `userId` = original operator, not SYSTEM |
| `reservation_cancelled` | `admin_reservations_section.dart:1378` via `logAdminAction` | Reservation cancelled in Admin | reservation snapshot, prev/new status | active, write-only, lowercase legacy naming |
| `developer.unlocked`, `developer.printers.save`, `developer.backup.create`, `developer.backup.restore`, `developer.recovery.pinReset`, `developer.data.wipe.start`, `developer.data.wipe.done` | `DeveloperAccess.logAction` | developer service actions | action-specific, `terminal` | active, write-only; `userId='developer:<jti>'` |

`logAdminAction` (`audit_repository.dart:704`) is a compatibility shim: for
`cancel_table`/`add_item`/`reduce_quantity`/`remove_item` with an `orderId` it
converts to report events; otherwise it writes a `legacy_event_<micros>` row
**and** an `AuditEventLog` row. Only `reservation_cancelled` still uses it.

### B3. Legacy rows (`legacy_event_<micros>`, read-only)

`_buildLegacyAuditReports` derives synthetic reports (`legacy_report_order_<id>`)
from `actionType` in `add_item`, `reduce_quantity`, `remove_item`,
`close_table`, `internal_close`, `restore_table`, `reopen_table`,
`sale_restored_to_order`, `cancel_table`, `custom`. No current writer except
the `logAdminAction` fallback. LEGACY_ONLY.

### B4. Platform control-plane audit (`backend/platform/platform-audit.service.ts`)

`pos.PlatformAuditEvent` with 20 dotted actions (`organization.*`, `venue.*`,
`device.*`). Actor is always a `PlatformUser`. Deliberately separate from
Venue staff audit. CORRECT; out of scope for restaurant taxonomy.

### B5. Not audit, but easily confused

- `SyncHub` `SyncEvent.action` (`created|updated|status_changed|deleted|reserved|freed`) — in-process UI refresh only.
- Backend gateway broadcasts (`order_updated`, `order_cancelled`, `audit_updated`, `data_updated`) — websocket refresh only.
- Edge contract command types (`ORDER_UPDATE`, `ORDER_CANCEL`, `ORDER_STATUS_UPDATE`, `TAKEAWAY_ORDER_UPSERT`, `DINE_IN_ORDER_UPSERT`, `RESERVATION_CREATE/STATUS_UPDATE/DELETE`, `EXPENSE_CREATE`, `STAFF_*`, three print types, `NOOP`) — transport intents, journaled in `edge_command_journal`, not audit.

## C. Current Order statuses (`core/models/order_status.dart`)

| Name | Meaning | Writers | Terminal | Revenue | Aliases |
| --- | --- | --- | --- | --- | --- |
| `pending` | created, not yet sent to kitchen | `createOrder`, `createTakeAwayOrder` | no | none | — |
| `confirmed` | sent to kitchen | POS confirm button, Package creation, Reservation activation, Manager upserts (auto-confirmed) | no | none | — |
| `preparing` | — | **never written** by POS/backend; Manager UI only labels it | no | none | LEGACY_ONLY |
| `served` | — | **never written**; label only | no | none | LEGACY_ONLY |
| `closed` | settled (fiscal or internal) or emptied by transfer | `CloseTableTransaction`, `OrderItemTransfer.releaseEmptiedOrder` | yes | via Sale only | `paid` (read alias) |
| `cancelled` | voided | POS cancel, Takeaway panel cancel, Manager `ORDER_STATUS_UPDATE` | yes | none; POS path writes an `isCancelled` Sale row | `canceled` (read) |
| `unknown` | unparseable | never written | — | — | — |

`paid`: read-only alias for `closed`. Not written by current POS/backend code,
but `PosCommandApplier.updateOrderStatus` passes any Cloud-sent status through
and `OrderRepository.updateOrderStatus` still frees tables on `'paid'`; the
backend only ever sends `cancelled`. Treat as LEGACY_ONLY but not yet sealed.

`OrderRepository.isOrderStatusActive` = not `paid|cancelled|closed`.
Close Day deletes `closed` Order rows for the day (the Sale is the durable record).

## D. Current Table states (`core/models/table.dart`, `table_operational_status.dart`)

Persisted fields: `isReserved`, `activeOrderId`, `reservationId`, `reservedBy`,
`currentBill`. Derived, never persisted: `free` (no order, not reserved),
`occupied` (`activeOrderId != null`), `reserved` (`isReserved` without order).

| Transition | Function | Audit |
| --- | --- | --- |
| free -> occupied | `TableRepository.reserveTable` (from `createOrder`, mobile dine-in upsert, activation) | none (SyncHub `reserved`) |
| free -> reserved | `reserveTableForReservation` (booking for today) | none |
| occupied/reserved -> free | `freeTable` (close, cancel, hard delete, transfer emptied) | none (SyncHub `freed`) |

There is no persisted table status enum and no table-level audit action.
`MOVE_TABLE` does not exist as an operation: a move is an item transfer
between two Orders (see G).

## E. Current Reservation statuses (`core/models/reservation_status.dart`)

| Status | Written by | Reservation STATUS? | Audit ACTION today |
| --- | --- | --- | --- |
| `pending` | `createReservation` default (POS UI create) | yes | none |
| `preparing` | accepted by parser and `syncTableReservationsForCurrentDate`; no current writer found | legacy/unclear | none |
| `confirmed` | website bridge (`RESERVATION_CREATE status=confirmed`), Manager create default, Admin panel status change | yes | none |
| `in-progress` | `ActivateReservationTransaction` (manual and automatic) | yes | none (Order gets `ORDER_CREATED` log + `ADD_ITEM`) |
| `completed` | `completeReservationByOrderId` (close, emptied transfer), Close Day for activated bookings | yes | none |
| `cancelled` | Admin panel, Manager/website `RESERVATION_STATUS_UPDATE`, `cancelReservationByOrderId` (hard delete of linked Order) | yes | `reservation_cancelled` (Admin panel only; write-only log) |
| `no-show` | Close Day for never-activated bookings | yes | none |
| physical delete | `deleteReservation` (POS, Manager `RESERVATION_DELETE`) | n/a | none |

Website side: `WebsiteReservationStatus` `PENDING | CONFIRMED | FAILED | COMPLETED`
(payment lifecycle, separate entity). Manager blocks `completed`/`in-progress`
from mobile.

## F. Current Sale / payment states (`core/models/sale_record.dart`)

| Concept | Representation | Kind |
| --- | --- | --- |
| Fiscal Sale | `recordType='sale'`, `isFiscal=true`, `paymentMethod` in `cash`, `card-tbc`, `card-bog`, `split`, legacy `card`, legacy `other` (+`customPaymentLabel`) | row type + flag |
| Internal Sale | `recordType='sale'`, `isFiscal=false`, `paymentMethod='non-fiscal'`, `collectedNow=0` | flag |
| Cancelled Order record | `paymentMethod='cancelled'`, `isFiscal=false`, `isCancelled=true`, `finalTransaction.type='cancelled_order'` (POS cancel path only) | flag + sentinel method |
| Voided Sale | `isCancelled=true`, `cancelledAt/By`, `cancellationReason` (Admin void) | flag |
| Restored Sale | `restoredToOrder=true`, `restoredAt/By`; excluded by revenue predicate | flag |
| Advance receipt | `recordType='advance_receipt'`, `advanceReceiptId`, `appliedToClosureId` | row type |
| Payment breakdown | `paymentBreakdown` map keyed `cash`, `card-tbc`, `card-bog`, `other:<label>`, `advance` | structured |
| Closure identity | `closureId`, `grossSaleAmount`, `advanceApplied`, `collectedNow`, `closedById` | fields |

Nothing here needs a duplicate audit event; the `CLOSE` event already copies
the money split into `details`.

## G. Walk-In lifecycle (POS)

| Step | Report event | Order status | Table | Sale | Semantic |
| --- | --- | --- | --- | --- | --- |
| open table + first submit (`menu_screen.dart:1215` -> `createOrder`) | `ADD_ITEM` × items (or empty report); log `ORDER_CREATED` | `pending` | occupied | — | **MISSING** `CREATE_WALKIN` |
| Manager dine-in create (`DINE_IN_ORDER_UPSERT`) | **none** (no report, no log) | `confirmed` | occupied | — | MISSING |
| add / increase | `ADD_ITEM` | unchanged | — | — | TOO_GENERIC (new line vs +qty) |
| decrease | `REDUCE_QTY` | — | — | — | CORRECT |
| remove | `DELETE_ITEM` | — | — | — | CORRECT |
| confirm / kitchen print | none | `confirmed` | — | — | not audited (acceptable) |
| print check | none | — | — | — | not audited |
| service fee / manual adjustment | none in report; log `ORDER_SERVICE_FEE_CHANGED` / `ORDER_MANUAL_ADJUSTMENT_CHANGED` | — | — | — | write-only |
| advance | none in report; log `ADVANCE_RECORDED` | — | — | `advance_receipt` row | write-only |
| move items to other/free table | `ADD_ITEM` (dest, note "გადმოტანილია"), `REDUCE_QTY` (src, note "გადატანილია"); new target: `ORDER_CREATED` log + empty report | src may become `closed` | src freed | none | MISLEADING (`MOVE_ITEMS` hidden in add/reduce); emptied src has **no closing event, report stays OPEN unlocked** |
| fiscal close | `CLOSE` (+details) ; report `CLOSED`, locked | `closed`, `closureId` | freed | Sale | CORRECT |
| internal close | `INTERNAL_CLOSE` | `closed` | freed | non-fiscal Sale | CORRECT |
| cancel (POS, password) | `CANCEL_TABLE`; report `CANCELLED`, locked | `cancelled` | freed | cancelled record | CORRECT |
| cancel (Manager `ORDER_STATUS_UPDATE`) | **none** | `cancelled` | freed | **none** | MISSING (P0) |
| Manager `ORDER_CANCEL` / Admin close-day fixer | **report deleted** | row deleted | freed | none | MISSING (P0) |
| restore | `RESTORE`; report reopened | open again | re-occupied | Sale flagged restored | CORRECT |
| re-close | new `CLOSE` (closure B) | `closed` | freed | new Sale | CORRECT |
| crash recovery finish | `CLOSE` attributed to original actor; log `CLOSURE_RECOVERED` | `closed` | freed | existing Sale | MISLEADING actor/provenance |

## H. Takeaway lifecycle

| Step | Report event | Order status | Sale | Semantic |
| --- | --- | --- | --- | --- |
| create (POS `createTakeAwayOrder`) | **no report created**; log `TAKEAWAY_ORDER_CREATED` | `pending` (`TA-<id>`, floor `takeaway`) | — | MISSING `CREATE_TAKEAWAY`; first visible report row is the first later edit or the close |
| create (Manager `TAKEAWAY_ORDER_UPSERT`) | none | `confirmed` | — | MISSING |
| edit items | diff events (report created lazily, `openedAt=order.createdAt`) | — | — | TOO_GENERIC |
| cancel (home panel `updateOrderStatus('cancelled')`) | **none** | `cancelled` | **none** | MISSING (P0) |
| cancel (order detail) | `CANCEL_TABLE` | `cancelled` | cancelled record | MISLEADING name for Takeaway |
| close | `CLOSE`/`INTERNAL_CLOSE` | `closed` | Sale | CORRECT |
| restore / re-close | `RESTORE` / `CLOSE` | — | — | CORRECT |

## I. Reservation lifecycle (real advance bookings)

| Action | Event today | Reservation status | Order/Table | Semantic |
| --- | --- | --- | --- | --- |
| create (POS UI, Manager, website bridge) | none | `pending` / `confirmed` | table `reserved` if today | MISSING `CREATE_RESERVATION` |
| edit tables / pre-order / details | none | unchanged | — | MISSING `UPDATE_RESERVATION` |
| confirm (Admin panel) | none | `confirmed` | — | MISSING |
| activate (manual / automatic) | `ORDER_CREATED` log + `ADD_ITEM` per pre-order item; actor `System (Reservation)` when automatic | `in-progress` | Order `confirmed`, occupied | MISSING `ACTIVATE_RESERVATION` (report identical to a Walk-In) |
| cancel (Admin) | `reservation_cancelled` (write-only log) | `cancelled` | freed | write-only |
| cancel (Manager/website) | none | `cancelled` | freed | MISSING |
| complete (close) | none reservation-specific (`CLOSE` on the Order) | `completed` | — | acceptable if `CLOSE.details` names the reservation (it does not today) |
| no-show / complete at Close Day | none | `no-show` / `completed` | — | MISSING |
| delete | none | row removed | — | MISSING |
| restore of linked Order | `RESTORE` on Order | back to `in-progress` | — | CORRECT |

## J. Package lifecycle

| Action | Event | Semantic |
| --- | --- | --- |
| create / update / disable / delete Package definition (`PackageRepository`) | none | MISSING (configuration change) |
| apply Package to tables (`createOrderForPackage`) | `ORDER_CREATED` log; **empty report** (items go to `packageItems`, not `items`); status `confirmed` silently | MISSING `APPLY_PACKAGE` |
| edit a Package Order's items | diff events on `items` only | TOO_GENERIC |
| close / cancel / restore | same as Walk-In | CORRECT |

## K. Payment / close lifecycle

Payment selection (`core/services/pos/table_payment_service.dart`):
`TablePaymentMethod {cash, bank, split}`, `bankProvider` `tbc|bog` (anything
else -> `tbc`). `resolvePaymentMethod` -> `cash` | `card-tbc` | `card-bog` |
`split`; `buildSaleBreakdown` -> `{cash: x, card-tbc|card-bog: y}`.

Durable chain: selection -> `ClosureJournalEntry` -> Sale
(`paymentMethod`, `paymentBreakdown`) -> `CLOSE.details.paymentMethod`,
`paymentBreakdown`, `cashAmount`, `cardAmount`. Cloud keeps `details` as JSON.

Not representable today: two card providers in one close; `other`/custom
label (no current UI writer, read-only legacy); a provider besides TBC/BOG.

## L. Staff / Admin lifecycle

| Action | POS local | Edge command | Audit |
| --- | --- | --- | --- |
| staff create / rename / PIN / role / delete | `UserRepository` | `STAFF_*` | **none** anywhere (POS, Edge, backend `mobile-users.service.ts`) |
| login | — | — | none |
| admin override (cancel password, restricted actions) | captured only as `CANCEL_TABLE.note` "Approved by …" | — | no structured `approvedBy` on the event |
| manual repair: hard delete Order, delete open Orders for date | `deleteOrderAndCleanup` | `ORDER_CANCEL` | none; **deletes the audit report** |
| settings: service-fee receipt policy, cost assumptions, business date | — | — | write-only log events |
| internal close authorization | `INTERNAL_CLOSE` actor only | — | no approver |
| developer service actions | — | — | `developer.*` write-only |

## M. Expense lifecycle

Create only (`SalesRepository.saveExpenseRecord`, Edge `EXPENSE_CREATE`,
Manager `mobile-expenses.service.ts`). No edit or delete path exists in the
POS. No audit event on any path. Expense rows carry `sourceId` for
convergence; there is no status model.

## N. Menu / configuration lifecycle

`MenuRepository` category/subcategory/item add/update/delete and kitchen
routing, `PackageRepository` CRUD/activation, printer settings, service-fee
rate: **no audit** except `developer.printers.save`, `RECEIPT_SERVICE_FEE_POLICY_CHANGED`,
`REPORT_COST_ASSUMPTION_CHANGED`. Price and availability changes are invisible.

Close Day (`CloseDayTransaction`): blocked -> `developer.log` only; success ->
`settings.currentDate` advanced, reservations finalized, closed Orders
deleted; **no audit event**. Admin business-date change emits
`BUSINESS_DATE_CHANGED` (write-only).

## O. Restore / Recovery / Backup distinctions

| Meaning | Current naming | Where | Assessment |
| --- | --- | --- | --- |
| Operator reopened a closed Order | report `RESTORE` + log `SALE_RESTORED_TO_ORDER` | `SalesRepository.restoreClosedOrderFromSale` | CORRECT (one duplicate) |
| System finished/abandoned an interrupted closure | log `CLOSURE_RECOVERED` (`recoveryAction`); report gets a normal `CLOSE` attributed to the journal actor | `ClosureRecoveryService` | MISLEADING provenance: the visible report row looks like a normal operator close |
| Data backup restored | `developer.backup.restore` (developer path only); Admin `restoreDataBackupFromFile` unaudited | `admin_developer_section.dart`, `admin_screen.dart:2319` | MISSING for the Admin path |
| Data wipe | `developer.data.wipe.*` | developer only | write-only |

The three meanings do not share one label today, but two of them are
invisible to every reader.

## P. Master current-state matrix

Status key: CORRECT, TOO_GENERIC, MISLEADING, MISSING, DUPLICATE, LEGACY_ONLY, UNCLEAR.
"Log" = write-only `AuditEventLog`; "Report" = per-Order `AuditReport`.

| DOMAIN | BUSINESS ACTION | CURRENT EVENT | ENTITY STATUS | DETAILS | ACTOR/SOURCE | CORRECT? | PROBLEM | PROPOSED |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Walk-In | open table / create Order (POS) | Report `ADD_ITEM`×n; Log `ORDER_CREATED` | Order `pending`; table occupied | items only | waiter username | MISSING | no creation row in report | `CREATE_WALKIN` (details: tables, floor, guestCount?, source) |
| Walk-In | create from Manager | none | `confirmed` | — | `waiterName` payload | MISSING | invisible | `CREATE_WALKIN` source=MANAGER |
| Walk-In | create by legacy LAN | Log `ORDER_CREATED` | `pending` | — | `Remote` | MISSING | — | same, source=LAN |
| Takeaway | create (POS) | Log `TAKEAWAY_ORDER_CREATED`; no report | `pending` | name/total | waiter | MISSING | report absent until later edit | `CREATE_TAKEAWAY` (customer, pickupTime) |
| Takeaway | create (Manager) | none | `confirmed` | — | payload | MISSING | — | same, source=MANAGER |
| Package | define/update/disable/delete | none | Package `isActive` | — | admin | MISSING | config invisible | `PACKAGE_CONFIG_CHANGED` (log) |
| Package | apply to Order | Log `ORDER_CREATED`; empty report | Order `confirmed` | — | waiter | MISSING | nothing shows package | `APPLY_PACKAGE` (packageId, name, guests, unitPrice, items) |
| Reservation | create | none | `pending`/`confirmed` | — | POS user / Manager / website | MISSING | — | `CREATE_RESERVATION` |
| Reservation | edit | none | unchanged | — | — | MISSING | — | `UPDATE_RESERVATION` |
| Reservation | confirm | none | `confirmed` | — | — | MISSING | — | `CONFIRM_RESERVATION` (or `UPDATE_RESERVATION` with status delta) |
| Reservation | activate | `ADD_ITEM`×preorder; Log `ORDER_CREATED` | `in-progress`; Order `confirmed` | — | user or `System (Reservation)` | MISSING | looks like Walk-In | `ACTIVATE_RESERVATION` (reservationId, customer, source=SYSTEM when automatic) |
| Reservation | cancel (Admin) | Log `reservation_cancelled` | `cancelled` | snapshot | admin | LEGACY_ONLY | unread | `CANCEL_RESERVATION` |
| Reservation | cancel (Manager/website) | none | `cancelled` | — | — | MISSING | — | `CANCEL_RESERVATION` source |
| Reservation | complete | none | `completed` | — | — | UNCLEAR | implied by `CLOSE` | add `reservationId` to `CLOSE.details`; optional `COMPLETE_RESERVATION` |
| Reservation | no-show (Close Day) | none | `no-show` | — | system | MISSING | — | `NO_SHOW_RESERVATION` source=SYSTEM |
| Reservation | delete | none | row gone | — | — | MISSING | — | `DELETE_RESERVATION` |
| Order items | add line | `ADD_ITEM` | — | qty 0->n | waiter | CORRECT | — | keep |
| Order items | increase qty | `ADD_ITEM` | — | qty a->b | waiter | TOO_GENERIC | same type as new line | `UPDATE_ITEM_QUANTITY` (or keep `ADD_ITEM` + `previousQty>0` as the discriminator) |
| Order items | decrease qty | `REDUCE_QTY` | — | — | waiter | CORRECT | rename candidate `UPDATE_ITEM_QUANTITY` | keep |
| Order items | remove line | `DELETE_ITEM` | — | — | waiter | CORRECT | — | keep |
| Order items | comment change only | none (only when qty also changed) | — | note | — | MISSING | — | `UPDATE_ITEM_NOTE` (P3) |
| Order items | move to other table | `ADD_ITEM`/`REDUCE_QTY` + Georgian note | src maybe `closed` | note text | waiter | MISLEADING | move hidden in add/reduce; emptied source never closed in report | `MOVE_ITEMS` on both reports (details: fromOrderId, toOrderId, tables); `CLOSE_EMPTY`/`TRANSFER_CLOSE` for the emptied source |
| Order money | manual adjustment | Log `ORDER_MANUAL_ADJUSTMENT_CHANGED` | — | prev/new | waiter | TOO_GENERIC | not in report | mirror into report as `ADJUST_ORDER` |
| Order money | service fee | Log `ORDER_SERVICE_FEE_CHANGED` | — | prev/new | waiter/manager | write-only | — | `SERVICE_FEE_CHANGED` in report |
| Order money | discount | `ORDER_DISCOUNT_CHANGED` | — | — | — | LEGACY_ONLY | no caller, no UI | drop or wire when discount UI exists |
| Order money | advance recorded | Log `ADVANCE_RECORDED`; `advance_receipt` Sale | — | amounts, receiptId | waiter | write-only | not in report | `RECORD_ADVANCE` in report |
| Order | confirm / kitchen print | none | `confirmed` | — | — | acceptable | — | optional `SEND_TO_KITCHEN` (P3) |
| Order | print check | none | — | — | — | acceptable | — | optional `PRINT_CHECK` (P3) |
| Close | fiscal cash/card/split | `CLOSE` | `closed` | full money details | actor | CORRECT | — | keep |
| Close | internal | `INTERNAL_CLOSE` | `closed` | `isFiscal=false` | actor | CORRECT | no approver | add `approvedBy` |
| Close | crash recovery finish | `CLOSE` | `closed` | same | original operator | MISLEADING | no recovery marker | `CLOSE` + `details.source=SYSTEM_RECOVERY`, `recoveryAction` |
| Cancel | POS cancel | `CANCEL_TABLE` | `cancelled` | note "Approved by" | waiter | CORRECT (name misleading for Takeaway) | approver in free text | `CANCEL_ORDER` alias + `approvedBy`, `reason` |
| Cancel | Takeaway home panel | none | `cancelled` | — | — | MISSING (P0) | no event, no cancelled Sale | `CANCEL_ORDER` |
| Cancel | Manager status=cancelled | none | `cancelled` | — | — | MISSING (P0) | — | `CANCEL_ORDER` source=MANAGER |
| Delete | Manager `ORDER_CANCEL`, Admin fixer, delete-open-for-date | none; report deleted | row removed | — | `mobile_manager` / admin | MISSING (P0) | history destroyed | `DELETE_ORDER` and keep the report (lock it) |
| Restore | reopen closed Order | `RESTORE` + Log `SALE_RESTORED_TO_ORDER` | reopened | closure/sale ids | operator | CORRECT/DUPLICATE | — | keep `RESTORE`; drop log duplicate later |
| Sale | void Sale (Admin) | Log `SALE_CANCELLED` | Sale `isCancelled` | reason | admin | write-only | not in report | `VOID_SALE` in report |
| Staff | create/rename/PIN/role/delete | none | — | — | — | MISSING | — | `STAFF_CHANGED` (log) with field, no PIN values |
| Staff | login | none | — | — | — | MISSING | out of scope unless required | optional |
| Expense | create | none | — | — | — | MISSING | — | `EXPENSE_CREATED` (log) |
| Menu | category/item CRUD, price, availability | none | — | — | — | MISSING | — | `MENU_CHANGED` (log) |
| Close Day | start/blocked/success | none | date advanced | — | admin | MISSING | — | `CLOSE_DAY` (log) with blocked reasons |
| Business date | re-date | Log `BUSINESS_DATE_CHANGED` | — | prev/new | admin | write-only | — | keep, surface |
| Backup | Admin restore | none | — | — | admin | MISSING | — | `BACKUP_RESTORED` (log) |
| Backup | developer restore/wipe | `developer.*` | — | — | developer token | write-only | — | keep |
| Settings | receipt policy, cost assumptions | Log events | — | — | admin | write-only | — | keep, surface |
| Platform | control-plane actions | `PlatformAuditEvent` | — | metadata | PlatformUser | CORRECT | — | keep separate |

## Q. Missing / misleading events (Q8 answer)

No meaningful audit event at all today:

1. Walk-In / Takeaway / Package / Reservation-activation **creation** in the report.
2. Manager-originated Order cancel; Takeaway cancel from the home panel.
3. Hard delete of an Order (Manager `ORDER_CANCEL`, Admin close-day fixer, delete-open-orders-for-date) — and the report is erased.
4. Emptied-by-transfer close of the source Order.
5. Every Reservation transition except Admin-panel cancel.
6. Package definition changes and Package application.
7. Staff CRUD, login, PIN/role changes (POS, Edge, Manager).
8. Expense create; menu/category/item/price/availability changes; printer config (non-developer).
9. Close Day (blocked and successful); Admin backup restore.
10. Item comment-only changes; kitchen/check prints (arguably acceptable).

Misleading today:

- `CANCEL_TABLE` for Takeaway; approver only inside `note`.
- `ADD_ITEM` for both new line and quantity increase and for lines moved in.
- Recovery-finished `CLOSE` attributed to the operator with no `SYSTEM_RECOVERY` marker.
- `ORDER_CREATED` log does not say Walk-In / Package / activation.
- `Reservation activation` report is identical to a Walk-In.

## R. Recommended target taxonomy (not implemented)

### Action / event (`AuditEventType`, per-Order report)

Keep: `ADD_ITEM`, `REDUCE_QTY`, `DELETE_ITEM`, `CLOSE`, `INTERNAL_CLOSE`,
`RESTORE`, `CANCEL_TABLE` (display alias `CANCEL_ORDER`).

Add (additive): `CREATE_WALKIN`, `CREATE_TAKEAWAY`, `APPLY_PACKAGE`,
`ACTIVATE_RESERVATION`, `MOVE_ITEMS`, `DELETE_ORDER`, `RECORD_ADVANCE`,
`ADJUST_ORDER` (manual adjustment / service fee, `details.field`),
`VOID_SALE`. Optional P3: `UPDATE_ITEM_QUANTITY` (only if the UI must separate
"+1" from "new line"; otherwise `previousQty > 0` already discriminates),
`UPDATE_ITEM_NOTE`, `SEND_TO_KITCHEN`, `PRINT_CHECK`.

Non-Order actions stay in `AuditEventLog` (it is the right shape) but need a
reader and a constant registry: `CREATE_RESERVATION`, `UPDATE_RESERVATION`,
`CONFIRM_RESERVATION`, `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`,
`DELETE_RESERVATION`, `STAFF_CHANGED`, `EXPENSE_CREATED`, `MENU_CHANGED`,
`PACKAGE_CONFIG_CHANGED`, `CLOSE_DAY`, `BACKUP_RESTORED`, plus the existing
`MoneyAuditAction` set. Rename `reservation_cancelled` -> `CANCEL_RESERVATION`
with the lowercase form kept as an alias.

### Entity status (unchanged)

`Order.status` `pending|confirmed|closed|cancelled` (retire `preparing`,
`served`, `paid` as read-only aliases). `Reservation.status`
`pending|confirmed|in-progress|completed|cancelled|no-show`. Table occupancy
derived. Sale flags as in F.

### Structured details (every report event)

`orderId`, `tableRefs`, `floor`, `actorId`, `actorName`, `source`
(`POS|MANAGER|WEBSITE|LAN|EDGE|SYSTEM|SYSTEM_RECOVERY|DEVELOPER`),
`businessDate`; close events add `closureId`, `isFiscal`, `paymentMethod`,
`paymentBreakdown`, `cashAmount`, `cardAmount`, `advanceApplied`,
`collectedNow`, `approvedBy`; creation events add `orderKind`
(`WALK_IN|TAKEAWAY|PACKAGE|RESERVATION`), `reservationId`, `packageId`,
`customerName`, `pickupTime`; cancel/delete add `reason`, `approvedBy`.

Do not encode `source`, payment method, provider, or order kind into type names.

## S. `CLOSE` vs `CLOSE_CASH` / `CLOSE_CARD` / provider (Q3, Q4, Q5)

Recommendation: **Option B** — `type=CLOSE` with `details.paymentMethod`,
`details.paymentBreakdown`, `details.cashAmount`, `details.cardAmount`;
`INTERNAL_CLOSE` stays a separate type because non-fiscal is a different
business event, not a tender.

| Criterion | Option A (`CLOSE_CASH`, `CLOSE_CARD_TBC`, `CLOSE_SPLIT`, …) | Option B (`CLOSE` + details) |
| --- | --- | --- |
| Queryability | one indexed string, but split/mixed closes need extra parsing anyway | `details` is `Json` in Postgres; `paymentMethod` is filterable via JSON path; Sale rows remain the reporting source of truth |
| Reporting | reports already read Sale `paymentBreakdown`, never the audit type | matches how X/Z/monthly/Manager already derive figures |
| Readability | label per type; split still needs amounts from details | one label + a money line rendered from details (POS `note` already does this) |
| Enum explosion | 2 fiscal flags × {cash, card-tbc, card-bog, split, other, custom} × future banks; every value must be added to POS enum, POS parser, backend normalizer, two UIs, `finalizeOrderClosureAudit` guard, closure-recovery and restore tests | zero new types |
| Backwards compatibility | old POS/Manager builds parse new types as `CUSTOM` and lose the "close" meaning; `finalizeOrderClosureAudit` rejects non-`CLOSE` types | fully compatible; details already shipped |
| New banks / providers | new enum value per bank | new `paymentBreakdown` key (`card-<bank>`), already handled by `PaymentUtils.methodLabel` |
| Split payments | `CLOSE_SPLIT` says nothing about which providers | `paymentBreakdown` lists every key; multi-provider split becomes a data-model change only (`TablePaymentSelection`) |
| Advance combinations | would need `CLOSE_CASH_WITH_ADVANCE` | `advanceApplied` already present |
| Custom methods | `CLOSE_OTHER` + label elsewhere | `other:<label>` key and `customPaymentLabel` |
| Internal close | `CLOSE_INTERNAL` already exists as `INTERNAL_CLOSE` | unchanged |

Q4: `CLOSE_CARD_TBC` is derivable from durable data for a single-card close
(`Sale.paymentMethod='card-tbc'`, `CLOSE.details.paymentMethod`), and for the
card portion of a split (`paymentBreakdown['card-tbc']`). It is **not** worth
a type. Q5: split with several providers should be `type=CLOSE`,
`paymentMethod='split'`, `paymentBreakdown={cash: 40, card-tbc: 30, card-bog: 30}`;
the only blocker is the single `bankProvider` in the payment dialog.

## T. `CREATE_WALKIN` / `CREATE_TAKEAWAY` (Q1, Q2, Q6, Q7)

- Q1: **Yes.** Emit `CREATE_WALKIN` as the first event of the report at
  `order.createdAt`, before the initial `ADD_ITEM` rows, with
  `details.orderKind=WALK_IN`, tables, `source`. Also emit for Manager
  dine-in upserts (source=MANAGER) and legacy LAN creates.
- Q2: **Yes.** Emit `CREATE_TAKEAWAY` and create the report eagerly in
  `createTakeAwayOrder` and `upsertMobileTakeawayOrder` (today no report exists
  until the first edit). Details: `customerName`, `customerPhone`, `pickupTime`.
- Q6: `APPLY_PACKAGE` on the Order report (details: `packageId`, `packageName`,
  `packageGuestCount`, `packageUnitPrice`, `packagePrice`, `packageItems`),
  preceded by `CREATE_WALKIN` with `orderKind=PACKAGE`. Package definition CRUD
  is a separate `PACKAGE_CONFIG_CHANGED` log action.
- Q7: Reservation entity events (`CREATE_RESERVATION`, `UPDATE_RESERVATION`,
  `CONFIRM_RESERVATION`, `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`,
  `DELETE_RESERVATION`) belong to the reservation-keyed log with `source`;
  `ACTIVATE_RESERVATION` is the creation event on the Order report (in place of
  `CREATE_WALKIN`) carrying `reservationId` and `customerName`; completion is
  the Order `CLOSE` with `details.reservationId`, with a reservation-keyed
  `COMPLETE_RESERVATION` only if the reservation timeline needs to stand alone.

## U. Backward-compatibility plan

- All proposed report types are **additive**. POS `auditEventTypeFromString`
  returns `custom` for unknown strings (label "ჩანაწერი"); Manager reads
  backend-normalized types. Historical rows need **no migration**.
- **Backend first.** `normalizeAuditEventType` maps unknown strings through
  quantity inference to `CUSTOM` and discards the raw string, so a POS emitting
  a new type before the backend knows it would be stored lossy. Sequence:
  backend normalizer + `CanonicalAuditEventType` -> Manager labels -> POS enum
  and emitters.
- `finalizeOrderClosureAudit` and `reopenOrderAuditReport` guard on exact
  types; unaffected by additive types.
- Display labels can map old + new together: keep `CANCEL_TABLE` stored, show
  "შეკვეთის გაუქმება" for Takeaway based on `floor`; keep `ADD_ITEM` and
  render "+n" when `previousQty > 0`.
- Aliases to add to both parsers when introduced: `CANCEL_ORDER` ->
  `CANCEL_TABLE`; lowercase `reservation_cancelled` -> `CANCEL_RESERVATION`
  (log actions are free strings; the backend only indexes `action`).
- `AuditEventLog.data` is a JSON string on the POS and `Json` on Cloud; a
  `source` field can be added without schema change. `AuditEvent.details` is
  `Json?` on Cloud; no migration for new detail keys.
- Sync revision hashes the serialized report, so adding events to existing
  open reports re-pushes them normally; locked historical reports are untouched.

## V. Prioritized implementation sequence

Status: the four P0 rows landed as Phase 1 (`CancelOrderTransaction`,
repair-only hard delete, `details.source` / `recoveryAction` on close events).
Phase 2 landed the creation taxonomy: `CREATE_WALKIN`, `CREATE_TAKEAWAY`,
`APPLY_PACKAGE`, `ACTIVATE_RESERVATION` as first report event (eager report
for Takeaway and Manager upserts), `MOVE_ITEMS` on both transfer reports, and
the emptied-by-transfer source closed with a locked `TRANSFER_CLOSE` (chosen
over `CLOSE_EMPTY`: it is a distinct business event, not a tender). The
backend normalizer knows all six. `DELETE /mobile/takeaway-orders/:id` marks
the Cloud row cancelled rather than deleting it. Still open: reservation
lifecycle log constants, the `AuditEventLog` reader, staff/expense/menu
events, Manager item-replacement audit on upsert, and labels (P3).

| P | Change | Call sites | Scope |
| --- | --- | --- | --- |
| P0 | Emit `CANCEL_TABLE` (+cancelled Sale record where the POS path writes one) for Manager `ORDER_STATUS_UPDATE status=cancelled` and Takeaway home-panel cancel; route both through one cancellation routine | `pos_command_applier.dart:245`, `home_take_away_section.dart:343`, `order_repository.dart:updateOrderStatus`, `order_detail_screen.dart:2520` | MEDIUM |
| P0 | Stop deleting the audit report on hard delete; append `DELETE_ORDER`, lock the report | `order_repository.dart:deleteOrderAndCleanup`, `pos_command_applier.dart:207`, `admin_close_day_section.dart:1073` | SMALL |
| P0 | Close the emptied source report on transfer (`MOVE_ITEMS` + closing event, lock) | `order_item_transfer.dart:releaseEmptiedOrder` | SMALL |
| P0 | Mark recovery: `CLOSE.details.source=SYSTEM_RECOVERY`, `recoveryAction`; keep operator as `actorId` | `close_table_transaction.dart:_closureDetails`, `closure_recovery_service.dart` | SMALL |
| P1 | `CREATE_WALKIN` / `CREATE_TAKEAWAY` / `APPLY_PACKAGE` / `ACTIVATE_RESERVATION` as first report event; eager report for Takeaway and Manager upserts | `order_repository.dart` (5 creation paths), `activate_reservation_transaction.dart`, backend `audit-event-type.ts`, two label switches | MEDIUM |
| P1 | Backend normalizer + Manager labels for new types (deploy first) | `backend/pos/audit/audit-event-type.ts`, `mobile_admin_audit_tab.dart`, `admin_audit_log_section.dart` | SMALL |
| P1 | `source`/`approvedBy`/`reason` structured details on cancel and close | `order_detail_screen.dart:2520`, `_closureDetails` | SMALL |
| P1 | Reservation lifecycle log events with constants (`ReservationAuditAction`) | `reservation_repository.dart` (create/update/status/delete), `activate_reservation_transaction.dart`, `close_day_transaction.dart` | MEDIUM |
| P1 | A reader for `AuditEventLog` (POS Admin tab or Manager endpoint) so write-only events become history | new backend `GET /mobile/audit-log`, POS `getAuditLogs` consumer | MEDIUM |
| P2 | `MOVE_ITEMS` instead of add/reduce with Georgian note | `order_item_transfer.dart:239-270` | SMALL |
| P2 | Staff, expense, menu, package-config, Close Day, Admin backup restore log events | `user_repository.dart`, `sales_repository.dart:saveExpenseRecord`, `menu_repository.dart`, `package_repository.dart`, `close_day_transaction.dart`, `admin_screen.dart:2319` | MEDIUM |
| P2 | Mirror money log events (`ADVANCE_RECORDED`, adjustments, service fee, `SALE_CANCELLED`) into the Order report | `money_audit.dart` callers | MEDIUM |
| P2 | Multi-provider split (`TablePaymentSelection` list of bank lines) | `table_payment_service.dart`, payment dialog | LARGE |
| P3 | Labels: Takeaway cancel wording, `+n` rendering, `ORDER` placeholder itemName, retire `preparing`/`served`/`paid`, remove dead `ORDER_DISCOUNT_CHANGED`, drop `SALE_RESTORED_TO_ORDER` duplicate | label switches, `order_status.dart`, `money_audit.dart` | SMALL |

## W. Files changed

- `docs/AUDIT_TAXONOMY_AUDIT.md` (this report). No production code changed.
