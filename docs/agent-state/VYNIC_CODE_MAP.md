# Vynic Code Map

Navigation index only. Start with the smallest relevant section, then inspect
the implementation and nearby tests. Do not treat this as architecture truth.

## Repository Roots

- Flutter POS + Manager: `apps/operations/`
- NestJS/Prisma backend: `apps/backend/`
- Vynic product site + Platform Admin: `apps/platform-web/`
- Custom Vankisi website: `apps/venue-web/`
- Shared generated contracts: `packages/contracts/`
- Architecture and state: `docs/`

## POS / Operations Shell

- Entry and runtime roles: `apps/operations/lib/main.dart`
- Windows POS screens: `apps/operations/lib/apps/windows_pos/screens/`
- Windows POS widgets: `apps/operations/lib/apps/windows_pos/widgets/`
- Shared persistence facade: `apps/operations/lib/core/services/database_service.dart`
- Hive boxes/init: `apps/operations/lib/core/database/database_core.dart`
- Hive migrations: `apps/operations/lib/core/database/hive_migration_service.dart`

## Money / Closing

- Atomic close: `apps/operations/lib/core/database/transactions/close_table_transaction.dart`
- Order cancellation (the one routine): `apps/operations/lib/core/database/transactions/cancel_order_transaction.dart`, proof in `apps/operations/test/unit/cancel_order_transaction_test.dart`
- Audit provenance values: `apps/operations/lib/core/models/audit_source.dart`
- Order-level audit details builder: `apps/operations/lib/core/services/audit/order_audit_details.dart`; creation/transfer proof in `apps/operations/test/unit/order_creation_audit_test.dart`
- Item transfer (`MOVE_ITEMS`, `TRANSFER_CLOSE`): `apps/operations/lib/core/services/pos/order_item_transfer.dart`
- The one Order item diff, shared by Manager upserts and `ORDER_UPDATE`: `apps/operations/lib/core/services/audit/audit_order_diff_service.dart`, proof in `apps/operations/test/unit/manager_item_replacement_audit_test.dart`
- Close payment rendering from details: `apps/operations/lib/core/services/audit/close_event_presentation.dart`, proof in `apps/operations/test/unit/close_event_presentation_test.dart`
- Money mirrors (`RECORD_ADVANCE`, `ADJUST_ORDER`, `VOID_SALE`): `apps/operations/lib/core/services/audit/money_audit.dart`, proof in `apps/operations/test/unit/money_audit_mirror_test.dart`
- Backend audit type normalizer (deploy before POS emits a new type): `apps/backend/src/pos/audit/audit-event-type.ts`
- Close-day transaction: `apps/operations/lib/core/database/transactions/close_day_transaction.dart`
- Closure journal: `apps/operations/lib/core/database/repositories/closure_journal_repository.dart`
- Startup recovery: `apps/operations/lib/core/services/pos/closure_recovery_service.dart`
- Money split: `apps/operations/lib/core/models/closure_money.dart`
- Sales/revenue rules: `apps/operations/lib/core/database/repositories/sales_repository.dart`
- Business-day totals: `apps/operations/lib/core/database/repositories/business_day_repository.dart`
- Governing state: `docs/MONEY_INTEGRITY.md`

## Sales / Reports

- POS sales store and revenue predicate: `apps/operations/lib/core/database/repositories/sales_repository.dart`
- POS Sale identity, bounded selection, exact serialization, ACK state and day completeness declarations: `apps/operations/lib/core/services/sync/sale_ledger_sync_state.dart`; orchestration in `apps/operations/lib/core/services/sync/manager_sync_service.dart`
- Cloud ledger ingestion, exact-money validation, lifecycle revisions and day reconciliation: `apps/backend/src/pos/sync/snapshot/sale-ledger-sync.service.ts`
- Manager exact summary, keyset Sale list/detail, product and staff analytics: `apps/backend/src/mobile/services/mobile-sale-ledger.service.ts`; routes in `apps/backend/src/mobile/mobile.controller.ts`
- Manager ledger UI: `apps/operations/lib/apps/mobile_app/presentation/screens/dashboard_screen.dart`, `apps/operations/lib/apps/mobile_app/presentation/screens/financials_screen.dart`
- Monthly reports: `apps/operations/lib/core/services/pos/monthly_report_service.dart`
- POS admin reports: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_financial_reports_panel.dart`
- Manager backend reports: `apps/backend/src/mobile/services/mobile-reports.service.ts`
- Cloud money reconciliation: `apps/backend/src/pos/sync/snapshot/business-day-sync.service.ts`

## Audit Sync

- POS event order/sequence: `apps/operations/lib/core/models/audit_report.dart`
  (`orderReportEvents`), `apps/operations/lib/core/database/repositories/audit_repository.dart`
  (`_appendedInSequence`), proof in `apps/operations/test/unit/audit_event_sequence_test.dart`
- POS revisions/ack state: `apps/operations/lib/core/services/sync/audit_sync_state.dart`
- POS upload orchestration: `apps/operations/lib/core/services/sync/manager_sync_service.dart`
- Backend ingestion: `apps/backend/src/pos/sync/application/ingest-audit-reports.service.ts`
- Report Order-kind derivation: `apps/backend/src/pos/audit/audit-order-kind.ts`
- Integration proof: `apps/backend/src/pos/sync/application/audit-incremental-sync.integration.spec.ts`
- POS Order-audit UI and constrained render proof: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_audit_log_section.dart`, `apps/operations/test/widget/admin_sections_render_test.dart`
- Contract notes: `docs/AUDIT_SYNC.md`
- Event/action/status taxonomy audit: `docs/AUDIT_TAXONOMY_AUDIT.md`
- Storage/relation integrity investigation: `docs/AUDIT_STORAGE_RELATIONS.md`

## Venue-Wide Audit (non-Order)

- POS writers and action/entity registry: `apps/operations/lib/core/services/audit/global_audit.dart`, `apps/operations/lib/core/services/audit/global_audit_registry.dart`
- Shared feed row and its display rules: `apps/operations/lib/core/models/global_audit_entry.dart`
- Backend entity derivation (also covers rows written before the columns existed): `apps/backend/src/pos/audit/audit-log-entity.ts`
- Manager reader endpoint: `apps/backend/src/mobile/services/mobile-audit-log.service.ts` (`GET /mobile/audit-log`)
- Reader UI: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_activity_log_section.dart` (POS), `apps/operations/lib/apps/mobile_app/presentation/screens/admin_screen/tabs/mobile_admin_activity_tab.dart` (Manager)
- Proofs: `apps/operations/test/unit/global_audit_test.dart`, `apps/backend/src/pos/audit/audit-log-entity.spec.ts`, `apps/backend/src/mobile/services/mobile-audit-log.integration.spec.ts`

## Staff Sync

- POS credential acknowledgments/selection: `apps/operations/lib/core/services/sync/staff_credential_sync_state.dart`
- POS snapshot assembly: `apps/operations/lib/core/services/sync/manager_sync_service.dart`
- Backend mirror/reconcile: `apps/backend/src/pos/sync/snapshot/staff-sync.service.ts`
- Plain-PIN store: `apps/backend/src/auth/staff-pin-vault.service.ts`
- Manager-side staff CRUD: `apps/backend/src/mobile/services/mobile-users.service.ts`
- Proofs: `apps/operations/test/unit/staff_credential_sync_test.dart`,
  `apps/backend/src/pos/sync/snapshot/staff-sync.service.spec.ts`,
  `apps/backend/src/auth/staff-pin-vault.service.spec.ts`,
  `apps/backend/src/mobile/services/mobile-users.service.spec.ts`

## Edge Transport — Backend

- Module/routes/guard: `apps/backend/src/edge/`
- Queue lifecycle: `apps/backend/src/edge/edge-command.service.ts`
- Cloud operation dispatcher: `apps/backend/src/pos/pos-command-dispatcher.service.ts`
- Frozen fallback: `apps/backend/src/pos/pos-callback.client.ts`, `apps/backend/src/pos/pos-outbox.service.ts`
- Integration tests: `apps/backend/src/edge/edge-transport.integration.spec.ts`, `apps/backend/src/pos/pos-command-dispatcher.integration.spec.ts`
- Current migration record: `docs/EDGE_COMMAND_MIGRATION.md`

## Edge Transport — POS

- Poll/claim/ack loop: `apps/operations/lib/core/services/edge/edge_transport_service.dart`
- HTTP client: `apps/operations/lib/core/services/edge/edge_transport_client.dart`
- Durable execution journal: `apps/operations/lib/core/services/edge/edge_command_journal.dart`
- Handler registry: `apps/operations/lib/core/services/edge/pos_edge_command_handlers.dart`
- Shared operation body: `apps/operations/lib/core/services/pos/pos_command_applier.dart`
- Legacy listener adapter: `apps/operations/lib/core/services/sync/pos_ingest_server.dart`

## Device Enrollment

- Backend service/controller: `apps/backend/src/edge/device-enrollment.service.ts`, `apps/backend/src/edge/device-enrollment.controller.ts`
- Platform API/UI: `apps/platform-web/src/platform/api.ts`, `apps/platform-web/src/platform/pages/venue/VenueEnrollmentPanel.tsx`
- POS client/flow: `apps/operations/lib/core/services/edge/edge_enrollment_client.dart`, `apps/operations/lib/core/services/edge/pos_enrollment_service.dart`
- POS UI: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_pos_enrollment_panel.dart`
- End-to-end reference: `docs/POS_ENROLLMENT.md`

## Manager App

- Flutter shell/screens: `apps/operations/lib/apps/mobile_app/`
- Shared Manager API client: `apps/operations/lib/core/services/manager_app/mobile_api_service.dart`
- Backend controller/services: `apps/backend/src/mobile/`
- Auth and tenant resolution: `apps/backend/src/auth/auth.service.ts`, `apps/backend/src/auth/manager-tenant.service.ts`
- Tenant rules: `docs/MANAGER_TENANT_AUTH.md`

## Orders / Walk-In / Takeaway / Packages

- Order model and every creation path: `apps/operations/lib/core/models/order.dart`, `apps/operations/lib/core/database/repositories/order_repository.dart`
  (`createOrder`, `createTakeAwayOrder`, `upsertMobileTakeawayOrder`,
  `upsertMobileDineInOrder`, `createOrderForPackage`)
- Order mode is not a field: takeaway is `floor == 'takeaway'` with a `TA-<id>` table
- Order status enum, and the one rule for a remote `ORDER_STATUS_UPDATE`: `apps/operations/lib/core/models/order_status.dart` (`OrderStatus`, `RemoteOrderStatusRule`), applied in `apps/operations/lib/core/services/pos/pos_command_applier.dart` (`updateOrderStatus`), proof in `apps/operations/test/unit/remote_order_status_test.dart`
- Package model/repository/admin: `apps/operations/lib/core/models/package.dart`, `apps/operations/lib/core/database/repositories/package_repository.dart`, `apps/operations/lib/apps/windows_pos/widgets/admin/admin_packages_section.dart`
- Stable Menu references on frozen Order/Package lines: `OrderItem.menuItemId` / `variantId`, `PackageItem.menuItemId` / `variantId`; transfer lives in `apps/operations/lib/core/services/pos/order_item_transfer.dart`, wire ingestion in `apps/operations/lib/core/services/pos/pos_command_applier.dart`, and regression proofs in `apps/operations/test/unit/menu_line_identity_test.dart`, `backup_completeness_test.dart`, `reservation_audit_test.dart`, `takeaway_order_source_test.dart`, and `order_item_transfer_test.dart`
- Takeaway detection, tickets and the home panel's source: `apps/operations/lib/core/models/takeaway_order.dart`, `apps/operations/lib/apps/windows_pos/widgets/home/home_take_away_section.dart`, proof in `apps/operations/test/unit/takeaway_order_source_test.dart`
- Booking-vs-bookkeeping predicates: `apps/operations/lib/core/utils/reservation_table_availability.dart`, `apps/operations/lib/core/utils/home_reservations_helper.dart`, `apps/backend/src/website/reservation/reservation-table-codes.ts`

## Menu

- POS model and stable node identity: `apps/operations/lib/core/models/menu_item_db.dart` (`MenuCategoryDB.id`, `MenuSubcategoryDB.id`, `MenuItemDB.id`, `MenuVariantDB.id`)
- CRUD, stable-ID audit and one-time rollout: `apps/operations/lib/core/database/repositories/menu_repository.dart` (`ensureStableMenuIds`, called from Hive migration v8 and after backup restore)
- Cloud mirror and authoritative reconciliation: `apps/backend/src/pos/sync/snapshot/menu-sync.service.ts` (stable identity first; legacy adoption only for unclaimed rows; identity-version gate; transactional child-first cleanup of explicitly POS-owned rows)
- Manager read: `apps/backend/src/mobile/services/mobile-menu.service.ts`; website read: `apps/backend/src/website/menu/menu.service.ts` (publishes the Cloud `MenuItem.id`, not the POS id)
- Only writer is the POS Admin: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_menu_section.dart`
- Proofs: `apps/operations/test/unit/menu_item_identity_test.dart`, `apps/backend/src/pos/sync/snapshot/menu-sync.service.spec.ts`, `apps/backend/src/pos/sync/snapshot/menu-sync.integration.spec.ts`

## Inventory

- Boundary and authority: `docs/INVENTORY_STEP1.md` (catalog), `docs/INVENTORY_STEP2.md` (receiving and the quantity ledger)
- Module wiring: `apps/backend/src/inventory/inventory.module.ts`, imported by `app.module.ts` and `edge-transport.module.ts`
- Cloud schema: `apps/backend/prisma/schema.prisma` (`StockItem`, `Supplier`, `StockItemPurchaseUnit`, `Receiving`, `ReceivingLine`, `StockMovement`); migrations `20260908120000_inventory_step1_core/`, `20260909120000_inventory_step2_receiving/`
- Catalog CRUD, derived current stock (`currentStock`), packaging and item detail: `apps/backend/src/inventory/inventory.service.ts`
- Receiving lifecycle, posting/cancellation transactions and history reads: `apps/backend/src/inventory/receiving.service.ts`
- Units and exact decimal arithmetic: `apps/backend/src/inventory/inventory-unit.ts`, `apps/backend/src/inventory/inventory-quantity.ts` (`resolveBaseQuantity`, `lineMoney`)
- Shared venue-wide audit writer/actions: `apps/backend/src/inventory/inventory-audit.ts`
- Manager routes: `apps/backend/src/mobile/mobile.controller.ts` (`/mobile/inventory/*`, including `receivings`, `receivings/:id/post`, `receivings/:id/cancel`)
- Device -> Venue complete projection (catalog v2): `GET /edge/inventory/catalog` in `apps/backend/src/edge/edge-transport.controller.ts`
- POS offline model/store/pull: `apps/operations/lib/core/models/inventory.dart`, `apps/operations/lib/core/database/repositories/inventory_repository.dart`, `apps/operations/lib/core/services/edge/inventory_projection_sync_service.dart`
- Manager Receiving read models: `apps/operations/lib/core/models/receiving.dart`; API client in `apps/operations/lib/core/services/manager_app/mobile_api_service.dart`
- Manager UI: `apps/operations/lib/apps/mobile_app/presentation/screens/admin_screen/tabs/mobile_admin_inventory_tab.dart` (catalog), `.../tabs/mobile_admin_receiving.dart` (Receiving list/detail/editor, Stock Item detail)
- Proofs: `apps/backend/src/inventory/*.spec.ts` (`receiving.integration.spec.ts` covers lifecycle, derived stock, idempotency, concurrency, tenancy and audit), `apps/backend/src/edge/edge-transport.integration.spec.ts`, `apps/operations/test/unit/inventory_*_test.dart`, `apps/operations/test/widget/manager_inventory_test.dart`, `apps/operations/test/widget/manager_receiving_test.dart`

## Reservations

- POS model/repository/transaction: `apps/operations/lib/core/models/reservation.dart`, `apps/operations/lib/core/database/repositories/reservation_repository.dart`, `apps/operations/lib/core/database/transactions/activate_reservation_transaction.dart`
- Reservation timeline registry and writer: `apps/operations/lib/core/services/audit/reservation_audit.dart`, proof in `apps/operations/test/unit/reservation_audit_test.dart`
- Reservation id generation (uuid, collision-safe): `apps/operations/lib/core/database/repositories/reservation_repository.dart` (`createReservation`), proof in `apps/operations/test/unit/reservation_id_uniqueness_test.dart`
- Booking-vs-bookkeeping rule and Cloud projection: `apps/operations/lib/core/models/reservation_classification.dart`, proof in `apps/operations/test/unit/reservation_projection_test.dart`
- Manager backend: `apps/backend/src/mobile/services/mobile-reservations.service.ts`
- Website booking: `apps/backend/src/website/reservation/`
- Cloud POS mirror: `apps/backend/src/pos/pos-reservation-mirror.service.ts`, `apps/backend/src/pos/sync/snapshot/reservation-sync.service.ts`
- Public UI route: `apps/venue-web/src/routes/reservation.ts`

## Printing

- Printer orchestration: `apps/operations/lib/core/services/printing/printer_service.dart`
- Queue/transport: `apps/operations/lib/core/services/printing/print_queue.dart`, `apps/operations/lib/core/services/printing/printer_transport.dart`
- Renderers: `apps/operations/lib/core/services/printing/`
- Admin configuration: `apps/operations/lib/apps/windows_pos/widgets/admin/printers/`
- Remote print handling: `apps/operations/lib/core/services/edge/pos_edge_command_handlers.dart`

## Platform Control Plane

- Backend module/controllers/services: `apps/backend/src/platform/`
- Principal/auth: `apps/backend/src/platform/platform-auth.service.ts`, `apps/backend/src/platform/platform-auth.guard.ts`
- Entitlements: `apps/backend/src/entitlements/venue-entitlements.service.ts`
- API reference: `docs/PLATFORM_CONTROL_PLANE_API.md`

## Platform Admin UI

- Route shell: `apps/platform-web/src/App.tsx`, `apps/platform-web/src/platform/Shell.tsx`
- Auth/session/API: `apps/platform-web/src/platform/auth.tsx`, `apps/platform-web/src/platform/session.ts`, `apps/platform-web/src/platform/api.ts`
- Pages: `apps/platform-web/src/platform/pages/`
- Integration tests: `apps/platform-web/src/test/`

## Venue Website

- App/pages: `apps/venue-web/src/App.tsx`, `apps/venue-web/src/pages/`
- API client: `apps/venue-web/src/services/api.ts`
- Backend website module: `apps/backend/src/website/`
- Host resolution: `apps/backend/src/website/tenancy/`
- Current tenancy reference: `docs/PUBLIC_TENANCY.md`

## Prisma / Database

- Schema: `apps/backend/prisma/schema.prisma`
- Migrations: `apps/backend/prisma/migrations/`
- Complete Menu/line identity migration: `apps/backend/prisma/migrations/20260906140000_complete_menu_identity/migration.sql`
- Cloud Sale Ledger migration: `apps/backend/prisma/migrations/20260907120000_cloud_sale_ledger/migration.sql`
- Prisma module/service: `apps/backend/src/shared/prisma/`, `apps/backend/src/prisma.service.ts`
- Backend application wiring: `apps/backend/src/app.module.ts`

## Shared Contracts

- Canonical schemas: `packages/contracts/schema/`
- Generator: `packages/contracts/scripts/generate.mjs`
- Generated TypeScript/Dart: `packages/contracts/generated/`
- Backend re-export: `apps/backend/src/shared/contracts/edge-command.ts`
- Flutter re-export: `apps/operations/lib/core/contracts/edge_command.dart`

## Tests

- Backend unit/integration specs live beside source under `apps/backend/src/`.
- Flutter unit tests: `apps/operations/test/unit/`
- Flutter widget tests: `apps/operations/test/widget/`
- Platform Web tests: `apps/platform-web/src/test/`
- Contract check: `packages/contracts/scripts/generate.mjs --check`

## Maintenance

Update only when a subsystem moves or a high-value entry point appears or is
removed. Do not turn this into an exhaustive file list.
