-- Step 4B1: scope POS-owned operational roots to the authenticated Venue.
-- The migration is staged in-place: nullable columns, deterministic backfill,
-- then required ownership and Venue-local uniqueness.

-- Stage 1: nullable ownership and foreign-key columns.
ALTER TABLE "pos"."Table" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."Order" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."MenuCategory" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."MenuItem" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."Expense" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."Staff" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."AuditReport" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."AuditEventLog" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."DailySnapshot" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."Setting" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."PosCallbackOutbox" ADD COLUMN "venueId" TEXT;

-- Stage 2: every pre-tenancy operational row belongs to the existing
-- deterministic bootstrap Venue introduced by Step 4A.
UPDATE "pos"."Table" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."Order" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."MenuCategory" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."MenuItem" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."Expense" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."Staff" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."AuditReport" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."AuditEventLog" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."DailySnapshot" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."Setting" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;
UPDATE "pos"."PosCallbackOutbox" SET "venueId" = '00000000-0000-4000-8000-000000000002' WHERE "venueId" IS NULL;

-- Stage 3: ownership is required after the backfill.
ALTER TABLE "pos"."Table" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."Order" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."MenuCategory" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."MenuItem" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."Expense" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."Staff" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."AuditReport" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."AuditEventLog" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."DailySnapshot" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."Setting" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."PosCallbackOutbox" ALTER COLUMN "venueId" SET NOT NULL;

-- Replace restaurant-local global uniqueness with Venue-scoped uniqueness.
DROP INDEX "pos"."Table_tableNumber_floor_key";
DROP INDEX "pos"."Order_posOrderId_key";
DROP INDEX "pos"."MenuCategory_slug_key";
DROP INDEX "pos"."Staff_username_key";
DROP INDEX "pos"."AuditReport_reportId_key";
DROP INDEX "pos"."DailySnapshot_date_key";
ALTER TABLE "pos"."Setting" DROP CONSTRAINT "Setting_pkey";

CREATE UNIQUE INDEX "Table_venueId_tableNumber_floor_key" ON "pos"."Table"("venueId", "tableNumber", "floor");
CREATE UNIQUE INDEX "Order_venueId_posOrderId_key" ON "pos"."Order"("venueId", "posOrderId");
CREATE UNIQUE INDEX "MenuCategory_venueId_slug_key" ON "pos"."MenuCategory"("venueId", "slug");
CREATE UNIQUE INDEX "Staff_venueId_username_key" ON "pos"."Staff"("venueId", "username");
CREATE UNIQUE INDEX "AuditReport_venueId_reportId_key" ON "pos"."AuditReport"("venueId", "reportId");
CREATE UNIQUE INDEX "DailySnapshot_venueId_date_key" ON "pos"."DailySnapshot"("venueId", "date");
ALTER TABLE "pos"."Setting" ADD CONSTRAINT "Setting_pkey" PRIMARY KEY ("venueId", "key");

-- Query-path indexes.
CREATE INDEX "Table_venueId_idx" ON "pos"."Table"("venueId");
CREATE INDEX "Order_venueId_businessDate_idx" ON "pos"."Order"("venueId", "businessDate");
CREATE INDEX "MenuCategory_venueId_idx" ON "pos"."MenuCategory"("venueId");
CREATE INDEX "MenuItem_venueId_idx" ON "pos"."MenuItem"("venueId");
CREATE INDEX "Expense_venueId_createdAt_idx" ON "pos"."Expense"("venueId", "createdAt");
CREATE INDEX "Staff_venueId_idx" ON "pos"."Staff"("venueId");
CREATE INDEX "AuditReport_venueId_idx" ON "pos"."AuditReport"("venueId");
CREATE INDEX "AuditEventLog_venueId_createdAt_idx" ON "pos"."AuditEventLog"("venueId", "createdAt");
CREATE INDEX "DailySnapshot_venueId_idx" ON "pos"."DailySnapshot"("venueId");
CREATE INDEX "Setting_venueId_idx" ON "pos"."Setting"("venueId");
CREATE INDEX "PosCallbackOutbox_venueId_status_nextAttemptAt_idx" ON "pos"."PosCallbackOutbox"("venueId", "status", "nextAttemptAt");

-- Ownership FKs are restrictive: deleting a Venue with operational history is
-- rejected rather than cascading restaurant data away.
ALTER TABLE "pos"."Table" ADD CONSTRAINT "Table_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."Order" ADD CONSTRAINT "Order_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."MenuCategory" ADD CONSTRAINT "MenuCategory_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."MenuItem" ADD CONSTRAINT "MenuItem_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."Expense" ADD CONSTRAINT "Expense_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."Staff" ADD CONSTRAINT "Staff_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."AuditReport" ADD CONSTRAINT "AuditReport_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."AuditEventLog" ADD CONSTRAINT "AuditEventLog_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."DailySnapshot" ADD CONSTRAINT "DailySnapshot_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."Setting" ADD CONSTRAINT "Setting_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."PosCallbackOutbox" ADD CONSTRAINT "PosCallbackOutbox_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
