# POS operational tenant scoping

Step 4B1 scopes the backend's POS-owned operational mirror to the Venue established by authenticated Device identity. It does not make booking, the customer website, or Manager authentication multi-tenant.

## Authority flow

```text
POS credential
  -> PosSyncGuard
  -> Device.venueId (or the legacy bootstrap Venue)
  -> PosAuthContext
  -> focused sync services
  -> every operational read and write includes venueId
```

Payload, query, and arbitrary header values are not tenant authority. Canonical Table UUIDs and legacy `floor`/`tableNumber` aliases are unchanged.

## Prisma ownership inventory

| Model | Current identity / uniqueness | Principal query paths | Classification | Direct `venueId` in 4B1 | Reason |
| --- | --- | --- | --- | --- | --- |
| `Organization` | UUID | Device/Venue administration | Control plane | No | Top-level owner. |
| `Venue` | UUID | Authentication tenant resolution | Control plane | No | Tenant boundary itself. |
| `Device` | UUID; global installation UUID | Device credential issue/verify | Control plane | Existing | Authenticated POS installation belongs directly to a Venue. |
| `Table` | canonical UUID; legacy floor/number alias | POS table sync, order linking, dashboard/diff | Tenant root | Yes | Independently read and updated; alias uniqueness is Venue-local. |
| `Order` | UUID; POS local integer | POS sync/reconcile, Manager order/report APIs | Tenant root | Yes | Aggregate root; local order numbers may overlap by Venue. |
| `OrderItem` | UUID; required `Order` | Nested order writes and report joins | Tenant child | No | Ownership is required and cascades through `Order`. |
| `MenuCategory` | UUID; slug | POS menu sync, Manager menu reads | Tenant root | Yes | Top of the synced catalog; slug is Venue-local. |
| `MenuSubcategory` | UUID; slug within category | POS menu sync | Tenant child | No | Required category relation supplies ownership. |
| `MenuItem` | UUID; name lookup within optional parent | POS menu sync, reports/bootstrap reads | Tenant root | Yes | Both parent relations are nullable and items are queried independently. |
| `MenuItemVariant` | UUID; required menu item | POS menu sync | Tenant child | No | Required menu-item relation supplies ownership. |
| `Expense` | UUID | POS snapshot write, Manager reports/mutations | Tenant root | Yes | Independently written and queried operational record. |
| `Staff` | UUID; username | POS reconcile, PIN login, Manager users | Tenant root | Yes | Independently reconciled; username is Venue-local. |
| `AuditReport` | UUID; POS report ID | POS audit sync, Manager reports/orders | Tenant root | Yes | Full-sync reconciliation must be isolated; report ID is Venue-local. |
| `AuditEvent` | UUID; required audit report | Audit replacement and Manager reads | Tenant child | No | Required report relation supplies ownership. |
| `AuditEventLog` | POS UUID | POS append-only audit-log sync | Tenant root | Yes | Direct POS ingestion root with no parent relation. |
| `DailySnapshot` | UUID; business date | No active production query found | Tenant root | Yes | Historical operational aggregate; date is Venue-local even though the model is currently dormant. |
| `Setting` | key | POS business-day/reporting/connection state and legacy Manager reads | Tenant root | Yes | Keys describe one restaurant; identity becomes Venue + key. |
| `PosCallbackOutbox` | UUID; optional local order reference | POS order/staff conflict checks and callback worker | Tenant root | Yes | Sync must not observe another Venue's pending changes. Existing bootstrap-only routing remains transitional. |
| `QuickOrderDraft` | UUID; draft UUID | Manager quick-order APIs | Deferred | No | Manager-owned workflow awaits authenticated Manager tenant resolution. |
| `QuickOrderDraftItem` | UUID; required draft | Manager quick-order APIs | Deferred child | No | Inherits from the deferred draft root. |
| `ManagerNotification` | UUID | Realtime notification persistence | Deferred | No | Manager tenancy/authentication and delivery routing are later work. |
| `ManagerNotificationDelivery` | UUID; notification + username | Manager notification reads | Deferred child | No | Belongs to the deferred notification root. |
| `PushDevice` | UUID; global FCM token | Manager push registration | Deferred | No | Needs Manager identity and Venue-aware notification routing. |
| `WebsiteUser` | UUID; email/phone | Customer auth | Global/shared | No | Customer identity is not POS operational ownership. |
| `WebsiteTable` | integer; website table number | Public booking | Deferred | No | Host/domain Venue resolution and booking tenancy are explicitly later. |
| `WebsiteReservation` | UUID; POS reservation bridge ID | Public booking/payment/POS bridge | Deferred | No | Reservation semantics are not redesigned in 4B1. |
| `WebsiteReservationTable` | integer; reservation + table | Public booking | Deferred child | No | Inherits from deferred website booking records. |

## Scoped uniqueness changes

- `Table(tableNumber, floor)` becomes `Table(venueId, tableNumber, floor)`.
- `Order(posOrderId)` becomes `Order(venueId, posOrderId)`.
- `MenuCategory(slug)` becomes `MenuCategory(venueId, slug)`.
- `Staff(username)` becomes `Staff(venueId, username)`.
- `AuditReport(reportId)` becomes `AuditReport(venueId, reportId)`.
- `DailySnapshot(date)` becomes `DailySnapshot(venueId, date)`.
- `Setting(key)` becomes the composite primary key `Setting(venueId, key)`.

Global UUID primary keys remain global. `Order.closureId` also remains globally unique because it is an opaque UUID idempotency token rather than a human/local sequence.

## Compatibility and remaining gaps

All existing rows are backfilled to the deterministic Step 4A bootstrap Venue. The legacy shared POS key resolves only to that Venue. Until Manager Cloud authentication exists, legacy Manager/mobile API paths resolve server-side to the same bootstrap Venue and never accept a client-provided Venue.

## Follow-on steps

- **Step 4B2A — complete.** Manager requests now resolve an authoritative Venue from the authenticated Staff identity, Manager APIs are scoped to it, and `MANAGER_APP` is enforced on the Manager product API. See [MANAGER_TENANT_AUTH.md](MANAGER_TENANT_AUTH.md).
- **Step 4B2B — next.** Public website tenancy: Host/domain → Venue resolution, booking and reservation tenant scoping, and retiring the website half of `LEGACY_MANAGER_TENANT`. See [CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md) and [FUTURE_SAAS_WEBSITE.md](FUTURE_SAAS_WEBSITE.md).

Still owned by later phases: Manager Cloud transport and networking, venue-discriminating Manager login, Zone, per-Venue callback routing and Cloud-to-Edge work queues, cloud deployment, billing/subscriptions, onboarding and device activation, and the previously recorded sync-correctness findings.
