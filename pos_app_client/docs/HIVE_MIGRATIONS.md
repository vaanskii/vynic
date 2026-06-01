# Hive Migration Guide

This document describes the new Hive migration workflow that protects existing POS installations when the local schema evolves.

## Metadata Tracking

- All schema metadata lives in the `meta` box under the `db_version` key.
- Versions start at `1`; the current build targets version `2`.
- The key `last_migration_timestamp` records when the most recent upgrade finished.

## Startup Flow

- `DatabaseService.init()` opens Hive, registers adapters, opens every box, and builds a `HiveMigrationContext`.
- `HiveMigrationService.runPendingMigrations()` reads the stored version and executes the next migration (for example `migrateV1toV2`) exactly once.
- After migration, defaults are seeded (users, tables, menu, settings) using the new schema so fresh installs still work.
- `DatabaseService.dbVersion` exposes the applied version for logging or troubleshooting.

## Restoring JSON Backups

- `DatabaseService.createDataBackup()` still produces the JSON archive under `Documents/Vpos_Data/backups`.
- To restore, call `DatabaseService.restoreDataBackupFromFile(File backup)`; it auto-creates a safety backup (unless disabled) and repopulates every Hive box.
- Restores accept either the generated file or the raw JSON string via `restoreDataBackupFromJson`.
- The procedure rewrites `meta/db_version`, rehydrates orders/reservations/menu data, and recalculates daily sales totals, so migrations continue from the restored version.

## Adding New Migrations (V3, V4, ...)

1. Implement a `migrateV{n}toV{n+1}` function inside `HiveMigrationService` using the context to read/write any box you need.
2. Update `targetVersion` and extend `runPendingMigrations` with a loop (or chained `if` blocks) so older devices run each missing migration in order.
3. Keep migrations idempotent—run them against sample backups with varied data to ensure they can retry safely.
4. Add unit/integration tests that seed legacy fixtures, execute `DatabaseService.init()`, and assert the upgraded shape.
5. Document the change in this file so future contributors know why the migration exists.

## Updating Hive TypeAdapters Safely

- **Never reuse or reorder `@HiveField` indices.** Append new fields with the next unused index.
- **Choose nullable types for new data when possible.** This prevents adapters from throwing while you migrate persisted objects.
- **Provide constructor defaults that match the migration.** Older records without the field will use these defaults when deserialized.
- **Guard reads in migrations.** Check for `null` or legacy values before writing the upgraded structure back.
- **Bump migrations in lock-step.** Whenever a TypeAdapter changes meaningfully, add a migration that normalizes existing box contents before your feature relies on them.

Following these guidelines keeps on-device data consistent while the POS evolves.
