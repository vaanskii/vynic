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
- Close-day transaction: `apps/operations/lib/core/database/transactions/close_day_transaction.dart`
- Closure journal: `apps/operations/lib/core/database/repositories/closure_journal_repository.dart`
- Startup recovery: `apps/operations/lib/core/services/pos/closure_recovery_service.dart`
- Money split: `apps/operations/lib/core/models/closure_money.dart`
- Sales/revenue rules: `apps/operations/lib/core/database/repositories/sales_repository.dart`
- Business-day totals: `apps/operations/lib/core/database/repositories/business_day_repository.dart`
- Governing state: `docs/MONEY_INTEGRITY.md`

## Sales / Reports

- POS sales store and revenue predicate: `apps/operations/lib/core/database/repositories/sales_repository.dart`
- Monthly reports: `apps/operations/lib/core/services/pos/monthly_report_service.dart`
- POS admin reports: `apps/operations/lib/apps/windows_pos/widgets/admin/admin_financial_reports_panel.dart`
- Manager backend reports: `apps/backend/src/mobile/services/mobile-reports.service.ts`
- Cloud money reconciliation: `apps/backend/src/pos/sync/snapshot/business-day-sync.service.ts`

## Audit Sync

- POS revisions/ack state: `apps/operations/lib/core/services/sync/audit_sync_state.dart`
- POS upload orchestration: `apps/operations/lib/core/services/sync/manager_sync_service.dart`
- Backend ingestion: `apps/backend/src/pos/sync/application/ingest-audit-reports.service.ts`
- Integration proof: `apps/backend/src/pos/sync/application/audit-incremental-sync.integration.spec.ts`
- Contract notes: `docs/AUDIT_SYNC.md`

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

## Reservations

- POS model/repository/transaction: `apps/operations/lib/core/models/reservation.dart`, `apps/operations/lib/core/database/repositories/reservation_repository.dart`, `apps/operations/lib/core/database/transactions/activate_reservation_transaction.dart`
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
