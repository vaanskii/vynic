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
| `WebsiteUser` | UUID; email/phone | Customer auth | Global/shared | No | Customer identity is not POS operational ownership. Re-confirmed in 4B2B. |
| `WebsiteTable` | integer; website table number | Public booking | Deferred | No | Host/domain Venue resolution and booking tenancy are explicitly later. **Venue-owned since 4B2B.** |
| `WebsiteReservation` | UUID; POS reservation bridge ID | Public booking/payment/POS bridge | Deferred | No | Reservation semantics are not redesigned in 4B1. **Venue-owned since 4B2B.** |
| `WebsiteReservationTable` | integer; reservation + table | Public booking | Deferred child | No | Inherits from deferred website booking records. Still a child in 4B2B. |

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
- **Step 4B2B — complete.** A registered hostname now resolves a Venue authoritatively, public menu/table/booking reads are scoped to it, `WebsiteTable` and `WebsiteReservation` are Venue-owned, and `WEBSITE` is enforced on the public website product API. The website half of `LEGACY_MANAGER_TENANT` is gone. See [PUBLIC_TENANCY.md](PUBLIC_TENANCY.md).
- **Step 6A — complete.** Cloud ↔ Edge transport foundation: a persistent, Device-routed Cloud → Edge work queue the Edge pulls with its Device credential, separate from Edge → Cloud snapshot sync, which is unchanged. The legacy LAN callback path is preserved and classified transitional. See [CLOUD_EDGE_TRANSPORT.md](CLOUD_EDGE_TRANSPORT.md).
- **Step 6B — complete.** The POS now claims, executes, journals and acknowledges Cloud work with its own Device credential, over generated Dart contracts, without ever depending on Cloud to operate. `NOOP` only; the legacy LAN callback path still carries every real command. See [CLOUD_EDGE_TRANSPORT.md](CLOUD_EDGE_TRANSPORT.md).
- **Step 6C — optional, and not a prerequisite.** Migrating the 18 legacy POS callback commands onto the Edge queue. It gates a *Cloud deployment*, not the control plane, so it can be staged behind 7A.
- **Step 7A — next.** Platform Admin identity and control plane, which four phases have now stopped at.

Then: Manager App Cloud networking, and the rest of the control plane — see [PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md) for why platform-admin identity gates the Backoffice, custom roles, and per-Venue payment credentials ([PAYMENT_INTEGRATIONS.md](PAYMENT_INTEGRATIONS.md)).

Still owned by later phases: venue-discriminating Manager login, the generic SaaS website frontend and the custom website runtime, domain-management UI, Zone, the reservation race / `TableHold`, cloud deployment, Vynic SaaS billing, onboarding and device activation, signed offline commercial licences, retiring the legacy `POS_SYNC_API_KEY`, and the previously recorded sync-correctness findings.
